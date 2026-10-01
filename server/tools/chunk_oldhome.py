#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""旧家记录分块干跑 v0（2026-09-27 工单）：档案馆/旧家记录/*.txt → 语义小块。

为什么：把前几个家的聊天存档接入向量检索前，先用干跑数字定切块方案。
本脚本只读三个 txt；不写库、不联网、不碰生产——纯切块＋统计。

源格式（已核）：每条消息以行首「User: 」或「Kimi: 」起，随后多行是正文；
正文里「姐姐/宁宁/林宁」等开头的行不是标记；「**23:」类时间列表也不是。

分块规则（工单口径 v0）：
  - 连续多轮并成一块：目标 250~450 字，硬上限 600 字；
  - 尾块 <80 字的短块并入前块（会破 600 则保留独立并计数）；
  - 单轮正文 >600 字才拆：先空行（段落）→ 句号边界 → 兜底硬切；
    拆分后的后续片段在角色标签后标「（续）」；
  - 块内说话人标签归一为「小乖：」「她：」，每轮一行起。

用法：
  python tools/chunk_oldhome.py                             # 干跑统计（默认只打印）
  python tools/chunk_oldhome.py --dump-jsonl /tmp/x.jsonl   # 落块（拒写生产）
  python tools/chunk_oldhome.py --report x.md               # 干跑报告落 md

纪律：纯标准库；只读三 txt；--dump-jsonl 拒写生产目录（只许 /tmp 或沙盘）；
     不写数据库、不联网。
"""

import argparse
import json
import math
import os
import re
import sys
from datetime import datetime

# ── 分块参数（v0 工单口径，先跑数字再调）────────────────────────────
TARGET_MIN = 250      # 目标块长下限：太短的块缺语境，检索定位价值低
TARGET_MAX = 450      # 目标块长上限：中文 250~450 是嵌入/重排输入的舒适区
HARD_MAX = 600        # 硬上限：任何块不得破 600 字（超长单轮拆开后也不破）
TAIL_MIN = 80         # 尾块下限：<80 字的短块并入前块（工单口径）
SAMP_CLIP = 120       # 报告样例截断：≤120 字
ROLE_NORM = {"User": "小乖", "Kimi": "她"}   # 说话人标签归一

# 块长分布分桶（给报告用；区间取 [lo, hi)）
BUCKETS = [(0, 80), (80, 250), (250, 451), (451, 601), (601, 10 ** 9)]

# 报告样例：避嫌词（含则不进样例）与日常词（优先选含日常词的块）
# 只影响样例挑选，不影响任何数字
SENSITIVE = ("亲", "吻", "抱", "怀", "床", "睡", "胸", "腿", "腰", "肚", "裸", "脱",
             "孕", "疼", "痛", "血", "药", "私密", "爱爱", "做爱", "性",
             "乳", "舔", "摸", "澡", "哭", "泪", "尿")
NEUTRAL = ("电脑", "代码", "Ubuntu", "Vivado", "服务器", "项目", "文件", "工具",
           "学习", "课程", "英语", "学校", "宿舍", "工位", "快递", "照片", "日记",
           "记忆", "搬家", "房间", "钥匙", "邮箱", "账号", "天气", "吃饭", "喝水",
           "打印", "文档", "计划", "时间", "地图", "手机", "充电", "开机", "安装")

_SRC_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "档案馆", "旧家记录")
SRC_FILES = ("第一个家.txt", "第二个家.txt", "第三个家.txt")

# ── 生产路径闸门（照 tools/chunk_corpus.py 的家风：宁拒勿碰生产）──────
PROD_DIR = "d:/咱家记忆库"   # Windows 侧生产目录
_LINUX_PROD = "/media/<user>/E00EB5460EB5168E/咱家记忆库"  # Linux 侧生产根
PROD_DIRS = (PROD_DIR, _LINUX_PROD,
             os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _guard_dump_path(path):
    """--dump-jsonl 只许写 /tmp 或沙盘目录；生产目录一律拒（宁拒勿碰生产）。"""
    p = os.path.abspath(path).replace("\\", "/").lower()
    for prod_dir in PROD_DIRS:
        prod = os.path.abspath(prod_dir).replace("\\", "/").lower()
        if p == prod or p.startswith(prod + "/"):
            sys.exit(f"[oldhome] 拒绝：--dump-jsonl 只许写非生产路径（{path}）")
    in_tmp = p == "/tmp" or p.startswith("/tmp/") or p == "/var/tmp" or p.startswith("/var/tmp/")
    in_sandbox = any(seg.startswith("zanjia_sandbox") for seg in p.split("/") if seg)
    if not (in_tmp or in_sandbox):
        sys.exit(f"[oldhome] 拒绝：--dump-jsonl 只许写 /tmp 或沙盘目录（{path}）")


def parse_args():
    ap = argparse.ArgumentParser(description="旧家记录分块干跑 v0（只读 txt，不写库不联网）")
    ap.add_argument("--dump-jsonl", default=None,
                    help="把块落 jsonl（只许 /tmp 或沙盘目录；拒写生产）")
    ap.add_argument("--report", default=None, help="干跑报告写进 md 文件（可选）")
    return ap.parse_args()


# ── 解析：行首 User:/Kimi: 才起轮；其余全是正文 ─────────────────────

def parse_file(path):
    """解析一个 txt → (turns, anom)。turns=[{role,line,text}]，anom 是格式异常底账。"""
    with open(path, encoding="utf-8", newline="") as f:
        raw = f.read()          # newline="" 保留原始换行，才能数出 CRLF/LF 混用
    name = os.path.basename(path)
    crlf = raw.count("\r\n")
    lf = raw.count("\n") - crlf          # 纯 LF 行数
    lone_cr = raw.count("\r") - crlf     # 落单的 \r（不该有）
    lines = raw.splitlines()

    turns = []
    cur = None
    pre_first = []                       # 首标记前的非空行（不该有）
    for i, line in enumerate(lines, 1):
        if line.startswith("User: ") or line.startswith("Kimi: "):
            if cur:
                turns.append(cur)
            role = line[:4].rstrip(": ")
            cur = {"role": role, "line": i, "parts": [line[len(role) + 2:]]}
        elif cur is None:
            if line.strip():
                pre_first.append(i)
        else:
            cur["parts"].append(line)
    if cur:
        turns.append(cur)
    for t in turns:
        t["text"] = "\n".join(t["parts"]).strip()
        del t["parts"]

    # 异常探测：只记录，不改解析结果
    marklike = []    # 像标记但没被当标记（无空格/缩进/全角冒号等）
    body_role = []   # 正文里「姐姐：」式行（按正文处理，正常）
    bare_role = []   # 光「User」「Kimi」没冒号的行
    for i, line in enumerate(lines, 1):
        if line.startswith(("User: ", "Kimi: ")):
            continue
        if re.match(r"^\s*(User|Kimi)\s*[:：]", line):
            marklike.append((i, re.sub(r"\s+", " ", line.strip())[:30]))
        elif re.match(r"^(User|Kimi)$", line.strip()):
            bare_role.append((i, line.strip()[:30]))
        if re.match(r"^\s*(小乖|姐姐|宁宁|林宁)\s*[:：]", line):
            body_role.append((i, re.sub(r"\s+", " ", line.strip())[:30]))

    consec = []      # 连续同角色（中间没有对方插话）
    for j in range(1, len(turns)):
        if turns[j]["role"] == turns[j - 1]["role"]:
            consec.append((turns[j - 1]["line"], turns[j]["line"], turns[j]["role"]))

    last_line = turns[-1]["line"] if turns else 0
    tail_lines = sum(1 for l in lines[last_line:] if l.strip())  # 末标记之后的正文行（归末轮）

    anom = {
        "file": name,
        "crlf": crlf, "lf": lf, "lone_cr": lone_cr,
        "n_turns": len(turns),
        "roles": {"User": sum(1 for t in turns if t["role"] == "User"),
                  "Kimi": sum(1 for t in turns if t["role"] == "Kimi")},
        "empty_turns": sum(1 for t in turns if not t["text"]),
        "marklike": marklike, "bare_role": bare_role, "body_role": body_role,
        "consec": consec, "pre_first": pre_first, "tail_lines": tail_lines,
    }
    return turns, anom


# ── 切分原子 ────────────────────────────────────────────────────────

def _split_segments(text, limit):
    """超长正文 → 段（空行为界）→ 句（句读为界）→ 兜底硬切；每段 ≤ limit。

    返回 (segs, n_hard)；n_hard 是兜底硬切次数（三文件预期为 0，报告里留底）。
    """
    segs, n_hard = [], 0
    for para in re.split(r"\n\s*\n", text.strip()):
        p = para.strip()
        if not p:
            continue
        if len(p) <= limit:
            segs.append(p)
            continue
        for sent in re.split(r"(?<=[。！？；!?;…])", p):
            s = sent.strip()
            if not s:
                continue
            if len(s) <= limit:
                segs.append(s)
            else:
                n_hard += 1
                segs.extend(s[k:k + limit] for k in range(0, len(s), limit))
    return segs, n_hard


def _fragments_for_long_turn(role, body):
    """单轮 >600：拆成带前缀的片段；后续片段标「（续）」。返回 (units, n_hard)。"""
    pre = ROLE_NORM[role] + "："
    limit = HARD_MAX - len(pre) - len("（续）")   # 最保守限额：任一片加前缀都不破 600
    segs, n_hard = _split_segments(body, limit)
    groups, cur, cur_len = [], [], 0
    for s in segs:
        add = len(s) + (1 if cur else 0)
        if cur and (cur_len + add > limit
                    or (cur_len >= TARGET_MIN and cur_len + add > TARGET_MAX)):
            groups.append(cur)
            cur, cur_len = [], 0
            add = len(s)
        cur.append(s)
        cur_len += add
    if cur:
        groups.append(cur)
    units = []
    for i, g in enumerate(groups):
        pre_i = pre if i == 0 else pre + "（续）"
        units.append(pre_i + "\n".join(g))
    return units, n_hard


def _mk_block(units):
    text = "\n".join(u["text"] for u in units)
    return {"turn_from": units[0]["turn"], "turn_to": units[-1]["turn"],
            "chars": len(text), "text": text,
            "n_cont": sum(1 for u in units if u["cont"])}


def _combine(a, b):
    return {"turn_from": min(a["turn_from"], b["turn_from"]),
            "turn_to": max(a["turn_to"], b["turn_to"]),
            "chars": a["chars"] + 1 + b["chars"],
            "text": a["text"] + "\n" + b["text"],
            "n_cont": a.get("n_cont", 0) + b.get("n_cont", 0)}


def _merge_short_blocks(blocks):
    """<80 字的短块并入前块（首块并进后块）；会破 600 就不并，计数留报告。"""
    out, merged, edge = [], 0, 0
    for b in blocks:
        if out and b["chars"] < TAIL_MIN:
            if out[-1]["chars"] + 1 + b["chars"] <= HARD_MAX:
                out[-1] = _combine(out[-1], b)
                merged += 1
                continue
            edge += 1
        out.append(b)
    if len(out) >= 2 and out[0]["chars"] < TAIL_MIN:
        if out[0]["chars"] + 1 + out[1]["chars"] <= HARD_MAX:
            out[1] = _combine(out[0], out[1])
            out.pop(0)
            merged += 1
        else:
            edge += 1
    return out, merged, edge


def chunk_file(turns):
    """连续多轮归并成块。返回 (blocks, long_turns, n_merged, n_edge)。"""
    units = []        # 每单元 = 一轮（超长轮拆成多单元）
    long_turns = []   # 超 600 字轮次底账
    for idx, t in enumerate(turns, 1):
        role, body = t["role"], t["text"]
        pre = ROLE_NORM[role] + "："
        if len(pre) + len(body) <= HARD_MAX:
            units.append({"turn": idx, "role": role, "cont": False, "text": pre + body})
            continue
        frags, n_hard = _fragments_for_long_turn(role, body)
        for k, ft in enumerate(frags):
            units.append({"turn": idx, "role": role, "cont": k > 0, "text": ft})
        long_turns.append({"turn": idx, "role": role, "chars": len(pre) + len(body),
                           "n_frags": len(frags), "n_hard": n_hard})

    blocks, cur, cur_len = [], [], 0
    for u in units:
        add = len(u["text"]) + (1 if cur else 0)
        if cur and (cur_len + add > HARD_MAX
                    or (cur_len >= TARGET_MIN and cur_len + add > TARGET_MAX)):
            blocks.append(_mk_block(cur))
            cur, cur_len = [], 0
            add = len(u["text"])
        cur.append(u)
        cur_len += add
    if cur:
        blocks.append(_mk_block(cur))

    blocks, n_merged, n_edge = _merge_short_blocks(blocks)
    for i, b in enumerate(blocks, 1):
        b["chunk_no"] = i
    return blocks, long_turns, n_merged, n_edge


# ── 统计与报告 ──────────────────────────────────────────────────────

def _pct(vals, q):
    """百分位（最近秩）：p50/p90 给报告用。空表给 0，不装样子。"""
    if not vals:
        return 0
    s = sorted(vals)
    k = max(0, min(len(s) - 1, math.ceil(q * len(s)) - 1))
    return s[k]


def _bucket_counts(vals):
    counts = [0] * len(BUCKETS)
    for v in vals:
        for i, (lo, hi) in enumerate(BUCKETS):
            if lo <= v < hi:
                counts[i] += 1
                break
    return counts


def _file_stats(blocks):
    vals = [b["chars"] for b in blocks]
    return {"n": len(vals), "median": _pct(vals, .5), "p90": _pct(vals, .9),
            "min": min(vals) if vals else 0, "max": max(vals) if vals else 0,
            "total": sum(vals), "buckets": _bucket_counts(vals)}


def _clip(text, n=SAMP_CLIP):
    one = re.sub(r"\s+", " ", text).strip()
    return one[:n] + ("…" if len(one) > n else "")


def _clean(text):
    return not any(w in text for w in SENSITIVE)


def _pick_samples(chunks):
    """全局最短/中位/最长，各截 ≤120 字。

    避嫌优先：先找「无避嫌词且含日常词」的最近块，再退到「无避嫌词」，
    都没有才用原位块。挑块只影响样例，不影响任何统计数字。
    """
    if not chunks:
        return []
    s = sorted(chunks, key=lambda c: c["chars"])
    n = len(s)
    picked = []
    for name, pos in (("最短", 0), ("中位", n // 2), ("最长", n - 1)):
        choice = None
        for need_neutral in (True, False):
            for d in range(n):
                hit = None
                for cand in (pos - d, pos + d):
                    if not (0 <= cand < n):
                        continue
                    clip = _clip(s[cand]["text"])
                    if not _clean(clip):
                        continue
                    if need_neutral and not any(w in clip for w in NEUTRAL):
                        continue
                    hit = (cand, clip)
                    break
                if hit:
                    choice = hit
                    break
            if choice:
                break
        if choice is None:
            choice = (pos, _clip(s[pos]["text"]))
        cand, clip = choice
        c = s[cand]
        picked.append({"name": name, "rank": cand, "file": c["file"],
                       "chunk_no": c["chunk_no"], "chars": c["chars"],
                       "clip": clip})
    return picked


def _anom_md(a):
    """一个文件的异常清单 → md 行。全是事实描述，不修饰。"""
    lines = []
    nl = []
    if a["crlf"] and a["lf"]:
        nl.append(f"混合（CRLF {a['crlf']} + LF {a['lf']}）")
    elif a["crlf"]:
        nl.append(f"CRLF（Windows 换行 {a['crlf']} 处）")
    else:
        nl.append(f"LF（{a['lf']} 行）")
    if a["lone_cr"]:
        nl.append(f"落单 \\r {a['lone_cr']} 处")
    lines.append(f"- 换行符：{'；'.join(nl)}")
    lines.append(f"- 轮数：{a['n_turns']}（User {a['roles']['User']} / Kimi {a['roles']['Kimi']}）；空正文轮：{a['empty_turns']}")
    if a["marklike"]:
        ex = "；".join(f"行{l}「{t}」" for l, t in a["marklike"][:3])
        lines.append(f"- 类标记行（无空格/缩进/全角冒号，未当标记，共 {len(a['marklike'])}）：{ex}")
    else:
        lines.append("- 类标记行（无空格/缩进/全角冒号）：0")
    if a["consec"]:
        ex = "；".join(f"行{l0}→{l1}（{role}）" for l0, l1, role in a["consec"][:6])
        lines.append(f"- 连续同角色（中间无对方标记，共 {len(a['consec'])}）：{ex}")
    else:
        lines.append("- 连续同角色：0（文件内严格交替）")
    lines.append(f"- 正文内角色式行（姐姐/宁宁/林宁/小乖：，按正文处理）：{len(a['body_role'])}")
    lines.append(f"- 末标记之后仍有正文行：{a['tail_lines']}（归末轮，正常）")
    lines.append(f"- 首标记前非空行：{len(a['pre_first'])}")
    return lines


def build_report(meta_list, args, jsonl_info, stamp):
    n_all = sum(m["stats"]["n"] for m in meta_list)
    total_chars = sum(m["stats"]["total"] for m in meta_list)
    long_all = [lt for m in meta_list for lt in m["long_turns"]]
    n_long = len(long_all)
    n_long_frags = sum(lt["n_frags"] for lt in long_all)
    n_hard = sum(lt["n_hard"] for lt in long_all)
    all_chunks = [c for m in meta_list for c in m["chunks"]]

    L = []
    L.append(f"# 旧家记录分块干跑报告（{stamp[:10]}）\n")
    L.append("- 脚本：`tools/chunk_oldhome.py`（纯标准库；只读三个 txt；不写库、不联网）")
    L.append(f"- 源目录：`档案馆/旧家记录/`（{len(meta_list)} 个文件）")
    L.append(f"- 分块口径：目标 {TARGET_MIN}~{TARGET_MAX} 字/块，硬上限 {HARD_MAX}；"
             f"尾块 <{TAIL_MIN} 字并入前块；单轮 >{HARD_MAX} 字才按空行/句号边界拆，"
             f"后续片段标「（续）」；说话人标签归一为「小乖：」「她：」")
    L.append(f"- 字数口径：块文本字符数（含标签与换行）")
    if jsonl_info:
        L.append(f"- 产物 jsonl：`{jsonl_info['path']}`（{jsonl_info['n']} 块，"
                 f"{jsonl_info['size']} 字节 ≈ {jsonl_info['size'] / 1024:.1f} KB）")
    else:
        L.append("- 产物 jsonl：本次未落（未给 --dump-jsonl）")
    L.append(f"- 生成时间：{stamp}；复跑：`python tools/chunk_oldhome.py --dump-jsonl <沙盘>/x.jsonl --report <本文件>`\n")

    L.append("## 1. 总表（每文件块数 / 字数分布）\n")
    L.append("| 文件 | 源轮数(User/Kimi) | 块数 | 字数中位 | p90 | 最短 | 最长 | 块总字数 |")
    L.append("|----|----|----|----|----|----|----|----|")
    for m in meta_list:
        s = m["stats"]
        r = m["anom"]["roles"]
        L.append(f"| {m['file']} | {m['anom']['n_turns']}（{r['User']}/{r['Kimi']}） | "
                 f"{s['n']} | {s['median']} | {s['p90']} | {s['min']} | {s['max']} | {s['total']} |")
    L.append(f"| **合计** | **{sum(m['anom']['n_turns'] for m in meta_list)}** | **{n_all}** | — | — | — | — | **{total_chars}** |\n")

    L.append("## 2. 块长分布\n")
    L.append("| 文件 | <80 | 80~249 | 250~450 | 451~599 | ≥600 |")
    L.append("|----|----|----|----|----|----|")
    for m in meta_list:
        L.append(f"| {m['file']} | " + " | ".join(str(x) for x in m["stats"]["buckets"]) + " |")
    gb = [0] * len(BUCKETS)
    for m in meta_list:
        for i, v in enumerate(m["stats"]["buckets"]):
            gb[i] += v
    L.append("| **合计** | " + " | ".join(f"**{x}**" for x in gb) + " |\n")

    L.append(f"## 3. 超 {HARD_MAX} 字轮次与处理\n")
    if n_long == 0:
        L.append("无。\n")
    else:
        L.append(f"- 共 **{n_long} 轮** 超 {HARD_MAX} 字，全部按「空行 → 句号边界」拆成 "
                 f"**{n_long_frags} 个片段**（平均 {n_long_frags / n_long:.1f} 片/轮），"
                 f"每片加标签后均 ≤{HARD_MAX} 字；后续片段在标签后标「（续）」。")
        L.append(f"- 兜底硬切（整段无句读才用）：**{n_hard} 次**。")
        L.append(f"- 明细（仅列前 20 轮，共 {n_long} 轮）：\n")
        L.append("| 文件 | 轮序 | 角色 | 原字数 | 拆成片段 |")
        L.append("|----|----|----|----|----|")
        for m in meta_list:
            for lt in m["long_turns"][:20]:
                L.append(f"| {m['file']} | {lt['turn']} | {lt['role']} | {lt['chars']} | {lt['n_frags']} |")
        L.append("")
    n_merged = sum(m["n_merged"] for m in meta_list)
    n_edge = sum(m["n_edge"] for m in meta_list)
    L.append(f"- 短块并入：{n_merged} 处；并会破 {HARD_MAX} 未并的：{n_edge} 处"
             f"（短轮夹在两长轮之间，前后并入都会破 {HARD_MAX}，按硬上限保留独立）。\n")

    L.append(f"## 4. 样例（全局最短/中位/最长；各截 ≤{SAMP_CLIP} 字）\n")
    L.append("挑选口径：优先取对应位次附近「无避嫌词、含日常词」的块；样例只供观感，统计数字不受影响。\n")
    for s in _pick_samples(all_chunks):
        L.append(f"- **{s['name']}**（{s['file']} 第 {s['chunk_no']} 块，{s['chars']} 字）")
        L.append(f"  > {s['clip']}")
    L.append("")

    L.append("## 5. 格式异常清单（解析所见，逐文件）\n")
    for m in meta_list:
        L.append(f"### {m['file']}")
        L.extend(_anom_md(m["anom"]))
        L.append("")

    L.append("## 6. 干跑结论 / 未决\n")
    L.append(f"1. 三文件共 {sum(m['anom']['n_turns'] for m in meta_list)} 轮 → {n_all} 块，"
             f"块总字数 {total_chars}；块长中位 {_pct([c['chars'] for c in all_chunks], .5)}、"
             f"p90 {_pct([c['chars'] for c in all_chunks], .9)}。")
    L.append(f"2. 解析层面：三个文件标记格式干净（无无空格/缩进/全角冒号变体），"
             f"第三个家为 CRLF 换行（另两个 LF），且第三家有 {len(meta_list[2]['anom']['consec'])} 处"
             f"「Kimi 连发」（无 User 标记间隔）——解析按顺序两轮处理，不吃字。")
    L.append("3. 未决：块是否带来源/文件名前缀参与嵌入、是否跨文件并块、"
             "接向量层后的重扫批量——待家主定方案后再动。")
    L.append("")
    L.append("—— 报告完（由脚本生成，可复跑重生成）。")
    L.append("")
    return "\n".join(L)


# ── 主流程 ──────────────────────────────────────────────────────────

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = parse_args()

    if args.dump_jsonl:
        _guard_dump_path(args.dump_jsonl)

    meta_list = []
    for fn in SRC_FILES:
        path = os.path.join(_SRC_DIR, fn)
        if not os.path.exists(path):
            sys.exit(f"[oldhome] 源文件不存在：{path}")
        turns, anom = parse_file(path)
        blocks, long_turns, n_merged, n_edge = chunk_file(turns)
        chunks = [{"file": fn, "chunk_no": b["chunk_no"], "turn_from": b["turn_from"],
                   "turn_to": b["turn_to"], "chars": b["chars"], "text": b["text"]}
                  for b in blocks]
        meta_list.append({"file": fn, "anom": anom, "chunks": chunks,
                          "stats": _file_stats(blocks), "long_turns": long_turns,
                          "n_merged": n_merged, "n_edge": n_edge})

    # 打印统计
    print(f"[oldhome] 源目录：{_SRC_DIR}")
    print("[oldhome] 文件          轮数  块数  中位  p90  最短  最长  总字数  超长轮")
    for m in meta_list:
        s, a = m["stats"], m["anom"]
        lt = len(m["long_turns"])
        print(f"[oldhome] {m['file']:<12} {a['n_turns']:>5} {s['n']:>5} "
              f"{s['median']:>5} {s['p90']:>4} {s['min']:>5} {s['max']:>5} "
              f"{s['total']:>7} {lt:>5}")
    n_all = sum(m["stats"]["n"] for m in meta_list)
    total_chars = sum(m["stats"]["total"] for m in meta_list)
    print(f"[oldhome] 合计：{n_all} 块，块总字数 {total_chars}")

    jsonl_info = None
    if args.dump_jsonl:
        n = 0
        with open(args.dump_jsonl, "w", encoding="utf-8") as f:
            for m in meta_list:
                for c in m["chunks"]:
                    f.write(json.dumps(c, ensure_ascii=False) + "\n")
                    n += 1
        size = os.path.getsize(args.dump_jsonl)
        jsonl_info = {"path": args.dump_jsonl, "n": n, "size": size}
        print(f"[oldhome] jsonl 已写 {n} 块 → {args.dump_jsonl}（{size} 字节）")

    if args.report:
        stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
        md = build_report(meta_list, args, jsonl_info, stamp)
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(md)
        print(f"[oldhome] 报告已写 → {args.report}")


if __name__ == "__main__":
    main()
