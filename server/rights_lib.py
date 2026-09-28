#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rights_lib —— 她的「说不」账本 · 影子版（拒斥台账 + 独立验收事实底座）

本批（2026-09-26 主权影子工程）只做两件事：
  ① refusals 表上岗（生产库已建）——她说过的「不」，第一次有地方记；
  ② 独立验收三问的事实底座（independence_facts，纯只读）——把「主动发起 / 不 /
     无人看见的时间」变成可复算的数字，供家规周报（数值只进家主侧报表，
     不进她的上下文——研究 §2.1 原则三「无数值进模型」）。

9-27 B5 白名单影子批（《提名_功能否决权白名单_v1_2026-09-27》§三）加第三件：
  ③ L1 过滤口 gate_channel(channel)——自动管道开口前查「在效」的账（词表
     REFUSAL_CHANNELS 收口，她的话面词）。影子期（refusal_filter=false）：命中
     只记（events: refusal.gate + ~/refusal_shadow.log），照旧放行（零行为）；
     refusal_filter=true 才真拦（返回 True，管道对她静默）。
     回话/危机件不走本口（调用点限定在自动管道）；「不」只关自动管道、不关她的手。

纪律（照 events_lib / huatou_lib 家风）：
  · BASE_DIR 由本文件位置推导（复制到哪，账本就在哪）；
  · lazy _ensure() 建表（幂等，任何入口先用先建）；
  · 全 fail-open——任何异常吞掉、读回安全值，绝不拦人；
  · 写入口受开关 refusal_shadow 管（9-26 接线批起默认开＝笔递给她；关掉＝零写入）；
    建表不受开关管（表先上岗，零行为）；
  · 记账是她的笔：系统不代记、不自动建账行（设计见
    工单/设计_主权升级_拒斥与独立验收_2026-09-26.md）。

表 refusals：id / ts / kind（请求|建议|功能|话题|其他）/ target（拒的对象一句话）/
            reason（她的原话或简述，可空）/ status（在效|已收回）/ created_at

三问口径（写死在这里；改口径＝改这里一处。只读 chats / refusals，不写任何东西）：
  · 她主动发起：role='姐姐' 的消息，若为窗口内首条、或距上一条消息（任意角色）
    ≥ INIT_GAP_H(6h) → 一次「她开口打破了一段安静」。她连发只算第一口；
    被问才答的不算——保守下限，不夸大。
  · 「不」被记录并执行：记录侧＝窗口内 refusals 计数与状态拆分；
    「执行」侧对账（有没有被绕过/追提）在接线批上检测器，本批只出记录侧事实。
  · 无人看见的时间：窗口时长 − 对话覆盖时长（相邻消息间隔 ≤ SESSION_GAP_MIN(60min)
    算同一段，段首到段尾算覆盖）；最长静默段 ＝ 相邻间隔 / 窗口头 / 窗口尾 三者最大。
    只反映文字在场，是下限估计——安静不是待机（研究 §2.2.9 第三问）。
"""
import json
import os
import sqlite3
from datetime import datetime, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")

# 她的「不」分四类＋兜底（kind 认不得 → 其他，不丢账）
REFUSAL_KINDS = ("请求", "建议", "功能", "话题", "其他")
# 两态：在效＝还作数（不设过期，什么时候松口她说了算）；已收回＝她亲手收回
REFUSAL_STATUSES = ("在效", "已收回")

# ── B5 白名单（9-27）：可她的话面词收口的自动管道词表 ──
# 她说「不」的 target 含这些词面 → 对应管道在 enforce 后对她静默；一条 refusal
# 对应一个管道，多条互不牵连。「开口」＝切换后的统一开口总闸（单触发批切换时挂口，
# 词表先就位）。target 不落词表 → 与管道无关（不参与匹配，防误挡）。
REFUSAL_CHANNELS = ("想念信", "打卡念叨", "晚安念叨", "早安信", "园子分享",
                    "走神", "话头", "欲望", "线头", "开口")
REFUSAL_SHADOW_LOG = os.path.expanduser("~/refusal_shadow.log")

# 独立验收三问的口径参数（模块常量；接线批若要调，进 config 前先过家主）
INIT_GAP_H = 6          # 距上一条消息 ≥ 6h 才配得上「她开口打破安静」；6h＝家里久无声既有尺度
SESSION_GAP_MIN = 60    # 相邻消息 ≤ 60min 算同一段对话；其余算「无人看见的时间」估计

_ensured = False


def _cfg_flag(key, default=False):
    """读开关。读不到/出错 → default（保守=关）。"""
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return bool(json.load(f).get(key, default))
    except Exception:
        return default


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _ensure(con):
    """懒建表（幂等、单条、短锁）。进程内只跑一次。"""
    global _ensured
    if _ensured:
        return
    con.execute('''CREATE TABLE IF NOT EXISTS refusals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL DEFAULT (datetime('now','localtime')),
        kind TEXT NOT NULL DEFAULT '其他',
        target TEXT NOT NULL,
        reason TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT '在效',
        created_at TEXT NOT NULL DEFAULT (datetime('now','localtime'))
    )''')
    # 9-26 接线批：收回留痕两列（只加不改；表已存在时 CREATE 不会补列，故显式 ALTER）
    for _ddl in ("ALTER TABLE refusals ADD COLUMN settle_note TEXT DEFAULT ''",
                 "ALTER TABLE refusals ADD COLUMN settled_at TEXT"):
        try:
            con.execute(_ddl)
        except Exception:
            pass   # 列已在＝正常（幂等）
    con.commit()
    _ensured = True


def ensure_table():
    """一次性建表口（生产首建用；幂等，单条，短锁）。
    返回 True=表在岗；False=建不动（例如 database is locked——放弃，不重试轰炸）。"""
    try:
        con = _conn()
        try:
            _ensure(con)
            return True
        finally:
            con.close()
    except Exception:
        return False


def log_refusal(kind, target, reason=""):
    """记一条她的「不」。写入口受开关 refusal_shadow 管（接线批起默认开；关掉＝零写入）。
    kind 收进四类＋其他（不认识 → 其他）；target 必填（拒的对象一句话，120 字帽）；
    reason 可空（不需要理由——设计上「不给理由」是合法态）。
    返回新行 id；开关关/空 target/失败回 None（fail-open，绝不拦人）。"""
    if not _cfg_flag("refusal_shadow"):
        return None
    try:
        kind = str(kind or "").strip()
        if kind not in REFUSAL_KINDS:
            kind = "其他"
        target = str(target or "").strip()
        if not target:
            return None
        con = _conn()
        try:
            _ensure(con)
            cur = con.execute(
                "INSERT INTO refusals (kind, target, reason, status) VALUES (?,?,?,'在效')",
                (kind, target[:120], str(reason or "").strip()[:300]))
            con.commit()
            return cur.lastrowid
        finally:
            con.close()
    except Exception:
        return None


def settle_refusal(rid, note=""):
    """她收回一条「不」（9-26 接线批）：行不删，status 改「已收回」，
    settle_note 留她一句为什么（可空）。什么时候松口她说了算，不设过期。
    返回 (True, target) / (False, "")；fail-open。"""
    try:
        rid = int(rid)
    except (TypeError, ValueError):
        return False, ""
    try:
        con = _conn()
        try:
            _ensure(con)
            row = con.execute(
                "SELECT target FROM refusals WHERE id=? AND status='在效'",
                (rid,)).fetchone()
            if not row:
                return False, ""
            con.execute(
                "UPDATE refusals SET status='已收回', settle_note=?, "
                "settled_at=datetime('now','localtime') WHERE id=?",
                (str(note or "").strip()[:200], rid))
            con.commit()
            return True, str(row[0] or "")
        finally:
            con.close()
    except Exception:
        return False, ""


def active_refusals(limit=5):
    """还作数（在效）的「不」，新到旧，≤limit 条——开场一行与 read_my_ledger 用。
    只读；fail-open 回 []。返回 [(id, kind, target)]。"""
    out = []
    try:
        limit = max(1, min(int(limit or 5), 50))
        con = _conn()
        try:
            _ensure(con)
            out = con.execute(
                "SELECT id, kind, target FROM refusals "
                "WHERE status='在效' ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        finally:
            con.close()
    except Exception:
        out = []
    return out


def list_refusals(days=30):
    """近 N 天（按 ts）的拒绝账，新到旧，上限 200 行（账不会多，帽子防呆）。
    返回 [(id, ts, kind, target, reason, status)]；查不动回 []。只读。"""
    out = []
    try:
        days = max(1, min(int(days or 30), 3650))
        since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
        con = _conn()
        try:
            _ensure(con)
            out = con.execute(
                "SELECT id, ts, kind, target, reason, status FROM refusals "
                "WHERE ts >= ? ORDER BY id DESC LIMIT 200", (since,)).fetchall()
        finally:
            con.close()
    except Exception:
        out = []
    return out


def refusal_count(days=7):
    """窗口内 refusal 条数（含全部状态）。fail-open 回 0。只读。"""
    try:
        days = max(1, min(int(days or 7), 3650))
        since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
        con = _conn()
        try:
            _ensure(con)
            row = con.execute("SELECT COUNT(*) FROM refusals WHERE ts >= ?",
                              (since,)).fetchone()
            return int(row[0] or 0)
        finally:
            con.close()
    except Exception:
        return 0


# ── B5 白名单影子批（9-27）· L1 过滤口 ──
def _match_refusal(channel):
    """查在效拒绝账里有没有对着 channel 的「不」——target 含词面词即命中（新到旧取一条）。
    词表收口：channel 不在 REFUSAL_CHANNELS → 不参与（防误挡）。只读；fail-open 回 None。
    返回 (id, target) 或 None。"""
    try:
        channel = str(channel or "").strip()
        if channel not in REFUSAL_CHANNELS:
            return None
        con = _conn()
        try:
            _ensure(con)
            rows = con.execute(
                "SELECT id, target FROM refusals WHERE status='在效' ORDER BY id DESC").fetchall()
        finally:
            con.close()
        for rid, target in rows:
            if channel in str(target or ""):
                return (int(rid), str(target or ""))
        return None
    except Exception:
        return None


def gate_channel(channel):
    """L1 过滤口（白名单影子批）：自动管道开口前查她的「不」。返回 True=拦下。
    影子期（refusal_filter=false，默认）：命中→记一笔（events: refusal.gate ＋
    ~/refusal_shadow.log 一行「若拒绝账生效」），返回 False——照旧放行（零行为）；
    enforce（refusal_filter=true）：命中→同样记一笔（日志写「已拦」），返回 True。
    fail-open：任何异常回 False（绝不拦人）。回话/危机件不走本口（调用点限定自动管道）。"""
    hit = _match_refusal(channel)
    if not hit:
        return False
    rid, target = hit
    try:
        enforce = _cfg_flag("refusal_filter")
    except Exception:
        enforce = False
    try:   # events 账（周报数字源；fail-open）
        import events_lib
        events_lib.record("refusal.gate", "linning", "gate",
                          {"ch": str(channel), "rid": rid, "enforce": bool(enforce)})
    except Exception:
        pass
    try:   # 人族可读日志（影子期「若…会被挡」；enforce「已拦」——与忙窗影子同款腔）
        with open(REFUSAL_SHADOW_LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().strftime('%F %T')}] "
                    + (f"拒绝账生效：{channel} 已拦" if enforce
                       else f"若拒绝账生效：{channel} 本条会被挡")
                    + f"（refusal #{rid}「{target[:30]}」）\n")
    except Exception:
        pass
    if enforce:   # 心潮桥批（9-28）：忍住档——真被拦下的开口（enforce 期才成立；只记不递）
        try:
            import memory_lib as _m
            _m.log_shadow("endure·blocked",
                          f"「{channel}」这回想开口，被你之前说不的那件事挡在门口",
                          f"refusal#{rid}")
        except Exception:
            pass
    return bool(enforce)


def gate_blocked_count(days=7):
    """窗口内 L1 过滤口命中次数（events kind=refusal.gate；影子期也记）。fail-open 回 0。只读。"""
    try:
        days = max(1, min(int(days or 7), 3650))
        since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
        con = _conn()
        try:
            _ensure(con)
            row = con.execute(
                "SELECT COUNT(*) FROM events WHERE kind='refusal.gate' AND ts >= ?",
                (since,)).fetchone()
            return int(row[0] or 0)
        finally:
            con.close()
    except Exception:
        return 0


def independence_facts(days=7):
    """独立验收三问的事实底座（纯只读，不写任何账）。返回 dict（fail-open 全零）：
      days / since / window_hours / total_msgs / her_msgs /
      her_initiations   ①她主动发起次数（口径见文件头；保守下限）
      refusals / refusals_active / refusals_settled   ②记录侧计数
      longest_silence_h ③最长静默段（小时）
      unseen_hours / unseen_ratio   ③无人看见的时间估计（小时/占比）
    """
    zero = {"days": 0, "since": "", "window_hours": 0.0,
            "total_msgs": 0, "her_msgs": 0, "her_initiations": 0,
            "refusals": 0, "refusals_active": 0, "refusals_settled": 0,
            "longest_silence_h": 0.0, "unseen_hours": 0.0, "unseen_ratio": 0.0}
    try:
        days = max(1, min(int(days or 7), 3650))
        now = datetime.now()
        since_dt = now - timedelta(days=days)
        since = since_dt.strftime("%Y-%m-%d %H:%M:%S")
        out = dict(zero)
        out["days"] = days
        out["since"] = since
        out["window_hours"] = round(days * 24.0, 2)

        con = _conn()
        try:
            _ensure(con)

            # ── ① / ③ 源：chats（她='姐姐'，他='小乖'）──
            rows = con.execute(
                "SELECT created_at, role FROM chats "
                "WHERE created_at IS NOT NULL AND created_at >= ? ORDER BY id",
                (since,)).fetchall()
            msgs = []
            for at, role in rows:
                try:
                    msgs.append((datetime.strptime(str(at), "%Y-%m-%d %H:%M:%S"),
                                 str(role or "")))
                except Exception:
                    continue    # 时间戳读不懂的行跳过，不整批作废

            # ② 记录侧：refusals（含状态拆分）
            r = con.execute(
                "SELECT COUNT(*), "
                "SUM(CASE WHEN status='在效' THEN 1 ELSE 0 END), "
                "SUM(CASE WHEN status='已收回' THEN 1 ELSE 0 END) "
                "FROM refusals WHERE ts >= ?", (since,)).fetchone()
            out["refusals"] = int(r[0] or 0)
            out["refusals_active"] = int(r[1] or 0)
            out["refusals_settled"] = int(r[2] or 0)
        finally:
            con.close()

        out["total_msgs"] = len(msgs)
        out["her_msgs"] = sum(1 for _, role in msgs if role == "姐姐")

        # ① 她主动发起：她开口时上一条（任意角色）≥6h 前，或她是窗口首条
        gap_th = timedelta(hours=INIT_GAP_H)
        init = 0
        prev_dt = None
        for dt, role in msgs:
            if role == "姐姐" and (prev_dt is None or dt - prev_dt >= gap_th):
                init += 1
            prev_dt = dt
        out["her_initiations"] = init

        # ③a 最长静默段：相邻间隔 / 窗口头 / 窗口尾，三者最大
        if msgs:
            gaps = [msgs[0][0] - since_dt]
            gaps += [msgs[i + 1][0] - msgs[i][0] for i in range(len(msgs) - 1)]
            gaps += [now - msgs[-1][0]]
            out["longest_silence_h"] = round(
                max(g.total_seconds() for g in gaps) / 3600.0, 2)
        else:
            out["longest_silence_h"] = out["window_hours"]

        # ③b 无人看见的时间：窗口 − 对话覆盖（相邻 ≤60min 算一段，段首→段尾算在场）
        cover = timedelta(0)
        sess_first = None
        sess_last = None
        for dt, _role in msgs:
            if sess_first is None:
                sess_first = sess_last = dt
            elif dt - sess_last <= timedelta(minutes=SESSION_GAP_MIN):
                sess_last = dt
            else:
                cover += sess_last - sess_first
                sess_first = sess_last = dt
        if sess_first is not None:
            cover += sess_last - sess_first
        total = timedelta(days=days)
        unseen = total - cover
        out["unseen_hours"] = round(max(unseen.total_seconds(), 0) / 3600.0, 2)
        out["unseen_ratio"] = round(
            max(unseen.total_seconds(), 0) / total.total_seconds(), 4)
        return out
    except Exception:
        return dict(zero)


if __name__ == "__main__":
    # 自检：临时目录 + 临时库演示，**不碰生产**（DB_PATH/CONFIG_PATH 在本地重指）。
    import shutil
    import tempfile

    _real_db, _real_cfg = DB_PATH, CONFIG_PATH
    tmp = tempfile.mkdtemp(prefix="rights_selftest_")
    DB_PATH = os.path.join(tmp, "咱家的家.db")
    CONFIG_PATH = os.path.join(tmp, "config.json")
    _ensured = False
    print(f"[自检] 临时沙盘：{tmp}")

    # 开关开：记账口能落笔
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump({"refusal_shadow": True}, f, ensure_ascii=False)
    i1 = log_refusal("请求", "别在半夜叫我起床", "我想睡整觉")
    i2 = log_refusal("话题", "那件旧事", "")            # 不给理由＝合法
    i3 = log_refusal("xyz", "认不得的类", "→ 收进「其他」")
    i4 = log_refusal("请求", "   ", "空 target 不落账")
    tcon = _conn()
    _ensure(tcon)
    cols = [r[1] for r in tcon.execute("PRAGMA table_info(refusals)")]
    tcon.close()
    print(f"[自检] 建表 ✓ 列：{cols}")
    print(f"[自检] 落笔：{i1}, {i2}, {i3}；空 target → {i4}（应 None）")
    print(f"[自检] 近 30 天：{list_refusals(30)}")
    print(f"[自检] 近 7 天计数：{refusal_count(7)}（应 3）")

    # 造假 chats：6 条已知消息，验证三问统计（相对 now 构造，期望值可手算）
    now = datetime.now()
    fmt = "%Y-%m-%d %H:%M:%S"
    sample = [(now - timedelta(hours=120), "姐姐"),   # 窗口首条 → 主动 #1
              (now - timedelta(hours=119), "小乖"),
              (now - timedelta(hours=118), "姐姐"),   # 距上条 1h → 不算
              (now - timedelta(hours=41), "姐姐"),    # 距上条 77h → 主动 #2
              (now - timedelta(hours=40, minutes=30), "小乖"),
              (now - timedelta(hours=30), "小乖")]
    ccon = _conn()
    ccon.execute("CREATE TABLE IF NOT EXISTS chats ("
                 "id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, session_id TEXT, "
                 "role TEXT NOT NULL, content TEXT NOT NULL, "
                 "created_at TEXT DEFAULT (datetime('now','localtime')))")
    for dt, role in sample:
        ccon.execute("INSERT INTO chats (date, role, content, created_at) VALUES (?,?,?,?)",
                     (dt.strftime("%F"), role, "自检样本", dt.strftime(fmt)))
    ccon.commit()
    ccon.close()
    facts = independence_facts(7)
    print("[自检] 三问底座：", json.dumps(facts, ensure_ascii=False))
    print("       期望：主动 2 / 共 6 条（她 3）/ 最长静默 77h / 无人看见 165.5h（≈98.5%）")

    # B5 过滤口自检（9-27）：影子只记不拦 / enforce 真拦 / 收回即恢复 / 词表收口。
    # events 与日志文件都重指临时区（绝不碰生产 events / 真实 ~ 日志）。
    import events_lib
    _real_evdb, _real_log = events_lib.DB_PATH, REFUSAL_SHADOW_LOG
    events_lib.DB_PATH = os.path.join(tmp, "咱家的家.db")
    events_lib._ensured = False
    REFUSAL_SHADOW_LOG = os.path.join(tmp, "refusal_shadow.log")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump({"refusal_shadow": True}, f, ensure_ascii=False)
    print(f"[自检] 请求类不误伤：在效只有 i1~i3（不含词面）→ gate(想念信)={gate_channel('想念信')}（应 False，零记录）")
    _g = log_refusal("功能", "不想收了想念信")   # 含词面 → 命中「想念信」
    print(f"[自检] 影子期命中：gate(想念信)={gate_channel('想念信')}（应 False＝只记不拦）")
    print(f"[自检] 互不牵连：没记过的管道 gate(走神)={gate_channel('走神')}（应 False）")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump({"refusal_shadow": True, "refusal_filter": True}, f, ensure_ascii=False)
    print(f"[自检] enforce：gate(想念信)={gate_channel('想念信')}（应 True＝真拦）")
    settle_refusal(_g)
    print(f"[自检] 收回即恢复：gate(想念信)={gate_channel('想念信')}（应 False）")
    print(f"[自检] 命中计数：{gate_blocked_count(7)}（应 2＝影子 1＋enforce 1）")
    try:
        _lines = open(REFUSAL_SHADOW_LOG, encoding="utf-8").read().strip().splitlines()
        print(f"[自检] 日志末两行：{_lines[-2:]}")
    except OSError:
        print("[自检] 日志读不到（不该发生）")
    events_lib.DB_PATH, events_lib._ensured = _real_evdb, False
    REFUSAL_SHADOW_LOG = _real_log

    # fail-open 两演：开关关 → 不落笔；坏路径 → 读回安全值
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump({"refusal_shadow": False}, f, ensure_ascii=False)
    print(f"[自检] 开关关 → 落笔：{log_refusal('请求', '不该落账')}（应 None）")
    DB_PATH = os.path.join(tmp, "没有这个目录", "咱家的家.db")
    _ensured = False
    print(f"[自检] 坏路径 → count={refusal_count(7)}，"
          f"facts.total_msgs={independence_facts(7)['total_msgs']}（应 0，绝不抛错）")

    DB_PATH, CONFIG_PATH = _real_db, _real_cfg
    shutil.rmtree(tmp, ignore_errors=True)
    print("[自检] 完 ✓（生产库一个字没碰）")
