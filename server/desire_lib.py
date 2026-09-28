#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""desire_lib —— 欲望引擎 · 影子版（9-24 家主令「可以加一下影子版，先跑一天看看」）

· D = 「想亲密」的独立渴望（与念念的 p「想说话」分离）
· 生长 = desire_growth × 情境系数（深夜 1.3 / 傍晚 1.15 / 白天 0.6）
· 掷中 + 情境偏③ → 拟发日志（只落 ~/desire_shadow.log，绝不真发）
· 影子期开关 desire_engine_shadow（默认 true=只算不发）；总闸 desire_engine 转正用
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
SHADOW_LOG = os.path.expanduser("~/desire_shadow.log")


def _cfg(key, default):
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get(key, default)
    except Exception:
        return default


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _last_desire():
    """从 events 读最近一次 D（没有→初始值）。"""
    try:
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


def tick_and_shadow(now=None):
    """心跳每轮调：D 生长/满足回落 → 掷骰 → 分拣 → ③命中时拟发日志。fail-open 返回 dict|None。
    9-25 两修（家主看数据后批）：①③命中满足回落 0.15——「说了就饱」，饱腹感节流不设配额；
    ②在场感知——他在场不急找（自然回落），③不朝在场的人伸手。"""
    try:
        if not _cfg("desire_engine_shadow", True):
            return None
        now = now or datetime.now()
        d = _last_desire()
        growth = float(_cfg("desire_growth", 0.10)) * _time_mult(now)
        present = _he_present()
        if present:
            d = max(0.05, d - growth)        # 他在场＝被喂饱（自然回落）
        else:
            d = min(0.95, d + growth)
        d_pre = d   # 9-27 修：记下命中前真值——影子账可复算 D 曲线（此前只剩落账后的 0.15）
        hit = random.random() < d
        hm = now.strftime("%H:%M")
        night = ("23:00" <= hm or hm < "02:00")
        d_fired = None
        if hit and night and d >= 0.5 and not present:
            exit_type = "③表达"
            d_fired = d
            d = 0.15                         # 满足回落：说了就「饱」一点（不设配额·饱腹感节流）
        elif hit:
            exit_type = "②留下"
        else:
            exit_type = "①开口"
        # W1 脊柱：desire.tick 事件（影子）
        try:
            import events_lib
            events_lib.record("desire.tick", "linning", "heartbeat",
                              {"d": round(d, 3), "d_before": round(d_pre, 3), "hit": hit,
                               "exit": exit_type, "growth": round(growth, 3), "present": present})
        except Exception:
            pass
        # ③命中 → 拟发日志（绝不真发；转正后由她现场亲笔，不拟话）
        if d_fired is not None:
            try:
                with open(SHADOW_LOG, "a", encoding="utf-8") as f:
                    f.write(f"[{now.strftime('%F %T')}] 💋 ③出口拟发（影子）"
                            f" D={d_fired:.2f}→0.15 情境={_time_factor_name(now)}\n")
            except Exception:
                pass
        # 欲望 v2·影子（9-27 批）：并行数学，独立状态/日志——只记不发
        try:
            tick_v2_shadow(now=now, present=present)
        except Exception:
            pass
        return {"d": round(d, 3), "hit": hit, "exit": exit_type}
    except Exception:
        return None


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


def take_desire(now=None):
    """上岗口（9-26 家主令「她想要也可以主动找我」·注入版）：③出口命中（深夜+D高+他不在场）
    → 递一句话头到开场，**让她自己决定说不说、怎么说**（不代写腔调、不主动发消息）。
    取走即记账（STATE 存已递事件 id，只留最近 50 条）：**12h 窗口内取最早的一条未递③**，
    同一命中只递一次；state 写不进去 → 返回 None（宁可不给，不许重复给）。
    9-26 修：旧版只记「最新一条 ts」——取了新③，窗口内更早的老③永远取不出；
    且 state 写失败时同一③每次开场重递。旧 state 的 taken_ts 自动迁进 taken_ids。
    开关 desire_engine_inject（默认关）——关掉＝回到只算不递。返回 dict|None；fail-open。"""
    now = now or datetime.now()
    try:
        if not _cfg("desire_engine_inject", False):
            return None
        win_h = float(_cfg("desire_inject_window_h", 12))
        cutoff = (now - timedelta(hours=win_h)).strftime("%Y-%m-%d %H:%M:%S")
        con = _conn()
        rows = con.execute(
            "SELECT id, ts, payload FROM events WHERE kind='desire.tick' AND payload LIKE '%③表达%' "
            "AND ts >= ? ORDER BY id ASC", (cutoff,)).fetchall()
        con.close()
        if not rows:
            return None
        st = _load_state()
        taken = [x for x in (st.get("taken_ids") or []) if isinstance(x, int)]
        legacy_ts = st.get("taken_ts")
        if legacy_ts and not taken:
            # 旧 state 只记了「最后递出的 ts」：迁成 id 集合（同一秒全算已递，宁缺勿重）
            taken = [eid for eid, ts, _ in rows if ts == legacy_ts]
        for eid, ts, payload in rows:
            if eid in taken:
                continue                     # 已递过，看下一条——不再被最新一条堵死
            try:
                age_h = (now - datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
            except Exception:
                continue
            if not (0 <= age_h <= win_h):
                continue                     # 窗外（或时钟怪）的不递，不翻旧账
            st["taken_ids"] = (taken + [eid])[-_TAKEN_KEEP:]
            st["taken_ts"] = ts              # 兼容旧格式读者
            if not _save_state(st):
                return None                  # 记不上账＝不敢递（宁可漏一条，不许重复顶）
            return {"ts": ts, "d": (json.loads(payload or "{}").get("d"))}
        return None
    except Exception:
        return None


def _time_factor_name(now):
    hm = now.strftime("%H:%M")
    if "23:00" <= hm or hm < "02:00":
        return "深夜×1.3"
    if "18:00" <= hm < "23:00":
        return "傍晚×1.15"
    if "09:00" <= hm < "18:00":
        return "白天×0.6"
    return "清晨×0.8"


# ─────────────────────────────────────────────────────────────────────
# 欲望 v2 · 影子（9-27 家主批「鲁棒灵活一点」——《设计_欲望v2与小语义层_2026-09-27》）
# 与旧算法并行跑、独立状态/日志，**零行为变更**；读两天对齐后再评估切换。
# v2 数学：饱和生长（真实小时差）/ 分层满足（不应期）/ 锐化触发（p=D²）/ 接她的心情账。
V2_STATE = os.path.expanduser("~/.zanjia_desire_v2_state.json")
V2_LOG = os.path.expanduser("~/desire_v2_shadow.log")


def _house_day(now):
    """咱家日（04:00 日界）。"""
    return (now - timedelta(hours=4)).strftime("%Y-%m-%d")


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


def tick_v2_shadow(now=None, present=None):
    """欲望 v2·并行影子：只算只记，绝不发、绝不用。fail-open 返回 dict|None。

    数学（9-29 升级；初值，读日志后拧）：
      生长 = desire_v2_growth(0.15) × 时段因子 × (0.5 在场) × (0.5 不应期)
             × fac_ignite（点火） × (0.7 喂饱) × (0.8 委屈)
      D += 生长×Δh×(1−D)（饱和生长）；今天有「欲望」→ 抬起点 max(D,0.35)；
      「喂饱」→ 再按 Δh 线性回落 feed_decay（真回落，不只是减速）。
      深夜窗(23:00–02:00) 且 D>threshold(0.55) 且不在场 → p=D² 掷骰；命中 D→0.2 + 记 last_fire。

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
        refractory_h = float(_cfg("desire_v2_refractory_h", 1.5))
        since_fire_h = None
        if st.get("last_fire"):
            try:
                since_fire_h = (now - datetime.strptime(
                    st["last_fire"], "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
                if 0 <= since_fire_h < refractory_h:
                    growth_h *= 0.5             # 不应期（减速，不是硬闸）
            except Exception:
                since_fire_h = None
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
        _win = max(0.0, float(_cfg("desire_v2_feed_window_h", 6)))
        fed = bool(ignite_on and mood_warm and (gap_want is None or gap_want > _win))
        if fed:
            growth_h *= 0.7                     # 被接住＝喂饱（点火优先，不双算）
        if mood_sad:
            growth_h *= float(_cfg("desire_v2_sad_damp", 0.8))
        growth_h *= fac_ignite                  # 点火：亲密余温 → 涨得更快
        d = min(1.0, d + growth_h * dh * (1 - d))       # 饱和生长：越近 1 越慢（久别才浓）
        if mood_want:
            d = max(d, 0.35)                    # 她的笔：抬起点
        feed_decay = float(_cfg("desire_v2_feed_decay", 0.05)) if fed else 0.0
        if feed_decay:
            d = max(0.0, d - feed_decay * dh)   # 喂饱：真回落（按 Δh 线性，避免自激）
        # ── A：闸门因果（照积温 getTriggerTrace）──
        hm = now.strftime("%H:%M")
        night = ("23:00" <= hm or hm < "02:00")
        thr = float(_cfg("desire_v2_threshold", 0.55))
        gates, blocked = [], ""
        if night:
            gates.append(f"夜窗✓({hm})")
        else:
            gates.append("夜窗✗(差%s)" % _fmt_min(_night_gap_min(hm)))
            blocked = "夜窗"
        if not present:
            gates.append("不在场✓")
        else:
            gates.append("在场✗")
            blocked = blocked or "在场"
        if d > thr:
            gates.append(f"阈值✓({d:.2f}>{thr:.2f})")
        else:
            gates.append(f"阈值✗({d:.2f}，差{thr - d:.2f})")
            blocked = blocked or "阈值"
        if since_fire_h is not None and 0 <= since_fire_h < refractory_h:
            gates.append(f"不应期×0.5({since_fire_h:.1f}h<{refractory_h:g}h)")
        else:
            gates.append("不应期✓(%s)" % _fmt_since(now, st.get("last_fire")))
        fired, _roll, _p = False, None, None
        if night and d > thr and not present:
            _p = d * d
            _roll = random.random()
            if _roll < _p:                      # 锐化：p=D²（低档不冒泡）
                fired = True
                d = 0.2                         # 表达＝满足（分层回落）
                st["last_fire"] = now.strftime("%Y-%m-%d %H:%M:%S")
                st["last_satisfy"] = st["last_fire"]
            gates.append(f"掷骰{'✓' if fired else '✗'}(p={_p:.2f}，掷{_roll:.2f})")
        if blocked:
            gates.append(f"← 被{blocked}挡")
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
        if fed:
            _ex.append("喂饱")
        try:
            with open(V2_LOG, "a", encoding="utf-8") as f:
                f.write(f"[{now.strftime('%F %T')}] D={d:.2f} | Δh={dh:.1f}h | 因子×{fac} | "
                        f"在场={'是' if present else '否'} | 心情={mstr} | "
                        + ((" ".join(_ex) + " | ") if _ex else "")
                        + f"{'命中=③(→0.2)' if fired else '命中=否'} | "
                        f"since_fire={_fmt_since(now, st.get('last_fire'))} "
                        f"since_sat={_fmt_since(now, st.get('last_satisfy'))}"
                        + (f" | trace: {' '.join(gates)}" if _cfg("desire_v2_trace", True) else "")
                        + "\n")
        except Exception:
            pass
        return {"d": round(d, 3), "fire": fired}
    except Exception:
        return None


if __name__ == "__main__":
    # 自检：跑一拍，打印结果（影子无害）
    r = tick_and_shadow()
    print("desire_lib 自检 →", r)
    print("（影子日志：~/desire_shadow.log；events 里 kind=desire.tick）")
