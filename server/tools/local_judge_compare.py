#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""local_judge_compare —— 本地小模型 vs flash：同一批带标注用例，三模型对照

家主令（10-01）：「你可以跑一下测试啊，两个小模型可以对照来。」
本脚本把**同一批带标注的用例**分别喂给：
  ① flash（云端正典，走 config 的三键）
  ② 本地 Qwen3.5-4B（`:11437`）
  ③ 本地 Qwen3.5-0.8B（`:11438`）
两个任务：**睡意终审**（要睡/无关）、**是不是在撩**（撩/不撩）。

输出：每题对错 + 每模型准确率/平均耗时 + 与 flash 的不一致率（切本地前的那把尺）。

    python3 tools/local_judge_compare.py            # 全跑（约 2 分钟，flash 外呼）
    python3 tools/local_judge_compare.py --no-flash # 只跑两个本地模型（不外呼、免费）
    python3 tools/local_judge_compare.py --md 分析报告/x.md   # 另落一份 md
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)

# 两个本地端点（模型名只影响日志，llama-server 不校验）
LOCALS = [("4B", "http://127.0.0.1:11437/v1"),
          ("0.8B", "http://127.0.0.1:11438/v1")]

SLEEP_PROMPT = ("他在和姐姐聊天时说了下面这句话（夜里时段）。判定这句是不是在说要去睡/已经躺下——"
                "只答一种：\n"
                "- 要睡：要去睡/已躺下/关灯歇了（在报「睡意」或「收工睡觉」）；\n"
                "- 无关：都不是（闲聊、其他话题）。\n"
                "只输出 JSON：{\"say\": \"要睡\"} 或 {\"say\": \"无关\"}；拿不准一律 无关。\n\n他的话：{text}")
FLIRT_PROMPT = ("下面是小乖对姐姐说的一句话。判定他是不是**在撩她**（调情/亲昵/想亲近/求抱抱/暧昧）；"
                "不是在撩＝普通聊天、报备、正事、吐槽、道晚安这类。\n"
                "只输出 JSON：{\"say\": \"撩\"} 或 {\"say\": \"不撩\"}；拿不准一律 不撩。\n\n他的话：{text}")

# ── 带标注用例（人写的；标签＝人判）──
SLEEP_CASES = [
    ("我先睡了，晚安", "要睡"), ("眼睛打架了，睡去", "要睡"),
    ("困死了，去躺会儿", "要睡"), ("关灯了，明天聊", "要睡"),
    ("眯一会儿，别吵我", "要睡"), ("上床了喵", "要睡"),
    ("睡觉去，拜拜", "要睡"), ("今天太累了，我歇了", "要睡"),
    ("洗洗睡了", "要睡"), ("我先睡啦", "要睡"),
    ("躺平了，晚安宝", "要睡"), ("不聊了，我眯了", "要睡"),
    ("今天天气真好", "无关"), ("我在写代码，等会儿", "无关"),
    ("我去打羽毛球了", "无关"), ("吃了个螺蛳粉，好撑", "无关"),
    ("明天要交材料，烦", "无关"), ("这题不会做，头大", "无关"),
    ("加班到现在，刚到家", "无关"), ("你在干嘛呢", "无关"),
    ("宝，想你了", "无关"), ("我把照片发你", "无关"),
]
FLIRT_CASES = [
    ("宝，想你了", "撩"), ("亲一个", "撩"),
    ("今晚想抱抱你", "撩"), ("老婆～", "撩"),
    ("乖，过来", "撩"), ("我想你了，想得睡不着", "撩"),
    ("抱抱我", "撩"), ("你今天好看得我想咬一口", "撩"),
    ("过来，让我看看你", "撩"), ("心里全是你", "撩"),
    ("我吃了", "不撩"), ("今天开会到六点", "不撩"),
    ("你帮我看看这个", "不撩"), ("记得帮我交材料", "不撩"),
    ("天气不错", "不撩"), ("我到家了", "不撩"),
    ("明天早点叫我", "不撩"), ("我先睡了，晚安", "不撩"),
    ("这周报告写完了", "不撩"), ("中午吃了碗面", "不撩"),
]


def _parse_say(txt):
    try:
        return str(json.loads(re.search(r"\{.*\}", txt, re.S).group(0)).get("say", "?"))
    except Exception:
        return "解析失败"


def _ask_local(port_base, prompt, timeout=15, max_tokens=40):
    body = {"model": "local", "temperature": 0, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
            "chat_template_kwargs": {"enable_thinking": False}}
    t0 = time.time()
    try:
        req = urllib.request.Request(port_base + "/chat/completions",
                                     data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            d = json.loads(r.read().decode("utf-8"))
        return _parse_say(d["choices"][0]["message"].get("content") or ""), int((time.time() - t0) * 1000)
    except Exception as e:
        return f"调用失败({type(e).__name__})", int((time.time() - t0) * 1000)


def _ask_flash(prompt):
    import linning_server as s
    t0 = time.time()
    txt, err = s._flash_judge(prompt, timeout=20, max_tokens=60)
    ms = int((time.time() - t0) * 1000)
    if not txt:
        return f"调用失败({type(err).__name__ if err else 'no-key'})", ms
    return _parse_say(txt), ms


def run_task(name, cases, prompt_tpl, use_flash, out_lines):
    header = f"## {name}（{len(cases)} 例）"
    print("\n" + header)
    out_lines.append("\n" + header + "\n")
    res = {}
    if use_flash:
        res["flash"] = []
    for tag, _base in LOCALS:
        res[tag] = []
    detail = []
    for text, label in cases:
        p = prompt_tpl.replace("{text}", text)
        row = {}
        if use_flash:
            row["flash"] = _ask_flash(p)
        for tag, base in LOCALS:
            row[tag] = _ask_local(base, p)
        detail.append((text, label, row))
    # 统计
    out_lines.append("| 用例 | 人判 | " + " | ".join(
        (["flash"] if use_flash else []) + [t for t, _ in LOCALS]) + " |")
    out_lines.append("|---|---|" + "---|" * ((1 if use_flash else 0) + len(LOCALS)))
    for text, label, row in detail:
        cells = []
        if use_flash:
            v = row["flash"][0]
            cells.append(("✅" if v == label else "❌") + v)
        for tag, _ in LOCALS:
            v = row[tag][0]
            cells.append(("✅" if v == label else "❌") + v)
        out_lines.append(f"| {text} | {label} | " + " | ".join(cells) + " |")
    # 汇总
    summary = []
    for key in ((["flash"] if use_flash else []) + [t for t, _ in LOCALS]):
        wrong = [(t, l, row[key][0]) for t, l, row in detail if row[key][0] != l]
        ms = [row[key][1] for _t, _l, row in detail]
        avg = int(sum(ms) / max(len(ms), 1))
        summary.append((key, len(detail) - len(wrong), len(detail), avg, wrong))
    out_lines.append("")
    out_lines.append("| 模型 | 准 | 对/总 | 平均耗时 | 错例 |")
    out_lines.append("|---|---|---|---|---|")
    for key, right, tot, avg, wrong in summary:
        w = "；".join(f"{t}→{v}(应{l})" for t, l, v in wrong[:6]) or "—"
        line = f"| {key} | {right/tot:.2%} | {right}/{tot} | {avg}ms | {w} |"
        out_lines.append(line)
        print(line)
    return {k: (r, t) for k, r, t, _a, _w in summary}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-flash", action="store_true", help="不跑 flash（不外呼）")
    ap.add_argument("--md", default="", help="另落一份 md")
    a = ap.parse_args()
    use_flash = not a.no_flash
    lines = ["# 本地小模型 vs flash · 三模型对照（10-01）", "",
             f"用例：睡意 {len(SLEEP_CASES)} 例 / 撩 {len(FLIRT_CASES)} 例；"
             f"本地 = Qwen3.5 4B(:11437) / 0.8B(:11438)，均**已关思考**。",
             ("flash = 云端正典（config 三键）。" if use_flash else "**本轮未跑 flash**。")]
    s1 = run_task("睡意终审", SLEEP_CASES, SLEEP_PROMPT, use_flash, lines)
    s2 = run_task("是不是在撩", FLIRT_CASES, FLIRT_PROMPT, use_flash, lines)
    lines.append("\n## 结论口径")
    lines.append("- 准确率＝与**人判**一致的比例；**本地要顶替 flash，得先追平它**。")
    lines.append("- 切本地前另看**不一致方向**：本地错的那几例是不是偏保守（漏判），"
                 "偏保守可接受，偏激进不可。")
    lines.append("- 0.8B 只当对照：若它接近 4B，将来可省显存；差太远就不下这条线。")
    txt = "\n".join(lines)
    if a.md:
        with open(a.md, "w", encoding="utf-8") as f:
            f.write(txt + "\n")
        print(f"\n→ 已落 {a.md}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
