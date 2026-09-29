#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""db_maint —— 数据库保养 · 先量后动（工单 §5 第 6 条；设计《数据保养（向量紧凑＋队列清理）》）

**默认只读 dry-run**：不改一个字节，只报"能省多少"＋用**真向量**实测 float16 精度。
迁移实施（写库）是另一步、要家主点窗口；本脚本现在**只量**。

    python3 tools/db_maint.py            # 量（默认）
    python3 tools/db_maint.py --samples 400   # 抽样条数（精度实测用）

量的四项（对应设计稿 §三）：
  ① 向量紧凑：vec 现以**文本**存（json 数组）→ 换 float16 BLOB 能省多少；顺带量"死模型"残留。
  ② 编解码可行性：纯标准库 struct('e') 打包/解包，真向量实测最大误差与余弦相似度、
     以及 top-1 近邻是否一致（float16 精度容差内应全同）。
  ③ embed_queue 残渣：done 超 7 天的行。
  ④ 小表轮转：obs_daily 超 180 天、idem_cache 超 7 天的行。

只读纪律：全程 SELECT；不开事务写、不建表、不 VACUUM。fail-open：某项量不动就打"（量不动）"。
"""
import argparse
import json
import math
import os
import sqlite3
import struct
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 库路径：默认私仓那份；`ZANJIA_DB` 可指到别处（沙盘套件/迁移演练用——免得套件读生产库）
DB_PATH = os.environ.get("ZANJIA_DB") or os.path.join(BASE_DIR, "咱家的家.db")

# 轮转天数（与设计稿 §五·待拍一致；改这里不改逻辑）
OBS_KEEP_DAYS = 180
IDEM_KEEP_DAYS = 7
QUEUE_KEEP_DAYS = 7
LIVE_MODEL = "harrier-oss-v1-0.6b"      # 现役嵌入模型（其它视为死账候选）


def _mb(n):
    return n / 1024.0 / 1024.0


def _f16_size(dim):
    """float16 BLOB 每行字节数：dim × 2（不含 SQLite 行开销，约 +30 字节/行）。"""
    return int(dim) * 2


def sec_db_size(con):
    st = os.path.getsize(DB_PATH)
    print("=" * 78)
    print("一、家底（只读）")
    print(f"  库文件：{_mb(st):.1f} MB（{st:,} 字节）")
    print("  dbstat 精确分表（top 12，按字节）：")
    try:
        rows = con.execute(
            "SELECT name, sum(pgsize) AS b FROM dbstat GROUP BY name ORDER BY b DESC LIMIT 12"
        ).fetchall()
        for name, b in rows:
            print(f"    {name:24} {_mb(b):7.2f} MB")
        tot_dbstat = con.execute("SELECT sum(pgsize) FROM dbstat").fetchone()[0]
        print(f"    {'— 合计（dbstat）':24} {_mb(tot_dbstat):7.2f} MB")
    except Exception as e:
        print(f"    （dbstat 量不动：{e}）")
    return st


def sec_vectors(con, samples):
    """① 向量紧凑能省多少（按真实 dim 逐行算，不拍脑袋）。"""
    print("=" * 78)
    print("二、向量紧凑（vec：文本 → float16 BLOB）")
    rows = con.execute(
        "SELECT model, kind, count(*), min(dim), max(dim), sum(length(vec)), "
        "sum(length(cast(vec as blob))) FROM vectors GROUP BY model, kind"
    ).fetchall()
    if not rows:
        print("  （vectors 空表：没得量）")
        return 0, 0
    tot_rows = tot_text = tot_f16 = 0
    print(f"  {'model':22} {'kind':8} {'行数':>6} {'dim':>5} {'文本 MB':>9} {'f16 MB':>8} {'省%':>6}")
    dead_rows = dead_text = dead_f16 = 0
    for model, kind, n, dmin, dmax, txt, blob in rows:
        d = int(dmax or dmin or 0)
        f16 = _f16_size(d) * int(n)
        txt = int(txt or 0)
        save = (1 - (f16 / txt)) * 100 if txt else 0
        mark = "" if model == LIVE_MODEL else "  ← 死账候选"
        print(f"  {model:22} {kind:8} {n:6} {d:5} {_mb(txt):9.2f} {_mb(f16):8.2f} {save:5.0f}%{mark}")
        tot_rows += int(n)
        tot_text += txt
        tot_f16 += f16
        if model != LIVE_MODEL:
            dead_rows += int(n)
            dead_text += txt
            dead_f16 += f16
    print("  " + "-" * 74)
    print(f"  合计：{tot_rows} 行 · 文本 {_mb(tot_text):.1f} MB → f16 {_mb(tot_f16):.2f} MB"
          f"　**省 {_mb(tot_text - tot_f16):.1f} MB（{100 * (1 - tot_f16 / max(tot_text, 1)):.1f}%）**")
    if dead_rows:
        print(f"  其中死模型残留（≠{LIVE_MODEL}）：{dead_rows} 行 / 文本 {_mb(dead_text):.2f} MB"
              f"（f16 后仅 {_mb(dead_f16):.2f} MB）——整批摘掉可再省 {_mb(dead_text):.2f} MB")
    sec_precision(con, samples)
    return tot_text, tot_f16


def sec_precision(con, samples):
    """② 真向量实测：float16 往返误差 / 余弦 / top-1 近邻是否一致（纯标准库）。"""
    print("  ── 精度实测（真向量，不是随机数）──")
    try:
        rows = con.execute(
            "SELECT id, dim, vec FROM vectors WHERE kind IN ('chunk','oldhome') "
            "ORDER BY id LIMIT ?", (int(samples),)).fetchall()
        if len(rows) < 10:
            print("    （样本太少，跳过）")
            return
        vecs = []
        for _id, dim, txt in rows:
            try:
                v = json.loads(txt)
            except Exception:
                continue
            if len(v) != int(dim):
                continue
            vecs.append(v)
        if len(vecs) < 10:
            print("    （能解析的样本太少，跳过）")
            return
        max_abs = 0.0
        min_cos = 1.0
        for v in vecs:
            q = _f16_roundtrip(v)
            for i in range(len(v)):
                d = abs(v[i] - q[i])
                if d > max_abs:
                    max_abs = d
            c = _cos(v, q)
            if c < min_cos:
                min_cos = c
        print(f"    float16 往返：{len(vecs)} 条 × dim{len(vecs[0])}")
        print(f"    最大绝对误差 max|Δ| = {max_abs:.3e}（float16 相对精度 ~2^-11 ≈ 4.9e-4）")
        print(f"    最小余弦相似度 min cos = {min_cos:.8f}")
        # top-1 近邻一致：拿前 5 条当查询，在样本池里找最近邻（float32 vs float16 各算一遍）
        pool = vecs[: min(len(vecs), 300)]
        pool_f16 = [_f16_roundtrip(v) for v in pool]
        same = 0
        queries = min(5, len(vecs))
        for qi in range(queries):
            q32, q16 = vecs[qi], pool_f16[qi]
            b32 = _top1(q32, pool)
            b16 = _top1(q16, pool_f16)
            if b32 == b16:
                same += 1
        print(f"    top-1 近邻一致：{same}/{queries}（池 {len(pool)} 条）")
        if same == queries and min_cos > 0.9999:
            print("    → 结论：精度足够，迁移不改变召回（与设计稿容差一致）")
        else:
            print("    → 结论：**有差异，迁移前要加核对**（别直接换）")
    except Exception as e:
        print(f"    （精度实测失手：{e}）")


def _f16_roundtrip(v):
    """list → float16 BLOB → list（照设计稿 _vec_dump/_vec_load 的口径）。"""
    blob = struct.pack("<%de" % len(v), *v)
    return list(struct.unpack("<%de" % len(v), blob))


def _cos(a, b):
    s = na = nb = 0.0
    for i in range(len(a)):
        s += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    d = math.sqrt(na) * math.sqrt(nb)
    return s / d if d else 0.0


def _top1(q, pool):
    best, bi = -2.0, -1
    for i in range(len(pool)):
        c = _cos(q, pool[i])
        if c > best:
            best, bi = c, i
    return bi


def sec_queue(con):
    """③ embed_queue 残渣。"""
    print("=" * 78)
    print("三、embed_queue 清理")
    try:
        tot, done, pend = con.execute(
            "SELECT count(*), sum(done), sum(case when done=0 then 1 else 0 end) FROM embed_queue"
        ).fetchone()
        old = con.execute(
            "SELECT count(*) FROM embed_queue WHERE done=1 "
            "AND created_at < datetime('now','localtime',?)", (f"-{QUEUE_KEEP_DAYS} days",)).fetchone()[0]
        print(f"  总 {tot} 行：done {done or 0} / 未 done {pend or 0}")
        print(f"  done 且超 {QUEUE_KEEP_DAYS} 天：**{old} 行可删**（留近 {QUEUE_KEEP_DAYS} 天）")
    except Exception as e:
        print(f"  （量不动：{e}）")
    return 0


def sec_small_tables(con):
    """④ 小表轮转。"""
    print("=" * 78)
    print("四、小表轮转")
    for tbl, col, keep in (("obs_daily", "day", OBS_KEEP_DAYS),
                           ("idem_cache", "created_at", IDEM_KEEP_DAYS)):
        try:
            n = con.execute(f"SELECT count(*) FROM {tbl}").fetchone()[0]
            if col == "day":
                old = con.execute(
                    f"SELECT count(*) FROM {tbl} WHERE {col} < date('now','localtime',?)",
                    (f"-{keep} days",)).fetchone()[0]
                first = con.execute(f"SELECT min({col}) FROM {tbl}").fetchone()[0]
            else:
                old = con.execute(
                    f"SELECT count(*) FROM {tbl} WHERE {col} < datetime('now','localtime',?)",
                    (f"-{keep} days",)).fetchone()[0]
                first = con.execute(f"SELECT min({col}) FROM {tbl}").fetchone()[0]
            print(f"  {tbl:12} 共 {n} 行（最早 {first}）；超 {keep} 天：**{old} 行可删**")
        except Exception as e:
            print(f"  {tbl:12} （量不动：{e}）")
    return 0


def main():
    ap = argparse.ArgumentParser(description="数据库保养 · 只读 dry-run（量能省多少）")
    ap.add_argument("--samples", type=int, default=200, help="精度实测抽样条数（默认 200）")
    a = ap.parse_args()
    if not os.path.exists(DB_PATH):
        print(f"找不到库：{DB_PATH}")
        return 1
    con = sqlite3.connect(DB_PATH)
    try:
        st = sec_db_size(con)
        tot_text, tot_f16 = sec_vectors(con, a.samples)
        sec_queue(con)
        sec_small_tables(con)
        print("=" * 78)
        print("五、合计预计（只算向量这一项，小表省的是零头）")
        if tot_text:
            after = st - (tot_text - tot_f16)
            print(f"  库 {_mb(st):.1f} MB → 约 {_mb(after):.1f} MB"
                  f"（省 ~{_mb(tot_text - tot_f16):.1f} MB，另可 VACUUM 收页）")
        print("  ⚠️ 本轮**只量不改**；真迁移＝另一步（备份→建 vectors_v2→逐行转→对账→原子换名），要家主点窗口。")
        print("=" * 78)
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
