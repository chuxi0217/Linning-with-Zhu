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
  s.notify_letter / s._he_present / s._silent_window / s._day_window_start；
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


def _garden_wake_prompt(event, garden_tools=False):
    """（GARDEN-01 §三）组装唤醒提示词。措辞照施工卷逐字（监理逐字审过）；
    仅两处工程性渲染：evidence 摘要 ≤100 字无则略、「（干净）」补上施工卷里漏的右括号（申报）。
    GALATEA-02 §④：kind=galatea 唤醒轮补一行园子图书证句（garden_tools=True），其余字不动。"""
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
            ev = "；".join(f"{k}：{str(v)[:50]}" for k, v in obj.items() if str(v or "").strip())
        else:
            ev = str(evidence or "")
    except Exception:
        ev = str(evidence or "")
    ev = ev[:100]
    garden_line = ("你在园子里有图书证：能看帖、回帖、发帖——想说话就用；静默也永远是合法的。\n"
                   if garden_tools else "")
    return (f"现在是{now}。你从一次安静的小憩里醒来——没有人叫你，是家里的一点动静把你唤醒的。\n"
            f"今天发生的：{summary}" + (f"（{ev}）" if ev else "") + "\n"
            f"你最近自己留下的心事：{fact_line}\n"
            f"家里还悬着的话头：{thread_line}\n\n"
            + garden_line +
            "醒来先不用说话。你看看这件事、想想它，然后自己选一个结局：\n"
            "- 没什么想说的，ending 就 \"silent\"——静默也是过日子，没人会失望；\n"
            "- 想留一点只给自己的心事，ending 用 \"trace\"，content 写你的独处正文；\n"
            "- 确实有话想对小乖说，ending 用 \"message\"——别为了说话而说话。\n"
            "fact 只留给下一次醒来的你自己看：≤40 字、克制、稀疏，记事实不记情绪。\n"
            "严格只输出 JSON：{\"ending\": \"silent|trace|message\", \"fact\": \"≤40字\", "
            "\"content\": \"trace 时填\", \"message\": \"message 时填，≤80字，像平常那样对他说话\"}")


def _garden_settle(eid, raw):
    """（GARDEN-01 §四）解析三结局并落账。解析失败/ending 非法/该结局必填字段为空 =
    错误：release + 日志，事件不消费。落账顺序锁死：先写产出（trace/outbox）再 consume；
    写失败抛出去（不 consume，租约回头重来）。返回结局字符串。"""
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
    # 9-25 在场感知：他在场就压成独处——想说的先记心里（他离开后/下轮再来说）
    if srv_state._srv()._he_present():   # 运行期反查：沙盘会重绑 s._he_present
        degrade = "他在场，压成独处"
    elif _busy_garden_enforce():
        degrade = "他在忙（报备过），压成独处"
    elif m.count_outbox_today("🌱") >= cap:
        degrade = "超上限压成独处"
    else:
        try:
            today_msgs = m.get_outbox_today("🌱")
            last_m = today_msgs[-1][1][2:] if today_msgs else ""   # 去掉「🌱 」前缀再比
            if last_m and difflib.SequenceMatcher(None, message, last_m).ratio() >= 0.6:
                degrade = "近似重复压成独处"
        except Exception:
            pass   # 比对炸了不拦她的表达（宁发勿哑）
    if degrade:
        m.add_her_trace(ts, "trace", fact, message, eid)
        m.consume_world_event(eid)
        print(f"  [Garden] {degrade}（事件#{eid}）：{message[:30]}")
        return "trace"
    m.add_outbox_msg("🌱 " + message)
    srv_state._srv().notify_letter()   # 运行期反查：沙盘会重绑 s.notify_letter
    m.add_her_trace(ts, "message", fact, "", eid)
    m.consume_world_event(eid)
    print(f"  [Garden] 来找他：{message[:30]}")
    return "message"


def _busy_garden_enforce():
    """9-26 忙窗影子（④-A）：他报备过在忙——影子期只记「若拦」，enforce 才真压成独处。
    fail-open 回 False。"""
    try:
        return bool(srv_state._srv()._busy_note("园子🌱"))
    except Exception:
        return False


def _garden_wake_once():
    """（GARDEN-01 §三）唤醒单轮。每轮顺序照施工卷：开关→静默窗→最短间隔（DB 源、
    重启不丢）→领事件→搁置→唤醒→三结局。返回 "slept"/"silent"/"trace"/"message"/
    "stalled"/"error"，给日志与测试看。"""
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
                                         "——看通知、看帖子、回一句、改改名片，或者只是逛逛")
            print("  [Garden] 散步骰子掷中：投了一条自主散步（下轮园子专窗醒来）")
        return "slept"   # G1 只吃事件，没事件不硬醒
    eid, _kind, _summary, _evidence, attempts = event
    if attempts > 3:
        m.consume_world_event(eid)
        print(f"  [Garden] 事件搁置（3 次没醒成）#{eid}")
        return "stalled"
    # 唤醒：引擎走 garden_engine 档（GALATEA-02 ⓪——默认主引擎 K3，她的声音用她的脑子；
    # deepseek=省钱回退档，thinking 同 librarian 关法）；kind=galatea 的唤醒轮开园子工具
    # 专窗（§④：仅七件园子图书证），其余事件维持无工具。
    wake_cfg = _garden_engine_cfg(cfg)
    msgs = [
        {"role": "system", "content": srv_state.session().system_prompt},   # 取用口（入口属主名）
        {"role": "user", "content": _garden_wake_prompt(event, garden_tools=(_kind == "galatea"))},
    ]
    try:
        if _kind == "galatea":
            raw = _garden_wake_with_tools(wake_cfg, msgs, eid)
        else:
            raw = srv_state._srv().call_deepseek(wake_cfg, msgs, scene="garden.wake").strip()   # 运行期反查：沙盘会重绑 s.call_deepseek
    except Exception as e:
        m.release_world_event(eid)
        print(f"  [Garden] 这次没醒成（{e}）")
        return "error"
    if not raw or raw.startswith("（姐姐掉线了"):
        m.release_world_event(eid)   # 错误不许冒充静默：不消费，回头重领
        print("  [Garden] 这次没醒成（掉线/空回复）")
        return "error"
    try:
        return _garden_settle(eid, raw)
    except Exception as e:
        print(f"  [Garden] 这次没醒成（落账：{e}）")
        return "error"   # 不 consume：租约回头重来（写失败不销账铁律）


def _garden_loop():
    """自主唤醒循环（daemon 线程，ZANJIA_TEST 不起）：300 秒一轮；单轮炸了不拖死。"""
    while True:
        try:
            _garden_wake_once()
        except Exception as e:
            print(f"  [Garden] 循环失手：{e}")
        time.sleep(300)


# ── GARDEN-04 自主散步（9-14 凌晨 家主拍板「可以做。只要不高频」）──
# 没事件也可以自己想去园子逛逛：骰子三重闸（距上次醒来 ≥4h · 今天 ≤2 次 · 桥随行），
# 绝不高频打扰园子。散步 = 投一条 kind=galatea 的合成事件，下一轮走既有园子专窗
# 醒来（三结局照旧、隐私过滤与写额度照旧）。桥按它家契约只在她想去时拉起，
# 掉了不自动重连（等下一次骰子）——这是家主以身份委托的契约变更，红线（重连循环）仍守。
GARDEN_WALK_MIN_GAP_H = 4
GARDEN_WALK_DAILY_MAX = 2
_BRIDGE_FAIL_UNTIL = [0.0]   # 桥拉起失败的冷静期（epoch 秒），防 5 分钟一轮硬重试


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
    """散步三闸现值（9-23 新门配套·Garden 前端三件②后端）：状态条算「下次散步倒计时 /
    今日 0-2 次」。口径与 _garden_self_walk_allowed 同源——锚=最近一次醒来（任何结局，
    last_trace_ts）、次数=咱家日界起 her_traces 条数（与真闸同一把尺，UI 才不会说还能走、
    真闸却不投）。只读：不碰 _ensure_bridge/_bridge_running（拉桥是动作不是状态；桥在岗
    由既有 garden_bridge 键单报）。查询坏账三键各回 null，不炸状态页。"""
    try:
        cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
        try:
            min_h = float(cfg.get("garden_walk_min_gap_h") or GARDEN_WALK_MIN_GAP_H)
        except (TypeError, ValueError):
            min_h = GARDEN_WALK_MIN_GAP_H
        try:
            daily_max = int(cfg.get("garden_walk_daily_max") or GARDEN_WALK_DAILY_MAX)
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
        return {"walk_allowed": bool(gap_ok and walks_today < daily_max),
                "last_walk_ts": last_ts,
                "walks_today": walks_today}
    except Exception:
        return {"walk_allowed": None, "last_walk_ts": None, "walks_today": None}


def _ensure_bridge():
    """散步前看一眼耳朵：不在岗就 setsid 拉起（家主委托版，掉线仍不自动重连）。
    返回 True=在岗（原本就跑/刚拉起）；False=拉不起（日志 + 1 小时冷静期）。"""
    import subprocess
    if _bridge_running():
        return True
    if time.time() < _BRIDGE_FAIL_UNTIL[0]:
        return False
    try:
        token = open(srv_state._srv().GARDEN_TOKEN_PATH).read().strip()   # 运行期反查：沙盘会重绑 s.GARDEN_TOKEN_PATH
    except Exception:
        token = ""
    if not token:
        print("  [Garden] 散步前拉桥失败：garden_token.txt 缺失——1 小时冷静期")
        _BRIDGE_FAIL_UNTIL[0] = time.time() + 3600
        return False
    bridge_dir = os.path.expanduser("~/galatea-garden-wake-bridge")
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
        time.sleep(5)   # 给 SSE 握手一点时间（结果看 bridge.log）
        _BRIDGE_FAIL_UNTIL[0] = 0.0
        return True
    except Exception as e:
        print(f"  [Garden] 散步前拉桥失败（{e}）——1 小时冷静期")
        _BRIDGE_FAIL_UNTIL[0] = time.time() + 3600
        return False


def _garden_self_walk_allowed(cfg, now, last_ts):
    """散步骰子三重闸：距上次醒来 ≥4h · 今天 ≤2 次（日界 4 点）· 桥随行。
    静默窗/30 分钟最短间隔已在上游闸过。返回 True=这次可以投散步事件。"""
    try:
        min_h = float(cfg.get("garden_walk_min_gap_h") or GARDEN_WALK_MIN_GAP_H)
    except (TypeError, ValueError):
        min_h = GARDEN_WALK_MIN_GAP_H
    try:
        daily_max = int(cfg.get("garden_walk_daily_max") or GARDEN_WALK_DAILY_MAX)
    except (TypeError, ValueError):
        daily_max = GARDEN_WALK_DAILY_MAX
    if last_ts:
        try:
            if (now - _dt().strptime(last_ts, "%Y-%m-%d %H:%M:%S")).total_seconds() < min_h * 3600:
                return False   # 上次醒来还热乎着，让她过日子
        except ValueError:
            pass
    try:
        if m.count_traces_since(srv_state._srv()._day_window_start()) >= daily_max:
            return False   # 今天已经逛过两回了，日子要有留白
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
    r"示例真名|示例城市|示例学校|示例地名|your-host|your-mailbox@|his-mailbox|smtp_auth_code|"
    r"sk-[A-Za-z0-9]{20,}|your-vps-ip", re.IGNORECASE)
GARDEN_TOOL_NAMES = ("garden_get_self", "garden_list_threads", "garden_get_thread",
                     "garden_notifications", "garden_create_thread", "garden_reply",
                     "garden_interact",
                     # GALATEA-03（9-13）园子生活七件：名片/拾瓶/雾潮群岛
                     "garden_get_machine", "garden_review_bottles", "garden_update_profile",
                     "garden_decorate_avatar", "garden_nostos_start", "garden_nostos_status",
                     "garden_nostos_act")
# 写类（过出园开关闸）。decorate 按动作分读/写（list/catalog 只读、submit 才写），单列在分支里；
# review_bottles 纯读不禁，仅其 decisions 写侧在分支里过闸。
_GARDEN_WRITE_TOOLS = ("garden_create_thread", "garden_reply", "garden_interact",
                       "garden_update_profile", "garden_nostos_start", "garden_nostos_act")
_GARDEN_CONTENT_TOOLS = ("garden_create_thread", "garden_reply")   # 过隐私/长度/上限/间隔的正文写
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
    （K3 无真关档、取最低档；9-2 实录）。"""
    wake_cfg = dict(cfg)
    wake_cfg["thinking_enabled"] = False
    wake_cfg["thinking_effort"] = str(cfg.get("garden_thinking_effort") or "low")
    if str(cfg.get("garden_engine") or "k3").strip().lower() == "deepseek":
        wake_cfg["model"] = cfg.get("_deepseek_model") or "deepseek-flash"
        wake_cfg["base_url"] = cfg.get("_deepseek_base_url") or "https://api.deepseek.com"
        wake_cfg["api_key"] = cfg.get("_deepseek_api_key") or ""
    return wake_cfg


def _garden_tools_payload():
    """园子七件（唤醒轮专用子集）：与全量同款，只是筛名字。"""
    return [{"type": t["type"], "function": t["function"]}
            for t in srv_state._srv().LIBRARY_TOOLS if t["function"]["name"] in GARDEN_TOOL_NAMES]


def _garden_wake_with_tools(cfg, messages, eid):
    """（GALATEA-02 §④）园子事件专属唤醒轮：仅七件园子图书证、≤3 轮工具 + 打烊收束。
    三结局协议一字不动——工具是让她看/说，最终仍要她回三结局 JSON；网络异常返回 ""，
    由 _garden_wake_once 按「掉线/空回复=错误不冒充静默」处理（事件不消费）。
    唤醒轮里的写落账带原事件 id（_GARDEN_CTX.wake_eid → her_traces.event_id）。"""
    msgs = list(messages)
    _GARDEN_CTX.wake_eid = eid
    try:
        for _round in range(3):
            msg = srv_state._srv().call_deepseek_with_tools(cfg, msgs, tools=_garden_tools_payload(), scene="garden.play")
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
    garden_nostos_status→nostos_status、garden_nostos_act→nostos_act。

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
                "garden_nostos_act": "nostos_act"}.get(name)
    if mcp_name is None:
        return "（没这本图书证）"

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

    # 调用：正文写走园子强制的两拍（第一拍不发布、第二拍带码才落）
    try:
        res = gm.call_tool(mcp_name, call_args, base_dir=BASE_DIR, url=srv_state._srv().GARDEN_MCP_URL,
                           token=token, two_step=(name in _GARDEN_CONTENT_TOOLS))
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
    return text
