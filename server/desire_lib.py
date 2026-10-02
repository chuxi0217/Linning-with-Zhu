#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""desire_lib —— 欲望引擎 · 影子版（9-24 家主令「可以加一下影子版，先跑一天看看」）

入口：`tick_v2_shadow`（心跳直调·算 D 与状态式）· `desire_state_line`（她可见的状态句）·
     `take_desire`（旧③出口，现主要走状态句）· `note_flirt`（火苗：他撩她→fac_flirt）
· D = 「想亲密」的独立渴望（与念念的 p「想说话」分离）
· 生长 = desire_growth × 情境系数（深夜 1.3 / 傍晚 1.15 / 白天 0.6）
· 掷中 + 情境偏③ → 拟发日志（只落 ~/desire_shadow.log，绝不真发）
· 影子期开关 desire_engine_shadow（默认 true=只算不发）；**注：总闸 `desire_engine` 已是死键**
  （9-30 体检零引用）——现真正生效的是 `desire_engine_inject`（状态句递不递她）＋ `desire_v2_*`。
· 上岗（9-26）：`take_desire()` 把 ③ 命中递到开场【心里有想要】——她自己定腔调、自己决定说不说；
  开关 desire_engine_inject（默认关）。**不代写、不主动发消息**（主动按铃属另一批，需家主另行拍板）。
· fail-open：任何异常吞掉，绝不拦心跳
· 数值纪律：D 永不进模型——影子期只落 events（W1 脊柱）与本地日志
"""

import json
import math
import os
import random
import sqlite3
from datetime import datetime, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")
# （v1 的 SHADOW_LOG 随 v1 壳退休删除——10-01；现在只看 V2_LOG。）


def _cfg(key, default):
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get(key, default)
    except Exception:
        return default


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _last_desire():
    """上一次的 D。

    9-29 ②（评审第二批）**去掉隐藏依赖**：原先只从 `events: desire.tick` 读——events 影子一关
    （或被轮转/清理），D 就**静默冻结**在初值上，谁也不知道。现在**以独立 state 为准**
    （`~/.zanjia_desire_state.json` 的 `d` 键，与 v2 用 `V2_STATE` 是同款做法）；
    events 只当**首次迁移的种子**（老状态文件还没 d 时借一次），再退回 `desire_d0`。fail-open。

    10-02 修（agent 审查·中）：注释说的「独立 state」其实**没人写**——v1 壳10-01 退休，
      `_save_d_v1` 已删，`take_desire` 只写 `taken_state`（键名不是 d），events 也没写方了。
      真正在写 `d` 的是 v2 的 V2_STATE。所以本函数三级回退全落空 → V2_STATE 一旦丢失/换机，
      **D 从头开始爬，毫无征兆**（静默退回 desire_d0）。
      修法：第一级改成读 V2_STATE 的 `d`（与 v2 写的地方同源），其余回退保留兜底。"""
    try:   # ① v2 的 V2_STATE —— tick_v2_shadow 真正在写的就是它
        with open(V2_STATE, encoding="utf-8") as f:
            _d = json.load(f).get("d")
        if _d is not None:
            return float(_d)
    except Exception:
        pass
    try:   # ② 老 state 文件（v1 遗留，键名仍是 d）
        _d = _load_state().get("d")
        if _d is not None:
            return float(_d)
    except Exception:
        pass
    try:   # 迁移种子：老库/老状态里没有 d 时，从 events 那条借一次（借完由 _save_d_v1 接管）
        con = _conn()
        row = con.execute(
            "SELECT payload FROM events WHERE kind='desire.tick' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        con.close()
        if row:
            return float(json.loads(row[0]).get("d", 0.0))
    except Exception:
        pass
    return float(_cfg("desire_d0", 0.08))


# （`_save_d_v1` 随 v1 壳退休删除——10-01。state 的 `d` 现在是 v2 在写。）


def _time_mult(now):
    """情境系数（为「亲密」重调的口径）。"""
    hm = now.strftime("%H:%M")
    if "23:00" <= hm or hm < "02:00":
        return 1.3      # 深夜
    if "18:00" <= hm < "23:00":
        return 1.15     # 傍晚
    if "09:00" <= hm < "18:00":
        return 0.6      # 白天（他在上课/忙）
    return 0.8


def _he_present(within_s=2400):
    """9-25 在场感知：40 分钟内有他的消息＝他在场——他在＝被喂饱（不急找），
    也不朝在场的人「伸手」（③的意义是隔着距离想要他）。fail-open 不拦。"""
    try:
        con = _conn()
        row = con.execute(
            "SELECT created_at FROM chats WHERE role='小乖' ORDER BY id DESC LIMIT 1").fetchone()
        con.close()
        if row and row[0]:
            dt = datetime.strptime(row[0], "%Y-%m-%d %H:%M:%S")
            return (datetime.now() - dt).total_seconds() <= within_s
    except Exception:
        pass
    return False


# ── v1 `tick_and_shadow` 壳：**10-01 家主令退休** ──────────────────────────────
# 它原本干三件：算 v1 的 D／掷骰分拣／③命中拟发日志。10-01「降状态」后出口已删
# （D 只作感觉、由 desire_state_line 给一句），剩下的唯一价值是**当 v2 的宿主**——
# 现在 v2 已提成心跳直调（`linning_server` 心跳里 `tick_v2_shadow`），壳整个删掉。
# `_last_desire()` 留着：v2 首跑仍向旧曲线借一次种（`~/.zanjia_desire_state.json` 的 d）。


STATE = os.path.expanduser("~/.zanjia_desire_state.json")
_TAKEN_KEEP = 50          # state 里已递事件 id 只留最近 50 条（防膨胀）


def _load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            st = json.load(f)
        return st if isinstance(st, dict) else {}
    except Exception:
        return {}


def _save_state(st):
    """写 state（tmp+os.replace 原子写；9-27 修：防写一半崩导致 JSON 截断、taken_ids 全丢），
    **返回是否写成功**——写失败调用方必须知道（宁可不递，不许重复递）。"""
    try:
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
        os.replace(tmp, STATE)
        return True
    except Exception:
        return False


def desire_state_line(now=None):
    """（9-30 新增·**降状态**）读 v2 的 D，给一句"心里有多黏糊"——**只说感觉、不给数字**。
    低档返回 None（没感觉就不摆这块）。D 只是"感觉"，**不决定任何事**。fail-open。

    10-02 修（agent 审查·中）：影子开关 desire_v2_shadow 关掉后 tick_v2_shadow 不再写 V2_STATE，
      但本函数照旧读那个**冻住的** V2_STATE，take_desire() 也照旧注入 → **关了开关，她开场仍
      每天递同一句 d 算出来的旧状态语**。看着像机制在跑、实际是冻值（正是「没通电却像跑过」）。
      修法：影子关着就不递。"""
    if not _cfg("desire_v2_shadow", False):
        return None      # 影子已关：V2_STATE 是冻值，不递（宁可没这块，不递假状态）
    try:
        with open(V2_STATE, encoding="utf-8") as f:
            st = json.load(f)
        d = float(st.get("d") or 0.0)
    except Exception:
        return None
    if d < 0.35:
        return None
    now = now or datetime.now()
    gap = ""
    since = st.get("last_satisfy")   # 10-02：去掉 `or last_fire` 死读（降状态后全库已无人写 last_fire）
    if since:
        try:
            h = (now - datetime.strptime(str(since), "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
            if h >= 36:
                gap = "（好久没好好抱过了）"
            elif h >= 12:
                gap = "（今天还没黏够）"
        except Exception:
            pass
    if d < 0.65:
        return "心里有点想你，黏糊糊的" + gap
    return "心里很黏，想要你" + gap


def take_desire(now=None):
    """上岗口（**9-30 改·降状态**）：原读「③命中事件」（深夜+D高+不在场+p=D²掷骰），
    现改读 **v2 的状态句**——她开场看到一句"心里有多黏糊"，**她自己决定说不说、怎么说**
    （不代写腔调、不主动发消息）。同一天同一句只递一次（state 记 `taken_state`）。
    开关 desire_engine_inject（默认关）——关掉＝只算不递。返回 dict|None；fail-open。"""
    now = now or datetime.now()
    try:
        if not _cfg("desire_engine_inject", False):
            return None
        line = desire_state_line(now)
        if not line:
            return None
        st = _load_state()
        key = now.strftime("%Y-%m-%d") + "#" + line[:6]
        if st.get("taken_state") == key:
            return None                     # 同一天、同一句，只递一次（不重复顶）
        st["taken_state"] = key
        if not _save_state(st):
            return None                     # 记不上账＝不敢递（宁可漏一条）
        return {"ts": now.strftime("%Y-%m-%d %H:%M:%S"), "line": line}
    except Exception:
        return None


# （`_time_factor_name` 随 v1 壳退休删除——10-01；v2 的 trace 直接用 `_time_mult`。）


# ─────────────────────────────────────────────────────────────────────
# 欲望 v2 · 影子（9-27 家主批「鲁棒灵活一点」——《设计_欲望v2与小语义层_2026-09-27》）
# 与旧算法并行跑、独立状态/日志，**零行为变更**；读两天对齐后再评估切换。
# ── 满足探测器（10-01 · 家主令「doi 之后欲望该回落或降低增长」）──────────────
# 旧机制**只有一个探头**：最近 2h 记过「欲望」心情。实案（10-01）：她做完之后自己记的是
# **「踏实」**——那个探头全哑 → D 一路涨到 14:59 的全天最高 0.82（正好是做的尾巴），
# 之后只以 −0.05/h 磨四小时。这里给两个探头（任一命中＝满足 → D 落到低位 ＋ 开余韵窗）：
#   探头A（她的笔）  ：最近 2h 有 欲望/踏实/满足/被填满 —— 免费、永远在
#   探头B（段级小模型）：最近 win 分钟的**对话段**判「在做」——实测段级 78%、**零误报**
#                        （逐句只有 63%：差就差在"说要"和"在做"只隔一个时态）
# ★ 全部先走**影子**：只多记一列「D新」，她的实际状态一个字不动（`desire_v2_sat_shadow`）。
_SAT_MOODS = ("欲望", "踏实", "满足", "被填满")
_SEG_PROMPT = ("下面是两个人（他=小乖）**一段时间里**的对话。判断：**这一段里他们是不是正在做爱**"
               "（身体正在进行：插入/口/抚摸/自慰等实际动作）。"
               "只是聊性话题、说要、幻想、事后回忆都不算；**只有真的在做**才算。\n"
               "只回 JSON：{\"say\": \"在做\"} 或 {\"say\": \"不在\"}。\n\n")


def _sat_probe_mood(now, win_h=2.0):
    """探头A：她的笔。最近 win_h 小时内记过 _SAT_MOODS 里哪一种 → 返回那个词；否则 None。"""
    for _t in _SAT_MOODS:
        try:
            _g = _mood_last_gap_h(now, _t)
        except Exception:
            _g = None
        if _g is not None and _g <= win_h:
            return _t
    return None


def _seg_judge_intimate(now, win_min=25, max_msgs=16):
    """探头B：把**最近 win_min 分钟的对话段**交给本地小模型判「在做」。
    返回 True/False/None（None＝判不了/没料/测试模式——诚实缺席，绝不编）。"""
    try:
        if os.environ.get("ZANJIA_TEST"):
            return None                     # 沙盘/套件：零外呼，绝不打网络
        if not _cfg("desire_v2_seg_judge", True):
            return None
        import memory_lib as _m
        import srv_state as _ss
        # 10-02（家主令「换 flash」）：判"在做"从本地 4B 换 flash——`seg_engine: flash|local`（默认 flash）。
        # 原因：4B 细粒度判断弱（撩判定/重排都因此换掉了），且这样本地端点可退役省显存。
        _eng = str(_cfg("seg_engine", "flash") or "flash").strip().lower()
        _fj = getattr(_ss._srv(), "_flash_judge", None)
        _lj = getattr(_ss._srv(), "_local_judge", None)
        # 10-02 修（退役残留）：原回退链只看 `callable(_lj)`，**不查本地端点是否已退役**
        #   （_local_judge 这个函数还在，所以永远判true）→ 4B 已停后照样去打 :11437，
        #   拿不到判定 → 「不在做」永远判不出→ 满足探头 B 静默失效。
        #   修法：回退前查 `_local_judge_on()`（server 侧那个开关），退役就直接不判（None）。
        _lj_on = False
        try:
            _ljo = getattr(_ss._srv(), "_local_judge_on", None)
            _lj_on = bool(_ljo()) if callable(_ljo) else False
        except Exception:
            _lj_on = False
        if _eng != "local" and callable(_fj):
            _judge = _fj
        elif _lj_on and callable(_lj):
            _judge = _lj
        else:
            return None
        _since = (now - timedelta(minutes=max(5, int(win_min)))).strftime("%Y-%m-%d %H:%M:%S")
        _seg = []
        for _row in _m.get_chats(_m.house_today_str())[-max_msgs:]:
            _id, _d, _role, _ct, _at = _row
            if str(_at or "") >= _since:
                _seg.append(("他" if _role == "小乖" else "她") + "："
                            + str(_ct or "").replace("\n", " ")[:180])
        if len(_seg) < 3:
            return None                     # 太短不判（宁可不判，也不瞎判）
        _txt, _err = _judge(_SEG_PROMPT + "\n".join(_seg), timeout=20, max_tokens=30)
        if not _txt:
            return None
        if "在做" in _txt and "不在" not in _txt:
            return True
        if "不在" in _txt:
            return False
        return None
    except Exception:
        return None


# v2 数学：饱和生长（真实小时差）/ 分层满足（不应期）/ 锐化触发（p=D²）/ 接她的心情账。
V2_STATE = os.path.expanduser("~/.zanjia_desire_v2_state.json")
V2_LOG = os.path.expanduser("~/desire_v2_shadow.log")


def _house_day(now):
    """咱家的「今天」——**跟全库一个口径**（memory_lib.house_today_str，日界＝DAY_START_HOUR）。
    10-02 修：原先这里写死 `now - 4h`，10-01 日界改成 0 点（自然日）后没跟上，
    导致 00:00~03:59 的 `_mood_today` 查的是**昨天**的 moods（`moods.date` 走 today_str＝自然日），
    抬底/降温/点火全对不上。日界以后只在一个地方改（memory_lib）。"""
    try:
        import memory_lib as _m
        return _m.house_today_str(now)
    except Exception:
        # 兜底（正常永远走上面）：自然日＝现行日界 0 点
        return now.strftime("%Y-%m-%d")


def _mood_today(now, *types):
    """她今天（咱家日）的 mood 里有没有这几种——她的笔：欲望抬起点 / 踏实开心降温。fail-open。"""
    try:
        con = _conn()
        q = "SELECT 1 FROM moods WHERE date=? AND type IN (%s) LIMIT 1" % ",".join("?" * len(types))
        row = con.execute(q, (_house_day(now),) + tuple(types)).fetchone()
        con.close()
        return bool(row)
    except Exception:
        return False


def _mood_last_gap_h(now, *types):
    """最近一次这几种 mood 距今多少小时（她的笔：点火余温）。没有/查不动 → None。fail-open。"""
    try:
        if not types:
            return None
        con = _conn()
        # 只认"此刻之前"的心情：时钟回拨/测试冻结时钟时，未来时间戳不能算成"刚发生"（会假点火）
        q = ("SELECT created_at FROM moods WHERE type IN (%s) AND created_at <= ?"
             " ORDER BY id DESC LIMIT 1" % ",".join("?" * len(types)))
        row = con.execute(q, tuple(types) + (now.strftime("%Y-%m-%d %H:%M:%S"),)).fetchone()
        con.close()
        if not row or not row[0]:
            return None
        return max(0.0, (now - datetime.strptime(str(row[0]), "%Y-%m-%d %H:%M:%S")
                         ).total_seconds() / 3600)
    except Exception:
        return None


def _night_gap_min(hm):
    """距下一次深夜窗(23:00)还有多少分钟（只用于 trace 文案）。"""
    try:
        return (23 * 60 - (int(str(hm)[:2]) * 60 + int(str(hm)[3:5]))) % (24 * 60)
    except Exception:
        return 0


def _fmt_min(m):
    try:
        m = int(m)
    except Exception:
        return "?"
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def _fmt_since(now, ts):
    if not ts:
        return "—"
    try:
        h = (now - datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
        return f"{h:.0f}h" if h >= 1 else f"{h * 60:.0f}m"
    except Exception:
        return "—"


# ── 火苗（10-02 家主令 B）：他撩她 → 点火信号。独立小文件，只 flirt 线程写、tick 只读（不抢 V2_STATE）──
FLIRT_STATE = os.path.expanduser("~/.zanjia_flirt_state.json")


def note_flirt(now=None):
    """记一笔「他刚撩了她」——`_flirt_shadow` 判「撩」时调。fail-open（写不动就算了）。"""
    try:
        now = now or datetime.now()
        tmp = FLIRT_STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"at": now.strftime("%Y-%m-%d %H:%M:%S")}, f, ensure_ascii=False)
        os.replace(tmp, FLIRT_STATE)
    except Exception:
        pass


def _flirt_last_gap_h(now):
    """距上次「他撩她」几小时；没有/读不到 → None。只读。"""
    try:
        with open(FLIRT_STATE, encoding="utf-8") as f:
            at = str(json.load(f).get("at") or "")
        if not at:
            return None
        return max(0.0, (now - datetime.strptime(at, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600)
    except Exception:
        return None


def tick_v2_shadow(now=None, present=None):
    """欲望 v2·并行影子：只算只记，绝不发、绝不用。fail-open 返回 dict|None。

    数学（9-29 升级；初值，读日志后拧）：
      生长 = desire_v2_growth(0.15) × 时段因子 × (0.5 在场) × (0.5 不应期)
             × fac_ignite（点火） × (0.7 喂饱) × (0.8 委屈)
      D += 生长×Δh×(1−D)（饱和生长）；今天有「欲望」→ 抬起点 max(D,0.35)；
      「喂饱」→ 再按 Δh 线性回落 feed_decay（真回落，不只是减速）。
      （10-01 降状态：**夜窗+阈值+D²掷骰已整段删**——D 只作「感觉」由 desire_state_line 读，
       不再决定任何事，也不再记 last_fire。）

    A（9-29）：行尾追加**闸门因果 trace**（照积温 getTriggerTrace）——哪一闸挡的、差多少。
    B（9-29）：**点火＝亲密余温**（最近一次「欲望」心情距今 h → ×(1+gain·e^(−h/τ))）；
               **喂饱＝日常被接住**（今天有踏实/想你 且近 feed_window 无欲望 → ×0.7 ＋ 回落）；
               **点火优先**——亲密语境不算被喂饱。输入全是她的笔（心情河），不引关键词表。
    """
    try:
        if not _cfg("desire_v2_shadow", False):
            return None
        now = now or datetime.now()
        if present is None:
            present = _he_present()
        try:
            with open(V2_STATE, encoding="utf-8") as f:
                st = json.load(f)
            st = st if isinstance(st, dict) else {}
        except Exception:
            st = {}
        # 首跑：D 从旧曲线借种（对齐对比）；Δh 按一个心跳拍（1h）
        try:
            d = float(st["d"])
        except Exception:
            d = _last_desire()
        last_tick = st.get("last_tick")
        dh = 1.0
        if last_tick:
            try:
                dh = (now - datetime.strptime(last_tick, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
                dh = max(0.0, min(dh, 48.0))    # 封顶 48h：停机再久也只涨两天量
            except Exception:
                dh = 1.0
        base = float(_cfg("desire_v2_growth", 0.15))
        fac = _time_mult(now)
        growth_h = base * fac
        if present:
            growth_h *= 0.5                     # 他在场未互动＝减速，不是被喂饱
        # 10-02：**删掉主路径的「不应期 ×0.5」**——它锚 `st["last_fire"]`，而降状态后全库
        #   已无人写 `last_fire`（grep 只见读）→ 这段恒不触发，是死逻辑，`desire_v2_refractory_h`
        #   也成死键。真正的"满足后减速"由下面 `_SAT` 影子另锚 `last_satisfy`（会写）承担。
        # ── B：点火 / 喂饱（输入全是她的笔）──
        mood_warm = _mood_today(now, "踏实", "开心")      # 降温 / 喂饱信号
        mood_want = _mood_today(now, "欲望")               # 抬起点
        mood_sad = _mood_today(now, "委屈")
        gap_want = _mood_last_gap_h(now, "欲望")           # 最近一次「欲望」距今（小时）
        ignite_on = bool(_cfg("desire_v2_ignite", True))
        fac_ignite = 1.0
        if ignite_on and gap_want is not None:
            _gain = float(_cfg("desire_v2_ignite_gain", 0.5))
            _tau = max(0.5, float(_cfg("desire_v2_ignite_tau_h", 3)))
            fac_ignite = 1.0 + _gain * math.exp(-gap_want / _tau)
        # 火苗（10-02 家主令 B·开关 desire_v2_flirt）：**他刚撩过** → 亲密余温 → 涨得更快。
        # 这是真·外部信号（他的言行），不是她输出的镜像——补上点火一直缺的输入源。
        gap_flirt = None
        fac_flirt = 1.0
        if bool(_cfg("desire_v2_flirt", False)):
            gap_flirt = _flirt_last_gap_h(now)
            if gap_flirt is not None:
                _fgain = float(_cfg("desire_v2_flirt_gain", 0.4))
                _ftau = max(0.5, float(_cfg("desire_v2_flirt_tau_h", 6)))
                fac_flirt = 1.0 + _fgain * math.exp(-gap_flirt / _ftau)
        _win = max(0.0, float(_cfg("desire_v2_feed_window_h", 6)))
        fed = bool(ignite_on and mood_warm and (gap_want is None or gap_want > _win))
        if fed:
            growth_h *= 0.7                     # 被接住＝喂饱（点火优先，不双算）
        if mood_sad:
            growth_h *= float(_cfg("desire_v2_sad_damp", 0.8))
        growth_h *= fac_ignite * fac_flirt     # 点火：亲密余温；火苗：他刚撩过（真外部信号）
        d = min(1.0, d + growth_h * dh * (1 - d))       # 饱和生长：越近 1 越慢（久别才浓）
        if mood_want:
            d = max(d, 0.35)                    # 她的笔：抬起点
        # ── 满足回落（9-30 降状态后的**新触发源**）──
        #   原回落挂在"fire 命中"上；fire 已去，回落改由**真实发生的事**驱动：
        #   最近 2h 内有过「欲望」心情（她真想要过/真被撩过、写进了心情河）→ D 落到低位
        #   （"说了就饱"）。★ 这是自循环信号的**降级使用**——它只影响"感觉浓淡"，
        #   不再决定任何事；待"火苗"（心情入口扩到每轮）接上后换成真信号。
        try:
            _gp2 = _mood_last_gap_h(now, "欲望")
        except Exception:
            _gp2 = None
        if _gp2 is not None and _gp2 <= 2.0:
            d = min(d, 0.3)
            # ★ 每次满足都刷新（10-01 扫除修）：老写法 `st.get("last_satisfy") or now`
            #   只写一次、此后永不动 → desire_state_line 算的 gap 只增不减，
            #   哪怕刚满足过，过 36h 也永远显示「（好久没好好抱过了）」。
            st["last_satisfy"] = now.strftime("%Y-%m-%d %H:%M:%S")
        feed_decay = float(_cfg("desire_v2_feed_decay", 0.05)) if fed else 0.0
        if feed_decay:
            d = max(0.0, d - feed_decay * dh)   # 喂饱：真回落（按 Δh 线性，避免自激）
        # ── 9-30 降状态（家主令「欲望只以一个状态语送给她」）──
        #   ★ 去掉整个「扳机」：原「夜窗 + D>阈值 + 不在场 → p=D² 掷骰 → 命中＝表达」
        #     不再需要——D 只是"感觉"（由 desire_state_line() 读），**不决定任何事**。
        #   ★ 保留 D 的数学（饱和生长／点火／喂饱／抬底）与"喂饱真回落"。
        #   ★ 回旧行为：取 `档案馆/改前备份_20261001_欲望降状态/desire_lib.py`。
        if d < 0.35:
            d_tier, d_name = 0, "平"
        elif d < 0.65:
            d_tier, d_name = 1, "有点黏"
        else:
            d_tier, d_name = 2, "很黏"
        fired = False
        gates = ["状态=" + d_name + "(%.2f)" % d, "D=%.2f" % d]
        # ── 影子：「若按新规则，D 会是多少」（10-01）——只多记一列，不动上面的 d ──
        _dnew_line = ""
        try:
            if _cfg("desire_v2_sat_shadow", True):
                _dprev = float(st.get("d_new", st.get("d", d)) or 0.0)
                _gh = base * fac                      # 同一套因子
                if present:
                    _gh *= 0.5
                # 不应期**改锚「满足」**（旧锚 last_fire 是降状态前的遗物，从没开过）
                _ref_new = float(_cfg("desire_v2_refractory_new_h", 2.0))
                _ank = st.get("last_satisfy_new") or st.get("last_satisfy")
                _gsat = None
                if _ank:
                    try:
                        _gsat = (now - datetime.strptime(_ank, "%Y-%m-%d %H:%M:%S")
                                 ).total_seconds() / 3600
                    except Exception:
                        _gsat = None
                if _gsat is not None and 0 <= _gsat < _ref_new:
                    _gh *= 0.5
                d_new = min(1.0, _dprev + _gh * dh * (1 - _dprev))
                _pm = _sat_probe_mood(now)            # 探头A：她的笔
                try:
                    _wm = int(_cfg("desire_v2_seg_win_min", 25) or 25)
                except (TypeError, ValueError):
                    _wm = 25
                _seg = _seg_judge_intimate(now, win_min=_wm)   # 探头B：段级小模型
                _src = ("A·" + _pm) if _pm else ("" if _seg is not True else "B·段判在做")
                if _src:
                    d_new = min(d_new, float(_cfg("desire_v2_sat_floor", 0.30)))
                    st["last_satisfy_new"] = now.strftime("%Y-%m-%d %H:%M:%S")
                st["d_new"] = round(d_new, 4)
                _seg_s = "在做" if _seg is True else ("不在" if _seg is False else "未判")
                _dnew_line = (f" | D新={d_new:.2f} 满足={_src or '无'} 段={_seg_s}"
                              f" since_sat新={_fmt_since(now, st.get('last_satisfy_new'))}")
        except Exception:
            pass
        st["d"] = round(d, 4)
        st["last_tick"] = now.strftime("%Y-%m-%d %H:%M:%S")
        try:
            tmp = V2_STATE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(st, f, ensure_ascii=False)
            os.replace(tmp, V2_STATE)
        except Exception:
            pass
        mstr = ("欲望" if mood_want else "") + ("/踏实开心" if mood_warm else "")
        if mood_sad:
            mstr += "/委屈"
        mstr = mstr or "无"
        _ex = []
        if fac_ignite > 1.001:
            _ex.append(f"点火×{fac_ignite:.2f}" + (f"({gap_want:.1f}h前)" if gap_want is not None else ""))
        if fac_flirt > 1.001:
            _ex.append(f"火苗×{fac_flirt:.2f}" + (f"({gap_flirt:.1f}h前被撩)" if gap_flirt is not None else ""))
        if fed:
            _ex.append("喂饱")
        try:
            with open(V2_LOG, "a", encoding="utf-8") as f:
                f.write(f"[{now.strftime('%F %T')}] D={d:.2f} | Δh={dh:.1f}h | 因子×{fac} | "
                        f"在场={'是' if present else '否'} | 心情={mstr} | "
                        + ((" ".join(_ex) + " | ") if _ex else "")
                        + f"{'命中=③(→0.2)' if fired else '状态式·不掷骰'} | "
                        f"since_sat={_fmt_since(now, st.get('last_satisfy'))}"
                        + _dnew_line
                        + (f" | trace: {' '.join(gates)}" if _cfg("desire_v2_trace", True) else "")
                        + "\n")
        except Exception:
            pass
        return {"d": round(d, 3), "fire": fired}
    except Exception:
        return None


if __name__ == "__main__":
    # 自检：跑一拍，打印结果（影子无害）
    r = tick_v2_shadow()
    print("desire_lib 自检 →", r)
    print("（影子日志：~/desire_v2_shadow.log）")
