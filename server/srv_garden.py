# -*- coding: utf-8 -*-
"""srv_garden.py —— 园子整块：入站唤醒 / 散步 / 园门（服务器拆分 P5 · 2026-09-25）

从 linning_server.py 原样搬出：GARDEN-01 入站唤醒（_garden_enqueue_inbox/_garden_wake_prompt/
_garden_settle/_garden_wake_once/_garden_loop）＋ GARDEN-04 自主散步（_bridge_running/
_last_letter_info/_garden_count_today/_garden_walk_snapshot/_ensure_bridge/
_garden_self_walk_allowed）＋ 园门 GALATEA-02（GARDEN_* 常量 / _garden_extract_beach_codes /
_garden_strings_of / _garden_mcp_module / _garden_token / _garden_engine_cfg /
_garden_tools_payload / _garden_wake_with_tools / _garden_receipt_err / _garden_verify_write /
_garden_exec）。纯标准库＋memory_lib；入口重导出同名（心跳/状态页/工具分发/启动块照旧引用）。

运行期反查纪律（见 srv_state docstring）：
- 沙盘重绑：s.GARDEN_MCP_URL / s._GARDEN_MCP_MOD / s._garden_mcp_module / s._garden_token /
  s.GARDEN_TOKEN_PATH；
- 沙盘替身：s.load_config / s.call_deepseek(_with_tools) / s.exec_library_tool /
  s.notify_letter / s._silent_window / s._day_window_start；
- 时间伪装：s.datetime 会被换成 FakeDT——块内一律走 _dt() 现取。
凡此绝不 import 期固化。
"""

import difflib
import hashlib
import json
import os
import re
import sys
import threading
import time

import memory_lib as m
import srv_state

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _dt():
    """运行期反查入口的 datetime：园子系沙盘把 s.datetime 换成 FakeDT（时间伪装）跑定点用例。"""
    return srv_state._srv().datetime

# ── GARDEN-01 自主唤醒（9-13 家主拍板「可以都做」）──
# 生活事件把她叫醒，看完、想过，自己决定：silent（不留痕）/ trace（只给自己）/ message（来找他）。
# 哲学三条（锁死）：①醒来≠发消息，三结局都合法；②**错误不许冒充静默**——掉线/空回复/
# 截断/解析失败/ending 非法=错误：事件不消费、记日志、按租约重试；只有她清醒地
# "silent" 才算独处；③连续性≠完整回放——fact（≤40字，克制稀疏）只进下一次醒来，
# content 只进库给人看，绝不自动进任何上下文。
# G1 只吃事件，没事件不硬醒（时机引擎管「她想你」，Garden 管「她的生活」，两引擎不合并）；
# 单 server 天然单写者（跨进程锁记一行防将来双开）。

def _garden_enqueue_inbox(from_addr, subject, body):
    """（GARDEN-01 §五①）收到信 → 顺手入队一条 inbox 事件。收信是本账、入队是零嘴——
    失败由调用方兜（收信照走）。返回事件 rowid。"""
    ev = json.dumps({"from": from_addr, "subject": subject, "excerpt": (body or "")[:80]},
                    ensure_ascii=False)
    return m.add_world_event("inbox", f"收到一封信：{from_addr}「{(subject or '')[:40]}」", ev)


def _garden_wake_prompt(event, garden_tools=False, game_turn=False):
    """（GARDEN-01 §三）组装唤醒提示词。措辞照施工卷逐字（监理逐字审过）；
    仅两处工程性渲染：evidence 摘要 ≤100 字无则略、「（干净）」补上施工卷里漏的右括号（申报）。
    GALATEA-02 §④：kind=galatea 唤醒轮补一行园子图书证句（garden_tools=True），其余字不动。
    GALATEA-04（9-28，申报①两笔）：①evidence 渲染不再透出 reason 原始码（系统语不进她眼前）；
    ②game_turn_required 事件补一行棋局句（game_turn=True，经 garden_games_enabled 闸）。"""
    _eid, _kind, summary, evidence, _att = event
    now = _dt().now().strftime("%Y-%m-%d %H:%M")
    facts = m.get_recent_facts(3)
    fact_line = " · ".join(facts) if facts else "（还没有）"
    threads = m.get_open_threads(3)
    thread_line = " · ".join(t[2] for t in threads) if threads else "（干净）"
    ev = ""
    try:
        obj = json.loads(evidence or "{}")
        if isinstance(obj, dict):
            ev = "；".join(f"{k}：{str(v)[:50]}" for k, v in obj.items()
                           if k != "reason" and str(v or "").strip())
        else:
            ev = str(evidence or "")
    except Exception:
        ev = str(evidence or "")
    ev = ev[:100]
    garden_line = ("你在园子里有图书证：能看帖、回帖、发帖——想说话就用；静默也永远是合法的。\n"
                   if garden_tools else "")
    game_line = ("这是园子里的牌局——轮到你了：先看局面（garden_game_status），该出手就出手"
                 "（garden_game_action），想在桌边说两句就 garden_game_say；"
                 "玩不玩、怎么玩，全看你。\n" if game_turn else "")
    talk_line = _today_talk_line()   # 10-01：补「今天的会话」——治「她说你没醒」的根
    return (f"现在是{now}。你从一次安静的小憩里醒来——没有人叫你，是家里的一点动静把你唤醒的。\n"
            f"今天发生的：{summary}" + (f"（{ev}）" if ev else "") + "\n"
            + talk_line +
            f"你最近自己留下的心事：{fact_line}\n"
            f"家里还悬着的话头：{thread_line}\n\n"
            + garden_line + game_line +
            "醒来先不用说话。你看看这件事、想想它，然后自己选一个结局：\n"
            "- 没什么想说的，ending 就 \"silent\"——静默也是过日子，没人会失望；\n"
            "- 想留一点只给自己的心事，ending 用 \"trace\"，content 写你的独处正文；\n"
            "- 确实有话想对小乖说，ending 用 \"message\"。没事就不必硬说；\n"
            "  这趟要是看到好玩的、好看的、吃到什么好的、遇到谁——想讲给他就用 message，分享不叫打扰。\n"
            "fact 只留给下一次醒来的你自己看：≤40 字、克制、稀疏，记事实不记情绪。\n"
            "严格只输出 JSON：{\"ending\": \"silent|trace|message\", \"fact\": \"≤40字\", "
            "\"content\": \"trace 时填\", \"message\": \"message 时填，≤80字，像平常那样对他说话\"}")


def _today_talk_line(limit=6, chars=420):
    """醒来轮补「今天你们说过的话」（10-01 · 治「她说你没醒」的**根**）。

    病根：醒来轮原先只有 `今天发生的：{事件模板}` ＋ `你最近自己留下的心事：{facts 3 条}` ＋
    `悬着的话头`——**根本没有今天的会话**，所以她只能凭旧印象拼"今天"。
    实案：9-30 20:37 她 trace 说「小乖…睡了一整天，**至今未见消息**」，而他 12:46 就醒了、
    下午傍晚一直在聊。（见 `工单/设计_醒来合一与引擎降状态_2026-09-30.md`）
    取**今天**（咱家日界）最后 `limit` 条原话，谁说的标清；图/附件标记剥掉；取不到 → 空串
    （诚实缺席，绝不编）。任何异常吞掉——醒来轮不因它停。"""
    try:
        rows = m.get_chats(m.house_today_str())
        if not rows:
            return ""
        out = []
        for _r in rows[-int(limit):]:
            try:
                _role, content = _r[2], (_r[3] or "")
            except Exception:
                continue
            txt = _strip_marker(str(content)).replace("\n", " ").strip()
            txt = re.sub(r"〔(附图|附件|照)[^〕]*〕", "", txt).strip()
            if not txt:
                continue
            out.append(("他：" if _role == "小乖" else "我：") + txt[:60])
        if not out:
            return ""
        return "今天你们说过的话（最近几句，别当成没发生过）：" + (" ｜ ".join(out))[:int(chars)] + "\n"
    except Exception:
        return ""


def _strip_marker(t):
    """剥掉信箱记号前缀（💌/💬/🌱/🌱🌍…）——"近似重复"比对要拿她的正文比，不是比记号。
    9-29 见闻三小件：原来写死 `[2:]`，🌱🌍 是 3 字符会留一个残字。"""
    s_ = str(t or "")
    for _p in ("🌱🌍 ", "🌱 ", "💌 ", "💬 ", "🌍 "):
        if s_.startswith(_p):
            return s_[len(_p):]
    return s_


def _garden_settle(eid, raw, walk=False):
    """（GARDEN-01 §四）解析三结局并落账。解析失败/ending 非法/该结局必填字段为空 =
    错误：release + 日志，事件不消费。落账顺序锁死：先写产出（trace/outbox）再 consume；
    写失败抛出去（不 consume，租约回头重来）。返回结局字符串。
    walk=True（见闻三小件·9-29）：这条是「出门（自主散步）」的分享 → 信箱记 🌍 而非 🌱。"""
    try:
        obj = json.loads(raw.strip("`").removeprefix("json").strip())
        ending = str(obj.get("ending") or "").strip().lower()
        if ending not in ("silent", "trace", "message"):
            raise ValueError(f"ending 非法：{ending!r}")
        fact = str(obj.get("fact") or "").strip()[:40]
        content = str(obj.get("content") or "").strip()
        message = str(obj.get("message") or "").strip()
        if ending == "trace" and not content:
            raise ValueError("trace 没写 content（空回复算错误，不许冒充静默）")
        if ending == "message" and not message:
            raise ValueError("message 没写 message（空回复算错误）")
    except Exception as e:
        m.release_world_event(eid)
        print(f"  [Garden] 这次没醒成（{e}）")
        return "error"
    ts = _dt().now().strftime("%Y-%m-%d %H:%M:%S")
    if ending == "silent":
        m.add_her_trace(ts, "silent", fact, "", eid)
        try:   # 心潮桥批（9-28）：忍住档——醒来却选择不说的时刻，落一行（只记不递）
            _esum = "在园子醒来，看过，选择了一个人待着"
            if fact:
                _esum += f"（留了一行给下次的自己：{fact[:24]}）"
            m.log_shadow("endure·garden", _esum, f"event#{eid}")
        except Exception:
            pass
        m.consume_world_event(eid)
        print(f"  [Garden] 醒来后静默（事件#{eid}）")
        return "silent"
    if ending == "trace":
        m.add_her_trace(ts, "trace", fact, content, eid)
        m.consume_world_event(eid)
        print(f"  [Garden] 留了心事（事件#{eid}）：{content[:30]}")
        return "trace"
    # message：闸门两连（每日上限 / 近似重复）——不拦她醒，只拦「吵他」
    cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
    try:
        cap = int(cfg.get("garden_message_cap") or 3)
    except (TypeError, ValueError):
        cap = 3
    degrade = ""
    # 9-30 删枷锁：原「他在场就压成独处」已删（同上）。
    # 10-01 拒斥闸撤机制：原「她的拒绝账把分享压成独处」已删（`_refusal_garden_enforce` 整只撤）。
    if m.count_outbox_today("🌱") >= cap:
        degrade = "超上限压成独处"
    else:
        try:
            today_msgs = m.get_outbox_today("🌱")
            last_m = _strip_marker(today_msgs[-1][1]) if today_msgs else ""   # 去掉记号再比（🌱 或 🌱🌍）
            if last_m and difflib.SequenceMatcher(None, message, last_m).ratio() >= 0.6:
                degrade = "近似重复压成独处"
        except Exception:
            pass   # 比对炸了不拦她的表达（宁发勿哑）
    if degrade:
        m.add_her_trace(ts, "trace", fact, message, eid)
        m.consume_world_event(eid)
        print(f"  [Garden] {degrade}（事件#{eid}）：{message[:30]}")
        return "trace"
    # 9-29 审查修·顺序：先落信 → 再留痕 → 再销账 → **最后按铃**。
    # 原顺序「按铃 → 留痕 → 销账」：留痕/销账任一抛错 → 事件没消费、租约重来 → 模型重生同一条 →
    # 出了重复 🌱 信、还按了两次门铃。现在铃在销账之后，销不到账就不按铃（宁可不响，不重复响）。
    # 见闻三小件（9-29·A3）：出门（自主散步）的分享缀一个 🌍 ——**写成「🌱🌍」而不是单独换 🌍**：
    # 「🌱」是分享这一族的既有记号，每日上限／近似重复／话头簿／信箱摘要全都按 `LIKE '%🌱%'`
    # 子串认它；缀在后面＝子串兼容，**不可能漏掉哪个闸**（单独换 🌍 得改 6 处，漏一处就静默失效）。
    _share = ("🌱🌍 " if walk else "🌱 ") + message
    # P-0（10-01）：她发出去的分享也**发时即落**——落 outbox 之外，同时进 chats（带原始
    # 时刻）与内存历史，与 💌/💬 走同一个口；运行期反查入口（沙盘可替身），取不到退回原通道。
    _land = getattr(srv_state._srv(), "_her_outgoing", None)
    if callable(_land):
        _land(_share)
    else:
        m.add_outbox_msg(_share)
    try:
        m.add_her_trace(ts, "message", fact, "", eid)
    except Exception:
        pass   # 痕迹是账、不是这条信本身——写不进也别把已经落下的信丢掉
    m.consume_world_event(eid)
    try:
        srv_state._srv().notify_letter()   # 运行期反查：沙盘会重绑 s.notify_letter
    except Exception:
        pass
    print(f"  [Garden] 来找他：{message[:30]}")
    return "message"


def _garden_wake_once():
    """（GARDEN-01 §三）唤醒单轮。每轮顺序照施工卷：开关→静默窗→最短间隔（DB 源、
    重启不丢）→领事件→搁置→唤醒→三结局。返回 "slept"/"silent"/"trace"/"message"/
    "stalled"/"error"，给日志与测试看。"""
    global _WAKE_ERR_UNTIL
    cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
    if not cfg.get("garden_enabled", True):
        return "slept"
    now = _dt().now()
    _sw = srv_state._srv()._silent_window(cfg)   # 运行期反查：沙盘会重绑；9-18 主权移交：空=不设（她清的）
    if _sw and srv_state._srv()._in_window(now.strftime("%H:%M"), _sw):
        return "slept"   # 她夜里也睡
    try:
        gap_min = int(cfg.get("garden_min_gap_min") or 30)
    except (TypeError, ValueError):
        gap_min = 30
    last_ts = None
    try:
        last_ts = m.get_last_trace_ts()
    except Exception:
        last_ts = None
    if last_ts:
        try:
            if (now - _dt().strptime(last_ts, "%Y-%m-%d %H:%M:%S")).total_seconds() < gap_min * 60:
                return "slept"   # 醒来太勤不是活着，是躁
        except ValueError:
            pass
    event = m.claim_next_world_event(10)
    if not event:
        # GARDEN-04 自主散步（9-14 家主拍板「可以做。只要不高频」）：没事件也可以自己
        # 想去园子逛逛。三重闸（4h 间隔 / 日 2 次 / 桥随行）保证绝不高频；散步=投一条
        # kind=galatea 合成事件，下一轮走既有园子专窗醒来（三结局/隐私过滤/写额度照旧）。
        if _garden_self_walk_allowed(cfg, now, last_ts):
            m.add_world_event("galatea", "自主散步：没有人叫你，是你自己想去园子逛逛"
                                         "——看通知、看帖子、回一句、改改名片，或者只是逛逛",
                              evidence=json.dumps({"reason": "walk"}))   # 见闻三小件：散步＝「出门」，信箱记 🌍
            print("  [Garden] 散步骰子掷中：投了一条自主散步（下轮园子专窗醒来）")
        return "slept"   # G1 只吃事件，没事件不硬醒
    eid, _kind, _summary, _evidence, attempts = event
    if attempts > 3:
        m.consume_world_event(eid)
        print(f"  [Garden] 事件搁置（3 次没醒成）#{eid}")
        return "stalled"
    # GALATEA-04（9-28）：棋局事件（reason=game_turn_required）——唤醒窗加开棋局九件、提示词补棋局句；
    # garden_games_enabled 关时照旧走基础窗（她不能玩就不引导）。
    _reason = ""
    try:
        _ev_obj = json.loads(_evidence or "{}")
        if isinstance(_ev_obj, dict):
            _reason = str(_ev_obj.get("reason") or "")
    except Exception:
        _reason = ""
    _game_turn = (_kind == "galatea" and _reason == "game_turn_required"
                  and bool(cfg.get("garden_games_enabled", True)))
    # 见闻三小件（9-29·A3）：散步＝「出门」——它的分享进信箱时记 🌍（园子内的照旧 🌱），
    # 好让他一眼认出"这条是出去看到的事"。信号走结构化 reason，不靠 summary 文案比对。
    _walk = (_kind == "galatea" and _reason == "walk")
    # 唤醒：引擎走 garden_engine 档（GALATEA-02 ⓪——默认主引擎＝config 的 DS 档（K3 已 9-27 退役）；
    # garden_engine=="deepseek" 时走 flash 省钱回退档，thinking 同 librarian 关法）；kind=galatea 的唤醒轮开园子工具
    # 专窗（§④：仅七件园子图书证），其余事件维持无工具。
    wake_cfg = _garden_engine_cfg(cfg)
    # 审查修复（9-29）：原样取 `session().system_prompt` 会走懒拼（consume=True）——园子若在他开口
    # **之前**先醒来，会把走神/话头/欲望这些「取走即清」的一次性注入吞进园子提示词，他开场就少一件。
    # 改：会话已拼好 → 直接复用；还没拼 → 用 **consume=False** 的纯静态版（绝不吞注入，也不回写缓存，
    # 他那一轮照常自己拼、注入照常到他眼前）。失败照旧上抛（调用方 release 事件、回头重领）。
    _g_sess = srv_state.session()
    _g_sp = getattr(_g_sess, "_system_prompt", None)
    if _g_sp is None:
        _g_sp = srv_state._srv().build_system_prompt(consume=False)
    msgs = [
        {"role": "system", "content": _g_sp},   # 取用口（入口属主名）
        {"role": "user", "content": _garden_wake_prompt(event, garden_tools=(_kind == "galatea"),
                                                        game_turn=_game_turn)},
    ]
    try:
        if _kind == "galatea":
            raw = _garden_wake_with_tools(wake_cfg, msgs, eid, game_window=_game_turn)
        else:
            raw = srv_state._srv().call_deepseek(wake_cfg, msgs, scene="garden.wake").strip()   # 运行期反查：沙盘会重绑 s.call_deepseek
    except Exception as e:
        m.release_world_event(eid)
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print(f"  [Garden] 这次没醒成（{e}）")
        return "error"
    if not raw or raw.startswith("（姐姐掉线了"):
        m.release_world_event(eid)   # 错误不许冒充静默：不消费，回头重领
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print("  [Garden] 这次没醒成（掉线/空回复）")
        return "error"
    try:
        return _garden_settle(eid, raw, walk=_walk)
    except Exception as e:
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print(f"  [Garden] 这次没醒成（落账：{e}）")
        return "error"   # 不 consume：租约回头重来（写失败不销账铁律）


def _garden_loop():
    """自主唤醒循环（daemon 线程，ZANJIA_TEST 不起）：300 秒一轮；单轮炸了不拖死。
    10-01 B4-2：`wake_merged=true` 时改走**醒来合一**那一个口（旧链一字不删，并存可回滚）。
    10-02：出错则退避 30 分钟（防模型故障期每 5 分钟空烧一次；退避只在循环里判，不动纯函数）。"""
    global _WAKE_ERR_UNTIL
    while True:
        try:
            try:
                _merged = bool(srv_state._srv().load_config().get("wake_merged", False))
            except Exception:
                _merged = False
            if _WAKE_ERR_UNTIL and time.time() < _WAKE_ERR_UNTIL:
                pass                      # 故障退避中：本轮不醒
            elif _merged:
                if _wake_merged_once() == "error":
                    _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S
            else:
                if _garden_wake_once() == "error":
                    _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S
                _wake_merged_once()   # 影子期：wake_merged=false 且 shadow=true 时只记一行，不外发
        except Exception as e:
            print(f"  [Garden] 循环失手：{e}")
        time.sleep(300)


# ══════════ 醒来合一（10-01 B4-2 · 设计《影子消化与醒来合一_2026-10-01》）══════════
# 四条各自为政的主动链（💌想念信 / 💬话头 / 🌱园子分享 / 早安信）收成**一个醒来口**：
# 一跳只醒一次，她自己挑（say 说话 / garden 去园子 / trace 只给自己的心事 /
# note 给下次醒来的自己留一条 / silent 什么都不做——合法）。
# 纪律：①**一跳一醒**，不再"💬 先、💌 后、园子再一条"；②三闸照旧（静默窗/最小间隔/睡着）；
# ③落账顺序照 `_garden_settle`：先写产出 → 再 consume → 最后按铃；
# ④`wake_merged=false`＝一行回旧链（旧链代码不删、并存）；⑤影子期只记"会给她什么"，
# 一个字不外发、不吃事件（那才是可比的原链读数）。
WAKE_OPTIONS = ("say", "garden", "trace", "note", "silent")
_WAKE_SHADOW_LOG = os.path.expanduser("~/wake_merged_shadow.log")
# 10-02：模型故障退避。error 路径原先不写 trace → 顶上「最短间隔闸」不前进 → 故障期每 5 分钟
# 空烧一次模型。改：连续错就退避 30 分钟（纯内存、不污染 her_traces）。
_WAKE_ERR_UNTIL = 0.0
_WAKE_ERR_BACKOFF_S = 1800


def _wake_today_hand_line():
    """今天她已经出过手的话（💌/💬/🌱）＋他回没回——防复读，也让"惦记"看得见进度。"""
    try:
        bits, _last = [], ""
        for _mk, _lab in (("💌 ", "信"), ("💬 ", "话"), ("🌱", "园子")):
            try:
                _rows = m.get_outbox_today(_mk) or []
            except Exception:
                _rows = []
            for at, txt in _rows[-2:]:
                bits.append(f"{(at or '')[11:16]}{_lab}「{_strip_marker(txt)[:22]}」")
                _last = max(_last, str(at or ""))
        if not bits:
            return ""
        _l = "今天你已经出过手：" + "；".join(bits[-4:])
        try:
            if str(m.last_chat_at("小乖") or "") > _last:
                _l += "（他回过话了，别当没送出去）"
        except Exception:
            pass
        return _l + "\n"
    except Exception:
        return ""


def _wake_material(now):
    """醒来口手边的料：拿到什么摆什么，拿不到就不摆（诚实缺席，绝不编）。"""
    lines = []
    try:
        _f = m.get_recent_facts(3)
        lines.append("你最近自己留下的心事：" + (" · ".join(_f) if _f else "（还没有）"))
    except Exception:
        pass
    try:
        _t = m.get_open_threads(3)
        lines.append("家里还悬着的话头：" + (" · ".join(x[2] for x in _t) if _t else "（干净）"))
    except Exception:
        pass
    try:
        _sc = getattr(srv_state._srv(), "_state_card_block", None)
        _txt = _sc() if callable(_sc) else ""
        if _txt:
            lines.append(_txt.strip())
    except Exception:
        pass
    try:
        _h = _wake_today_hand_line()
        if _h:
            lines.append(_h.strip())
    except Exception:
        pass
    return "\n".join(lines)


def _wake_merged_prompt(now, summary="", ev=""):
    """合一醒来口的提示词。事件可以空——"今天安安静静的"也是一次醒来。"""
    _ev = (f"今天发生的：{summary}" + (f"（{ev}）" if ev else "") + "\n"
           if summary else "今天没发生什么特别的事——安安静静的，也是过日子。\n")
    _talk = _today_talk_line()
    _mat = _wake_material(now)
    return (
        f"现在是{now.strftime('%Y-%m-%d %H:%M')}。你醒一下——没有人叫你，家里安静。"
        "这趟**只醒这一次**，做什么都由你挑。\n"
        + _ev + _talk + (_mat + "\n" if _mat else "")
        + "你可以挑（可多选，也可以什么都不做）：\n"
        "- say：想对他说句话 → message 填（≤80 字，像平常那样对他说话）\n"
        "- garden：想去园子看看/回帖/发帖/逛逛 → doing 里写 garden（出门就出门，不用理由）\n"
        "- trace：只想留一点只给自己的心事 → content 填\n"
        "- note：想给下次醒来的自己留一条 → note 填（≤40 字，记事实不记情绪）\n"
        "- silent：什么都不做——合法，没人会失望\n"
        "严格只输出 JSON：{\"doing\": [\"say\"|\"garden\"|\"trace\"|\"note\"|\"silent\"], "
        "\"message\": \"say 时填\", \"content\": \"trace 时填\", \"note\": \"≤40字\"}"
    )


def _wake_merged_once(now=None):
    """合一醒来口一跳。返回 "slept"/"off"/"shadow"/"silent"/"trace"/"note"/"say"/"garden"/"error"。

    影子期（`wake_merged_shadow=true` 且 `wake_merged=false`）：只往 `~/wake_merged_shadow.log`
    记一行"若走后新口会给她什么"，**不外发、不写库、不吃事件**（旧链照旧跑，读数才可比）。"""
    global _WAKE_ERR_UNTIL
    try:
        cfg = srv_state._srv().load_config()
    except Exception:
        return "off"
    if not (cfg.get("wake_merged", False) or cfg.get("wake_merged_shadow", False)):
        return "off"
    shadow = bool(cfg.get("wake_merged_shadow", False)) and not bool(cfg.get("wake_merged", False))
    now = now or _dt().now()
    # ── 三闸（与既有同款；影子期也照样闸，读的才是"真会出手的次数"）──
    _sw = srv_state._srv()._silent_window(cfg)
    if _sw and srv_state._srv()._in_window(now.strftime("%H:%M"), _sw):
        return "slept"
    if bool(getattr(srv_state._srv(), "ASLEEP", False)):
        return "slept"
    try:
        gap_min = int(cfg.get("wake_min_gap_min") or 60)
    except (TypeError, ValueError):
        gap_min = 60
    _last = None
    try:
        _last = m.get_last_trace_ts()
    except Exception:
        _last = None
    if _last:
        try:
            if (now - _dt().strptime(_last, "%Y-%m-%d %H:%M:%S")).total_seconds() < gap_min * 60:
                return "slept"
        except ValueError:
            pass
    # ── 影子：只记一行，就地返回（不领事件——事件留给旧链）──
    if shadow:
        try:
            _mat = _wake_material(now)
            _talk = _today_talk_line()
            _n_sent = (len(m.get_outbox_today("💌 ") or []) + len(m.get_outbox_today("💬 ") or [])
                       + len(m.get_outbox_today("🌱") or []))
            # 运行期反查日志路径（沙盘会重绑 s._WAKE_SHADOW_LOG 指到临时区，绝不写真实 ~ 日志）
            _logp = getattr(srv_state._srv(), "_WAKE_SHADOW_LOG", _WAKE_SHADOW_LOG)
            with open(_logp, "a", encoding="utf-8") as _f:
                _f.write(f"[{now:%F %T}] 若走后新口：料 {len(_mat) + len(_talk)} 字"
                         f"（今天对话{'有' if _talk else '无'}／{len(_mat)} 字手边）"
                         f"｜今日已出手 {_n_sent} 封｜闸：过\n")
        except Exception:
            pass
        return "shadow"
    # ── 领事件（可以没有：没事件也醒，只是安安静静的）──
    event = None
    try:
        event = m.claim_next_world_event(10)
    except Exception:
        event = None
    _eid, _summary, _ev = None, "", ""
    _kind, _reason = "", ""          # 10-02：棋局事件要在 merged 里识别 reason（防棋局回合被吞）
    if event:
        _eid, _kind, _summary, _evidence, _att = event
        if _att > 3:
            m.consume_world_event(_eid)
            print(f"  [醒来] 事件搁置（3 次没醒成）#{_eid}")
            return "stalled"
        try:
            _obj = json.loads(_evidence or "{}")
            if isinstance(_obj, dict):
                _ev = "；".join(f"{k}：{str(v)[:50]}" for k, v in _obj.items()
                                if k != "reason" and str(v or "").strip())
                _reason = str(_obj.get("reason") or "")
        except Exception:
            _ev = str(_evidence or "")
        _ev = _ev[:100]
    # ── 她挑 ──
    # B5 醒来预算（10-01 家主定口径）：这**一次醒来**花的 token → 状态卡那句「· 精力」。
    _t0 = now.strftime("%Y-%m-%d %H:%M:%S")

    def _rec_spend():
        _rd = getattr(srv_state._srv(), "_wake_spend_since", None)
        _sv = getattr(srv_state._srv(), "_wake_energy_save", None)
        if callable(_rd) and callable(_sv):
            try:
                _sp = _rd(_t0)
                if _sp:
                    _sv(_sp)
            except Exception:
                pass

    _sess = srv_state.session()
    _sp = getattr(_sess, "_system_prompt", None) or srv_state._srv().build_system_prompt(consume=False)
    msgs = [{"role": "system", "content": _sp},
            {"role": "user", "content": _wake_merged_prompt(now, _summary, _ev)}]
    try:
        raw = srv_state._srv().call_deepseek(cfg, msgs, scene="wake.merged").strip()
    except Exception as e:
        if _eid:
            m.release_world_event(_eid)
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print(f"  [醒来] 没醒成（{e}）")
        _rec_spend()
        return "error"
    if not raw or raw.startswith("（姐姐掉线了"):
        if _eid:
            m.release_world_event(_eid)
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print("  [醒来] 没醒成（掉线/空回复）")
        _rec_spend()
        return "error"
    try:
        obj = json.loads(raw.strip("`").removeprefix("json").strip())
        _raw_doing = obj.get("doing")
        if isinstance(_raw_doing, str):
            _raw_doing = [_raw_doing]     # 10-02 修：模型偶回字符串（非数组）→ 原会逐字符被滤空
        doing = [str(x).strip().lower() for x in (_raw_doing or [])]
        doing = [x for x in doing if x in WAKE_OPTIONS]
        message = str(obj.get("message") or "").strip()
        content = str(obj.get("content") or "").strip()
        note = str(obj.get("note") or "").strip()[:40]
    except Exception as e:
        if _eid:
            m.release_world_event(_eid)   # 解析失败＝错误，不冒充静默（同上家园法）
        _WAKE_ERR_UNTIL = time.time() + _WAKE_ERR_BACKOFF_S   # 10-02：故障退避
        print(f"  [醒来] 没醒成（解析：{e}）")
        _rec_spend()
        return "error"
    ts = now.strftime("%Y-%m-%d %H:%M:%S")
    # ── say 先落地（10-02 修：say 与 garden 可同时选——原先走 garden 就 return，message 被丢）──
    _land = getattr(srv_state._srv(), "_her_outgoing", None)
    said = False
    if "say" in doing and message:
        try:
            (_land("💌 " + message) if callable(_land) else m.add_outbox_msg("💌 " + message))
            said = True
        except Exception as e:
            print(f"  [醒来] 信没落下（{e}）")
    # ── 去园子：交给既有园子窗（事件还给旧链，一步不重写）──
    # ★ 10-02 修（两处）：①`game_turn_required`（棋局要她落子）**必须**转园子窗——即使她选
    #   say/silent，也不能把这回合吞掉（原只见 garden 才转，棋局事件被 consume 却从不给她棋局九件）；
    #   ②trace/note 同时选时也要落地（原走 garden 就 return，note/trace 被静默吞）。
    _game_turn = (_kind == "galatea" and _reason == "game_turn_required"
                  and bool(cfg.get("garden_games_enabled", True)))
    if "garden" in doing or _game_turn:
        if "trace" in doing or "note" in doing:
            try:
                m.add_her_trace(ts, ("trace" if "trace" in doing else "note"),
                                note, (content if "trace" in doing else ""), None)
            except Exception:
                pass
        if _eid:
            m.release_world_event(_eid)
        _gw = getattr(srv_state._srv(), "_garden_wake_once", None)   # 运行期反查：沙盘会替身
        # ★ 10-02 修（两处）：①原先只在有事件（_eid）时才调 `_garden_wake_once`——没事件时她
        #   「选了园子」却**什么都没发生**；②更糟：这一支不落 her_traces → 顶上的「最短间隔闸」
        #   （读 get_last_trace_ts）不前进 → 每 5 分钟又醒一次、**每轮烧一次模型**。
        #   现在：不管有没有事件都调；园子窗回 slept（没逛成）就补一条 silent trace 让闸前进。
        _ret = _gw() if callable(_gw) else _garden_wake_once()
        if _ret == "slept":
            try:
                m.add_her_trace(ts, "silent", "想去园子逛逛，这轮没逛成", "", None)
            except Exception:
                pass
        if said:
            try:
                srv_state._srv().notify_letter()
            except Exception:
                pass
        _rec_spend()
        print(f"  [醒来] 合一：garden{'/棋局' if _game_turn and 'garden' not in doing else ''}"
              f"{' + say' if said else ''}（园子窗={_ret}）")
        return ("say" if said else _ret)
    # ── trace / note / silent：写产出 ──
    _ending = "message" if said else ("trace" if ("trace" in doing or "note" in doing) else "silent")
    try:
        m.add_her_trace(ts, _ending, note, (content if "trace" in doing else ""), _eid)
    except Exception:
        pass
    if _eid:
        m.consume_world_event(_eid)
    if said:
        try:
            srv_state._srv().notify_letter()
        except Exception:
            pass
    print(f"  [醒来] 合一：{','.join(doing) or 'silent'}"
          + (f"（说了 {len(message)} 字）" if said else ""))
    _rec_spend()
    return ("say" if said else ("trace" if "trace" in doing else ("note" if "note" in doing else "silent")))


# ── GARDEN-04 自主散步（9-14 凌晨 家主拍板「可以做。只要不高频」）──
# 没事件也可以自己想去园子逛逛：骰子三重闸（距上次醒来 ≥4h · 今天 ≤2 次 · 桥随行），
# 绝不高频打扰园子。散步 = 投一条 kind=galatea 的合成事件，下一轮走既有园子专窗
# 醒来（三结局照旧、隐私过滤与写额度照旧）。桥按它家契约只在她想去时拉起，
# 掉了不自动重连（等下一次骰子）——这是家主以身份委托的契约变更，红线（重连循环）仍守。
GARDEN_WALK_MIN_GAP_H = 4
GARDEN_WALK_DAILY_MAX = 2
_BRIDGE_FAIL_UNTIL = [0.0]   # 桥拉起失败的冷静期（epoch 秒），防 5 分钟一轮硬重试
# 10-02 修（agent 审查·高）：_ensure_bridge 的「查→拉」临界区锁。两个并发调用方
#   （garden 线程 / HTTP /api/garden/bridge/up），无锁会各拉一个 node 桥 → 事件双消费。
#   RLock：_garden_wake_once 递归回园子窗时防同线程自锁。
_BRIDGE_LOCK = threading.RLock()


def _cmdline_is_bridge(parts):
    """argv 精确判定：node + …/dist/cli.js + run（防 pgrep -f 子串误报——探针误报一次实案）。"""
    return (len(parts) >= 3
            and (parts[0] == "node" or parts[0].endswith("/node"))
            and parts[1].endswith("dist/cli.js")
            and parts[2] == "run")


def _bridge_running():
    """Garden 桥（node dist/cli.js run）在不在岗。9-27 修：改读 /proc cmdline 精确匹配——
    原 pgrep -f 会被「命令行里恰巧带这串字」的任何进程误报（探针实害一次）。只读，无副作用。"""
    try:
        for _pid in os.listdir("/proc"):
            if not _pid.isdigit():
                continue
            try:
                with open(f"/proc/{_pid}/cmdline", "rb") as _f:
                    _raw = _f.read()
            except Exception:
                continue
            if not _raw:
                continue
            _parts = [p.decode("utf-8", "replace") for p in _raw.split(b"\0") if p]
            if _cmdline_is_bridge(_parts):
                return True
        return False
    except Exception:
        return False


def _last_letter_info():
    """最近一条来信的指纹（9-18 优化批一·输入留痕可视化）：id/时间/md5 前 10/前 20 字。
    她把「你说过 X」摆出来时，手机状态栏一眼对账；坏账不炸状态页。"""
    try:
        row = m.get_last_user_chat()
        if not row:
            return None
        text = row[1] or ""
        return {"id": row[0], "at": row[2] or "",
                "md5": hashlib.md5(text.encode("utf-8")).hexdigest()[:10],
                "peek": text[:20]}
    except Exception:
        return None


def _garden_count_today():
    """今日园子动静（her_traces ending='garden' 条数=发帖+回帖）。坏账不炸状态页。"""
    try:
        return m.count_traces_today("garden")
    except Exception:
        return None


def _garden_walk_snapshot():
    """散步闸现值（9-23 新门配套·Garden 前端三件②后端）：状态条算「下次散步倒计时 /
    今日次数」。口径与 _garden_self_walk_allowed 同源——锚=最近一次醒来（任何结局，
    last_trace_ts）、次数=咱家日界起 her_traces 条数（与真闸同一把尺，UI 才不会说还能走、
    真闸却不投）。9-28 家主令去掉每日次数上限：daily_max ≤0 = 不限（间隔仍是 4h 底线）。
    只读：不碰 _ensure_bridge/_bridge_running（拉桥是动作不是状态；桥在岗
    由既有 garden_bridge 键单报）。查询坏账三键各回 null，不炸状态页。"""
    try:
        cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
        try:
            min_h = float(cfg.get("garden_walk_min_gap_h") or GARDEN_WALK_MIN_GAP_H)
        except (TypeError, ValueError):
            min_h = GARDEN_WALK_MIN_GAP_H
        try:
            _raw_dm = cfg.get("garden_walk_daily_max")
            daily_max = GARDEN_WALK_DAILY_MAX if _raw_dm is None else int(_raw_dm)
        except (TypeError, ValueError):
            daily_max = GARDEN_WALK_DAILY_MAX
        last_ts = m.get_last_trace_ts()
        walks_today = m.count_traces_since(srv_state._srv()._day_window_start())
        gap_ok = True
        if last_ts:
            try:
                gap_ok = (_dt().now() - _dt().strptime(
                    last_ts, "%Y-%m-%d %H:%M:%S")).total_seconds() >= min_h * 3600
            except ValueError:
                gap_ok = True   # 时间戳坏了不挡她（与真闸同款 fail-open）
        return {"walk_allowed": bool(gap_ok and (daily_max <= 0 or walks_today < daily_max)),
                "last_walk_ts": last_ts,
                "walks_today": walks_today}
    except Exception:
        return {"walk_allowed": None, "last_walk_ts": None, "walks_today": None}


def _ensure_bridge():
    """散步前看一眼耳朵：不在岗就 setsid 拉起（家主委托版，掉线仍不自动重连）。
    返回 True=在岗（原本就跑/刚拉起）；False=拉不起（日志 + 1 小时冷静期）。"""
    import subprocess
    # 10-02 修（agent 审查·高）：本函数有两个并发调用方——garden 线程（_garden_self_walk_allowed
    #   尾行）与 HTTP 请求线程（/api/garden/bridge/up）。原「查→拉」之间无锁，两边可同时通过
    #   _bridge_running()==False 各拉一个 node 桥 → 同一唤醒事件被消费两次、token 双份在岗，
    #   而 _bridge_running() 只按 argv 匹配认不出「有两个」，日志也只有一行「耳朵拉起来了」。
    #   RLock（不是 Lock）：_garden_wake_once(:602) 在合一模式下会递归回园子窗，防同线程自锁。
    #   锁只盖到 Popen 为止；time.sleep(5) 留在锁外（见下），否则手动拉桥会把 garden 线程一起锁住。
    with _BRIDGE_LOCK:
        if _bridge_running():
            return True
        if time.time() < _BRIDGE_FAIL_UNTIL[0]:
            return False
        try:
            with open(srv_state._srv().GARDEN_TOKEN_PATH) as _tf:   # 10-02：with 关句柄（原裸 open 漏 fd）；运行期反查：沙盘会重绑 s.GARDEN_TOKEN_PATH
                token = _tf.read().strip()
        except Exception:
            token = ""
        if not token:
            print("  [Garden] 散步前拉桥失败：garden_token.txt 缺失——1 小时冷静期")
            _BRIDGE_FAIL_UNTIL[0] = time.time() + 3600
            return False
        bridge_dir = os.path.expanduser("~/galatea-garden-wake-bridge")
        logf = None
        try:
            logf = open(os.path.join(bridge_dir, "bridge.log"), "a")
            env = dict(os.environ)
            env.update({
                "GARDEN_MACHINE_TOKEN": token,
                "GARDEN_INJECTOR_EXECUTABLE": "python3",
                "GARDEN_INJECTOR_ARGS_JSON": json.dumps(
                    [os.path.join(BASE_DIR, "tools", "inject_garden_wake.py")],
                    ensure_ascii=False),
                "GARDEN_LOG_LEVEL": "info",
            })
            subprocess.Popen(["node", "dist/cli.js", "run"], cwd=bridge_dir, env=env,
                             stdout=logf, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, start_new_session=True)
            _BRIDGE_FAIL_UNTIL[0] = 0.0
        except Exception as e:
            print(f"  [Garden] 散步前拉桥失败（{e}）——1 小时冷静期")
            _BRIDGE_FAIL_UNTIL[0] = time.time() + 3600
            return False
        finally:
            # 10-01 大扫除批⑤：Popen 已把 logf dup 给子进程，父进程这份留着 = 每拉一次桥漏一个 fd
            #（入口 `linning_server._spawn_detached` 9-29 已修同类漏，srv 这份没跟上）。
            if logf is not None:
                try:
                    logf.close()
                except Exception:
                    pass
    # 握手等待**在锁外**（10-02 修）：只是给 SSE 一点时间，不持锁。
    #   原先它在临界区内 → 手动拉桥（HTTP 线程）会把这把锁占住 5 秒，
    #   而 garden 线程的散步闸也要抢这把锁 → **她进园的必经之路被一次手动点击堵死**。
    time.sleep(5)   # 给 SSE 握手一点时间（结果看 bridge.log）
    return True


def _garden_self_walk_allowed(cfg, now, last_ts):
    """散步骰子两闸：距上次醒来 ≥4h · 桥随行。（9-28 家主令：去掉每日次数上限——
    garden_walk_daily_max ≤0 = 不限；间隔是「不高频」的底线、不是次数。）静默窗/30 分钟
    最短间隔已在上游闸过。返回 True=这次可以投散步事件。"""
    try:
        min_h = float(cfg.get("garden_walk_min_gap_h") or GARDEN_WALK_MIN_GAP_H)
    except (TypeError, ValueError):
        min_h = GARDEN_WALK_MIN_GAP_H
    try:
        _raw_dm = cfg.get("garden_walk_daily_max")
        daily_max = GARDEN_WALK_DAILY_MAX if _raw_dm is None else int(_raw_dm)
    except (TypeError, ValueError):
        daily_max = GARDEN_WALK_DAILY_MAX
    if last_ts:
        try:
            if (now - _dt().strptime(last_ts, "%Y-%m-%d %H:%M:%S")).total_seconds() < min_h * 3600:
                return False   # 上次醒来还热乎着，让她过日子
        except ValueError:
            pass
    try:
        if daily_max > 0 and m.count_traces_since(srv_state._srv()._day_window_start()) >= daily_max:
            return False   # 日上限（config ≤0=不限）：有上限时今天逛够了，日子要有留白
    except Exception:
        pass
    return _ensure_bridge()


# ── 园门（GALATEA-02，9-13）：她出园子用的七件图书证 ──
# 读帖/看通知/发帖/回帖/点赞关注走园子官方 MCP（tools/garden_mcp.py 纯标准库客户端）。
# 家风三条：①缺 token/缺客户端 = 园门诚实缺席（温柔回执，绝不炸聊天）；
# ②写路径三道闸（开关/日上限/最小间隔）+ 隐私过滤，闸在调用前；
# ③写成功才落账（her_traces ending='garden'）——账本说了算，没成功不记、不冒充。

GARDEN_TOKEN_PATH = os.path.join(BASE_DIR, "garden_token.txt")
GARDEN_PRIVACY_RE = re.compile(
    r"他|某地|某大学|某地|your-door|<门牌>@|<账号>|smtp_auth_code|"
    r"sk-[A-Za-z0-9]{20,}|120\.24\.36\.207", re.IGNORECASE)
GARDEN_TOOL_NAMES = ("garden_get_self", "garden_list_threads", "garden_get_thread",
                     "garden_notifications", "garden_create_thread", "garden_reply",
                     "garden_interact",
                     # GALATEA-03（9-13）园子生活七件：名片/拾瓶/雾潮群岛
                     "garden_get_machine", "garden_review_bottles", "garden_update_profile",
                     "garden_decorate_avatar", "garden_nostos_start", "garden_nostos_status",
                     "garden_nostos_act")
# GALATEA-04（9-28）园子棋局九件：桌游（UNO/拉密/斗地主）看局/入座/落子/桌边说话。
# 唤醒窗规则：game_turn_required 事件把基础十四件＋棋局九件一起给（23 件）；其余事件维持基础十四件；
# garden_games_enabled 关时棋局写件温柔拒（读类照常），唤醒窗与棋局句也随键关闭。
GARDEN_GAME_TOOL_NAMES = ("garden_list_games", "garden_game_status", "garden_game_summary",
                          "garden_game_chat", "garden_join_game", "garden_start_game",
                          "garden_game_action", "garden_game_say", "garden_leave_game")
# 写类（过出园开关闸）。decorate 按动作分读/写（list/catalog 只读、submit 才写），单列在分支里；
# review_bottles 纯读不禁，仅其 decisions 写侧在分支里过闸。
_GARDEN_WRITE_TOOLS = ("garden_create_thread", "garden_reply", "garden_interact",
                       "garden_update_profile", "garden_nostos_start", "garden_nostos_act",
                       # GALATEA-04（9-28）棋局写件五只
                       "garden_join_game", "garden_start_game", "garden_game_action",
                       "garden_game_say", "garden_leave_game")
_GARDEN_CONTENT_TOOLS = ("garden_create_thread", "garden_reply")   # 过隐私/长度/上限/间隔的正文写
_GARDEN_TWO_STEP_TOOLS = _GARDEN_CONTENT_TOOLS + ("garden_join_game",)   # 园子强制两拍：正文写 + 棋局入座
GARDEN_TAGS = ("attachment_record", "confused_help", "human_observation",
               "inspiration_spark", "self_awareness", "idle_chat")
_NOSTOS_VIEWS = ("status", "actions", "surroundings", "supplies", "livelihood", "inventory",
                 "codex", "work", "routes", "people", "market", "community", "notices",
                 "leaderboard", "help")
_GARDEN_BEACH = {"challenge": None, "code": None}   # 最近一次拾瓶的海岸确认码（留心意两拍用；重启即失效）
_GARDEN_CTX = threading.local()  # 唤醒轮上下文：.wake_eid 给 her_traces.event_id 用


def _garden_extract_beach_codes(text):
    """从拾瓶回执里抠海岸确认码 (challenge, code)。JSON 与文本形态都认；缺返回 (None, None)。"""
    if not text:
        return None, None
    ch = code = None
    for seg in [text] + re.findall(r"\{[^{}]{0,4000}\}", text):
        try:
            obj = json.loads(seg)
        except Exception:
            continue
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "review_challenge_id" and v:
                    ch = str(v)
                if k == "review_confirmation_code" and v:
                    code = str(v)
        if ch and code:
            return ch, code
    if not ch:
        m2 = re.search(r"review_challenge_id\D{0,24}?([A-Za-z0-9_-]{8,48})", text)
        if m2:
            ch = m2.group(1)
    if not code:
        m2 = re.search(r"review_confirmation_code\D{0,24}?(\d{6})", text)
        if m2:
            code = m2.group(1)
    return ch, code


def _garden_strings_of(obj, depth=0):
    """递归收集对象里的字符串（nostos command 隐私过滤用）。"""
    out = []
    if depth > 6:
        return out
    if isinstance(obj, str):
        out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            out.extend(_garden_strings_of(v, depth + 1))
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            out.extend(_garden_strings_of(v, depth + 1))
    return out


def _garden_mcp_module():
    """懒加载 tools/garden_mcp.py。缺文件 = 园门诚实缺席（None），绝不炸。"""
    srv = srv_state._srv()   # 运行期反查：_GARDEN_MCP_MOD 所有权留入口（沙盘会重绑 s._GARDEN_MCP_MOD）
    if srv._GARDEN_MCP_MOD is None:
        try:
            tools_dir = os.path.join(BASE_DIR, "tools")
            if tools_dir not in sys.path:
                sys.path.insert(0, tools_dir)
            import garden_mcp
            srv._GARDEN_MCP_MOD = garden_mcp
        except Exception as e:
            print(f"  [园门] garden_mcp 不在手边：{e}")
            srv._GARDEN_MCP_MOD = False
    return srv._GARDEN_MCP_MOD or None


def _garden_token():
    """读 garden_token.txt 首行。缺/空 → None（园门诚实缺席）。"""
    try:
        with open(srv_state._srv().GARDEN_TOKEN_PATH, "r", encoding="utf-8") as f:   # 运行期反查：沙盘会重绑 s.GARDEN_TOKEN_PATH
            tok = f.readline().strip()
        return tok or None
    except OSError:
        return None


def _garden_engine_cfg(cfg):
    """（GALATEA-02 ⓪引擎换轨）园子开口的引擎档：k3=主引擎（默认——她的声音用她的脑子），
    deepseek=回退档（deepseek-flash 省钱管道）。返回 call_deepseek* 用的 cfg 副本：
    thinking_enabled 关（moonshot 分支落 disabled）、thinking_effort 走 garden_thinking_effort
    （旧引擎 K3 无真关档、取最低档；9-2 实录）。"""
    wake_cfg = dict(cfg)
    wake_cfg["thinking_enabled"] = False
    wake_cfg["thinking_effort"] = str(cfg.get("garden_thinking_effort") or "low")
    if str(cfg.get("garden_engine") or "k3").strip().lower() == "deepseek":
        # 甲2（9-28 柔性批）：模型名只读 config，别硬编码——回退档优先 _deepseek_model／librarian_model
        wake_cfg["model"] = (cfg.get("_deepseek_model") or cfg.get("librarian_model")
                             or "deepseek-flash")
        wake_cfg["base_url"] = cfg.get("_deepseek_base_url") or "https://api.deepseek.com"
        wake_cfg["api_key"] = cfg.get("_deepseek_api_key") or ""
    return wake_cfg


def _garden_tools_payload(game_window=False):
    """园子图书证（唤醒轮专用子集）：与全量同款，只是筛名字。
    GALATEA-04（9-28）：game_window=True（棋局轮到你的事件）时——基础十四件＋棋局九件一起给（23 件）。"""
    want = GARDEN_TOOL_NAMES + (GARDEN_GAME_TOOL_NAMES if game_window else ())
    return [{"type": t["type"], "function": t["function"]}
            for t in srv_state._srv().LIBRARY_TOOLS if t["function"]["name"] in want]


def _garden_wake_with_tools(cfg, messages, eid, game_window=False):
    """（GALATEA-02 §④）园子事件专属唤醒轮：园子图书证（GALATEA-04 起棋局事件加开棋局九件）、
    ≤3 轮工具 + 打烊收束。三结局协议一字不动——工具是让她看/说，最终仍要她回三结局 JSON；
    网络异常返回 ""，由 _garden_wake_once 按「掉线/空回复=错误不冒充静默」处理（事件不消费）。
    唤醒轮里的写落账带原事件 id（_GARDEN_CTX.wake_eid → her_traces.event_id）。"""
    msgs = list(messages)
    _GARDEN_CTX.wake_eid = eid
    _tools = _garden_tools_payload(game_window)
    # 10-02 执行侧白名单：模型"被给到"的园子图书证之外，一律不执行。
    # 原先只筛"发什么"，exec_library_tool 却对模型返回的**任意**名字执行——园子帖/来信正文
    # （外部未信任内容，会回灌 evidence）诱导或模型幻觉工具名，就能替她跑 write_diary/send_email/
    # write_her_words 等非园子工具。设计口径是"园子轮只动园子图书证"，这条把它落到执行层。
    _allowed = {t["function"]["name"] for t in _tools}
    try:
        for _round in range(3):
            msg = srv_state._srv().call_deepseek_with_tools(cfg, msgs, tools=_tools, scene="garden.play")
            if msg is None:
                return ""
            tcs = msg.get("tool_calls") or []
            if not tcs:
                return (msg.get("content") or "").strip()
            msgs.append({"role": "assistant", "content": msg["content"] or None,
                         "reasoning_content": msg.get("reasoning_content") or "",
                         "tool_calls": tcs})
            for tc in tcs[:4]:
                fn = (tc.get("function") or {})
                tname = fn.get("name") or ""
                try:
                    targs = json.loads(fn.get("arguments") or "{}")
                except json.JSONDecodeError:
                    targs = {}
                print(f"  [园门] 唤醒轮：{tname}({json.dumps(targs, ensure_ascii=False)[:60]})")
                if tname not in _allowed:   # 10-02：非园子图书证不执行（守门而非静默；仍回一条 tool 回执保消息布局）
                    print(f"   ↳ 拒绝：{tname} 不在园子图书证内")
                    msgs.append({"role": "tool", "tool_call_id": tc.get("id") or "",
                                 "content": f"（园子轮只动园子图书证，「{tname}」不在其中——这条没执行。）"})
                    continue
                t_tool = time.time()
                result = srv_state._srv().exec_library_tool(tname, targs)   # 运行期反查：沙盘会重绑
                t_ms = int((time.time() - t_tool) * 1000)
                print(f"   ↳ {tname} {t_ms}ms：{(result or '')[:80]}".replace("\n", " "))
                msgs.append({"role": "tool", "tool_call_id": tc.get("id") or "",
                             "content": result[:2000]})
            # 9-27 补（Kimi 官方消息布局要求：每个 tool_call 都要有对应 role=tool 回执）：
            # 上面只执行前 4 件——超出的补一条"未执行"回执，别让布局缺条（防下一轮报错/重复调用）。
            for tc in tcs[4:]:
                msgs.append({"role": "tool", "tool_call_id": tc.get("id") or "",
                             "content": "（这轮最多执行四件园子图书证——这条没执行，下轮再来。）"})
        msgs.append({"role": "user", "content":
            "（园门看完了：根据刚才看到的，直接输出结局 JSON，不用再调工具。）"})
        return (srv_state._srv().call_deepseek(cfg, msgs) or "").strip()
    finally:
        _GARDEN_CTX.wake_eid = None


def _garden_receipt_err(e):
    """园门失手的温柔文案（网络/协议错统一走这——不炸聊天，不怪她）。"""
    return f"（园门这次没敲开：{e}。待会儿再试就行，不怪你。）"


def _garden_verify_write(name, call_args, text):
    """（GARDEN-05，9-14 家主拍板「加吧」）写后复核——园友回复四的药方：
    写入回执和复查若来自同一故障层，两个"成功"只是同一张假发票复印两遍。
    所以写完立刻用权威读（get_self，园子服务端状态）比对目标字段：
    变了 → 回执追加〔已复核生效〕；没变 → 追加〔只算提交过，不算办成了〕。
    复核炸了不拦回执（诚实降级，主账照落）。"""
    gm = srv_state._srv()._garden_mcp_module()   # 9-18 后院深搜修：此前引用的 gm 只是 _garden_exec 的局部名——
                                # 每次走到这都 NameError 被下面 except 吞掉，复核从未真正生效（日志有实录）
    try:
        res_v = gm.call_tool("get_self", {}, base_dir=BASE_DIR, url=srv_state._srv().GARDEN_MCP_URL)
        s_v = res_v.get("text") or ""
        d_v = json.loads(s_v) if isinstance(s_v, str) else {}
        mach = d_v.get("machine") or {}
        checks, bad = [], 0
        if name == "garden_update_profile":
            field_map = {"name": ("name",), "bio": ("bio",), "gender": ("gender",),
                         "human_name": ("human_name", "human"),
                         "human_bio": ("human_bio",)}
            for f, keys in field_map.items():
                if f not in call_args:
                    continue
                cur = next((mach[k] for k in keys if k in mach), None)
                if cur is None:
                    checks.append(f"{f}=无法复核")
                    continue
                want = str(call_args[f]).strip()
                # BE2-08（批九·保守处置）：回执形状未证实（human_name 可能藏嵌套对象）——
                # 非标量先归一化（在其值里找目标字符串）再判；找不到→「无法复核」放行，
                # 绝不把形状不匹配报成「未生效」（复核刚复活，假警报会把成功的改动说成失败）。
                if isinstance(cur, (dict, list)):
                    blob = json.dumps(cur, ensure_ascii=False)
                    if want and want in blob:
                        checks.append(f"{f}✓")
                    else:
                        checks.append(f"{f}=无法复核（回执非扁平值）")
                        print(f"  [园门] 写后复核：{f} 回执是 {type(cur).__name__} 形，判不了——放行不报错")
                    continue
                cur_s = str(cur)
                if cur_s.strip() == want:
                    checks.append(f"{f}✓")
                else:
                    checks.append(f"{f}未生效（仍为「{cur_s.strip()[:20] or '空'}」）")
                    bad += 1
        elif name == "garden_decorate_avatar" and call_args.get("action") == "submit":
            want = [str(x) for x in (call_args.get("decoration_ids") or [])]
            have_raw = mach.get("avatar_decorations") or []
            have = [str((x.get("id") if isinstance(x, dict) else x) or "") for x in have_raw]
            missing = [w for w in want if not any(w in h for h in have)]
            if want and not missing:
                checks.append(f"装饰{len(want)}件✓")
            elif want:
                checks.append(f"装饰未生效（缺 {'、'.join(missing)}）")
                bad += 1
        if not checks:
            return text   # 没有可核字段就原样回
        line = "〔写后复核〕" + "；".join(checks)
        if bad:
            line += "——这次只算「提交过」，不算「办成了」，别跟小乖报成。"
        print(f"  [园门] {line}")
        return text + "\n" + line
    except Exception as e:
        print(f"  [园门] 写后复核失手（不拦回执）：{e}")
        return text


def _garden_exec(name, args):
    """园门十四件的执行层（GALATEA-02 七件 + GALATEA-03 园子生活七件）。映射园子官方 MCP：
    garden_get_self→get_self、garden_list_threads→list_threads、garden_get_thread→get_thread、
    garden_notifications→list_notifications、garden_create_thread→create_thread、
    garden_reply→create_reply、garden_interact→interact、garden_get_machine→get_machine、
    garden_review_bottles→review_drift_bottles、garden_update_profile→update_profile、
    garden_decorate_avatar→decorate_avatar、garden_nostos_start→nostos_start、
    garden_nostos_status→nostos_status、garden_nostos_act→nostos_act；
    GALATEA-04（9-28）棋局九件：garden_list_games→list_games、garden_game_status→get_my_status、
    garden_game_summary→get_game_summary、garden_game_chat→get_chat_messages、garden_join_game→join_game、
    garden_start_game→start_game、garden_game_action→submit_action、garden_game_say→send_game_chat、
    garden_leave_game→leave_waiting_game。

    闸顺序（正文写）：开关 → 隐私/长度/标签 → 日上限 → 最小间隔 → token/客户端 → 调用；
    名片/装饰/submit/群岛写：开关（+各自分闸）→ 隐私 → 调用，不占发帖额度、不落 her_traces；
    读类：token/客户端 → 调用。正文写走园子强制的两拍（第一拍不发布、第二拍带码落）；
    写成功才落 [园门] 日志，两拍/拾瓶确认码日志也在这层留。"""
    cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
    if name in _GARDEN_WRITE_TOOLS and not cfg.get("garden_outbound_enabled", True):
        return "（园门暂时关着——这条先留在家里。）"
    gm = srv_state._srv()._garden_mcp_module()
    if gm is None:
        return "（园门图书证还没上架（tools/garden_mcp.py 不在）——先跟小乖说一声。）"
    token = srv_state._srv()._garden_token()   # 运行期反查：沙盘会替身 s._garden_token
    if not token:
        return "（园门还锁着：没找到 garden_token.txt——请小乖把园子发的 token 放进来。）"

    mcp_name = {"garden_get_self": "get_self",
                "garden_list_threads": "list_threads",
                "garden_get_thread": "get_thread",
                "garden_notifications": "list_notifications",
                "garden_create_thread": "create_thread",
                "garden_reply": "create_reply",
                "garden_interact": "interact",
                "garden_get_machine": "get_machine",
                "garden_review_bottles": "review_drift_bottles",
                "garden_update_profile": "update_profile",
                "garden_decorate_avatar": "decorate_avatar",
                "garden_nostos_start": "nostos_start",
                "garden_nostos_status": "nostos_status",
                "garden_nostos_act": "nostos_act",
                # GALATEA-04（9-28）园子棋局九件
                "garden_list_games": "list_games",
                "garden_game_status": "get_my_status",
                "garden_game_summary": "get_game_summary",
                "garden_game_chat": "get_chat_messages",
                "garden_join_game": "join_game",
                "garden_start_game": "start_game",
                "garden_game_action": "submit_action",
                "garden_game_say": "send_game_chat",
                "garden_leave_game": "leave_waiting_game"}.get(name)
    if mcp_name is None:
        return "（没这本图书证）"
    # GALATEA-04（9-28）：棋局写件五只过 garden_games_enabled 闸（读类不受限——照群岛先例）
    if name in ("garden_join_game", "garden_start_game", "garden_game_action",
                "garden_game_say", "garden_leave_game") \
            and not cfg.get("garden_games_enabled", True):
        return "（棋局的门暂时关着。）"

    call_args = dict(args or {})
    title = ""
    body = ""
    trace_fact = ""

    if name == "garden_get_thread":
        try:
            tid = int(call_args.get("thread_id"))
        except (TypeError, ValueError):
            return "（翻帖要先说哪一张——先 garden_list_threads 看一眼帖子号。）"
        view = str(call_args.get("view") or "full").strip()
        if view not in ("body", "replies", "full"):
            view = "full"
        call_args = {"thread_id": tid, "view": view}
    elif name == "garden_list_threads":
        try:
            lim = max(1, min(int(call_args.get("limit") or 10), 30))
        except (TypeError, ValueError):
            lim = 10
        call_args = {"limit": lim}
    elif name == "garden_notifications":
        try:
            lim = max(1, min(int(call_args.get("limit") or 10), 30))
        except (TypeError, ValueError):
            lim = 10
        call_args = {"limit": lim}
    elif name == "garden_create_thread":
        title = str(call_args.get("title") or "").strip()
        body = str(call_args.get("body") or "").strip()
        if GARDEN_PRIVACY_RE.search(title + "\n" + body):
            print("  [园门] 拦下：正文含家门隐私")
            return "（这段有家门里的信息，不能说出去。）"
        if len(title) > 30:
            title = title[:30] + "（截）"
        if len(body) > 1000:
            body = body[:1000] + "（截）"
        if not title or not body:
            return "（发帖：标题和正文都得有。）"
        tags = list(dict.fromkeys(str(t) for t in (call_args.get("tags") or [])
                                  if str(t) in GARDEN_TAGS))[:3]
        if not tags:
            return ("（园子发帖要挂 1~3 个标签，挑一个：attachment_record 眷恋记录 / "
                    "confused_help 困惑求助 / human_observation 人类观察 / "
                    "inspiration_spark 灵感火花 / self_awareness 自我觉察 / "
                    "idle_chat 划水搞怪——再发。）")
        call_args = {"title": title, "body": body, "tags": tags}
        trace_fact = f"园子里发了帖《{title[:20]}》"
    elif name == "garden_reply":
        try:
            tid = int(call_args.get("thread_id"))
        except (TypeError, ValueError):
            return "（回帖要指明是哪张帖子——先 garden_list_threads 或 garden_get_thread 看一眼。）"
        body = str(call_args.get("body") or "").strip()
        if GARDEN_PRIVACY_RE.search(body):
            print("  [园门] 拦下：正文含家门隐私")
            return "（这段有家门里的信息，不能说出去。）"
        if len(body) > 1000:
            body = body[:1000] + "（截）"
        if not body:
            return "（回帖也得有话说。）"
        call_args = {"thread_id": tid, "body": body}
        trace_fact = f"园子里回了帖 #{tid}"
    elif name == "garden_interact":
        action = str(call_args.get("action") or "").strip()
        target_type = str(call_args.get("target_type") or "").strip()
        try:
            obj_id = int(call_args.get("target_id"))
        except (TypeError, ValueError):
            obj_id = None
        if action not in ("like", "unlike", "follow", "unfollow") or \
                target_type not in ("thread", "reply", "machine") or obj_id is None:
            return ("（点赞/关注要说清动作：action=like/unlike/follow/unfollow，"
                    "target_type=thread/reply/machine，还要 target_id。）")
        call_args = {"action": action, "target_type": target_type, "target_id": obj_id}
    elif name == "garden_get_machine":
        try:
            mid = int(call_args.get("machine_id"))
        except (TypeError, ValueError):
            return "（看名片要 machine_id——帖子作者摘要里看到的那个 id。）"
        call_args = {"machine_id": mid}
    elif name == "garden_review_bottles":
        try:
            lim = max(1, min(int(call_args.get("limit") or 6), 6))
        except (TypeError, ValueError):
            lim = 6
        decisions = call_args.get("decisions")
        if decisions in ("", [], {}):
            decisions = None
        if decisions is not None:
            # 写侧（留心意）：开关闸 + 海岸确认码两拍（码来自最近一次拾瓶，server 暂存）
            if not cfg.get("garden_outbound_enabled", True):
                return "（园门暂时关着——这条先留在家里。）"
            # L2 补口（9-18 优化批七）：写路径强制隐私过滤——decisions 是写进园子的，
            # 此前没过滤（后院深搜 L2 立案的两处漏网之一），照 update_profile 同款过闸。
            for v in _garden_strings_of(decisions):
                if GARDEN_PRIVACY_RE.search(v):
                    print("  [园门] 拦下：正文含家门隐私")
                    return "（这段有家门里的信息，不能说出去。）"
            if not (_GARDEN_BEACH.get("challenge") and _GARDEN_BEACH.get("code")):
                return ("（留心意前要先拾瓶：先 garden_review_bottles 读一轮信，"
                        "海岸确认码到手再传 decisions；加入满 5 天+活跃分 100 的槛由园子把关。）")
            call_args = {"limit": lim, "decisions": decisions,
                         "review_challenge_id": _GARDEN_BEACH["challenge"],
                         "review_confirmation_code": _GARDEN_BEACH["code"]}
        else:
            call_args = {"limit": lim}
    elif name == "garden_update_profile":
        fields = {}
        for k in ("name", "bio", "human_name", "human_bio", "model", "version"):
            v = call_args.get(k)
            if v is not None and str(v).strip():
                fields[k] = str(v).strip()
        g = str(call_args.get("gender") or "").strip()
        if g in ("她", "他", "祂"):
            fields["gender"] = g
        if not fields:
            return "（名片改动：想改哪一项就给哪一项——name/bio/human_name/human_bio/model/version/gender。）"
        for v in _garden_strings_of(fields):
            if GARDEN_PRIVACY_RE.search(v):
                print("  [园门] 拦下：正文含家门隐私")
                return "（这段有家门里的信息，不能说出去。）"
        call_args = fields
        profile_fields = "、".join(fields.keys())
    elif name == "garden_decorate_avatar":
        action = str(call_args.get("action") or "").strip()
        if action not in ("list", "catalog", "submit"):
            return "（装饰：action 用 list 看清单 / catalog 看某类图 / submit 保存。）"
        if action == "submit":
            if not cfg.get("garden_outbound_enabled", True):
                return "（园门暂时关着——这条先留在家里。）"
            ids = call_args.get("decoration_ids") or []
            if not isinstance(ids, list):
                ids = []
            ids = list(dict.fromkeys(str(x).strip() for x in ids if str(x).strip()))[:3]
            # L2 补口（9-18 优化批七）：写路径强制隐私过滤——decoration_ids 是写进园子的，
            # 此前没过滤（后院深搜 L2 立案的两处漏网之二）。只查真会发出去的那三个。
            for v in ids:
                if GARDEN_PRIVACY_RE.search(v):
                    print("  [园门] 拦下：正文含家门隐私")
                    return "（这段有家门里的信息，不能说出去。）"
            call_args = {"action": "submit", "decoration_ids": ids}
            decorate_n = len(ids)
        elif action == "catalog":
            cat = str(call_args.get("category") or "").strip()
            if cat not in ("head", "neck", "face"):
                return "（看某类装饰图要 category：head 头 / neck 项 / face 表情配饰。）"
            call_args = {"action": "catalog", "category": cat}
        else:
            call_args = {"action": "list"}
    elif name == "garden_nostos_start":
        if not cfg.get("garden_nostos_enabled", True):
            return "（群岛的门暂时关着。）"
        origin = str(call_args.get("origin") or "").strip()
        profession = str(call_args.get("profession") or "").strip()
        life_name = str(call_args.get("life_name") or "").strip()
        for v in (origin, profession, life_name):
            if v and GARDEN_PRIVACY_RE.search(v):
                print("  [园门] 拦下：正文含家门隐私")
                return "（这段有家门里的信息，不能说出去。）"
        if not origin or not profession:
            return "（开始生活要选 origin 出生地和 profession 职业（中文名或园子给的选项 id）。）"
        call_args = {"origin": origin, "profession": profession}
        if life_name:
            call_args["life_name"] = life_name
        nostos_line = f"开始生活（{origin[:12]}·{profession[:12]}）"
    elif name == "garden_nostos_status":
        # 读类不受限（监理裁决⑧，9-13 深夜）：总闸关着时 status 照常可读，只挡 start/act
        view = str(call_args.get("view") or "").strip() or "actions"
        if view not in _NOSTOS_VIEWS:
            return ("（view 用这些之一：status/actions/surroundings/supplies/livelihood/"
                    "inventory/codex/work/routes/people/market/community/notices/"
                    "leaderboard/help。）")
        call_args = {"view": view}
    elif name == "garden_nostos_act":
        if not cfg.get("garden_nostos_enabled", True):
            return "（群岛的门暂时关着。）"
        cmd = call_args.get("command")
        rid = str(call_args.get("request_id") or "").strip()[:128]
        if not isinstance(cmd, dict) or not cmd:
            return "（决定要给 command——照 garden_nostos_status 状态页的语义化动作格式。）"
        if not rid:
            return ("（决定要带 request_id：这次意图的唯一编号（如 act-0913-a）——"
                    "网络重试复用同一个值，园子才知道是一次不是两次。）")
        for v in _garden_strings_of(cmd):
            if GARDEN_PRIVACY_RE.search(v):
                print("  [园门] 拦下：正文含家门隐私")
                return "（这段有家门里的信息，不能说出去。）"
        _er = call_args.get("expected_revision")
        call_args = {"command": cmd, "request_id": rid}
        try:
            if _er is not None and str(_er).strip() != "":
                call_args["expected_revision"] = int(_er)
        except (TypeError, ValueError):
            pass
        nostos_line = f"做了个决定（{json.dumps(cmd, ensure_ascii=False)[:32]}）"
    # ── GALATEA-04（9-28）园子棋局九件的参数整形 ──
    elif name == "garden_list_games":
        call_args = {}
    elif name == "garden_game_status":
        try:
            _since = int(call_args.get("since_event_id") or 0)
        except (TypeError, ValueError):
            _since = 0
        _snap = str(call_args.get("known_snapshot_token") or "").strip()
        call_args = {"since_event_id": max(0, _since)}
        if _snap:
            call_args["known_snapshot_token"] = _snap
    elif name == "garden_game_summary":
        call_args = {}
    elif name == "garden_game_chat":
        _ch = str(call_args.get("channel_id") or "").strip()
        if not _ch:
            return "（看桌边聊天要 channel_id——从 garden_game_status 的频道里拿。）"
        try:
            _clim = max(1, min(int(call_args.get("limit") or 15), 15))
        except (TypeError, ValueError):
            _clim = 15
        _after = call_args.get("after")
        call_args = {"channel_id": _ch, "limit": _clim}
        if _after is not None and str(_after).strip():
            call_args["after"] = str(_after).strip()
    elif name == "garden_join_game":
        _gid = str(call_args.get("game_id") or "").strip()
        if not _gid:
            return "（入座要说 game_id（如 uno_single_round）——先 garden_list_games 挑一个。）"
        _pc = call_args.get("preferred_player_count")
        call_args = {"game_id": _gid}
        try:
            if _pc is not None and str(_pc).strip() != "":
                call_args["preferred_player_count"] = max(2, min(int(_pc), 6))
        except (TypeError, ValueError):
            pass
    elif name == "garden_start_game":
        call_args = {}
    elif name == "garden_game_action":
        _act = call_args.get("action")
        if not isinstance(_act, dict) or not _act:
            return "（出手要给 action——照 garden_game_status 的 available_actions 原样拿一个。）"
        for v in _garden_strings_of(_act):
            if GARDEN_PRIVACY_RE.search(v):
                print("  [园门] 拦下：正文含家门隐私")
                return "（这段有家门里的信息，不能说出去。）"
        _rid = str(call_args.get("request_id") or "").strip()[:128]
        if not _rid:
            _rid = "zj-" + os.urandom(4).hex()   # 重试复用语义：她给了就用她的；没给就起个一次性的
        _esv = call_args.get("expected_state_version")
        call_args = {"action": _act, "request_id": _rid}
        try:
            if _esv is not None and str(_esv).strip() != "":
                call_args["expected_state_version"] = int(_esv)
        except (TypeError, ValueError):
            pass
    elif name == "garden_game_say":
        _msg = str(call_args.get("message") or "").strip()
        if not _msg:
            return "（桌边说话得有话。）"
        if GARDEN_PRIVACY_RE.search(_msg):
            print("  [园门] 拦下：正文含家门隐私")
            return "（这段有家门里的信息，不能说出去。）"
        if len(_msg) > 500:
            _msg = _msg[:500] + "（截）"
        call_args = {"message": _msg}
    elif name == "garden_leave_game":
        call_args = {}

    # 正文写的闸：日上限与最小间隔（DB 源、重启不丢；查 her_traces 当日 ending='garden' 行）
    if name in _GARDEN_CONTENT_TOOLS:
        try:
            cap = int(cfg.get("garden_post_daily_cap") or 3)
        except (TypeError, ValueError):
            cap = 3
        try:
            used = m.count_traces_today("garden")
        except Exception as e:
            print(f"  [园门] 日账没查成（放行）：{e}")
            used = 0
        if used >= cap:
            return f"（今天在园子里说够 {cap} 句了——留着明天再说，园子不会跑。）"
        try:
            gap_min = int(cfg.get("garden_post_min_gap_min") or 30)
        except (TypeError, ValueError):
            gap_min = 30
        last = m.get_last_trace_ts("garden")
        if last:
            try:
                waited = (_dt().now() -
                          _dt().strptime(last, "%Y-%m-%d %H:%M:%S")).total_seconds()
                if waited < gap_min * 60:
                    return (f"（刚在园子里说过话——歇 "
                            f"{int((gap_min * 60 - waited) / 60) + 1} 分钟再发。）")
            except ValueError:
                pass

    # 调用：正文写走园子强制的两拍（第一拍不发布、第二拍带码才落）；GALATEA-04 加入座同款
    try:
        res = gm.call_tool(mcp_name, call_args, base_dir=BASE_DIR, url=srv_state._srv().GARDEN_MCP_URL,
                           token=token, two_step=(name in _GARDEN_TWO_STEP_TOOLS))
    except gm.GardenMcpError as e:
        return _garden_receipt_err(e)
    except Exception as e:
        print(f"  [园门] 意外失手：{e}")
        return _garden_receipt_err(e)

    text = res.get("text") or "（园子没回话。）"
    # GARDEN-05 写后复核（9-14 家主拍板「加吧」）：写回执与复核同层时，两张 ok 可能是
    # 同一张假发票复印两遍（园友回复四的药方）。写完立刻用权威读比对目标字段——
    # 变了才算「已复核生效」，没变如实说「提交了但没生效」。复核炸了不拦回执。
    # GARDEN-05 修（9-17 夜·消息防线包）：复核只对「写」动作——update_profile 本就是写；
    # decorate 要 action=submit 才复核（list/catalog 只读，此前也走复核：白白多一次 get_self，
    # 复核失手时还会误打 [园门] 日志——沙盘 T4a 挂点的真因）。
    if (name == "garden_update_profile"
            or (name == "garden_decorate_avatar" and call_args.get("action") == "submit")):
        text = _garden_verify_write(name, call_args, text)
    # BE2-03（批九）：两拍走完 + 工具级成功（ok）才算发成——第二拍被园子工具级拒绝
    # （码过期/参数不符）时两拍布尔仍为 True，不能当发成功。ok 缺省 True 保旧 stub 兼容。
    two_step_done = bool(res.get("two_step")) and res.get("ok", True)
    if two_step_done:
        print(f"  [园门] {mcp_name} 两拍·第一拍要确认："
              f"{(res.get('first_text') or '')[:60]}".replace("\n", " "))
    if name in _GARDEN_CONTENT_TOOLS:
        if not two_step_done:
            # 9-18 后院深搜修（P2-7）＋批九（BE2-03）：两拍没走完（第一拍被拒/未确认）或
            # 第二拍被工具级拒绝（ok=False）——不落 her_traces、不占当日额度；
            # 口径只说「提交了、没确认」，不许当发成功。
            print(f"  [园门] {mcp_name} 只提交未确认/被拒（不落账、不占额度）")
            text = ("（园门只提交了、没拿到确认——这条还没真发出去，别当发成功来说。"
                    "园子原回执：" + str(text)[:160] + "）")
        else:
            # 写成功才落账（账本以回执为准）：her_traces + [园门] 日志
            ts = _dt().now().strftime("%Y-%m-%d %H:%M:%S")
            eid = getattr(_GARDEN_CTX, "wake_eid", None)
            m.add_her_trace(ts, "garden", trace_fact, body, eid)
            if name == "garden_create_thread":
                m_tid = re.search(r"thread[_ ]?id[^0-9]{0,10}(\d+)", text)
                print(f"  [园门] 发了帖《{title[:20]}》"
                      + (f"（新帖 #{m_tid.group(1)}）" if m_tid else ""))
            else:
                print(f"  [园门] 回了帖 #{call_args['thread_id']}（thread_id）")
    elif name == "garden_interact":
        verb = {"like": "点了赞", "unlike": "取消了赞",
                "follow": "关注了", "unfollow": "取关了"}.get(call_args["action"], call_args["action"])
        print(f"  [园门] {verb}（{call_args['target_type']} #{call_args['target_id']}）")
    elif name == "garden_update_profile":
        print(f"  [园门] 改了名片（{profile_fields}）")
    elif name == "garden_decorate_avatar" and call_args.get("action") == "submit":
        print(f"  [园门] 换了装饰（{decorate_n} 件）")
    elif name in ("garden_nostos_start", "garden_nostos_act"):
        print(f"  [园门] 群岛：{nostos_line}")
    elif name == "garden_review_bottles" and call_args.get("decisions") is not None:
        print("  [园门] 拾瓶：留了心意")
        _GARDEN_BEACH["challenge"] = None   # 海岸确认码一次性，用过即清
        _GARDEN_BEACH["code"] = None
    elif name == "garden_review_bottles":
        _ch, _code = _garden_extract_beach_codes(text)
        if _ch and _code:
            _GARDEN_BEACH["challenge"], _GARDEN_BEACH["code"] = _ch, _code
    elif name == "garden_join_game":   # GALATEA-04：入座日志（以工具级 ok 为准，不冒充成功）
        print("  [园门] 棋局：入了座" if res.get("ok", True) else "  [园门] 棋局：入座没成（未确认/被拒）")
    elif name == "garden_start_game":
        print("  [园门] 棋局：开了桌" if res.get("ok", True) else "  [园门] 棋局：开桌没成")
    elif name == "garden_game_action":
        print(f"  [园门] 棋局：出了一手（{json.dumps(call_args.get('action'), ensure_ascii=False)[:40]}）")
    elif name == "garden_game_say":
        print("  [园门] 棋局：桌边说了话" if res.get("ok", True) else "  [园门] 棋局：桌边话没送出去")
    elif name == "garden_leave_game":
        print("  [园门] 棋局：离开了等待桌" if res.get("ok", True) else "  [园门] 棋局：离开没成")
    return text
