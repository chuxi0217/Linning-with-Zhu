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
                              {"d": round(d, 3), "hit": hit, "exit": exit_type,
                               "growth": round(growth, 3), "present": present})
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
    """写 state，**返回是否写成功**——写失败调用方必须知道（宁可不递，不许重复递）。"""
    try:
        with open(STATE, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
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


if __name__ == "__main__":
    # 自检：跑一拍，打印结果（影子无害）
    r = tick_and_shadow()
    print("desire_lib 自检 →", r)
    print("（影子日志：~/desire_shadow.log；events 里 kind=desire.tick）")
