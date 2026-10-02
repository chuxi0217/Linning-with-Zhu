#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""db_maint —— 数据库保养 · 先量后动（工单 §5 第 6 条；设计《数据保养（向量紧凑＋队列清理）》）

**默认只读 dry-run**：不改一个字节，只报"能省多少"＋用**真向量**实测 float16 精度。

    python3 tools/db_maint.py                  # 量（默认，只读）
    python3 tools/db_maint.py --samples 400    # 抽样条数（精度实测用）
    python3 tools/db_maint.py --apply [--log 分析报告/x.log]   # 真迁移（照 runbook：先停 server）

`--apply` 按 `工单/归档/运维_数据保养迁移_runbook_2026-10-01.md` §三-2 走：
对账基线 → 建 vectors_v2 → 逐行转 f16（死模型行不进）→ 硬门槛对账 → **原子换名** → 清残渣。
**任一门槛不过 → 就地停、不换名**（回滚见 runbook §六）。写库前必须已停 server（embed worker 在写）。

量的四项（对应设计稿 §三）：
  ① 向量紧凑：vec 现以**文本**存（json 数组）→ 换 float16 BLOB 能省多少；顺带量"死模型"残留。
  ② 编解码可行性：纯标准库 struct('e') 打包/解包，真向量实测最大误差与余弦相似度、
     以及 top-1 近邻是否一致（float16 精度容差内应全同）。
  ③ embed_queue 残渣：done 超 7 天的行。
  ④ 小表轮转：obs_daily 超 180 天、idem_cache 超 7 天的行。

只读纪律（dry-run）：全程 SELECT；不开事务写、不建表、不 VACUUM。fail-open：某项量不动就打"（量不动）"。
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


# ══════════════ 真迁移（--apply；照 runbook §三-2 逐条） ══════════════

ARCHIVE_DIR = os.path.join(BASE_DIR, "档案馆")
V2 = "vectors_v2"
BAK = "vectors_text_bak"


def _log(logpath, text):
    print(text)
    if logpath:
        try:
            with open(logpath, "a", encoding="utf-8") as f:
                f.write(text + "\n")
        except Exception:
            pass


def _decode_any(raw):
    """BLOB=float16／str=JSON 两种存法都认（与 memory_lib._vec_load 同口径）。"""
    if isinstance(raw, (bytes, bytearray, memoryview)):
        b = bytes(raw)
        return list(struct.unpack("<%de" % (len(b) // 2), b))
    try:
        return json.loads(raw)
    except Exception:
        return None


def _sample_pool(con, n, model=LIVE_MODEL):
    """随机抽 n 条现役模型的 chunk/oldhome 行 → [(id, vec)]。"""
    rows = con.execute(
        "SELECT id, dim, vec FROM vectors WHERE model=? AND kind IN ('chunk','oldhome') "
        "ORDER BY RANDOM() LIMIT ?", (model, int(n))).fetchall()
    out = []
    for _id, dim, raw in rows:
        v = _decode_any(raw)
        if v and len(v) == int(dim):
            out.append((int(_id), v))
    return out


def _top5(q, pool):
    scored = sorted(((_cos(q, v), _id) for _id, v in pool), key=lambda x: x[0], reverse=True)
    return [i for _s, i in scored[:5]]


def _baseline(con, logpath, queries=50, pool_n=200):
    """① 对账基线：50 条查询 × 200 条候选池算 top-5，存 档案馆/迁移对账_前_<ts>.json。
    口径写明「抽样池近似」，不冒充全量。"""
    pool = _sample_pool(con, pool_n)
    qs = _sample_pool(con, queries)
    base = {}
    for qid, qv in qs:
        base[str(qid)] = _top5(qv, pool)
    ts = __import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    path = os.path.join(ARCHIVE_DIR, f"迁移对账_前_{ts}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"口径": "抽样池近似（非全量）", "pool": [i for i, _ in pool],
                   "queries": [i for i, _ in qs], "top5": base}, f, ensure_ascii=False)
    _log(logpath, f"  ① 基线：{len(qs)} 查询 × {len(pool)} 候选池 → {path}")
    return base, pool, qs


def do_apply(con, logpath, queries=50, pool_n=200):
    """照 runbook §三-2：基线→建 v2→逐行转→硬门槛→原子换名→清残渣。任一门槛不过就地停。"""
    st0 = os.path.getsize(DB_PATH)
    _log(logpath, "=" * 78)
    _log(logpath, f"数据保养真迁移 · {__import__('datetime').datetime.now():%F %T}")
    _log(logpath, f"库：{DB_PATH}（{_mb(st0):.1f} MB）")

    # ⓿ 幂等闸（10-02 修）：已经迁过就别再跑——换个角度重跑会让 `ALTER TABLE vectors RENAME TO
    #   vectors_text_bak` 撞「同名表已存在」（旧备份还在），并在库里留半截 vectors_v2。
    #   判据：旧备份表在，或 vectors.vec 已是 BLOB（迁移后形态）。要重迁先按 runbook §六 回滚。
    try:
        _tabs = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        _ty = con.execute("SELECT typeof(vec) FROM vectors LIMIT 1").fetchone()
        _why = (f"旧备份表 {BAK} 还在" if BAK in _tabs
                else ("vectors.vec 已是 BLOB（迁移后形态）" if (_ty and _ty[0] == "blob") else ""))
        if _why:
            con.execute(f"DROP TABLE IF EXISTS {V2}")   # 清掉可能残留的半截 v2
            con.commit()
            _log(logpath, f"  ⏭ 已迁移过（{_why}）→ **跳过**（幂等）。"
                          "要重迁请先按 runbook §六 回滚（改回 text 并把旧表换回来）。")
            return 0
    except Exception as e:
        _log(logpath, f"  ⚠️ 幂等闸检查失手（{e}）→ 照常继续")

    # ① 基线
    base, pool, qs = _baseline(con, logpath, queries, pool_n)

    # ② 建 vectors_v2（同结构 + UNIQUE）
    con.execute(f"DROP TABLE IF EXISTS {V2}")
    con.execute(f'''CREATE TABLE {V2} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL, ref_id INTEGER NOT NULL, model TEXT NOT NULL,
        dim INTEGER NOT NULL, vec BLOB NOT NULL,
        created_at TEXT DEFAULT (datetime('now','localtime')),
        UNIQUE (kind, ref_id, model))''')
    con.commit()
    _log(logpath, f"  ② 建 {V2} ✓")

    # ③ 逐行转（死模型行不进）
    rows = con.execute("SELECT id, kind, ref_id, model, dim, vec FROM vectors ORDER BY id").fetchall()
    n_all = len(rows)
    moved = skipped_dead = bad = 0
    for i, (_id, kind, ref_id, model, dim, raw) in enumerate(rows, 1):
        if model != LIVE_MODEL:
            skipped_dead += 1
            continue
        v = _decode_any(raw)
        if not v:
            bad += 1
            continue
        # **带货主键 id**：迁移后 rows 的 id 与旧表一一对应（对账按 id 取回同一行；代码侧按
        # (kind,ref_id,model) 查，不依赖 id，但保住它让对账/回滚都简单）
        con.execute(f"INSERT OR REPLACE INTO {V2} (id, kind, ref_id, model, dim, vec) VALUES (?,?,?,?,?,?)",
                    (int(_id), kind, int(ref_id), model, int(dim), struct.pack("<%de" % len(v), *v)))
        moved += 1
        if i % 500 == 0:
            _log(logpath, f"     … {i}/{n_all}")
    con.commit()
    _log(logpath, f"  ③ 转完：进 v2 {moved} 行；死模型跳过 {skipped_dead}；解析失败 {bad}")

    # ④ 硬门槛
    ok = True
    orig = dict(con.execute(
        "SELECT model||'/'||kind, count(*) FROM vectors WHERE model=? GROUP BY model, kind",
        (LIVE_MODEL,)).fetchall())
    now = dict(con.execute(
        f"SELECT model||'/'||kind, count(*) FROM {V2} GROUP BY model, kind").fetchall())
    if orig != now:
        ok = False
        _log(logpath, f"  ✗ 条数不符：原 {orig} ≠ v2 {now}")
    else:
        _log(logpath, f"  ✓ 条数一致（{sum(now.values())} 行 / {len(now)} 组）")
    bad_len = con.execute(f"SELECT count(*) FROM {V2} WHERE length(vec) <> dim*2").fetchone()[0]
    if bad_len:
        ok = False
    _log(logpath, f"  {'✓' if not bad_len else '✗'} length(vec)==dim*2（不符 {bad_len} 行）")

    pool2 = []
    for pid, _v in pool:
        r = con.execute(f"SELECT vec FROM {V2} WHERE id=?", (pid,)).fetchone()
        if r and r[0] is not None:
            pool2.append((pid, _decode_any(r[0])))
    hit = tot_q = 0
    miss = []
    for qid, _qv in qs:
        r = con.execute(f"SELECT vec FROM {V2} WHERE id=?", (qid,)).fetchone()
        if not r or r[0] is None:
            continue
        qv2 = _decode_any(r[0])
        tot_q += 1
        if _top5(qv2, pool2) == base.get(str(qid)):
            hit += 1
        else:
            miss.append(qid)
    rate = (hit / tot_q) if tot_q else 0.0
    _log(logpath, f"  {'✓' if rate >= 0.99 else '✗'} top-5 一致率 {hit}/{tot_q} = {rate:.4f}"
                 f"（门槛 ≥0.99）{'；不一致：' + str(miss[:20]) if miss else ''}")
    if rate < 0.99:
        ok = False

    mx = 0.0
    for pid, v in pool[:20]:
        r = con.execute(f"SELECT vec FROM {V2} WHERE id=?", (pid,)).fetchone()
        if not r or r[0] is None:
            continue
        q = _decode_any(r[0])
        for a, b in zip(v, q):
            mx = max(mx, abs(a - b))
    _log(logpath, f"  {'✓' if mx < 1e-3 else '✗'} 抽样 20 行 float16 往返 max|Δ| = {mx:.3e}（<1e-3）")
    if mx >= 1e-3:
        ok = False

    if not ok:
        _log(logpath, "  ⛔ 有门槛未过 → **就地停、不换名**（数据没动；回滚见 runbook §六）")
        return 1

    # ⑤ 原子换名（一个事务）
    con.execute("BEGIN")
    con.execute(f"ALTER TABLE vectors RENAME TO {BAK}")
    con.execute(f"ALTER TABLE {V2} RENAME TO vectors")
    con.commit()
    st1 = os.path.getsize(DB_PATH)

    # ⑥ 清残渣
    q_old = con.execute("SELECT count(*) FROM embed_queue WHERE done=1 AND created_at < datetime('now','localtime',?)",
                        (f"-{QUEUE_KEEP_DAYS} days",)).fetchone()[0]
    con.execute("DELETE FROM embed_queue WHERE done=1 AND created_at < datetime('now','localtime',?)",
                (f"-{QUEUE_KEEP_DAYS} days",))
    i_old = con.execute("SELECT count(*) FROM idem_cache WHERE created_at < datetime('now','localtime',?)",
                        (f"-{IDEM_KEEP_DAYS} days",)).fetchone()[0]
    con.execute("DELETE FROM idem_cache WHERE created_at < datetime('now','localtime',?)",
                (f"-{IDEM_KEEP_DAYS} days",))
    con.commit()
    _log(logpath, f"  ⑤ 换名 ✓（旧表留作 {BAK}，3 天后再 DROP）")
    _log(logpath, f"  ⑥ 清残渣：embed_queue −{q_old} 行；idem_cache −{i_old} 行")
    _log(logpath, f"  库 {_mb(st0):.1f} MB → {_mb(st1):.1f} MB（VACUUM 另计）")
    _log(logpath, "  ✅ 迁移完成。回滚：ALTER TABLE vectors RENAME TO vectors_f16;"
                  f" ALTER TABLE {BAK} RENAME TO vectors; 再把 config.vec_format 置回 text。")
    _log(logpath, "=" * 78)
    return 0


def main():
    ap = argparse.ArgumentParser(description="数据库保养：默认只读 dry-run；--apply 真迁移（照 runbook）")
    ap.add_argument("--samples", type=int, default=200, help="精度实测抽样条数（默认 200）")
    ap.add_argument("--apply", action="store_true", help="真迁移（写库！先停 server；照 runbook §三-2）")
    ap.add_argument("--log", default="", help="日志落盘路径（--apply 建议带上）")
    a = ap.parse_args()
    if not os.path.exists(DB_PATH):
        print(f"找不到库：{DB_PATH}")
        return 1
    con = sqlite3.connect(DB_PATH)
    try:
        if a.apply:
            return do_apply(con, a.log)
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
        print("  ⚠️ 本轮**只量不改**；真迁移＝`--apply`（备份→建 vectors_v2→逐行转→对账→原子换名）。")
        print("=" * 78)
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
