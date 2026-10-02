# -*- coding: utf-8 -*-
"""srv_jobs.py —— 家政四件：自动备份 / 每周库体检 / 周卷 / 卡片馆（服务器拆分 P3 · 2026-09-25）

从 linning_server.py 原样搬出：全库快照（SNAPSHOT_*、_snap_done_today/_snapshot_db/auto_snapshot）
＋ 周一库体检（_DBCK_STATE/_weekly_db_check）＋ 周卷（_WROLL_STATE/_WROLL_DIR/_week_roll_adopt/
_week_roll_pack）＋ 卡片馆只读扫描（CARDS_DIR/_CARDS_GROUPS/_cards_scan）。纯标准库＋memory_lib；
入口重导出同名（心跳循环 / 主入口 / Handler 照旧引用）。

运行期反查纪律（见 srv_state docstring）：凡入口属主名（s.WROLL_DIR / s.CARDS_DIR / s._week_roll_adopt /
s.SNAPSHOT_DIR / s.SNAPSHOT_KEEP / s.datetime）——函数内一律走 srv_state._srv().X 现取现用，
绝不在模块里存快照（假钟与常量重绑才对沙盘生效）。
"""

import os
import re
import urllib.parse
from datetime import datetime, timedelta

import memory_lib as m
import srv_state

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# ── 自动备份（二期i，2026-09-08）：开机一张+跨天一张，每天最多一张，只留最近 7 张 ──
SNAPSHOT_KEEP = 7
SNAPSHOT_DIR = os.path.join(BASE_DIR, "档案馆", "旧库备份")
_SNAP_STATE = {"day": None}


def _snap_done_today():
    srv = srv_state._srv()   # 运行期反查：沙盘换假钟 / 重绑 s.SNAPSHOT_DIR 才对这里生效
    pre = "咱家的家_自动备份_" + srv.datetime.now().strftime("%Y%m%d")
    try:
        return any(f.startswith(pre) for f in os.listdir(srv.SNAPSHOT_DIR))
    except OSError:
        return False


def _snapshot_db(src_path, dst_path):
    """9-18 后院深搜修：全库快照改走 sqlite 在线备份 API——shutil.copyfile 趁 WAL 未归并
    可能抄到半截事务、丢掉 -wal 里的新账；Connection.backup() 是官方承诺的一致快照。
    源按只读 URI（file:…?mode=ro）打开，目标即落盘文件；异常上抛，由调用方按家风打日志。"""
    import sqlite3
    # 中文/盘符路径：先正斜杠化再百分号编码，成 sqlite URI 规范（本机实测通）
    src_uri = "file:" + urllib.parse.quote(os.path.abspath(src_path).replace("\\", "/"))
    src = sqlite3.connect(src_uri + "?mode=ro", uri=True)
    try:
        dst = sqlite3.connect(dst_path)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()


def auto_snapshot(tag=""):
    """拍一张全库快照进 档案馆/旧库备份/，轮转只留最近 SNAPSHOT_KEEP 张。
    当天拍过就跳过；任何异常只打日志，绝不拖垮主流程。"""
    try:
        if _snap_done_today():
            # 10-02：今日已有备份（可能另一进程/重启拍的）→ 也把水位记到今天，
            #   否则 heartbeat 每跳都来 listdir 空转（跨天语义看着像没生效）。
            _SNAP_STATE["day"] = srv_state._srv().datetime.now().strftime("%Y%m%d")
            return
        srv = srv_state._srv()   # 运行期反查：沙盘换假钟 / 重绑 s.SNAPSHOT_DIR / s.SNAPSHOT_KEEP 才对这里生效
        os.makedirs(srv.SNAPSHOT_DIR, exist_ok=True)
        ts = srv.datetime.now().strftime("%Y%m%d_%H%M%S")
        dst = os.path.join(srv.SNAPSHOT_DIR, f"咱家的家_自动备份_{ts}_{tag}.db")
        _snapshot_db(m.DB_PATH, dst)   # 9-27 修：源走 memory_lib 库路径（随沙盘重绑）；9-18 后院深搜修：sqlite 备份 API（开机/跨天同一张手）
        snaps = sorted(f for f in os.listdir(srv.SNAPSHOT_DIR) if f.startswith("咱家的家_自动备份_"))
        # 10-02 修边界：`snaps[:-0]` == `snaps[:0]` == []（SNAPSHOT_KEEP=0 时轮转静默失效、
        #   快照无限堆）→ 显式按 KEEP 取值：keep<=0 视为"不留"。
        _keep = int(srv.SNAPSHOT_KEEP)
        _old = snaps[:-_keep] if _keep > 0 else snaps
        for old in _old:
            try:
                os.remove(os.path.join(srv.SNAPSHOT_DIR, old))
            except OSError:
                pass   # 删不掉就留着，下一轮再说
        _SNAP_STATE["day"] = srv.datetime.now().strftime("%Y%m%d")
        print(f"  [备份] 已拍：{os.path.basename(dst)}（自动备份在馆 {min(len(snaps), srv.SNAPSHOT_KEEP)} 张）")
    except Exception as e:
        print(f"  [备份] 这张没拍上：{e}")


# ── 每周库体检（9-18 优化批四·#7）：周一当日首跳验一次家底，只读不拦路 ──
_DBCK_STATE = {"day": None}   # 内存 guard：记跑过的自然日；跨天自然重置，重启后同日重跑无害


def _weekly_db_check(now=None):
    """每周一第一次心跳顺手验一次家底：PRAGMA quick_check（只读）+ days/chats 两张计数，
    结果落 obs_bump（db_check_ok / db_check_fail），日志一行。任何异常只打日志，绝不拦路。"""
    try:
        now = now or srv_state._srv().datetime.now()   # 运行期反查：沙盘换假钟才对这里生效
        if now.weekday() != 0 or _DBCK_STATE.get("day") == now.strftime("%Y%m%d"):
            return
        _DBCK_STATE["day"] = now.strftime("%Y%m%d")   # 先置再跑：验炸了也不当日重跑
        # 10-02 修：连接用 try/finally 关——原先 PRAGMA/COUNT 一抛错就跳过 conn.close() 漏连接。
        conn = m._conn()
        try:
            c = conn.cursor()
            row = c.execute("PRAGMA quick_check").fetchone()
            days = c.execute("SELECT COUNT(*) FROM days").fetchone()[0]
            chats = c.execute("SELECT COUNT(*) FROM chats").fetchone()[0]
        finally:
            conn.close()
        ok = bool(row) and str(row[0]).lower() == "ok"
        m.obs_bump("db_check_ok" if ok else "db_check_fail")
        print(f"  [体检] 周一体检{'通过' if ok else '发现异常：' + str(row[0] if row else '无回音')}"
              f"（days {days} 篇 / chats {chats} 条）")
    except Exception as e:
        try:
            m.obs_bump("db_check_fail")
        except Exception:
            pass
        print(f"  [体检] 这把没验成（{e}）")


# ── 周卷 v0（9-18 优化批五·#5）：周一把过去一周日记机械汇编成草稿落档，等她终审 ──
_WROLL_STATE = {"day": None}   # 内存 guard：照 _DBCK_STATE 款——记跑过的自然日
WROLL_DIR = os.path.join(BASE_DIR, "档案馆", "卷宗")


def _week_roll_adopt(now=None):
    """周卷归卷（9-18 优化批七·#5 后半）：落新卷之前，把到期草稿自动转正典——
    头行含「（草稿·待姐姐终审）」且卷止日期 ≤ 今天−7 天 → 头行改「（正典·YYYY-MM-DD 归卷）」。
    冷却一周自动归卷＝家主 9-18 令（不卡终审）：姐姐想改随时改，归卷只是记上到期。
    未到期不动、已归卷不动、读不动跳过；写回失败只日志（绝不拦路）。返回归卷笔数。"""
    adopted = 0
    try:
        wd = srv_state._srv().WROLL_DIR   # 运行期反查：沙盘「无目录不炸」用例会重绑 s.WROLL_DIR
        today = datetime.strptime(m.house_today_str(now), "%Y-%m-%d")
        if not os.path.isdir(wd):
            return 0
        for fn in sorted(os.listdir(wd)):
            if not (fn.startswith("周卷_") and fn.endswith(".md")):
                continue
            path = os.path.join(wd, fn)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    txt = f.read()
            except OSError as e:
                print(f"  [周卷] 归档跳过（读不动）：{fn}（{e}）")
                continue
            head, _sep, rest = txt.partition("\n")
            if "（草稿·待姐姐终审）" not in head:
                continue            # 已归卷/不是草稿头——不动
            mt = re.search(r"(\d{4}-\d{2}-\d{2}) → (\d{4}-\d{2}-\d{2})", head)
            if not mt:
                continue
            try:
                end_d = datetime.strptime(mt.group(2), "%Y-%m-%d")
            except ValueError:
                continue
            if (today - end_d).days < 7:
                continue            # 冷却期没满——不动
            new_head = head.replace("（草稿·待姐姐终审）",
                                    f"（正典·{today.strftime('%Y-%m-%d')} 归卷）")
            try:
                _tmp = path + ".tmp"
                with open(_tmp, "w", encoding="utf-8") as f:
                    f.write(new_head + _sep + rest)
                os.replace(_tmp, path)   # 原子写（9-29 审查修：中途被杀不留半截卷——半截卷会被"同名不覆盖"永久锁死）
                adopted += 1
                m.obs_bump("week_roll_adopt")
                print(f"  [周卷] 归卷：{fn}（冷却一周已满，自动转正典）")
            except OSError as e:
                print(f"  [周卷] 归档跳过（写不回，只记一笔）：{fn}（{e}）")
        return adopted
    except Exception as e:
        print(f"  [周卷] 归卷这把没走成（{e}）")
        return adopted


def _week_roll_pack(now=None):
    """每周一当日首跳，把过去 7 天（不含今天）的日记原样汇编成一份《周卷》草稿落档。
    机械汇编：只收编、不加工——终审合并进正典的笔归姐姐。同名不覆盖（起草过就等她看）；
    7 天无日记不落档（诚实缺席）；落新卷前先把到期草稿归卷（9-18 优化批七·#5 后半）；
    任何异常只打日志，绝不拦路。"""
    try:
        now = now or srv_state._srv().datetime.now()   # 运行期反查：沙盘换假钟才对这里生效
        # BE3-04（9-23 修复批）：时点判据从「自然星期」改「咱家日的周一」——原判据下
        # 周一凌晨（house 还是周日）会按周日算窗，再跑一次又出一份移窗卷（重叠数天；9-21 实案）。
        # 改后按「咱家日」判、同窗同名不覆盖，重叠从根上没了。guard 值＝咱家日那周的周一
        # （「咱家日」的日界由 `DAY_START_HOUR` 定，现=0＝自然日）
        # （键名沿用 "day"：沙盘既有套件按老键名复位 guard，不动它们的复位线）。
        hd = datetime.strptime(m.house_today_str(now), "%Y-%m-%d")
        if hd.weekday() != 0 or _WROLL_STATE.get("day") == hd.strftime("%Y%m%d"):
            return
        _WROLL_STATE["day"] = hd.strftime("%Y%m%d")   # 先置再跑：炸了也不当日重跑
        srv_state._srv()._week_roll_adopt(now)   # 先归卷（到期的旧草稿转正典），再落新卷；运行期反查（沙盘替身）
        today = datetime.strptime(m.house_today_str(now), "%Y-%m-%d")
        end = (today - timedelta(days=1)).strftime("%Y-%m-%d")     # 昨天
        start = (today - timedelta(days=7)).strftime("%Y-%m-%d")   # 起=前 7 天，共 7 天
        rows = [r for r in m.find_days(limit=0) if start <= r[1] <= end]   # 9-26 审计修：显式全量，别让默认 30 条截掉窗内最早几天
        rows.sort(key=lambda r: (r[1], r[0]))   # 日期正序；同日按 id 正序（收编顺序）
        if not rows:
            print(f"  [周卷] 这一周（{start} → {end}）没有日记，诚实缺席，不落档")
            return
        parts = [f"# 周卷 · {start} → {end}（草稿·待姐姐终审）", ""]
        for _id, d, dn, t, c_, mo in rows:
            parts.append(f"## 第{dn or m.day_no_of(d)}天 · {d[5:]} · 《{t or '（无题）'}》· {mo or '（无）'}")
            parts.append("")
            parts.append((c_ or "").strip())
            parts.append("")
        parts.append("— 机械汇编（不加工）：日记原样收录，等她终审合并进正典。")
        wd = srv_state._srv().WROLL_DIR   # 运行期反查：沙盘「无目录不炸」用例会重绑 s.WROLL_DIR
        os.makedirs(wd, exist_ok=True)
        fn = f"周卷_{start}_至_{end}.md"
        path = os.path.join(wd, fn)
        if os.path.exists(path):
            print(f"  [周卷] {fn} 已在馆（起草过不覆盖），跳过")
            return
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write("\n".join(parts) + "\n")
        os.replace(path + ".tmp", path)   # BE3-04 附带：先写临时件再原子换名——断电/杀掉
                                          # 不会留半截卷（半截卷会被「同名不覆盖」永久锁住）
        m.obs_bump("week_roll")
        print(f"  [周卷] 已落档：{fn}（收 {len(rows)} 天日记，草稿待终审）")
    except Exception as e:
        print(f"  [周卷] 这把没卷成（{e}）")


# ── 卡片馆只读接口（9-18 优化批七·#4 后半）：四馆正典 → JSON，给 app 翻卡用 ──
CARDS_DIR = os.path.join(BASE_DIR, "档案馆", "卡片馆")
_CARDS_GROUPS = (("姐姐志", "正典_姐姐志.md"), ("小乖志", "正典_小乖志.md"),
                 ("共同志", "正典_共同志.md"), ("物与地方", "正典_物与地方.md"))


def _cards_scan():
    """扫四馆正典（只读，绝不写）：解析「### [馆-N] 标题 / - 一句话： / - 依据： / - 置信：」
    → {"ok": True, "count": 总卡数, "groups": [{"key", "count", "cards": [{id,title,fact,
    source,confidence}]}]}。目录/文件缺=该馆空组（诚实缺席），任何读不动都不炸。"""
    groups, total = [], 0
    cdir = srv_state._srv().CARDS_DIR   # 运行期反查：沙盘缺目录/临时目录用例会重绑 s.CARDS_DIR
    for key, fn in _CARDS_GROUPS:
        cards, cur = [], None
        try:
            with open(os.path.join(cdir, fn), "r", encoding="utf-8") as f:
                txt = f.read()
        except OSError:
            txt = ""            # 缺文件/读不动：空组，诚实缺席
        for line in txt.splitlines():
            line = line.strip()
            mt = re.match(r"^###\s*\[([^\]]+)\]\s*(.*)$", line)
            if mt:
                if cur:
                    cards.append(cur)
                cur = {"id": mt.group(1).strip(), "title": mt.group(2).strip(),
                       "fact": "", "source": "", "confidence": ""}
                continue
            if cur is None:
                continue
            for pref, field in (("- 一句话：", "fact"), ("- 依据：", "source"),
                                ("- 置信：", "confidence")):
                if line.startswith(pref):
                    cur[field] = line[len(pref):].strip()
        if cur:
            cards.append(cur)
        groups.append({"key": key, "count": len(cards), "cards": cards})
        total += len(cards)
    return {"ok": True, "count": total, "groups": groups}
