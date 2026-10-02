// ── 接口与词表正典（9-30 第 1 批拆分·纯类型零运行时）───────────────────────────
// 从 pages/Index.ets 原样搬出：全部 interface ＋ 情绪/河/夜设词表常量。
// 搬出来的理由：这层是「数据长什么样」，改它不该碰 UI 文件；别的页面/组件也能 import。
// 行为逐字未改（搬家而已）。

// 情绪词表（9-9 心情曲线 v2；9-12 MOOD-V1 九并六）：与 server MOOD_TYPES 常量同一份正典
//（改词表=两处都改）。顺序即展示顺序，色值即情绪河墨色。
export interface MoodTypeItem {
  name: string;
  color: string;
}
export const MOOD_TYPES: MoodTypeItem[] = [
  { name: '欲望', color: '#d95d63' },
  { name: '想你', color: '#e08cae' },
  { name: '开心', color: '#e2a93b' },
  { name: '委屈', color: '#7a9bd4' },
  { name: '踏实', color: '#7fa66a' },
  { name: '累', color: '#8d8478' }
];
export const MOOD_LEGACY_COLOR: string = '#c9beb0';   // 词表上线前的旧数字分（type 空串）画中性灰
// MOOD-V1（9-12）词表九并六：心疼/平静/骄傲 退出正典——旧数据原样留库，
// 展示层先过这张映射再取色取名（只用于展示，绝不回写）。
export const LEGACY_MOOD_MAP: Record<string, string> = {
  '心疼': '委屈',
  '平静': '踏实',
  '骄傲': '开心'
};

export interface LocInfo {
  lat: number;
  lon: number;
  place?: string;   // 逆地理编码出的文字地址，可没有
}

export interface ChatBody {
  message: string;
  msg_id?: string;    // 9-12 消息身份证：重试/补发复用同一张，server 凭它去重（回包丢了也不双发）
  image?: string;
  loc?: LocInfo;
  place?: string;
  file?: FileBody;    // 9-1-#8 刀2：文本附件
  stream?: boolean;   // 9-4 自由发挥包：SSE 流式（思考+正文打字机）
}

// 9-4 流式 SSE 事件（server 契约：thinking/reply/status/tool/round/done/error）
export interface StreamEvent {
  type?: string;
  delta?: string;
  text?: string;
  name?: string;      // 9-12 tool 事件：正在调用的图书证名
  args?: string;      // 9-12 tool 事件：参数摘要（server 已截 30 字）
  round?: number;     // 9-12 round 事件：工具循环轮次边界（>0 时封上一轮步骤卡）
  think_ms?: number;
  tools?: ToolUseInfo[];
  chat_id?: number;
  dedup?: boolean;    // 9-12 去重命中：server 返回 JSON（非 SSE）原样还上次那句
  reply?: string;     // 9-12 dedup JSON 的正文（server 字段名与流式事件不同）
}

// 文本附件：名字+全文（≤32KB）
export interface FileBody {
  name: string;
  content: string;
}

// CAL-01（9-13）日程上报形状：只带标题+开始时间（家训：只放必要信息）
export interface ScheduleItem {
  time: string;    // 'HH:MM'
  title: string;   // ≤20 字
}

export interface ScheduleBody {
  date: string;    // 'YYYY-MM-DD'
  items: ScheduleItem[];
}

export interface ChatReply {
  reply?: string;
  think_ms?: number;
  tools?: ToolUseInfo[];
  reasoning?: string;   // 二期d：思考链原文（思考模式开着且这轮有的话）
}

export interface ToolUseInfo {
  name: string;
  args: string;
  ms: number;
  rounds: number;
}

// APP-01（10-01）：过程留存——这一轮她"做过什么"的全过程（各轮思考/中间话/工具）。
// 老消息没有这栏（undefined/null）→ app 按纯文本气泡渲染，向后兼容。
export interface TurnTool {
  name: string;
  args?: string;
  ms?: number;
  brief?: string;
}

export interface TurnInfo {
  r: number;              // 第几轮（1 起）
  think?: string;         // 这一轮的思考
  say?: string;           // 这一轮的正文（多轮里的"中间那段回复"）
  tools?: TurnTool[];     // 这一轮调过的图书证
  final?: boolean;        // 收尾轮标记
}

export interface HistoryMsg {
  who: string;
  text: string;
  image: string | null;
  time: string;
  id?: number;              // 二期d：chats 行号，取思考链要用
  has_thinking?: boolean;   // 二期d：这条姐姐回复有没有思考链
  file?: string | null;     // 9-1-#8：附件文件名（〔附件：…〕解析出来的）
  turns?: TurnInfo[] | null;   // APP-01：过程留存（老消息/无过程＝null/缺）
}

export interface HistoryResp {
  messages: HistoryMsg[];
  has_more?: boolean | null;   // 9-23 V-1：更早还有没有（旧 server 不带此键=不分页）
}

export interface StatusLoc {
  lat: number;
  lon: number;
  time: string;
  place?: string;
}

export interface StatusResp {
  now?: string;
  weather?: string;
  loc?: StatusLoc;
  chats_today?: number;
  asleep?: boolean;
  server_up_since?: string | null;    // 9-4 自由发挥包：server 开工时间 HH:MM
  server_up_min?: number | null;      // 9-4 自由发挥包：server 跑了多少分钟
  favorites_count?: number;           // 9-4 自由发挥包：收藏夹照片数
  letters_unread?: number;            // 9-9 家主信箱：未读来信数
  longing_p?: number;                 // RHYTHM-V2·G：她此刻的想念值 0~1
  rhythm_7d?: RhythmFacts;            // Seline 事实仪表（9-10）：近 7 天开口/回应/时延
  garden_bridge?: boolean;            // 9-17 夜：Garden 耳朵（唤醒桥）在不在岗
  garden_today?: number | null;       // 9-17 夜：今日园子动静（发帖+回帖条数）
  garden_walk?: GardenWalk | null;    // 9-23：散步三闸现值（键缺/null→状态条整行不出）
  last_letter?: LastLetter | null;    // 9-18：最近一条来信指纹（输入留痕可视化）
  why_now?: WhyNow | null;            // 9-18 #15：想念仪表（Linux 端才有，旧 server 缺席→整行不出）
  obs_7d?: ObsFacts | null;           // 9-23 能上批 c：对账观测十键（键缺/全 0 → 整段不出）
  threads?: ThreadsSnap | null;       // 9-26：线头盒观测（悬线数/最老几天）——键缺/null → 整行不出
  state?: StateSnap | null;           // 9-26：她此刻（只用 line 人话句；服务端标 server_only）
  ledger?: LedgerSnap | null;         // 9-26 W2：两本影子账的人话投影——键缺/null → 整行不出
}

// 事件脊柱读端（W2，9-26）：status.ledger——只报事实不打分；since=影子账从哪天起记
export interface LedgerSnap {
  days?: number | null;               // 窗口天数（默认 7）
  his?: number | null;                // 他说了几句
  hers?: number | null;               // 她说了几句
  proactive?: number | null;          // 她主动开口几次（💌＋💬）
  calls?: number | null;              // 引擎调用笔数
  in_tokens?: number | null;          // 上下文 token
  out_tokens?: number | null;         // 她写出来的 token
  since?: string | null;              // 账从哪天起记
}

// 线头盒观测（9-26）：status.threads——悬线总数 + 最老挂了几天；只报事实，不打分
export interface ThreadsSnap {
  open?: number | null;               // 悬线总数
  oldest_days?: number | null;        // 最老一条挂了几天（空盒/算不出 → null）
}

// 她此刻·人话投影（9-26）：status.state——只用 line（服务端 _state_line 生成的人话句）。
// server_only=true 是服务端的守门：这些值只给家主看，绝不接进任何模型侧文本。前端只读那句话。
export interface StateSnap {
  line?: string | null;               // 人话句
  server_only?: boolean;              // true＝只给家主看（不进她的行李）
}

// 对账观测（9-23 能上批 c）：/api/status.obs_7d 十键——只报事实不打分，零新请求
// RV-01（9-23 小修批）：键名照服务端实测订正——五键带前缀（claim_* / l2_*），规格卷把键名写简了
export interface ObsFacts {
  claim_named?: number | null;    // 对账：提名
  claim_passed?: number | null;   // 对账：放行
  claim_shadow?: number | null;   // 对账：影子
  claim_held?: number | null;     // 对账：打回
  fake_tool?: number | null;      // 假工具调用拦下次数
  recall?: number | null;         // 开场检索次数
  recall_hit?: number | null;     // 开场检索命中次数
  l2_in_class?: number | null;    // 时机感知：上课压
  l2_just_slept?: number | null;  // 时机感知：刚睡压
  l2_idle_boost?: number | null;  // 时机感知：闲抬
}

// 最近来信指纹（9-18 优化批一）：她摆出「你说过 X」时，手机一眼对账
export interface LastLetter {
  id?: number;
  at?: string;
  md5?: string;
  peek?: string;
}

// 想念仪表（9-18 升级 #15）：引擎刚才在想什么——last 空=还没照过面；整个键缺席=旧 server，整行不出
export interface WhyNow {
  last?: string;
  last_open?: string;
  opens_7d?: number;
  holds_7d?: number;
  recent?: string[];
}

// 散步三闸现值（9-23 Garden 前端三件②）：与真闸同源的只读投影——
// walk_allowed=这会儿能不能出门；值 null=查询坏账（server 三键各回 null），UI 不出行
export interface GardenWalk {
  walk_allowed?: boolean | null;
  last_walk_ts?: string | null;
  walks_today?: number | null;
}

// 拉耳朵响应（9-18 优化批二）
export interface BridgeUpResp {
  ok?: boolean;
  running?: boolean;
  msg?: string;
}

export interface GoodnightResp {
  diary?: string;
  note?: string;
}

// 工地日志（9-12）：GET /api/logs 的返回——server 日志尾部原样
export interface LogsResp {
  lines?: string[];
}

// 共读书架（9-12）：一本书 + 你们俩先后落的批注（who 两色墨迹）
export interface BookMark {
  id: number;
  who: string;      // 小乖 | 姐姐
  loc: string;      // 位置随手写：页码/章节/百分比
  text: string;
  time: string;
  para?: number;    // 锚定的段落号（阅读器里点段落的批注；-1/undefined=不锚段落）
}

export interface BookShelf {
  id: number;
  title: string;
  author: string;
  status: string;
  file?: string;
  pos_me?: number;    // 我的阅读进度（段落号）
  pos_her?: number;   // 姐姐的阅读进度（段落号）
  marks: BookMark[];
}

export interface BooksResp {
  books?: BookShelf[];
}

// FE-02（9-13）：她的独处格——her_traces 窗口（Garden 的痕迹，给人看的那面）
export interface TraceItem {
  id: number;
  ts: string;
  ending: string;
  fact: string;
  content: string;
}

export interface TracesResp {
  traces?: TraceItem[];
}

// 情绪河快捷档（9-12）：「日/周/月」chips = 窗口 1/7/30 天的快捷键，缩放本身是连续的
export interface RVTab {
  label: string;
  days: number;
}

export const RIVER_TABS: RVTab[] = [
  { label: '日', days: 1 },
  { label: '周', days: 7 },
  { label: '月', days: 30 },
];

// 夜间模式三选（9-12）：关 / 开 / 跟随系统
export interface PrefTab {
  value: string;
  label: string;
}

export const NIGHT_PREF_TABS: PrefTab[] = [
  { value: 'off', label: '关闭' },
  { value: 'on', label: '开启' },
  { value: 'auto', label: '跟随系统' },
];

// 共读原文（9-12 下午）：GET /api/books/content?id= 的返回——txt 全文，app 本地切段
export interface BookContentResp {
  ok?: boolean;
  id?: number;
  content?: string;
  error?: string;
}

// 咱家的账本（9-12 晚）：GET /api/stats——总账上墙
export interface StatsResp {
  chats?: number;         // 库内对话总条数
  chars?: number;         // 库内对话总字符数
  first_day?: string;     // 最早一条的日期
  old_msgs?: number;      // 旧家档案条数（档案馆/旧家记录）
  old_cn_chars?: number;  // 旧家档案中文字数
  // 9-23 新门配套（只加不改）：总账页新键——旧五键继续给原卡用，两把尺别混
  chats_cn_chars?: number | null;   // 中文字数（新口径；DB 忙时 null）
  old_home?: LedgerPair | null;     // 旧家三卷账；null=缺席（不拿 0 冒充）
  grand_total?: LedgerPair | null;  // 两本合账；null=算不齐
}

// 总账一格：条数 + 中文字数（old_home / grand_total 同款）
export interface LedgerPair {
  msgs?: number;
  cn_chars?: number;
}

// ── 档案馆（9-23 V-2「全都看得见」）──
// 契约（服务端下一批）：GET /api/archive → items[{name,group,size}]；?name= → text（只读，限馆内）。
// 列表五组（卡片馆/周卷/旧家三卷/全档案续页/大事记卷）由服务端 group 字段带出，前端不硬编码组名。
export interface ArchiveItem {
  name?: string;
  group?: string;
  size?: number;
}
export interface ArchiveResp {
  ok?: boolean;
  items?: ArchiveItem[];
}
export interface ArchiveTextResp {
  ok?: boolean;
  text?: string;
}
// 卡片馆走现成 /api/cards（40 卡）：groups[{key,count,cards[{id,title,fact,source,confidence}]}]
export interface CardItem {
  id?: string;
  title?: string;
  fact?: string;
  source?: string;
  confidence?: string;
}
export interface CardGroup {
  key?: string;
  count?: number;
  cards?: CardItem[];
}
export interface CardsResp {
  ok?: boolean;
  count?: number;
  groups?: CardGroup[];
}
// ── 9-23 能上批 a：照片墙——GET /api/favorites → {"photos":["x.jpg",…]}（只读，无参）──
export interface FavoritesResp {
  photos?: string[];
}
// ── 9-23 能上批 b：门牌墙——GET /api/wall → {"pins":[{"pin_id","content"}]}（只读，无参）──
export interface WallPin {
  pin_id?: number | string;   // 只作 ForEach key
  content?: string;
}
export interface WallResp {
  ok?: boolean;
  pins?: WallPin[];
}
// ── 9-23 能上批 d：周报（服务端本批配套）——列表/开卷契约照监理原文：
// GET /api/lib_reports → {"ok":true,"items":[{id,date,kind,status,created_at,title}]}；
// GET ?id=N → {"ok":true,id,title,status,text}。只读，终审是姐姐的笔（前端绝不代签） ──
export interface LibReportItem {
  id?: number;
  date?: string;
  kind?: string;
  status?: string;
  created_at?: string;
  title?: string;
}
export interface LibReportsResp {
  ok?: boolean;
  items?: LibReportItem[];
}
export interface LibReportDocResp {
  ok?: boolean;
  id?: number;
  title?: string;
  status?: string;
  text?: string;
}

export interface PromiseResp {
  promise?: string;
  first?: string | null;   // FE-02 门楣：今天日记的首句（server 只加不改，没有则 null）
}

// ── 9-29 §12 app 显示面：三只只读口的返回形状（字段全 optional，缺项照缺席渲染，不拿 0 冒充）──
// 家的体检·观测层 /api/health（9-28 柔性批已上线；health_api 关着时 404）
export interface HealthSoftTop {
  where?: string;
  n?: number;
}

export interface HealthSoftFail {
  days?: number;
  total?: number;
  top3?: HealthSoftTop[];
}

export interface HealthEmbed {
  endpoint?: string;
  model?: string;
}

export interface HealthBackup {
  file?: string;
  at?: string;
  age_h?: number;
}

export interface HealthMechFace {
  tunnel?: boolean;
  tunnel_up?: boolean;
  garden_bridge?: boolean;
  embedding?: HealthEmbed | null;
  last_backup?: HealthBackup | null;
}

export interface HealthLedgerScene {
  scene?: string;
  calls?: number;
  in?: number;
  out?: number;
  cached?: number;
}

export interface HealthLedger {
  date?: string;
  calls?: number;
  in_tokens?: number;
  out_tokens?: number;
  cached_tokens?: number;
  cache_hit?: number | null;
  cost_est?: number | null;
  cost_mode?: string;
  scenes?: HealthLedgerScene[];
}

export interface HealthResp {
  now?: string;
  server_up_min?: number | null;
  soft_fail?: HealthSoftFail | null;
  mechanisms?: HealthMechFace | null;
  ledger_today?: HealthLedger | null;
}

// 家的体检·影子读数 /api/shadows（9-29 服务端新件）——只有读数与条数，**不带她的原文**
export interface ShDesire {
  D?: number | null;
  blocked_by?: string | null;
  ticks_today?: number;
  fired_today?: number;
  at?: string | null;
}

export interface ShSingle {
  tier?: number | null;
  p?: number | null;
  blocked_by?: string | null;
  ticks_today?: number;
  hits_today?: number;
  at?: string | null;
}

export interface ShRecall {
  walks_today?: number;
  cards_today?: number;
  at?: string | null;
}

export interface ShHuatou {
  collected_today?: number;
  delivered_today?: number;
  said_today?: number;
  held_today?: number;
  at?: string | null;
}

export interface ShGate {
  samples_24h?: number;
  delivered?: number;
  kept?: number;
  dropped?: number;
  empty_rate?: number | null;
}

export interface ShadowsResp {
  ok?: boolean;
  now?: string;
  desire_v2?: ShDesire | null;
  single?: ShSingle | null;
  recall?: ShRecall | null;
  huatou?: ShHuatou | null;
  gate?: ShGate | null;
}

// 家的体检·机制台账公开段 /api/mech（9-29 服务端新件；私档段服务端已剔）
export interface MechSection {
  title?: string;
  text?: string;
}

export interface MechResp {
  ok?: boolean;
  generated?: string | null;
  sections?: MechSection[];
}

// 夜里·睡眠整理 /api/dream（9-29 服务端新件；牵线只给条数）
export interface DreamHeat {
  hot?: number;
  warm?: number;
  cold?: number;
}

export interface DreamMerge {
  a?: string;
  a_ref?: string;
  b?: string;
  b_ref?: string;
  ratio?: number;
}

export interface DreamReplay {
  day_no?: number;
  title?: string;
  mood?: string;
}

export interface DreamNight {
  date?: string;
  heat?: DreamHeat | null;
  merge?: DreamMerge[];
  link_n?: number;
  replay?: DreamReplay[];
}

export interface DreamResp {
  ok?: boolean;
  nights?: DreamNight[];
}

// 随手记 /api/notes（9-9 现成，此前 app 没接）
export interface NoteItem {
  id?: number;
  text?: string;
  time?: string;
}

export interface NotesResp {
  notes?: NoteItem[];
}

export interface ThinkingResp {
  thinking?: string | null;
}

// 开门有信（9-2 #总）
export interface OutboxLetter {
  id: number;
  text: string;
  time: string;
}

export interface OutboxResp {
  letters?: OutboxLetter[];
}

// ── 打卡（工单 9-1-#2） ──
export interface CheckinItem {
  id: number;
  name: string;
  target_time: string | null;
  created_at: string;
}

export interface CheckinItemsResp {
  items?: CheckinItem[];
}

export interface TodayCheckin {
  id: number;
  item_id: number;
  name: string;
  time: string;
}

export interface TodayCheckinsResp {
  checkins?: TodayCheckin[];
}

// CHECKIN-2（9-13）：月视图——每项本月打卡日（day 数字数组）+ 连续/最长（里程碑在 server 侧入 Garden）
export interface MonthCheckinItem {
  item_id: number;
  name: string;
  archived: boolean;
  streak: number;
  best: number;
  days: number[];
}

export interface MonthCheckinsResp {
  month?: string;
  items?: MonthCheckinItem[];
}

export interface OkResp {
  ok?: boolean;
  id?: number;
  error?: string;
}

// ── 心情曲线 v2（9-9） ──
export interface MoodPoint {
  date: string;
  score: number;      // 浓度 1~5（旧字段名 score 沿用 server 契约）
  source: string;     // 小乖 | 姐姐 | 今日主色
  note: string;
  time: string;
  hh?: number;        // 9-12：真小时数（0~23，-1=没解析出）。日视图按它分布——
                      // 旧版从 time（MM-DD HH:MM）前两位抠出的是月份，全挤一列的血案
  type: string;       // 词表词；空串=旧数字分
}

export interface MoodsResp {
  types?: MoodTypeItem[];
  moods?: MoodPoint[];
}

// 心情打卡请求体（ArkTS 不许无类型对象字面量）
export interface MoodReqBody {
  type: string;
  intensity: number;
  note: string;
}

// 情绪河墨点坐标缓存（RIVER-3）：画的时候记下每个星落在哪里，点了才知道弹哪条
export interface RiverDot {
  x: number;
  y: number;
  point: MoodPoint;
}

// 日记馆（HALL-01，9-10）：两格合并条目——src='days' 是姐姐正典的投影，'hall' 是他投的
export interface HallEntry {
  id: number;
  src: string;
  date: string;
  author: string;
  title: string;
  content: string;
  mood: string;
  time: string;
}

export interface HallResp {
  entries?: HallEntry[];
  error?: string;
}

export interface HallReqBody {
  title: string;
  content: string;
  mood: string;
}

// 两封信（HER-WORDS，9-10）：小乖的话（亲笔存储版优先，没写过回退常量）+ 姐姐的话（她的自留页最新版）
export interface WordsResp {
  xiaoguai?: string;
  xiaoguai_version?: number;   // 9-12：他亲笔的版号（0=还是工地代笔常量，没写过）
  jiejie?: HerWords;
}

export interface HerWords {
  text?: string;
  version?: number;
  time?: string;
}

// Seline 事实仪表（9-10，波索斯家风：只报事实不打分）
export interface RhythmFacts {
  letters?: number | null;
  replies?: number | null;
  avg_reply_min?: number | null;
}

// 家主信箱投信请求体（9-9）
export interface LetterReqBody {
  message: string;
}

// 打卡请求体（ArkTS 不许无类型对象字面量）
export interface CheckinReqBody {
  item_id: number;
}

export interface ArchiveReqBody {
  id: number;
}

// outbox 待发队列条目：message 必有，其余照发送时的可选字段原样存
export interface OutboxItem {
  message: string;
  msgId?: string;     // 9-12 消息身份证跟着排队走：补发时原样带回去重（绝不双发）
  image?: string;
  loc?: LocInfo;
  place?: string;
  file?: FileBody;    // 9-1-#8：附件跟着排队走
  queuedAt: string;
}

export interface ChatItem {
  key: string;
  who: string;      // '小乖' | '姐姐' | '系统' | '思考'
  text: string;
  imageUrl: string; // '' 表示无图；新拍的照片用 dataURL，历史图用 /photos/ URL
  time: string;     // 'HH:MM' 或 '思考 X.Xs · HH:MM'
  tools?: ToolUseInfo[];   // 姐姐动过的图书证，无则不渲染
  msgId?: number;          // 二期d：chats 行号（历史才有）
  hasThinking?: boolean;   // 二期d：这条有思考链可点开
  fileName?: string;       // 9-1-#8：附件文件名（气泡里显示小片）
  thinkDone?: boolean;     // 9-12 时间线：思考卡已封口（time=「思考了 Ns」，text=全文可展开）
}
