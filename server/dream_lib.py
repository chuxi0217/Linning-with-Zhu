# -*- coding: utf-8 -*-
# dream_lib · 睡眠整理（她的梦）· v1 影子（2026-09-28 家主拍板；设计稿：
#   工单/设计_睡眠整理（她的梦）_v1_2026-09-28.md）
#   她睡着时（安静时段内核 03:00–06:59，与熄灯/日记补写错峰），家里记忆做一遍「只读的整理」——
#   夜里长出来的只有「提名」，原文一字不动，她的笔永远是她的。
#   v1 只干跑：热度分层读数＋梦三模式（归拢/牵线/回望）候选——全部只写 dream_shadow.log，
#   零产出零可见、不进任何模型上下文（数值只做读数）。
#   依据：kiwi-mem（热度分层/被想起续命）＋ DreamVault（治理梦游不治梦/卧室非病房/成分分离）
#   ＋ Bitterbot（梦模式清单挑三）＋ Mímir（学名注释：Zeigarnik/Spreading Activation）。
#   纪律：影子只读不写库、不打搅讲话、失败静默。
#   ⚠️ 隐藏依赖（9-29 ② 评审第二批·写明）：**热度分层依赖 events 影子**——`mem.inject` /
#   `mem.inject.used` 两串事件。events 记录一关（或被轮转/清理），热度读数会**静默为空**
#   （读数空≠没有旧事，是"看不见递过什么"）。所以本模块的读数只在 events 开着时有意义；
#   真要长期留痕，得给"递过/用过"建一张自己的小表（同 desire v2 用独立 state 的办法）。
import difflib
import json
import os
import sqlite3
import time
from datetime import datetime, timedelta

import memory_lib as m

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DREAM_LOG = os.path.join(BASE_DIR, "dream_shadow.log")
DREAM_STAMP = os.path.join(BASE_DIR, "dream_last.txt")

_STRONG_MOOD = ("低落", "难过", "委屈", "想哭", "哭", "生气", "不开心", "崩")
_SKIP_TOKENS = {"的", "了", "是", "在", "我", "他", "你", "和", "就", "都", "也", "很",
                "不", "还", "她", "咱家", "今天", "一天", "一个", "什么", "没有"}


def _say(line):
    """影子日志一行（fail-silent）。"""
    try:
        with open(DREAM_LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().strftime('%F %T')}] {line}\n")
    except Exception:
        pass


def _conn():
    return sqlite3.connect(m.DB_PATH, timeout=10)


def _tokens(text):
    text = str(text or "")
    try:
        import jieba
        return {w for w in jieba.lcut(text) if len(w) >= 2 and w not in _SKIP_TOKENS}
    except Exception:
        return {text[i:i + 2] for i in range(len(text) - 1)} - _SKIP_TOKENS


def heat_dry_run(con, now):
    """热度分层读数（kiwi-mem：被想起→续命）：近 14 天「递过的旧事」（mem.inject）
    按近度加权（≤3d×1.0 / ≤7d×0.6 / 其余×0.3）＋「用没用」（mem.inject.used ×2）
    ＋情绪浓度（day 条目看历史 mood）→ 若分层的档位读数。v1 初值，复盘后调；只写日志。"""
    since = (now - timedelta(days=14)).strftime("%Y-%m-%d %H:%M:%S")
    score = {}
    try:
        for ts, payload in con.execute(
                "SELECT ts, payload FROM events WHERE kind='mem.inject' AND ts >= ?", (since,)):
            try:
                obj = json.loads(payload or "{}")
            except Exception:
                continue
            try:
                age_d = max(0.0, (now - datetime.strptime(str(ts)[:19], "%Y-%m-%d %H:%M:%S")
                                  ).total_seconds() / 86400)
            except Exception:
                age_d = 7.0
            w = 1.0 if age_d <= 3 else (0.6 if age_d <= 7 else 0.3)
            for it in (obj.get("items") or []):
                try:
                    key = (str(it.get("k")), int(it.get("id") or 0))
                except Exception:
                    continue
                d = score.setdefault(key, {"hits": 0.0, "used": 0, "head": str(it.get("h") or "")})
                d["hits"] += w
        for _ts, payload in con.execute(
                "SELECT ts, payload FROM events WHERE kind='mem.inject.used' AND ts >= ?", (since,)):
            try:
                obj = json.loads(payload or "{}")
            except Exception:
                continue
            for h in (obj.get("hits") or []):
                try:
                    key = (str(h.get("k")), int(h.get("id") or 0))
                except Exception:
                    continue
                if key in score:
                    score[key]["used"] += 1
    except Exception:
        pass

    def _mood_bonus(k, i):
        if k != "day":
            return 0.0
        try:
            row = con.execute("SELECT mood FROM days WHERE id=?", (i,)).fetchone()
            mo = str((row or [""])[0] or "")
            if not mo:
                return 0.0
            return 2.0 if any(w in mo for w in _STRONG_MOOD) else 0.8
        except Exception:
            return 0.0

    if not score:
        # 9-29 ②：把"读数空"的**两种原因分开说**——真没递过 vs events 影子关着看不见（隐藏依赖）
        try:
            _n_ev = con.execute(
                "SELECT count(*) FROM events WHERE kind IN ('mem.inject','mem.inject.used') "
                "AND ts >= ?", (since,)).fetchone()[0]
        except Exception:
            _n_ev = -1
        if _n_ev == 0:
            _say("梦·热度｜读数空（近两周 **一条 mem.inject 记录都没有**）——注意本读数依赖 events 影子，"
                 "events 关着时它会静默为空，**不代表没有旧事**")
        else:
            _say(f"梦·热度｜近两周没有『被递过』的旧事，读数空（events 里另有 {_n_ev} 条注入记录）")
        return {"hot": 0, "warm": 0, "cold": 0}
    tiers = {"热": [], "温": [], "冷": []}
    for (k, i), d in score.items():
        s = d["hits"] + d["used"] * 2.0 + _mood_bonus(k, i)
        tier = "热" if s >= 3 else ("温" if s >= 1 else "冷")
        tiers[tier].append((s, k, i, d["head"]))
    for t in tiers:
        tiers[t].sort(reverse=True)
    top = tiers["热"][:3]
    _say(f"梦·热度｜若分层：热 {len(tiers['热'])} / 温 {len(tiers['温'])} / 冷 {len(tiers['冷'])}"
         + ("　热档例：" + "；".join(f"{h[:16]}（{s:.1f}）" for s, _k, _i, h in top) if top else ""))
    return {"hot": len(tiers["热"]), "warm": len(tiers["温"]), "cold": len(tiers["冷"])}


def merge_candidates(con, now):
    """归拢（Compression）：同卷内的重复/近义（小本本×小本本、近 30 天日记×日记），
    相似 ≥0.75 →「这几件可以归拢成一段」。只记候选，原文一字不动。"""
    notes_items, day_items = [], []
    try:
        for i, t in con.execute("SELECT id, text FROM notes ORDER BY id DESC LIMIT 40"):
            notes_items.append((f"小本本#{i}", str(t or "")))
        for i, d, t, c in con.execute(
                "SELECT id, date, title, content FROM days ORDER BY id DESC LIMIT 30"):
            day_items.append((f"日记 {d}", f"{t or ''} {str(c or '')[:80]}"))
    except Exception:
        pass
    pairs = []
    for group in (notes_items, day_items):
        for a in range(len(group)):
            for b in range(a + 1, len(group)):
                ta, tb = group[a][1].strip(), group[b][1].strip()
                if len(ta) < 6 or len(tb) < 6:
                    continue
                r = difflib.SequenceMatcher(None, ta, tb).ratio()
                if r >= 0.75:
                    pairs.append((r, group[a], group[b]))
    pairs.sort(reverse=True)
    seen, uniq = set(), []
    for r, A, B in pairs:   # 同一对文案只提一次（重复行会派生多条同文对，日志去重）
        key = (A[1], B[1])
        if key in seen:
            continue
        seen.add(key)
        uniq.append((r, A, B))
    for r, A, B in uniq[:3]:
        _say(f"梦·归拢｜若提名：把{A[0]}「{A[1][:18]}」和{B[0]}「{B[1][:18]}」归拢成一段（相似 {r:.2f}）")
    if not uniq:
        _say("梦·归拢｜没找到要归拢的（干净）")
    return len(uniq[:3])


def link_candidates(con, now):
    """牵线（Relation）：挂着的线头 × 近 14 天日记——共同词 ≥2 →「这两件可能有关」。
    （学名：Spreading Activation，Mímir。）只记候选。"""
    try:
        threads = m.get_open_threads(10) or []
    except Exception:
        threads = []
    days = []
    try:
        since_date = (now - timedelta(days=14)).strftime("%Y-%m-%d")
        for d, t, c in con.execute(
                "SELECT date, title, content FROM days WHERE date >= ? ORDER BY id DESC LIMIT 20",
                (since_date,)):
            days.append((str(d), str(t or ""), str(c or "")))
    except Exception:
        pass
    found = 0
    for th in threads:
        try:
            text = str(th[2] or "")
        except Exception:
            continue
        tt = _tokens(text)
        if len(tt) < 2:
            continue
        for d, t, c in days:
            shared = tt & _tokens(f"{t} {c[:120]}")
            if len(shared) >= 2:
                _say(f"梦·牵线｜若提名：线头「{text[:18]}」与日记 {d}「{t[:14]}」可能有关"
                     f"（共同词：{'、'.join(list(shared)[:3])}）")
                found += 1
                if found >= 3:
                    return found
    if not found:
        _say("梦·牵线｜线头与近两周日记没找到关联（干净）")
    return found


def replay_candidates(con, now):
    """回望（Replay）：高情绪浓度的旧事（≥14 天、强心情）——只在她的窗口里摆
    （v1 只记，不进行李）。"""
    try:
        older = (now - timedelta(days=14)).strftime("%Y-%m-%d")
        rows = con.execute(
            "SELECT date, day_no, title, mood FROM days WHERE date <= ? ORDER BY id DESC LIMIT 60",
            (older,)).fetchall()
    except Exception:
        rows = []
    strong = [(str(mo), d, dn, str(t or "")) for d, dn, t, mo in rows
              if mo and any(w in str(mo) for w in _STRONG_MOOD)]
    if strong:
        for mo, d, dn, t in strong[:2]:
            _say(f"梦·回望｜第{dn}天「{t[:16]}」（心情：{mo[:12]}）——只放在她的窗口里，不进行李")
    else:
        _say("梦·回望｜没有要回望的旧事（干净）")
    return len(strong[:2])


def dry_run(now=None):
    """一整套干跑（只写 dream_shadow.log）；返回读数 dict。失败静默（影子纪律）。"""
    now = now or datetime.now()
    stats = {"heat": {"hot": 0, "warm": 0, "cold": 0}, "merge": 0, "link": 0, "replay": 0}
    try:
        _say(f"═══ 梦（{now.strftime('%F')}）干跑 ═══")
        con = _conn()
        try:
            stats["heat"] = heat_dry_run(con, now)
            stats["merge"] = merge_candidates(con, now)
            stats["link"] = link_candidates(con, now)
            stats["replay"] = replay_candidates(con, now)
        finally:
            con.close()
        _say("梦·完（只记不递；原文一字未动）")
    except Exception as e:
        _say(f"梦·干跑失手（{e}）——静默过去，不打扰")
    return stats


def due_now(now=None):
    """她睡着时才做：安静时段内核 03:00–06:59（避开熄灯最迟兜底 ~02:00 与起床 07:00）。"""
    now = now or datetime.now()
    return now.hour in (3, 4, 5, 6)


def tick(now=None):
    """每夜一次干跑（stamp 防重）。fail-silent。返回 True=本 tick 跑了。"""
    try:
        now = now or datetime.now()
        if not due_now(now):
            return False
        stamp = now.strftime("%Y-%m-%d")
        try:
            if os.path.exists(DREAM_STAMP):
                with open(DREAM_STAMP, encoding="utf-8") as f:
                    if f.read().strip() == stamp:
                        return False
        except Exception:
            pass
        dry_run(now)
        with open(DREAM_STAMP, "w", encoding="utf-8") as f:
            f.write(stamp)
        return True
    except Exception:
        return False
