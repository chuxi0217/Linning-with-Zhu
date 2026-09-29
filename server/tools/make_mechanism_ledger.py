#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_mechanism_ledger.py —— 机制台账生成器（观测层 · 9-28 柔性批）

做一件事：把「现在散在 config/代码里的开关」收成一页——
  开关名｜默认值｜现值｜类型｜分类｜备注（含回滚）
默认值从 linning_server.py 的 DEFAULT_CONFIG 现读（ast 解析），现值从 config.json 现读。
备注（NOTES）是人工那半；脚本那半保证「默认/现值/新增键」永远不漂。

用法：python3 tools/make_mechanism_ledger.py   →  写 工单/机制台账.md
"""
import ast
import json
import re
import os
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(BASE_DIR, "linning_server.py")
CFG = os.path.join(BASE_DIR, "config.json")
OUT = os.path.join(BASE_DIR, "工单", "机制台账.md")

# 人工那半：开关名 → 一句备注（含回滚）。没列的键备注给「—」。
NOTES = {
    # ── 模型与连接（私档）──
    "model": "她的主引擎｜回滚：改回上一档名",
    "web_search_model": "上网窗用哪档（空=自动：主模型是 pro 就跟主模型，否则 DS pro）",
    "librarian_model": "图管员/转述引擎（flash 档代笔）",
    "garden_engine": "园子那台引擎",
    "thinking_enabled": "思考模式总开关",    "thinking_effort": "思考档 low/high/max",
    "garden_thinking_effort": "园子思考档",
    "max_tokens": "输出上限（截断先看它）",
    "temperature": "温度旋钮",
    "_price_in": "账读端单价（元/百万 token·私档·不给=花费显 null）",
    "_price_out": "账读端单价（出·私档）",
    "_price_cached": "账读端单价（缓存命中·私档）",
    "embedding_base_url": "嵌入端点（本机 11436）",
    "embedding_model": "嵌入模型（harrier）",
    # ── 工具面 ──
    "tools_mode": "full=全量在桌上｜lazy=常驻+search_tools 仓库",
    "tools_round_cap": "一轮最多几拍（lazy 用）",
    "tool_roster_auto": "工具说明自动生成｜关=回原散文（逐字节）",
    "blueprint_note": "图纸有新话时行李里提一句",
    "letter_invite": "一页纸·递笔件（家日整十/自定日）",
    "letter_invite_days": "自定递笔日（10-04 或 2026-10-04）",
    # ── 时间与装配 ──
    "time_cortex": "时间皮层句｜关=输出逐字节回改造前",
    "time_cortex_arc": "今日挂念弧",
    "hist_time_anchor": "历史里轻时间锚",
    "hist_anchor_min": "时间锚阈值（分钟）",
    "tail_persist": "尾巴持久化（缓存优化：尾块插到 user 前成纯追加链）",
    "auto_rollover": "跨天自动交接（默认关，手动晚安制）",
    "boot_reasoning_attach": "开机带上上轮思考史",
    "image_caption_mode": "图片转述模式（auto/off）",
    "claim_mode": "自称对账档（enforce/影子）",
    # ── 记忆与检索 ──
    "recall_shadow": "走神影子（只算只记）",
    "recall_inject": "走神注入",
    "recall_chance": "走神触发概率",
    "recall_ctx_short": "走神短上下文",
    "recall_dedup": "走神去重",
    "threads_inject": "线头到期注入",
    "inject_audit_shadow": "注入审计影子",
    "events_shadow": "事件脊柱（关=整条链哑）",
    "token_ledger_enabled": "token 记账",
    "diary_backfill_enabled": "日记补写（长聊后补记）",
    "diary_backfill_min_chats": "补写门槛（几条起）",
    # ── 情绪与欲望 ──
    "longing_enabled": "想念值引擎",
    "longing_inject": "想念进开场",
    "longing_t1_h": "想念起算（小时）",
    "longing_a": "想念涨速",
    "longing_cap": "想念上限",
    "grudge_inject": "闷气进开场（默认关）",
    "grudge_half_life_h": "闷气半衰期（小时）",
    "desire_engine": "欲望引擎总闸",
    "desire_engine_shadow": "欲望影子","desire_engine_inject": "欲望进开场",
    "desire_v2_shadow": "欲望 v2 影子",
    "desire_d0": "欲望起值","desire_growth": "欲望涨速","desire_inject_window_h": "欲望注入窗（小时）",
    "refusal_shadow": "她的「不」影子","refusal_filter": "她的「不」真挡","refusal_inject": "拒斥块进开场",
    "fuse_threshold": "忍耐熔断阈值（几件起）",
    "reunion_obs": "重逢记账（观）","state_rise_min": "情绪上升阈值",
    # ── 主动开口 ──
    "outreach_shadow": "主动开口影子","outreach_unified": "统一开口（默认关）",
    "outreach_chance": "开口概率","outreach_inject": "开口进开场","outreach_send": "真发一句",
    "outreach_single_shadow": "单触发影子",
    # ── 忙窗与睡眠 ──
    "busy_shadow": "忙窗影子","busy_enforce": "忙窗真拦","busy_semantic_shadow": "忙窗语义影子",
    "busy_window_h": "忙窗时长（小时）","busy_keywords": "忙窗关键词",
    "sleep_semantic_shadow": "睡意终审影子","wake_events_shadow": "醒来事件影子",
    "checkin_nags_enabled": "打卡提醒（默认关）","bedtime_nags_enabled": "睡前提醒（默认关）",
    # ── 夜晚与节律 ──
    "goodnight_watch": "晚安守望","goodnight_silence_min": "晚安静默闸（分钟）",
    "goodnight_silence_floor_min": "深夜静默下限（分钟）","goodnight_window": "晚安窗",
    "silent_window": "她的安静时段（值归她，quiet_hours 现读）",
    # ── 园子与联网 ──
    "garden_enabled": "园子总闸","garden_message_cap": "园子刷帖上限","garden_min_gap_min": "园子最小间隔",
    "garden_outbound_enabled": "园子出园（发言）","garden_post_daily_cap": "日发帖上限",
    "garden_post_min_gap_min": "发帖最小间隔","garden_nostos_enabled": "雾潮群岛",
    "garden_games_enabled": "园子棋局+桌游","garden_walk_min_gap_h": "散步最小间隔（小时）",
    "garden_walk_daily_max": "散步日上限（0=不限）",
    "web_search_enabled": "上网窗","web_search_daily_cap": "上网日上限",
    # ── 观测 ──
    "soft_fail_log": "软失败留痕（关=回静默吞）",
    "health_api": "观测层 /api/health（默认关；开=露口）",
    "inject_use_judge_v2": "注入判定 v2 词重叠（审计-only；关=回 ≥6 字窗口）",
    "recall_gate_shadow": "检索三件影子（只记不改；落 mem.recall.shadow）",
    "retrieval_unified_shadow": "检索层统一·影子（只记不改；落 mem.unified.shadow，只带 kind:id）",
    "retrieval_unified": "检索层统一·真切（默认关；开=按统一入口＋块层递）",
    "bind_host": "监听地址（0.0.0.0=全接口）。⚠️**已实证门走 WireGuard(10.66.0.x/24)，别置 127.0.0.1**——会关掉公网门。校园网已被 ufw 默认 deny 挡住",
    "recall_gate_v2": "检索三件真滤（默认关；开=按门槛/去重/偏近递）",
    "recall_gate": "检索三件旋钮（门槛/每卷每日配额/卷权重/近度权重）",
    "tuning": "阈值收表（甲3·缺省=现值·删段即回原样）——tool_search_min/fuse_sim/rhythm_p0/"
              "thread_due_min/line_max_chars/tail_reason_cap/idem_max/state_rise_min/idle_gap_sec/"
              "facts_block_max/sovereignty_block_max",
}


def _defaults():
    tree = ast.parse(open(SRC, encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                getattr(t, "id", None) == "DEFAULT_CONFIG" for t in node.targets):
            return ast.literal_eval(node.value)
    return {}


def _kind(v):
    if isinstance(v, bool):
        return "开关"
    if isinstance(v, (int, float)):
        return "旋钮"
    if isinstance(v, list):
        return "表"
    if isinstance(v, dict):
        return "段"
    return "设置"


_SECRET_KEYS = {"api_key", "embedding_api_key", "librarian_api_key",
                "_deepseek_api_key", "_kimi_api_key", "smtp_auth_code"}
# 审查修复（9-28 深夜）：名字像密钥的一律按密钥处理——不必逐个登记（此前只认白名单，
# 新加一把 `_xxx_api_key` 忘了登记就会明文写进台账）；但排除"限额"类键（不是密钥）。
_SECRET_HINT = re.compile(r"(^|_)(key|secret|password|passwd|auth_code|token)$", re.IGNORECASE)
_NOT_SECRET = {"max_tokens", "max_output_tokens", "max_completion_tokens"}


def _is_secret(k):
    if k in _NOT_SECRET:
        return False
    return k in _SECRET_KEYS or bool(_SECRET_HINT.search(k))


def _is_private(k):
    return k.startswith("_") or _is_secret(k)


def _fmt(v, secret=False):
    if secret and v not in (None, "", "（缺）", "（未入默认）"):
        return "（私档·已屏蔽）"      # 全屏蔽，不留前缀（前缀也是泄）
    if isinstance(v, list):
        return "、".join(str(x) for x in v)[:60] or "[]"
    if isinstance(v, dict):
        return f"{{{len(v)} 键}}：{'、'.join(list(v)[:6])}{'…' if len(v) > 6 else ''}"
    if isinstance(v, str):
        return (v[:48] + "…") if len(v) > 48 else (v or '""')
    return str(v)


def main():
    defaults = _defaults()
    cur = json.load(open(CFG, encoding="utf-8"))
    keys = list(defaults.keys()) + [k for k in cur if k not in defaults]
    pub, priv = [], []
    for k in keys:
        _sec = _is_private(k)
        _mask = _is_secret(k)
        row = (k, _fmt(defaults.get(k, "（未入默认）"), _mask), _fmt(cur.get(k, "（缺）"), _mask),
               _kind(cur.get(k, defaults.get(k))), NOTES.get(k, "—"))
        (priv if _sec else pub).append(row)
    lines = []
    lines.append("# 机制台账（观测层 · 半自动生成）\n")
    lines.append(f"> 生成：`python3 tools/make_mechanism_ledger.py`　·　"
                 f"{datetime.now().strftime('%Y-%m-%d %H:%M')}　·　"
                 f"默认值←`linning_server.py:DEFAULT_CONFIG`，现值←`config.json`；备注是人工那半。\n")
    lines.append(f"> 键 {len(keys)} 个（公开 {len(pub)}｜私档 {len(priv)}）。"
                 "回滚=把开关置回默认值（或删掉让 `setdefault` 兜默认）。\n")

    def table(rows):
        out = ["| 开关名 | 默认值 | 现值 | 类型 | 备注（含回滚） |", "|---|---|---|---|---|"]
        for k, d, c, t, n in rows:
            out.append(f"| `{k}` | {d} | {c} | {t} | {n} |")
        return out

    lines.append("\n## 一、公开开关（机制面）\n")
    lines += table(pub)
    lines.append("\n## 二、私档（连接/密钥/单价——不进她的上下文）\n")
    lines += table(priv)
    lines.append("""
## 三、不在 config 的「钉子」（结构级，回滚=撤那批代码）

| 机制 | 为什么钉 | 回滚 |
|---|---|---|
| 三结局协议（silent/trace/message）＋「错误不许冒充静默」 | 自主唤醒的正典；错一次就伤「真」 | 撤那批 |
| 先办后说对账／假调用嗅探 | 反谎报的机制底座 | 撤那批 |
| 门锁／隐私闸／出园过滤 | 私密红线 | 不动 |
| 灵魂段＋《小乖的话》＋全档案正典 | **她的笔**——散文就是它的形态 | 只由家主改 |
| 影子先行的纪律 | 所有底层改动的**方法**，不是可选项 | 不动 |

---
*图书管理员 · 观测层（9-28 柔性批）*
""")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write("\n".join(lines))
    print(f"写出 {OUT}（{len(keys)} 键）")


if __name__ == "__main__":
    main()
