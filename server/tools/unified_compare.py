#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""unified_compare —— 检索层统一·影子读账（§5 第 5 条 · 批次①）

读 `events: mem.unified.shadow`（只带 kind/id/分，无原文），把**新规则 vs 现状**并排算给你：
条数、卷分布、top-5 交集率、多捞/少捞归属，以及最近几轮的样例。**只读，不写库。**

    python3 tools/unified_compare.py            # 近 2 天
    python3 tools/unified_compare.py --days 3
    python3 tools/unified_compare.py --tail 8   # 末尾列 8 轮样例

判据（与工单一致）：**不一致率 = 1 − 交集率**；> 30% 就先别切 `retrieval_unified`，先查原因。
"""
import argparse
import json
import os
import sqlite3
import sys
from collections import Counter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.environ.get("ZANJIA_DB") or os.path.join(BASE_DIR, "咱家的家.db")
TOP_N = 5


def _keys(items, n=TOP_N):
    """取前 n 个 'kind:id'（去掉可能带的 '(分)'）。"""
    out = []
    for it in items or []:
        s = str(it)
        if "(" in s:
            s = s.split("(", 1)[0]
        out.append(s)
        if len(out) >= n:
            break
    return out


def main():
    ap = argparse.ArgumentParser(description="检索层统一·影子读账（只读）")
    ap.add_argument("--days", type=int, default=2, help="看近几天（默认 2）")
    ap.add_argument("--tail", type=int, default=5, help="末尾列几轮样例（默认 5）")
    ap.add_argument("--db", default=DB_PATH)
    a = ap.parse_args()

    if not os.path.exists(a.db):
        print(f"找不到库：{a.db}")
        return 1
    con = sqlite3.connect(a.db)
    con.row_factory = sqlite3.Row
    try:
        rows = con.execute(
            "SELECT ts, payload FROM events WHERE kind='mem.unified.shadow' "
            "AND ts >= datetime('now','localtime',?) ORDER BY id",
            (f"-{int(a.days)} day",)).fetchall()
    finally:
        con.close()

    print("=" * 76)
    print(f"检索层统一·影子读账（近 {a.days} 天）")
    if not rows:
        print("  （一条都还没有：开关 retrieval_unified_shadow 关着？或还没人聊过天。）")
        print("  ⚠️ 影子在 `_retrieve_mixed` 里跑——只有真检索（他说话）才会落账。")
        print("=" * 76)
        return 0

    n = len(rows)
    cur_pool = new_pool = 0
    inter_sum = 0.0
    gained_all = Counter()
    lost_all = Counter()
    born = Counter()          # 新规则里出现的卷
    cur_born = Counter()
    paths = Counter()
    samples = []
    for r in rows:
        try:
            p = json.loads(r["payload"] or "{}")
        except Exception:
            continue
        # 池子大小用 *_all_n；不一致率用**同预算**的 cur/new（各前 cmp_n 条）
        cur_pool += int(p.get("cur_all_n") or p.get("cur_n") or 0)
        new_pool += int(p.get("new_all_n") or p.get("new_n") or 0)
        ck, nk = set(_keys(p.get("cur"), 99)), set(_keys(p.get("new"), 99))
        inter = len(ck & nk)
        denom = max(1, len(ck | nk))
        inter_sum += inter / denom
        for k in (p.get("gained") or []):
            gained_all[str(k).split(":")[0]] += 1
        for k in (p.get("lost") or []):
            lost_all[str(k).split(":")[0]] += 1
        for k, v in (p.get("by_kind") or {}).items():
            born[str(k)] += int(v)
        for it in (p.get("cur") or []):
            cur_born[str(it).split(":")[0]] += 1
        paths[str(p.get("p") or "?")] += 1
        samples.append((r["ts"], p))

    _cmpn = max([int(p.get("cmp_n") or 5) for _ts, p in samples] or [5])
    print(f"  轮数 {n}｜**同预算对比**（各前 {_cmpn} 条）")
    print(f"  池子大小（未截断）：现状平均 {cur_pool / n:.1f} 条 / 新规则平均 {new_pool / n:.1f} 条"
          f"　← 新规则卷多所以池子大，**别拿这个当不一致**")
    print(f"  路径分布：{dict(paths)}")
    print(f"  **top-{_cmpn} 交集率（Jaccard）：平均 {inter_sum / n * 100:.0f}%"
          f"　→ 不一致率 {100 - inter_sum / n * 100:.0f}%**"
          f"　（判据：>30% 先别切）")
    print("  新规则捞到的卷（合计）：" + "、".join(f"{k} {v}" for k, v in born.most_common()))
    print("  现状捞到的卷（合计）：  " + "、".join(f"{k} {v}" for k, v in cur_born.most_common()))
    if gained_all:
        print("  **新规则多捞的**（gained 归属）：" + "、".join(f"{k} {v}" for k, v in gained_all.most_common()))
    if lost_all:
        print("  新规则漏掉的（lost 归属）：  " + "、".join(f"{k} {v}" for k, v in lost_all.most_common()))
    if a.tail > 0:
        print(f"  ── 末尾 {min(a.tail, len(samples))} 轮样例 ──")
        for ts, p in samples[-a.tail:]:
            print(f"    [{ts}] p={p.get('p')} 池子 现状{p.get('cur_all_n')}→新{p.get('new_all_n')}"
                  f"（同预算各 {p.get('cmp_n')}）")
            if p.get("gained"):
                print(f"       多捞：{'、'.join(p['gained'][:6])}")
            if p.get("lost"):
                print(f"       漏掉：{'、'.join(p['lost'][:6])}")
    print("=" * 76)
    return 0


if __name__ == "__main__":
    sys.exit(main())
