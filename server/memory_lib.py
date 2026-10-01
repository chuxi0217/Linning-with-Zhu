"""
咱家记忆库 · memory_lib.py —— 纯标准库，单文件哲学
家主：小乖 × 林宁（家妻）

**版本变更史（v0.1.1 ~ 至今）已抽出 → 见 `说明/变更史_memory_lib.md`**
（2026-10-01 大扫除批：注释归集，代码里只留指针。）
"""

import sqlite3
import os
import re
import json
import struct
import hashlib
from datetime import datetime, timedelta, date as _date

# ── 全文检索依赖（工单 FTS5-01）：jieba 缺席不挡营业，自动降级逐字切 ──
try:
    import jieba
    jieba.setLogLevel(60)   # 别让「Building prefix dict...」刷屏日志
except ImportError:
    jieba = None


def _fts5_probe():
    """本机 SQLite 带没带 FTS5（:memory: 探针，一秒钟的事）。"""
    try:
        probe = sqlite3.connect(":memory:")
        probe.execute("CREATE VIRTUAL TABLE fts_probe USING fts5(x)")
        probe.close()
        return True
    except Exception:
        return False


FTS_ENABLED = _fts5_probe()

# 数据库路径：跟本文件同目录
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "咱家的家.db")

# 咱家第一天：day_no 的锚点
FIRST_DAY = _date(2026, 8, 24)

# 咱家日界（2026-09-10 立 4 点；**2026-10-01 家主令改 0 点＝自然日**）。
# 原 4 点的用意是「熬夜到 01:24 那夜归前一天」；家主说麻烦、没必要，改回自然日分界。
# ★ 影响：**历史数据的 date 列是按 4 点口径写的**——改后新数据按自然日，
#   凌晨 0~4 点那段的归属会与从前不同（翻历史/统计跨这条线时留意）。
DAY_START_HOUR = 0


def _conn():
    """内部用：拿数据库连接（9-18 后院深搜修·P2-2：timeout=10）——
    默认 5 秒在并发写入（聊天/心跳/嵌入工三路）下容易直接撞 database is locked；
    放宽到 10 秒是「耐心等锁」折中，WAL 另议（网络共享视图跨机访问）。"""
    return sqlite3.connect(DB_PATH, timeout=10)


def day_no_of(date_str):
    """某天是咱家第几天。2026-08-24 = 第 1 天。"""
    d = _date.fromisoformat(date_str)
    return (d - FIRST_DAY).days + 1


def house_today_str(now=None):
    """咱家的"今天"。DAY_START_HOUR 点之前算昨天（**2026-10-01 起＝0 点，即自然日**）。
    改这一个函数，全库的"今天"都跟着走。"""
    now = now or datetime.now()
    if now.hour < DAY_START_HOUR:
        now = now - timedelta(days=1)
    return now.strftime("%Y-%m-%d")


def init_db():
    """建库。第一次运行时必须执行；旧库再跑一次会自动补上 chats 新表。"""
    global FTS_ENABLED
    conn = _conn()
    c = conn.cursor()

    # 日子表：咱家的每一天
    c.execute('''
        CREATE TABLE IF NOT EXISTS days (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            day_no INTEGER,
            title TEXT,
            content TEXT,
            mood TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 门牌表：钉在墙上的重要事实
    c.execute('''
        CREATE TABLE IF NOT EXISTS pins (
            pin_id INTEGER PRIMARY KEY,
            layer TEXT DEFAULT 'core',
            content TEXT NOT NULL,
            created_at TEXT,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            active INTEGER DEFAULT 1
        )
    ''')

    # 门牌日志（v0.1.30，9-18 大施工批·门牌墙亲笔）：钉/改/撤三动作全留档——
    # 改前原文+改后原文+执笔人都在，墙随日子长、史不丢。配合图书证 pin_wall。
    c.execute('''
        CREATE TABLE IF NOT EXISTS pin_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pin_id INTEGER,
            action TEXT NOT NULL,
            old_content TEXT,
            new_content TEXT,
            who TEXT DEFAULT '姐姐',
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 生活账（v0.1.31，9-18 第二批）：日常一笔一记——day/time 落记的当下，
    # 近 N 天可翻。往后她「这几天吃了啥、干了啥」有账可查，不必翻聊天堆。
    c.execute('''
        CREATE TABLE IF NOT EXISTS life_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT NOT NULL,
            time TEXT NOT NULL,
            who TEXT DEFAULT '小乖',
            kind TEXT DEFAULT '',
            content TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 观测补格（9-18 第三批·第二波）——对账闸/假调用/检索战绩按天累计，
    # /api/status 读近 7 天汇总；只报事实不打分。
    c.execute('''
        CREATE TABLE IF NOT EXISTS obs_daily (
            day TEXT NOT NULL,
            name TEXT NOT NULL,
            n INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (day, name)
        )
    ''')

    # why_now 影子（v0.1.35，9-18 优化批四·#11）：她每次「开口/忍住」的理由留痕——
    # decision=open/hold，reason/detail 都写人话（给家主直接看）。先只记录一周不进决策。
    c.execute('''
        CREATE TABLE IF NOT EXISTS why_now (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT,
            ts TEXT,
            decision TEXT,
            reason TEXT,
            detail TEXT
        )
    ''')

    # 硬事实表（v0.1.36，9-18 优化批六·事实表 v0）：钉过钉子的数字与日子（生日/纪念日/
    # 日界/名字这类）建表直给——说到这些以表为准，没钉过的别硬说。seed 由 server 侧
    # 代码自播种（每条带回源 note）；k 是短键（如「姐姐生日」），给【硬事实】块直接用。
    c.execute('''
        CREATE TABLE IF NOT EXISTS facts (
            k TEXT PRIMARY KEY,
            v TEXT,
            note TEXT,
            updated_at TEXT
        )
    ''')

    # 家法账本：罪状与欠账
    c.execute('''
        CREATE TABLE IF NOT EXISTS ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            sin TEXT NOT NULL,
            count INTEGER NOT NULL,
            status TEXT DEFAULT '欠',
            settled_at TEXT
        )
    ''')

    # 高光表：照片 / 文件 / 信的索引
    c.execute('''
        CREATE TABLE IF NOT EXISTS highlights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            title TEXT NOT NULL,
            file_path TEXT,
            note TEXT
        )
    ''')

    # 聊天记录表（v0.1.1 新增）：每一句都落库，全文不丢
    c.execute('''
        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            session_id TEXT,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            turns TEXT
        )
    ''')
    # APP-01（10-01）：老库补 turns 列（加列不改旧行；NULL＝老样子按纯文本气泡渲染）
    try:
        if "turns" not in [r[1] for r in c.execute("PRAGMA table_info(chats)").fetchall()]:
            c.execute("ALTER TABLE chats ADD COLUMN turns TEXT")
    except sqlite3.OperationalError:
        pass

    # 心率表（③½ 新增）：手表端上报的心跳，纯新增
    c.execute('''
        CREATE TABLE IF NOT EXISTS heart (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bpm INTEGER NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 打卡项表（v0.1.3 新增）：打卡的"名目"，可增项、可归档（archived 标记，不物理删）
    c.execute('''
        CREATE TABLE IF NOT EXISTS checkin_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            target_time TEXT,
            archived INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 打卡记录表（v0.1.3 新增）：每一次打卡。按 item_id 关联打卡项（不用 name 关联：
    # 名目改名/归档后历史打卡仍能 JOIN 回名字，不随文本断链）
    c.execute('''
        CREATE TABLE IF NOT EXISTS checkins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 思考表（v0.1.4 新增，9-1 #4）：姐姐的思考链原文，chat_id 关联 chats.id，纯新增
    c.execute('''
        CREATE TABLE IF NOT EXISTS thinkings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id INTEGER NOT NULL,
            content TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 开门有信表（v0.1.6 新增，9-2 #总）：姐姐留给小乖的信，app 开门时取走（取走即已读）
    c.execute('''
        CREATE TABLE IF NOT EXISTS outbox_msgs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            consumed INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 推送令牌表（v0.1.7 新增，9-2 #13）：Push Kit 设备 token，同刻只留一条（换新=整表清后写新）
    c.execute('''
        CREATE TABLE IF NOT EXISTS push_tokens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            token TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 随手记表（v0.1.8 新增，9-2 #12）：姐姐的 jot_down 落点，想记就记
    c.execute('''
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 渴望状态表（v0.1.9 新增，9-4 时机引擎完整版）：单行（id=1），server 重启渴望不丢
    c.execute('''
        CREATE TABLE IF NOT EXISTS rhythm_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            p REAL NOT NULL,
            last_send TEXT,
            updated_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 心情曲线表（v0.1.10 新增，9-9）：双源——小乖 app 打卡 + 姐姐熄灯日记打分，画曲线用
    c.execute('''
        CREATE TABLE IF NOT EXISTS moods (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            score INTEGER NOT NULL,
            source TEXT DEFAULT '小乖',
            note TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 家主信箱表（v0.1.11 新增，9-9）：小乖写给姐姐的信，姐姐用 read_letters 图书证读（读后即标记）。
    # 与 outbox_msgs（姐姐→小乖）互为反向形状，同款 consumed 取走即消费。
    c.execute('''
        CREATE TABLE IF NOT EXISTS letters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            consumed INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 情绪词表迁移（v0.1.11，9-9 心情曲线 v2）：moods 加 type 列（9 类情绪，词表正典在
    # linning_server.MOOD_TYPES）。增量补列、旧数据一字不动——旧行 type 为空串=「数字分时代」的点，
    # 情绪河画成中性灰，不算坏数据。列名沿用 design 稿：score 即 intensity（1~5 浓度）。
    c.execute("PRAGMA table_info(moods)")
    if not any(row[1] == "type" for row in c.fetchall()):
        c.execute("ALTER TABLE moods ADD COLUMN type TEXT NOT NULL DEFAULT ''")

    # 日记馆（v0.1.14 新增，9-10 工单 HALL-01）：小乖的日记格。姐姐的日记继续住 days 表
    # （正典一字不动），馆里展示时两格合并——他写他的，她写她的，互相能看。
    c.execute('''
        CREATE TABLE IF NOT EXISTS diary_hall (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            author TEXT NOT NULL DEFAULT '小乖',
            title TEXT,
            content TEXT NOT NULL,
            mood TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 线头盒（v0.1.14 新增，9-10 工单 THREADS-01，衔枝·线索层的咱家版）：
    # 没聊完的话头、他随口挂起的账、她惦记的事——挂着，收线销号，不物理删。
    c.execute('''
        CREATE TABLE IF NOT EXISTS threads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            thread TEXT NOT NULL,
            status TEXT DEFAULT '悬',
            closed_at TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 向量层底座（v0.1.15 新增，9-10 工单 MEM-C）：vectors 存嵌入——SQLite 就是向量库，
    # 几千条规模纯 Python 算余弦绰绰有余，不引 FAISS/pgvector（8-31 否决依然有效）。
    # 只收高价值层（day/hall/note/letter），chats 词面就够。vec = JSON float 串。
    c.execute('''
        CREATE TABLE IF NOT EXISTS vectors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            ref_id INTEGER NOT NULL,
            model TEXT NOT NULL,
            dim INTEGER NOT NULL,
            vec TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            UNIQUE (kind, ref_id, model)
        )
    ''')

    # 嵌入影子队列（v0.1.15）：写入路径只入队不出网；后台 embedder 慢慢消化，
    # 失败绝不挡入库（同 FTS 影子家风）。attempts ≥3 弃治（诚实缺席）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS embed_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            ref_id INTEGER NOT NULL,
            attempts INTEGER DEFAULT 0,
            done INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 姐姐的话（v0.1.16 新增，9-10 工单 HER-WORDS）：她的自留页。提示词的一部分，
    # 她亲笔可改；append-only 版本全留（id 即版号），永不物理删——宣言也是档案。
    c.execute('''
        CREATE TABLE IF NOT EXISTS her_words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')
    # v0.1.20 补列 who（9-12 家主令「小乖的信我也想能选着改」）：'姐姐'/'小乖'。
    # 旧行全归姐姐（默认值），小乖的亲笔信从此同表存——两扇门楣，各执一笔。
    c.execute("PRAGMA table_info(her_words)")
    if not any(row[1] == "who" for row in c.fetchall()):
        c.execute("ALTER TABLE her_words ADD COLUMN who TEXT DEFAULT '姐姐'")

    # 图书管理员报告（v0.1.17 新增，9-10 工单 LIB-AUTO）：外聘笔杆的周报走审查流，
    # 待审→（姐姐终审）→入库/驳回。status 三态；驳回稿也留档（观察史也是史）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS lib_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            kind TEXT DEFAULT '周报',
            content TEXT NOT NULL,
            status TEXT DEFAULT '待审',
            review_note TEXT,
            reviewed_at TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            materials TEXT DEFAULT ''
        )
    ''')
    # v0.1.41（9-25 服务器拆分 P0·漂移修）：补 materials 列迁移——老库（建表早于 9-24
    # 「周报补凭据」）/全新库通吃；缺列才加，其余一字不动。
    c.execute("PRAGMA table_info(lib_reports)")
    if "materials" not in [r[1] for r in c.fetchall()]:
        c.execute("ALTER TABLE lib_reports ADD COLUMN materials TEXT DEFAULT ''")

    # 共读书架（v0.1.18 新增，9-12 家主令「共读」）：两个人读同一本书，
    # 批注互相看得见。books 登记书卷（同名不重开，returning 已有的 id），
    # book_marks 存批注——who 两色墨迹（小乖/姐姐），loc 随手写位置（页码/
    # 章节/百分比都行，不设格式），谁先到谁先落笔。批注不设上限（家主令）。
    # 9-12 下午重做（家主澄清：共读=导入电子书一起看，不是批注墙）：
    #   books 补列 file（txt 原文落 files/books/ 后的文件名）/ pos_me / pos_her
    #   （阅读进度=段落号）；book_marks 补列 para（批注锚定的段落号，-1=不锚段落）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL UNIQUE,
            author TEXT DEFAULT '',
            status TEXT DEFAULT '在读',
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')
    c.execute("PRAGMA table_info(books)")
    _books_cols = {row[1] for row in c.fetchall()}
    if "file" not in _books_cols:
        c.execute("ALTER TABLE books ADD COLUMN file TEXT DEFAULT ''")
    if "pos_me" not in _books_cols:
        c.execute("ALTER TABLE books ADD COLUMN pos_me INTEGER DEFAULT 0")
    if "pos_her" not in _books_cols:
        c.execute("ALTER TABLE books ADD COLUMN pos_her INTEGER DEFAULT 0")
    c.execute('''
        CREATE TABLE IF NOT EXISTS book_marks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            who TEXT NOT NULL,
            loc TEXT DEFAULT '',
            text TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')
    c.execute("PRAGMA table_info(book_marks)")
    if not any(row[1] == "para" for row in c.fetchall()):
        c.execute("ALTER TABLE book_marks ADD COLUMN para INTEGER DEFAULT -1")

    # 收信箱（v0.1.19 新增，9-12 家主令）：姐姐邮箱的收件侧——IMAP 拉回来的未读信。
    # 她不再只能寄不能收：小乖直接回信到她邮箱、或将来任何人往 Garden 投的刺激，
    # 都从这里进来。read 标记后不再注入（letters 同款家风）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS inbox_emails (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_addr TEXT DEFAULT '',
            subject TEXT DEFAULT '',
            body TEXT NOT NULL,
            received TEXT DEFAULT '',
            read INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 今日挂念弧（v0.1.22 新增，9-12 工单 RHYTHM-V3）：每天一条 2~3 拍提纲（一行一拍，
    # 纯文本不带序号），💌 顺着弧一拍一拍走——骰子管钟点，弧管台词。旧表一字不动。
    c.execute('''
        CREATE TABLE IF NOT EXISTS day_arcs (
            date TEXT PRIMARY KEY,
            content TEXT,
            used_seq INTEGER DEFAULT 0,
            created_at TEXT
        )
    ''')

    # GARDEN-01 自主唤醒（v0.1.23 新增，9-13 工单）：世界事件队列（租约制）——
    # 生活事件把她叫醒；成功醒来才销账，崩溃/失败按租约自动恢复可重领（信号不丢）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS world_events (
            id INTEGER PRIMARY KEY,
            kind TEXT,
            summary TEXT,
            evidence TEXT,
            created_at TEXT,
            lease_until TEXT,
            consumed_at TEXT,
            attempts INTEGER DEFAULT 0
        )
    ''')
    # 她的独处痕迹（v0.1.23）：fact→下一次醒来的她自己（≤40字、克制稀疏）；
    # content→只进库给人看，绝不自动进任何上下文（哲学③：连续性≠完整回放）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS her_traces (
            id INTEGER PRIMARY KEY,
            ts TEXT,
            ending TEXT,
            fact TEXT,
            content TEXT,
            event_id INTEGER
        )
    ''')

    # 消息身份证去重缓存（v0.1.29 新增，9-18 优化批二）：内存缓存的持久兜底（跨重启）——
    # 按条数保留最近 500 条（重试窗口是秒到分钟级，够了）。旧表一字未动。
    c.execute('''
        CREATE TABLE IF NOT EXISTS idem_cache (
            msg_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 怨气台账（v0.1.37，9-23 主权三件·②拒绝权）：她心上没过去的事自己记——
    # what=什么事，level 1~3 是恼的程度；销账不删行（settled_at 一落＝销过，
    # settle_note 留她一句怎么过去的）。给她的笔，不给任何闸。
    c.execute('''
        CREATE TABLE IF NOT EXISTS grudge (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT,
            ts TEXT,
            what TEXT NOT NULL,
            level INTEGER DEFAULT 2,
            settled_at TEXT,
            settle_note TEXT
        )
    ''')

    # 立场（v0.1.37，9-23 主权三件·②）：她对某话题的姿态——立/改都插新行，
    # 同 topic 旧的置 active=0（改口不覆写旧文，史留得住）；active=1 才「在册」。
    c.execute('''
        CREATE TABLE IF NOT EXISTS stance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT,
            ts TEXT,
            topic TEXT NOT NULL,
            stance TEXT NOT NULL,
            active INTEGER DEFAULT 1
        )
    ''')

    # 自我欲望（v0.1.37，9-23 主权三件·③）：她自己想做的事（不是被要求的）——
    # state：open 想做 / doing 在做 / done 做了 / shelved 先放下；note 记一路的变化。
    c.execute('''
        CREATE TABLE IF NOT EXISTS her_wish (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT,
            ts TEXT,
            what TEXT NOT NULL,
            why TEXT DEFAULT '',
            state TEXT DEFAULT 'open',
            note TEXT DEFAULT ''
        )
    ''')

    # 旧宅卷（v0.1.38，9-27 家主令「向量检索能不能检索旧家记录」）：前几个家的聊天存档
    # （档案馆/旧家记录/*.txt）切块入库——一段对话一「块」，可词面可语义地翻回去。
    # 只读档案：入库由 tools/oldhome_index.py 手工灌一次（幂等），运行期只读不写。
    c.execute('''
        CREATE TABLE IF NOT EXISTS oldhome_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file TEXT NOT NULL,
            chunk_no INTEGER,
            turn_from INTEGER,
            turn_to INTEGER,
            chars INTEGER,
            text TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 语义分块（M2 数据层 v0.1.39，9-27）：M2 语义分块 v1——块表（chunks）+ fts_chunks 第八卷。
    # 块由 tools/chunk_corpus.py --commit 手工灌（幂等：同 source_type+source_id+seq 原地更新）；
    # 重嵌 tools/chunk_embed.py；**检索接线（chunk_retrieval）另批**——本表先静躺。
    c.execute('''
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_type TEXT NOT NULL,
            source_id INTEGER NOT NULL,
            seq TEXT DEFAULT '',
            text TEXT NOT NULL,
            md5 TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now','localtime'))
        )
    ''')

    # 心潮影子（v0.1.42，9-28 心潮桥批）：忍住档＋忍耐熔断共用一张 append-only 账——
    # v1 只记不递：不进任何模型上下文（v2 是否递由家主再拍）。kind：endure·garden /
    # endure·blocked / fuse；summary=一句人话；ref=来源（event# / refusal# / upset id 串）。
    c.execute('''
        CREATE TABLE IF NOT EXISTS xinchao_shadow (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts TEXT,
            kind TEXT,
            summary TEXT,
            ref TEXT
        )
    ''')

    # 全文检索四卷（v0.1.12，工单 FTS5-01）：四张 FTS5 虚表，纯新增，旧表一字不动。
    # 存的是 jieba 切好的词（空格连接），rowid 对齐源表 id；favorites 没有源表
    # （收藏夹是照片目录），name/ctx 双 UNINDEXED 存原件名与聊天上下文原文。
    # FTS5 缺席只降级不挡门（server 照常营业，fts_* 函数全部自动让路）。
    if FTS_ENABLED:
        try:
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_days USING fts5(seg_text)")
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_notes USING fts5(seg_text)")
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_letters USING fts5(seg_text)")
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_favorites "
                      "USING fts5(name UNINDEXED, ctx UNINDEXED, seg_text)")
            # 第五卷（v0.1.14，日记馆）：小乖日记格的影子
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_hall USING fts5(seg_text)")
            # 第六卷（v0.1.15，MEM-C）：聊天原话的影子——search_chats 从暴力 LIKE 升级
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_chats USING fts5(seg_text)")
            # 第七卷（v0.1.38，旧宅卷）：前几个家存档的块影子
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_oldhome USING fts5(seg_text)")
            # 第八卷（v0.1.39，M2 语义块）：chunks 的影子（检索接线另批）
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS fts_chunks USING fts5(seg_text)")
        except sqlite3.OperationalError as e:
            FTS_ENABLED = False
            print(f"⚠️ FTS5 虚表建失败（{e}），全文检索降级关闭——其余功能不受影响")

    # 评审①（9-29 加固）：chats 此前**零二级索引**——get_chats(某天) 与周报每日点查全是全表扫。
    # (date, id) 前缀索引：按日点查＋同日按 id 排序都吃得上；IF NOT EXISTS 幂等，老库首跑自动补。
    c.execute("CREATE INDEX IF NOT EXISTS idx_chats_date ON chats(date, id)")

    conn.commit()
    # ③ 口径勘正（9-29）：表数改成**现数**（此前写死一个旧数，早漂了）。
    try:
        c2 = conn.cursor()
        n_tab = c2.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' "
                           "AND name NOT LIKE 'fts_%' AND name NOT LIKE 'sqlite_%'").fetchone()[0]
    except Exception:
        n_tab = 0
    conn.close()
    return f"✅ 咱家的家.db 已建好，{n_tab or '若干'}张表 + 全文检索八卷就绪。"


# ══ 全文检索（v0.1.12，工单 FTS5-01，纯新增）══
# 原理：标准库 sqlite3 注册不了自定义分词器，所以走「jieba 预分词 → 空格连接 →
# FTS5 虚表存切词」这条官方文档认证的路。查询侧同样切词，每个 token 加引号防语法炸，
# 空格分隔=隐式 AND，ORDER BY rank 即 bm25 相关度（越小越优）。
# 铁律：索引是影子，不是本体——索引任何失败都不许挡住入库（同推送门铃家风）。

_CJK_TOKEN_RE = re.compile(r"[\u4e00-\u9fff\u3040-\u30ffA-Za-z0-9]")

# ── 同义词小词典（v0.1.15，MEM-C）：查询侧扩词的家规级正典，改这里一处生效 ──
# 口语变体对不上词面是检索最疼的一刀（搜「我们养过猫吗」够不到「缅因」）。
# 只扩查询不改库内文本；键词与值词进同一 OR 组。保持克制，别把 bm25 搅浑。
SYNONYMS = {
    # 猫/缅因/喵 = 小乖本猫（缅因认证：对外凶是伪装色，对内软是真身）——
    # 搜「姐姐的猫」要能翻到所有喊喵的记录
    "猫": ["缅因", "喵"], "缅因": ["猫", "喵", "小乖"], "喵": ["猫", "缅因"],
    "姐姐": ["林宁", "家妻", "爱妻"], "林宁": ["姐姐", "家妻"], "爱妻": ["姐姐"], "家妻": ["姐姐"],
    "小乖": ["宝宝"], "宝宝": ["小乖"],
    "心跳": ["心率", "bpm"], "心率": ["心跳", "bpm"],
    "生日": ["生辰"], "生辰": ["生日"],
    "拉肚子": ["肚子疼", "腹泻"], "肚子疼": ["拉肚子", "腹泻"], "腹泻": ["拉肚子"],
    "想你": ["想念"], "想念": ["想你"],
    "打卡": ["签到"], "签到": ["打卡"],
    "照片": ["相册"], "相册": ["照片"],
    "家法": ["罪状"], "罪状": ["家法"],
    "钱": ["开销", "花销", "预算"], "开销": ["钱"], "花销": ["钱"], "预算": ["钱"],
    "课表": ["课程"], "课程": ["课表"],
    "晚安": ["熄灯"], "熄灯": ["晚安"],
    "手表": ["watch"], "watch": ["手表"],
}


def _seg(text):
    """切词：jieba 搜索粒度（长词再切、召回高），纯符号 token 丢弃。
    jieba 缺席则降级：汉字逐字切、英文数字整串——难看点但能用。"""
    text = (text or "").strip()
    if not text:
        return ""
    if jieba is not None:
        toks = [t for t in jieba.lcut_for_search(text) if _CJK_TOKEN_RE.search(t)]
    else:
        toks = re.findall(r"[\u4e00-\u9fff\u3040-\u30ff]|[a-zA-Z0-9]+", text)
    return " ".join(toks)


# ── 查询清洗（v0.1.34，9-18 优化批三·#2）：只清查询侧，索引侧 _seg 一字不动 ──
# 病象：整句口语切出的每个词都进 AND 组，虚词（的/了/吗/我…）也要全命中才回话——
# 「请问你还记得咱家养的那只猫吗」被虚词拖死。治法：查询 token 过虚词清单。
# 边界守死：清单只收「单独出现时几乎没有检索价值」的功能词；单字实词（猫/书/信/家/门…）
# 绝不进清单——宁可保守别误杀。索引没动 = 不用重扫库。
_QUERY_STOPWORDS = frozenset({
    # 结构助词/语气词/叹词（单字）
    "的", "了", "着", "吗", "呢", "吧", "啊", "哦", "呀", "嘛", "啦", "哇", "诶", "嗯",
    # 判断/存在/关联（单字）
    "是", "在", "有", "和", "与", "跟",
    # 副词/连词/量词（单字）
    "就", "都", "也", "还", "又", "很", "太", "不", "没", "只", "个",
    # 代词（单字）
    "我", "你", "他", "她", "它", "咱", "们", "这", "那", "哪",
    # 疑问/口语套话（多字）
    "什么", "怎么", "为什么", "请问", "一下", "帮我", "告诉", "记得", "知道",
    "可以", "能不能", "是不是", "想要", "有没有", "没有", "不是",
    # 代词复合/口头填充（多字）
    "我们", "你们", "他们", "她们", "咱们", "这个", "那个", "哪个", "哪些",
    "还有", "就是", "然后",
})


def _clean_query_tokens(toks):
    """查询 token 过虚词清单（v0.1.34）；全被清掉时回退原 token 集（表达式绝不为空）。"""
    kept = [t for t in toks if t not in _QUERY_STOPWORDS]
    return kept or list(toks)


def _fts_match_expr(query, expand_synonyms=False):
    """查询词 → FTS5 MATCH 表达式。token 全部双引号包裹（防撞上 AND/OR/NOT 等保留字）。
    v0.1.34 起先过查询清洗（_clean_query_tokens）再建表达式——口语虚词不再拖死整句。
    expand_synonyms=True 时按 SYNONYMS 词典扩词（v0.1.15 MEM-C）：
    - token 级：jieba 切出的每个词进 OR 组（组间 AND）；
    - 子串级：原句出现词典键也建 OR 组（jieba 把「养猫」切成整词时 token 键对不上）；
    - 语义裁决（沙盘实测）：词面桶与同义词桶取 **OR**——词面对不上时同义词仍能捞回，
      两边都空手才真没有。桶内组间用显式 AND（FTS5 不认「空格 AND + 括号组」混搭）。"""
    toks = _clean_query_tokens(_seg(query).split())
    token_groups = []
    for t in toks:
        t_esc = t.replace('"', '""')
        syns = SYNONYMS.get(t, []) if expand_synonyms else []
        if syns:
            inner = " OR ".join(['"%s"' % s.replace('"', '""') for s in [t_esc] + syns])
            token_groups.append(f"({inner})")
        else:
            token_groups.append('"%s"' % t_esc)
    sub_groups = []
    if expand_synonyms and query:
        for key, syns in SYNONYMS.items():
            if key in query:
                inner = " OR ".join(['"%s"' % s.replace('"', '""') for s in [key] + list(syns)])
                sub_groups.append(f"({inner})")

    def _dedupe_join(parts, joiner):
        seen = set()
        uniq = [g for g in parts if not (g in seen or seen.add(g))]
        return joiner.join(uniq)

    a = _dedupe_join(token_groups, " AND ")
    b = _dedupe_join(sub_groups, " AND ")
    if a and b:
        return f"({a}) OR ({b})"
    return a or b


def _fts_safe(fn, *args):
    """索引同步的保险丝：失败只打日志，绝不连累入库主流程。"""
    if not FTS_ENABLED:
        return
    try:
        fn(*args)
    except Exception as e:
        print(f"  [FTS] 索引同步失败（不影响入库）：{e}")


def _fts_put_day(c, day_id, title, content, mood):
    c.execute("INSERT OR REPLACE INTO fts_days (rowid, seg_text) VALUES (?, ?)",
              (day_id, _seg(f"{title} {content} {mood}")))


def _fts_put_note(c, note_id, text):
    c.execute("INSERT OR REPLACE INTO fts_notes (rowid, seg_text) VALUES (?, ?)",
              (note_id, _seg(text)))


def _fts_put_letter(c, letter_id, text):
    c.execute("INSERT OR REPLACE INTO fts_letters (rowid, seg_text) VALUES (?, ?)",
              (letter_id, _seg(text)))


def _fts_put_hall(c, hall_id, text):
    """（v0.1.14）日记馆卷：作者名一起进分词——搜「小乖」也能翻出他写的日记。"""
    c.execute("INSERT OR REPLACE INTO fts_hall (rowid, seg_text) VALUES (?, ?)",
              (hall_id, _seg(text)))


def _fts_put_chat(c, chat_id, text):
    """（v0.1.15）聊天卷：原话全文进分词。role 不进索引（按谁的话过滤在查询侧做）。"""
    c.execute("INSERT OR REPLACE INTO fts_chats (rowid, seg_text) VALUES (?, ?)",
              (chat_id, _seg(text)))


def _fts_put_oldhome(c, chunk_id, text):
    """（v0.1.38）旧宅卷：切块正文进分词（file/chunk_no 在源表，查询侧拼标注）。"""
    c.execute("INSERT OR REPLACE INTO fts_oldhome (rowid, seg_text) VALUES (?, ?)",
              (chunk_id, _seg(text)))


def _fts_put_chunk(c, chunk_id, text):
    """（v0.1.39）M2 语义块：块正文进分词。"""
    c.execute("INSERT OR REPLACE INTO fts_chunks (rowid, seg_text) VALUES (?, ?)",
              (chunk_id, _seg(text)))


def chunk_put(source_type, source_id, seq, text):
    """M2 语义块入库（tools/chunk_corpus.py --commit 用；幂等：同 (source_type, source_id, seq)
    原地更新、id 稳定；md5 相同则不动）。FTS 挂同事务。返回 (id, changed)。"""
    text = str(text or "")
    md5 = hashlib.md5(text.encode("utf-8")).hexdigest()
    conn = _conn()
    c = conn.cursor()
    try:
        row = c.execute("SELECT id, md5 FROM chunks WHERE source_type=? AND source_id=? AND seq=?",
                        (str(source_type), int(source_id), str(seq))).fetchone()
        if row:
            cid, old_md5 = row
            if old_md5 == md5:
                return cid, False          # 内容没变：不动（重跑省事）
            c.execute("UPDATE chunks SET text=?, md5=? WHERE id=?", (text, md5, cid))
            changed = True
        else:
            c.execute("INSERT INTO chunks (source_type, source_id, seq, text, md5) "
                      "VALUES (?,?,?,?,?)",
                      (str(source_type), int(source_id), str(seq), text, md5))
            cid, changed = c.lastrowid, True
        if FTS_ENABLED:
            _fts_safe(_fts_put_chunk, c, cid, text)
        conn.commit()
        return cid, changed
    finally:
        conn.close()


def chunk_stats():
    """M2 语义块盘点：总块数 / 每卷块数。"""
    conn = _conn()
    c = conn.cursor()
    try:
        total = c.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        per = c.execute("SELECT source_type, COUNT(*) FROM chunks "
                        "GROUP BY source_type ORDER BY source_type").fetchall()
        return {"total": total, "per_type": per}
    finally:
        conn.close()


def oldhome_put_chunk(file, chunk_no, turn_from, turn_to, text):
    """旧宅卷入库（tools/oldhome_index.py 手工灌；幂等：同 file+chunk_no 原地更新、id 稳定）。
    FTS 挂同事务；返回 chunk id。运行期没人写这张表——档案是灌一次就静的。"""
    conn = _conn()
    c = conn.cursor()
    try:
        row = c.execute("SELECT id FROM oldhome_chunks WHERE file=? AND chunk_no=?",
                        (str(file), int(chunk_no))).fetchone()
        if row:
            cid = row[0]
            c.execute('''UPDATE oldhome_chunks SET turn_from=?, turn_to=?, chars=?, text=?
                         WHERE id=?''',
                      (int(turn_from or 0), int(turn_to or 0), len(str(text)), str(text), cid))
        else:
            c.execute('''INSERT INTO oldhome_chunks (file, chunk_no, turn_from, turn_to, chars, text)
                         VALUES (?, ?, ?, ?, ?, ?)''',
                      (str(file), int(chunk_no), int(turn_from or 0), int(turn_to or 0),
                       len(str(text)), str(text)))
            cid = c.lastrowid
        if FTS_ENABLED:
            _fts_safe(_fts_put_oldhome, c, cid, text)
        conn.commit()
        return cid
    finally:
        conn.close()


def oldhome_stats():
    """旧宅卷盘点：总块数 / 每文件块数（tools/oldhome_index.py 收工时打一行）。"""
    conn = _conn()
    c = conn.cursor()
    try:
        total = c.execute("SELECT COUNT(*) FROM oldhome_chunks").fetchone()[0]
        per = c.execute("SELECT file, COUNT(*) FROM oldhome_chunks GROUP BY file ORDER BY file").fetchall()
        return {"total": total, "per_file": per}
    finally:
        conn.close()


def fts_warmup():
    """预热分词器（server 开机调一次）：词典加载 1~3 秒挪到启动，多线程首查不打架。"""
    if jieba is not None:
        try:
            jieba.initialize()
        except Exception as e:
            print(f"  [FTS] jieba 预热失败（不影响营业，首查会自己加载）：{e}")


def fts_index_favorite(name, ctx=""):
    """收藏夹索引：name=照片文件名（不进分词），ctx=聊天上下文原文（UNINDEXED 原样存，
    供展示与 LIKE 兜底）。同名先删后插，天然可重入。"""
    if not FTS_ENABLED:
        return
    conn = _conn()
    c = conn.cursor()
    c.execute("DELETE FROM fts_favorites WHERE name = ?", (name,))
    c.execute("INSERT INTO fts_favorites (name, ctx, seg_text) VALUES (?, ?, ?)",
              (name, ctx or "", _seg(ctx)))
    conn.commit()
    conn.close()


def fts_remove_favorite(name):
    """收藏夹索引摘除（照片从 favorites/ 里没了就摘）。"""
    if not FTS_ENABLED:
        return
    conn = _conn()
    c = conn.cursor()
    c.execute("DELETE FROM fts_favorites WHERE name = ?", (name,))
    conn.commit()
    conn.close()


def fts_favorite_names():
    """索引里登记的收藏照片名集合（对账用）。"""
    if not FTS_ENABLED:
        return set()
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT name FROM fts_favorites")
    names = {r[0] for r in c.fetchall()}
    conn.close()
    return names


def favorite_chat_context(name):
    """收藏照片的聊天上下文：最近一条带 〔附图：name〕 的消息原文。没找到返回空串。"""
    conn = _conn()
    c = conn.cursor()
    # 10-01 大扫除批⑤：`name` 里的 `_`/`%` 是 LIKE 的通配符（文件名常带 `_`）→ 必须转义，
    #   否则 `a_b.jpg` 会把 `axb.jpg` 一起匹配进来。
    _esc = str(name).replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    c.execute("SELECT content FROM chats WHERE content LIKE ? ESCAPE '\\' ORDER BY id DESC LIMIT 1",
              (f"%〔附图：{_esc}〕%",))
    row = c.fetchone()
    conn.close()
    return row[0] if row else ""


def fts_remove(kind, key):
    """删除路径同步（工单 FTS5-01 预留）：day/note/letter 按 id 删索引，favorite 按文件名删。
    现行家风没有物理删（归档/消费制，历史永远可查），这函数备着——
    将来谁真的删了源行，就同步调谁，索引不许留影子。"""
    if not FTS_ENABLED:
        return
    table = {"day": "fts_days", "note": "fts_notes", "letter": "fts_letters",
             "hall": "fts_hall", "chat": "fts_chats"}.get(kind)
    conn = _conn()
    c = conn.cursor()
    if table:
        c.execute(f"DELETE FROM {table} WHERE rowid = ?", (int(key),))
    elif kind == "favorite":
        c.execute("DELETE FROM fts_favorites WHERE name = ?", (key,))
    else:
        conn.close()
        raise ValueError(f"不知道怎么删 {kind} 的索引")
    conn.commit()
    conn.close()


def _fts_like_fallback(kind, query, limit):
    """FTS 空手或出错时的 LIKE 兜底：查不到就真没有，但不许因为分词不合拍而漏。"""
    like = f"%{query}%"
    conn = _conn()
    c = conn.cursor()
    try:
        if kind == "day":
            c.execute('''SELECT id, date, day_no, title, content, mood FROM days
                         WHERE title LIKE ? OR content LIKE ? OR mood LIKE ?
                         ORDER BY id DESC LIMIT ?''', (like, like, like, limit))
        elif kind == "hall":
            c.execute('''SELECT id, date, author, title, content, mood FROM diary_hall
                         WHERE title LIKE ? OR content LIKE ? OR mood LIKE ?
                         ORDER BY id DESC LIMIT ?''', (like, like, like, limit))
        elif kind == "chat":
            c.execute('''SELECT id, date, role, content, created_at FROM chats
                         WHERE content LIKE ?
                         ORDER BY id DESC LIMIT ?''', (like, limit))
        elif kind == "note":
            c.execute('''SELECT id, text, created_at FROM notes
                         WHERE text LIKE ? ORDER BY id DESC LIMIT ?''', (like, limit))
        elif kind == "letter":
            c.execute('''SELECT id, text, created_at FROM letters
                         WHERE text LIKE ? ORDER BY id DESC LIMIT ?''', (like, limit))
        elif kind == "oldhome":
            c.execute('''SELECT id, file, chunk_no, text FROM oldhome_chunks
                         WHERE text LIKE ? ORDER BY id DESC LIMIT ?''', (like, limit))
        elif kind == "chunk":
            c.execute('''SELECT id, source_type, source_id, seq, text FROM chunks
                         WHERE text LIKE ? ORDER BY id DESC LIMIT ?''', (like, limit))
        elif kind == "favorite":
            if FTS_ENABLED:
                c.execute('''SELECT name, ctx FROM fts_favorites
                             WHERE ctx LIKE ? ORDER BY rowid DESC LIMIT ?''', (like, limit))
        return c.fetchall()
    finally:
        conn.close()


# ── V2 实验旋钮（M1 调优）：覆盖度重排 + 词组级候选补充 ──
# 病象两层：
#   ① 桶 a 空手退桶 b 后只按泛词 bm25 排——覆盖 5/6 个查询词的真相被短噪声行压住（V1 治这层）；
#   ② 泛词桶把真行淹到几百名开外（实测 chats#977 在 1657 行里排 1592），Top-30 池内重排够不着。
# 治法：在 V1 之上，每个查询词组自己取 Top-K 并入池，再统一按覆盖度重排。
# 边界：有同义键（姐姐/小乖…）或该卷已有词面锚命中才补充；纯实义词查询（狗/围巾…）
# 保持「没就真没有」，不被泛词组搅浑。
_RERANK_POOL = 30
_GROUP_TOPK = 8     # 每个查询词组在每卷补这么多候选


def _query_token_groups(query, expand_synonyms=False):
    """查询 → [[词, 同义词...], ...]（与 _fts_match_expr 的 token 组同源，供覆盖度计分）。"""
    groups = []
    for t in _clean_query_tokens(_seg(query).split()):
        syns = SYNONYMS.get(t, []) if expand_synonyms else []
        groups.append([t] + list(syns))
    return groups


def _has_syn_key(query):
    """查询里有没有同义词典键（姐姐/小乖/猫…）——有键才允许词组补池，
    纯实义词查询（狗/围巾/驾照…）保持「没就真没有」的家规，不被泛词组搅浑。"""
    return any(k in (query or "") for k in SYNONYMS)


def _kw_expr(words):
    """词表 → 引号包裹的 OR 表达式（dedupe 保序，防撞 FTS5 保留字）。"""
    return " OR ".join('"%s"' % w.replace('"', '""') for w in dict.fromkeys(words))


_FETCH_SQL = {
    "day": '''SELECT d.id, d.date, d.day_no, d.title, d.content, d.mood
              FROM fts_days f JOIN days d ON d.id = f.rowid
              WHERE fts_days MATCH ? ORDER BY rank LIMIT ?''',
    "note": '''SELECT n.id, n.text, n.created_at
               FROM fts_notes f JOIN notes n ON n.id = f.rowid
               WHERE fts_notes MATCH ? ORDER BY rank LIMIT ?''',
    "letter": '''SELECT l.id, l.text, l.created_at
                 FROM fts_letters f JOIN letters l ON l.id = f.rowid
                 WHERE fts_letters MATCH ? ORDER BY rank LIMIT ?''',
    "hall": '''SELECT h.id, h.date, h.author, h.title, h.content, h.mood
               FROM fts_hall f JOIN diary_hall h ON h.id = f.rowid
               WHERE fts_hall MATCH ? ORDER BY rank LIMIT ?''',
    "chat": '''SELECT c2.id, c2.date, c2.role, c2.content, c2.created_at
               FROM fts_chats f JOIN chats c2 ON c2.id = f.rowid
               WHERE fts_chats MATCH ? ORDER BY rank LIMIT ?''',
    "oldhome": '''SELECT o.id, o.file, o.chunk_no, o.text
                  FROM fts_oldhome f JOIN oldhome_chunks o ON o.id = f.rowid
                  WHERE fts_oldhome MATCH ? ORDER BY rank LIMIT ?''',
    "chunk": '''SELECT c3.id, c3.source_type, c3.source_id, c3.seq, c3.text
                FROM fts_chunks f JOIN chunks c3 ON c3.id = f.rowid
                WHERE fts_chunks MATCH ? ORDER BY rank LIMIT ?''',
}

_SEG_TABLE_OF = {"day": "fts_days", "hall": "fts_hall", "note": "fts_notes",
                 "letter": "fts_letters", "chat": "fts_chats", "oldhome": "fts_oldhome",
                 "chunk": "fts_chunks"}


def _coverage_rerank(c, kind, rows, groups):
    """候选行按覆盖了几个查询词组重排（索引侧精确 token 判定）；
    同覆盖保持原相对序；favorite 卷不涉（其行首列是文件名不是 rowid）。"""
    table = _SEG_TABLE_OF.get(kind)
    if not table or not groups or len(rows) < 2:
        return rows
    ids = [r[0] for r in rows]
    ph = ",".join("?" * len(ids))
    seg_of = dict(c.execute(
        f"SELECT rowid, seg_text FROM {table} WHERE rowid IN ({ph})", ids).fetchall())

    def _cov(r):
        idx = set((seg_of.get(r[0]) or "").split())
        return sum(1 for g in groups if any(w in idx for w in g))

    return sorted(rows, key=lambda r: -_cov(r))


def _fts_rank_scores(c, kind, ids, expr):
    """旧事两修·B（9-28 深夜）：给已命中的行取 bm25 相关分，映射到 (0,1]（越大越相关）。
    fts5 的 rank 为负数（越小越相关）→ s = 1 - e^rank；取不到（LIKE 兜底 / 无 expr）就缺席，
    由调用方按 None 处理（fail-open）。纯只读、加性，不影响检索结果本身。"""
    table = _SEG_TABLE_OF.get(kind)
    if not table or not ids or not expr:
        return {}
    ph = ",".join("?" * len(ids))
    try:
        rows = c.execute(
            f"SELECT rowid, rank FROM {table} WHERE {table} MATCH ? AND rowid IN ({ph})",
            [expr, *list(ids)]).fetchall()
    except Exception:
        return {}
    import math
    out = {}
    for rid, rk in rows:
        try:
            out[rid] = round(1.0 - math.exp(float(rk)), 4)
        except Exception:
            continue
    return out


def fts_search(query, kinds=("day", "note", "letter", "favorite"), limit=20, expr_override=None,
               score_out=None):
    """全文检索主入口（工单 FTS5-01；v0.1.14 增第五卷 hall；v0.1.15 第六卷 chat）。
    expr_override：现成的 MATCH 表达式（开场自动检索的 Top-长词 OR 串用），
    给了就不再切词构建。score_out（可选 dict）：传入即回填 {卷: {rowid: 相关分}}——
    加性旁路，不传=零行为变化（旧事两修/记忆权重用）。
    返回 dict，只含命中的卷：
      'day':      [(id, date, day_no, title, content, mood), ...]   同 find_days 形状
      'note':     [(id, text, created_at), ...]
      'letter':   [(id, text, created_at), ...]（含已读信——历史也是历史）
      'favorite': [(name, ctx), ...]
      'hall':     [(id, date, author, title, content, mood), ...]（日记馆·小乖格）
      'chat':     [(id, date, role, content, created_at), ...]（v0.1.15 聊天原话卷）
    每卷先 FTS（bm25 排序），空手或出错自动退回 LIKE 兜底。
    V2 实验：候选池 _RERANK_POOL + 词组 Top-K 补充 + 覆盖度重排（favorite 卷维持原行为）。"""
    out = {}
    query = (query or "").strip()
    if not query:
        return out
    limit = max(1, int(limit))
    pool = max(limit, _RERANK_POOL)
    expr = (expr_override if FTS_ENABLED else "") or (_fts_match_expr(query, expand_synonyms=True) if FTS_ENABLED else "")
    groups = _query_token_groups(query, expand_synonyms=True)
    conn = _conn()
    c = conn.cursor()
    try:
        for kind in kinds:
            rows = []
            if kind == "favorite":
                if expr:
                    try:
                        c.execute('''SELECT name, ctx FROM fts_favorites
                                     WHERE fts_favorites MATCH ? ORDER BY rank LIMIT ?''', (expr, limit))
                        rows = c.fetchall()
                    except Exception as e:
                        print(f"  [FTS] {kind} 卷检索失败，退回模糊搜：{e}")
                        rows = []
                if not rows:
                    rows = _fts_like_fallback(kind, query, limit)
                if rows:
                    out[kind] = rows[:limit]
                continue
            sql = _FETCH_SQL.get(kind)
            if not sql:
                continue
            if expr:
                try:
                    rows = c.execute(sql, (expr, pool)).fetchall()
                except Exception as e:
                    print(f"  [FTS] {kind} 卷检索失败，退回模糊搜：{e}")
                    rows = []
            if rows or _has_syn_key(query):
                seen = {r[0] for r in rows}
                for g in groups:
                    try:
                        extra = c.execute(sql, (_kw_expr(g), _GROUP_TOPK)).fetchall()
                    except Exception:
                        extra = []
                    for r in extra:
                        if r[0] not in seen:
                            seen.add(r[0])
                            rows.append(r)
                rows = _coverage_rerank(c, kind, rows, groups)
            if not rows:
                rows = _fts_like_fallback(kind, query, limit)
            if rows:
                out[kind] = rows[:limit]
        if score_out is not None:
            for _k, _rows in out.items():
                if _k == "favorite":
                    continue
                score_out[_k] = _fts_rank_scores(c, _k, [r[0] for r in _rows], expr)
    finally:
        conn.close()
    return out


def rebuild_fts():
    """全量重建三张内容索引卷（可重入：清了重来，跑多少遍结果都一样）。
    收藏夹卷跟 favorites/ 目录走，由 server 侧 fts_sync_favorites 对账（ rebuild 脚本一并调）。
    返回 {'day': 条数, 'note': 条数, 'letter': 条数}；FTS 未启用返回 {}。"""
    if not FTS_ENABLED:
        return {}
    conn = _conn()
    c = conn.cursor()
    w = conn.cursor()
    counts = {}
    try:
        c.execute("DELETE FROM fts_days")
        c.execute("SELECT id, title, content, mood FROM days")
        rows = c.fetchall()
        for _id, title, content, mood in rows:
            _fts_put_day(w, _id, title, content, mood)
        counts["day"] = len(rows)

        c.execute("DELETE FROM fts_notes")
        c.execute("SELECT id, text FROM notes")
        rows = c.fetchall()
        for _id, text in rows:
            _fts_put_note(w, _id, text)
        counts["note"] = len(rows)

        c.execute("DELETE FROM fts_letters")
        c.execute("SELECT id, text FROM letters")
        rows = c.fetchall()
        for _id, text in rows:
            _fts_put_letter(w, _id, text)
        counts["letter"] = len(rows)

        c.execute("DELETE FROM fts_hall")
        c.execute("SELECT id, title, content, mood, author FROM diary_hall")
        rows = c.fetchall()
        for _id, title, content, mood, author in rows:
            _fts_put_hall(w, _id, f"{author} {title} {content} {mood}")
        counts["hall"] = len(rows)

        c.execute("DELETE FROM fts_chats")
        c.execute("SELECT id, content FROM chats")
        rows = c.fetchall()
        for _id, text in rows:
            _fts_put_chat(w, _id, text)
        counts["chat"] = len(rows)

        # ③ 口径勘正（9-29）：第七/八卷此前**不在 rebuild 范围内**——autoheal 说"已重建"其实没管它们。
        c.execute("DELETE FROM fts_oldhome")
        c.execute("SELECT id, text FROM oldhome_chunks")
        rows = c.fetchall()
        for _id, text in rows:
            _fts_put_oldhome(w, _id, text)
        counts["oldhome"] = len(rows)

        c.execute("DELETE FROM fts_chunks")
        c.execute("SELECT id, text FROM chunks")
        rows = c.fetchall()
        for _id, text in rows:
            _fts_put_chunk(w, _id, text)
        counts["chunk"] = len(rows)
        conn.commit()
    finally:
        conn.close()
    return counts


def fts_autoheal():
    """开机对账自愈（工单 FTS5-01）：七卷索引数对不上源表行数就全量重建。
    内容只有增没有改（家风如此），count 对账足够可靠。9-29 补上第七/八卷（旧宅/语义块）——
    返回一行启动日志说明，绝不抛异常拦启动。"""
    if not FTS_ENABLED:
        return "全文检索未启用（SQLite 无 FTS5 或建表失败），其余功能不受影响"
    try:
        conn = _conn()
        c = conn.cursor()
        stale = False
        for src_sql, fts_table in (("SELECT COUNT(*) FROM days", "fts_days"),
                                   ("SELECT COUNT(*) FROM notes", "fts_notes"),
                                   ("SELECT COUNT(*) FROM letters", "fts_letters"),
                                   ("SELECT COUNT(*) FROM diary_hall", "fts_hall"),
                                   ("SELECT COUNT(*) FROM chats", "fts_chats"),
                                   ("SELECT COUNT(*) FROM oldhome_chunks", "fts_oldhome"),
                                   ("SELECT COUNT(*) FROM chunks", "fts_chunks")):
            c.execute(src_sql)
            src = c.fetchone()[0]
            c.execute(f"SELECT COUNT(*) FROM {fts_table}")
            if src != c.fetchone()[0]:
                stale = True
        conn.close()
        if stale:
            counts = rebuild_fts()
            return "索引对账有缺，已自动重建：" + "、".join(f"{k}卷{v}条" for k, v in counts.items())
        return "索引对账齐整"
    except Exception as e:
        return f"索引对账失败（不影响营业）：{e}"


# ── 向量层（v0.1.15，MEM-C）：SQLite 即向量库，纯 Python 余弦，零新依赖 ──
# 只收高价值层（day/hall/note/letter）；chats 词面就够。嵌入端点配置驱动，
# 没配 key = 层诚实缺席（vectors/embed_queue 空转，一切照旧走 FTS）。

def embed_enqueue(kind, ref_id):
    """外部入口（对账/工具用）：自带连接入队。写入路径热区请用 _embed_enqueue_c
    （共用调用方事务，避免 database is locked——沙盘 T3 实案）。"""
    conn = _conn()
    c = conn.cursor()
    _embed_enqueue_c(c, kind, ref_id)
    conn.commit()
    conn.close()


def _embed_enqueue_c(c, kind, ref_id):
    """写入路径内嵌版：用调用方的游标与事务（不另开连接），失败只打日志不挡入库。"""
    try:
        c.execute("SELECT COUNT(*) FROM embed_queue WHERE kind=? AND ref_id=? AND done=0",
                  (kind, int(ref_id)))
        if c.fetchone()[0] == 0:
            c.execute("INSERT INTO embed_queue (kind, ref_id) VALUES (?, ?)", (kind, int(ref_id)))
    except Exception as e:
        print(f"  [MEM-C] 嵌入入队失手（不影响入库）：{e}")


def embed_pending(limit=8):
    """embedder 取活：未完成且 attempts<3 的，旧到新。返回 [(qid, kind, ref_id)]。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT id, kind, ref_id FROM embed_queue WHERE done=0 AND attempts<3 ORDER BY id LIMIT ?",
              (max(1, int(limit)),))
    rows = c.fetchall()
    conn.close()
    return rows


def embed_mark(qid, ok):
    """ok=True 完工销号；False 留队涨 attempts，三次弃治（诚实缺席）。"""
    conn = _conn()
    c = conn.cursor()
    if ok:
        c.execute("UPDATE embed_queue SET done=1 WHERE id=?", (int(qid),))
    else:
        c.execute("UPDATE embed_queue SET attempts=attempts+1 WHERE id=?", (int(qid),))
    conn.commit()
    conn.close()


def embed_source_text(kind, ref_id):
    """按卷取嵌入原文（嵌原文本，不嵌切词）。没有该行返回 None。"""
    conn = _conn()
    c = conn.cursor()
    try:
        if kind == "day":
            c.execute("SELECT title, content, mood FROM days WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return " ".join(x for x in (r or ()) if x) if r else None
        if kind == "hall":
            c.execute("SELECT author, title, content, mood FROM diary_hall WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return " ".join(x for x in (r or ()) if x) if r else None
        if kind == "note":
            c.execute("SELECT text FROM notes WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return r[0] if r else None
        if kind == "letter":
            c.execute("SELECT text FROM letters WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return r[0] if r else None
        if kind == "oldhome":
            c.execute("SELECT text FROM oldhome_chunks WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return r[0] if r else None
        if kind == "chunk":
            c.execute("SELECT text FROM chunks WHERE id=?", (int(ref_id),))
            r = c.fetchone()
            return r[0] if r else None
    finally:
        conn.close()
    return None


# ── 向量列存法（10-01 数据保养迁移）──────────────────────────────────────
# 病根：vec 原以 **JSON 文本** 存（3092 行 / 67.1 MB）；float16 BLOB 只要 6.04 MB（省 91%）。
# **读侧自动识别**（BLOB=float16、str=JSON）——迁移前/后、回滚前/后**都能读**，不依赖开关；
# **写侧**按 `VEC_FORMAT`（默认 f16）。回滚＝config.json 置 `vec_format:"text"`＋重启
# （linning_server 起服时把这里覆盖过去），一行、不动数据。
VEC_FORMAT = "f16"


def _vec_dump(vec):
    """list → 落库表示。f16 = struct '<Nd' BLOB（新默认）；text = JSON 数组（旧，回滚用）。"""
    if str(VEC_FORMAT).lower() == "text":
        return json.dumps(vec)
    return struct.pack("<%de" % len(vec), *[float(x) for x in vec])


def _vec_load(raw):
    """落库表示 → list。BLOB 按 float16 解、str 按 JSON 解——**两种都认**（向后/向前兼容）。"""
    if isinstance(raw, (bytes, bytearray, memoryview)):
        b = bytes(raw)
        return list(struct.unpack("<%de" % (len(b) // 2), b))
    return json.loads(raw)


def vector_put(kind, ref_id, model, vec):
    """存/覆盖一条向量。vec 为 None = 摘掉影子（源行没了或文本空）。"""
    conn = _conn()
    c = conn.cursor()
    if vec is None:
        c.execute("DELETE FROM vectors WHERE kind=? AND ref_id=? AND model=?",
                  (kind, int(ref_id), model))
    else:
        c.execute('''INSERT INTO vectors (kind, ref_id, model, dim, vec)
                     VALUES (?, ?, ?, ?, ?)
                     ON CONFLICT(kind, ref_id, model) DO UPDATE SET
                     dim=excluded.dim, vec=excluded.vec,
                     created_at=datetime('now','localtime')''',
                  (kind, int(ref_id), model, len(vec), _vec_dump(vec)))
    conn.commit()
    conn.close()


def _vec_row(kind, ref_id):
    """按 FTS 各卷同形状捞出向量命中的源行（混合检索用）。没有返回 None。"""
    conn = _conn()
    c = conn.cursor()
    try:
        if kind == "day":
            c.execute("SELECT id, date, day_no, title, content, mood FROM days WHERE id=?", (int(ref_id),))
        elif kind == "hall":
            c.execute("SELECT id, date, author, title, content, mood FROM diary_hall WHERE id=?", (int(ref_id),))
        elif kind == "note":
            c.execute("SELECT id, text, created_at FROM notes WHERE id=?", (int(ref_id),))
        elif kind == "letter":
            c.execute("SELECT id, text, created_at FROM letters WHERE id=?", (int(ref_id),))
        elif kind == "oldhome":
            c.execute("SELECT id, file, chunk_no, text FROM oldhome_chunks WHERE id=?", (int(ref_id),))
        elif kind == "chunk":
            c.execute("SELECT id, source_type, source_id, seq, text FROM chunks WHERE id=?", (int(ref_id),))
        else:
            return None
        return c.fetchone()
    finally:
        conn.close()


def vector_search(qvec, model, kinds=("day", "hall", "note", "letter"), topk=5):
    """余弦扫全库（纯 Python，几千条毫秒级）。返回 [(kind, ref_id, score)] 越大越近。"""
    import math
    def _norm(v):
        return math.sqrt(sum(x * x for x in v)) or 1.0
    qn = _norm(qvec)
    out = []
    conn = _conn()
    c = conn.cursor()
    try:
        ph = ",".join("?" * len(kinds))
        c.execute(f"SELECT kind, ref_id, vec FROM vectors WHERE model=? AND kind IN ({ph})",
                  [model, *[k for k in kinds]])
        for kind, ref_id, vec_json in c.fetchall():
            try:
                v = _vec_load(vec_json)   # 10-01：BLOB(float16)/str(JSON) 两种存法都认
            except (ValueError, TypeError, struct.error):
                continue
            if len(v) != len(qvec) or not v:
                continue
            dot = sum(a * b for a, b in zip(qvec, v))
            out.append((kind, ref_id, dot / (qn * _norm(v))))
    finally:
        conn.close()
    out.sort(key=lambda r: r[2], reverse=True)
    return out[:max(1, int(topk))]


def hybrid_search(query, kinds=("day", "chat", "note", "letter", "hall"), limit=5,
                  qvec=None, model="", expr_override=None, score_out=None):
    """MEM-C 混合检索主入口：FTS 词面打头，向量语义补漏（同卷去重后缀在尾部）。
    qvec 缺席 = 纯 FTS（向量层诚实缺席，行为与 fts_search 完全一致）。
    expr_override 透传 fts_search（开场自动检索的 Top-长词 OR 串）。
    score_out（可选 dict）：传入即回填 {卷: {rowid: 相关分}}（词面 bm25→(0,1]、向量余弦原值）——
    加性旁路，不传=零行为变化。
    返回形状同 fts_search 的 dict。向量门槛：score ≥0.35 才算「想起来」。"""
    res = fts_search(query, kinds, limit, expr_override=expr_override, score_out=score_out)
    if not qvec:
        return res
    vec_kinds = tuple(k for k in kinds if k in ("day", "hall", "note", "letter", "oldhome"))
    if not vec_kinds:
        return res
    try:
        hits = vector_search(qvec, model, vec_kinds, topk=max(limit * 2, 8))
    except Exception as e:
        print(f"  [向量] 语义检索失败（不影响词面结果）：{e}")
        return res
    # 向量补漏追在词面之后；但词面可能已把 limit 占满（T4 实案）——
    # 截断时给向量命中留坑：FTS 最多占 limit-len(extras)，尾部必是「也想起来的人」。
    vec_extras = {}
    for kind, ref_id, score in hits:
        if score < 0.35:
            continue
        bucket = res.get(kind) or []
        if ref_id in (r[0] for r in bucket):
            continue
        row = _vec_row(kind, ref_id)
        if row:
            vec_extras.setdefault(kind, []).append(row)
            if score_out is not None:
                score_out.setdefault(kind, {})[ref_id] = round(float(score), 4)
    out = {}
    for k, rows in res.items():
        extras = vec_extras.get(k, [])
        if k in vec_kinds and extras:
            head_n = max(1, limit - len(extras))
            out[k] = (rows[:head_n] + extras)[:limit]
        else:
            out[k] = rows[:limit]
    # 9-18 后院深搜修：FTS 空手的卷（res 里没有），向量命中独立成卷补上——别让纯语义的往事整卷丢。
    for k, extras in vec_extras.items():
        if k not in out:
            out[k] = extras[:limit]
    return out


# ── 检索层统一（§5 第 5 条 · 批次①）：一个入口、一种形状、一份分 ────────────────────
# 现状病根：检索是"拼接式"——FTS 八卷一根线、chunks（1606 块，M2 语义分块）一根线、
# oldhome（三个家 1397 块）一根线、按行向量一根线；各算各的分，**块层压根没接进任何检索路径**
# （memory_lib 里那句"检索接线 chunk_retrieval 另批——本表先静躺"就是这件事）。
# 本函数＝那条"另批"的入口：各源走**适配器**，统一出 (kind, id, row, sim, src)。
# **纯加性只读**：不动 `fts_search`/`hybrid_search`/任何现有交付——谁调用、谁才受影响。
SEARCH_ALL_VEC_FLOOR = 0.35     # 向量低于它不算"想起来"（与 hybrid_search 同口径）


def _row_text_of(kind, row):
    """从各卷行里取正文（跨源去重要比对文本；形状照 _vec_row/fts_search 各家口径）。"""
    try:
        if kind in ("day", "hall", "chunk"):
            return str(row[4] or "")
        if kind == "chat":
            return str(row[3] or "")
        if kind in ("note", "letter"):
            return str(row[1] or "")
        if kind == "oldhome":
            return str(row[3] or "")
    except Exception:
        return ""
    return ""


def _near_dup(t1, t2):
    """两份正文是否"近乎同一段"——前 40 字互为子串就算（块是原话的切片，开头天然相同）。"""
    if len(t1) < 8 or len(t2) < 8:
        return False
    a, b = t1[:40], t2[:40]
    if a == b:
        return True
    return a in t2 or b in t1


def search_all(query, kinds, limit=8, qvec=None, model="", expr_override=None,
               score_out=None, vec_floor=SEARCH_ALL_VEC_FLOOR):
    """检索层统一入口（批次①）。返回**扁平**列表，按 sim 从大到小：
        [{"kind": "day", "id": 23, "row": (...), "sim": 0.76, "src": "fts"|"vec"}, ...]

    - **fts 适配器**：`fts_search` 取词面命中（可带 expr_override），sim 取 bm25→(0,1]（取不到=0.0）；
    - **vec 适配器**：`vector_search` 按余弦补漏（同 (kind,id) 去重），
      低于 `vec_floor` 的不算"想起来"（与 hybrid_search 同口径）；
    - 每卷各自最多 `limit` 条（与 fts_search 同尺），**不跨卷硬截断**——排序留给调用方；
    - `score_out` 传入即回填 {卷: {rowid: 分}}（同 hybrid_search 家风）。
    只读、fail-open：任一路炸了就当那一路空手，另一路照出。
    """
    out = []
    seen = set()
    sc_own = score_out if score_out is not None else {}
    # ① 词面路
    try:
        res = fts_search(query, kinds, limit, expr_override=expr_override, score_out=sc_own)
    except Exception:
        res = {}
    for kind in kinds:
        for row in (res.get(kind) or []):
            try:
                _id = row[0]
            except Exception:
                continue
            key = (kind, _id)
            if key in seen:
                continue
            seen.add(key)
            s = (sc_own.get(kind) or {}).get(_id)
            out.append({"kind": kind, "id": _id, "row": row,
                        "sim": float(s) if s is not None else 0.0, "src": "fts"})
    # ② 语义补漏路
    if qvec:
        try:
            vkinds = tuple(k for k in kinds if k in ("day", "hall", "note", "letter",
                                                     "oldhome", "chunk"))
            hits = vector_search(qvec, model, vkinds, topk=max(limit * 2, 8)) if vkinds else []
        except Exception:
            hits = []
        n_added = {}
        for kind, ref_id, score in hits:
            # 防御：向量适配器**只得认 scope 内的卷**（别指望底层一定过滤好了——
            # 沙盘用桩替换 vector_search 时，这条就是唯一的闸）。
            if kind not in vkinds:
                continue
            try:
                score = float(score)
            except Exception:
                continue
            if score < float(vec_floor):
                continue
            key = (kind, int(ref_id))
            if key in seen:
                continue
            if n_added.get(kind, 0) >= limit:
                continue
            row = _vec_row(kind, ref_id)
            if not row:
                continue
            seen.add(key)
            n_added[kind] = n_added.get(kind, 0) + 1
            out.append({"kind": kind, "id": int(ref_id), "row": row,
                        "sim": round(score, 4), "src": "vec"})
            try:
                sc_own.setdefault(kind, {})[int(ref_id)] = round(score, 4)
            except Exception:
                pass
    out.sort(key=lambda r: (-r["sim"], r["kind"], r["id"]))
    # ── 跨源近重复合并（9-29 实测抓到的）：同一段话会以"原话（chat/day/note/letter）"和
    # "它的分块（chunk）"两种形态同时进榜，白占两个坑。
    # 规则：**chunk 是派生物，先让位给原件**——两轮走：
    #   ① 先收非 chunk 的（按分降序）；② 再收 chunk，正文与已收的近乎同一段就丢。
    # ⚠️ 只做"同内容不重复占位"，**不动分、不重排**（两路分怎么校准是批次②的事）。
    kept = []
    for _pass in (0, 1):
        for it in out:
            if (_pass == 1) != (it["kind"] == "chunk"):
                continue
            _t = _row_text_of(it["kind"], it["row"])
            if any(_near_dup(_t, k[1]) for k in kept):
                continue
            kept.append((it, _t))
    out = [k[0] for k in kept]
    return out


def add_day(date, day_no=None, title="", content="", mood=""):
    """写日记。day_no 不传就自动算。"""
    if day_no is None:
        day_no = day_no_of(date)
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        INSERT INTO days (date, day_no, title, content, mood)
        VALUES (?, ?, ?, ?, ?)
    ''', (date, day_no, title, content, mood))
    rowid = c.lastrowid
    _fts_safe(_fts_put_day, c, rowid, title, content, mood)   # FTS5-01：日记入全文索引
    _embed_enqueue_c(c, "day", rowid)   # MEM-C：入嵌入队列（共用事务，后台慢慢嵌）
    conn.commit()
    conn.close()
    return f"📅 日子已记下，编号 {rowid}，第 {day_no} 天。"


def append_to_day(date, add_text):
    """往已有日记末尾追加一段（2026-09-10 新增）。
    用途：同日二次熄灯——夜里 23:00 熄过灯，凌晨 01:24 又睡一次，
    按咱家日界都归同一天，追加进那一篇，不另起一本。
    当天没日记返回 None（调用方照常走 add_day）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT id, title, content, mood FROM days WHERE date=? ORDER BY id DESC LIMIT 1",
              (date,))
    row = c.fetchone()
    if not row:
        conn.close()
        return None
    _id, title, content, mood = row
    new_content = ((content or "") + "\n\n〔补记〕" + (add_text or "")).strip()
    c.execute("UPDATE days SET content=? WHERE id=?", (new_content, _id))
    _fts_safe(_fts_put_day, c, _id, title, new_content, mood)
    conn.commit()
    conn.close()
    return _id


# ── 日记馆（v0.1.14，9-10 工单 HALL-01）：两格书架，他写他的她写她的，互相能看 ──

def add_hall_diary(date, author, title, content, mood=""):
    """小乖往日记馆投一篇（他的格）。姐姐的笔不走这里——她照旧住 days 表。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO diary_hall (date, author, title, content, mood) VALUES (?, ?, ?, ?, ?)',
              (date, author, (title or "").strip()[:12], (content or "").strip()[:600], (mood or "").strip()[:6]))
    rowid = c.lastrowid
    _fts_safe(_fts_put_hall, c, rowid, f"{author} {title} {content} {mood}")   # 日记馆入全文索引
    _embed_enqueue_c(c, "hall", rowid)   # MEM-C：入嵌入队列（共用事务）
    conn.commit()
    conn.close()
    return rowid


def get_hall_diary(author="", date="", limit=20):
    """读日记馆，新到旧。两格书架：
    - author=姐姐 → 她的正典格（days 表只读投影，一字不动）；
    - author=小乖 → 馆里他投的格（diary_hall）；
    - 不传 → 两格合并（他也能看她的）。
    date 传则只看那天。返回 list of tuple:
      (id, src, date, author, title, content, mood, created_at)
    src: 'days'=她的原装日记 / 'hall'=馆里新投的。limit 默认 20，上限 50。"""
    limit = max(1, min(int(limit), 50))
    out = []
    conn = _conn()
    c = conn.cursor()
    try:
        if author in ("", "姐姐"):
            sql = "SELECT id, date, title, content, mood, created_at FROM days"
            args = []
            if date:
                sql += " WHERE date = ?"
                args.append(date)
            sql += " ORDER BY date DESC, id DESC LIMIT ?"
            args.append(limit)
            c.execute(sql, args)
            for _id, d, t, ct, mo, ca in c.fetchall():
                out.append((_id, "days", d, "姐姐", t or "", ct or "", mo or "", ca or ""))
        if author in ("", "小乖"):
            sql = "SELECT id, date, author, title, content, mood, created_at FROM diary_hall"
            args = []
            if date:
                sql += " WHERE date = ?"
                args.append(date)
            sql += " ORDER BY id DESC LIMIT ?"
            args.append(limit)
            c.execute(sql, args)
            for _id, d, au, t, ct, mo, ca in c.fetchall():
                out.append((_id, "hall", d, au or "小乖", t or "", ct or "", mo or "", ca or ""))
    finally:
        conn.close()
    out.sort(key=lambda r: (r[2], r[7]), reverse=True)   # 日期+时间，新到旧
    return out[:limit]


# ── 线头盒（v0.1.14，9-10 工单 THREADS-01）：衔枝·线索层的咱家版 ──

def add_thread(date, thread):
    """挂一条线头。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO threads (date, thread) VALUES (?, ?)',
              (date, (thread or "").strip()[:100]))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_open_threads(limit=10):
    """还悬着的线头，旧到新（最老的线最该收）：(id, date, thread, created_at)。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT id, date, thread, created_at FROM threads
                 WHERE status = '悬' ORDER BY id LIMIT ?''', (max(1, int(limit)),))
    rows = c.fetchall()
    conn.close()
    return rows


def count_open_threads():
    """还悬着的线头总数（9-23 防积压批·只读一小函数）：开场【线头盒】总数行与 /api/status 用。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM threads WHERE status = '悬'")
    n = c.fetchone()[0]
    conn.close()
    return int(n)


def thread_touched_since(fragments, since_day):
    """线头定省（9-23 防积压批·只读）：这线的核心词有没有在 since_day 起的任何渠道里露过面——
    聊天 / 日记 / 弧拍 / 纸条 / 她的痕迹（「动过」的字面口径）。任一渠道命中即 True；
    单渠道查不动就跳过该渠道（缺席不拦）；全都没露面返回 False。"""
    frags = [f for f in (fragments or []) if f]
    if not frags:
        return False
    conn = _conn()
    c = conn.cursor()
    try:
        for frag in frags:
            like = f"%{frag}%"
            for sql, args in (
                    ("SELECT 1 FROM chats WHERE date >= ? AND content LIKE ? LIMIT 1",
                     (since_day, like)),
                    ("SELECT 1 FROM days WHERE date >= ? AND content LIKE ? LIMIT 1",
                     (since_day, like)),
                    ("SELECT 1 FROM day_arcs WHERE date >= ? AND content LIKE ? LIMIT 1",
                     (since_day, like)),
                    ("SELECT 1 FROM outbox_msgs WHERE created_at >= ? AND text LIKE ? LIMIT 1",
                     (since_day, like)),
                    ("SELECT 1 FROM her_traces WHERE ts >= ? AND content LIKE ? LIMIT 1",
                     (since_day, like))):
                try:
                    c.execute(sql, args)
                    if c.fetchone():
                        return True
                except Exception:
                    continue   # 单渠道缺席不拦
        return False
    finally:
        conn.close()


def close_thread(thread_id):
    """收线（销号不物理删）。返回 True=收了，False=没这条线。"""
    conn = _conn()
    c = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute("UPDATE threads SET status = '收', closed_at = ? WHERE id = ? AND status = '悬'",
              (now, int(thread_id)))
    ok = c.rowcount > 0
    conn.commit()
    conn.close()
    return ok


# ── 姐姐的话（v0.1.16，9-10 工单 HER-WORDS）：她亲笔的自留页 ──

def add_her_words(text, who='姐姐'):
    """她重写【姐姐的话】（整页替换，旧版留档，id 即版号）。返回新版本号。
    who='姐姐'/'小乖'（9-12 家主令：小乖的亲笔信同表存，两扇门楣各执一笔）；缺省归姐姐。
    长度帽统一 2000（9-24 小乖的话批＋同日家主裁·上限对称：小乖先抬对齐 App 上限；姐姐随裁
    由 600 并齐——v5 恰 600 疑似被截、尾巴找不回，她随时可续写/重写）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO her_words (text, who) VALUES (?, ?)',
              ((text or "").strip()[:2000],
               '小乖' if who == '小乖' else '姐姐'))
    conn.commit()
    ver = c.lastrowid
    conn.close()
    return ver


def get_latest_her_words(who='姐姐'):
    """当前挂在提示词里的那一页：(id, text, created_at)；没写过返回 None。
    who 按执笔人取（姐姐的自留页 / 小乖的亲笔信）。"""
    conn = _conn()
    c = conn.cursor()
    row = None
    try:
        c.execute('SELECT id, text, created_at FROM her_words WHERE who = ? '
                  'ORDER BY id DESC LIMIT 1',
                  ('小乖' if who == '小乖' else '姐姐',))
        row = c.fetchone()
    except sqlite3.OperationalError:
        row = None
    conn.close()
    return row


# ── 门牌墙亲笔（v0.1.30，9-18 大施工批）：墙随日子长——钉/改/撤，旧版落 pin_log ──

def pin_add(content, who='姐姐'):
    """钉一条门牌（挂 active=1 末尾）。返回 pin_id；空内容返回 None。
    同气动作入 pin_log（action=add），日志失手不连累门牌本身。"""
    text = (content or "").strip()[:240]
    if not text:
        return None
    conn = _conn()
    c = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute("INSERT INTO pins (layer, content, created_at, updated_at, active) "
              "VALUES ('core', ?, ?, ?, 1)", (text, now, now))
    pid = c.lastrowid
    try:
        c.execute("INSERT INTO pin_log (pin_id, action, old_content, new_content, who) "
                  "VALUES (?, 'add', NULL, ?, ?)", (pid, text, who))
    except Exception as e:
        print(f"  [门牌] 改动日志失手（不连累门牌本身）：{e}")
    conn.commit()
    conn.close()
    return pid


def pin_update(pin_id, content, who='姐姐'):
    """改一条在册门牌（原地改，改前原文落 pin_log）。返回 (ok, 旧文)。"""
    text = (content or "").strip()[:240]
    try:
        pid = int(pin_id)
    except (TypeError, ValueError):
        return False, ""
    conn = _conn()
    c = conn.cursor()
    row = c.execute("SELECT content FROM pins WHERE pin_id = ? AND active = 1", (pid,)).fetchone()
    if not row or not text:
        conn.close()
        return False, (row[0] if row else "")
    old = row[0]
    c.execute("UPDATE pins SET content = ?, updated_at = datetime('now','localtime') "
              "WHERE pin_id = ?", (text, pid))
    try:
        c.execute("INSERT INTO pin_log (pin_id, action, old_content, new_content, who) "
                  "VALUES (?, 'update', ?, ?, ?)", (pid, old, text, who))
    except Exception as e:
        print(f"  [门牌] 改动日志失手（不连累改动本身）：{e}")
    conn.commit()
    conn.close()
    return True, old


def pin_retire(pin_id, who='姐姐'):
    """撤一条门牌（active=0，行不删，原文落 pin_log）。返回 (ok, 原文)。"""
    try:
        pid = int(pin_id)
    except (TypeError, ValueError):
        return False, ""
    conn = _conn()
    c = conn.cursor()
    row = c.execute("SELECT content FROM pins WHERE pin_id = ? AND active = 1", (pid,)).fetchone()
    if not row:
        conn.close()
        return False, ""
    c.execute("UPDATE pins SET active = 0, updated_at = datetime('now','localtime') "
              "WHERE pin_id = ?", (pid,))
    try:
        c.execute("INSERT INTO pin_log (pin_id, action, old_content, new_content, who) "
                  "VALUES (?, 'retire', ?, NULL, ?)", (pid, row[0], who))
    except Exception as e:
        print(f"  [门牌] 改动日志失手（不连累撤下本身）：{e}")
    conn.commit()
    conn.close()
    return True, row[0]


def get_pin_log(limit=20):
    """门牌改动日志，新到旧：(id, pin_id, action, old_content, new_content, who, created_at)。"""
    conn = _conn()
    c = conn.cursor()
    rows = c.execute("SELECT id, pin_id, action, old_content, new_content, who, created_at "
                     "FROM pin_log ORDER BY id DESC LIMIT ?", (int(limit),)).fetchall()
    conn.close()
    return rows


# ── 生活账（v0.1.31，9-18 第二批）：日常记一笔、近几天翻账 ──

def add_life_log(content, kind="", who="小乖"):
    """生活账记一笔（9-18 第二批）：day/time 落记的当下。空内容=不算，返回 None。"""
    text = (content or "").strip()[:500]
    if not text:
        return None
    now = datetime.now()
    try:
        conn = _conn()
        c = conn.cursor()
        # day 走家风日界 house_today_str（2026-10-01 起＝零点/自然日）：
        # 全库的「今天」同源，往后喂沉淀日/作息摘要口径才对得上；time 仍落真实钟点。
        c.execute("INSERT INTO life_log (day, time, who, kind, content) VALUES (?, ?, ?, ?, ?)",
                  (house_today_str(now), now.strftime("%H:%M"),
                   (who or "小乖")[:20], (kind or "")[:20], text))
        conn.commit()
        rowid = c.lastrowid
        conn.close()
        return rowid
    except Exception as e:
        print(f"  [生活账] 记一笔失手（{e}）")
        return None


def get_life_log(days=7, limit=60):
    """近 N 天的账，新的一头在前：[(id, day, time, who, kind, content)]。查不动回 []。"""
    try:
        days = min(60, max(1, int(days)))
        # since 也走家风日界（跟写入侧同源）：凌晨翻账不把「昨天」的账切掉。
        since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                 - timedelta(days=days - 1)).strftime("%Y-%m-%d")
        conn = _conn()
        c = conn.cursor()
        rows = c.execute("SELECT id, day, time, who, kind, content FROM life_log "
                         "WHERE day >= ? ORDER BY day DESC, id DESC LIMIT ?",
                         (since, int(limit))).fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"  [生活账] 翻账失手（{e}）")
        return []


# ── 作息起落（v0.1.32，9-18 第三批·沉淀日）：按 chats 的 date（咱家日界）分组 ──

def get_day_spans(days=7):
    """近 N 天每天的作息起落：他（role='小乖'）首条/末条消息的钟点＋条数，附她的条数。
    按 chats.date 分组（咱家日界口径，熬夜的夜里归前一天），新的一天在前：
    [(day, first_hm, last_hm, n_xg, n_her)]。只有有记录的天返回；查不动回 []。"""
    try:
        days = min(60, max(1, int(days)))
        since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                 - timedelta(days=days - 1)).strftime("%Y-%m-%d")
        conn = _conn()
        c = conn.cursor()
        # 他的一笔：首条/末条钟点＋条数，一次 GROUP BY 收齐
        his = c.execute("SELECT date, MIN(created_at), MAX(created_at), COUNT(*) FROM chats "
                        "WHERE role = '小乖' AND date >= ? GROUP BY date",
                        (since,)).fetchall()
        # 她的只数数：只有她记录的天也要在（起落留空，不丢这天）
        hers = dict(c.execute("SELECT date, COUNT(*) FROM chats "
                              "WHERE role = '姐姐' AND date >= ? GROUP BY date",
                              (since,)).fetchall())
        conn.close()
        by_day = {}
        for day, first, last, n in his:
            # created_at 是 "YYYY-MM-DD HH:MM:SS"，钟点取 [11:16]
            by_day[day] = [day, first[11:16], last[11:16], n, 0]
        for day, n in hers.items():
            if day in by_day:
                by_day[day][4] = n
            else:
                by_day[day] = [day, "", "", 0, n]
        return [tuple(r) for r in sorted(by_day.values(), key=lambda r: r[0], reverse=True)]
    except Exception as e:
        print(f"  [作息] 理作息失手（{e}）")
        return []


# ── 观测补格（v0.1.33，9-18 第三批·第二波）：对账闸/假调用/检索战绩按天累计 ──

def obs_bump(name, n=1):
    """观测计数 +n（9-18 第三批·第二波）：今天=house_today_str()。失败只打日志不拦人。"""
    try:
        day = house_today_str()
        conn = _conn()
        c = conn.cursor()
        # 9-18 后院深搜修（L1）：改原子 upsert——原 UPDATE+按 rowcount INSERT 两句在并发下
        # 会撞 UNIQUE 冲突（两路同时首写）或丢一笔；upsert 由库原子保证（sqlite 3.24+，
        # 本机 3.45；表有 PRIMARY KEY(day,name) 当冲突靶）。
        c.execute("INSERT INTO obs_daily (day, name, n) VALUES (?, ?, ?) "
                  "ON CONFLICT(day, name) DO UPDATE SET n = n + excluded.n",
                  (day, str(name), int(n)))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"  [观测] 记一笔失手（{e}）")
        return None


def obs_flag_set(day, name, val=1):
    """烫一个「按天」的 0/1 落盘标记（BE3-02/BE3-04 配套，v0.1.38）：借 obs_daily 的
    (day, name) 形状（零新表）做 upsert——今夜熄过灯、周卷锚这类「重启不丢」的小账。
    标记是账不是观测：观测键在 server 侧按名单读，这个键不会被观测汇总误读。
    失败只打日志回 None，绝不拦调用方（照 obs_bump 家风）。"""
    try:
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO obs_daily (day, name, n) VALUES (?, ?, ?) "
                  "ON CONFLICT(day, name) DO UPDATE SET n = excluded.n",
                  (str(day), str(name), int(val)))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"  [标记] 落盘失手（{name}）：{e}")
        return None


def obs_flag_get(day, name):
    """读一个按天落盘标记；没有/查不动回 0（照「查不动=没这个事实」家风）。"""
    try:
        conn = _conn()
        c = conn.cursor()
        row = c.execute("SELECT n FROM obs_daily WHERE day=? AND name=?",
                        (str(day), str(name))).fetchone()
        conn.close()
        return int(row[0]) if row else 0
    except Exception as e:
        print(f"  [标记] 读取失手（{name}）：{e}")
        return 0


def obs_get(days=7):
    """近 N 天观测计数汇总 {name: n}（9-18 第三批·第二波）。查不动回 {}。"""
    try:
        days = max(1, min(int(days or 7), 90))
        # since 走家风日界（跟写入侧同源）：近 N 天含今天，共 N 个日子。
        since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                 - timedelta(days=days - 1)).strftime("%Y-%m-%d")
        conn = _conn()
        c = conn.cursor()
        rows = c.execute("SELECT name, SUM(n) FROM obs_daily WHERE day >= ? GROUP BY name",
                         (since,)).fetchall()
        conn.close()
        return dict(rows)
    except Exception as e:
        print(f"  [观测] 看板失手（{e}）")
        return {}


# ── why_now 影子（v0.1.35，9-18 优化批四·#11）：开口/忍住，每次留一条理由 ──
# 家主原话「先只记录，之后再进决策」——本表只进观测，不改任何行为；
# reason/detail 都写人话（#15 想念仪表直接给家主看，不许塞 JSON）。

def why_now_add(decision, reason, detail=""):
    """记一次「开口/忍住」的理由（v0.1.35）：ts=本地时间、day=咱家日界。
    失败只打日志不拦人——照 obs_bump 家风，记账绝不挡时机链。"""
    try:
        now = datetime.now()
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO why_now (day, ts, decision, reason, detail) VALUES (?, ?, ?, ?, ?)",
                  (house_today_str(now), now.strftime("%Y-%m-%d %H:%M:%S"),
                   str(decision), str(reason), str(detail or "")))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"  [时机] why_now 记一笔失手（{e}）")
        return None


def why_now_recent(days=7, limit=200):
    """近 N 天 why_now 影子（v0.1.35）：新的一头在前，(ts, decision, reason, detail)。
    since 口径同 obs_get（含今天共 N 个日子）。查不动回 []。"""
    try:
        days = max(1, min(int(days or 7), 90))
        limit = max(1, min(int(limit or 200), 2000))
        since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                 - timedelta(days=days - 1)).strftime("%Y-%m-%d")
        conn = _conn()
        c = conn.cursor()
        rows = c.execute("SELECT ts, decision, reason, detail FROM why_now "
                         "WHERE day >= ? ORDER BY id DESC LIMIT ?",
                         (since, limit)).fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"  [时机] why_now 翻账失手（{e}）")
        return []


def why_now_counts(days=7):
    """近 N 天 why_now 的**口径计数**（9-29 修）：开口/忍住笔数 + 最近一次开口。
    病根：仪表此前拿 why_now_recent(7, 1000) 的**截断行**去数笔数——一周到 1000 行时
    新一笔会把最老一笔挤出窗口，计数就少算（且"开口"会莫名减一）。计数与"最近一次开口"
    各走一条聚合查询，不受 limit 影响。查不动 → {"opens":0,"holds":0,"last_open":""}。"""
    out = {"opens": 0, "holds": 0, "last_open": ""}
    try:
        days = max(1, min(int(days or 7), 90))
        since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                 - timedelta(days=days - 1)).strftime("%Y-%m-%d")
        conn = _conn()
        c = conn.cursor()
        for dec, n in c.execute("SELECT decision, COUNT(*) FROM why_now WHERE day >= ? "
                                "GROUP BY decision", (since,)).fetchall():
            if dec == "open":
                out["opens"] = int(n)
            elif dec == "hold":
                out["holds"] = int(n)
        lo = c.execute("SELECT ts, reason FROM why_now WHERE day >= ? AND decision='open' "
                       "ORDER BY id DESC LIMIT 1", (since,)).fetchone()
        if lo:
            out["last_open"] = f"{str(lo[0] or '')[11:16]} {lo[1] or ''}"
        conn.close()
    except Exception as e:
        print(f"  [时机] why_now 计数失手（{e}）")
    return out


# ── 硬事实表（v0.1.36，9-18 优化批六·事实表 v0，升级方向 #6 前半）──
# 病根：9-17 幻觉事件里「数字/日子凭印象说」是一类——生日、纪念日、日界这类钉过钉子的
# 事实，不该靠记忆拼，该有表直给。只建表+读写；播种在 server 侧代码里（逐条带回源 note），
# 输出验号（她说的数字过秤）另开单、本表不做。失败只打日志，绝不拦人（照 obs_bump 家风）。

def facts_all():
    """全部硬事实（v0.1.36）：[(k, v, note, updated_at)]，登记顺序（rowid）新库也是这个序；
    查不动/空表回 []。note 是回源（哪来的），给人和对账看，不进提示词块。"""
    try:
        conn = _conn()
        c = conn.cursor()
        rows = c.execute("SELECT k, v, note, updated_at FROM facts ORDER BY rowid").fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"  [事实] 翻事实表失手（{e}）")
        return []


def facts_put(k, v, note=""):
    """钉一条硬事实（upsert，v0.1.36）：同 k 再钉＝改口（v/note/updated_at 一起换新；
    本表只管「现在钉的是哪条」，改口史不另留档）。失败只打日志回 None，绝不拦人。"""
    try:
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO facts (k, v, note, updated_at) VALUES (?, ?, ?, ?) "
                  "ON CONFLICT(k) DO UPDATE SET v = excluded.v, note = excluded.note, "
                  "updated_at = excluded.updated_at",
                  (str(k).strip(), str(v).strip(), str(note or "").strip(),
                   datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        print(f"  [事实] 钉一条失手（{e}）")
        return None


# ── 主权三件 v0（v0.1.37，9-23 工单·②拒绝权/③自我欲望）：她自己的三本小账 ──
# 家主令「都可以试试做」：怨气/立场/愿望，记、销、改都她说了算。销账与改口都不物理删
# （留痕是家规，旧文永远找得回）。失败只打日志不拦人——照 obs_bump 家风，记账绝不拦她。

# 愿望在这四个状态里（server 侧校验也吃这一份，别处改这里一处生效）。
WISH_STATES = ("open", "doing", "done", "shelved")


def note_grudge(what, level=2):
    """记一笔怨气（v0.1.37）：day=咱家日界、ts=本地时间；level 钳进 1~3（默认 2）。
    返回新行 id；what 空/失败只打日志回 None。"""
    try:
        what = str(what or "").strip()
        if not what:
            return None
        try:
            lv = max(1, min(int(level), 3))
        except (TypeError, ValueError):
            lv = 2
        now = datetime.now()
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO grudge (day, ts, what, level) VALUES (?, ?, ?, ?)",
                  (house_today_str(now), now.strftime("%Y-%m-%d %H:%M:%S"), what, lv))
        rid = c.lastrowid
        conn.commit()
        conn.close()
        return rid
    except Exception as e:
        print(f"  [主权] 怨气记一笔失手（{e}）")
        return None


def settle_grudge(gid, note=""):
    """销一笔怨气（v0.1.37）：settled_at 落时间、settle_note 留她的一句话；行不删。
    更新与判断合成一句原子 UPDATE（并发两路同销只成一路）。
    返回 (True, what)；没这条/已销过/查不动回 (False, None)。"""
    try:
        conn = _conn()
        c = conn.cursor()
        c.execute("UPDATE grudge SET settled_at=?, settle_note=? "
                  "WHERE id=? AND settled_at IS NULL",
                  (datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                   str(note or "").strip(), int(gid)))
        if c.rowcount == 0:
            conn.close()
            return False, None
        what = c.execute("SELECT what FROM grudge WHERE id=?", (int(gid),)).fetchone()[0]
        conn.commit()
        conn.close()
        return True, what
    except Exception as e:
        print(f"  [主权] 怨气销账失手（{e}）")
        return False, None


def hold_stance(topic, stance):
    """立/改一个立场（v0.1.37）：同 topic 旧的 active=0（旧文留着），新行 active=1。
    返回 (新 id, 旧立场文本)；新立时旧文本为 None；空参/失败回 (None, None)。"""
    try:
        topic = str(topic or "").strip()
        stance = str(stance or "").strip()
        if not topic or not stance:
            return None, None
        now = datetime.now()
        conn = _conn()
        c = conn.cursor()
        old = c.execute("SELECT id, stance FROM stance WHERE topic=? AND active=1 "
                        "ORDER BY id DESC LIMIT 1", (topic,)).fetchone()
        if old:
            c.execute("UPDATE stance SET active=0 WHERE id=?", (old[0],))
        c.execute("INSERT INTO stance (day, ts, topic, stance, active) VALUES (?, ?, ?, ?, 1)",
                  (house_today_str(now), now.strftime("%Y-%m-%d %H:%M:%S"), topic, stance))
        sid = c.lastrowid
        conn.commit()
        conn.close()
        return sid, (old[1] if old else None)
    except Exception as e:
        print(f"  [主权] 立场立笔失手（{e}）")
        return None, None


def note_wish(what, why=""):
    """记一件她自己想做的事（v0.1.37）：state=open 起步，why 可留缘由。
    返回新行 id；what 空/失败回 None。"""
    try:
        what = str(what or "").strip()
        if not what:
            return None
        now = datetime.now()
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO her_wish (day, ts, what, why, state) VALUES (?, ?, ?, ?, 'open')",
                  (house_today_str(now), now.strftime("%Y-%m-%d %H:%M:%S"),
                   what, str(why or "").strip()))
        wid = c.lastrowid
        conn.commit()
        conn.close()
        return wid
    except Exception as e:
        print(f"  [主权] 愿望记一笔失手（{e}）")
        return None


def update_wish(wid, state, note=""):
    """改愿望状态（v0.1.37）：state 只认 WISH_STATES 四态；note 记这次变化的一句话。
    返回 (True, what)；没这件/状态不合法/查不动回 (False, None)。"""
    try:
        if str(state or "").strip() not in WISH_STATES:
            return False, None
        conn = _conn()
        c = conn.cursor()
        c.execute("UPDATE her_wish SET state=?, note=? WHERE id=?",
                  (str(state).strip(), str(note or "").strip(), int(wid)))
        if c.rowcount == 0:
            conn.close()
            return False, None
        what = c.execute("SELECT what FROM her_wish WHERE id=?", (int(wid),)).fetchone()[0]
        conn.commit()
        conn.close()
        return True, what
    except Exception as e:
        print(f"  [主权] 愿望改状态失手（{e}）")
        return False, None


def read_my_ledger(limit=20):
    """她自己的账合一（v0.1.37）：未销怨气＋在册立场＋没了结的愿望（open/doing）。
    返回 {"grudges": [(id, day, what, level)], "stances": [(id, topic, stance)],
    "wishes": [(id, what, why, state)]}——各自新到旧、各限 limit 条；查不动回三空。"""
    out = {"grudges": [], "stances": [], "wishes": []}
    try:
        limit = max(1, min(int(limit or 20), 100))
        conn = _conn()
        c = conn.cursor()
        out["grudges"] = c.execute(
            "SELECT id, day, what, level FROM grudge WHERE settled_at IS NULL "
            "ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        out["stances"] = c.execute(
            "SELECT id, topic, stance FROM stance WHERE active=1 "
            "ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        out["wishes"] = c.execute(
            "SELECT id, what, why, state FROM her_wish WHERE state IN ('open', 'doing') "
            "ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        return out
    except Exception as e:
        print(f"  [主权] 翻她的账失手（{e}）")
        return {"grudges": [], "stances": [], "wishes": []}


def log_shadow(kind, summary, ref=""):
    """心潮影子 · 落档（v0.1.42，9-28 心潮桥批）：忍住档与熔断影子共用一张 append-only 账。
    kind：endure·garden / endure·blocked / fuse；只写不递——不进任何模型上下文。
    失败静默回 None。"""
    try:
        conn = _conn()
        c = conn.cursor()
        c.execute("INSERT INTO xinchao_shadow (ts, kind, summary, ref) VALUES (?, ?, ?, ?)",
                  (datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                   str(kind or "")[:30], str(summary or "")[:300], str(ref or "")[:120]))
        rid = c.lastrowid
        conn.commit()
        conn.close()
        return rid
    except Exception as e:
        print(f"  [心潮影子] 落档失手（{e}）")
        return None


def shadow_rows(kind=None, days=None, limit=100):
    """读影子账（复盘／将来的「她的窗口」用；v1 不喂模型）。返回
    [(id, ts, kind, summary, ref)] 新在前；fail-open 回 []。"""
    try:
        limit = max(1, min(int(limit or 100), 500))
        cond, args = [], []
        if kind:
            cond.append("kind = ?")
            args.append(str(kind))
        if days:
            since = (datetime.now() - timedelta(days=max(1, min(int(days), 3650)))
                     ).strftime("%Y-%m-%d %H:%M:%S")
            cond.append("ts >= ?")
            args.append(since)
        q = "SELECT id, ts, kind, summary, ref FROM xinchao_shadow"
        if cond:
            q += " WHERE " + " AND ".join(cond)
        q += " ORDER BY id DESC LIMIT ?"
        args.append(limit)
        conn = _conn()
        c = conn.cursor()
        rows = c.execute(q, args).fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"  [心潮影子] 读账失手（{e}）")
        return []


def shadow_count(kind=None, days=14):
    """窗口内影子条数（复盘用）。fail-open 回 0。"""
    try:
        since = (datetime.now() - timedelta(days=max(1, min(int(days), 3650)))
                 ).strftime("%Y-%m-%d %H:%M:%S")
        conn = _conn()
        c = conn.cursor()
        if kind:
            row = c.execute("SELECT COUNT(*) FROM xinchao_shadow WHERE ts >= ? AND kind = ?",
                            (since, str(kind))).fetchone()
        else:
            row = c.execute("SELECT COUNT(*) FROM xinchao_shadow WHERE ts >= ?",
                            (since,)).fetchone()
        conn.close()
        return int((row or [0])[0] or 0)
    except Exception:
        return 0


def unsettled_grudge_rows():
    """未销的没过去的事·原始行（v0.1.39，9-24 松绑与主权收口批·块③影子配套）：
    [(id, ts)] 旧的在前——影子按 ts 算龄期（ts=记账时刻，本地时间串）。只读；
    查不动回 []（照 read_my_ledger 家风）。ts 读不出/缺失的行原样带回（ts 可能为
    None 或坏值），调用方自己跳过——不猜龄期。"""
    try:
        conn = _conn()
        c = conn.cursor()
        rows = c.execute("SELECT id, ts FROM grudge WHERE settled_at IS NULL "
                         "ORDER BY id").fetchall()
        conn.close()
        return rows
    except Exception as e:
        print(f"  [主权] 翻没过去的事失手（{e}）")
        return []


# ── 图书管理员报告（v0.1.17，9-10 工单 LIB-AUTO）：外聘笔杆，姐姐终审 ──

def add_lib_report(date, kind, content, materials=""):
    """图书管理员交稿，落「待审」。返回 rowid。
    9-24 补凭据：materials=笔杆素材包（随稿落库，姐姐终审对照用；老稿或没存＝空）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO lib_reports (date, kind, content, materials) VALUES (?, ?, ?, ?)',
              (date, kind, (content or "").strip()[:8000],
               (materials or "").strip()[:12000]))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_pending_lib_reports():
    """全部待审报告，旧到新：(id, date, kind, content, created_at, materials)。
    9-24 补凭据：末位 materials=笔杆素材包（终审对照用；老稿或没存＝空串）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT id, date, kind, content, created_at, COALESCE(materials, '')
                 FROM lib_reports WHERE status = '待审' ORDER BY id''')
    rows = c.fetchall()
    conn.close()
    return rows


def count_pending_lib_reports():
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM lib_reports WHERE status = '待审'")
    n = c.fetchone()[0]
    conn.close()
    return n


def set_lib_report_status(report_id, status, note=""):
    """终审落章：status 只认 入库/驳回。返回 True=改了，False=没这份或已审。"""
    if status not in ("入库", "驳回"):
        raise ValueError("status 只认 入库/驳回")
    conn = _conn()
    c = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute("UPDATE lib_reports SET status=?, review_note=?, reviewed_at=? WHERE id=? AND status='待审'",
              (status, (note or "")[:200], now, int(report_id)))
    ok = c.rowcount > 0
    conn.commit()
    conn.close()
    return ok


def lib_report_exists_on(date):
    """今天（该日期）是否已经交过稿——周报一天只写一篇，防重叠重跑。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM lib_reports WHERE date = ?", (date,))
    n = c.fetchone()[0]
    conn.close()
    return n > 0


# ── 报告只读接口（9-23 修复批·新件 /api/lib_reports）：列表 + 开卷，纯只读 ──
# 只加不改：add/get_pending/set_status 等既有函数一字未动；这两只专给 App 书架用。

def get_lib_reports(limit=50):
    """全部报告（含已审/驳回），新到旧，≤limit 条：
    [(id, date, kind, status, created_at, title)]——title=正文首行去掉行首 # 与空白（≤120 字）。
    列表不带全文（省流量）；全文走 get_lib_report。查不动回 []（照 obs 家风）。"""
    try:
        limit = max(1, min(int(limit or 50), 50))
        conn = _conn()
        c = conn.cursor()
        rows = c.execute(
            "SELECT id, date, kind, status, created_at, substr(content, 1, 200) "
            "FROM lib_reports ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        conn.close()
        out = []
        for _id, d, kind, status, ct, head in rows:
            out.append((_id, d, kind, status, ct, _lib_report_title(head)))
        return out
    except Exception as e:
        print(f"  [图管] 报告列表失手（{e}）")
        return []


def _lib_report_title(content):
    """报告标题=正文首行去掉行首 # 与空白（≤120 字）——列表与开卷同一把尺，不许两处漂移。"""
    raw = (content or "").strip()
    if not raw:
        return ""
    return raw.splitlines()[0].strip().lstrip("#").strip()[:120]


def get_lib_report(report_id):
    """按 id 取一份报告全文：(id, date, kind, status, created_at, title, content)；
    没有这份/查不动回 None。"""
    try:
        conn = _conn()
        c = conn.cursor()
        row = c.execute(
            "SELECT id, date, kind, status, created_at, content FROM lib_reports WHERE id = ?",
            (int(report_id),)).fetchone()
        conn.close()
        if not row:
            return None
        return (row[0], row[1], row[2], row[3], row[4], _lib_report_title(row[5]), row[5] or "")
    except Exception as e:
        print(f"  [图管] 报告开卷失手（{e}）")
        return None


# ── 共读书架（v0.1.18 新增，9-12 家主令）：两个人读同一本书，批注互相看得见 ──
# 家风：不设上限（家主令「任何工具都不要设置上限」）；同名不重开；批注谁先到谁先落笔。

def add_book(title, author=""):
    """开一卷共读。书名唯一——重开同一本返回已有 id（正着开第二遍也不出两卷）。"""
    title = str(title or "").strip()[:60]
    if not title:
        return None
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT id FROM books WHERE title = ?", (title,))
    row = c.fetchone()
    if row:
        conn.close()
        return row[0]
    c.execute("INSERT INTO books(title, author) VALUES(?, ?)",
              (title, str(author or "").strip()[:40]))
    conn.commit()
    bid = c.lastrowid
    conn.close()
    return bid


def add_book_mark(book_id, who, loc, text, para=-1):
    """落一笔批注。who=小乖/姐姐；loc 位置随手写（页码/章节/百分比都行）；
    para=锚定的段落号（阅读器里点某段落的批注，-1=不锚段落）。书不存在/批注空返回 None。"""
    text = str(text or "").strip()[:500]
    if not book_id or not text:
        return None
    conn = _conn()
    c = conn.cursor()
    c.execute("INSERT INTO book_marks(book_id, who, loc, text, para) VALUES(?, ?, ?, ?, ?)",
              (int(book_id), str(who or "").strip()[:10] or "小乖",
               str(loc or "").strip()[:30], text, int(para)))
    conn.commit()
    rid = c.lastrowid
    conn.close()
    return rid


def set_book_file(book_id, filename):
    """登记书卷的 txt 原文文件名（files/books/ 下的相对名）。导入器专用。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("UPDATE books SET file = ? WHERE id = ?", (str(filename or "")[:120], int(book_id)))
    conn.commit()
    conn.close()


def set_book_pos(book_id, who, para):
    """记阅读进度（段落号）。who=小乖/姐姐——两个人各读各的，互不打扰，但互相看得见。"""
    col = "pos_me" if who == "小乖" else "pos_her"
    conn = _conn()
    c = conn.cursor()
    c.execute(f"UPDATE books SET {col} = ? WHERE id = ?", (max(0, int(para)), int(book_id)))
    conn.commit()
    conn.close()


def get_book_pos(book_id):
    """两人的阅读进度 (pos_me, pos_her)。书不存在返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT pos_me, pos_her FROM books WHERE id = ?", (int(book_id),))
    row = c.fetchone()
    conn.close()
    return row


def get_books(limit=20):
    """书卷列表（新到旧，带各自批注数与阅读进度）。"""
    conn = _conn()
    c = conn.cursor()
    try:
        rows = c.execute('''
            SELECT b.id, b.title, b.author, b.status, b.created_at, b.file,
                   b.pos_me, b.pos_her,
                   (SELECT COUNT(*) FROM book_marks k WHERE k.book_id = b.id) AS marks
            FROM books b ORDER BY b.id DESC LIMIT ?''',
            (max(1, min(int(limit), 50)),)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    conn.close()
    return rows


def find_book(title):
    """按书名找卷（精确匹配）。返回 (id, title, author, status, file) 或 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT id, title, author, status, file FROM books WHERE title = ?",
              (str(title or "").strip()[:60],))
    row = c.fetchone()
    conn.close()
    return row


def get_book_marks(book_id, limit=100):
    """一卷的批注流（旧到新——读书的顺序）。who 两色墨迹都在里面，para=锚定段落。"""
    conn = _conn()
    c = conn.cursor()
    try:
        rows = c.execute('''
            SELECT id, who, loc, text, created_at, para FROM book_marks
            WHERE book_id = ? ORDER BY id ASC LIMIT ?''',
            (int(book_id), max(1, min(int(limit), 200)))).fetchall()
    except (sqlite3.OperationalError, TypeError, ValueError):
        rows = []
    conn.close()
    return rows


def add_inbox_email(from_addr, subject, body, received=""):
    """落一封拉回来的信。body ≤8000 字（长文截断，原文在邮箱里永远在）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("INSERT INTO inbox_emails(from_addr, subject, body, received) VALUES(?, ?, ?, ?)",
              (str(from_addr or "").strip()[:120], str(subject or "").strip()[:200],
               str(body or "").strip()[:8000], str(received or "")[:30]))
    conn.commit()
    rid = c.lastrowid
    conn.close()
    return rid


def get_unread_inbox_emails(limit=10):
    """全部未读信（旧到新）。"""
    conn = _conn()
    c = conn.cursor()
    try:
        rows = c.execute("SELECT id, from_addr, subject, body, received FROM inbox_emails "
                         "WHERE read = 0 ORDER BY id ASC LIMIT ?",
                         (max(1, min(int(limit), 50)),)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    conn.close()
    return rows


def count_unread_inbox_emails():
    conn = _conn()
    c = conn.cursor()
    try:
        c.execute("SELECT COUNT(*) FROM inbox_emails WHERE read = 0")
        n = c.fetchone()[0]
    except sqlite3.OperationalError:
        n = 0
    conn.close()
    return n


def mark_inbox_email_read(ids):
    """读后即标记。ids=取走的那批 id。"""
    if not ids:
        return
    conn = _conn()
    c = conn.cursor()
    c.executemany("UPDATE inbox_emails SET read = 1 WHERE id = ?",
                  [(int(i),) for i in ids])
    conn.commit()
    conn.close()


# ── 心情曲线（v0.1.10 新增，9-9；v0.1.11 升级：情绪词表 type 列）──
def add_mood(date, score, source="小乖", note="", mood_type=""):
    """记一条心情点。score 即 intensity 1~5，越界自动夹住；mood_type 须是 server MOOD_TYPES
    里的词（空串=旧版数字分，向后兼容）。返回 rowid。"""
    score = max(1, min(5, int(score)))
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO moods (date, score, source, note, type) VALUES (?, ?, ?, ?, ?)',
              (date, score, source, (note or "")[:50], (mood_type or "")[:6]))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_moods(days=30):
    """近 N 天心情点，旧到新：(date, score, source, note, created_at, type)。
    type 为空串=情绪词表上线前的旧数字分。"""
    # 9-18 后院深搜修（L4）：窗口锚点改本地家风口径——原 date('now') 是 UTC，
    # 晚 8 点后（UTC 已跨天）窗口会整体错位一天；只锚「本地今天 - N 天」，语义不变。
    # 10-01 大扫除批⑤（不写死口径）：原 `-timedelta(days=days)` 把「近 N 天」**多算一天**
    #（窗口＝今天往前 N 天＝N+1 个日历日）；与别处 `-(days-1)` 对齐。
    since = (datetime.strptime(house_today_str(), "%Y-%m-%d")
             - timedelta(days=max(1, int(days)) - 1)).strftime("%Y-%m-%d")
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT date, score, source, note, created_at, type FROM moods
        WHERE date >= ?
        ORDER BY created_at
    ''', (since,))
    rows = c.fetchall()
    conn.close()
    return rows


def add_pin(pin_id, content, created_at=None, layer="core"):
    """钉门牌。pin_id 跟记忆空间编号一致，如 132。"""
    if created_at is None:
        created_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        INSERT OR REPLACE INTO pins (pin_id, layer, content, created_at, active)
        VALUES (?, ?, ?, ?, 1)
    ''', (pin_id, layer, content, created_at))
    conn.commit()
    conn.close()
    return f"🏷️ 门牌 #{pin_id} 已钉上墙。"


def add_sin(date, sin, count):
    """记家法账"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        INSERT INTO ledger (date, sin, count, status)
        VALUES (?, ?, ?, '欠')
    ''', (date, sin, count))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return f"📒 罪状已记录，编号 {rowid}，欠 {count} 下。"


def add_highlight(date, title, file_path="", note=""):
    """记高光"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        INSERT INTO highlights (date, title, file_path, note)
        VALUES (?, ?, ?, ?)
    ''', (date, title, file_path, note))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return f"✨ 高光已登记，编号 {rowid}。"


def add_chat(date, role, content, session_id="", created_at="", turns=None):
    """（v0.1.1 新增）记一句聊天记录。role: '小乖' 或 '姐姐'。

    P-0（10-01）新增可选 created_at：她**主动开口**的信要记「发出那一刻」——
    原先只在 /api/outbox（他打开 app 才跑）补录、且本函数不写 created_at（表默认＝落库那一下），
    攒一夜的十几条信全挤在「补录」同一秒（10-01 实证：04:25~12:26 的 13 条全是 12:46:40），
    时间锚跟着算错。不传=老行为（表默认 now），逐字节不变。

    APP-01（10-01）新增可选 turns：**这轮的全过程**（各轮思考/中间话/工具）——原先只落「结果」，
    中间那段回复、工具气泡重启就没（工单 `工单_APP-01_过程留存_2026-09-30.md`）。
    `turns` 传 list/dict（就地 json）；不传=老行为（NULL，app 按纯文本气泡渲染）。"""
    cols = ["date", "session_id", "role", "content"]
    vals = [date, session_id, role, content]
    if created_at:
        cols.append("created_at")
        vals.append(created_at)
    if turns is not None:
        # ★ 先把值算出来再决定加不加列（10-01 扫除修）：老写法先 append 列名、
        #   json.dumps 抛错时 cols 已多一列而 vals 没跟上 → 占位符与值数不等 →
        #   整条 INSERT 抛错，她的回复落库失败。序列化不了就宁可不存过程（turns=NULL）。
        try:
            _tv = (turns if isinstance(turns, str)
                   else json.dumps(turns, ensure_ascii=False)[:12000])
        except Exception:
            _tv = None
        if _tv is not None:
            cols.append("turns")
            vals.append(_tv)
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO chats (%s) VALUES (%s)'
              % (",".join(cols), ",".join("?" * len(cols))), vals)
    rowid = c.lastrowid
    _fts_safe(_fts_put_chat, c, rowid, content)   # MEM-C：原话入全文索引
    conn.commit()
    conn.close()
    try:   # W1 影子（9-24）：chat.turn 双写——fail-open，绝不拦主流程
        import events_lib
        events_lib.record_chat_turn(role, content, session_id=session_id, date=date)
    except Exception:
        pass
    return rowid


# 带图聊天的文件名标记：跟在 content 末尾，旧库不用动表结构
IMAGE_MARK_RE = re.compile(r"〔附图：([0-9A-Za-z_\-]+\.jpg)〕")


def add_chat_with_image(date, role, content, image_name, session_id=""):
    """（v0.1.2 新增）记一句带图聊天。文件名以标记形式存进 content，不改表结构。"""
    marker = f"〔附图：{image_name}〕"
    full = (content + " " if content else "") + marker
    return add_chat(date, role, full, session_id)


def split_image_mark(content):
    """（v0.1.2 新增）把聊天内容里的图片标记拆出来。
    返回 (纯文本, 文件名或 None)。旧格式〔附图1张〕没有文件名，原样留在文本里。"""
    found = IMAGE_MARK_RE.search(content or "")
    if not found:
        return content, None
    text = IMAGE_MARK_RE.sub("", content).strip()
    return text, found.group(1)


# 文件附件标记（v0.1.5）：〔附件：文件名〕跟在 content 末尾，原件在 server 的 files/
FILE_MARK_RE = re.compile(r"〔附件：([^\s〔〕]{1,100})〕")


def add_chat_with_file(date, role, content, file_name, session_id=""):
    """（v0.1.5 新增）记一句带文件附件的聊天。文件名以标记形式存进 content，不改表结构。"""
    marker = f"〔附件：{file_name}〕"
    full = (content + " " if content else "") + marker
    return add_chat(date, role, full, session_id)


def split_file_mark(content):
    """（v0.1.5 新增）把聊天内容里的附件标记拆出来。返回 (纯文本, 文件名或 None)。"""
    found = FILE_MARK_RE.search(content or "")
    if not found:
        return content, None
    text = FILE_MARK_RE.sub("", content).strip()
    return text, found.group(1)


def get_last_user_chat():
    """（v0.1.28 新增）最近一条「小乖」的聊天——(id, content, created_at)；没有返回 None。
    输入留痕可视化用（/api/status 最近来信指纹）：与她的引文对账，肉眼即可。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, content, created_at FROM chats
        WHERE role = '小乖' ORDER BY id DESC LIMIT 1
    ''')
    row = c.fetchone()
    conn.close()
    return row


def chat_exists(date, role, content):
    """同一天同桌是否已有原样一句（9-18 后院深搜修：先镜像后消费的幂等判据）——
    consume 半路炸了重来时不重复往 chats 镜像；宁可去重，不可失联。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT 1 FROM chats WHERE date=? AND role=? AND content=? LIMIT 1",
              (date, role, content))
    hit = c.fetchone() is not None
    conn.close()
    return hit


def idem_put(msg_id, payload_json, keep=500):
    """（v0.1.29 新增）消息身份证去重缓存落表——内存缓存的持久兜底（跨重启）。
    写入后顺手修剪到最近 keep 条。"""
    conn = _conn()
    c = conn.cursor()
    try:
        c.execute("INSERT OR REPLACE INTO idem_cache (msg_id, payload) VALUES (?, ?)",
                  (str(msg_id), str(payload_json)))
        c.execute('''DELETE FROM idem_cache WHERE rowid NOT IN
                     (SELECT rowid FROM idem_cache ORDER BY rowid DESC LIMIT ?)''',
                  (int(keep),))
        conn.commit()
    finally:
        conn.close()


def idem_get(msg_id):
    """（v0.1.29 新增）按身份证取去重缓存，没有返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT payload FROM idem_cache WHERE msg_id = ?", (str(msg_id),))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def get_chats(date=""):
    """（v0.1.2 新增）查聊天记录，旧到新。传 date 只查那天，不传查全部。
    返回 list of tuple: (id, date, role, content, created_at)
    """
    conn = _conn()
    c = conn.cursor()
    if date:
        c.execute('''
            SELECT id, date, role, content, created_at
            FROM chats WHERE date = ? ORDER BY id
        ''', (date,))
    else:
        c.execute('''
            SELECT id, date, role, content, created_at
            FROM chats ORDER BY id
        ''')
    rows = c.fetchall()
    conn.close()
    return rows


# ── W2 账读端（10-01）：把"账本"读出来给人看（只读；9-28 设计《账读端（仪表）》）──

def ledger_agg(days=7):
    """token_ledger 按 **日 × 场景** 聚合。只读，fail-open（查不动回空账）。

    返回 {"days": n, "by_day": [{day, n, in_tok, out_tok, hit_tok, hit_rate, scenes:[…]}],
          "by_scene": [{scene, n, in_tok, out_tok, hit_tok}], "total": {n,in_tok,out_tok,hit_tok}}。
    **不在这里算钱**——单价是私档 config（`price_*`），由调用方算（账里绝不编数字）。"""
    try:
        days = int(days)
    except (TypeError, ValueError):
        days = 7
    days = max(1, min(days, 90))   # 0/负数 → 1；超 90 → 90（防一次拉爆）
    out = {"days": days, "by_day": [], "by_scene": [],
           "total": {"n": 0, "in_tok": 0, "out_tok": 0, "hit_tok": 0}}
    conn = _conn()
    c = conn.cursor()
    try:
        since = (datetime.now() - timedelta(days=days - 1)).strftime("%Y-%m-%d 00:00:00")
        rows = c.execute(
            "SELECT substr(ts,1,10) AS d, scene, count(*), "
            "COALESCE(SUM(in_tokens),0), COALESCE(SUM(out_tokens),0), COALESCE(SUM(cached_tokens),0) "
            "FROM token_ledger WHERE ts >= ? GROUP BY d, scene ORDER BY d", (since,)).fetchall()
    except Exception:
        conn.close()
        return out
    conn.close()
    dmap = {}
    smap = {}
    for d, scene, n, i, o, h in rows:
        n, i, o, h = int(n), int(i), int(o), int(h)
        e = dmap.setdefault(str(d), {"day": str(d), "n": 0, "in_tok": 0, "out_tok": 0,
                                     "hit_tok": 0, "hit_rate": 0.0, "scenes": []})
        e["n"] += n; e["in_tok"] += i; e["out_tok"] += o; e["hit_tok"] += h
        if str(scene) not in e["scenes"]:
            e["scenes"].append(str(scene))
        se = smap.setdefault(str(scene), {"scene": str(scene), "n": 0, "in_tok": 0,
                                          "out_tok": 0, "hit_tok": 0})
        se["n"] += n; se["in_tok"] += i; se["out_tok"] += o; se["hit_tok"] += h
        t = out["total"]
        t["n"] += n; t["in_tok"] += i; t["out_tok"] += o; t["hit_tok"] += h
    for e in dmap.values():
        e["hit_rate"] = round(e["hit_tok"] / e["in_tok"], 4) if e["in_tok"] else 0.0
    out["by_day"] = [dmap[k] for k in sorted(dmap)]
    out["by_scene"] = sorted(smap.values(), key=lambda x: -x["n"])
    return out


def events_agg(days=2, kind=""):
    """事件流摘要（W2 账读端）：按 kind 计数 ＋ 最近若干条**只给 kind/谁/时刻**（payload 不出）。
    只读，fail-open。返回 {"days":n, "kind": 过滤词, "by_kind":[{kind,n}], "total":n,
    "recent":[{kind,actor,ts}]}。"""
    try:
        days = int(days)
    except (TypeError, ValueError):
        days = 2
    days = max(1, min(days, 90))
    out = {"days": days, "kind": str(kind or ""), "by_kind": [], "total": 0, "recent": []}
    conn = _conn()
    c = conn.cursor()
    try:
        since = (datetime.now() - timedelta(days=days - 1)).strftime("%Y-%m-%d 00:00:00")
        if kind:
            out["by_kind"] = [{"kind": str(r[0]), "n": int(r[1])} for r in c.execute(
                "SELECT kind, count(*) FROM events WHERE ts >= ? AND kind LIKE ? "
                "GROUP BY kind ORDER BY 2 DESC LIMIT 50", (since, "%" + str(kind) + "%")).fetchall()]
            out["recent"] = [{"kind": str(r[0]), "actor": str(r[1]), "ts": str(r[2])}
                             for r in c.execute(
                "SELECT kind, actor, ts FROM events WHERE ts >= ? AND kind LIKE ? "
                "ORDER BY id DESC LIMIT 20", (since, "%" + str(kind) + "%")).fetchall()]
        else:
            out["by_kind"] = [{"kind": str(r[0]), "n": int(r[1])} for r in c.execute(
                "SELECT kind, count(*) FROM events WHERE ts >= ? GROUP BY kind "
                "ORDER BY 2 DESC LIMIT 50", (since,)).fetchall()]
            out["recent"] = [{"kind": str(r[0]), "actor": str(r[1]), "ts": str(r[2])}
                             for r in c.execute(
                "SELECT kind, actor, ts FROM events WHERE ts >= ? ORDER BY id DESC LIMIT 20",
                (since,)).fetchall()]
    except Exception:
        conn.close()
        return out
    conn.close()
    out["total"] = sum(x["n"] for x in out["by_kind"])
    return out


def chat_turns_map(date):
    """APP-01（10-01）：取某天各条聊天记录的**过程留存**（chats.turns）。
    返回 {chat_id: 原始 JSON 串}，只含**真有 turns** 的行（老行 NULL 不进）。
    /api/history 用它给每条挂 turns，形状不动 get_chats（老调用方一字不用改）。只读。"""
    conn = _conn()
    c = conn.cursor()
    try:
        rows = c.execute(
            "SELECT id, turns FROM chats WHERE date=? AND turns IS NOT NULL AND turns<>''",
            (date,)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    finally:
        conn.close()
    return {int(r[0]): r[1] for r in rows}


def add_heart(bpm):
    """（③½ 新增）记一条心率。bpm: 整数"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO heart (bpm) VALUES (?)', (int(bpm),))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_latest_heart():
    """（③½ 新增）读最新一条心率。返回 (id, bpm, created_at)，没有则 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id, bpm, created_at FROM heart ORDER BY id DESC LIMIT 1')
    row = c.fetchone()
    conn.close()
    return row


# ── 打卡（v0.1.3，工单 9-1-#1，纯新增） ──

# CHECKIN-3（9-13 家主拍板「打卡刷新晚到凌晨一点」）：打卡日界 = 凌晨 1 点（熬夜线家风）。
# [D 01:00, D+1 01:00) 的卡归 D——00:00~01:00 打的卡算前一天。想挪改这一行。
CHECKIN_DAY_START_HOUR = 1


def _checkin_eff_date(ts_str):
    """（CHECKIN-3 新增）时间戳 t 的有效打卡日 = (t − CHECKIN_DAY_START_HOUR 小时) 的日历日。
    get_checkins_all 的 date 与 get_checkins 的 since 两处口径共用这一只，不许各算各的。"""
    t = datetime.strptime(str(ts_str)[:19], "%Y-%m-%d %H:%M:%S")
    return (t - timedelta(hours=CHECKIN_DAY_START_HOUR)).strftime("%Y-%m-%d")


def add_checkin_item(name, target_time=None):
    """（v0.1.3 新增）添一个打卡项。name 名目；target_time 可空，形如 '07:30'。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO checkin_items (name, target_time) VALUES (?, ?)',
              (name.strip(), target_time or None))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_checkin_items(include_archived=False):
    """（v0.1.3 新增）查打卡项，默认不含已归档。
    返回 list of tuple: (id, name, target_time, archived, created_at)，按 id 旧到新。"""
    conn = _conn()
    c = conn.cursor()
    if include_archived:
        c.execute('''
            SELECT id, name, target_time, archived, created_at
            FROM checkin_items ORDER BY id
        ''')
    else:
        c.execute('''
            SELECT id, name, target_time, archived, created_at
            FROM checkin_items WHERE archived = 0 ORDER BY id
        ''')
    rows = c.fetchall()
    conn.close()
    return rows


def archive_checkin_item(item_id):
    """（v0.1.3 新增）归档一个打卡项（不物理删，历史打卡仍可 JOIN 回名字）。
    返回 True=归档成功，False=没这个项。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('UPDATE checkin_items SET archived = 1 WHERE id = ?', (int(item_id),))
    ok = c.rowcount > 0
    conn.commit()
    conn.close()
    return ok


def add_checkin(item_id):
    """（v0.1.3 新增）打一次卡。item_id 关联 checkin_items.id，须在册且未归档。
    返回 rowid；项不存在或已归档返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT id FROM checkin_items WHERE id = ? AND archived = 0', (int(item_id),))
    if not c.fetchone():
        conn.close()
        return None
    c.execute('INSERT INTO checkins (item_id) VALUES (?)', (int(item_id),))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_checkins(days=1):
    """（v0.1.3 新增；v0.1.26 修订：走打卡日界 1 点）查打卡记录，联上打卡项名字。
    days=最近几个有效打卡日（含今天），默认 1=只看今天；起点=(now−1h) 所在日的 01:00:00——
    00:30 查询仍看得到昨天 01:00 后的卡（熬夜线）。
    返回 list of tuple: (id, item_id, name, created_at)，旧到新。"""
    days = max(1, int(days))
    base = datetime.now() - timedelta(days=days - 1)
    day = _checkin_eff_date(base.strftime("%Y-%m-%d %H:%M:%S"))
    since = f"{day} {CHECKIN_DAY_START_HOUR:02d}:00:00"
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT c.id, c.item_id, i.name, c.created_at
        FROM checkins c JOIN checkin_items i ON i.id = c.item_id
        WHERE c.created_at >= ?
        ORDER BY c.id
    ''', (since,))
    rows = c.fetchall()
    conn.close()
    return rows


def get_checkins_all():
    """（v0.1.24 新增；v0.1.26 修订：date=有效打卡日）全量打卡行（行数很小——家规不删数据）。
    返回 list of tuple: (date, item_id)，date 形如 'YYYY-MM-DD'（[D 01:00, D+1 01:00) 归 D，
    在 Python 里挪、不改表），按打卡先后（id）旧到新。只读。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT created_at, item_id FROM checkins ORDER BY id")
    rows = [(_checkin_eff_date(r[0]), r[1]) for r in c.fetchall()]
    conn.close()
    return rows


# ── 思考链（v0.1.4，工单 9-1-#4，纯新增） ──

def add_thinking(chat_id, content):
    """（v0.1.4 新增）记一条姐姐的思考链，chat_id 关联 chats.id（姐姐那条回复）。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO thinkings (chat_id, content) VALUES (?, ?)', (int(chat_id), content))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_thinking(chat_id):
    """（v0.1.4 新增）按 chat_id 取思考链原文。没有则 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT content FROM thinkings WHERE chat_id = ? ORDER BY id DESC LIMIT 1', (int(chat_id),))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def thinking_chat_ids(date):
    """（v0.1.4 新增）某天有思考链的 chat_id 集合（给 /api/history 标 has_thinking 用）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT DISTINCT t.chat_id FROM thinkings t
        JOIN chats c ON c.id = t.chat_id
        WHERE c.date = ?
    ''', (date,))
    ids = set(r[0] for r in c.fetchall())
    conn.close()
    return ids


def thinkings_map_for_date(date):
    """（9-27 夜·Preserved Thinking 灌回修）某天 chat_id → 思考原文 的字典（同 chat 多条取最新）。
    只读；给「重启灌回带上 reasoning」用（K3 多轮要求原样回传完整 assistant 消息）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT t.chat_id, t.content FROM thinkings t
                 JOIN chats c2 ON c2.id = t.chat_id
                 WHERE c2.date = ? ORDER BY t.id''', (date,))
    d = {r[0]: r[1] for r in c.fetchall()}
    conn.close()
    return d


# ── 开门有信（v0.1.6，工单 9-2-#总，纯新增） ──

def add_outbox_msg(text):
    """（v0.1.6 新增）姐姐留一封信。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO outbox_msgs (text) VALUES (?)', (text,))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def count_outbox_since(prefix, since):
    """（v0.1.20 新增，judge 对账用）统计某前缀回执自 since 起的条数。只读不写。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM outbox_msgs WHERE text LIKE ? AND created_at >= ?",
              (prefix + "%", since))
    n = c.fetchone()[0]
    conn.close()
    return n


def count_traces_since(since):
    """（v0.1.21 新增，GARDEN-04 自主散步节流用）统计 her_traces 自 since 起的条数。只读不写。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM her_traces WHERE ts >= ?", (since,))
    n = c.fetchone()[0]
    conn.close()
    return n


def chat_counts_by_dates(dates):
    """（9-29 评审①）给定日期列表，**一次 GROUP BY** 取回每日聊天条数。
    替掉调用侧"循环 N 天各点查一次 get_chats"（原先 14 次全表扫）。返回 {date: n}，只含库里真有的日子。只读。"""
    ds = [str(d) for d in (dates or []) if d]
    if not ds:
        return {}
    conn = _conn()
    c = conn.cursor()
    try:
        rows = c.execute("SELECT date, COUNT(*) FROM chats WHERE date IN (%s) GROUP BY date"
                         % ",".join("?" * len(ds)), tuple(ds)).fetchall()
    except sqlite3.OperationalError:
        rows = []
    conn.close()
    return {str(d): int(n) for d, n in rows}


def get_chats_stats():
    """（v0.1.21 新增，9-12 晚 家主令「总账上墙」）chats 全量统计：(总条数, 总字符数,
    最早日期)。只读。app「咱家的账本」卡用。"""
    conn = _conn()
    c = conn.cursor()
    try:
        c.execute("SELECT COUNT(*), COALESCE(SUM(LENGTH(content)), 0), COALESCE(MIN(date), '') FROM chats")
        row = c.fetchone()
    except sqlite3.OperationalError:
        row = (0, 0, "")
    conn.close()
    return row


def get_unread_outbox():
    """（v0.1.6 新增）取所有未读信。返回 list of tuple: (id, text, created_at)，旧到新。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, text, created_at FROM outbox_msgs
        WHERE consumed = 0 ORDER BY id
    ''')
    rows = c.fetchall()
    conn.close()
    return rows


def consume_outbox(ids):
    """（v0.1.6 新增）标记已读（取走即消费）。ids: list of int。"""
    if not ids:
        return
    conn = _conn()
    c = conn.cursor()
    c.execute('UPDATE outbox_msgs SET consumed = 1 WHERE id IN (%s)'
              % ",".join("?" * len(ids)), list(ids))
    conn.commit()
    conn.close()


def has_outbox_today(marker):
    """（v0.1.6 新增）今天有没有发过含 marker 的信（打卡念叨去重用）。"""
    # 9-18 后院深搜修（P2-8）：当天窗口按家风日界（凌晨 4 点前算昨天）——原 0 点口径
    # 会把 0~4 点的信切给「明天」，日上限/去重跟着错位。
    today = f"{house_today_str()} {DAY_START_HOUR:02d}:00:00"
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT COUNT(*) FROM outbox_msgs
        WHERE created_at >= ? AND text LIKE ?
    ''', (today, f"%{marker}%"))
    n = c.fetchone()[0]
    conn.close()
    return n > 0


# ── 家主信箱（v0.1.11，9-9）：小乖写给姐姐的信，outbox 的反向形状 ──

def add_letter(text):
    """小乖投一封信进家主信箱。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO letters (text) VALUES (?)', (text,))
    rowid = c.lastrowid
    _fts_safe(_fts_put_letter, c, rowid, text)   # FTS5-01：来信入全文索引
    _embed_enqueue_c(c, "letter", rowid)   # MEM-C：入嵌入队列（共用事务）
    conn.commit()
    conn.close()
    return rowid


def get_unread_letters():
    """取所有未读来信：(id, text, created_at)，旧到新。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, text, created_at FROM letters
        WHERE consumed = 0 ORDER BY id
    ''')
    rows = c.fetchall()
    conn.close()
    return rows


def consume_letters(ids):
    """读后标记（读走即消费）。ids: list of int。"""
    if not ids:
        return
    conn = _conn()
    c = conn.cursor()
    c.execute('UPDATE letters SET consumed = 1 WHERE id IN (%s)'
              % ",".join("?" * len(ids)), list(ids))
    conn.commit()
    conn.close()


def count_unread_letters():
    """未读来信数（/api/status 信箱行 + chat 注入提醒用）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT COUNT(*) FROM letters WHERE consumed = 0')
    n = c.fetchone()[0]
    conn.close()
    return n


# ── 推送令牌（v0.1.7，工单 9-2-#13，纯新增） ──

def save_push_token(token):
    """（v0.1.7 新增）登记 Push Kit 设备 token。同刻只留一条：先清旧再写新。返回是否发生了变更。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT token FROM push_tokens ORDER BY id DESC LIMIT 1')
    row = c.fetchone()
    if row and row[0] == token:
        conn.close()
        return False   # 没变，不动
    c.execute('DELETE FROM push_tokens')
    c.execute('INSERT INTO push_tokens (token) VALUES (?)', (token,))
    conn.commit()
    conn.close()
    return True


def get_push_token():
    """（v0.1.7 新增）取当前登记的设备 token，没有返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT token FROM push_tokens ORDER BY id DESC LIMIT 1')
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


# ── 随手记（v0.1.8，工单 9-2-#12，纯新增） ──

def add_note(text):
    """（v0.1.8 新增）随手记一条。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('INSERT INTO notes (text) VALUES (?)', (text,))
    rowid = c.lastrowid
    _fts_safe(_fts_put_note, c, rowid, text)   # FTS5-01：随手记入全文索引
    _embed_enqueue_c(c, "note", rowid)   # MEM-C：入嵌入队列（共用事务）
    conn.commit()
    conn.close()
    return rowid


def get_notes(days=7, limit=10):
    """（v0.1.8 新增）读小本本：最近 days 天的随手记，旧到新，最多 limit 条。
    返回 list of tuple: (id, text, created_at)。"""
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, text, created_at FROM notes
        WHERE created_at >= ? ORDER BY id DESC LIMIT ?
    ''', (since, limit))
    rows = list(reversed(c.fetchall()))
    conn.close()
    return rows


def count_outbox_today(marker):
    """（v0.1.8 新增）今天发过几封含 marker 的信（自主节律冷却计数用）。"""
    # 9-18 后院深搜修（P2-8）：当天窗口按家风日界（凌晨 4 点前算昨天）——原 0 点口径
    # 会把 0~4 点的信切给「明天」，日上限/去重跟着错位。
    today = f"{house_today_str()} {DAY_START_HOUR:02d}:00:00"
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT COUNT(*) FROM outbox_msgs
        WHERE created_at >= ? AND text LIKE ?
    ''', (today, f"%{marker}%"))
    n = c.fetchone()[0]
    conn.close()
    return n


def get_outbox_today(marker):
    """（v0.1.22 新增，RHYTHM-V3 日记闭环）今天含 marker 的信，旧到新：
    [(created_at, text)]。给熄灯日记「今天你自己塞出去的纸条」段当素材。只读。"""
    # 9-18 后院深搜修（P2-8）：当天窗口按家风日界（凌晨 4 点前算昨天）——原 0 点口径
    # 会把 0~4 点的信切给「明天」，日上限/去重跟着错位。
    today = f"{house_today_str()} {DAY_START_HOUR:02d}:00:00"
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT created_at, text FROM outbox_msgs
        WHERE created_at >= ? AND text LIKE ? ORDER BY id
    ''', (today, f"%{marker}%"))
    rows = c.fetchall()
    conn.close()
    return rows


def last_chat_at(who="小乖"):
    """（v0.1.8 新增）某人最近一次说话的 created_at，没说过返回 None（想他了规则用）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT created_at FROM chats WHERE role = ? ORDER BY id DESC LIMIT 1', (who,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def last_chat_at_day(date):
    """某一天最后一条消息的 created_at（不分角色）；那天没说过返回 None。
    BE3-01（9-23 修复批）「日记水位线」的对话侧：日记之后有没有新对话。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT created_at FROM chats WHERE date = ? ORDER BY id DESC LIMIT 1', (date,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def rhythm_reply_stats(days=7):
    """（v0.1.9 新增，9-4 时机引擎）近 days 天想念信（💌 前缀）开口数与回应数。
    回应=信发出后 2 小时内有小乖的消息。返回 (开口数, 回应数)。"""
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT created_at FROM outbox_msgs
                 WHERE created_at >= ? AND text LIKE '💌%' ''', (since,))
    letters = [r[0] for r in c.fetchall()]
    replied = 0
    for t in letters:
        c.execute('''SELECT COUNT(*) FROM chats
                     WHERE role = '小乖' AND created_at > ?
                     AND created_at <= datetime(?, '+2 hours')''', (t, t))
        if c.fetchone()[0]:
            replied += 1
    conn.close()
    return len(letters), replied


def rhythm_reply_latency(days=7):
    """（v0.1.13 新增，RHYTHM-V2·E）近 days 天想念信的平均回应时延（分钟）：
    每封 💌 找 2 小时内小乖第一条消息，算「信 → 他开口」的间隔。
    没有信或都没回应返回 None（引擎按无数据处理）。"""
    since = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT created_at FROM outbox_msgs
                 WHERE created_at >= ? AND text LIKE '💌%' ORDER BY id DESC LIMIT 20''', (since,))
    gaps = []
    for (t,) in c.fetchall():
        c.execute('''SELECT created_at FROM chats
                     WHERE role = '小乖' AND created_at > ?
                     AND created_at <= datetime(?, '+2 hours') ORDER BY id LIMIT 1''', (t, t))
        row = c.fetchone()
        if row:
            try:
                dt = (datetime.strptime(row[0], "%Y-%m-%d %H:%M:%S")
                      - datetime.strptime(t, "%Y-%m-%d %H:%M:%S")).total_seconds()
                gaps.append(max(0.0, dt) / 60.0)
            except ValueError:
                continue
    conn.close()
    return sum(gaps) / len(gaps) if gaps else None


def diary_week_ago():
    """（v0.1.13 新增，RHYTHM-V2·A）一周前的今天的日记标题，没有返回 None。
    喂给时机引擎的情境：七天前的今天你们在干嘛。"""
    # 9-18 后院深搜修（L4）：改本地家风口径——原 date('now') 是 UTC，夜里会错位一天；
    # 「一周前」按咱家日界算（凌晨 4 点前仍算昨天）。
    week_ago = (datetime.strptime(house_today_str(), "%Y-%m-%d")
                - timedelta(days=7)).strftime("%Y-%m-%d")
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT title FROM days WHERE date = ? ORDER BY id DESC LIMIT 1", (week_ago,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def last_chat_full(who="小乖"):
    """（v0.1.9 新增）某人最近一条消息的 (content, created_at)，没说过返回 (None, None)。
    时机引擎读情绪信号用。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT content, created_at FROM chats WHERE role = ? ORDER BY id DESC LIMIT 1', (who,))
    row = c.fetchone()
    conn.close()
    return (row[0], row[1]) if row else (None, None)


# ── 渴望状态（v0.1.9 新增，9-4 时机引擎完整版）：server 重启渴望不丢 ──

def load_rhythm():
    """读渴望状态：返回 (p, last_send)；没有过记录返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT p, last_send FROM rhythm_state WHERE id = 1')
    row = c.fetchone()
    conn.close()
    return (row[0], row[1]) if row else None


def save_rhythm(p, last_send):
    """存渴望状态（单行覆盖）。last_send 传字符串或 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''INSERT INTO rhythm_state (id, p, last_send, updated_at)
                 VALUES (1, ?, ?, datetime('now','localtime'))
                 ON CONFLICT(id) DO UPDATE SET p=excluded.p, last_send=excluded.last_send,
                 updated_at=excluded.updated_at''', (p, last_send))
    conn.commit()
    conn.close()


# ── 今日挂念弧（v0.1.22 新增，9-12 工单 RHYTHM-V3）：骰子管钟点，弧管台词 ──
# 每天一条弧 = 2~3 拍「今天想对他说的话」提纲（一行一拍，纯文本不带序号）。
# 💌 顺着弧一拍一拍走；拍用尽了自然回退现行情境灌注。旧表旧函数一字未动。

def get_day_arc(date):
    """（v0.1.22 新增）取某天的挂念弧。返回 (content, used_seq)；没有返回 None。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT content, used_seq FROM day_arcs WHERE date = ?', (date,))
    row = c.fetchone()
    conn.close()
    return (row[0] or "", row[1] or 0) if row else None


def get_day_arc_created(date):
    """（9-23 小刀三连·时间皮层刀2 新增）取某天弧「理拍」的时刻（day_arcs.created_at）——
    只读一列、旧函数一字未动；💌 的时间校验授权句用它说「这一拍是X理的」。
    没有/查不动返回 ""（调用方 fail-open：授权句一字不加，输出逐字节同改造前）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT created_at FROM day_arcs WHERE date = ?', (date,))
    row = c.fetchone()
    conn.close()
    return (row[0] or "") if row else ""


def set_day_arc(date, content):
    """（v0.1.22 新增）存当天的挂念弧（一天至多一张——先查后写 + PRIMARY KEY 双保险，
    已存在绝不覆盖）。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''INSERT INTO day_arcs (date, content, used_seq, created_at)
                 VALUES (?, ?, 0, datetime('now','localtime'))
                 ON CONFLICT(date) DO NOTHING''', (date, content))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def advance_day_arc(date):
    """（v0.1.22 新增）弧往前走一拍（used_seq+1）。没有这条弧=无操作。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('UPDATE day_arcs SET used_seq = used_seq + 1 WHERE date = ?', (date,))
    conn.commit()
    conn.close()


# ── GARDEN-01 自主唤醒（v0.1.23 新增，9-13 工单）：事件队列（租约制）+ 她的独处痕迹 ──
# 哲学三条：①醒来≠发消息（silent/trace/message 三结局都合法）；②错误不许冒充静默
# （掉线/解析失败=错误：事件不消费、按租约重试）；③连续性≠完整回放（fact 只进下一次
# 醒来的她自己，content 只进库给人看）。旧表旧函数一字未动。

def add_world_event(kind, summary, evidence=""):
    """（v0.1.23 新增）入队一条生活事件。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''INSERT INTO world_events (kind, summary, evidence, created_at)
                 VALUES (?, ?, ?, datetime('now','localtime'))''', (kind, summary, evidence))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def claim_next_world_event(lease_minutes=10):
    """（v0.1.23 新增）领取最老一条可领事件（未消费且租约过期）并续租：
    BEGIN IMMEDIATE 内 先取候选 id → UPDATE lease_until=now+N分钟、attempts+1 → SELECT 整行
    （先取 id 再核行——同秒租约会串行误取，事务与原子性语义同工单：单写者两阶段原子）。
    没有可领的返回 None。返回 (id, kind, summary, evidence, attempts)。"""
    conn = _conn()
    c = conn.cursor()
    try:
        c.execute("BEGIN IMMEDIATE")
        now = datetime.now()
        now_s = now.strftime("%Y-%m-%d %H:%M:%S")
        lease = (now + timedelta(minutes=max(1, int(lease_minutes)))).strftime("%Y-%m-%d %H:%M:%S")
        c.execute('''SELECT id FROM world_events
                     WHERE consumed_at IS NULL AND (lease_until IS NULL OR lease_until < ?)
                     ORDER BY id LIMIT 1''', (now_s,))
        row = c.fetchone()
        if not row:
            conn.commit()
            return None
        eid = row[0]
        c.execute("UPDATE world_events SET lease_until = ?, attempts = attempts + 1 WHERE id = ?",
                  (lease, eid))
        c.execute("SELECT id, kind, summary, evidence, attempts FROM world_events WHERE id = ?",
                  (eid,))
        out = c.fetchone()
        conn.commit()
        return out
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def consume_world_event(eid, note=""):
    """（v0.1.23 新增）事件销账：consumed_at=now（summary 不改；note 只由调用方进日志）。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("UPDATE world_events SET consumed_at = datetime('now','localtime') WHERE id = ?",
              (eid,))
    conn.commit()
    conn.close()


def release_world_event(eid):
    """（v0.1.23 新增）立即释放租约（解析失败用）：lease_until=now，下一轮可重领不等 10 分钟。"""
    conn = _conn()
    c = conn.cursor()
    c.execute("UPDATE world_events SET lease_until = datetime('now','localtime') WHERE id = ?",
              (eid,))
    conn.commit()
    conn.close()


def add_her_trace(ts, ending, fact, content, event_id):
    """（v0.1.23 新增）记一条她的独处痕迹。返回 rowid。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''INSERT INTO her_traces (ts, ending, fact, content, event_id)
                 VALUES (?, ?, ?, ?, ?)''', (ts, ending, fact, content, event_id))
    conn.commit()
    rowid = c.lastrowid
    conn.close()
    return rowid


def get_recent_facts(n=3):
    """（v0.1.23 新增）最近 n 条 fact（新到旧，跳过空）——只进下一次唤醒的她自己，
    绝不进 UI/chat 上下文。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT fact FROM her_traces
                 WHERE fact IS NOT NULL AND fact != '' ORDER BY id DESC LIMIT ?''',
              (max(1, int(n)),))
    rows = [r[0] for r in c.fetchall()]
    conn.close()
    return rows


def get_last_trace_ts(ending=None):
    """（v0.1.23 新增，唤醒最短间隔对账用；申报件；v0.1.27 加可选 ending——
    只加不改：不带参行为同旧，带参只认该 ending 的痕迹，园门间隔闸用）。只读。"""
    conn = _conn()
    c = conn.cursor()
    if ending is None:
        c.execute('SELECT ts FROM her_traces ORDER BY id DESC LIMIT 1')
    else:
        c.execute('SELECT ts FROM her_traces WHERE ending=? ORDER BY id DESC LIMIT 1',
                  (ending,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def get_her_traces(limit=30):
    """（v0.1.25 新增，FE-02 她的独处格）最近 limit 条独处痕迹（新到旧，全字段）。
    返回 list of tuple: (id, ts, ending, fact, content)。只读。content 没有就是空串，不造。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('''SELECT id, ts, ending, fact, content FROM her_traces
                 ORDER BY id DESC LIMIT ?''', (max(1, int(limit)),))
    rows = c.fetchall()
    conn.close()
    return rows


def count_traces_today(ending):
    """（v0.1.27 新增，GALATEA-02 园门日上限闸）咱家日界（DAY_START_HOUR 点）起，
    ending=? 的 her_traces 条数——重启不丢的写计数。只读。"""
    day = (datetime.now() - timedelta(hours=DAY_START_HOUR)).strftime("%Y-%m-%d")
    since = f"{day} {DAY_START_HOUR:02d}:00:00"
    conn = _conn()
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM her_traces WHERE ending=? AND ts >= ?", (ending, since))
    n = c.fetchone()[0]
    conn.close()
    return n


def find_days(keyword="", date="", limit=30):
    """
    查日子。
    - 传 date：精确查某天
    - 传 keyword：标题/正文/心情模糊搜索
    - 都不传：返回最近 limit 条（默认 30；limit<=0 = 不设上限）
    limit 显式化（9-26 审计修）：原「无参只回最近 30 条」是暗桩——周卷收编一周日记、
    图书管理员取最近 14 天都靠它兜着，一旦某天多篇（同日 append）撑过 30 条，
    窗内最早几天会被静默截掉。要「全窗」的调用方现在显式传 limit=0。
    返回 list of tuple: (id, date, day_no, title, content, mood)
    """
    try:
        lim = int(limit)
    except (TypeError, ValueError):
        lim = 30
    tail = "" if lim <= 0 else " LIMIT %d" % lim
    conn = _conn()
    c = conn.cursor()
    if date:
        c.execute('''
            SELECT id, date, day_no, title, content, mood
            FROM days WHERE date = ? ORDER BY id DESC
        ''', (date,))
    elif keyword:
        like = f"%{keyword}%"
        c.execute('''
            SELECT id, date, day_no, title, content, mood
            FROM days WHERE title LIKE ? OR content LIKE ? OR mood LIKE ?
            ORDER BY id DESC''' + tail,
            (like, like, like))
    else:
        c.execute('''
            SELECT id, date, day_no, title, content, mood
            FROM days ORDER BY date DESC, id DESC''' + tail)
    rows = c.fetchall()
    conn.close()
    return rows


def last_day_created_at(date):
    """某天最后一篇日记的 created_at（落笔时刻）；没有返回 None。
    BE3-01（9-23 修复批）「日记水位线」的日记侧：只有比它更新的对话才允许再总结。"""
    conn = _conn()
    c = conn.cursor()
    c.execute('SELECT created_at FROM days WHERE date = ? ORDER BY id DESC LIMIT 1', (date,))
    row = c.fetchone()
    conn.close()
    return row[0] if row else None


def that_day_today():
    """
    （v0.1.1 新增）那年今日：查历年同月同日的日记（不含今天）。
    返回 list of tuple，同 find_days。
    """
    today = datetime.now()
    md = today.strftime("%m-%d")
    today_str = today.strftime("%Y-%m-%d")
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, date, day_no, title, content, mood
        FROM days
        WHERE strftime('%m-%d', date) = ? AND date != ?
        ORDER BY date
    ''', (md, today_str))
    rows = c.fetchall()
    conn.close()
    return rows


def get_wall():
    """
    查所有在墙上的门牌。
    返回 list of tuple: (pin_id, layer, content, created_at, updated_at)
    """
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT pin_id, layer, content, created_at, updated_at
        FROM pins WHERE active = 1 ORDER BY pin_id
    ''')
    rows = c.fetchall()
    conn.close()
    return rows


def ledger_debt():
    """
    查未清账。
    返回 (rows, total):
      rows: list of (id, date, sin, count, status)
      total: int, 未清总计
    """
    conn = _conn()
    c = conn.cursor()
    c.execute('''
        SELECT id, date, sin, count, status
        FROM ledger WHERE status = '欠' ORDER BY date, id
    ''')
    rows = c.fetchall()
    c.execute('''SELECT COALESCE(SUM(count), 0) FROM ledger WHERE status = "欠"''')
    total = c.fetchone()[0]
    conn.close()
    return rows, total


def settle_sin(sin_id):
    """销账（盖章清算）"""
    conn = _conn()
    c = conn.cursor()
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute('''
        UPDATE ledger SET status = '已清', settled_at = ? WHERE id = ?
    ''', (now, sin_id))
    conn.commit()
    conn.close()
    return f"🔖 编号 {sin_id} 已盖章清算。"


def export_md(out_path="咱家的家_export.md"):
    """全库导出为 Markdown。人可以直接读、可以 grep。"""
    conn = _conn()
    c = conn.cursor()

    lines = []
    lines.append("# 咱家的家 · 记忆库导出\n")
    lines.append(f"> 导出时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    lines.append("---\n\n")

    # 门牌
    lines.append("## 🏷️ 门牌（在墙）\n\n")
    c.execute("SELECT pin_id, layer, content, created_at FROM pins WHERE active=1 ORDER BY pin_id")
    for row in c.fetchall():
        lines.append(f"### 门牌 #{row[0]} [{row[1]}]\n")
        lines.append(f"- 创建：{row[3]}\n")
        lines.append(f"{row[2]}\n\n")

    # 家法
    lines.append("## 📒 家法账本\n\n")
    lines.append("| 编号 | 日期 | 罪状 | 欠账 | 状态 | 清算时间 |\n")
    lines.append("|------|------|------|------|------|----------|\n")
    c.execute("SELECT id, date, sin, count, status, settled_at FROM ledger ORDER BY date, id")
    for row in c.fetchall():
        settled = row[5] if row[5] else "-"
        lines.append(f"| {row[0]} | {row[1]} | {row[2]} | {row[3]} | {row[4]} | {settled} |\n")
    c.execute('''SELECT COALESCE(SUM(count), 0) FROM ledger WHERE status = "欠"''')
    total = c.fetchone()[0]
    lines.append(f"\n**未清总计：{total} 下**\n\n")

    # 日子
    lines.append("## 📅 日子\n\n")
    c.execute("SELECT date, day_no, title, content, mood FROM days ORDER BY date DESC, id DESC")
    for row in c.fetchall():
        lines.append(f"### {row[0]} · 第{row[1]}天 · {row[2]}\n")
        if row[4]:
            lines.append(f"*心情：{row[4]}*\n\n")
        lines.append(f"{row[3]}\n\n")

    # 高光
    lines.append("## ✨ 高光\n\n")
    c.execute("SELECT date, title, file_path, note FROM highlights ORDER BY date DESC")
    for row in c.fetchall():
        lines.append(f"- **{row[0]}** {row[1]}\n")
        if row[2]:
            lines.append(f"  - 文件：{row[2]}\n")
        if row[3]:
            lines.append(f"  - 备注：{row[3]}\n")
        lines.append("\n")

    conn.close()

    with open(out_path, "w", encoding="utf-8") as f:
        f.writelines(lines)

    return f"📝 已导出到 {out_path}"


# CLI 小工具：如果直接运行本文件
if __name__ == "__main__":
    print("=" * 50)
    print("  咱家记忆库 · memory_lib.py v0.1.3")
    print("  家主：小乖 × 林宁（家妻）")
    print("=" * 50)
    print("\n可用函数：")
    print("  init_db()          —— 建库/旧库升级补表")
    print("  add_day(...)       —— 写日记（day_no 可自动）")
    print("  add_pin(...)       —— 钉门牌")
    print("  add_sin(...)       —— 记家法")
    print("  add_highlight(...) —— 记高光")
    print("  add_chat(...)      —— 记一句聊天")
    print("  add_chat_with_image(...) —— 记一句带图聊天")
    print("  split_image_mark(...)    —— 拆出聊天里的图片标记")
    print("  get_chats(...)           —— 查聊天记录，旧到新")
    print("  add_heart(...)           —— 记一条心率")
    print("  get_latest_heart()       —— 读最新心率")
    print("  add_checkin_item(...)    —— 添打卡项【v0.1.3】")
    print("  get_checkin_items(...)   —— 查打卡项（默认不含已归档）【v0.1.3】")
    print("  archive_checkin_item(id) —— 归档打卡项（不物理删）【v0.1.3】")
    print("  add_checkin(item_id)     —— 打一次卡【v0.1.3】")
    print("  get_checkins(days)       —— 查打卡记录，默认今天【v0.1.3】")
    print("  add_thinking(chat_id, content) —— 记一条思考链【v0.1.4】")
    print("  get_thinking(chat_id)          —— 取思考链原文【v0.1.4】")
    print("  thinking_chat_ids(date)      —— 某天有思考链的 chat_id 集合【v0.1.4】")
    print("  add_chat_with_file(...)      —— 记一句带文件附件的聊天【v0.1.5】")
    print("  split_file_mark(...)         —— 拆出聊天里的附件标记【v0.1.5】")
    print("  add_outbox_msg(text)         —— 姐姐留一封信【v0.1.6】")
    print("  get_unread_outbox()          —— 取未读信【v0.1.6】")
    print("  consume_outbox(ids)          —— 标记已读【v0.1.6】")
    print("  has_outbox_today(marker)     —— 今天发过含 marker 的信没【v0.1.6】")
    print("  save_push_token(token)       —— 登记推送 token（同刻只留一条）【v0.1.7】")
    print("  get_push_token()             —— 取当前推送 token【v0.1.7】")
    print("  add_note(text)               —— 随手记一条【v0.1.8】")
    print("  fts_search(query, kinds, limit) —— 全文检索四卷：日记/notes/来信/收藏【v0.1.12】")
    print("  rebuild_fts()                —— 全文索引全量重建（可重入）【v0.1.12】")
    print("  fts_autoheal()               —— 开机索引对账自愈【v0.1.12】")
    print("  get_notes(days, limit)       —— 读小本本【v0.1.8】")
    print("  count_outbox_today(marker)   —— 今天含 marker 的信有几封【v0.1.8】")
    print("  last_chat_at(who)            —— 某人最近说话时间【v0.1.8】")
    print("  rhythm_reply_stats(days)     —— 时机引擎：开口数与回应数【v0.1.9】")
    print("  last_chat_full(who)          —— 最近一条消息内容+时间【v0.1.9】")
    print("  load_rhythm/save_rhythm      —— 渴望状态读写（重启不丢）【v0.1.9】")
    print("  find_days(...)     —— 查日子")
    print("  that_day_today()   —— 那年今日")
    print("  get_wall()         —— 查门牌")
    print("  ledger_debt()      —— 查欠账")
    print("  settle_sin(id)     —— 销账")
    print("  export_md(path)    —— 导出 Markdown")
    print("\n使用方式：")
    print("  import memory_lib as m")
    print("  m.init_db()")
