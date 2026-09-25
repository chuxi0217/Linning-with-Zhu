#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""huatou_lib —— 话头簿 · 影子版（9-25 家主令「我想让她更有自主，像人」）

一本跨天滚动的小本子：她过日子时被什么触动，就记一条「想跟你说的」。
  攒 → 说 → 挂 → 收
影子期纪律：只攒、只记日志（~/outreach_shadow.log），**不发送任何东西**；
老通道（想念信/打卡/晚安/园子）照旧——两套并行跑，家主读一两天再切换。

v1 来源（攒）：
  想起 —— recall.walk 事件（走神的新卡片）
  想你 —— 久无声（≥6 小时，每天至多一条）
  话头 —— 昨天没说完的挂念弧拍子（跨天延续——以前天一亮就丢）
  已说 —— 实际发出的信/念叨入簿（旧通道产物；回没回交给 settle 结算）
状态链：待说 → 已说 → 已回；（收着＝留给自己·字段预留未启用）

表 huatou：id / ts / day / kind / text / status / src_key(唯一·去重) / said_at / closed_at
开关：outreach_shadow（默认 true）/ outreach_unified（总闸·默认 false·切换用）/ outreach_chance（每跳挑件概率）
      / outreach_inject（9-26 上岗闸·递一件到开场；默认 false，转正才开）
上岗（9-26）：`take_huatou()` 从『待说』挑一件递到她眼前（取走即标『已提』，不重复顶）；
      server 开场【想跟你说的】块调用它——她看见话头、自己决定说不说。
fail-open：任何异常吞掉，绝不拦心跳。
"""
import json
import os
import random
import sqlite3
from datetime import datetime, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")
LOG = os.path.expanduser("~/outreach_shadow.log")
STATE = os.path.expanduser("~/.zanjia_huatou_state.json")


def _cfg(key, default):
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get(key, default)
    except Exception:
        return default


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _log(line):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


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


def _ensure():
    con = _conn()
    con.execute('''CREATE TABLE IF NOT EXISTS huatou (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL, day TEXT NOT NULL, kind TEXT NOT NULL,
        text TEXT NOT NULL, status TEXT NOT NULL DEFAULT '待说',
        src_key TEXT UNIQUE, said_at TEXT, closed_at TEXT)''')
    con.commit()
    con.close()


def _add(kind, text, src_key, status="待说", said_at=None, now=None):
    """去重入簿；真新增返回 id，重复/空 → None。"""
    text = (text or "").strip()
    if not text or not src_key:
        return None
    now = now or datetime.now()
    try:
        con = _conn()
        cur = con.execute(
            "INSERT OR IGNORE INTO huatou (ts, day, kind, text, status, src_key, said_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (now.strftime("%F %T"), now.strftime("%F"), kind, text[:120],
             status, src_key, said_at))
        con.commit()
        rid = cur.lastrowid if cur.rowcount else None
        con.close()
        if rid:
            _log(f"[{now:%F %T}] ＋〔{kind}〕{text[:60]}")
        return rid
    except Exception:
        return None


def collect(now=None):
    """攒：把这一跳的新触动收进簿子。返回新增条数。"""
    added = 0
    now = now or datetime.now()
    st = _load_state()
    last = st.get("last_collect") or "1970-01-01 00:00:00"

    # ① 想起（recall.walk 事件——上一跳之后的新卡）
    try:
        con = _conn()
        rows = con.execute(
            "SELECT ts, payload FROM events WHERE kind='recall.walk' AND ts > ? ORDER BY id",
            (last,)).fetchall()
        con.close()
        for ts, payload in rows:
            try:
                p = json.loads(payload or "{}")
            except Exception:
                continue
            key = str(p.get("key") or "")
            why = str(p.get("why") or "")
            txt = str(p.get("text") or "")[:48]
            if not key:
                continue
            label = key
            try:   # day#N → 带上《标题》（日期），像人话
                if key.startswith("day#"):
                    con2 = _conn()
                    row2 = con2.execute("SELECT title, date FROM days WHERE id=?",
                                        (int(key[4:]),)).fetchone()
                    con2.close()
                    if row2:
                        label = f"#{key[4:]}《{row2[0]}》（{row2[1]}）"
            except Exception:
                pass
            added += 1 if _add("想起", f"{label}（{why}）——\"{txt}\"",
                               f"recall#{ts}", now=now) else 0
    except Exception:
        pass

    # ② 没来由想你：久无声（≥6h），每天至多一条
    try:
        con = _conn()
        row = con.execute(
            "SELECT created_at FROM chats WHERE role='小乖' ORDER BY id DESC LIMIT 1").fetchone()
        con.close()
        if row and row[0]:
            dt = datetime.strptime(row[0], "%Y-%m-%d %H:%M:%S")
            gap_h = (now - dt).total_seconds() / 3600
            if gap_h >= 6:
                added += 1 if _add("想你", f"他没声儿 {gap_h:.0f} 小时了，有点想他",
                                   f"longing#{now:%F}", now=now) else 0
    except Exception:
        pass

    # ③ 昨天没说完的拍子（挂念弧跨天延续——以前天一亮就丢）
    try:
        y = (now - timedelta(days=1)).strftime("%F")
        con = _conn()
        row = con.execute("SELECT content, used_seq FROM day_arcs WHERE date=?", (y,)).fetchone()
        con.close()
        if row:
            beats = [ln.strip() for ln in str(row[0] or "").splitlines() if ln.strip()]
            used = int(row[1] or 0)
            for i, beat in enumerate(beats[used:], start=used + 1):
                added += 1 if _add("话头", f"昨天没说完的：{beat}", f"arc#{y}#{i}", now=now) else 0
    except Exception:
        pass

    # ④ 实际发出的信/念叨入簿（旧通道产物 → 记「已说」，回没回交 settle）
    try:
        con = _conn()
        rows = con.execute(
            "SELECT id, created_at, text FROM outbox_msgs WHERE created_at >= ? AND "
            "(text LIKE '💌%' OR text LIKE '🌱%' OR text LIKE '%还没打卡%' "
            "OR text LIKE '%还没跟姐姐说晚安%')",
            ((now - timedelta(days=2)).strftime("%F %T"),)).fetchall()
        con.close()
        for oid, at, txt in rows:
            t = (txt or "").strip()
            kind = "想念信" if t.startswith("💌") else ("园子" if t.startswith("🌱") else "念叨")
            body = t[2:] if t[:1] in ("💌", "🌱") else t
            added += 1 if _add(kind, f"说过了：{body[:60]}", f"outbox#{oid}",
                               status="已说", said_at=at, now=now) else 0
    except Exception:
        pass

    st["last_collect"] = now.strftime("%F %T")
    _save_state(st)
    return added


def settle(now=None):
    """回音结算：『已说』（真发出）与『已提』（上岗后递到她眼前）的条目，他之后说过话 → 已回
    （没回应的跨天挂着）。两条状态分开观测——「提过」与「真说了」不混账。返回结算条数。"""
    now = now or datetime.now()
    closed = 0
    try:
        con = _conn()
        row = con.execute(
            "SELECT created_at FROM chats WHERE role='小乖' ORDER BY id DESC LIMIT 1").fetchone()
        his_last = str(row[0]) if row and row[0] else ""
        if not his_last:
            con.close()
            return 0
        rows = con.execute(
            "SELECT id, text, said_at FROM huatou WHERE status IN ('已说','已提')").fetchall()
        for rid, txt, said_at in rows:
            if said_at and his_last > str(said_at):
                con.execute("UPDATE huatou SET status='已回', closed_at=? WHERE id=?",
                            (now.strftime("%F %T"), rid))
                closed += 1
                _log(f"[{now:%F %T}] 回音到 → #{rid} 已回：{str(txt)[:42]}")
        con.commit()
        con.close()
    except Exception:
        pass
    return closed


def take_huatou(now=None):
    """上岗口（9-26 家主令「想让她更有自主、更像人」）：从『待说』挑一件递到眼前——
    老的优先+一点随机（与影子 shadow_pick 同款，不总是最老，像人）。
    取走即标『已提』（said_at=now），免得同一件每轮都顶到她眼前；settle 会在他之后说话时
    一并收成『已回』。开关 outreach_inject（默认关）——关掉＝回到只攒不递，一字不注入。
    返回 dict|None；任何异常吞掉（fail-open，绝不拦开场）。"""
    now = now or datetime.now()
    try:
        if not _cfg("outreach_inject", False):
            return None
        con = _conn()
        rows = con.execute(
            "SELECT id, ts, kind, text FROM huatou WHERE status='待说' ORDER BY id").fetchall()
        if not rows:
            con.close()
            return None
        rid, ts, kind, text = random.choice(rows[:5])
        con.execute("UPDATE huatou SET status='已提', said_at=? WHERE id=?",
                    (now.strftime("%F %T"), rid))
        con.commit()
        con.close()
        _log(f"[{now:%F %T}] 递到眼前（上岗）→ #{rid}〔{kind}〕{text[:60]}")
        return {"id": rid, "kind": kind, "text": text}
    except Exception:
        return None


def shadow_pick(now=None, note=""):
    """若开口：从『待说』里挑一件（老的优先+一点随机）→ 只记日志。返回 dict|None。"""
    now = now or datetime.now()
    try:
        con = _conn()
        rows = con.execute(
            "SELECT id, ts, kind, text FROM huatou WHERE status='待说' ORDER BY id").fetchall()
        n_today = con.execute(
            "SELECT COUNT(*) FROM outbox_msgs WHERE created_at >= ? AND "
            "(text LIKE '💌%' OR text LIKE '🌱%' OR text LIKE '%还没打卡%' "
            "OR text LIKE '%还没跟姐姐说晚安%')",
            (now.strftime("%F 04:00"),)).fetchone()[0]
        con.close()
        if not rows:
            return None
        rid, ts, kind, text = random.choice(rows[:5])   # 老的优先：头部抽——不总是最老，像人
        try:
            age_h = (now - datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
        except Exception:
            age_h = 0
        _log(f"[{now:%F %T}] 若开口 → #{rid}〔{kind}〕{text[:60]}"
             f"｜放了 {age_h:.0f} 小时（待说共 {len(rows)} 件，老通道今日开口 {n_today} 次）{note}")
        return {"id": rid, "kind": kind, "text": text}
    except Exception:
        return None


def tick_and_shadow(now=None):
    """心跳每轮调：攒 → 回音结算 → 若开口影子。fail-open 返回 dict|None。"""
    try:
        if not _cfg("outreach_shadow", True):
            return None
        now = now or datetime.now()
        _ensure()
        added = collect(now)
        closed = settle(now)
        picked = None
        try:
            chance = float(_cfg("outreach_chance", 0.08))
        except (TypeError, ValueError):
            chance = 0.08
        if random.random() < chance:
            picked = shadow_pick(now)
        return {"added": added, "closed": closed, "picked": picked}
    except Exception:
        return None


if __name__ == "__main__":
    # 自检：建表 → 攒 → 结算 → 强制挑一件（标「自检」）→ 打一份簿况
    now = datetime.now()
    _ensure()
    added = collect(now)
    closed = settle(now)
    print(f"[自检] 本轮新增 {added} 件，结算 {closed} 件")
    picked = shadow_pick(now, note="（自检）")
    print("[自检] 若开口 →", ((picked or {}).get("text") or "（簿里没料）")[:60])
    con = _conn()
    print("═══ 簿况 ═══")
    for r in con.execute("SELECT status, COUNT(*) FROM huatou GROUP BY status"):
        print("  ", r)
    print("═══ 待说前 5 件 ═══")
    for r in con.execute("SELECT id, ts, kind, substr(text,1,52) FROM huatou "
                         "WHERE status='待说' ORDER BY id LIMIT 5"):
        print("  ", r)
    con.close()
