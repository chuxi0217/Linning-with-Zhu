#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T2-01 一次性重扫脚本（2026-09-18）：把四类素材全量入 embed_queue，
由嵌入影子工按当前 config 的模型（harrier）慢慢嵌。
跑一次即可；重复跑安全（pending 去重，done 后可再入）。"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import memory_lib as m

KINDS = [("day", "days"), ("hall", "diary_hall"), ("letter", "letters"), ("note", "notes")]


def main():
    base = os.path.dirname(os.path.abspath(m.__file__))
    con = sqlite3.connect(os.path.join(base, "咱家的家.db"))
    total = 0
    for kind, table in KINDS:
        ids = [r[0] for r in con.execute(f"SELECT id FROM {table}")]
        for rid in ids:
            m.embed_enqueue(kind, rid)
            total += 1
        print(f"  {kind}: {len(ids)} 条已入队")
    con.close()
    print(f"共入队 {total} 条（pending 去重；worker 按当前模型慢慢嵌）")


if __name__ == "__main__":
    main()
