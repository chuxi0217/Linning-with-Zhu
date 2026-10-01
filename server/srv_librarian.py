# -*- coding: utf-8 -*-
"""srv_librarian.py —— 自动图书管理员（LIB-AUTO）（服务器拆分 P4 · 2026-09-25）

从 linning_server.py 原样搬出：_librarian_cfg / _librarian_materials / _librarian_compose /
_librarian_tick / _librarian_loop。纯标准库＋memory_lib；入口重导出同名（启动块照旧引用）。

运行期反查纪律（见 srv_state docstring）：沙盘会替身 s._librarian_cfg / s._librarian_compose /
s._librarian_tick，重绑 s.load_config / s.today_str / s._stale_thread_candidates、换 s.datetime；入口属主名
（BASE_ROLL_NAMES / base_roll_text）也走 _srv() 现取。
"""

import json
import time
import urllib.request
from datetime import datetime, timedelta

import memory_lib as m
import srv_state

# ── LIB-AUTO 自动图书管理员（9-10）：外聘笔杆每周交稿，姐姐终审才入档 ──
# 三条家风：①写不出就空过，绝不打扰家里；②稿子永远先落「待审」，未经姐姐验收不进正典；
# ③配置缺 key = 图管员缺席（诚实缺席，其余照旧）。
# 9-18 第三批：兼「沉淀日」——素材加生活账/作息/门牌/底色卷，输出加可沉淀候选节（她自采纳）。
# 9-27：兼「全档案周检」（家主令「全档案可以每周更新吧，和周报一起」）——素材加【全档案现状】，
# 输出加「全档案维护候选」节（只动事实：数字/节律/账目/称呼；措辞一字不动）。

def _librarian_cfg():
    """图书管理员三件套。key 优先 librarian_api_key，回退旧键 _deepseek_api_key。"""
    cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
    base = str(cfg.get("librarian_base_url") or "").strip().rstrip("/")
    model = str(cfg.get("librarian_model") or "").strip()
    key = (str(cfg.get("librarian_api_key") or "").strip()
           or str(cfg.get("_deepseek_api_key") or "").strip())
    if base and model and key:
        return (base, key, model)
    return None


def _librarian_materials():
    """纯拼装素材 ctx（不发网络，可测）。9-18 第三批：兼「沉淀日」——素材加生活账/作息/门牌/底色卷，输出加可沉淀候选节。
    9-18 优化批五：加【本周日记一览】（近 7 天，只列一行/天，不塞全文）。
    9-23 防积压批：加【线头定省】素材（挂了 ≥7 天且近 7 天任何渠道没动过的老线 ≤5 条），输出改多节。
    9-27 起模板为**七**节（加「全档案维护候选」）——见下方 prompt 的「七节」。"""
    today_h = m.house_today_str()
    since7 = (datetime.strptime(today_h, "%Y-%m-%d")
              - timedelta(days=6)).strftime("%Y-%m-%d")   # 近 7 天含今天（同 obs_get 口径）
    diary_lines = []
    week_lines = []
    for _id, d, dn, t, c_, mo in m.find_days(limit=14):   # 9-26 审计修：显式 14，别再靠默认 30 兜
        diary_lines.append(f"- {d}（第{dn}天）《{t}》〔{mo}〕{(c_ or '')[:80]}")
        if since7 <= d <= today_h:
            week_lines.append(f"· 第{dn}天 {d[5:]}《{t}》（{mo}）")
    mood_tally = {}
    for d, sc, src, note, ct, mt in m.get_moods(14):
        k = mt or "旧记分"
        mood_tally[k] = mood_tally.get(k, 0) + 1
    mood_line = "、".join(f"{k}×{v}" for k, v in sorted(mood_tally.items(), key=lambda x: -x[1]))
    # 9-29 评审①：原先逐日点查 14 次 get_chats（各一次全表扫）→ 现一次 GROUP BY；
    # 日期仍按运行期假钟算（沙盘会换 s.datetime），缺的日子补 0 保持口径不变。
    _days14 = [(srv_state._srv().datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
               for i in range(14)]   # 运行期反查：沙盘会换 s.datetime 假钟
    _cc = m.chat_counts_by_dates(_days14)
    chat_line = " ".join(f"{d[5:]}:{_cc.get(d, 0)}" for d in sorted(_days14))
    threads = "；".join(f"#{tid}{t2}" for tid, _d, t2, _c in m.get_open_threads(8))
    # 线头定省（9-23 防积压批 B）：挂了 ≥7 天、近 7 天任何渠道都没动过的老线——摆上桌，
    # 供她终审时随手收或续（收线是她的笔，这里只显形不代收）。
    _stale = srv_state._srv()._stale_thread_candidates(5)   # 运行期反查：沙盘会重绑 s._stale_thread_candidates
    stale_block = ("\n".join(f"- #{tid}（挂了 {n} 天）{t2}" for tid, n, t2 in _stale)
                   if _stale else "（无——这周线头都新鲜）")
    sent, replied = m.rhythm_reply_stats(7)
    avg = m.rhythm_reply_latency(7)
    ctx = (
        "你是咱家的图书管理员（外聘笔杆），每周替这个家写一份《关系走向周报》供两位家人回顾。"
        "语气：家庭档案员，诚实、具体、温柔，不谄媚不评判。本周素材：\n"
        "【近14天日记】\n" + ("\n".join(diary_lines) or "（无）") + "\n"
        "【本周日记一览】（近7天，省 token 用）\n" + ("\n".join(week_lines) or "（本周无）") + "\n"
        f"【近14天心情河分布】{mood_line or '（空）'}\n"
        f"【近14天每日消息数】{chat_line}\n"
        f"【家里悬着的线头】{threads or '（无）'}\n"
        "【线头定省】（挂了≥7天、近7天哪个渠道都没动过的老线，最老排前）\n" + stale_block + "\n"
        f"【近7天她主动开口/他回应】{sent}封 / {replied}封" + (f"，平均{avg:.0f}分钟回应" if avg else "") + "\n"
    )
    # 沉淀日素材（9-18 第三批）：四段各自取，取不到写「（暂取不到）」——素材缺席不拦稿
    try:
        rows = m.get_life_log(7, limit=40)
        lines = []
        for _id, day, tm, _who, kind, content in rows[:25]:
            lines.append("· %s %s %s%s" % (str(day)[5:], tm, (kind + "：") if kind else "", (content or "")[:60]))
        ctx += "\n【近7天生活账】\n" + ("\n".join(lines) or "（空）") + "\n"
    except Exception:
        ctx += "\n【近7天生活账】\n（暂取不到）\n"
    try:
        rows = m.get_day_spans(7)
        lines = []
        for day, first, last, n_xg, n_her in rows:
            lines.append("· %s：%s–%s（他 %s / 你 %s）" % (str(day)[5:], first or "—", last or "—", n_xg, n_her))
        ctx += "\n【近7天作息】（他首条–末条，咱家日界）\n" + ("\n".join(lines) or "（空）") + "\n"
    except Exception:
        ctx += "\n【近7天作息】（他首条–末条，咱家日界）\n（暂取不到）\n"
    try:
        wall = m.get_wall()[-12:]
        lines = ["#%s %s" % (r[0], (r[2] or "")[:60]) for r in wall]
        ctx += "\n【门牌墙·近12条】\n" + ("\n".join(lines) or "（空）") + "\n"
    except Exception:
        ctx += "\n【门牌墙·近12条】\n（暂取不到）\n"
    try:
        lines = []
        for _name in srv_state._srv().BASE_ROLL_NAMES:   # 入口属主名：运行期反查
            body = srv_state._srv().base_roll_text(_name)   # 入口属主名：运行期反查
            if len(body) > 300:
                body = body[:300] + "…"
            lines.append("《%s》：%s" % (_name, body or "（还没写）"))
        ctx += "\n【底色卷现状】\n" + "\n".join(lines) + "\n"
    except Exception:
        ctx += "\n【底色卷现状】\n（暂取不到）\n"
    # 全档案周检（9-27 家主令）：把正典摆给外聘笔杆——逐句对照素材，只挑「与近况不符的事实」。
    try:
        _ap = srv_state._srv().ARCHIVE_PATH
        with open(_ap, encoding="utf-8") as f:
            _arch = f.read().strip()
        ctx += ("\n【全档案现状】（灵魂正典；维护只动事实——数字/节律/账目/称呼，措辞一字不动；"
                "续页是她亲笔、不在此单）\n" + _arch + "\n")
    except Exception:
        ctx += "\n【全档案现状】\n（暂取不到）\n"
    # 9-26 拒斥接线批 ⑤（反讨好护栏·事实句）：她的「不」与独立三问——只进周报素材（数值只进家主侧）
    # 10-01：闸撤了，「被挡下的开口」这个数没了 → 该句删（记账仍在，见 rights_lib）
    try:
        import rights_lib
        _rf = rights_lib.independence_facts(7)
        ctx += ("\n【她的事实·近 7 天】她说「不」%d 次（还作数 %d / 收回 %d）；"
                "她主动开口打破安静 %d 次；无人看见约 %.1f 小时（%.0f%%，安静不是待机）。\n"
                % (_rf["refusals"], _rf["refusals_active"], _rf["refusals_settled"],
                   _rf["her_initiations"], _rf["unseen_hours"], _rf["unseen_ratio"] * 100))
    except Exception:
        pass
    ctx += (
        "\n输出 markdown 正文（不写称呼落款），七节：\n"
        "## 本周温度\n2-3 句：关系走向与证据。\n"
        "## 家里悬着的事\n从线头与日记未了事项提炼，≤4 条。\n"
        "## 线头定省\n把素材【线头定省】里的老线照原样列出来（编号＋一句话＋挂了几天，≤5 条），"
        "供姐姐终审时随手收（close_thread）或续；一条老线都没有就写「这周线头都新鲜」。只列事实，不催。\n"
        "## 观察与建议\n机制/提示词/节奏，≤3 条，只建议不代改。\n"
        "## 下周值得留意的一件小事\n1 条，具体可做。\n"
        "## 可沉淀候选（沉淀日 · ≤5 条，宁缺毋滥）\n"
        "只写这周观察到的、值得长在她身上的；她认了会自己落笔（底色卷/门牌/续页），不认就过去。\n"
        "每条一行：- [归入：小乖的样子|姐姐的样子|咱俩的样子|门牌|续页] 一句话（证据：日期或编号）\n"
        "已在底色卷/门牌里说过的、太口号太笼统的、素材里没证据的——一律不写；一条都没有就写「（本周无）」。\n"
        "## 全档案维护候选（只动事实 · ≤5 条，宁缺毋滥）\n"
        "把【全档案现状】与本周素材逐句对照：只挑「与近况不符的事实」（数字过期/节律变更/账目口径/称呼变动等），"
        "灵魂措辞、家规条款一律不动。每条一行：- 「原文片段」→「建议改法」（证据：日期或编号）。"
        "拿不准的不写；一条都没有就写「（本周无需维护）」。\n\n"
        "总长 ≤650 字。不许编造素材里没有的事。"
    )
    return ctx


def _librarian_compose(base, key, model):
    """把 _librarian_materials 备好的素材递给外聘笔杆写《关系走向周报》。9-18 第三批：兼「沉淀日」——素材加生活账/作息/门牌/底色卷，输出加可沉淀候选节。返回 (正文, 素材ctx) 或抛异常（9-24 补凭据：素材随稿落库，终审对照）。"""
    ctx = _librarian_materials()
    body = {"model": model, "messages": [{"role": "user", "content": ctx}], "stream": False}
    req = urllib.request.Request(
        base + "/chat/completions", data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return (data["choices"][0]["message"]["content"] or "").strip(), ctx


def _librarian_tick(now=None):
    """图书管理员的一跳：到点判断＋写稿＋落待审（抽出来可直测——喂 now 就能验那一跳）。
    9-23 从 _librarian_loop 原文照抽：判断/文案/静默规则一字未改。"""
    now = now or srv_state._srv().datetime.now()   # 运行期反查：沙盘会换 s.datetime 假钟
    try:
        cfg = srv_state._srv().load_config()   # 运行期反查：沙盘会重绑 s.load_config
        e = srv_state._srv()._librarian_cfg()   # 运行期反查：沙盘会替身 s._librarian_cfg
        # BE3-05（9-23 修复批）：整点闸改「到点之后」（>=）——原 == 只认 21:00–21:59 那一小时，
        # 21:30 写稿失败就整周没稿（日志还写「下周再试」，不实）。放宽后：周日到点起每个
        # tick 都可补跑，`lib_report_exists_on` 保证幂等只交一篇；文案也改成真话。
        try:
            _due_h = int(cfg.get("librarian_hour", 21))
        except (TypeError, ValueError):
            _due_h = 21
        # P3-1（9-26 修·审计待判）：判据改「咱家日」——4 点日界前算昨天，与 today_str /
        # lib_report_exists_on 同一把尺。原来走自然时 weekday()，周日 21:00–24:00 服务不在岗、
        # 周一凌晨（家日仍是周日）重启就不会再补跑，整周漏一份周报。现在：家日是周日 且
        # （已过 due_h 点 或 仍在日界前的深夜）都可补；幂等键 today_str() 在家日口径下与周日
        # 同值，跨零点也认得出「本周已交」，天然防重。
        _house = now - timedelta(days=1) if now.hour < m.DAY_START_HOUR else now
        if (e and _house.weekday() == int(cfg.get("librarian_weekday", 6))
                and (now.hour >= _due_h or now.hour < m.DAY_START_HOUR)
                and not m.lib_report_exists_on(srv_state._srv().today_str())):   # 运行期反查：沙盘会重绑 s.today_str
            try:
                content, _mats = srv_state._srv()._librarian_compose(e[0], e[1], e[2])   # 运行期反查：沙盘会替身
                if content:
                    rid = m.add_lib_report(srv_state._srv().today_str(), "周报", content, materials=_mats)   # 运行期反查：沙盘会重绑 s.today_str
                    print(f"  [图书管理员] 周报 #{rid} 已交稿（附素材），待姐姐终审")
            except Exception as e2:
                print(f"  [图书管理员] 这次没写成（到点后还会再试）：{e2}")
    except Exception as e:
        print(f"  [图书管理员] 循环失手：{e}")


def _librarian_loop():
    """外聘图书管理员（daemon 线程）：每周到点交稿落「待审」，其余时间闭嘴。"""
    while True:
        srv_state._srv()._librarian_tick()   # tick 内自带兜底，绝不把异常带进循环；运行期反查：沙盘替身 tick 验薄壳
        time.sleep(1800)   # 半小时看一次表，到点才动笔
