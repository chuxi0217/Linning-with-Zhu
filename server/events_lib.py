#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""events_lib —— 事件脊柱与成本账本（W1 · 2026-09-24 · 家规微调 A 案）

咱家升级研究 v0.4 §1/§3 的第一铲：
  · events 表：chat.turn 双写（影子——只写不用）
  · token_ledger：每次 LLM 调用记账（只记不读）

纪律（照工单 W1）：
  1. 只写不用——读路径 W2 才议
  2. fail-open——写影子失败绝不拦主流程（「事件已发生，投影只是看法」）
  3. 开关——config.json 的 events_shadow / token_ledger_enabled，关掉即哑
  4. 与 memory_lib 同层（SQL 住 memory_lib + events_lib；两模块互不 import）
"""
import hashlib
import json
import os
import sqlite3
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
_ensured = False


def _cfg_flag(key):
    """读开关。读不到/出错 → False（保守=关）。"""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return bool(json.load(f).get(key, False))
    except Exception:
        return False


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _ensure(con):
    global _ensured
    if _ensured:
        return
    con.executescript("""
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  kind TEXT NOT NULL,
  actor TEXT NOT NULL,
  source TEXT NOT NULL,
  payload TEXT NOT NULL,
  trace_id TEXT,
  session_id TEXT,
  idem_key TEXT UNIQUE,
  visibility TEXT NOT NULL DEFAULT 'normal',
  supersedes INTEGER REFERENCES events(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);
CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind, id);
CREATE INDEX IF NOT EXISTS idx_events_trace ON events(trace_id);
CREATE INDEX IF NOT EXISTS idx_events_actor ON events(actor, id);
CREATE TABLE IF NOT EXISTS token_ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  trace_id TEXT,
  session_id TEXT,
  scene TEXT NOT NULL,
  model TEXT NOT NULL,
  in_tokens INTEGER NOT NULL,
  out_tokens INTEGER NOT NULL,
  cached_tokens INTEGER NOT NULL DEFAULT 0,
  thinking_level TEXT,
  latency_ms INTEGER,
  ok INTEGER NOT NULL DEFAULT 1,
  cost_est REAL,
  budget_bucket TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ledger_scene_ts ON token_ledger(scene, ts);
""")
    con.commit()
    _ensured = True


def record(kind, actor, source, payload=None, trace_id=None, session_id=None,
           idem_key=None, visibility="normal"):
    """写一条事件（影子）。fail-open：任何异常吞掉并返回 None。"""
    if not _cfg_flag("events_shadow"):
        return None
    try:
        pl = json.dumps(payload or {}, ensure_ascii=False, separators=(",", ":"))
        con = _conn()
        try:
            _ensure(con)
            cur = con.execute(
                "INSERT INTO events (kind, actor, source, payload, trace_id,"
                " session_id, idem_key, visibility) VALUES (?,?,?,?,?,?,?,?)",
                (kind, actor, source, pl, trace_id, session_id, idem_key, visibility))
            con.commit()
            return cur.lastrowid
        finally:
            con.close()
    except Exception:
        return None


def record_chat_turn(role, content, session_id="", trace_id=None, date=None):
    """chat.turn 双写专用：只落骨架（长度/md5/日期），不落全文（全文在 chats）。"""
    text = content or ""
    return record(
        "chat.turn",
        actor=("xiaoguai" if role == "小乖" else "linning"),
        source="chat",
        payload={
            "role": role,
            "len": len(text),
            "md5": hashlib.md5(text.encode("utf-8")).hexdigest()[:12],
            "date": date or "",
        },
        trace_id=trace_id,
        session_id=session_id or None,
    )


def ledger_record(scene, model, in_tokens, out_tokens, cached_tokens=0,
                  thinking_level=None, latency_ms=None, ok=1, cost_est=None,
                  budget_bucket="soul", trace_id=None, session_id=None):
    """记一笔 LLM 调用账（影子）。fail-open。"""
    if not _cfg_flag("token_ledger_enabled"):
        return None
    try:
        con = _conn()
        try:
            _ensure(con)
            cur = con.execute(
                "INSERT INTO token_ledger (trace_id, session_id, scene, model,"
                " in_tokens, out_tokens, cached_tokens, thinking_level, latency_ms,"
                " ok, cost_est, budget_bucket) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (trace_id, session_id, scene, model, int(in_tokens or 0),
                 int(out_tokens or 0), int(cached_tokens or 0), thinking_level,
                 latency_ms, int(ok), cost_est, budget_bucket))
            con.commit()
            return cur.lastrowid
        finally:
            con.close()
    except Exception:
        return None


def est_tokens(text):
    """流式无 usage 时的粗估：中文≈1字/token、英文≈4字符/token，统一按 字符数/2.5 兜底。"""
    try:
        return max(1, int(len(text or "") / 2.5))
    except Exception:
        return 0


def ledger_from_usage(scene, model, usage, latency_ms=None, ok=1,
                      budget_bucket="soul", thinking_level=None, trace_id=None,
                      session_id=None):
    """从 OpenAI 兼容响应的 usage 折算记账（含缓存命中识别；金额先不估，留 cost_est=None）。"""
    try:
        u = usage if isinstance(usage, dict) else {}
        pin = int(u.get("prompt_tokens") or u.get("input_tokens") or 0)
        pout = int(u.get("completion_tokens") or u.get("output_tokens") or 0)
        details = u.get("prompt_tokens_details")
        hit = int(u.get("prompt_cache_hit_tokens")
                  or (details.get("cached_tokens") if isinstance(details, dict) else 0)
                  or 0)
        return ledger_record(scene, model, pin, pout, cached_tokens=hit,
                             thinking_level=thinking_level, latency_ms=latency_ms,
                             ok=ok, cost_est=None, budget_bucket=budget_bucket,
                             trace_id=trace_id, session_id=session_id)
    except Exception:
        return None


def last_event(kind):
    """最近一条某类事件 (ts, payload 原文) —— 只读小助手（9-26：放电投影等用）。
    fail-open 回 None。"""
    try:
        con = _conn()
        try:
            _ensure(con)
            row = con.execute(
                "SELECT ts, payload FROM events WHERE kind=? ORDER BY id DESC LIMIT 1",
                (str(kind),)).fetchone()
            return row if row else None
        finally:
            con.close()
    except Exception:
        return None


if __name__ == "__main__":
    print("events_lib 自检……")
    n1 = record("selftest", "engine", "selftest", {"ok": True})
    n2 = ledger_record("selftest", "none", 1, 1, budget_bucket="embed")
    print("record →", n1, "| ledger →", n2)
    if n1 or n2:
        con = _conn()
        _ensure(con)
        con.execute("DELETE FROM events WHERE kind='selftest'")
        con.execute("DELETE FROM token_ledger WHERE scene='selftest'")
        con.commit()
        con.close()
        print("自检并清理 ✓")
    else:
        print("两个开关都关着（events_shadow / token_ledger_enabled）——影子未启用，属正常。")
