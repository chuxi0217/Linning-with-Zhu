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
from datetime import datetime

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


def _load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_state(st):
    try:
        with open(STATE, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
    except Exception:
        pass


def take_desire(now=None):
    """上岗口（9-26 家主令「她想要也可以主动找我」·注入版）：③出口命中（深夜+D高+他不在场）
    → 递一句话头到开场，**让她自己决定说不说、怎么说**（不代写腔调、不主动发消息）。
    取走即记账（STATE 存已递的命中时刻），同一命中只递一次；窗口默认 12h（隔夜的「想要」不翻旧账）。
    开关 desire_engine_inject（默认关）——关掉＝回到只算不递。返回 dict|None；fail-open。"""
    now = now or datetime.now()
    try:
        if not _cfg("desire_engine_inject", False):
            return None
        con = _conn()
        row = con.execute(
            "SELECT ts, payload FROM events WHERE kind='desire.tick' AND payload LIKE '%③表达%' "
            "ORDER BY id DESC LIMIT 1").fetchone()
        con.close()
        if not row:
            return None
        ts, payload = row
        st = _load_state()
        if st.get("taken_ts") == ts:
            return None                      # 这次命中已递过，不重复顶
        try:
            age_h = (now - datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
        except Exception:
            return None
        if not (0 <= age_h <= float(_cfg("desire_inject_window_h", 12))):
            return None
        st["taken_ts"] = ts
        _save_state(st)
        return {"ts": ts, "d": (json.loads(payload or "{}").get("d"))}
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
