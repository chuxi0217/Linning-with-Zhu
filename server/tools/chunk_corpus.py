#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M2 前置·语义分块脚本 v0（2026-09-18 工单）：四卷 → 语义小块（只读干跑）。

为什么：向量层现在整篇一个坐标（一天日记＝一个点），检索定位不到段落。
本脚本先按语义把 days/chats/notes/letters 切成小块，给将来的块表＋reranker 用；
本脚本绝不写库、不联网、不调嵌入端点——纯切块＋统计。

分块规则（v0 保守值，理由随常量写）：
  days    按空行/段落切；目标 150~400 字，超长按句子边界再切，过短与邻块合并。
  chats   同日内相邻消息间隔 ≤10 分钟为一窗；窗内 ≤8 条或 ≤400 字再分块。
  notes   整条即块。
  letters 整封即块；长信按段落 400 字切。

用法：
  python tools/chunk_corpus.py                        # 全库干跑，打印统计
  python tools/chunk_corpus.py --sample 3             # 每卷只挑 3 条源记录（小样）
  python tools/chunk_corpus.py --dump-jsonl x.jsonl   # 另落块 jsonl（拒写生产路径）
  python tools/chunk_corpus.py --report x.md          # 干跑报告落 md
  python tools/chunk_corpus.py --db <库> --commit --yes  # M2 数据层：块写进库（幂等）

纪律：纯标准库；--db 以只读打开做切块；--commit 才写 chunks/fts_chunks（走 memory_lib，
生产库要 --yes）；嵌入不在此脚本（另跑 tools/chunk_embed.py）；绝不联网。
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime

# ── 分块参数（v0 保守值，先跑数字再调）──────────────────────────────
DAY_MIN = 150          # 日记块下限：太短的块缺语境，定位价值低；200 字以下一段话一般够了
DAY_MAX = 400          # 日记块上限：中文 ~400 字是嵌入/重排输入的舒适区，也防块内混话题
CHAT_GAP_MIN = 10      # 对话窗间隔：≤10 分钟视作同一轮连续对话；超了多半是换话题或人走了
CHAT_MAX_MSGS = 8      # 窗内块最多 8 条消息：再多块内话题就杂了，检索定位不纯
CHAT_MAX_CHARS = 400   # 窗内块字数上限：与日记同口径，谁的线先到按谁切
LETTER_MAX = 400       # 长信上限：按段落切，同日记口径
SAMPLE_CHUNKS = 3      # 每卷打印样例数：最短/中位/最长三点，最能看出切得狠不狠

# 块长分布分桶：太短 / 中短 / 舒适区 / 稍长 / 过长（整数域 [lo, hi)，400 整归第三桶）
CHUNK_BUCKETS = [(0, 150), (150, 250), (250, 401), (401, 600), (600, 10 ** 9)]

PROD_DIR = "d:/咱家记忆库"   # 生产目录（Windows 侧）：--dump-jsonl 禁写（只读副本才允许干活）
# Linux 侧生产目录（双系统同一道闸，宁拒勿碰生产）：
#   ① 本脚本所在仓库根——脚本在 <仓库根>/tools/ 下，根下 档案馆/、photos/、咱家的家.db 全是生产卷；
#   ② 已知 Linux 生产根（server :8024 跑的那份；磁盘挂载路径若变，同步改这行）。
_LINUX_PROD = "/media/<user>/E00EB5460EB5168E/咱家记忆库"
PROD_DIRS = (PROD_DIR, _LINUX_PROD,
             os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# chats 窗内排序需要时间；库里格式已核过全为 YYYY-MM-DD HH:MM:SS（0 异常）
_TS_FMT = "%Y-%m-%d %H:%M:%S"


def _guard_dump_path(path):
    """--dump-jsonl 只许写非生产路径：宁拒勿碰生产（工单纪律）。"""
    p = os.path.abspath(path).replace("\\", "/").lower()
    for prod_dir in PROD_DIRS:
        prod = os.path.abspath(prod_dir).replace("\\", "/").lower()
        if p == prod or p.startswith(prod + "/"):
            sys.exit(f"[chunk] 拒绝：--dump-jsonl 只许写非生产路径（{path}）")


def parse_args():
    ap = argparse.ArgumentParser(description="四卷语义分块 v0（只读干跑）")
    ap.add_argument("--db", default="d:/zanjia_sandbox_v3/chunk_v0_src.db",
                    help="库路径（默认沙盘只读副本；只读打开）")
    ap.add_argument("--dump-jsonl", default=None,
                    help="把块落 jsonl（只许非生产路径；本单最多小样跑）")
    ap.add_argument("--sample", type=int, default=None,
                    help="每卷最多处理 N 条源记录（调试/小样用，默认全量）")
    ap.add_argument("--report", default=None, help="干跑报告写进 md 文件（可选）")
    ap.add_argument("--commit", action="store_true",
                    help="M2 数据层（9-27）：把块写进 --db 指向的库（memory_lib.chunk_put，幂等；"
                         "生产库要 --yes）——嵌入由 tools/chunk_embed.py 单独做")
    ap.add_argument("--yes", action="store_true", help="写生产库的确认钮")
    return ap.parse_args()


# ── 切分原子 ─────────────────────────────────────────────────────

def _split_paras(text):
    """按空行分段；单换行只当段内软换行（日记排版常这样）。"""
    parts = re.split(r"\n\s*\n", text.strip())
    return [p.strip() for p in parts if p.strip()]


def _split_sentences(text):
    """按句末标点切句（标点留在句尾）；中文句读 + 英文兜底。"""
    parts = re.split(r"(?<=[。！？；!?;…])", text)
    return [p.strip() for p in parts if p.strip()]


def _hard_split(text, n):
    """兜底：整段没有句读还超长时，按 n 字硬切（诚实切，不丢字）。"""
    return [text[i:i + n] for i in range(0, len(text), n)]


def _pack_segments(segs, min_len, max_len):
    """把段（或句）贪心装块：装到 max 收块；收尾过短与邻块合并。

    这是 days/letters 共用的装配机：min 是"希望达到"，max 是"不许超过"。
    单段超 max 的前提已在调用方按句/硬切处理，这里只做装箱。
    """
    chunks = []
    cur = ""
    for s in segs:
        if not cur:
            cur = s
        elif len(cur) + 1 + len(s) <= max_len:
            cur = cur + "\n" + s
        else:
            chunks.append(cur)
            cur = s
    if cur:
        chunks.append(cur)
    # 过短与邻块合并：先向上并，再检查首块能不能并进第二块
    merged = []
    for c in chunks:
        if merged and len(c) < min_len and len(merged[-1]) + 1 + len(c) <= max_len:
            merged[-1] = merged[-1] + "\n" + c
        else:
            merged.append(c)
    if len(merged) >= 2 and len(merged[0]) < min_len \
            and len(merged[0]) + 1 + len(merged[1]) <= max_len:
        merged[1] = merged[0] + "\n" + merged[1]
        merged.pop(0)
    return merged


def _cut_long_paras(text, max_len):
    """超长段先按句切；单句仍超长才硬切（保底，报告未决里有它）。"""
    segs = []
    for p in _split_paras(text):
        if len(p) <= max_len:
            segs.append(p)
            continue
        for s in _split_sentences(p):
            if len(s) <= max_len:
                segs.append(s)
            else:
                segs.extend(_hard_split(s, max_len))
    return segs


# ── 四卷各自的分块 ────────────────────────────────────────────────

def chunk_day(row):
    """days：整条即块（≤400 字）；超长按段落/句子切，过短合并。"""
    (day_id, date, day_no, title, content) = row
    text = (content or "").strip()
    if not text:
        return [], 1
    meta = {"date": date, "day_no": day_no, "title": title or ""}
    if len(text) <= DAY_MAX:
        return [_mk("day", day_id, 0, text, meta)], 0
    segs = _cut_long_paras(text, DAY_MAX)
    out = []
    for i, t in enumerate(_pack_segments(segs, DAY_MIN, DAY_MAX)):
        out.append(_mk("day", day_id, i, t, meta))
    return out, 0


def _mk(kind, ref_id, seq, text, meta):
    """统一块壳：chunk_id 一眼能看出卷/来源/序号。"""
    return {
        "chunk_id": f"{kind}:{ref_id}:{seq}",
        "kind": kind,
        "ref_id": ref_id,
        "seq": seq,
        "chars": len(text),
        "text": text,
        "meta": meta,
    }


def _slice_chat_window(msgs):
    """窗内再切：≤8 条且 ≤400 字，谁的线先到按谁切（单条超长只好独占）；诚实留白。"""
    blocks = []
    cur = []
    cur_len = 0
    for m in msgs:
        line_len = len(m["role"]) + 1 + len(m["content"])   # "角色：内容"
        add = line_len + (1 if cur else 0)                  # 换行分隔
        if cur and (len(cur) >= CHAT_MAX_MSGS or cur_len + add > CHAT_MAX_CHARS):
            blocks.append(cur)
            cur = []
            cur_len = 0
            add = line_len
        cur.append(m)
        cur_len += add
    if cur:
        blocks.append(cur)
    return blocks


def chunk_chats(rows):
    """chats：同日内相邻消息间隔 ≤10 分钟为一窗；窗内再按条数/字数切块。

    rows 需按 (date, created_at, id) 排好。返回 (块列表, 跳过数, 超长单条数)。
    """
    out = []
    skipped = 0
    oversize = 0                      # 单条 >400 字（块独占）的计数，给未决问题留底
    win = []
    win_no = 0
    prev_dt = None

    def close_win():
        nonlocal win, win_no
        if not win:
            return
        # 超长单条先按句化开（保持原 role/id）——95 条长消息（多为姐姐长信）
        # 若不化开必破 400 上限，而它们恰恰是最该细分的段落
        units = []
        for m in win:
            if len(m["role"]) + 1 + len(m["content"]) <= CHAT_MAX_CHARS:
                units.append(dict(m, frag=0))
            else:
                for j, frag in enumerate(_cut_long_paras(m["content"], CHAT_MAX_CHARS - 4)):
                    # -4：给 "角色：" 前缀留位，保证加前缀后仍 ≤400
                    units.append(dict(m, content=frag, frag=j))
        for bi, block in enumerate(_slice_chat_window(units)):
            # 块首带 role（自包含）；同一消息的相邻片段不重复报 role
            lines = []
            for i, m in enumerate(block):
                if i == 0 or m["id"] != block[i - 1]["id"]:
                    lines.append(f"{m['role']}：{m['content']}")
                else:
                    lines.append(m["content"])
            text = "\n".join(lines)
            m0, m1 = block[0], block[-1]
            meta = {
                "date": m0["date"],
                "win_no": win_no,
                "time_start": m0["created_at"][11:19],
                "time_end": m1["created_at"][11:19],
                "msg_id_min": min(m["id"] for m in block),
                "msg_id_max": max(m["id"] for m in block),
                "n_msgs": len({m["id"] for m in block}),   # 去重：片段多当一条算
                "n_frags": len(block),
            }
            out.append(_mk("chat", m0["id"], f"w{win_no}b{bi}", text, meta))
        win = []

    for r in rows:
        (cid, date, role, content, created_at) = r
        try:
            dt = datetime.strptime(created_at, _TS_FMT)
        except (TypeError, ValueError):
            skipped += 1
            continue
        if not (content or "").strip() or not (role or "").strip():
            skipped += 1
            continue
        m = {"id": cid, "date": date, "role": role, "content": content.strip(),
             "created_at": created_at}
        if len(role) + 1 + len(m["content"]) > CHAT_MAX_CHARS:
            oversize += 1   # 带 "角色：" 前缀后破 400 的单条，会被按句化开
        # 断窗：跨日 或 与上一条间隔 >10 分钟
        if win and (date != win[-1]["date"]
                    or (dt - prev_dt).total_seconds() > CHAT_GAP_MIN * 60):
            close_win()
            win_no += 1
        win.append(m)
        prev_dt = dt
    close_win()
    return out, skipped, oversize


def chunk_note(row):
    """notes：小本本整条即块（本来就是一则短记录）。"""
    (note_id, text, created_at) = row
    text = (text or "").strip()
    if not text:
        return [], 1
    return [_mk("note", note_id, 0, text, {"created_at": created_at})], 0


def chunk_letter(row):
    """letters：整封即块；长信按段落 400 字切（同日记装配机）。"""
    (letter_id, text, created_at) = row
    text = (text or "").strip()
    if not text:
        return [], 1
    meta = {"created_at": created_at}
    if len(text) <= LETTER_MAX:
        return [_mk("letter", letter_id, 0, text, meta)], 0
    segs = _cut_long_paras(text, LETTER_MAX)
    out = []
    for i, t in enumerate(_pack_segments(segs, DAY_MIN, LETTER_MAX)):
        out.append(_mk("letter", letter_id, i, t, meta))
    return out, 0


# ── 统计与报告 ────────────────────────────────────────────────────

def _stats(chunks):
    """(块数, 平均, 最短, 最长)。空卷给全 0，不装样子。"""
    cs = [c["chars"] for c in chunks]
    if not cs:
        return 0, 0, 0, 0
    return len(cs), sum(cs) // len(cs), min(cs), max(cs)


def _hist(chunks):
    counts = [0] * len(CHUNK_BUCKETS)
    for c in chunks:
        for i, (lo, hi) in enumerate(CHUNK_BUCKETS):
            if lo <= c["chars"] < hi:
                counts[i] += 1
                break
    return counts


def _sample_three(chunks):
    """最短/中位/最长三个，看切块的两端和中间。"""
    if len(chunks) <= SAMPLE_CHUNKS:
        return list(chunks)
    s = sorted(chunks, key=lambda c: c["chars"])
    return [s[0], s[len(s) // 2], s[-1]]


def _clip(text, n=120):
    """样例显示用：单行、截断。"""
    one = re.sub(r"\s+", " ", text).strip()
    return one[:n] + ("…" if len(one) > n else "")


def build_report(vol_stats, hist, skipped, oversize, args, db_path, vec_dist):
    lines = []
    lines.append("# 分块脚本 v0 干跑报告（2026-09-18）\n")
    lines.append("- 脚本：`tools/chunk_corpus.py`（纯标准库，只读干跑，不联网、不动库）")
    lines.append(f"- 库副本：`{db_path}`（从生产 `d:/咱家记忆库/咱家的家.db` sqlite3 backup 拷入沙盘，只读打开）")
    lines.append(f"- 参数：`--sample {args.sample if args.sample is not None else '全量'}`")
    lines.append("- 说明：本报告由脚本生成（数字、未决问题、建议都随脚本版本）；复跑可随时重生成。\n")

    lines.append("## 1. 总表（每卷块数 / 块长）\n")
    lines.append("| 卷 | 源条数(处理) | 块数 | 平均块长 | 最短 | 最长 | 跳过 |")
    lines.append("|----|----|----|----|----|----|----|")
    tot_chunks = tot_chars = 0
    for kind in ("days", "chats", "notes", "letters"):
        n_src, chunks = vol_stats[kind]
        cn, avg, mn, mx = _stats(chunks)
        tot_chunks += cn
        tot_chars += sum(c["chars"] for c in chunks)
        lines.append(f"| {kind} | {n_src} | {cn} | {avg} | {mn} | {mx} | {skipped[kind]} |")
    lines.append(f"| **合计** | — | **{tot_chunks}** | — | — | — | "
                 f"**{sum(skipped.values())}** |\n")

    lines.append("## 2. 块长分布\n")
    lines.append("| 卷 | <150 | 150~249 | 250~400 | 401~599 | ≥600 |")
    lines.append("|----|----|----|----|----|----|")
    for kind in ("days", "chats", "notes", "letters"):
        h = hist[kind]
        lines.append(f"| {kind} | " + " | ".join(str(x) for x in h) + " |")
    lines.append("")

    lines.append("## 3. 样例块（每卷最短/中位/最长，各截 120 字）\n")
    for kind in ("days", "chats", "notes", "letters"):
        chunks = vol_stats[kind][1]
        lines.append(f"### {kind}")
        if not chunks:
            lines.append("（本卷无块）\n")
            continue
        for c in _sample_three(chunks):
            meta_bits = ", ".join(f"{k}={v}" for k, v in c["meta"].items())
            lines.append(f"- `{c['chunk_id']}`（{c['chars']} 字；{meta_bits}）")
            lines.append(f"  > {_clip(c['text'])}")
        lines.append("")

    lines.append("## 4. 重扫工作量粗估\n")
    vec_desc = " / ".join(f"{k} {v}" for k, v in sorted(vec_dist.items()))
    total_vec = sum(vec_dist.values())
    lines.append(f"- 全库共切出 **{tot_chunks} 块**（现向量层 {total_vec} 个坐标：{vec_desc}）。")
    lines.append(f"- 块文本总字符 ≈ **{tot_chars}**（已含 chats {sum(c['chars'] for c in vol_stats['chats'][1])} 字，现向量层不含 chats）。")
    lines.append(f"- 重扫口径（粗）：落块后每块一次嵌入调用 → 一次全量重扫 ≈ **{tot_chunks} 次调用**；")
    lines.append("  字符量按所选模型分字器折算（中文粗按 1 字 ≈ 1 token 量级，具体以模型为准），供排队估时。")
    if oversize.get("chats"):
        lines.append(f"- 另注：chats 有 **{oversize['chats']} 条超长单消息**（加「角色：」前缀 >400 字；最长 1258）——")
        lines.append("  v0 已把它们按句化开再入窗打包，不独占超长块。")
    lines.append("")

    # 5/6 节：v0 的未决问题与下一步（随脚本版本更新，复跑不丢）
    lines.append("## 5. 未决问题（v0.1 调参项，等 reranker／金标对照）\n")
    lines.append("1. **对话窗参数**：当前「间隔 ≤10 分钟 / 窗内 ≤8 条或 ≤400 字」为初值，未做过检索对照。可用 M1 的 `评测/run_eval.py`（冻结 45/45）做块化前后对照；建议试 [5/10/30 分钟] × [6/8/10 条]。")
    lines.append("2. **短块**：短文日记（整条即块）与聊天窗口尾碎片会产生 <150 字短块（分布见第 2 节）。跨源合并会破坏「块＝定位单位」，v0 不动；若要合并只可在同源同窗内做。")
    lines.append("3. **块文本要不要带来源前缀**参与嵌入：现在纯原文＋角色前缀，date/title 只在 meta。带「9-14 日记」类前缀可能利于时间式查询，也会污染语义——待对照实验。")
    lines.append("4. **跨日窗**：现严格同日内断窗，23:58→00:03 的连续对话会被切开；是否允许跨日（只看间隔）未定。")
    lines.append("5. **hall 卷**（diary_hall）未纳入 v0 四卷；是否并入 day 卷同规则处理待定。")
    lines.append("6. **超长单条化开**：>400 字消息按句化开已做；碎片以句子为界、与相邻消息正常混装，块的「消息数 / 片段数」已用 n_msgs／n_frags 分开记。")
    lines.append("7. **emoji/特殊符号**：块文本含 emoji（💌 等），换嵌入模型时其分字器处理要验。\n")

    lines.append("## 6. 下一步建议\n")
    lines.append("1. **块表 schema（v1 落地时）**：建议 `chunks(id, kind, ref_id, ord, text, n_chars, meta_json, created_at)`＋`UNIQUE(kind, ref_id, ord)`；向量层复用现有 `vectors`（`kind='chunk'`, `ref_id=chunks.id`），嵌入源文本 = `chunks.text`。")
    lines.append("   - kind 取 day/chat/note/letter（hall 待定）；chat 块 ref_id 取块首消息 id，消息范围与时间在 meta_json（msg_id_min/max、time_start/end、win_no）。")
    lines.append("2. **重扫顺序**：① days/notes/letters 先落块（量小，金标覆盖多，可与现向量直接对照）；② chats 落块（新域大头）；③ **与 T2 换嵌入合并成一次重扫**——T2 本就要全量重扫＋金标双跑，分块搭同班车只扫一遍。")
    lines.append("3. **增量路径**：块化挂写入路径（新日记/新消息落库即入块并进 embed_queue，kind='chunk'），之后只补增量，不再全量。")
    lines.append("4. **对照评测口径**：块化后用同一把尺子做「整篇向量 vs 分块向量」同题对照；FTS 侧可选做 chunk 版索引对照（现纯 FTS 45/45）。\n")
    lines.append("—— 报告完。脚本可复跑：`python tools/chunk_corpus.py --report <路径>`（只读副本、不写生产数据）。")
    lines.append("")
    return "\n".join(lines)


# ── 主流程 ────────────────────────────────────────────────────────

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args()

    if args.dump_jsonl:
        _guard_dump_path(args.dump_jsonl)

    if not os.path.exists(args.db):
        sys.exit(f"[chunk] 库不存在：{args.db}")

    # 只读打开：本脚本没有一条写语句，改不了库（mode=ro 再加一道门闩）
    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    con.text_factory = str

    lim = f" LIMIT {int(args.sample)}" if args.sample else ""
    rows_days = con.execute(
        f"SELECT id, date, day_no, title, content FROM days ORDER BY id{lim}").fetchall()
    rows_chats = con.execute(
        f"SELECT id, date, role, content, created_at FROM chats "
        f"ORDER BY date, created_at, id{lim}").fetchall()
    rows_notes = con.execute(
        f"SELECT id, text, created_at FROM notes ORDER BY id{lim}").fetchall()
    rows_letters = con.execute(
        f"SELECT id, text, created_at FROM letters ORDER BY id{lim}").fetchall()
    vec_dist = dict(con.execute(
        "SELECT kind, COUNT(*) FROM vectors GROUP BY kind").fetchall())
    con.close()

    vol_stats, skipped, oversize = {}, {}, {"chats": 0}
    day_chunks = []
    skipped["days"] = 0
    for r in rows_days:
        cs, sk = chunk_day(r)
        day_chunks.extend(cs)
        skipped["days"] += sk
    vol_stats["days"] = (len(rows_days), day_chunks)

    chats_chunks, skipped["chats"], oversize["chats"] = chunk_chats(rows_chats)
    vol_stats["chats"] = (len(rows_chats), chats_chunks)

    note_chunks = []
    skipped["notes"] = 0
    for r in rows_notes:
        cs, sk = chunk_note(r)
        note_chunks.extend(cs)
        skipped["notes"] += sk
    vol_stats["notes"] = (len(rows_notes), note_chunks)

    letter_chunks = []
    skipped["letters"] = 0
    for r in rows_letters:
        cs, sk = chunk_letter(r)
        letter_chunks.extend(cs)
        skipped["letters"] += sk
    vol_stats["letters"] = (len(rows_letters), letter_chunks)

    hist = {k: _hist(vol_stats[k][1]) for k in vol_stats}

    # 打印总表
    print(f"[chunk] 库：{args.db}")
    print("[chunk] 卷    源条数  块数  平均  最短  最长  跳过")
    for kind in ("days", "chats", "notes", "letters"):
        n_src, chunks = vol_stats[kind]
        cn, avg, mn, mx = _stats(chunks)
        print(f"[chunk] {kind:<7} {n_src:>5} {cn:>5} {avg:>5} {mn:>5} {mx:>5} {skipped[kind]:>4}")
    print(f"[chunk] 超长单条（带前缀 >400 字，已按句化开）：{oversize['chats']}")
    for kind in ("days", "chats", "notes", "letters"):
        for c in _sample_three(vol_stats[kind][1]):
            print(f"[chunk] 样例 {c['chunk_id']} ({c['chars']}字) {_clip(c['text'], 60)}")

    if args.dump_jsonl:
        n = 0
        with open(args.dump_jsonl, "w", encoding="utf-8") as f:
            for kind in ("days", "chats", "notes", "letters"):
                for c in vol_stats[kind][1]:
                    f.write(json.dumps(c, ensure_ascii=False) + "\n")
                    n += 1
        print(f"[chunk] jsonl 已写 {n} 块 → {args.dump_jsonl}")

    if args.report:
        md = build_report(vol_stats, hist, skipped, oversize, args, args.db, vec_dist)
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"[chunk] 报告已写 → {args.report}")

    # ── M2 数据层（9-27）：--commit 把块写进库（幂等；生产要 --yes）──
    if args.commit:
        _root = os.path.dirname(os.path.abspath(args.db))
        if _root not in sys.path:
            sys.path.insert(0, _root)
        import memory_lib as _m
        if os.path.abspath(_m.DB_PATH) != os.path.abspath(args.db):
            sys.exit(f"[chunk] 拒绝：--db（{args.db}）与 memory_lib 的库（{_m.DB_PATH}）"
                     f"不是同一个——防写错库")
        _prod_dbs = [os.path.join(d, "咱家的家.db") for d in PROD_DIRS]
        _prod = any(os.path.abspath(args.db).replace("\\", "/").lower()
                    == os.path.abspath(p).replace("\\", "/").lower() for p in _prod_dbs)
        if _prod and not args.yes:
            print("[chunk] 目标是生产库——加 --yes 才写；本次只报数。")
            return
        _m.init_db()
        n_changed = n_same = 0
        for kind in ("days", "chats", "notes", "letters"):
            for c in vol_stats[kind][1]:
                _cid, _changed = _m.chunk_put(c["kind"], c["ref_id"], str(c["seq"]), c["text"])
                n_changed += 1 if _changed else 0
                n_same += 0 if _changed else 1
        _st = _m.chunk_stats()
        print(f"[chunk] 已写库：新增/更新 {n_changed}，未变 {n_same}；"
              f"盘点 {_st['total']} 块 {_st['per_type']}")


if __name__ == "__main__":
    main()
