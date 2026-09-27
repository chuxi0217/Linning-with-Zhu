#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""recall_lib —— 走神 · 联想式回忆（影子版）· 9-24 家主令「自然的联想/自然想起很有必要做」

现状：她的记忆是「问才答」（检索：他给话头 → 搜 → 浮上来）。
本模块补另一条腿：「不查也来」——走神时旧事自己浮上来（升级研究 §6.7）。

三种漫步（v1）：
  calendar 日历锚  —— 同月-日的历史日记（「一个月前的今天」）
  random   翻旧日记 —— 日记池随机翻一篇（避开近日翻过的·久违感）
  topic    话题第二跳 —— 近几条对话取词 → FTS 记忆池（day/note/letter）
            不取 top-1（那是检索），取第 2~8 名——「远而不生」

纪律：影子期只算只记（~/recall_shadow.log + events 账 recall.walk），不注入。
开关：recall_shadow（总闸·默认 true）/ recall_inject（注入闸·默认 false·转正才开）
      / recall_chance（每跳概率·默认 0.05；心跳 30 分钟一跳 → 约 2~3 次/天）
9-26 修（注入结构性失效）：候选从「只活内存 · 30 分钟过期」改为**落盘持久化**
（~/.zanjia_recall_state.json 的 cand/cand_at 键，跨进程/重启可读）+ 窗口放宽到 12 小时
（INJECT_WINDOW_S）——walk 与建 Session 时间几乎永远错开 30 分钟窗，不落盘/不放宽＝注入到不了眼前；
take 后消费清除协议不变。
9-26 修②（残留双投）：take 真取走时把候选 key 记入 state 的**已递集合**（delivered_keys，留最近
50 个）——旧 walk 事件已递到她眼前，话头簿 collect 重扫时必须跳过（不然日后经【想跟你说的】再提
一遍同一件事）；只读口 delivered_keys() 供 huatou_lib 查。
fail-open：任何异常吞掉，绝不拦心跳。
"""

import json
import os
import random
import sqlite3
import time
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")
SHADOW_LOG = os.path.expanduser("~/recall_shadow.log")
STATE_PATH = os.path.expanduser("~/.zanjia_recall_state.json")

# 种子词黑名单：虚词 + 高频人名词（搜「姐姐」会命中一切——不当初子）
_STOP = {
    "的", "了", "是", "我", "你", "他", "她", "不", "在", "有", "和", "就", "都", "也",
    "这", "那", "一个", "我们", "你们", "什么", "今天", "明天", "现在", "还是", "没有",
    "知道", "可以", "姐姐", "小乖", "自己", "就是", "不是", "怎么", "如果", "然后",
    "因为", "所以", "但是", "已经", "这个", "那个", "一下", "一点", "真的", "时候",
}

_TAG = {"calendar": "日历锚", "random": "翻旧日记", "topic": "话题第二跳"}

# ── 9-25 上岗：注入取用口（取走即清）──
# 影子期只记日志；转正后 server 开场来取一次，取走就清——一次走神只提一次，不车轱辘反复念。
# 9-26 修（注入结构性失效）：候选**落盘持久化**（同一 state 文件里 cand / cand_at 两键，与 recent
# 共存；磁盘为准＝跨进程/重启可读），窗口 30 分钟 → 12 小时。_LAST 保留为进程内镜像（兼容）。
INJECT_WINDOW_S = 12 * 3600      # 12 小时：隔夜的走神不翻旧账
DELIVERED_KEEP = 50              # 已递集合保留最近 N 个（防状态文件膨胀；够覆盖话头簿重扫窗）
_LAST = {"cand": None, "at": 0.0}


def take_recall(max_age_s=None):
    """取最近一次走神结果给开场注入；**取走即清**（同一次不走第二遍）。
    9-26 修：读落盘候选、窗口默认 12h（INJECT_WINDOW_S）——walk 与建 Session 常错开 30 分钟窗，
    不落盘/不放宽＝注入到不了眼前；超窗不注入并顺手清掉（隔夜不翻旧账）。显式传 max_age_s 仍照旧生效。
    9-26 修②：真取走时把 key 记入「已递」（delivered_keys）——话头簿重扫旧事件时跳过，不重提。
    注入闸关 / 没有 / 过期 → None（fail-open，绝不拦开场）。"""
    try:
        if not _cfg("recall_inject", False):
            return None
        c, at = _load_cand()
        if not c:
            return None
        win = INJECT_WINDOW_S if max_age_s is None else max_age_s
        if time.time() - float(at or 0) > float(win):
            _clear_cand()   # 超窗：不注入，也不留在盘上日后翻出来（没到她眼前，不算已递）
            return None
        # 9-27 修：先记「已递」，写不进去就不递（候选留着下次再来）——防「递了没记住」被话头簿再投一次。
        if not _mark_delivered(c.get("key")):
            return None
        _clear_cand()       # 取走即清——一次走神只提一次
        return c
    except Exception:
        return None


def delivered_keys():
    """只读：「最近已递」的候选 key 集合——被 take 真取走、递到她眼前过的走神。
    huatou collect 据此跳过已递过的旧 recall.walk 事件（事件还在库里，重扫时不能再收进簿子
    日后经【想跟你说的】再提一遍）。老状态文件没这个键 → 空集；读不到/坏文件 → 空集。fail-open。"""
    try:
        keys = _load_state().get("delivered_keys") or []
        return {str(k) for k in keys if k}
    except Exception:
        return set()


def _mark_delivered(key):
    """take 真取走候选时记一笔「已递」：state 文件 delivered_keys（去重、只留最近 DELIVERED_KEEP 个）。
    与 recent/cand 同住 state 文件、保留其它键。9-26 修②；9-27 修：**返回是否写成功**——
    写失败调用方宁可不递（不清候选），防日后经话头簿把同一条再投一次。"""
    try:
        key = str(key or "")
        if not key:
            return False
        st = _load_state()
        keys = [str(k) for k in (st.get("delivered_keys") or []) if k]
        if key in keys:
            keys.remove(key)
        keys.append(key)
        st["delivered_keys"] = keys[-DELIVERED_KEEP:]
        return _save_state(st)
    except Exception:
        return False


def current_cand_key(max_age_s=None):
    """只读：当前走神候选的 key（不消费、不清）——话头簿 collect 据此跳过同一次走神（9-26 修双投）。
    注入闸关 → None（走神不会递出，话头该照常收，不能把这条记忆憋死）；超窗 → None。fail-open。"""
    try:
        if not _cfg("recall_inject", False):
            return None
        c, at = _load_cand()
        if not c:
            return None
        win = INJECT_WINDOW_S if max_age_s is None else max_age_s
        if time.time() - float(at or 0) > float(win):
            return None
        return str(c.get("key") or "") or None
    except Exception:
        return None


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
        with open(SHADOW_LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _load_state():
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


# ── 9-26 修：走神候选落盘（注入结构性失效）——cand / cand_at 与 recent 同住 state 文件 ──

def _save_state(st):
    """写 state 文件（tmp+os.replace 原子写；9-27 修：防写一半崩把 delivered/候选全丢）。返回是否成功。"""
    try:
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
        os.replace(tmp, STATE_PATH)
        return True
    except Exception:
        return False


def _save_cand(cand):
    """候选落盘 + 进程内镜像。保留 state 其它键（recent 等）。fail-open。9-26 修。"""
    at = time.time()
    try:
        _LAST["cand"], _LAST["at"] = cand, at
    except Exception:
        pass
    st = _load_state()
    st["cand"] = cand
    st["cand_at"] = at
    _save_state(st)


def _load_cand():
    """读候选 (cand, at)——**磁盘为准**（跨进程/重启可读）。读不到 → (None, 0.0)。fail-open。9-26 修。"""
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            st = json.load(f)
        c = st.get("cand")
        if isinstance(c, dict) and c.get("key"):
            return c, float(st.get("cand_at") or 0)
    except Exception:
        pass
    return None, 0.0


def _clear_cand():
    """消费/超窗后清除候选（磁盘 + 镜像）；保留 recent 等其它键。fail-open。9-26 修。"""
    try:
        _LAST["cand"], _LAST["at"] = None, 0.0
    except Exception:
        pass
    try:
        st = _load_state()
        if "cand" in st or "cand_at" in st:
            st.pop("cand", None)
            st.pop("cand_at", None)
            _save_state(st)
    except Exception:
        pass


def _remember(key):
    """记一笔「翻过了」——近日降权用（久违感）。"""
    try:
        st = _load_state()
        recent = [k for k in st.get("recent", []) if k != key]
        recent.append(key)
        st["recent"] = recent[-12:]
        _save_state(st)
    except Exception:
        pass


def _seed_words(text, k=3):
    """切词取种子（她的话里挑内容词）——jieba 缺席退正则，宁缺勿滥。"""
    cand = []
    try:
        import memory_lib as m
        jb = getattr(m, "jieba", None)
        if jb is not None:
            cand = jb.lcut(text or "")
    except Exception:
        pass
    if not cand:
        import re
        cand = re.findall(r"[\u4e00-\u9fff]{2,4}", text or "")
    seen, out = set(), []
    for w in cand:
        w = (w or "").strip()
        if len(w) < 2 or w in _STOP or w in seen:
            continue
        if not all("\u4e00" <= ch <= "\u9fff" for ch in w):
            continue
        seen.add(w)
        out.append(w)
    out.sort(key=len, reverse=True)   # 长词更具体，优先
    pool = out[:20]
    random.shuffle(pool)
    return pool[:k]


def _months_since(date_str, today):
    """'YYYY-MM-DD' → 距 today 的月数（「N 个月前的今天」用）。"""
    try:
        y, mo, _d = (int(x) for x in date_str.split("-"))
        return max((today.year - y) * 12 + (today.month - mo), 0)
    except Exception:
        return 0


def _walk_calendar(now):
    """日历锚：同「日」的历史日记——「一个月前的今天」。没料回 None。"""
    dd = now.strftime("%d")
    con = _conn()
    try:
        rows = con.execute(
            "SELECT id, date, title, content FROM days "
            "WHERE substr(date, 9, 2) = ? AND date < ? ORDER BY date DESC LIMIT 3",
            (dd, now.strftime("%Y-%m-%d"))).fetchall()
    finally:
        con.close()
    if not rows:
        return None
    rid, rdate, rtitle, rcontent = random.choice(rows)
    n = _months_since(rdate, now)
    why = f"{n} 个月前的今天" if n >= 1 else "往月同日"
    return {"type": "calendar", "key": f"day#{rid}",
            "ref": f"#{rid}《{rtitle}》（{rdate}）",
            "text": (rcontent or "").strip().replace("\n", " ")[:80],
            "why": why}


def _walk_random():
    """翻旧日记：日记池随机翻一篇——避开近日翻过的。"""
    st = _load_state()
    recent = set(st.get("recent", []))
    con = _conn()
    try:
        rows = con.execute(
            "SELECT id, date, title, content FROM days ORDER BY RANDOM() LIMIT 12").fetchall()
    finally:
        con.close()
    pick = None
    for r in rows:
        if f"day#{r[0]}" not in recent:
            pick = r
            break
    if pick is None and rows:
        pick = rows[0]
    if not pick:
        return None
    rid, rdate, rtitle, rcontent = pick
    return {"type": "random", "key": f"day#{rid}",
            "ref": f"#{rid}《{rtitle}》（{rdate}）",
            "text": (rcontent or "").strip().replace("\n", " ")[:80],
            "why": "翻旧日记"}


def _walk_topic():
    """话题第二跳：近几条对话取词 → FTS 记忆池 → 中段名次（「远而不生」）。"""
    con = _conn()
    try:
        rows = con.execute(
            "SELECT role, content FROM chats ORDER BY id DESC LIMIT 6").fetchall()
    finally:
        con.close()
    text = " ".join((c or "") for _r, c in rows)
    for word in _seed_words(text, 3):
        try:
            import memory_lib as m
            res = m.fts_search(word, kinds=("day", "note", "letter"), limit=8)
        except Exception:
            continue
        for kind in ("day", "note", "letter"):
            hits = res.get(kind) or []
            pool = hits[1:] if len(hits) > 1 else []   # 不取 top-1——那是检索
            if not pool:
                continue
            hit = random.choice(pool)
            rank = hits.index(hit) + 1
            if kind == "day":
                hid, hdate, _hno, htitle, hcontent, _mood = hit
                return {"type": "topic", "key": f"day#{hid}",
                        "ref": f"#{hid}《{htitle}》（{hdate}）",
                        "text": (hcontent or "").strip().replace("\n", " ")[:80],
                        "why": f"从「{word}」联想（第 {rank} 名·非首条）"}
            if kind == "note":
                hid, htext, hct = hit
                return {"type": "topic", "key": f"note#{hid}",
                        "ref": f"随手记#{hid}（{str(hct)[:10]}）",
                        "text": (htext or "").strip().replace("\n", " ")[:80],
                        "why": f"从「{word}」联想（第 {rank} 名）"}
            hid, htext, hct = hit   # letter
            return {"type": "topic", "key": f"letter#{hid}",
                    "ref": f"信#{hid}（{str(hct)[:10]}）",
                    "text": (htext or "").strip().replace("\n", " ")[:80],
                    "why": f"从「{word}」联想（第 {rank} 名）"}
    return None


def tick_and_shadow(now=None):
    """心跳每轮调：概率闸 → 挑一条腿漫步 → 只记日志（+events 账）。fail-open 返回 dict|None。"""
    try:
        if not _cfg("recall_shadow", True):
            return None
        try:
            chance = float(_cfg("recall_chance", 0.05))
        except (TypeError, ValueError):
            chance = 0.05
        if random.random() >= chance:
            return None
        now = now or datetime.now()
        kind = random.choices(("calendar", "random", "topic"),
                              weights=(0.35, 0.35, 0.30))[0]
        if kind == "calendar":
            cand = _walk_calendar(now)
        elif kind == "random":
            cand = _walk_random()
        else:
            cand = _walk_topic()
        if not cand:
            return None
        _log(f"[{now.strftime('%F %T')}] 走神·{_TAG[kind]} ｜ 种子={cand['why']}\n"
             f"    → {cand['ref']}：\"{cand['text']}\"")
        _remember(cand["key"])
        _save_cand(cand)              # 9-26 修：落盘持久化（跨进程/重启可读；take 后消费清除）
        try:
            import events_lib
            events_lib.record("recall.walk", "linning", "heartbeat",
                              {"type": cand["type"], "key": cand["key"],
                               "why": cand["why"], "text": cand["text"][:60]})
        except Exception:
            pass
        return cand
    except Exception:
        return None


if __name__ == "__main__":
    # 自检：三种腿各走一次（不过概率闸），样张落日志供家主直接读
    now = datetime.now()
    for name, cand in (("日历锚", _walk_calendar(now)),
                       ("翻旧日记", _walk_random()),
                       ("话题第二跳", _walk_topic())):
        if cand:
            _log(f"[{now.strftime('%F %T')}] 走神·{name}（自检样张） ｜ 种子={cand['why']}\n"
                 f"    → {cand['ref']}：\"{cand['text']}\"")
            print(f"[自检] {name} → {cand['ref']}")
        else:
            print(f"[自检] {name} → （这次没料）")
