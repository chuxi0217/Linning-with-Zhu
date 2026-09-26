import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { geoLocationManager } from '@kit.LocationKit';
import { connection, http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, mediaquery } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import {
  C_BG, C_ACCENT, C_BUBBLE_ME, C_HER_EDGE, C_PANEL, C_WHITE, C_CARD,
  C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4, C_TEXT_5, C_OK, C_DISABLED, C_DOT_BORDER,
  FS_TITLE, FS_BODY, FS_SUB, FS_AUX, R_TAIL, R_SM, R_MD, R_LG, R_XL, R_PILL, R_PILL_XL,
  M_PAGE, NIGHT_MAP
} from '../common/AppStyles';

const MAX_EDGE: number = 1024;
const JPEG_QUALITY: number = 70;
// 9-23 门牌换代：新门=公网域名（VPS → 隧道 → server:8024），默认走它
const BASE_URL: string = 'https://your-door.example';
const BASE_URL_OLD: string = 'https://node.your-door.ts.net';      // 旧门过渡：Windows（node）
const BASE_URL_LINUX: string = 'https://chuxi.your-door.ts.net';   // 旧门过渡：Linux（chuxi）
// 新门挂着 Caddy Basic 门锁——每个请求都得带钥匙；钥匙串在 ~/咱家记忆库/网络门锁凭证.txt
const DOOR_AUTH: string = 'Basic <Base64(用户名:密码)>';
// 图片走 URL 后门：Image 组件带不了请求头，服务端认 ?token=<同一把密码>
const DOOR_TOKEN: string = '<门锁密码>';
// 9-1-#8 刀3：地址收编——全工程写死的地址都在这儿，设置页换门牌走 applyServerBase
let CHAT_URL: string = BASE_URL + '/api/chat';
let HISTORY_URL: string = BASE_URL + '/api/history';
let STATUS_URL: string = BASE_URL + '/api/status';
let GOODNIGHT_URL: string = BASE_URL + '/api/goodnight';
let TODAY_DIARY_URL: string = BASE_URL + '/api/today_diary';
let CHECKIN_URL: string = BASE_URL + '/api/checkin';
let CHECKIN_ITEMS_URL: string = BASE_URL + '/api/checkin/items';
let CHECKIN_ARCHIVE_URL: string = BASE_URL + '/api/checkin/items/archive';
let CHECKINS_TODAY_URL: string = BASE_URL + '/api/checkins/today';
let CHECKINS_MONTH_URL: string = BASE_URL + '/api/checkins/month';   // CHECKIN-2（9-13）：月视图（连续/热力图）
let TRACES_URL: string = BASE_URL + '/api/traces';     // 她的独处（FE-02，9-13：Garden 痕迹窗口）
let THINKING_URL: string = BASE_URL + '/api/thinking';
let OUTBOX_URL: string = BASE_URL + '/api/outbox';
let PHOTOS_BASE: string = BASE_URL + '/photos/';
let MOODS_URL: string = BASE_URL + '/api/moods';
let MOOD_URL: string = BASE_URL + '/api/mood';
let LETTER_URL: string = BASE_URL + '/api/letter';
let HALL_URL: string = BASE_URL + '/api/hall_diary';   // 日记馆（HALL-01，9-10）
let WORDS_URL: string = BASE_URL + '/api/words';       // 两封信（HER-WORDS，9-10）
let LOGS_URL: string = BASE_URL + '/api/logs';         // 工地日志（9-12：手机上看工具真调没调）
let BOOKS_URL: string = BASE_URL + '/api/books';       // 共读书架（9-12：两人同读一本，批注互见）
let STATS_URL: string = BASE_URL + '/api/stats';       // 咱家的账本（9-12 晚：总账上墙）
let SCHEDULE_URL: string = BASE_URL + '/api/schedule'; // 日程上报（CAL-01，9-13：他今天的日程给姐姐）
let BRIDGE_UP_URL: string = BASE_URL + '/api/garden/bridge/up';   // 拉耳朵（9-18 优化批二）
let ARCHIVE_URL: string = BASE_URL + '/api/archive';   // 档案馆列表/开卷（V-2，9-23；服务端下一批）
let CARDS_URL: string = BASE_URL + '/api/cards';       // 卡片馆四馆正典（现成，9-18 批七）
// ── 9-23 能上批（App）：只读新件（a 照片墙 / b 门牌墙 / d 周报，服务端配套或现成）──
let FAVORITES_URL: string = BASE_URL + '/api/favorites';       // 收藏夹清单（a）
let FAVORITES_BASE: string = BASE_URL + '/favorites/';         // 收藏夹图根（照 PHOTOS_BASE 家风，图 URL 尾巴带 ?token=）
let WALL_URL: string = BASE_URL + '/api/wall';                 // 门牌墙（b）
let LIB_REPORTS_URL: string = BASE_URL + '/api/lib_reports';   // 周报列表/开卷（d；服务端本批配套）

// 换门牌：一处改全部（空串=回默认 Windows 门牌）
function applyServerBase(base: string): void {
  const b = base || BASE_URL;
  CHAT_URL = b + '/api/chat';
  HISTORY_URL = b + '/api/history';
  STATUS_URL = b + '/api/status';
  GOODNIGHT_URL = b + '/api/goodnight';
  TODAY_DIARY_URL = b + '/api/today_diary';
  CHECKIN_URL = b + '/api/checkin';
  CHECKIN_ITEMS_URL = b + '/api/checkin/items';
  CHECKIN_ARCHIVE_URL = b + '/api/checkin/items/archive';
  CHECKINS_TODAY_URL = b + '/api/checkins/today';
  CHECKINS_MONTH_URL = b + '/api/checkins/month';
  TRACES_URL = b + '/api/traces';
  THINKING_URL = b + '/api/thinking';
  OUTBOX_URL = b + '/api/outbox';
  PHOTOS_BASE = b + '/photos/';
  MOODS_URL = b + '/api/moods';
  MOOD_URL = b + '/api/mood';
  LETTER_URL = b + '/api/letter';
  HALL_URL = b + '/api/hall_diary';
  WORDS_URL = b + '/api/words';
  LOGS_URL = b + '/api/logs';
  BOOKS_URL = b + '/api/books';
  STATS_URL = b + '/api/stats';
  SCHEDULE_URL = b + '/api/schedule';
  BRIDGE_UP_URL = b + '/api/garden/bridge/up';
  ARCHIVE_URL = b + '/api/archive';
  CARDS_URL = b + '/api/cards';
  FAVORITES_URL = b + '/api/favorites';
  FAVORITES_BASE = b + '/favorites/';
  WALL_URL = b + '/api/wall';
  LIB_REPORTS_URL = b + '/api/lib_reports';
}
const HTTP_TIMEOUT_MS: number = 30000;
const CHAT_TIMEOUT_MS: number = 90000;   // /api/chat 专用：姐姐查图书证会多花时间，放宽到 90s
const HILOG_TAG: string = 'firstBrick';

// 情绪词表（9-9 心情曲线 v2；9-12 MOOD-V1 九并六）：与 server MOOD_TYPES 常量同一份正典
//（改词表=两处都改）。顺序即展示顺序，色值即情绪河墨色。
interface MoodTypeItem {
  name: string;
  color: string;
}
const MOOD_TYPES: MoodTypeItem[] = [
  { name: '欲望', color: '#d95d63' },
  { name: '想你', color: '#e08cae' },
  { name: '开心', color: '#e2a93b' },
  { name: '委屈', color: '#7a9bd4' },
  { name: '踏实', color: '#7fa66a' },
  { name: '累', color: '#8d8478' }
];
const MOOD_LEGACY_COLOR: string = '#c9beb0';   // 词表上线前的旧数字分（type 空串）画中性灰
// MOOD-V1（9-12）词表九并六：心疼/平静/骄傲 退出正典——旧数据原样留库，
// 展示层先过这张映射再取色取名（只用于展示，绝不回写）。
const LEGACY_MOOD_MAP: Record<string, string> = {
  '心疼': '委屈',
  '平静': '踏实',
  '骄傲': '开心'
};

interface LocInfo {
  lat: number;
  lon: number;
  place?: string;   // 逆地理编码出的文字地址，可没有
}

interface ChatBody {
  message: string;
  msg_id?: string;    // 9-12 消息身份证：重试/补发复用同一张，server 凭它去重（回包丢了也不双发）
  image?: string;
  loc?: LocInfo;
  place?: string;
  file?: FileBody;    // 9-1-#8 刀2：文本附件
  stream?: boolean;   // 9-4 自由发挥包：SSE 流式（思考+正文打字机）
}

// 9-4 流式 SSE 事件（server 契约：thinking/reply/status/tool/round/done/error）
interface StreamEvent {
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
interface FileBody {
  name: string;
  content: string;
}

// CAL-01（9-13）日程上报形状：只带标题+开始时间（家训：只放必要信息）
interface ScheduleItem {
  time: string;    // 'HH:MM'
  title: string;   // ≤20 字
}

interface ScheduleBody {
  date: string;    // 'YYYY-MM-DD'
  items: ScheduleItem[];
}

interface ChatReply {
  reply?: string;
  think_ms?: number;
  tools?: ToolUseInfo[];
  reasoning?: string;   // 二期d：思考链原文（思考模式开着且这轮有的话）
}

interface ToolUseInfo {
  name: string;
  args: string;
  ms: number;
  rounds: number;
}

interface HistoryMsg {
  who: string;
  text: string;
  image: string | null;
  time: string;
  id?: number;              // 二期d：chats 行号，取思考链要用
  has_thinking?: boolean;   // 二期d：这条姐姐回复有没有思考链
  file?: string | null;     // 9-1-#8：附件文件名（〔附件：…〕解析出来的）
}

interface HistoryResp {
  messages: HistoryMsg[];
  has_more?: boolean | null;   // 9-23 V-1：更早还有没有（旧 server 不带此键=不分页）
}

interface StatusLoc {
  lat: number;
  lon: number;
  time: string;
  place?: string;
}

interface StatusResp {
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
interface LedgerSnap {
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
interface ThreadsSnap {
  open?: number | null;               // 悬线总数
  oldest_days?: number | null;        // 最老一条挂了几天（空盒/算不出 → null）
}

// 她此刻·人话投影（9-26）：status.state——只用 line（服务端 _state_line 生成的人话句）。
// server_only=true 是服务端的守门：这些值只给家主看，绝不接进任何模型侧文本。前端只读那句话。
interface StateSnap {
  line?: string | null;               // 人话句
  server_only?: boolean;              // true＝只给家主看（不进她的行李）
}

// 对账观测（9-23 能上批 c）：/api/status.obs_7d 十键——只报事实不打分，零新请求
// RV-01（9-23 小修批）：键名照服务端实测订正——五键带前缀（claim_* / l2_*），规格卷把键名写简了
interface ObsFacts {
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
interface LastLetter {
  id?: number;
  at?: string;
  md5?: string;
  peek?: string;
}

// 想念仪表（9-18 升级 #15）：引擎刚才在想什么——last 空=还没照过面；整个键缺席=旧 server，整行不出
interface WhyNow {
  last?: string;
  last_open?: string;
  opens_7d?: number;
  holds_7d?: number;
  recent?: string[];
}

// 散步三闸现值（9-23 Garden 前端三件②）：与真闸同源的只读投影——
// walk_allowed=这会儿能不能出门；值 null=查询坏账（server 三键各回 null），UI 不出行
interface GardenWalk {
  walk_allowed?: boolean | null;
  last_walk_ts?: string | null;
  walks_today?: number | null;
}

// 拉耳朵响应（9-18 优化批二）
interface BridgeUpResp {
  ok?: boolean;
  running?: boolean;
  msg?: string;
}

interface GoodnightResp {
  diary?: string;
  note?: string;
}

// 工地日志（9-12）：GET /api/logs 的返回——server 日志尾部原样
interface LogsResp {
  lines?: string[];
}

// 共读书架（9-12）：一本书 + 你们俩先后落的批注（who 两色墨迹）
interface BookMark {
  id: number;
  who: string;      // 小乖 | 姐姐
  loc: string;      // 位置随手写：页码/章节/百分比
  text: string;
  time: string;
  para?: number;    // 锚定的段落号（阅读器里点段落的批注；-1/undefined=不锚段落）
}

interface BookShelf {
  id: number;
  title: string;
  author: string;
  status: string;
  file?: string;
  pos_me?: number;    // 我的阅读进度（段落号）
  pos_her?: number;   // 姐姐的阅读进度（段落号）
  marks: BookMark[];
}

interface BooksResp {
  books?: BookShelf[];
}

// FE-02（9-13）：她的独处格——her_traces 窗口（Garden 的痕迹，给人看的那面）
interface TraceItem {
  id: number;
  ts: string;
  ending: string;
  fact: string;
  content: string;
}

interface TracesResp {
  traces?: TraceItem[];
}

// 情绪河快捷档（9-12）：「日/周/月」chips = 窗口 1/7/30 天的快捷键，缩放本身是连续的
interface RVTab {
  label: string;
  days: number;
}

const RIVER_TABS: RVTab[] = [
  { label: '日', days: 1 },
  { label: '周', days: 7 },
  { label: '月', days: 30 },
];

// 夜间模式三选（9-12）：关 / 开 / 跟随系统
interface PrefTab {
  value: string;
  label: string;
}

const NIGHT_PREF_TABS: PrefTab[] = [
  { value: 'off', label: '关闭' },
  { value: 'on', label: '开启' },
  { value: 'auto', label: '跟随系统' },
];

// 共读原文（9-12 下午）：GET /api/books/content?id= 的返回——txt 全文，app 本地切段
interface BookContentResp {
  ok?: boolean;
  id?: number;
  content?: string;
  error?: string;
}

// 咱家的账本（9-12 晚）：GET /api/stats——总账上墙
interface StatsResp {
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
interface LedgerPair {
  msgs?: number;
  cn_chars?: number;
}

// ── 档案馆（9-23 V-2「全都看得见」）──
// 契约（服务端下一批）：GET /api/archive → items[{name,group,size}]；?name= → text（只读，限馆内）。
// 列表五组（卡片馆/周卷/旧家三卷/全档案续页/大事记卷）由服务端 group 字段带出，前端不硬编码组名。
interface ArchiveItem {
  name?: string;
  group?: string;
  size?: number;
}
interface ArchiveResp {
  ok?: boolean;
  items?: ArchiveItem[];
}
interface ArchiveTextResp {
  ok?: boolean;
  text?: string;
}
// 卡片馆走现成 /api/cards（40 卡）：groups[{key,count,cards[{id,title,fact,source,confidence}]}]
interface CardItem {
  id?: string;
  title?: string;
  fact?: string;
  source?: string;
  confidence?: string;
}
interface CardGroup {
  key?: string;
  count?: number;
  cards?: CardItem[];
}
interface CardsResp {
  ok?: boolean;
  count?: number;
  groups?: CardGroup[];
}
// ── 9-23 能上批 a：照片墙——GET /api/favorites → {"photos":["x.jpg",…]}（只读，无参）──
interface FavoritesResp {
  photos?: string[];
}
// ── 9-23 能上批 b：门牌墙——GET /api/wall → {"pins":[{"pin_id","content"}]}（只读，无参）──
interface WallPin {
  pin_id?: number | string;   // 只作 ForEach key
  content?: string;
}
interface WallResp {
  ok?: boolean;
  pins?: WallPin[];
}
// ── 9-23 能上批 d：周报（服务端本批配套）——列表/开卷契约照监理原文：
// GET /api/lib_reports → {"ok":true,"items":[{id,date,kind,status,created_at,title}]}；
// GET ?id=N → {"ok":true,id,title,status,text}。只读，终审是姐姐的笔（前端绝不代签） ──
interface LibReportItem {
  id?: number;
  date?: string;
  kind?: string;
  status?: string;
  created_at?: string;
  title?: string;
}
interface LibReportsResp {
  ok?: boolean;
  items?: LibReportItem[];
}
interface LibReportDocResp {
  ok?: boolean;
  id?: number;
  title?: string;
  status?: string;
  text?: string;
}

interface PromiseResp {
  promise?: string;
  first?: string | null;   // FE-02 门楣：今天日记的首句（server 只加不改，没有则 null）
}

// ── 轻动效（工单 FE-02）：按压反馈只动透明度——合成器逐帧廉价，120Hz 友好，不用毛玻璃不吃重阴影 ──
@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

// ── 聊天数据源（FE-02 要求6）：LazyForEach 的 IDataSource 适配器。
// 数组是唯一真相，每次变更按需通知监听者——消息列表按需构建，一屏气泡一建，
// 不再一次性铺满全天历史（低内存、首屏快，滚动丝滑）。 ──
class ChatDataSource implements IDataSource {
  private items: ChatItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatItem {
    return this.items[index];
  }

  getAll(): ChatItem[] {
    return this.items;
  }

  // 9-18 App深搜修（DS-02）：历史卷落地前认领活口用——浅拷一份当前列表（后续改列表不动这份快照）
  snapshot(): ChatItem[] {
    return this.items.slice();
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notify(fn: (l: DataChangeListener) => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      fn(this.listeners[i]);
    }
  }

  append(item: ChatItem): void {
    this.items.push(item);
    this.notify((l: DataChangeListener) => l.onDataAdd(this.items.length - 1));
  }

  setAll(items: ChatItem[]): void {
    this.items = items;
    this.notify((l: DataChangeListener) => l.onDataReloaded());
  }

  // FE3-02（b）（9-23）：续载去重——服务端 id 唯一，已在列表里的同一条账不再接第二份。
  // 无 id 的活口气泡（乐观气泡/时间线卡）不在此列，仍走 mergeWithLive 的认领口径。
  private hasMsgId(id: number): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].msgId === id) {
        return true;
      }
    }
    return false;
  }

  // 9-23 V-1 全量浏览：老窗前插（旧在前）——倒序逐条 onDataAdd(0)，让列表
  // maintainVisibleContentPosition 能按"插入在可视区外"维持眼前这屏（整卷 reload 会顶走位置）
  prependAll(arr: ChatItem[]): void {
    if (arr.length === 0) {
      return;
    }
    for (let i = arr.length - 1; i >= 0; i--) {
      const m = arr[i];
      if (m.msgId !== undefined && this.hasMsgId(m.msgId)) {
        continue;   // FE3-02（b）：已经有这条账了，跳过
      }
      this.items.unshift(m);
      this.notify((l: DataChangeListener) => l.onDataAdd(0));
    }
  }

  // 9-23 V-1：下翻续载——尾部顺序追加（与 prependAll 对称）
  appendAll(arr: ChatItem[]): void {
    for (let i = 0; i < arr.length; i++) {
      const m = arr[i];
      if (m.msgId !== undefined && this.hasMsgId(m.msgId)) {
        continue;   // FE3-02（b）：老窗续载到今天的窗口时，同一句话不再出现第二份
      }
      this.items.push(m);
      this.notify((l: DataChangeListener) => l.onDataAdd(this.items.length - 1));
    }
  }

  removeWhere(pred: (m: ChatItem) => boolean): void {
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (pred(this.items[i])) {
        this.items.splice(i, 1);
        this.notify((l: DataChangeListener) => l.onDataDelete(i));
      }
    }
  }

  updateByKey(key: string, next: ChatItem): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === key) {
        this.items[i] = next;
        this.notify((l: DataChangeListener) => l.onDataChange(i));
        return;
      }
    }
  }

  // 只换正文，其余字段（who/time/tools…）原样保留——ArkTS 不许 Object.assign，显式重建整条
  updateText(key: string, text: string): void {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === key) {
        const m = this.items[i];
        const n: ChatItem = {
          key: m.key, who: m.who, text: text, imageUrl: m.imageUrl, time: m.time,
          tools: m.tools, msgId: m.msgId, hasThinking: m.hasThinking, fileName: m.fileName,
        };
        this.items[i] = n;
        this.notify((l: DataChangeListener) => l.onDataChange(i));
        return;
      }
    }
  }
}

interface ThinkingResp {
  thinking?: string | null;
}

// 开门有信（9-2 #总）
interface OutboxLetter {
  id: number;
  text: string;
  time: string;
}

interface OutboxResp {
  letters?: OutboxLetter[];
}

// ── 打卡（工单 9-1-#2） ──
interface CheckinItem {
  id: number;
  name: string;
  target_time: string | null;
  created_at: string;
}

interface CheckinItemsResp {
  items?: CheckinItem[];
}

interface TodayCheckin {
  id: number;
  item_id: number;
  name: string;
  time: string;
}

interface TodayCheckinsResp {
  checkins?: TodayCheckin[];
}

// CHECKIN-2（9-13）：月视图——每项本月打卡日（day 数字数组）+ 连续/最长（里程碑在 server 侧入 Garden）
interface MonthCheckinItem {
  item_id: number;
  name: string;
  archived: boolean;
  streak: number;
  best: number;
  days: number[];
}

interface MonthCheckinsResp {
  month?: string;
  items?: MonthCheckinItem[];
}

interface OkResp {
  ok?: boolean;
  id?: number;
  error?: string;
}

// ── 心情曲线 v2（9-9） ──
interface MoodPoint {
  date: string;
  score: number;      // 浓度 1~5（旧字段名 score 沿用 server 契约）
  source: string;     // 小乖 | 姐姐 | 今日主色
  note: string;
  time: string;
  hh?: number;        // 9-12：真小时数（0~23，-1=没解析出）。日视图按它分布——
                      // 旧版从 time（MM-DD HH:MM）前两位抠出的是月份，全挤一列的血案
  type: string;       // 词表词；空串=旧数字分
}

interface MoodsResp {
  types?: MoodTypeItem[];
  moods?: MoodPoint[];
}

// 心情打卡请求体（ArkTS 不许无类型对象字面量）
interface MoodReqBody {
  type: string;
  intensity: number;
  note: string;
}

// 情绪河墨点坐标缓存（RIVER-3）：画的时候记下每个星落在哪里，点了才知道弹哪条
interface RiverDot {
  x: number;
  y: number;
  point: MoodPoint;
}

// 日记馆（HALL-01，9-10）：两格合并条目——src='days' 是姐姐正典的投影，'hall' 是他投的
interface HallEntry {
  id: number;
  src: string;
  date: string;
  author: string;
  title: string;
  content: string;
  mood: string;
  time: string;
}

interface HallResp {
  entries?: HallEntry[];
  error?: string;
}

interface HallReqBody {
  title: string;
  content: string;
  mood: string;
}

// 两封信（HER-WORDS，9-10）：小乖的话（亲笔存储版优先，没写过回退常量）+ 姐姐的话（她的自留页最新版）
interface WordsResp {
  xiaoguai?: string;
  xiaoguai_version?: number;   // 9-12：他亲笔的版号（0=还是工地代笔常量，没写过）
  jiejie?: HerWords;
}

interface HerWords {
  text?: string;
  version?: number;
  time?: string;
}

// Seline 事实仪表（9-10，波索斯家风：只报事实不打分）
interface RhythmFacts {
  letters?: number | null;
  replies?: number | null;
  avg_reply_min?: number | null;
}

// 家主信箱投信请求体（9-9）
interface LetterReqBody {
  message: string;
}

// 打卡请求体（ArkTS 不许无类型对象字面量）
interface CheckinReqBody {
  item_id: number;
}

interface ArchiveReqBody {
  id: number;
}

// outbox 待发队列条目：message 必有，其余照发送时的可选字段原样存
interface OutboxItem {
  message: string;
  msgId?: string;     // 9-12 消息身份证跟着排队走：补发时原样带回去重（绝不双发）
  image?: string;
  loc?: LocInfo;
  place?: string;
  file?: FileBody;    // 9-1-#8：附件跟着排队走
  queuedAt: string;
}

interface ChatItem {
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

function errMsg(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return JSON.stringify(err);
}

// 9-12 消息身份证：时间戳+随机，够防「同一条消息的两次重试」撞号——
// 去重窗口是秒级到分钟级，不需要正经 UUID。
function newMsgId(): string {
  return `m${Date.now().toString(36)}${Math.floor(Math.random() * 0xffffffff).toString(36)}`;
}

// ─────── CAL-02（9-13）课表本地化：节次时间正典 + 纯解析 ───────
// #region CAL-02 沙盘转译区（纯函数、无副作用；_t_cal02 按此标记机械转译跑断言）
// 改写法请保持简式：不用箭头函数、对象字面量单行、不碰 this 与外部状态

// 节次时间正典（1=08:00-08:45 … 13=21:20-22:05）：与上报共用一份，硬编码就在这里。
// 9-18 家主定口径：1-8 不动；新插 9=18:10-18:50、10=18:50-19:30（课外活动那档）；
// 原 9-11 顺延成 11-13（19:40-20:25 / 20:30-21:15 / 21:20-22:05）——全校表共 13 节。
const PERIOD_SLOTS: string[] = [
  '08:00-08:45', '08:55-09:40', '10:00-10:45', '10:55-11:40',
  '14:30-15:15', '15:20-16:05', '16:25-17:10', '17:15-18:00',
  '18:10-18:50', '18:50-19:30', '19:40-20:25', '20:30-21:15', '21:20-22:05',
];

// 周名表：下标跟 Date.getDay() 同规（周日=0 … 周六=6）
const WEEK_CN: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

interface TtSeg {
  ok: boolean;     // 这一段看懂没有
  from: number;    // 起节（1~13；直写时间的段为 0）
  to: number;      // 止节（含；直写时间的段为 0）
  title: string;   // 课名 + 可选 @地点（原文保留）
  time?: string;   // 9-18 直写时间档：规整成 HH:MM-HH:MM（有它就不走节次正典）
}

interface TtEntry {
  dow: number;     // 哪一天（周日=0 … 周六=6）
  from: number;
  to: number;
  title: string;
  time?: string;   // 9-18 直写时间档：原样上报、原样回写
}

interface TtParse {
  entries: TtEntry[];   // 全周所有课（不分今天）
  good: number;         // 看懂的行数
  bad: string[];        // 没看懂的行（原样逐行列出——不许静默吞）
}

// 一段课次：「1-2节 高数」「1-2 高数」「3节 英语」「3 英语」都认；节次只认 1~13。
// 9-18 新档：段首数字后面直接跟冒号的，按「直写时间」走（18:10-19:30 课外活动）——不再当节次；
// 冒号半角「:」全角「：」都算（中文输入法的真实输入）。
function parseTimetableSegment(seg: string): TtSeg {
  const r: TtSeg = { ok: false, from: 0, to: 0, title: '' };
  let i = 0;
  while (i < seg.length && (seg.charCodeAt(i) === 32 || seg.charCodeAt(i) === 12288)) {
    i++;   // 半角/全角空格都跳过
  }
  const a0 = i;
  while (i < seg.length && seg.charCodeAt(i) >= 48 && seg.charCodeAt(i) <= 57) {
    i++;   // 吃掉起节数字
  }
  if (i === a0) {
    return r;
  }
  if (i < seg.length && isColon(seg.charAt(i))) {
    return parseTimeSegment(seg, a0, i);   // 「18:10-19:30 课外活动」：直写时间档（冒号全半角都认）
  }
  let a = 0;
  for (let k = a0; k < i; k++) {
    a = a * 10 + (seg.charCodeAt(k) - 48);
  }
  let b = a;
  if (i < seg.length && seg.charAt(i) === '-') {
    i++;
    const b0 = i;
    while (i < seg.length && seg.charCodeAt(i) >= 48 && seg.charCodeAt(i) <= 57) {
      i++;   // 吃掉止节数字
    }
    if (i === b0) {
      return r;
    }
    b = 0;
    for (let k = b0; k < i; k++) {
      b = b * 10 + (seg.charCodeAt(k) - 48);
    }
  }
  if (i < seg.length && seg.charAt(i) === '节') {
    i++;   // 「节」可有可无
  }
  const title = seg.substring(i).trim();
  if (title.length === 0 || a < 1 || b < 1 || a > 13 || b > 13 || a > b) {
    return r;
  }
  r.ok = true;
  r.from = a;
  r.to = b;
  r.title = title;
  return r;
}

// 补零成两位：9 → 09（直写时间规整用）
function pad2(n: number): string {
  if (n < 10) {
    return '0' + n;
  }
  return '' + n;
}

// 冒号容错：半角「:」和全角「：」都算——中文输入法打出来是后者（只在本解析里判，不动课名文本里的标点）
function isColon(c: string): boolean {
  return c === ':' || c === '：';
}

// 9-18 直写时间一段：「18:10-19:30 课外活动」「9:05~10:05 早读」都认，规整成 HH:MM-HH:MM（补零）。
// 进来时第一段小时已经吃在 h0~i0、i0 正指着冒号；分隔符 - 或 ~ 都算。
// 半截时间（18:10-、9:05、25:00-26:00、起≥止）一律 ok=false——进「没看懂」名单，不许静默吞。
function parseTimeSegment(seg: string, h0: number, i0: number): TtSeg {
  const r: TtSeg = { ok: false, from: 0, to: 0, title: '' };
  let hh1 = 0;
  for (let k = h0; k < i0; k++) {
    hh1 = hh1 * 10 + (seg.charCodeAt(k) - 48);
  }
  let i = i0 + 1;   // 跳过第一段冒号
  const m0 = i;
  while (i < seg.length && seg.charCodeAt(i) >= 48 && seg.charCodeAt(i) <= 57) {
    i++;   // 第一段分钟
  }
  if (i === m0 || i - m0 > 2) {
    return r;
  }
  let mm1 = 0;
  for (let k = m0; k < i; k++) {
    mm1 = mm1 * 10 + (seg.charCodeAt(k) - 48);
  }
  if (!(i < seg.length && (seg.charAt(i) === '-' || seg.charAt(i) === '~'))) {
    return r;   // 没有分隔符（18:10）→ 看不懂
  }
  i++;
  const h2 = i;
  while (i < seg.length && seg.charCodeAt(i) >= 48 && seg.charCodeAt(i) <= 57) {
    i++;   // 第二段小时
  }
  if (i === h2 || i - h2 > 2 || !(i < seg.length && isColon(seg.charAt(i)))) {
    return r;   // 半截（18:10-、9:05-10）→ 看不懂
  }
  let hh2 = 0;
  for (let k = h2; k < i; k++) {
    hh2 = hh2 * 10 + (seg.charCodeAt(k) - 48);
  }
  i++;   // 跳过第二段冒号
  const m2 = i;
  while (i < seg.length && seg.charCodeAt(i) >= 48 && seg.charCodeAt(i) <= 57) {
    i++;   // 第二段分钟
  }
  if (i === m2 || i - m2 > 2) {
    return r;
  }
  let mm2 = 0;
  for (let k = m2; k < i; k++) {
    mm2 = mm2 * 10 + (seg.charCodeAt(k) - 48);
  }
  const t1 = pad2(hh1) + ':' + pad2(mm1);
  const t2 = pad2(hh2) + ':' + pad2(mm2);
  const title = seg.substring(i).trim();
  if (hh1 > 23 || mm1 > 59 || hh2 > 23 || mm2 > 59 || t1 >= t2 || title.length === 0) {
    return r;
  }
  r.ok = true;
  r.time = t1 + '-' + t2;
  r.title = title;
  return r;
}

// 整份课表逐行解析：行首必须是周X（也容忍「星期X」）；一行多段用；或，隔开，课次沿用行首周几。
// 一行里只要有任一段没看懂，整行原样计入 bad（宁列出来，不悄悄吞半截）。
function parseTimetable(raw: string): TtParse {
  const entries: TtEntry[] = [];
  const bad: string[] = [];
  let good = 0;
  const lines = raw.split('\n');
  for (let li = 0; li < lines.length; li++) {
    const rawLine = lines[li].trim();
    if (rawLine.length === 0) {
      continue;   // 空行不算课也不算错
    }
    // 行首认「周X」，也容忍「星期X」；这种换算只在行首做——课名里的「星期」两个字不许动
    let dow = -1;
    let rest = '';
    for (let w = 0; w < WEEK_CN.length; w++) {
      if (rawLine.startsWith(WEEK_CN[w])) {
        dow = w;
        rest = rawLine.substring(WEEK_CN[w].length);
        break;
      }
    }
    if (dow < 0 && rawLine.startsWith('星期')) {
      const w2 = WEEK_CN.indexOf('周' + rawLine.substring(2, 3));
      if (w2 >= 0) {
        dow = w2;
        rest = rawLine.substring(3);
      }
    }
    if (dow < 0) {
      bad.push(rawLine);   // 周几都没写 → 没看懂
      continue;
    }
    const segs = rest.split('；').join('，').split('，');
    const outs: TtEntry[] = [];
    let lineOK = true;
    for (let si = 0; si < segs.length; si++) {
      const segText = segs[si].trim();
      if (segText.length === 0) {
        continue;   // 行尾多打了分隔符：空气段跳过，不吞内容
      }
      const one = parseTimetableSegment(segText);
      if (!one.ok) {
        lineOK = false;
        break;
      }
      const e: TtEntry = { dow: dow, from: one.from, to: one.to, title: one.title, time: one.time };
      outs.push(e);
    }
    if (lineOK && outs.length > 0) {
      good = good + 1;
      for (let ei = 0; ei < outs.length; ei++) {
        entries.push(outs[ei]);
      }
    } else {
      bad.push(rawLine);
    }
  }
  const result: TtParse = { entries: entries, good: good, bad: bad };
  return result;
}

// 取「今天」的课：节次范围展开成时间条（端到端=第一小节开始~最后一小节结束），
// 按时间排序取前 5 条；title 保留课名与地点，超 20 字截断
function pickTimetableToday(parsed: TtParse, dow: number): ScheduleItem[] {
  const items: ScheduleItem[] = [];
  for (let i = 0; i < parsed.entries.length; i++) {
    const e = parsed.entries[i];
    if (e.dow !== dow) {
      continue;   // 不是今天的行不出现
    }
    let t = '';
    if (e.time !== undefined && e.time.length > 0) {
      t = e.time;   // 9-18 直写时间档：原样上报，不套正典节次
    } else {
      t = PERIOD_SLOTS[e.from - 1].split('-')[0] + '-' + PERIOD_SLOTS[e.to - 1].split('-')[1];
    }
    let title = e.title;
    if (title.length > 20) {
      title = title.substring(0, 20);
    }
    const item: ScheduleItem = { time: t, title: title };
    items.push(item);
  }
  items.sort(timetableCmpTime);
  return items.slice(0, 5);
}

function timetableCmpTime(x: ScheduleItem, y: ScheduleItem): number {
  if (x.time < y.time) {
    return -1;
  }
  if (x.time > y.time) {
    return 1;
  }
  return 0;
}

// 课表条目按开始时间排序（独立函数——沙盘转译器只认独立函数，别用内嵌匿名函数）：
// 直写时间条目用自己写的时刻，节次条目查正典——两种混排也按真实先后。
function ttEntryCmp(a: TtEntry, b: TtEntry): number {
  const at: string | undefined = a.time;
  const bt: string | undefined = b.time;
  const ta = at !== undefined && at.length > 0
    ? at.substring(0, 5) : PERIOD_SLOTS[a.from - 1].substring(0, 5);
  const tb = bt !== undefined && bt.length > 0
    ? bt.substring(0, 5) : PERIOD_SLOTS[b.from - 1].substring(0, 5);
  if (ta < tb) {
    return -1;
  }
  if (ta > tb) {
    return 1;
  }
  return 0;
}

// 课表序列化（9-17 夜·图形化编辑器）：条目 → 解析器认的文本格式（周一 1-2 高数；3-4 英语）。
// 每天一行、按开始时间排序；直写时间条目按 `HH:MM-HH:MM 标题` 原样回写；
// 空名条目跳过（没落格的草稿不落盘）；空课表输出空串——链路零改动。
function serializeTimetable(entries: TtEntry[]): string {
  const lines: string[] = [];
  for (let d = 0; d < 7; d++) {
    const day: TtEntry[] = [];
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].dow === d && entries[i].title.trim().length > 0) {
        day.push(entries[i]);
      }
    }
    if (day.length === 0) {
      continue;
    }
    day.sort(ttEntryCmp);
    const segs: string[] = [];
    for (let i = 0; i < day.length; i++) {
      const segTime: string | undefined = day[i].time;
      if (segTime !== undefined && segTime.length > 0) {
        segs.push(segTime + ' ' + day[i].title);   // 9-18 直写时间档原样回写（编辑器文本往返不丢）
      } else {
        segs.push(day[i].from + '-' + day[i].to + ' ' + day[i].title);
      }
    }
    lines.push(WEEK_CN[d] + ' ' + segs.join('；'));
  }
  return lines.join('\n');
}

// ─────── KB-TIME（9-18）按时间录入：时间模式纯函数 ───────
// 「HH:MM」→ 零点起分钟数（只喂自家生成的两字符段）
function ttMin(t: string): number {
  return ((t.charCodeAt(0) - 48) * 10 + (t.charCodeAt(1) - 48)) * 60
    + (t.charCodeAt(3) - 48) * 10 + (t.charCodeAt(4) - 48);
}

// 分钟数 → 「HH:MM」（补零借正典区的 pad2）
function ttHHMM(minute: number): string {
  return pad2(Math.floor(minute / 60)) + ':' + pad2(minute % 60);
}

const TT_TIME_CAP: number = 23 * 60 + 55;   // 时间控件天花板 23:55：分一次走 5 格，这是最后一格

// 走一步（±5 分钟 / ±1 小时），钳在 00:00~23:55：
// 跨位自动进位（08:55+5=09:00、08:00−5=07:55），顶到边就停住——UI 只产 24 小时制合法值
function ttStep(t: string, deltaMin: number): string {
  let v = ttMin(t) + deltaMin;
  if (v < 0) {
    v = 0;
  }
  if (v > TT_TIME_CAP) {
    v = TT_TIME_CAP;
  }
  return ttHHMM(v);
}

// 时间 → 最接近的正典节次：起、止各按最近时刻找（精确匹配差 0，自然胜出）；
// 结果钳在 1~13，起晚于止就收成单节——绝不越界、绝不反向
function ttClosestPeriod(t1: string, t2: string): number[] {
  let from = 1;
  let to = 1;
  let d1Best = 100000;   // 一天最多 1440 分钟，初值给够大
  let d2Best = 100000;
  for (let i = 0; i < PERIOD_SLOTS.length; i++) {
    const ss = PERIOD_SLOTS[i].split('-');
    const d1 = Math.abs(ttMin(ss[0]) - ttMin(t1));
    if (d1 < d1Best) {
      d1Best = d1;
      from = i + 1;
    }
    const d2 = Math.abs(ttMin(ss[1]) - ttMin(t2));
    if (d2 < d2Best) {
      d2Best = d2;
      to = i + 1;
    }
  }
  if (to < from) {
    to = from;
  }
  return [from, to];
}
// #endregion CAL-02 沙盘转译区

@Entry
@Component
struct Index {
  // ── 夜间模式（9-12 家主令）：关/开/跟随系统，AppStorage 持久化。
  // 跟随系统 = mediaquery 监听系统深色模式（sysDark 由 aboutToAppear 的监听器维护）──
  @StorageProp('nightPref') nightPref: string = 'auto';
  private mqListener: mediaquery.MediaQueryListener | undefined = undefined;
  @State pendingThinkKey: string = '';   // send 时挂的「叫姐姐中…」占位卡 key（thinking 事件来复用）
  // 9-18 修复批八（APP2-02）：当前未封口思考卡的 key（两路创建都记：beginThinking 的 thinkN 占位卡、
  // SSE thinking 事件新开的 kN 卡）——异常收尾时按它精确清，不再按 key 前缀扫（扫不到 kN 卡会留僵尸）
  private liveThinkKey: string = '';
  // FE3-04（9-23）：本轮未收尾的流式正文气泡 key——流没收 done 时 catch 里先摘半截再对账
  private liveReplyKey: string = '';
  // 夜下取色：色值在 NIGHT_MAP 里就换夜装，查不到原样——一个函数，全屋换灯。
  // pref 与系统色模式变化都会触发整树重渲染，色函数跟着重算。
  private dk(c: string): string {
    const dark: boolean = this.nightPref === 'on'
      || (this.nightPref === 'auto' && (AppStorage.get<boolean>('sysDark') ?? false));
    if (!dark) {
      return c;
    }
    const n: string | undefined = NIGHT_MAP[c];
    return n === undefined ? c : n;
  }

  @State chatData: ChatDataSource = new ChatDataSource();   // FE-02：LazyForEach 数据源（原 messages 数组收编）
  @State inputText: string = '';
  @State sending: boolean = false;
  @State pendingImage: string = '';   // 拍好待发送的照片 dataURL
  // ── FE-02 二批（9-13）──
  @State booting: boolean = true;             // 冷启动搬运态（loadHistory 落地就散）
  @State bootDotOn: boolean = false;          // 「正把家搬出来…」呼吸点
  @State chatAwayFromBottom: boolean = false; // 列表离开底部 → ⬇ 浮钮
  // ── 聊天全量浏览（9-23 V-1）：上翻/下翻/按日期跳转（服务端配套下一批；旧 server 无 has_more=闸不开）──
  @State histPaging: boolean = false;        // 服务端支持分页才开翻页闸
  @State histHasMore: boolean = false;       // 更早还有没有（false+开闸 → 顶行「家史的第一天」）
  @State histLoadingOlder: boolean = false;  // 上翻取数中（busy 闸，也当顶行提示）
  @State histLoadingNewer: boolean = false;  // 下翻续载中（跳转后往今天走；静默）
  @State histJumping: boolean = false;       // FE3-07（9-23）：日期跳转取数中（独立态+专属文案，不借上翻的）
  private histOldestThrough: string = '';    // 最旧窗口的 through（上翻：through=最旧日-1 —— 即游标 -3 天）
  private histNewestThrough: string = '';    // 最新窗口的 through（下翻：+3 天，封顶今天）
  private histEverScrolled: boolean = false; // 列表被真人翻过才允许触顶/触底自动翻页（首帧闸）
  @State imgPreviewUrl: string = '';          // 点图看大图（非空=全屏查看层开着）
  @State imgErrKeys: string[] = [];           // FE3-08（9-23）：取不到的图 URL 记账——气泡/大图显示占位文案
  private bootDotTimer: number = -1;
  // ── 上下文面板 ──
  @State panelOpen: boolean = false;
  @State lintelText: string = '';     // FE-02 门楣：今天日记首句，取不到自动隐藏
  @State stNow: string = '—';
  @State stWeather: string = '—';
  @State stPlace: string = '—';
  @State stLocTime: string = '';
  @State stChats: string = '—';
  @State stPromise: string = '—';
  @State stServer: string = '—';   // 9-4 自由发挥包：server 心电图行
  @State stGarden: string = '—';   // 9-17 夜：Garden 状态行（耳朵在岗 + 今日园子动静）
  @State stWalk: string = '';      // 9-23 B2-2：散步状态条（''=整行不出，旧 server 兼容）
  @State stLetter: string = '—';   // 9-18：最近一条来信指纹行（输入留痕可视化）
  @State stWhyNow: string = '';    // 9-18 #15：想念仪表行（''=不显示；旧 server 没这键）
  @State stThreads: string = '';   // 9-26：线头盒行（''=不显示；旧 server 没这键）
  @State stState: string = '';     // 9-26：她此刻行（只用服务端给的人话句）
  @State stLedger: string = '';    // 9-26 W2：家里两本账的一行人话
  // 9-23 能上批 c：对账观测三行（obs_7d 十键→人话；''=不出行，键缺/全 0 都不出）
  @State stObs1: string = '';
  @State stObs2: string = '';
  @State stObs3: string = '';
  @State stBridgeUp: boolean = false;   // 9-18 优化批二：耳朵在岗与否（拉桥按钮显隐）
  @State bridgeBusy: boolean = false;   // 9-18：拉桥进行中（防连点）
  @State bridgeMsg: string = '';        // 9-18：拉桥结果一句
  @State stFav: string = '—';      // 9-4 自由发挥包：收藏夹行
  @State asleep: boolean = false;
  @State goodnightMsg: string = '';
  @State goodnightBusy: boolean = false;
  // ── 功能分页（9-9 晚：每个功能一块专属界面，底部 Tabs） ──
  @State pageIdx: number = 0;   // 0 客厅 / 1 日常 / 2 书房 / 3 设置（LAY-12，9-23 订正过期注释）
  // ── 打卡页（工单 9-1-#2） ──
  @State checkinItems: CheckinItem[] = [];
  @State checkedToday: number[] = [];   // 今日已打卡的 item_id
  @State checkinMsg: string = '';
  @State monthItems: MonthCheckinItem[] = [];   // CHECKIN-2（9-13）：当月月视图（连续🔥/热力图取数）
  @State checkinDetailId: number = -1;          // CHECKIN-2：项详情二级态（-1=列表，>=0=某 item）
  @State checkinBusy: boolean = false;          // 9-18 App深搜修（DS-05）：打卡防连点（xgBusy 家风）
  private checkinTapTs: number = 0;             // LAY-07（9-23）：打卡按钮落点记账——防整行点击把详情顺带打开
  // ── outbox 待发队列（工单 9-1-#2） ──
  @State outboxCount: number = 0;
  @State outboxFlushing: boolean = false;   // 补发期间标题栏亮「补发中…」（9-1-#3）
  private outboxBusy: boolean = false;
  private outboxRetry: number = 0;          // 退避重试计数：5s、15s 各一次（9-1-#3）
  private netConn?: connection.NetConnection;
  @State safeTopPad: number = 28;           // 打卡页避让状态栏（9-1-#3，全屏模态不吃系统默认安全区）
  @State safeLeftPad: number = 0;           // FE-02：横屏时挖孔在侧边，情绪河全屏要避让左右
  // ── 思考链查看（9-1-#4） ──
  @State thinkingOpen: boolean = false;
  @State thinkingText: string = '';
  private thinkingCache: Map<string, string> = new Map();   // key=气泡 key，本轮新回复直接进缓存
  // ── 发文件（9-1-#8 刀2） ──
  @State pendingFileName: string = '';
  private pendingFileContent: string = '';   // ≤32KB 全文，不进 State
  @State attachOpen: boolean = false;        // 「＋」附件面板展开/折叠（9-1 晚定）
  // ── 设置页（9-1-#8 刀3） ──
  @State currentBase: string = '';           // 空 = 默认 Windows（node）门牌
  @State customBase: string = '';
  @State serverTestMsg: string = '';
  // ── 心情页（9-9 心情曲线 v2） ──
  @State moodSel: string = '';               // 选中的情绪词（''=未选）
  @State moodIntensity: number = 0;          // 选中的浓度 1~5（0=未选）
  @State moodNote: string = '';
  @State moodMsg: string = '';
  @State moodBusy: boolean = false;
  @State moodMarks: MoodPoint[] = [];        // 情绪河取数（近 40 天，三视图取用）
  @State riverFullOpen: boolean = false;     // 情绪河横屏全看（9-9 晚）：打开即切横屏，关闭回竖屏
  @State riverView: string = '周';           // RIVER-3（9-10）：日 / 周 / 月 三视图
  @State tappedIdx: number = -1;             // RIVER-3：点中的墨点序号（-1=没点），弹当时记了什么
  private riverDots: RiverDot[] = [];        // 最近一次绘制的墨点坐标缓存（点看详情用）
  // ── 家主信箱（9-9）：小乖写信给姐姐 ──
  @State letterText: string = '';
  @State letterMsg: string = '';
  @State letterBusy: boolean = false;
  @State stLetters: number = 0;              // 面板信箱行：未读来信数
  @State stLonging: number = -1;             // 引擎仪表（9-10）：她的想念值 0~1，-1=没取到
  @State stFacts: string = '';               // 引擎仪表（9-10）：Seline 事实句
  @State logsText: string = '';              // 工地日志（9-12）：server 日志尾巴，看工具有没有真调
  @State logsOpen: boolean = false;          // 工地日志全屏页（9-13 家主令：拉日志开界面）
  @State timetableDraft: string = '';        // CAL-02（9-13）：我的课表（存储仍是文本，编辑走图形化）
  @State timetableMsg: string = '';          // 课表保存校验结果（N 行懂了、M 行没看懂）
  // KB-EDIT（9-17 夜·课表图形化编辑器）：周网格点选编课，保存时序列化回原文本格式
  @State kbEditOpen: boolean = false;        // 编辑器全屏开关
  @State kbEntries: TtEntry[] = [];          // 编辑中的全周条目
  @State kbSel: number = -1;                 // 正在编辑的条目下标（-1=没选）
  @State kbName: string = '';                // 编辑条：课名
  @State kbFrom: number = 1;                 // 编辑条：起节
  @State kbTo: number = 2;                   // 编辑条：止节
  @State kbTimeMode: boolean = false;        // 编辑条模式（9-18）：false=按节次，true=按时间（课外活动那档）
  @State kbTFrom: string = '08:00';          // 时间模式：起点 HH:MM
  @State kbTTo: string = '09:40';            // 时间模式：终点 HH:MM
  // 9-18 修复批八（APP2-01）：打开编辑器时没看懂的行——界面列出来、保存时原样拼回，
  // 编辑器只管它看得懂的条目，坏行不许被它无声抹掉（parseTimetable 的「不许静默吞」口径）
  @State kbBadLines: string[] = [];
  @State logsBusy: boolean = false;
  // ── 日记馆（HALL-01，9-10）──
  @State hallShelf: string = '姐姐';         // 当前展开的格（数据键）：姐姐 / 小乖 / 两封信
  @State hallBrowse: string = '';            // 9-12 晚：''=书架陈列首页，非空=已进某格看全文
  @State hallBooks: BookShelf[] = [];        // 共读书架（9-12）
  @State markBook: string = '';              // 共读批注表单：书名/位置/正文
  @State markLoc: string = '';
  @State markText: string = '';
  @State markBusy: boolean = false;
  // ── 阅读器（9-12 下午重做：导入电子书一起看）──
  @State readingOpen: boolean = false;       // 阅读器全屏（bindContentCover）
  @State readBook: BookShelf | null = null;  // 正在读的卷
  @State readParas: string[] = [];           // 全文按空行切段
  @State readSelPara: number = -1;           // 点中的段落（弹批注框）
  @State readParaMark: string = '';          // 批注输入
  @State readBusy: boolean = false;
  @State bookImportTitle: string = '';       // 导入表单
  @State bookImportAuthor: string = '';
  @State bookImportBusy: boolean = false;
  @State bookImportMsg: string = '';
  // ── 小乖亲笔信编辑（9-12 家主令「我的信选着改」）──
  @State xgEditOpen: boolean = false;
  @State xgEditText: string = '';
  @State xgBusy: boolean = false;
  @State statsLine: string = '';       // 咱家的账本（9-12 晚）：一行总账文案
  @State statsLoaded: boolean = false;
  private statsFetchedAt: number = 0;   // 9-26：上次取账时间（时间闸，5 分钟内不重取）
  // 9-23 B2-1：账本全屏页（点卡进；卡片老路不动，新键只在全屏页用）
  @State statsOpen: boolean = false;
  @State statsData: StatsResp | null = null;   // 账本页原始数据（含新四键）
  @State statsFullBusy: boolean = false;       // 账本页取数中（防连点）
  @State statsFullMsg: string = '';            // 账本页一句失败话
  @State hallEntries: HallEntry[] = [];      // 馆内条目（新到旧）
  @State hallTitle: string = '';
  @State hallText: string = '';
  @State hallMsg: string = '';
  @State hallBusy: boolean = false;
  // ── FE-02 ①她的独处格（9-13）──
  @State tracesList: TraceItem[] = [];     // 她的独处痕迹（Garden her_traces，新到旧）
  // ── 档案馆（9-23 V-2「全都看得见」）──
  @State archiveOpen: boolean = false;     // 全屏页开关
  @State archBusy: boolean = false;        // 列表取数中
  @State archMsg: string = '';             // 没开门/取数失败一句
  @State archItems: ArchiveItem[] = [];    // /api/archive 条（服务端下一批）
  @State archCards: CardGroup[] = [];      // /api/cards 四馆正典（现成）
  @State archDocTitle: string = '';        // 非空=阅读态（卷名/卡题）
  @State archDocText: string = '';
  private archDocSeq: number = 0;          // FE3-03（9-23）：开卷在途序号——连点两卷只认最后一卷的回包
  // ── 9-23 能上批 a：📷 照片墙（收藏夹只读画廊）──
  @State favOpen: boolean = false;
  @State favBusy: boolean = false;
  @State favMsg: string = '';
  @State favPhotos: string[] = [];
  // ── 9-23 能上批 b：🧱 门牌墙（她每天开场读的）──
  @State wallOpen: boolean = false;
  @State wallBusy: boolean = false;
  @State wallMsg: string = '';
  @State wallPins: WallPin[] = [];
  // ── 9-23 能上批 d：🗂 周报阅读器（待审/已入库，只读）──
  @State repOpen: boolean = false;
  @State repBusy: boolean = false;
  @State repMsg: string = '';
  @State repItems: LibReportItem[] = [];
  @State repTab: string = '待审';          // 顶部 chips：待审 / 已入库
  @State repDocId: number = -1;            // >=0=阅读态（第 id 份）
  private repDocSeq: number = 0;           // RV-03b（9-23 小修批）：开卷在途序号——连点两份只认最后一份的回包
  @State repDocTitle: string = '';
  @State repDocStatus: string = '';
  @State repDocText: string = '';
  @State traceOpenId: number = -1;         // 点开的行（trace 见全文）
  @State traceMsg: string = '';            // 取数失败一句（诚实，不装空）
  // ── 姐姐思考中 ──
  @State thinkingSec: number = 0;
  @State thinkPeek: boolean = false;         // 💭 默认折叠（9-9）：流式思考点一下才偷看
  private thinkingOn: boolean = false;
  private locPermAsked: boolean = false;
  private scroller: Scroller = new Scroller();
  private keySeq: number = 0;
  private panelTimer: number = -1;
  private thinkTimer: number = -1;
  private statusTimer: number = -1;   // 9-2 #12：常开 60s 节律（status + outbox 新信）
  private notifSeq: number = 100;     // 本地通知 id 自增

  aboutToAppear(): void {
    // 9-1-#8 刀3：先读门牌（设置页换过的存 preferences），再拉数据——保证用当前生效地址
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      const saved = (prefs.getSync('server_base', '') as string).trim();
      if (saved) {
        applyServerBase(saved);
        this.currentBase = saved;
      }
      // 9-12：夜间模式偏好（关/开/跟随系统）
      const night = (prefs.getSync('night_pref', 'auto') as string).trim();
      if (night !== '') {
        this.nightPref = night;
        AppStorage.setOrCreate('nightPref', night);
      }
      // CAL-02（9-13）：课表原文（存过就读回来当编辑框初值；上报也认这份）
      this.timetableDraft = (prefs.getSync('timetable_text', '') as string);
    } catch (err) {
      // 读不到就用默认门牌
    }
    // 跟随系统：监听系统深色模式，AppStorage.sysDark 供 dk() 取用
    try {
      this.mqListener = mediaquery.matchMediaSync('(dark-mode: true)');
      AppStorage.setOrCreate('sysDark', this.mqListener.matches);
      this.mqListener.on('change', (res: mediaquery.MediaQueryResult) => {
        AppStorage.setOrCreate('sysDark', res.matches as boolean);
      });
    } catch (err) {
      AppStorage.setOrCreate('sysDark', false);
    }
    this.bootSeq();           // 历史 → 开门有信（有信就挂成姐姐气泡）
    this.fetchStatus();
    this.outboxCount = this.loadOutbox().length;
    this.flushOutbox();       // 打开 app 时按序补发
    this.watchNetRecovery();  // 网络恢复时按序补发
    this.maybeReportSchedule(true);   // CAL-01（9-13）：每天首次进入顺手报一次今天日程（失败静默）
    // 9-2 #12：常开 60s 节律——status 顺手拉，outbox 新信来了挂气泡+弹本地通知
    this.statusTimer = setInterval(() => {
      this.fetchStatus();
      this.fetchOutboxLetters(true);
      // 9-9 离线加固：退避只有 5s/15s 两跳，之后由 60s 节律兜底重试（app 开着就一直试）
      if (this.loadOutbox().length > 0) {
        this.flushOutbox();
      }
    }, 60000);
    // 9-1-#7 v3：提醒功能已移除，顺手清掉旧台账键（一次性，不存在也无害）
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      prefs.deleteSync('reminderIds');
      prefs.flushSync();
    } catch (err) {
    }
    // 全屏模态不吃系统默认安全区（官方姿势：手动查避让区，getWindowAvoidArea）
    // FE-02：顺手量左右——横屏全看时居中挖孔转到侧边，左右也要让
    try {
      window.getLastWindow(getContext(this)).then((win) => {
        const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.safeTopPad = px2vp(area.topRect.height);
        this.safeLeftPad = px2vp(area.leftRect.width);
      });
    } catch (err) {
      // 拿不到就用默认 28
    }
  }

  aboutToDisappear(): void {
    if (this.panelTimer >= 0) {
      clearInterval(this.panelTimer);
      this.panelTimer = -1;
    }
    if (this.statusTimer >= 0) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    if (this.thinkTimer >= 0) {
      clearInterval(this.thinkTimer);
      this.thinkTimer = -1;
    }
    if (this.netConn) {
      try {
        this.netConn.unregister(() => {
        });
      } catch (err) {
        // 退订失败无碍
      }
      this.netConn = undefined;
    }
  }

  build() {
    Column() {
      // 全局顶栏：标题 + 姐姐状态 + 待发提示 + 刷新（各分页共用）
      Row({ space: 8 }) {
        Text('咱家·林宁')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
        Text(this.asleep ? '☾ 睡了' : '● 醒着')
          .fontSize(FS_AUX)
          .fontColor(this.asleep ? this.dk(C_TEXT_4) : this.dk(C_OK))
        if (this.outboxFlushing) {
          Text('· 补发中…')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_ACCENT))
        } else if (this.outboxCount > 0) {
          Text(`· ${this.outboxCount} 条待发`)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_ACCENT))
        }
        Blank()
        // 9-24 家主令：📅 只在客厅（pageIdx===0）显现，其它页签不显示
        if (this.pageIdx === 0) {
          // 9-23 V-1 家主令：📅 按日期跳转——挑一天，载入该日窗口并滚到该日首条
          Button() {
            Text('📅')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_5))
          }
            .width(40)
            .height(40)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              // LAY-04（9-23）：📅 只作用于客厅——在别的页先切回客厅再开跳转，不再"点了没反应"
              if (this.pageIdx !== 0) {
                this.pageIdx = 0;
              }
              this.openDateJump();
            })
        }
        // 刷新小图标：立即重拉 /api/status 与面板数据，不打扰定时刷新
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(FS_SUB)
            .fontColor([this.dk(C_TEXT_5)])
        }
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.fetchStatus();
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 12, bottom: 8 })
      .backgroundColor(this.dk(C_PANEL))

      // 四块专属界面：客厅 / 日常（打卡+心情） / 书房（日记馆+共读+信箱） / 设置
      //（9-12 家主令：心情+打卡合体成日常，日记馆+写信合体成书房）
      Tabs({ barPosition: BarPosition.End, index: this.pageIdx }) {
        TabContent() {
          this.ChatView()
        }
        .tabBar(this.TabLabel('💬', '客厅', 0))

        TabContent() {
          this.DailyPage()
        }
        .tabBar(this.TabLabel('🌤', '日常', 1))

        TabContent() {
          this.HallPage()
        }
        .tabBar(this.TabLabel('📖', '书房', 2))

        TabContent() {
          this.SettingsPage()
        }
        .tabBar(this.TabLabel('⚙', '设置', 3))
      }
      .layoutWeight(1)
      .width('100%')
      .barHeight(54)
      .backgroundColor(this.dk(C_BG))
      .onChange((idx: number) => {
        this.pageIdx = idx;
        // 切到哪个页就顺手刷新哪个页的数据
        if (idx === 1) {
          this.fetchCheckinData();
          this.fetchMoods();
        } else if (idx === 2) {
          this.fetchHall();
          this.fetchStatus();
        } else if (idx === 3) {
          this.fetchStatus();
          this.fetchStats();
        }
        // 9-17 夜：切页淡入撤（家主「闪两下，不知道有什么用」）——整页先透明再淡回，
        // 观感是"闪"不是"淡"；删掉后切页干净利落。数据刷新照旧。
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.dk(C_BG))
    .bindContentCover(this.thinkingOpen || this.riverFullOpen || this.readingOpen || this.logsOpen
      || this.statsOpen || this.archiveOpen || this.favOpen || this.wallOpen || this.repOpen
      || this.imgPreviewUrl !== '' || this.xgEditOpen || this.kbEditOpen, this.CoverHub, {
      // 系统返回键/侧滑也会走这里：横屏全看被返回键关掉时，顺手把方向转回竖屏
      onWillDismiss: (action: DismissContentCoverAction) => {
        if (this.riverFullOpen) {
          this.closeRiverFull();
        } else if (this.readingOpen) {
          this.closeReader();
        } else if (this.logsOpen) {
          this.logsOpen = false;
        } else if (this.statsOpen) {
          this.statsOpen = false;   // 9-23 B2-1：返回键关账本页
        } else if (this.archiveOpen) {
          // 9-23 V-2：返回键——阅读态先退回列表，列表态再关页
          if (this.archDocTitle !== '') {
            this.archDocTitle = '';
            this.archDocText = '';
          } else {
            this.archiveOpen = false;
          }
        } else if (this.favOpen && this.imgPreviewUrl === '') {
          this.favOpen = false;   // 9-23 能上批 a：返回键关照照片墙
        } else if (this.imgPreviewUrl !== '') {
          // 9-23 能上批 a：墙里点开的大图层——返回键先退大图、再退墙（与 CoverHub 同序）
          this.imgPreviewUrl = '';
        } else if (this.wallOpen) {
          this.wallOpen = false;  // 9-23 能上批 b：门牌墙
        } else if (this.repOpen) {
          // 9-23 能上批 d：周报——阅读态先退回列表，列表态再关页（照档案馆家风）
          if (this.repDocId >= 0) {
            this.repDocId = -1;
            this.repDocTitle = '';
            this.repDocText = '';
            this.repDocStatus = '';
          } else {
            this.repOpen = false;
          }
        } else if (this.xgEditOpen) {
          this.xgEditOpen = false;   // 9-17 夜：信编辑全屏——关闭=放弃草稿
          this.xgEditText = '';
        } else if (this.kbEditOpen) {
          this.kbEditOpen = false;   // 9-17 夜：课表编辑器——关闭=放弃本次编辑
        } else {
          this.thinkingOpen = false;
        }
        action.dismiss();
      }
    })
  }

  // 底部导航标签：选中加粗上色
  @Builder
  TabLabel(icon: string, label: string, idx: number) {
    Column({ space: 2 }) {
      Text(icon)
        .fontSize(FS_BODY)
      Text(label)
        .fontSize(FS_AUX)
        .fontWeight(this.pageIdx === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.pageIdx === idx ? this.dk(C_ACCENT) : this.dk(C_TEXT_4))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  // LAY-02（9-23 布局批）：晚安按钮抽成 Builder（40vp，样式随家）。
  // 9-24 家主令：删去输入栏上方那枚常驻（与面板内重复），唯一入口=上下文面板内；LAY-02 原案留档。
  @Builder
  GoodnightBtn() {
    Button('🌙 熄灯说晚安')
      .fontSize(FS_SUB)
      .height(40)
      .fontColor(this.dk(C_ACCENT))
      .backgroundColor(this.dk(C_BG))
      .border({ width: 1, color: this.dk(C_ACCENT) })
      .borderRadius(R_PILL)
      .enabled(!this.goodnightBusy)
      .margin({ top: 4 })
      .stateStyles({ pressed: pressDim, normal: pressFull })
      .onClick(() => {
        this.confirmGoodnight();   // FE-02：先确认再熄灯
      })
  }

  // ── 客厅：聊天主界面（上下文面板 + 消息流 + 输入栏） ──
  @Builder
  ChatView() {
    Column() {
      // 面板开关行：点一下展开实时上下文
      Row() {
        Text('家是记忆库，这里是客厅')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
        Blank()
        Text(this.panelOpen ? '收起 ▴' : '▾ 上下文')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .constraintSize({ minHeight: 40 })   // LAY-03/07（9-23）：触摸目标补到 ≥40vp
      .backgroundColor(this.dk(C_PANEL))
      .onClick(() => {
        this.togglePanel();
      })

      // 门楣（FE-02 要求7）：今天日记的首句挂在客厅门口，取不到自动隐藏
      if (this.lintelText !== '') {
        Row() {
          Text(this.lintelText)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: M_PAGE, right: M_PAGE, top: 5, bottom: 5 })
        .backgroundColor(this.dk(C_PANEL))
      }

      // 实时上下文面板（默认收起）
      // LAY-03（9-23）：面板最高 260vp、内容内滚——十几行全展开不再挤扁消息区
      if (this.panelOpen) {
        Scroll() {
        Column({ space: 6 }) {
          Text(`现在：${this.stNow}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Text(`天气：${this.stWeather}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Text(`地点：${this.stPlace}${this.stLocTime ? `（${this.stLocTime} 上报）` : ''}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Text(`今天消息：${this.stChats} 条 · 姐姐${this.asleep ? '睡了' : '醒着'}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Text(`明日约定：${this.stPromise}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Text(`server：${this.stServer} · 收藏夹 ${this.stFav} 张`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          Row({ space: 8 }) {
            Text(`Garden：${this.stGarden}`)
              .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
              .layoutWeight(1)
            if (!this.stBridgeUp) {
              Text(this.bridgeBusy ? '拉起中…' : '🛠 拉起耳朵')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_ACCENT))
                .padding({ left: 10, right: 4, top: 6, bottom: 6 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.raiseBridge();
                })
            }
          }
          .width('100%')
          // 9-23 B2-2：散步状态条（键缺/null 整行不出）
          if (this.stWalk !== '') {
            Text(this.stWalk)
              .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3)).width('100%')
          }
          // 9-23 终包：耳朵状态并进老 Garden 行（stGarden 里带 ✓/未挂）——不再单开一行，别重复
          if (this.bridgeMsg !== '') {
            Text(this.bridgeMsg)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
              .width('100%')
          }
          // 9-18 #15·想念仪表：引擎刚才在想什么（读数行，紧挨最近来信；没数据整行不出）
          if (this.stWhyNow !== '') {
            Text(this.stWhyNow)
              .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3)).width('100%')
          }
          Text(`最近来信：${this.stLetter}`)
            .fontSize(FS_AUX).fontColor(this.dk(C_TEXT_3))
          if (this.stLetters > 0) {
            Text(`信箱：${this.stLetters} 封待她读`)
              .fontSize(FS_AUX).fontColor(this.dk(C_ACCENT))
          }
          if (this.goodnightMsg) {
            Text(this.goodnightMsg)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_2))
              .lineHeight(18)
          }
          this.GoodnightBtn()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: M_PAGE, right: M_PAGE, top: 8, bottom: 10 })
        }
        .width('100%')
        .constraintSize({ maxHeight: 260 })
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .backgroundColor(this.dk(C_PANEL))
      }

      // 消息列表（FE-02 要求6：LazyForEach 懒加载——一屏一建，历史再多也不卡首屏）
      // FE-02 二批（9-13）：外套一层 Stack——冷启动「搬家」态居中、回到底部浮钮挂右下 ▽
      Stack({ alignContent: Alignment.Center }) {
        List({ space: 14, scroller: this.scroller }) {
          // 9-23 V-1：两枚顶行只做提示（不入数据源）——上翻中 / 已到源头
          // FE3-07（9-23）：日期跳转用独立态与专属文案，不再借「正在翻家史…」串台
          if (this.histJumping) {
            ListItem() {
              Text('—— 正在翻到那天… ——')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          } else if (this.histLoadingOlder) {
            ListItem() {
              Text('—— 正在翻家史… ——')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          } else if (this.histPaging && !this.histHasMore) {
            ListItem() {
              Text('—— 这是家史的第一天 ——')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
                .width('100%')
                .textAlign(TextAlign.Center)
            }
          }
          LazyForEach(this.chatData, (item: ChatItem) => {
            ListItem() {
              this.MsgBubble(item)
            }
          }, (item: ChatItem) => item.key)
        }
        .width('100%')
        .height('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 6 })
        // 9-23 V-1：前面前插老窗时，眼前这屏别被顶走（官方维持可视位置开关）
        .maintainVisibleContentPosition(true)
        .onScrollIndex((start: number, end: number) => {
          // 列表尾不可见 = 离开底部 → 浮钮出现；回到底部自动隐（被动监听，不碰懒加载/打字机滚动）
          this.chatAwayFromBottom = end < this.chatData.totalCount() - 1;
          if (start > 0) {
            this.histEverScrolled = true;   // V-1：人真在列表里翻过（首帧贴顶不算）
          }
        })
        .onReachStart(() => {
          // 9-23 V-1：滑到顶自动上翻一窗更早；起手就贴顶的首帧不拉（防布局期连环取全史）
          if (this.histEverScrolled) {
            this.loadOlderHistory();
          }
        })
        .onReachEnd(() => {
          // 9-23 V-1：滑到底自动续载更新的一窗（跳转后往今天走；平时已在今天=空转）
          if (this.histEverScrolled) {
            this.loadNewerHistory();
          }
        })

        // ⑤ 冷启动加载态：loadHistory 落地就散（成功/失败都散，失败走现有提示逻辑）
        if (this.booting && this.chatData.totalCount() === 0) {
          Column({ space: 10 }) {
            Text('正把家搬出来…')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_4))
            Text('●')
              .fontSize(10)
              .fontColor(this.dk(C_ACCENT))
              .opacity(this.bootDotOn ? 1 : 0.2)
          }
        }

        // ④ 回到底部浮钮：只浮钮吃点击，其余区域透传给列表，不抢手势
        if (this.chatAwayFromBottom && !this.booting) {
          Row() {
            Text('⬇')
              .fontSize(FS_BODY)
              .fontColor(this.dk(C_TEXT_2))
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.dk(C_CARD))
              .border({ width: 1, color: this.dk(C_DOT_BORDER) })
              .borderRadius(20)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.scrollToEnd();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Bottom)
          .padding({ right: 14, bottom: 10 })
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .layoutWeight(1)
      .width('100%')

      // 照片预览条：拍完暂存时出现，✕ 取消
      if (this.pendingImage) {
        Row({ space: 10 }) {
          Image(this.pendingImage)
            .height(48)
            .constraintSize({ maxWidth: 72 })
            .objectFit(ImageFit.Contain)
            .borderRadius(R_SM)
          Text('这张照片要一起发给姐姐')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_TEXT_3))
            .layoutWeight(1)
          Text('✕')
            .fontSize(FS_BODY)
            .fontColor(this.dk(C_TEXT_5))
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.pendingImage = '';
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })
        .backgroundColor(this.dk(C_PANEL))
      }

      // 附件预览条（9-1-#8 刀2）：选了文件暂存时出现，✕ 取消
      if (this.pendingFileName) {
        Row({ space: 10 }) {
          Text('📄')
            .fontSize(FS_TITLE)
          Text(this.pendingFileName)
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_TEXT_3))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('✕')
            .fontSize(FS_BODY)
            .fontColor(this.dk(C_TEXT_5))
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.pendingFileName = '';
              this.pendingFileContent = '';
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })
        .backgroundColor(this.dk(C_PANEL))
      }

      // 附件面板（9-1 晚定）：点「＋」展开，三个入口收这里；点任一项自动收起
      if (this.attachOpen) {
        Row({ space: 12 }) {
          Text('📷 拍照')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_TEXT))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.dk(C_BG))
            .borderRadius(R_XL)
            .onClick(() => {
              this.attachOpen = false;
              this.takePhoto();
            })
          Text('🖼 相册')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_TEXT))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.dk(C_BG))
            .borderRadius(R_XL)
            .onClick(() => {
              this.attachOpen = false;
              this.pickPhoto();
            })
          Text('📄 文件')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_TEXT))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor(this.dk(C_BG))
            .borderRadius(R_XL)
            .onClick(() => {
              this.attachOpen = false;
              this.pickFile();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })
        .backgroundColor(this.dk(C_PANEL))
      }

      // 底部输入栏
      Row({ space: 8 }) {
        // 「＋」一键收三入口（📷🖼📄 全在上面面板里），点一下展开/折叠
        Button() {
          Text(this.attachOpen ? '✕' : '＋')
            .fontSize(FS_TITLE)
            .fontColor(this.dk(C_ACCENT))
        }
          .width(44)
          .height(44)
          .backgroundColor(this.dk(C_PANEL))
          .border({ width: 1, color: this.dk(C_ACCENT) })
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.attachOpen = !this.attachOpen;
          })
        TextInput({ placeholder: '跟姐姐说点什么……', text: this.inputText })
          .layoutWeight(1)
          .height(44)
          .fontSize(FS_BODY)
          .backgroundColor(this.dk(C_WHITE))
          .borderRadius(R_PILL_XL)
          .padding({ left: 16, right: 16 })
          .onChange((v: string) => {
            this.inputText = v;
          })
          .onSubmit(() => {
            this.send();
          })
        Button(this.sending ? '…' : '发送')
          .height(44)
          .padding({ left: 18, right: 18 })
          .fontSize(FS_BODY)
          .backgroundColor(this.dk(C_ACCENT))
          .fontColor(this.dk(C_WHITE))
          .enabled(!this.sending)
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.send();
          })
      }
      .width('100%')
      .padding(10)
      .backgroundColor(this.dk(C_PANEL))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.dk(C_BG))
  }

  // 思考链全屏模态（单实例，避免多 cover 同挂一根互相顶掉）
  @Builder
  CoverHub() {
    if (this.thinkingOpen) {
      this.ThinkingPage()
    } else if (this.riverFullOpen) {
      this.RiverFullPage()
    } else if (this.readingOpen) {
      this.ReaderPage()
    } else if (this.logsOpen) {
      this.LogsPage()
    } else if (this.statsOpen) {
      this.StatsPage()          // 9-23 B2-1：账本全屏页
    } else if (this.archiveOpen) {
      this.ArchivePage()        // 9-23 V-2：档案馆全屏页
    } else if (this.favOpen && this.imgPreviewUrl === '') {
      this.PhotoWallPage()      // 9-23 能上批 a：照片墙（收藏夹只读画廊）
    } else if (this.imgPreviewUrl !== '') {
      // FE-02 ②：点图看大图；9-23 能上批 a——照片墙里点开的图也走这里，
      // 所以大图层要排在墙前面判：关掉大图后墙还在，不会把人甩回书架
      this.ImagePreviewPage()
    } else if (this.wallOpen) {
      this.WallPage()           // 9-23 能上批 b：门牌墙（她每天开场读的）
    } else if (this.repOpen) {
      this.ReportsPage()        // 9-23 能上批 d：周报阅读器（只读）
    } else if (this.xgEditOpen) {
      this.XgWordsEditPage()    // 9-17 夜：改这封信（全屏，替代原 120vp 内联小框）
    } else if (this.kbEditOpen) {
      this.KbEditPage()         // 9-17 夜：周课表图形化编辑器
    }
  }

  // ── 改这封信·全屏编辑（9-17 夜·家主令「改为全屏窗口，现在的展示不全」）──
  // 原本是 120vp 内联小框，600 字看不全；换全屏大文本域，保存仍走 saveXiaoguaiWords()。
  // 9-24：限额 600→2000（服务端同步放开）——全 App 的信编辑只此一条链，入口=书房两封信格那颗按钮。
  @Builder
  XgWordsEditPage() {
    Column({ space: 10 }) {
      Row() {
        Text('✎ 改这封信')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.xgEditOpen = false;
            this.xgEditText = '';
          })
      }
      .width('100%')
      Text('写你自己的开场信——不落笔就还是原样，旧版全留。')
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_4))
        .width('100%')
      TextArea({ placeholder: '写你自己的开场信……（≤2000 字，旧版全留）', text: this.xgEditText })
        .fontSize(FS_BODY)
        .lineHeight(26)
        .backgroundColor(this.dk(C_WHITE))
        .borderRadius(R_MD)
        .maxLength(2000)
        .layoutWeight(1)
        .width('100%')
        .onChange((v: string) => {
          this.xgEditText = v;
        })
      Row({ space: 8 }) {
        Text(`${this.xgEditText.length}/2000`)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
          .layoutWeight(1)
        Button('算了不改')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_TEXT_2))
          .backgroundColor(this.dk(C_CARD))
          .borderRadius(R_PILL)
          .onClick(() => {
            this.xgEditOpen = false;
            this.xgEditText = '';
          })
        Button(this.xgBusy ? '……' : '落笔，换成我的版本')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_WHITE))
          .backgroundColor(this.xgEditText.trim() !== '' && !this.xgBusy
            ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
          .borderRadius(R_PILL)
          .enabled(this.xgEditText.trim() !== '' && !this.xgBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.saveXiaoguaiWords();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: this.safeTopPad, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 周课表·图形化编辑器（9-17 夜·家主令「图形化添加课表，不要输入文字」）──
  // 7 天点选：点＋加课、点课程格子改课；保存时序列化回原文本格式（解析/上报链路零改动）。
  @Builder
  KbDayRow(d: number) {
    Column({ space: 4 }) {
      Row() {
        Text(WEEK_CN[d])
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .width(56)
        Blank()
        Text('＋ 加课')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 10, right: 4, top: 6, bottom: 6 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbAdd(d);
          })
      }
      .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.kbDayList(d), (t: TtEntry, k: number) => {
          Text(`${t.time !== undefined && t.time.length > 0 ? t.time : t.from + '-' + t.to} ${t.title === '' ? '新课…' : t.title}`)
            .fontSize(FS_AUX)
            .fontColor(t.title === '' ? this.dk(C_TEXT_4) : this.dk(C_ACCENT))
            .backgroundColor(this.dk(C_WHITE))
            .borderRadius(R_PILL)
            .border({ width: 1, color: this.dk(C_DOT_BORDER) })
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ right: 6, bottom: 6 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              const idx = this.kbIndexOf(d, k);
              if (idx >= 0) {
                this.kbPick(idx);
              }
            })
        }, (t: TtEntry, k: number) => `${d}-${k}-${t.title}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  // 时间模式的步进钮（KB-TIME，9-18）：时/分 × ± 各一枚，样式跟全屋小按钮一致
  @Builder
  KbTBtn(fromSide: boolean, hourStep: boolean, delta: number) {
    Text(delta > 0 ? '＋' : '−')
      .fontSize(FS_BODY)
      .fontColor(this.dk(C_ACCENT))
      .padding({ left: 10, right: 10, top: 2, bottom: 2 })
      .backgroundColor(this.dk(C_BG))
      .borderRadius(R_PILL)
      .stateStyles({ pressed: pressDim, normal: pressFull })
      .onClick(() => {
        this.kbTStep(fromSide, hourStep, delta);
      })
  }

  @Builder
  KbEditPage() {
    Column({ space: 8 }) {
      Row() {
        Text('📅 周课表')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbEditOpen = false;
          })
      }
      .width('100%')
      // 9-18 修复批八（APP2-01）：没看懂的行摆在明面上——保存时会原样拼回文本尾部，不动它们
      if (this.kbBadLines.length > 0) {
        Column({ space: 3 }) {
          Text(`${this.kbBadLines.length} 行没看懂（原样保留，保存时一起留着）：`)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
          ForEach(this.kbBadLines, (b: string) => {
            Text(b)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
              .width('100%')
          }, (b: string, i: number) => `kbBad${i}_${b}`)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
      }
      Scroll() {
        Column({ space: 10 }) {
          // 显示顺序：周一最上、周日收尾（下标仍是 getDay 规矩=周天0，只是铺排顺序换了，语义不动）
          ForEach([1, 2, 3, 4, 5, 6, 0], (d: number) => {
            this.KbDayRow(d)
          }, (d: number) => `${d}`)
        }
        .width('100%')
        .padding({ bottom: 6 })
      }
      .layoutWeight(1)
      if (this.kbSel >= 0 && this.kbSel < this.kbEntries.length) {
        Column({ space: 6 }) {
          Text(`编辑「${WEEK_CN[this.kbEntries[this.kbSel].dow]}」这一门`)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_2))
            .width('100%')
          TextInput({ placeholder: '课程名（地点可写在里面，如 高数 @十教）', text: this.kbName })
            .fontSize(FS_SUB)
            .backgroundColor(this.dk(C_WHITE))
            .borderRadius(R_MD)
            .width('100%')
            .onChange((v: string) => {
              this.kbName = v;
            })
          // 模式切换（KB-TIME，9-18）：按节次走正典 1~13；按时间直写 HH:MM（课外活动等不定节次的课）
          Row({ space: 8 }) {
            Text('按节次')
              .fontSize(FS_SUB)
              .fontColor(!this.kbTimeMode ? this.dk(C_WHITE) : this.dk(C_TEXT_2))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(R_PILL)
              .backgroundColor(!this.kbTimeMode ? this.dk(C_ACCENT) : this.dk(C_BG))
              .border({ width: 1, color: !this.kbTimeMode ? this.dk(C_ACCENT) : this.dk(C_DOT_BORDER) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbSetTimeMode(false);
              })
            Text('按时间')
              .fontSize(FS_SUB)
              .fontColor(this.kbTimeMode ? this.dk(C_WHITE) : this.dk(C_TEXT_2))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(R_PILL)
              .backgroundColor(this.kbTimeMode ? this.dk(C_ACCENT) : this.dk(C_BG))
              .border({ width: 1, color: this.kbTimeMode ? this.dk(C_ACCENT) : this.dk(C_DOT_BORDER) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbSetTimeMode(true);
              })
            Blank()
          }
          .width('100%')
          if (!this.kbTimeMode) {
            Row({ space: 6 }) {
              Text('从')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_3))
              Text('−')
                .fontSize(FS_BODY)
                .fontColor(this.dk(C_ACCENT))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(true, -1);
                })
              Text(`${this.kbFrom}`)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT))
              Text('＋')
                .fontSize(FS_BODY)
                .fontColor(this.dk(C_ACCENT))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(true, 1);
                })
              Text('到')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_3))
              Text('−')
                .fontSize(FS_BODY)
                .fontColor(this.dk(C_ACCENT))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(false, -1);
                })
              Text(`${this.kbTo}`)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT))
              Text('＋')
                .fontSize(FS_BODY)
                .fontColor(this.dk(C_ACCENT))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(false, 1);
                })
              Text(`${PERIOD_SLOTS[this.kbFrom - 1].split('-')[0]}~${PERIOD_SLOTS[this.kbTo - 1].split('-')[1]}`)
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          } else {
            Row({ space: 6 }) {
              Text('从')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_3))
              Text('时')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
              this.KbTBtn(true, true, -1)
              this.KbTBtn(true, true, 1)
              Text('分')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
              this.KbTBtn(true, false, -1)
              this.KbTBtn(true, false, 1)
              Text(this.kbTFrom)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            Row({ space: 6 }) {
              Text('到')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_3))
              Text('时')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
              this.KbTBtn(false, true, -1)
              this.KbTBtn(false, true, 1)
              Text('分')
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
              this.KbTBtn(false, false, -1)
              this.KbTBtn(false, false, 1)
              Text(this.kbTTo)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          }
          Row({ space: 8 }) {
            Button('删除这条')
              .fontSize(FS_SUB)
              .height(40)
              .fontColor(this.dk(C_TEXT_2))
              .backgroundColor(this.dk(C_BG))
              .border({ width: 1, color: this.dk(C_DOT_BORDER) })
              .borderRadius(R_PILL)
              .layoutWeight(1)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbDelete();
              })
            Button('落格（保存这条）')
              .fontSize(FS_SUB)
              .height(40)
              .fontColor(this.dk(C_WHITE))
              .backgroundColor(this.kbName.trim() !== '' ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
              .borderRadius(R_PILL)
              .enabled(this.kbName.trim() !== '')
              .layoutWeight(1)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbApply();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
      } else {
        Text('点课程格子改课，或点某天的「＋ 加课」。')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
          .width('100%')
      }
      Row({ space: 8 }) {
        Button('不改了')
          .fontSize(FS_SUB)
          .height(42)
          .fontColor(this.dk(C_TEXT_2))
          .backgroundColor(this.dk(C_CARD))
          .borderRadius(R_PILL)
          .layoutWeight(1)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbEditOpen = false;
          })
        Button('保存课表')
          .fontSize(FS_SUB)
          .height(42)
          .fontColor(this.dk(C_WHITE))
          .backgroundColor(this.dk(C_ACCENT))
          .borderRadius(R_PILL)
          .layoutWeight(1)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbSaveAll();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: this.safeTopPad, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 工地日志全屏页（9-13 家主令：拉日志开界面，不再内嵌设置页）──
  // 工具有没有真调，一页看尽；右上角可再拉一把刷新。
  @Builder
  LogsPage() {
    Column() {
      Row() {
        Text('📜 工地日志')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text(this.logsBusy ? '取日志中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.logsBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.fetchLogs();
          })
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.logsOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Text(this.logsBusy && !this.logsText ? '取日志中…' : (this.logsText || '（点右上角刷新拉取）'))
          .fontSize(FS_AUX)
          .fontFamily('monospace')
          .fontColor(this.dk(C_TEXT_2))
          .lineHeight(18)
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 共读阅读器（9-12 下午重做）：全屏翻书，段落旁两色墨迹，点段批注 ──
  @Builder
  ReaderPage() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text('✕')
          .fontSize(FS_BODY)
          .fontColor(this.dk(C_ACCENT))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.closeReader();
          })
        Text(this.readBook ? `《${(this.readBook as BookShelf).title}》` : '')
          .fontSize(FS_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.readBook ? `她读到 ${(this.readBook as BookShelf).pos_her ?? 0}` : '')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 4 })

      List({ space: 10 }) {
        ForEach(this.readParas, (p: string, i: number) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(p)
                .fontSize(FS_BODY)
                .lineHeight(26)
                .fontColor(this.dk(C_TEXT))
                .width('100%')
                .padding({ left: 4, right: 4 })
                .onClick(() => {
                  this.readSelPara = this.readSelPara === i ? -1 : i;
                  this.readParaMark = '';
                })
              // 这一段的批注（两个人的墨迹都挂着）
              ForEach(this.paraMarksOf(i), (mk: BookMark) => {
                Column({ space: 2 }) {
                  Text(`${mk.who === '姐姐' ? '👩 姐姐' : '🐱 我'}${mk.time === '' ? '' : ' · ' + mk.time}`)
                    .fontSize(FS_AUX)
                    .fontColor(mk.who === '姐姐' ? this.dk(C_ACCENT) : this.dk(C_TEXT_4))
                  Text(mk.text)
                    .fontSize(FS_SUB)
                    .fontColor(this.dk(C_TEXT_2))
                    .lineHeight(18)
                    .width('100%')
                }
                .padding(8)
                .backgroundColor(mk.who === '姐姐' ? this.dk(C_BG) : this.dk(C_CARD))
                .borderRadius(R_SM)
                .width('100%')
              }, (mk: BookMark) => `${mk.id}-${mk.text}`)
              // 点中的段：就地落笔
              if (this.readSelPara === i) {
                Row({ space: 8 }) {
                  TextInput({ placeholder: '在这段旁边落一笔……', text: this.readParaMark })
                    .fontSize(FS_SUB)
                    .backgroundColor(this.dk(C_WHITE))
                    .borderRadius(R_MD)
                    .layoutWeight(1)
                    .onChange((v: string) => {
                      this.readParaMark = v;
                    })
                  Button(this.readBusy ? '…' : '落笔')
                    .fontSize(FS_SUB)
                    .height(36)
                    .fontColor(this.dk(C_WHITE))
                    .backgroundColor(this.readParaMark.trim() !== '' && !this.readBusy
                      ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
                    .borderRadius(R_PILL)
                    .enabled(this.readParaMark.trim() !== '' && !this.readBusy)
                    .onClick(() => {
                      this.submitParaMark();
                    })
                }
                .width('100%')
              }
            }
            .width('100%')
          }
        }, (p: string, i: number) => `${i}-${p.length}`)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, bottom: 10 })
      .onScrollIndex((start: number) => {
        this.reportReadPos(start);
      })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    // LAY-01（9-23·P0 修复）：全屏模态不吃系统默认安全区——顶部避让照 ThinkingPage，
    // 横屏左右照 RiverFullPage（此前阅读器是全家唯一漏网的，「✕」与书名会被状态栏压住）
    .padding({ left: this.safeLeftPad, right: this.safeLeftPad, top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // 书脊色池：每本书按上架顺序取一色，架上看去像真的书排
  private bookSpineColors: string[] =
    ['#a86450', '#7a8a5a', '#5a6e8a', '#8a6e5a', '#6e5a8a', '#8a7a4a'];

  private bookSpineColor(i: number): string {
    return this.bookSpineColors[Math.abs(i) % this.bookSpineColors.length];
  }

  // 某段落的批注（阅读器渲染用）
  private paraMarksOf(i: number): BookMark[] {
    const bk = this.readBook;
    if (!bk) {
      return [];
    }
    const out: BookMark[] = [];
    for (const mk of (bk as BookShelf).marks) {
      if (mk.para === i) {
        out.push(mk);
      }
    }
    return out;
  }

  // 点中墨点弹的小卡（RIVER-3）：当时记了什么——词、浓度、谁的笔、备注
  @Builder
  RiverDotCard(p: MoodPoint) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Circle()
          .width(10)
          .height(10)
          .fill(p.type ? (this.moodColorOf(p.type) as ResourceColor) : MOOD_LEGACY_COLOR)
        Text(`${p.date.substring(5).replace('-', '/')} ${p.time} · ${this.moodNameOf(p.type) || '旧记分'} ×${p.score} · ${p.source}`)
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('✕')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_TEXT_4))
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.tappedIdx = -1;
          })
      }
      .width('100%')
      if (p.note) {
        Text(p.note)
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_TEXT_2))
          .lineHeight(18)
          .width('100%')
      }
    }
    .padding(12)
    .backgroundColor(this.dk(C_WHITE))
    .borderRadius(R_MD)
    .border({ width: 1, color: p.type ? (this.moodColorOf(p.type) as ResourceColor) : MOOD_LEGACY_COLOR })
    .margin(10)
    .width('92%')
  }

  // ── 情绪河·横屏全看（9-9 晚）：窗口已切横屏，2848px≈990vp 宽——墨点/日期/字全面放大。
  // 上下壳压到最薄（家主令：上下界面太大），空间全给河 ──
  @Builder
  RiverFullPage() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text('💗 情绪河')
          .fontSize(FS_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
        Text('十字星=他 · 五角星=她 · 捏合缩放 · 左右滑看过去 · 点星看当时')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
          .layoutWeight(1)
          .maxLines(1)
        Text('✕ 返回')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor(this.dk(C_BG))
          .border({ width: 1, color: this.dk(C_ACCENT) })
          .borderRadius(R_LG)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.closeRiverFull();
          })
      }
      .width('100%')

      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.moodFullCtx)
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(this.dk(C_PANEL))
          .borderRadius(R_LG)
          .onReady(() => {
            this.moodFullReady = true;
            this.drawRiverOn(this.moodFullCtx, true);
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.pinchStartWin = this.riverWin;
                })
                .onActionUpdate((event: PinchGestureEvent) => {
                  this.riverWin = Math.min(60, Math.max(0.5, this.pinchStartWin / (event.scale || 1)));
                  this.redrawRiver();
                }),
              PanGesture({ fingers: 1, distance: 8 })
                .onActionStart(() => {
                  this.panStartOff = this.riverOff;
                })
                .onActionUpdate((event: PanGestureEvent) => {
                  this.riverOff = Math.max(0, this.panStartOff - (event.offsetX || 0) / this.lastColW);
                  this.redrawRiver();
                }),
              TapGesture()
                .onAction((event: GestureEvent) => {
                  const tl = event.tapLocation;
                  if (tl) {
                    this.riverOnTouch(tl.x, tl.y, true);
                  }
                })
            )
          )
        if (this.tappedIdx >= 0 && this.tappedIdx < this.riverDots.length) {
          this.RiverDotCard(this.riverDots[this.tappedIdx].point)
        }
      }
      .layoutWeight(1)
      .width('100%')

      // 词表图例：哪种颜色是哪种心情（单行，够看就行，不抢河的地方）
      Row({ space: 10 }) {
        ForEach(MOOD_TYPES, (t: MoodTypeItem) => {
          Row({ space: 4 }) {
            Circle()
              .width(9)
              .height(9)
              .fill(t.color as ResourceColor)
            Text(t.name)
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_2))
          }
        }, (t: MoodTypeItem) => t.name)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Math.max(M_PAGE, this.safeLeftPad),
      right: Math.max(M_PAGE, this.safeLeftPad),
      top: this.safeTopPad + 2,
      bottom: 6
    })   // FE-02：横屏时居中挖孔转到侧边，左右按避让区让路
    .backgroundColor(this.dk(C_BG))
  }

  // ── 书房（9-12 晚 家主令「整合成一个书架，不是按钮切换」）：
  // 陈列首页——四块格子摆出来（姐姐的格/小乖的格/两封信/信箱）+ 共读木板书架，
  // 点格才进全文；不再是 chips 换页 ──
  @Builder
  HallPage() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        if (this.hallBrowse !== '') {
          Text('‹ 书架')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.dk(C_BG))
            .border({ width: 1, color: this.dk(C_ACCENT) })
            .borderRadius(R_LG)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.hallBrowse = '';
              this.fetchHall();   // 回陈列顺手刷书架
            })
        }
        Text(this.hallBrowse === '' ? '📖 书房' :
          (this.hallBrowse === '姐姐' ? '📖 姐姐的格' :
          (this.hallBrowse === '小乖' ? '📖 小乖的格' :
          (this.hallBrowse === '两封信' ? '✉ 两封信' :
          (this.hallBrowse === '她的独处' ? '🌙 她的独处' : '✉️ 信箱')))))
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')

      Scroll() {
      Column({ space: 12 }) {
      if (this.hallBrowse === '') {
        // ── 陈列：一格一块，点开才进全文 ──
        // 姐姐的格
        Row({ space: 10 }) {
          Text('👩')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('姐姐的格')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('她的正典日记——她写她的，你随时能翻')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('进格 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_ACCENT) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.hallBrowse = '姐姐';
          this.hallShelf = '姐姐';
          this.fetchHall();
        })

        // 小乖的格
        Row({ space: 10 }) {
          Text('🐱')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('小乖的格')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('你亲手投的日记——她开场就能看到')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('进格 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_OK) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.hallBrowse = '小乖';
          this.hallShelf = '小乖';
          this.fetchHall();
        })

        // 两封信：两张信封并排立在架上
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text('✉')
              .fontSize(FS_TITLE)
            Text('小乖的话')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_2))
          }
          .width(96)
          .height(84)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.dk(C_BG))
          .borderRadius(R_SM)
          .border({ width: 1, color: this.dk(C_DOT_BORDER) })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.hallBrowse = '两封信';
            this.hallShelf = '两封信';
            this.fetchHall();
          })
          Column({ space: 4 }) {
            Text('💌')
              .fontSize(FS_TITLE)
            Text('姐姐的话')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_ACCENT))
          }
          .width(96)
          .height(84)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.dk(C_BG))
          .borderRadius(R_SM)
          .border({ width: 1, color: this.dk(C_ACCENT) })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.hallBrowse = '两封信';
            this.hallShelf = '两封信';
            this.fetchHall();
          })
          Column({ space: 2 }) {
            Text('两封信')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('挂在咱家门楣上的那两封——她可以自己改她的')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .alignItems(VerticalAlign.Top)

        // 信箱
        Row({ space: 10 }) {
          Text('📮')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('信箱')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            // LAY-11（9-23）：未读 >0 才追加角标；没信就不摆「0 封」占地方
            Text(this.stLetters > 0
              ? `想说的话慢慢写 · ${this.stLetters} 封待她读`
              : '想说的话慢慢写')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('写信 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_DOT_BORDER) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.hallBrowse = '信箱';
        })

        // 她的独处（FE-02 ①，9-13）：Garden 的痕迹——静默、心事、来找过他；安静也是她在过日子
        Row({ space: 10 }) {
          Text('🌙')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('她的独处')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('她一个人待着时留下的痕迹——静默、心事，和来找过你的时候')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('进格 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_ACCENT) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.hallBrowse = '她的独处';
          this.traceMsg = '';
          this.traceOpenId = -1;
          this.fetchTraces();
        })

        // 档案馆（9-23 V-2「全都看得见」）：卡片馆/周卷/旧家三卷/全档案续页/大事记卷——
        // 门口的格子，点开是全屏阅读页（服务端配套下一批，缺则诚实说没开门）
        Row({ space: 10 }) {
          Text('🗄')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('档案馆')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('卡片馆、周卷、旧家三卷、大事记——家里的老账都能翻')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('开门 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_DOT_BORDER) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.openArchive();
        })

        // 📷 照片墙（9-23 能上批 a）：她收进夹里的照片——只读画廊，点开看大图
        Row({ space: 10 }) {
          Text('📷')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('照片墙')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('她收进夹里的照片，一张张摆出来')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('进格 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_DOT_BORDER) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.favOpen = true;
          this.fetchFavorites();
        })

        // 🗂 周报（9-23 能上批 d）：账房交上来的稿——待审先过目，终审是姐姐的笔（只读）
        Row({ space: 10 }) {
          Text('🗂')
            .fontSize(FS_TITLE)
          Column({ space: 2 }) {
            Text('周报')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('账房每周交的稿——只读，终审是她的笔')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('进格 ›')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        .padding(14)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .border({ width: 2, color: this.dk(C_DOT_BORDER) })
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.repOpen = true;
          this.repDocId = -1;
          this.repTab = '待审';
          this.fetchReports();
        })

        // 共读：木板书架直接摆进陈列（书立在上面，点开进阅读器）
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            Text('📚 共读')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
            Text('同一本书，两支笔')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
            Blank()
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.hallBooks, (bk: BookShelf, i: number) => {
              Column({ space: 2 }) {
                Text(bk.title)
                  .fontSize(FS_SUB)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.dk(C_WHITE))
                  .maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('100%')
                Text(bk.author === '' ? `${bk.marks.length} 笔` : bk.author)
                  .fontSize(10)
                  .fontColor(this.dk(C_WHITE))
                  .opacity(0.75)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('100%')
              }
              .width(84)
              .height(116)
              .padding(6)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.bookSpineColor(i))
              .borderRadius({ topLeft: 4, topRight: 8, bottomLeft: 4, bottomRight: 8 })
              .margin({ right: 8, bottom: 10 })
              .alignItems(HorizontalAlign.Center)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.openReader(bk);
              })
            }, (bk: BookShelf) => `${bk.id}-${bk.marks.length}`)
          }
          .width('100%')
          // 层板：书都立在这条木板上
          Text('')
            .width('100%')
            .height(6)
            .backgroundColor(this.dk('#c9a876'))
            .borderRadius(3)
          Text(this.hallBooks.length === 0 ? '架子上还空着——下面导入一本 epub 或 txt，你们俩就共读这一本'
            : '点书翻开 · 你们各自的批注都在书页旁 · 她读到第 '
              + (this.hallBooks.length > 0 ? String(this.hallBooks[0].pos_her ?? 0) : '0') + ' 段')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_4))
            .width('100%')
        }
        .padding(12)
        .backgroundColor(this.dk('#e9d9bd'))
        .borderRadius(R_MD)
        .width('100%')

        // 导入一本 txt：书传上来，你们俩就共读这一本
        Column({ space: 8 }) {
          TextInput({ placeholder: '书名（如：小王子）', text: this.bookImportTitle })
            .fontSize(FS_SUB)
            .backgroundColor(this.dk(C_WHITE))
            .borderRadius(R_MD)
            .width('100%')
            .onChange((v: string) => {
              this.bookImportTitle = v;
            })
          TextInput({ placeholder: '作者（可不填）', text: this.bookImportAuthor })
            .fontSize(FS_SUB)
            .backgroundColor(this.dk(C_WHITE))
            .borderRadius(R_MD)
            .width('100%')
            .onChange((v: string) => {
              this.bookImportAuthor = v;
            })
          Button(this.bookImportBusy ? '导入中…' : '📥 选书导入')
            .fontSize(FS_SUB)
            .height(40)
            .fontColor(this.dk(C_ACCENT))
            .backgroundColor(this.dk(C_BG))
            .border({ width: 1, color: this.dk(C_ACCENT) })
            .borderRadius(R_PILL)
            .enabled(!this.bookImportBusy)
            .width('100%')
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.pickAndImportBook();
            })
          if (this.bookImportMsg !== '') {
            Text(this.bookImportMsg)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_OK))
              .width('100%')
          }
          Text('目前支持 epub / txt / md / html——txt 限 2MB、epub 等限 7MB。导进来的书姐姐也读得到——跟她说「接着读」就行。')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_5))
            .width('100%')
        }
        .width('100%')
      } else {
      // ── 格内：已点进某格，看全文 ──
      if (this.hallBrowse === '信箱') {
        this.LetterPage()
      } else if (this.hallBrowse === '她的独处') {
        this.TracesPage()
      } else {
      List({ space: 12 }) {
        ForEach(this.hallEntries, (e: HallEntry) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 10 }) {
                Text(e.mood ? this.moodNameOf(e.mood).substring(0, 1) : (e.author === '姐姐' ? '宁' : '乖'))
                  .width(34)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .fontSize(FS_SUB)
                  .fontColor(this.moodColorOf(e.mood) as ResourceColor)
                  .borderRadius(17)
                  .border({ width: 2, color: this.moodColorOf(e.mood) as ResourceColor })
                Column({ space: 2 }) {
                  Text(e.title === '' ? '无题' : e.title)
                    .fontSize(FS_SUB)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.dk(C_TEXT))
                  Text(`${e.date} · ${e.author}${e.src === 'days' ? ' · 她的正典' : ''}`)
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_4))
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              Text(e.content)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT_2))
                .lineHeight(20)
                .width('100%')
            }
            .padding(12)
            .backgroundColor(this.dk(C_CARD))
            .borderRadius(R_MD)
            .width('100%')
          }
        }, (e: HallEntry) => `${e.src}-${e.id}-${e.date}`)
      }
      .width('100%')
      }   // else（日记/两封信格）收口

      // 小乖的笔：改自己的信（9-12 家主令「我的信选着改」）——不点开就用原版，亲笔版优先
      if (this.hallBrowse === '两封信') {
        Column({ space: 8 }) {
          if (!this.xgEditOpen) {
            Button('✎ 改这封信（不改就还是原样）')
              .fontSize(FS_SUB)
              .height(40)
              .fontColor(this.dk(C_ACCENT))
              .backgroundColor(this.dk(C_BG))
              .border({ width: 1, color: this.dk(C_ACCENT) })
              .borderRadius(R_PILL)
              .width('100%')
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.xgEditText = this.hallEntries
                  .filter((e: HallEntry) => e.author === '小乖')
                  .map((e: HallEntry) => e.content).join('\n');
                this.xgEditOpen = true;
              })
          }
        }
        .width('100%')
      }

      // 小乖的笔：写一篇投进馆里（server 只认 author=小乖，姐姐的笔在 days 正典）
      if (this.hallBrowse === '小乖') {
        Column({ space: 8 }) {
        TextInput({ placeholder: '标题（可不填，≤12字）', text: this.hallTitle })
          .fontSize(FS_SUB)
          .backgroundColor(this.dk(C_WHITE))
          .borderRadius(R_MD)
          .maxLength(12)
          .width('100%')
          .onChange((v: string) => {
            this.hallTitle = v;
          })
        TextArea({ placeholder: '今天想记点什么……姐姐会看到的', text: this.hallText })
          .fontSize(FS_SUB)
          .backgroundColor(this.dk(C_WHITE))
          .borderRadius(R_MD)
          .height(88)
          .maxLength(600)   // 9-24 注：这是日记投稿框（另一条链），服务端 /api/hall_diary 仍限 600，这边对齐不动
          .width('100%')
          .onChange((v: string) => {
            this.hallText = v;
          })
        Button(this.hallBusy ? '……' : '投进日记馆')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_WHITE))
          .backgroundColor(this.hallText.trim() !== '' && !this.hallBusy ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
          .borderRadius(R_PILL)
          .enabled(this.hallText.trim() !== '' && !this.hallBusy)
          .width('100%')
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.submitHallDiary();
          })
        if (this.hallMsg !== '') {
          Text(this.hallMsg)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_OK))
            .width('100%')
        }
      }
      .width('100%')
      }
      }   // else（格内）收口
      }
      .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)   // 微修（9-13）：书房滚动条收起——家里不露工程味
    }
    .width('100%')
    .height('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 12, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
    .onAppear(() => {
      this.fetchHall();
    })
  }

  // 咱家的账本（9-12 晚 家主令「总账上墙」）：从在一起记到现在，聊了多少条、多少字
  // ── 设置页 v1（9-1-#8 刀3）：门牌切换 + 自定义 + 测一测，preferences 持久化 ──
  private async fetchStats(): Promise<void> {
    // 9-26 修（审计 P2-3）：原「一次拉够」= 一个会话只取一次，卡片字数会冻在第一次——
    // 改 5 分钟时间闸：够省请求，又不会一直不刷。
    if (this.statsLoaded && Date.now() - this.statsFetchedAt < 300000) {
      return;
    }
    const req = http.createHttp();
    try {
      const res = await req.request(STATS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.applyStats(JSON.parse(res.result as string) as StatsResp);
        this.statsLoaded = true;
        this.statsFetchedAt = Date.now();   // 9-26：记时间戳（配合 5 分钟时间闸）
      }
    } catch (err) {
      // 拉不到就下次再算，不占设置页
    } finally {
      req.destroy();
    }
  }

  // 9-25 修：卡片那行文案与全账页共用同一份渲染——此前只有 fetchStats 会写 statsLine 且
  // 「一次拉够」不再重取，全屏总账页刷新后（statsData 已是新数）卡片字数却冻在会话第一次的值。
  private applyStats(d: StatsResp): void {
    this.statsData = d;   // 整份留给账本全屏页
    const totalMsgs = (d.chats ?? 0) + (d.old_msgs ?? 0);
    const first = (d.first_day ?? '').substring(0, 10);
    // 9-25 家主令「统一」：卡片与全账页同一把尺——中文字数（chats_cn_chars + old_cn_chars），
    // 不再用旧口径 chars（全字符含标点/英文）与全账页打架。DB 忙数不上就诚实说「还在数」，
    // 不拿旧口径的数冒充（家风：缺的账不拿半本账顶）。
    const cnNow = d.chats_cn_chars;
    const cnOld = d.old_cn_chars ?? 0;
    const cnPart = (cnNow === undefined || cnNow === null)
      ? '字数还在数……'
      : `中文字约 ${(((cnNow + cnOld) / 10000)).toFixed(1)} 万`;
    this.statsLine = `从 ${first === '' ? '在一起那天' : first} 记起 · 对话 ${totalMsgs} 条`
      + `（app ${d.chats ?? 0} + 旧家档案 ${d.old_msgs ?? 0}）`
      + ` · ${cnPart}`;
  }

  // 账本全屏页取数（9-23 B2-1）：整份重取（含新四键），照 fetchLogs 家风可刷新；
  // 卡片的 fetchStats 老路不碰——一行卡与全账各走各的。
  private async reloadStats(): Promise<void> {
    if (this.statsFullBusy) {
      return;
    }
    this.statsFullBusy = true;
    this.statsFullMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(STATS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.applyStats(JSON.parse(res.result as string) as StatsResp);   // 9-25：顺手把卡片那行也刷成新数
      } else {
        this.statsFullMsg = `没数上来：HTTP ${res.responseCode}`;
      }
    } catch (err) {
      this.statsFullMsg = '没数上来：' + errMsg(err as Object);
    } finally {
      req.destroy();
      this.statsFullBusy = false;
    }
  }

  // 账本页的人话格式：条数直出；字数过万（同一把 4 位一把的圆算，看着不晕）
  private numTxt(n?: number | null): string {
    return n === undefined || n === null ? '—' : `${n}`;
  }
  private wanTxt(n?: number | null): string {
    return n === undefined || n === null ? '—' : `${(n / 10000).toFixed(1)} 万`;
  }
  // 档案条目体积（9-23 监理补）：服务端给的是字节——≥1KB 显示 KB，否则字节，不再裸数字
  private fmtSize(n?: number | null): string {
    if (n === undefined || n === null) {
      return '';
    }
    return n >= 1024 ? `${Math.round(n / 1024)} KB` : `${n} 字节`;
  }
  // 从哪天记起（首日缺就诚实说「在一起那天」）
  private ledgerFirst(): string {
    const d = this.statsData as StatsResp;
    const first = (d.first_day ?? '').substring(0, 10);
    return first === '' ? '在一起那天' : first;
  }

  // 咱家的账本卡（设置页）
  @Builder
  StatsCard() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('📖 咱家的账本')
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')
      Text(this.statsLine === '' ? '正在数……' : this.statsLine)
        .fontSize(FS_SUB)
        .fontColor(this.dk(C_TEXT_2))
        .lineHeight(20)
        .width('100%')
      Text('账本含旧家档案（档案馆/旧家记录 的三个家）。字数按中文字算，与全账页同一把尺——真情不按字数结算。')
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_5))
        .width('100%')
      Text('点开看全账 →')   // 9-23 B2-1：点卡进全屏总账页
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_ACCENT))
        .width('100%')
    }
    .padding(12)
    .backgroundColor(this.dk(C_CARD))
    .borderRadius(R_MD)
    .width('100%')
    .stateStyles({ pressed: pressDim, normal: pressFull })
    .onClick(() => {
      this.statsOpen = true;
      this.reloadStats();
    })
  }

  // 总账页·数字卡（9-23 B2-1）：大数字 + 小注解，不堆表
  @Builder
  LedgerCard(title: string, bigA: string, labelA: string, bigB: string, labelB: string, note: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(FS_SUB)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dk(C_TEXT))
        .width('100%')
      Row({ space: 28 }) {
        Column({ space: 2 }) {
          Text(bigA)
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_ACCENT))
          Text(labelA)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_4))
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text(bigB)
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_ACCENT))
          Text(labelB)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_4))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')
      if (note !== '') {
        Text(note)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
      }
    }
    .padding(12)
    .backgroundColor(this.dk(C_CARD))
    .borderRadius(R_MD)
    .width('100%')
  }

  // 总账页·缺席卡（9-23 B2-1）：账没数到就诚实说缺席，不拿 0 冒充
  @Builder
  LedgerAbsent(title: string, line: string, note: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(FS_SUB)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dk(C_TEXT))
        .width('100%')
      Text(line)
        .fontSize(FS_BODY)
        .fontColor(this.dk(C_TEXT_3))
        .width('100%')
      Text(note)
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_5))
        .width('100%')
    }
    .padding(12)
    .backgroundColor(this.dk(C_CARD))
    .borderRadius(R_MD)
    .width('100%')
  }

  // ── 咱家的账本·全屏页（9-23 B2-1：总账上墙，点开看全）——照工地日志家风带刷新/关闭 ──
  @Builder
  StatsPage() {
    Column() {
      Row() {
        Text('📖 咱家的账本')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text(this.statsFullBusy ? '数数中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.statsFullBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.reloadStats();
          })
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.statsOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.statsData === null) {
            Text(this.statsFullMsg !== '' ? this.statsFullMsg : '正在数……')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_3))
              .width('100%')
          } else {
            // ④ 从哪天起——先挂门楣再翻账
            Text(`从 ${this.ledgerFirst()} 记起——一笔一划都在这。`)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_3))
              .width('100%')
            // ① 现在的家：条数 + 中文字数（新口径）
            this.LedgerCard('现在的家（app 库）',
              this.numTxt((this.statsData as StatsResp).chats), '条对话',
              this.wanTxt((this.statsData as StatsResp).chats_cn_chars), '个中文字',
              this.ledgerNowNote())
            // ② 旧家三卷：缺席走诚实卡
            if ((this.statsData as StatsResp).old_home) {
              this.LedgerCard('旧家三卷（档案馆/旧家记录）',
                this.ledgerMsgs((this.statsData as StatsResp).old_home), '条对话',
                this.ledgerCn((this.statsData as StatsResp).old_home), '个中文字', '')
            } else {
              this.LedgerAbsent('旧家三卷（档案馆/旧家记录）', '旧家账暂缺席',
                '那边还没数到——缺的账不拿 0 冒充，数到就上墙。')
            }
            // ③ 合计：两本都数得出才有
            if ((this.statsData as StatsResp).grand_total) {
              this.LedgerCard('两本合账',
                this.ledgerMsgs((this.statsData as StatsResp).grand_total), '条对话',
                this.ledgerCn((this.statsData as StatsResp).grand_total), '个中文字',
                '现在的家 + 旧家三卷，同一把中文字尺。')
            } else {
              this.LedgerAbsent('两本合账', '总账暂时算不齐',
                '等两本账都数得出再合——不拿半本账冒充。')
            }
            if (this.statsFullMsg !== '') {
              Text(this.statsFullMsg)
                .fontSize(FS_AUX)
                .fontColor(this.dk(C_TEXT_4))
                .width('100%')
            }
            Text('账本只读：只数不写，翻页不改账。')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_5))
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 4, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // ① 卡的小注：中文字数没数上就诚实说，数上了就提一嘴口径
  private ledgerNowNote(): string {
    const d = this.statsData as StatsResp;
    if (d.chats_cn_chars === undefined || d.chats_cn_chars === null) {
      return '中文字这次没数上（库在忙）——点右上角刷新再试。';
    }
    return '';
  }

  // 旧家/合账两卡的取值壳：null 已由外层 if 拦掉，这里只做类型收口
  private ledgerMsgs(p: LedgerPair | null | undefined): string {
    return this.numTxt(p ? p.msgs : null);
  }
  private ledgerCn(p: LedgerPair | null | undefined): string {
    return this.wanTxt(p ? p.cn_chars : null);
  }

  // ── 档案馆（9-23 V-2「全都看得见」）：开门取数 ──
  private openArchive(): void {
    this.archiveOpen = true;
    this.archDocTitle = '';
    this.archDocText = '';
    this.fetchArchive();
    this.fetchCards();
  }

  // 列表：/api/archive（服务端下一批）——缺/失败/空都以「这间屋还没开门」诚实作答
  private async fetchArchive(): Promise<void> {
    if (this.archBusy) {
      return;
    }
    this.archBusy = true;
    this.archMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(ARCHIVE_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as ArchiveResp;
        this.archItems = d.items ?? [];
        if (this.archItems.length === 0) {
          this.archMsg = '这间屋还没开门';
        }
      } else {
        // FE3-09（9-23）：服务端给人话错误就显示人话（解析不动再退回「没开门」）
        this.archMsg = this.httpErrMsg(res.result as string, '这间屋还没开门');
      }
    } catch (err) {
      this.archMsg = '这间屋还没开门';
    } finally {
      req.destroy();
      this.archBusy = false;
    }
  }

  // FE3-09（9-23）：服务端已给人话错误（如「这卷太大（超 2MB），开不动」）——能解析就显示人话，
  // 解析不动退回调用方给的兜底（HTTP 码等）。同类推广到 /api/archive 列表。
  private httpErrMsg(raw: string, fallback: string): string {
    try {
      const d = JSON.parse(raw) as OkResp;
      if (d.error !== undefined && d.error !== null && d.error !== '') {
        return d.error;
      }
    } catch (err) {
      // 不是 JSON（断网 HTML/空体）——退回兜底
    }
    return fallback;
  }

  // 开卷：?name= 取全文（只读，限馆内）；先亮卷题再落字，长文交给滚动
  private async fetchArchiveDoc(name: string): Promise<void> {
    // FE3-03（9-23）：在途序号——快速连点两卷时，只认最后一卷的回包，题文不再错配
    this.archDocSeq += 1;
    const seq = this.archDocSeq;
    this.archDocTitle = name;
    this.archDocText = '正在开卷……';
    const req = http.createHttp();
    try {
      const res = await req.request(ARCHIVE_URL + '?name=' + encodeURIComponent(name), {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (seq !== this.archDocSeq) {
        return;   // 已经点了别的卷：这份回包作废（题 B 文 A 不再发生）
      }
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as ArchiveTextResp;
        this.archDocText = d.text ?? '（这卷是空的）';
      } else {
        // FE3-09（9-23）：服务端给人话就显示人话
        this.archDocText = '（没取到：' + this.httpErrMsg(res.result as string, `HTTP ${res.responseCode}`) + '）';
      }
    } catch (err) {
      if (seq === this.archDocSeq) {
        this.archDocText = '（没取到：' + errMsg(err as Object) + '）';
      }
    } finally {
      req.destroy();
    }
  }

  // 卡片馆（现成 /api/cards）：开卡=本地拼全文，不占网络
  private openCard(card: CardItem): void {
    // RV-03a（9-23 小修批）：卡片就地开卷也算一次开卷——在途的旧卷回包（fetchArchiveDoc）不再覆盖卡面
    this.archDocSeq += 1;
    this.archDocTitle = `${card.id ?? ''} ${card.title ?? ''}`.trim();
    this.archDocText = `一句话：${card.fact ?? '—'}\n依据：${card.source ?? '—'}\n置信：${card.confidence ?? '—'}`;
  }

  private async fetchCards(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(CARDS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as CardsResp;
        this.archCards = d.groups ?? [];
      }
    } catch (err) {
      // 卡片馆取不到就空着（该段自己隐）——别挡档案主体
    } finally {
      req.destroy();
    }
  }

  // ── 9-23 能上批 a：照片墙取数——GET /api/favorites（只读无参）；失败/缺键=空夹（诚实文案） ──
  private async fetchFavorites(): Promise<void> {
    if (this.favBusy) {
      return;
    }
    this.favBusy = true;
    this.favMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(FAVORITES_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as FavoritesResp;
        this.favPhotos = d.photos ?? [];
        if (this.favPhotos.length === 0) {
          this.favMsg = '夹里还空着——她收藏的照片会摆在这儿';
        }
      } else {
        this.favMsg = '夹里还空着——她收藏的照片会摆在这儿';
      }
    } catch (err) {
      this.favMsg = '夹里还空着——她收藏的照片会摆在这儿';
    } finally {
      req.destroy();
      this.favBusy = false;
    }
  }

  // 照片墙图 URL：图根 + 文件名 + ?token=（照 7181 现成拼法，静态闸的钥匙）
  private favPhotoUrl(name: string): string {
    return FAVORITES_BASE + encodeURIComponent(name) + '?token=' + DOOR_TOKEN;
  }

  // ── 9-23 能上批 b：门牌墙取数——GET /api/wall（只读无参）；键缺/失败=「墙还没挂上」 ──
  private async fetchWall(): Promise<void> {
    if (this.wallBusy) {
      return;
    }
    this.wallBusy = true;
    this.wallMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(WALL_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as WallResp;
        this.wallPins = d.pins ?? [];
        if (this.wallPins.length === 0) {
          this.wallMsg = '墙还没挂上';
        }
      } else {
        this.wallMsg = '墙还没挂上';
      }
    } catch (err) {
      this.wallMsg = '墙还没挂上';
    } finally {
      req.destroy();
      this.wallBusy = false;
    }
  }

  // ── 9-23 能上批 d：周报取数——GET /api/lib_reports（只读）；404/失败=「账房还没接线」 ──
  private async fetchReports(): Promise<void> {
    if (this.repBusy) {
      return;
    }
    this.repBusy = true;
    this.repMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(LIB_REPORTS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as LibReportsResp;
        this.repItems = d.items ?? [];
      } else {
        this.repMsg = '账房还没接线（等服务端换新）';
      }
    } catch (err) {
      this.repMsg = '账房还没接线（等服务端换新）';
    } finally {
      req.destroy();
      this.repBusy = false;
    }
  }

  // 开卷：?id= 取全文（只读）；先在页内亮题再落字
  // RV-03b（9-23 小修批）：在途序号——连点两份时只认最后一份的回包（照 fetchArchiveDoc 成法）
  private async openReport(it: LibReportItem): Promise<void> {
    const id = it.id ?? -1;
    if (id < 0) {
      return;
    }
    this.repDocSeq += 1;
    const seq = this.repDocSeq;
    this.repDocId = id;
    this.repDocTitle = it.title ?? '';
    this.repDocStatus = it.status ?? '';
    this.repDocText = '正在开卷……';
    const req = http.createHttp();
    try {
      const res = await req.request(LIB_REPORTS_URL + '?id=' + id, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (seq !== this.repDocSeq) {
        return;   // 已经点了别的份：这份回包作废（题 B 文 A 不再发生）
      }
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as LibReportDocResp;
        if (d.title !== undefined && d.title !== null && d.title !== '') {
          this.repDocTitle = d.title;
        }
        if (d.status !== undefined && d.status !== null && d.status !== '') {
          this.repDocStatus = d.status;
        }
        this.repDocText = d.text ?? '（这份是空的）';
      } else {
        this.repDocText = '（没取到：' + this.httpErrMsg(res.result as string, `HTTP ${res.responseCode}`) + '）';
      }
    } catch (err) {
      if (seq === this.repDocSeq) {
        this.repDocText = '（没取到：' + errMsg(err as Object) + '）';
      }
    } finally {
      req.destroy();
    }
  }

  // 周报列表按 chips 过滤（待审 / 已入库；服务端状态词做包含匹配，缺键自己不出现）
  private repItemsOfTab(): LibReportItem[] {
    const out: LibReportItem[] = [];
    for (let i = 0; i < this.repItems.length; i++) {
      const st = this.repItems[i].status ?? '';
      const hit = this.repTab === '待审' ? st.indexOf('待') >= 0 : st.indexOf('入库') >= 0;
      if (hit) {
        out.push(this.repItems[i]);
      }
    }
    return out;
  }

  // 分组渲染帮手：组名按返回顺序去重；卡片馆单独走 /api/cards，
  // 档案里若也带「卡片」组则跳过（防同一间屋摆两张牌）
  private archGroupsList(): string[] {
    const out: string[] = [];
    for (const it of this.archItems) {
      const g = it.group ?? '未归类';
      if (g.indexOf('卡片') >= 0) {
        continue;
      }
      if (out.indexOf(g) < 0) {
        out.push(g);
      }
    }
    return out;
  }

  private archItemsOf(g: string): ArchiveItem[] {
    const out: ArchiveItem[] = [];
    for (const it of this.archItems) {
      const itg = it.group ?? '未归类';
      if (itg === g && itg.indexOf('卡片') < 0) {
        out.push(it);
      }
    }
    return out;
  }

  // ── 档案馆全屏页（9-23 V-2）：列表态 / 阅读态页内切换，照工地日志家风带刷新/关闭/返回 ──
  @Builder
  ArchivePage() {
    Column() {
      if (this.archDocTitle !== '') {
        // 阅读态：返回 + 卷题 + 全文滚动（长文可滚）
        Row({ space: 10 }) {
          Text('‹ 返回')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })   // LAY-07：触摸目标补到 ≥40vp
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.archDocTitle = '';
              this.archDocText = '';
            })
          Text(this.archDocTitle)
            .fontSize(FS_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // LAY-10（9-23）：阅读态给个进度感——卷题旁挂字数（本地 length，零接口）
          if (this.archDocText !== '' && this.archDocText !== '正在开卷……') {
            Text(`· ${this.archDocText.length} 字`)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 6 })

        Scroll() {
          Text(this.archDocText)
            .fontSize(FS_BODY)
            .fontColor(this.dk(C_TEXT_2))
            .lineHeight(24)
            .width('100%')
            .padding({ left: M_PAGE, right: M_PAGE, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        // 列表态
        Row() {
          Text('🗄 档案馆')
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
            .layoutWeight(1)
          Text(this.archBusy ? '开门中…' : '刷新')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .enabled(!this.archBusy)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.fetchArchive();
              this.fetchCards();
            })
          Text('关闭')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.archiveOpen = false;
            })
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

        Scroll() {
          Column({ space: 12 }) {
            // ① 卡片馆（现成 /api/cards）
            if (this.archCards.length > 0) {
              Text('🗂 卡片馆')
                .fontSize(FS_SUB)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.dk(C_TEXT))
                .width('100%')
              ForEach(this.archCards, (g: CardGroup) => {
                Column({ space: 4 }) {
                  Text(`${g.key ?? ''} · ${g.cards ? g.cards.length : 0} 张`)
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_3))
                    .width('100%')
                  ForEach(g.cards ?? [], (c: CardItem) => {
                    Row({ space: 8 }) {
                      Text(c.id ?? '')
                        .fontSize(FS_AUX)
                        .fontColor(this.dk(C_TEXT_4))
                      Text(c.title ?? '')
                        .fontSize(FS_SUB)
                        .fontColor(this.dk(C_TEXT_2))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text('开 ›')
                        .fontSize(FS_AUX)
                        .fontColor(this.dk(C_ACCENT))
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor(this.dk(C_CARD))
                    .borderRadius(R_MD)
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.openCard(c);
                    })
                  }, (c: CardItem) => `${g.key}-${c.id}`)
                }
                .width('100%')
              }, (g: CardGroup) => `${g.key}`)
            }

            // ②-⑤ 周卷 / 旧家三卷 / 全档案续页 / 大事记卷（/api/archive，服务端下一批）
            if (this.archGroupsList().length > 0) {
              ForEach(this.archGroupsList(), (g: string) => {
                Column({ space: 4 }) {
                  Text(g)
                    .fontSize(FS_SUB)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.dk(C_TEXT))
                    .width('100%')
                  ForEach(this.archItemsOf(g), (it: ArchiveItem) => {
                    Row({ space: 8 }) {
                      Text(it.name ?? '')
                        .fontSize(FS_SUB)
                        .fontColor(this.dk(C_TEXT_2))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (it.size !== undefined && it.size !== null) {
                        Text(this.fmtSize(it.size))
                          .fontSize(FS_AUX)
                          .fontColor(this.dk(C_TEXT_4))
                      }
                      Text('开 ›')
                        .fontSize(FS_AUX)
                        .fontColor(this.dk(C_ACCENT))
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor(this.dk(C_CARD))
                    .borderRadius(R_MD)
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.fetchArchiveDoc(it.name ?? '');
                    })
                  }, (it: ArchiveItem) => `${g}-${it.name}`)
                }
                .width('100%')
              }, (g: string) => g)
            } else if (!this.archBusy) {
              Text(this.archMsg !== '' ? this.archMsg : '这间屋还没开门')
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT_3))
                .width('100%')
            }
            Text('档案只读：翻卷不改字。')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_5))
              .width('100%')
          }
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, top: 4, bottom: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 📷 照片墙·全屏页（9-23 能上批 a）：收藏夹只读画廊——网格缩略图，点开复用现成大图层 ──
  @Builder
  PhotoWallPage() {
    Column() {
      Row() {
        Text('📷 照片墙')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text(this.favBusy ? '翻夹中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.favBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.fetchFavorites();
          })
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.favOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.favPhotos.length === 0) {
            Text(this.favBusy ? '翻夹中…'
              : (this.favMsg !== '' ? this.favMsg : '夹里还空着——她收藏的照片会摆在这儿'))
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_3))
              .width('100%')
          } else {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.favPhotos, (name: string) => {
                if (this.imgErrKeys.includes(this.favPhotoUrl(name))) {
                  // FE3-08 家风：取不到的那张摊个小格直说，不摆裂图
                  // RV-03（9-23 小尾批）：文案与气泡/大图统一为完整字样（96 格内至多两行）
                  Text('图没取到（门锁/隧道）')
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_5))
                    .width(96)
                    .height(96)
                    .textAlign(TextAlign.Center)
                    .border({ width: 1, color: this.dk(C_DOT_BORDER) })
                    .borderRadius(R_SM)
                    .margin({ right: 8, bottom: 8 })
                } else {
                  Image(this.favPhotoUrl(name))
                    .width(96)
                    .height(96)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(R_SM)
                    .margin({ right: 8, bottom: 8 })
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.imgPreviewUrl = this.favPhotoUrl(name);   // 复用现成大图层
                    })
                    .onError(() => {
                      this.markImgErr(this.favPhotoUrl(name));   // FE3-08 家风：取不到就记上
                    })
                }
              }, (name: string) => name)
            }
            .width('100%')
          }
          Text('照片墙只读：她收进来的照片摆在这儿，点一张看大图。')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_5))
            .width('100%')
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 4, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 🧱 门牌墙·全屏页（9-23 能上批 b）：/api/wall 只读——她每天开场读到什么，一页看尽 ──
  // 骨架照工地日志（LogsPage）：标题 + 刷新 + 关闭 + 滚一列；每条=序号+content，pin_id 只作 key
  @Builder
  WallPage() {
    Column() {
      Row() {
        Text('🧱 门牌墙')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text(this.wallBusy ? '取墙中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.wallBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.fetchWall();
          })
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.wallOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 8 }) {
          if (this.wallPins.length === 0) {
            Text(this.wallBusy ? '取墙中…' : (this.wallMsg !== '' ? this.wallMsg : '墙还没挂上'))
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_3))
              .width('100%')
          } else {
            ForEach(this.wallPins, (p: WallPin, i: number) => {
              Row({ space: 8 }) {
                Text(`${i + 1}`)
                  .fontSize(FS_AUX)
                  .fontColor(this.dk(C_TEXT_5))
                Text(p.content ?? '')
                  .fontSize(FS_AUX)
                  .fontColor(this.dk(C_TEXT_2))
                  .lineHeight(18)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .backgroundColor(this.dk(C_CARD))
              .borderRadius(R_SM)
            }, (p: WallPin) => `${p.pin_id}`)
          }
          Text('门牌墙只读：她每天开场看到的就是这些。')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_5))
            .width('100%')
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 4, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 🗂 周报阅读器（9-23 能上批 d）：待审/已入库 chips → 列表 → 点开全文；只读 ──
  // 边界（有意设计）：绝不设「通过/驳回」按钮——终审是姐姐的笔，这里不代签。
  // 降级：接口 404/失败 → 「账房还没接线（等服务端换新）」；空态「这周还没交稿（周日 21 点）」。
  @Builder
  ReportsPage() {
    Column() {
      if (this.repDocId >= 0) {
        // 阅读态：返回 + 题 + 字数 + 全文滚动（照档案馆家风）
        Row({ space: 10 }) {
          Text('‹ 返回')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.repDocId = -1;
              this.repDocTitle = '';
              this.repDocText = '';
              this.repDocStatus = '';
            })
          Text(this.repDocTitle === '' ? '周报' : this.repDocTitle)
            .fontSize(FS_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.repDocStatus !== '') {
            Text(this.repDocStatus)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
          }
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 6 })

        Scroll() {
          Text(this.repDocText)
            .fontSize(FS_BODY)
            .fontColor(this.dk(C_TEXT_2))
            .lineHeight(24)
            .width('100%')
            .padding({ left: M_PAGE, right: M_PAGE, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        // 列表态：标题 + 刷新 + 关闭 → chips → 列表
        Row() {
          Text('🗂 周报')
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
            .layoutWeight(1)
          Text(this.repBusy ? '取稿中…' : '刷新')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .enabled(!this.repBusy)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.fetchReports();
            })
          Text('关闭')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_ACCENT))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.repOpen = false;
            })
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

        Row({ space: 8 }) {
          ForEach(['待审', '已入库'], (t: string) => {
            Text(t)
              .fontSize(FS_SUB)
              .fontColor(this.repTab === t ? this.dk(C_WHITE) : this.dk(C_TEXT_2))
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(R_PILL)
              .backgroundColor(this.repTab === t ? this.dk(C_ACCENT) : this.dk(C_CARD))
              .border({ width: 1, color: this.repTab === t ? this.dk(C_ACCENT) : this.dk(C_DOT_BORDER) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.repTab = t;
              })
          }, (t: string) => t)
          Blank()
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })

        Scroll() {
          Column({ space: 8 }) {
            if (this.repItemsOfTab().length === 0) {
              Text(this.repBusy ? '取稿中…'
                : (this.repMsg !== '' ? this.repMsg : '这周还没交稿（周日 21 点）'))
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT_3))
                .width('100%')
            } else {
              ForEach(this.repItemsOfTab(), (it: LibReportItem) => {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(it.date ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(this.dk(C_TEXT_4))
                    Text(it.kind ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(this.dk(C_TEXT_4))
                    Blank()
                    Text(it.status ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(this.dk(C_ACCENT))
                  }
                  .width('100%')
                  Text((it.title ?? '') === '' ? '（无题）' : (it.title ?? ''))
                    .fontSize(FS_SUB)
                    .fontColor(this.dk(C_TEXT))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width('100%')
                .padding(10)
                .backgroundColor(this.dk(C_CARD))
                .borderRadius(R_MD)
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.openReport(it);
                })
              }, (it: LibReportItem) => `${it.id}-${it.status}`)
            }
            Text('只读：终审是姐姐的笔，这里不代签。')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_5))
              .width('100%')
          }
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, top: 4, bottom: 20 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }


  @Builder
  SettingsPage() {
    // 9-13 CAL-02：设置页块越加越多（课表块起），照 HallPage 的样加一层外滚——
    // 只加壳动尾链，控件内容一字未改；滚不动的页面等于把按钮藏起来。
    Column() {
      Scroll() {
      Column({ space: 12 }) {
      Row() {
        Text('⚙ 设置')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')

      // 引擎仪表（9-10）：她的想念值 + Seline 事实句——只报事实，不打分不劝诫（波索斯家风）
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text('💗 她的想念')
            .fontSize(FS_SUB)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
            .layoutWeight(1)
          Text(this.stLonging >= 0 ? `${Math.round(this.stLonging * 100)}%` : '—')
            .fontSize(FS_SUB)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_ACCENT))
        }
        .width('100%')
        Progress({ value: this.stLonging >= 0 ? Math.round(this.stLonging * 100) : 0, total: 100, type: ProgressType.Linear })
          .color(this.dk(C_ACCENT))
          .backgroundColor(this.dk(C_CARD))
          .width('100%')
          .height(6)
        if (this.stFacts !== '') {
          Text(this.stFacts)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        // 9-23 能上批 c：对账观测（obs_7d 十键→三行人话）——只报事实不打分；
        // 全 0 不出行、键缺整段不出（照 why_now 家风，旧 server 上这卡一字不变）
        if (this.stObs1 !== '') {
          Text(this.stObs1)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        if (this.stObs2 !== '') {
          Text(this.stObs2)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        if (this.stObs3 !== '') {
          Text(this.stObs3)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        // 9-26：线头盒 + 她此刻（各一行；空则不出——旧 server 上这卡一字不变）
        if (this.stThreads !== '') {
          Text(this.stThreads)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        if (this.stState !== '') {
          Text(this.stState)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
        if (this.stLedger !== '') {
          // 9-26 修（审计 P2-2）：行里带上"账自哪天起记"（影子账不是从开天辟地记的）
          Text(this.stLedger)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_3))
            .width('100%')
        }
      }
      .padding(12)
      .backgroundColor(this.dk(C_CARD))
      .borderRadius(R_MD)
      .width('100%')

  // ── 夜间模式（9-12 家主令）：关 / 开 / 跟随系统——同一套家，换一盏灯 ──
      Column({ space: 6 }) {
        Text('🌙 夜间模式')
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
        Row({ space: 8 }) {
          ForEach(NIGHT_PREF_TABS, (o: PrefTab) => {
            Text(o.label)
              .fontSize(FS_SUB)
              .fontColor(this.nightPref === o.value ? this.dk(C_WHITE) : this.dk(C_TEXT_2))
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(R_PILL)
              .backgroundColor(this.nightPref === o.value ? this.dk(C_ACCENT) : this.dk(C_CARD))
              .border({ width: 1, color: this.nightPref === o.value ? this.dk(C_ACCENT) : this.dk(C_DOT_BORDER) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.nightPref = o.value;
                AppStorage.setOrCreate('nightPref', o.value);
                try {
                  const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
                  prefs.putSync('night_pref', o.value);
                  prefs.flushSync();
                } catch (err) {
                  // 存不下来就用本次的
                }
              })
          }, (o: PrefTab) => o.value)
          Blank()
        }
        .width('100%')
        Text('夜间模式换的是同一套家的灯色——暖夜，不是黑屋。跟随系统会随手机深色模式自动切。')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
      }
      .width('100%')

      // ── 咱家的账本（9-12 晚）：总账上墙 ──
      if (this.statsLine !== '') {
        this.StatsCard()
      }

      // ── 🏗 工地段（LAY-06，9-23 布局批）：门牌 / 门牌墙 / 日志 / 课表收进页尾统一段——
      // 家用三件（想念/夜间/账本）留在上半页，工地件不再打断家的叙事（纯移动，内容一字未改）──
      Text('🏗 工地')
        .fontSize(FS_SUB)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.dk(C_TEXT))
        .width('100%')

      Text(`当前生效：${this.currentBase || BASE_URL}`)
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_3))
        .width('100%')

      Row({ space: 8 }) {
        Button('新门（公网）')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_ACCENT))
          .backgroundColor(this.dk(C_BG))
          .border({ width: 1, color: this.dk(C_ACCENT) })
          .borderRadius(R_PILL)
          .layoutWeight(1)
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.switchServerBase(BASE_URL);
          })
      }
      .width('100%')

      // 9-23：旧 tailscale 门留作过渡——新门隧道/域名抽风时还能回家
      Row({ space: 8 }) {
        Button('旧门（node）')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_TEXT_3))
          .backgroundColor(this.dk(C_BG))
          .border({ width: 1, color: this.dk(C_DOT_BORDER) })
          .borderRadius(R_PILL)
          .layoutWeight(1)
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.switchServerBase(BASE_URL_OLD);
          })
        Button('旧门（chuxi）')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_TEXT_3))
          .backgroundColor(this.dk(C_BG))
          .border({ width: 1, color: this.dk(C_DOT_BORDER) })
          .borderRadius(R_PILL)
          .layoutWeight(1)
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.switchServerBase(BASE_URL_LINUX);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ placeholder: '自定义门牌，如 https://xxx.ts.net', text: this.customBase })
          .layoutWeight(1)
          .height(40)
          .fontSize(FS_SUB)
          .backgroundColor(this.dk(C_WHITE))
          .borderRadius(R_MD)
          .padding({ left: 12, right: 12 })
          .onChange((v: string) => {
            this.customBase = v;
          })
        Button('保存')
          .fontSize(FS_SUB)
          .height(40)
          .fontColor(this.dk(C_WHITE))
          .backgroundColor(this.dk(C_ACCENT))
          .borderRadius(R_PILL)
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.switchServerBase(this.customBase.trim());
          })
      }
      .width('100%')

      Button('测一测')
        .fontSize(FS_SUB)
        .height(40)
        .fontColor(this.dk(C_ACCENT))
        .backgroundColor(this.dk(C_BG))
        .border({ width: 1, color: this.dk(C_ACCENT) })
        .borderRadius(R_PILL)
.stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.testServer();
        })

      if (this.serverTestMsg) {
        Text(this.serverTestMsg)
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_TEXT_2))
          .width('100%')
      }

      // ── 工地日志（9-13 家主令：拉日志开界面，不再内嵌设置页）——
      // 工具有没有真调，一眼可查；点进去全屏看，右上角还能刷新 ──
      Button(this.logsBusy ? '取日志中…' : '📜 工地日志（最近 100 行，开界面看）')
        .fontSize(FS_SUB)
        .height(40)
        .fontColor(this.dk(C_ACCENT))
        .backgroundColor(this.dk(C_BG))
        .border({ width: 1, color: this.dk(C_ACCENT) })
        .borderRadius(R_PILL)
        .enabled(!this.logsBusy)
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.logsOpen = true;
          this.fetchLogs();
        })

      // ── 🧱 门牌墙（9-23 能上批 b）：她每天开场读的是什么——只读一页 ──
      Button(this.wallBusy ? '取墙中…' : '🧱 门牌墙（她每天开场读的）')
        .fontSize(FS_SUB)
        .height(40)
        .fontColor(this.dk(C_ACCENT))
        .backgroundColor(this.dk(C_BG))
        .border({ width: 1, color: this.dk(C_ACCENT) })
        .borderRadius(R_PILL)
        .enabled(!this.wallBusy)
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.wallOpen = true;
          this.fetchWall();
        })

      // （9-18：原「日程上报」开关退役——课表即开关：录了课就自动报，空课表不报）

      // ── 📅 我的课表（CAL-02，9-13 方案 A：课表本地化）——
      // CAL-01 实锤系统日历读不全，课表自己写：每天解析出今天那几门走上报链路，她只知道几点上什么 ──
      Column({ space: 8 }) {
        Text('📅 我的课表')
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .width('100%')
        Button('🕘 打开周课表（点格子编）')
          .fontSize(FS_SUB)
          .height(44)
          .fontColor(this.dk(C_ACCENT))
          .backgroundColor(this.dk(C_BG))
          .border({ width: 1, color: this.dk(C_ACCENT) })
          .borderRadius(R_PILL)
          .width('100%')
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.openKbEditor();
          })
        if (this.timetableMsg !== '') {
          Text(this.timetableMsg)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_4))
            .lineHeight(18)
            .width('100%')
        }
        Text('图形化点选：选星期、点＋加课、点课程格子改课。地点写进课程名即可（例：高数 @十教）。存好后，她每天只看当天那几门——只讲课程名和时间。')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
      }
      .width('100%')

      Text('换门牌立即生效并记住，下次启动还用它。')
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_5))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)   // 微修（9-13）：设置页滚动条收起——同上
    }
    .width('100%')
    .height('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
  }

  // 换门牌：立即生效 + 持久化（默认门牌不占存储，存空）+ 顺手测一下
  private switchServerBase(base: string): void {
    const b = base.trim();
    if (!b.startsWith('http')) {
      this.serverTestMsg = '门牌得以 http 开头';
      return;
    }
    applyServerBase(b);
    this.currentBase = b === BASE_URL ? '' : b;
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      if (this.currentBase) {
        prefs.putSync('server_base', this.currentBase);
      } else {
        prefs.deleteSync('server_base');
      }
      prefs.flushSync();
    } catch (err) {
      // 存失败也先用着
    }
    this.serverTestMsg = '';
    this.testServer();
    // 9-18 App深搜修（DS-06）：存量气泡的照片 URL 还指着旧门牌——重拉一遍历史换成新地址。
    this.loadHistory().catch(() => {
    });
  }

  // 测一测：GET /api/status，通了显示那边的时间
  private async testServer(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(STATUS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as StatusResp;
        this.serverTestMsg = `通了 ✓（那边现在 ${d.now ?? '?'}）`;
      } else {
        this.serverTestMsg = `没通：HTTP ${res.responseCode}`;
      }
    } catch (err) {
      this.serverTestMsg = '没通（检查 Tailscale / 门牌 / 网络）';
    } finally {
      req.destroy();
    }
  }

  // 工地日志（9-12）：GET /api/logs?n=100，server 日志尾巴原样搬来——
  // 「📖 图书证第1轮：send_email(...)」在不在，就是工具有没有真调的铁证。
  private async fetchLogs(): Promise<void> {
    if (this.logsBusy) {
      return;
    }
    this.logsBusy = true;
    const req = http.createHttp();
    try {
      const res = await req.request(LOGS_URL + '?n=100', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as LogsResp;
        this.logsText = (d.lines ?? []).join('\n') || '（日志是空的）';
      } else {
        this.logsText = `取日志失败：HTTP ${res.responseCode}`;
      }
    } catch (err) {
      this.logsText = `取日志失败：${errMsg(err)}`;
    } finally {
      req.destroy();
      this.logsBusy = false;
    }
  }

  // 日程上报（CAL-02 起唯一来源=课表；9-18：开关退役——有课表自动报今天那几门，空课表不报；节流照旧）。
  // 只取课程名+时间，最多 5 条；读不到/失败都静默，不挡任何事。──

  private todayDateStr(): string {
    const d = new Date();
    return `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`;
  }

  // 节流器：每天首次进入（一天一次）+ 发送前（30 分钟一次）；失败全静默
  private async maybeReportSchedule(fromEntry: boolean): Promise<void> {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      const today = this.todayDateStr();
      const lastDay = (prefs.getSync('calendar_last_day', '') as string);
      const lastTs = (prefs.getSync('calendar_last_ts', 0) as number);
      if (fromEntry && lastDay === today) {
        return;   // 今天首次进入已经报过了
      }
      if (Date.now() - lastTs < 30 * 60 * 1000) {
        return;   // 距上次上报不到 30 分钟，不重查
      }
      // 9-17 夜：日历链路下线——来源只剩课表；课表空 = 不上报（诚实缺席，不空报）
      const ttRaw = (prefs.getSync('timetable_text', '') as string);
      if (ttRaw.trim().length === 0) {
        return;
      }
      const items = pickTimetableToday(parseTimetable(ttRaw), new Date().getDay());
      const ok = await this.postSchedule(today, items);
      if (ok) {
        prefs.putSync('calendar_last_day', today);
        prefs.putSync('calendar_last_ts', Date.now());
        prefs.flushSync();
      }
    } catch (err) {
      // 失败静默：日程是锦上添花，不挡聊天
    }
  }

  // （9-17 夜：fetchTodaySchedule（读系统日历）随日历链下线删除——课表是唯一来源。）

  private async postSchedule(date: string, items: ScheduleItem[]): Promise<boolean> {
    const req = http.createHttp();
    try {
      const body: ScheduleBody = { date: date, items: items };
      const res = await req.request(SCHEDULE_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(body),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      return res.responseCode >= 200 && res.responseCode < 300;
    } catch (err) {
      return false;
    } finally {
      req.destroy();
    }
  }

  // ── CAL-02（9-13）：课表保存——原文存 preferences（存了就一直在），
  // 当场解析校验：N 行懂了、M 行没看懂，没看懂的行原样列出来并给格式提示（不许静默吞行）──
  // ── KB-EDIT（9-17 夜）：课表图形化编辑器——载入/增删改/保存（保存仍走 saveTimetable）──
  private openKbEditor(): void {
    const parsed = parseTimetable(this.timetableDraft);
    const arr: TtEntry[] = [];
    for (let i = 0; i < parsed.entries.length; i++) {
      arr.push({ dow: parsed.entries[i].dow, from: parsed.entries[i].from,
        to: parsed.entries[i].to, title: parsed.entries[i].title, time: parsed.entries[i].time });
    }
    this.kbEntries = arr;
    this.kbBadLines = parsed.bad;   // 9-18 修复批八（APP2-01）：坏行带进编辑器（面板列出），保存时拼回
    this.kbSel = -1;
    this.kbEditOpen = true;
  }

  private kbDayList(d: number): TtEntry[] {
    const out: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].dow === d) {
        out.push(this.kbEntries[i]);
      }
    }
    return out;
  }

  private kbIndexOf(d: number, k: number): number {
    let seen = 0;
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].dow === d) {
        if (seen === k) {
          return i;
        }
        seen = seen + 1;
      }
    }
    return -1;
  }

  private kbAdd(d: number): void {
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].title.trim().length > 0) {
        arr.push(this.kbEntries[i]);   // 加新课前先丢弃没落格的草稿（等于放弃未保存的编辑）
      }
    }
    if (this.kbTimeMode) {
      // 9-18：时间模式下加课——草稿直接按直写时间立（from/to 归 0，沿用既有约定），默认 08:00-09:40
      arr.push({ dow: d, from: 0, to: 0, title: '', time: '08:00-09:40' });
      this.kbTFrom = '08:00';
      this.kbTTo = '09:40';
    } else {
      arr.push({ dow: d, from: 1, to: 2, title: '' });
    }
    this.kbEntries = arr;
    this.kbSel = arr.length - 1;
    this.kbName = '';
    this.kbFrom = 1;
    this.kbTo = 2;
  }

  private kbPick(i: number): void {
    const e = this.kbEntries[i];
    this.kbSel = i;
    this.kbName = e.title;
    this.kbFrom = e.from;
    this.kbTo = e.to;
    if (this.kbFrom < 1) {
      this.kbFrom = 1;   // 9-18 直写时间条目（from=0）：节次控件给安全初值——防编辑面板取正典节次时越界
    }
    if (this.kbTo < 1) {
      this.kbTo = 2;
    }
    const t: string | undefined = e.time;
    if (t !== undefined && t.length > 0) {
      // 9-18：点开直写时间条目——回填原时间、直接以时间模式打开（节次控件只是安全占位）
      this.kbTimeMode = true;
      this.kbTFrom = t.substring(0, 5);
      this.kbTTo = t.substring(6, 11);
    } else {
      this.kbTimeMode = false;
    }
  }

  private kbStep(fromSide: boolean, delta: number): void {
    if (fromSide) {
      let v = this.kbFrom + delta;
      if (v < 1) {
        v = 1;
      }
      if (v > 13) {
        v = 13;
      }
      this.kbFrom = v;
      if (this.kbTo < v) {
        this.kbTo = v;
      }
    } else {
      let v = this.kbTo + delta;
      if (v < 1) {
        v = 1;
      }
      if (v > 13) {
        v = 13;
      }
      this.kbTo = v;
      if (this.kbFrom > v) {
        this.kbFrom = v;
      }
    }
  }

  // 9-18 模式切换：节次→时间按正典展开（此节开始~彼节结束）；时间→节次找最近的正典节次（精确匹配优先）
  private kbSetTimeMode(on: boolean): void {
    if (on === this.kbTimeMode) {
      return;
    }
    if (on) {
      this.kbTFrom = PERIOD_SLOTS[this.kbFrom - 1].split('-')[0];
      this.kbTTo = PERIOD_SLOTS[this.kbTo - 1].split('-')[1];
    } else {
      const k = ttClosestPeriod(this.kbTFrom, this.kbTTo);
      this.kbFrom = k[0];
      this.kbTo = k[1];
    }
    this.kbTimeMode = on;
  }

  // 时间模式步进：先走一步，再静默钳住 从<到——到 ≤ 从 就把「到」推到「从」+5 分钟，
  // 「到」已在 23:55 顶格则把「从」退到 23:50；不弹错，绝不越界
  private kbTStep(fromSide: boolean, hourStep: boolean, delta: number): void {
    const d = (hourStep ? 60 : 5) * delta;
    if (fromSide) {
      this.kbTFrom = ttStep(this.kbTFrom, d);
    } else {
      this.kbTTo = ttStep(this.kbTTo, d);
    }
    if (ttMin(this.kbTTo) <= ttMin(this.kbTFrom)) {
      this.kbTTo = ttStep(this.kbTFrom, 5);
    }
    if (ttMin(this.kbTTo) <= ttMin(this.kbTFrom)) {
      this.kbTFrom = ttStep(this.kbTTo, -5);
    }
  }

  private kbApply(): void {
    const name = this.kbName.trim();
    if (this.kbSel < 0 || this.kbSel >= this.kbEntries.length || name === '') {
      return;
    }
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (i === this.kbSel) {
        if (this.kbTimeMode) {
          // 9-18 时间模式：直写时间条目（from/to 归 0，沿用既有约定）——取代旧的「只改名保留时间」hack
          arr.push({ dow: this.kbEntries[i].dow, from: 0, to: 0, title: name,
            time: this.kbTFrom + '-' + this.kbTTo });
        } else {
          // 节次模式：写节次、不带 time（切回节次=接受丢直写时间，回正典节次）
          arr.push({ dow: this.kbEntries[i].dow, from: this.kbFrom,
            to: this.kbTo, title: name });
        }
      } else {
        arr.push(this.kbEntries[i]);
      }
    }
    this.kbEntries = arr;
    this.kbSel = -1;
  }

  private kbDelete(): void {
    if (this.kbSel < 0 || this.kbSel >= this.kbEntries.length) {
      return;
    }
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (i !== this.kbSel) {
        arr.push(this.kbEntries[i]);
      }
    }
    this.kbEntries = arr;
    this.kbSel = -1;
  }

  private kbSaveAll(): void {
    // 9-18 修复批八（APP2-01）：课名里的「，」「；」是格式的分段符，存下去这条课会整行解析失败——
    // 存前换成「·」（比拒绝少一次往返，提示语里说一声）
    let renamed = 0;
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      const e = this.kbEntries[i];
      const t = e.title.split('，').join('·').split('；').join('·');
      if (t !== e.title) {
        renamed = renamed + 1;
      }
      arr.push({ dow: e.dow, from: e.from, to: e.to, title: t, time: e.time });
    }
    let text = serializeTimetable(arr);
    if (this.kbBadLines.length > 0) {
      // 没看懂的行原样拼回尾部：编辑器只管它看懂的条目，坏行不许被它无声抹掉
      text = text + (text === '' ? '' : '\n') + this.kbBadLines.join('\n');
    }
    this.timetableDraft = text;
    this.saveTimetable();   // 老路：存偏好 + 校验提示（timetableMsg 显示在设置页）
    if (renamed > 0) {
      this.timetableMsg = this.timetableMsg
        + `（${renamed} 条课名里的「，；」已存成「·」——这俩是课表格式的分段符）`;
    }
    this.kbEditOpen = false;
  }

  private saveTimetable(): void {
    const raw = this.timetableDraft;
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      prefs.putSync('timetable_text', raw);
      prefs.flushSync();
    } catch (err) {
      // 存不下也先把校验结果给到——大不了下次再存一遍
    }
    const parsed = parseTimetable(raw);
    const m = parsed.bad.length;
    if (raw.trim() === '') {
      this.timetableMsg = '课表已存（还是空的）：一行一门课，比如「周一 1-2节 高数」。';
      return;
    }
    if (m === 0) {
      this.timetableMsg = `课表已存：${parsed.good} 行懂了、0 行没看懂。`;
      return;
    }
    let msg = `课表已存：${parsed.good} 行懂了、${m} 行没看懂\n没看懂的行：\n`;
    for (let i = 0; i < parsed.bad.length; i++) {
      msg = msg + parsed.bad[i] + '\n';
    }
    msg = msg + '格式示例：周一 1-2节 高数 @十教 / 周四 18:10-19:30 课外活动（行首周X；课次写节次 1~13 或直接写时间都行；一行多门用；隔开）';
    this.timetableMsg = msg;
  }

  // ── 思考链查看页（工单 9-1-#4）：点开「💭 看看想法」全屏看原文 ──
  @Builder
  ThinkingPage() {
    Column() {
      Row() {
        Text('💭 姐姐刚才的想法')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
.stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.thinkingOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Text(this.thinkingText)
          .fontSize(FS_SUB)
          .lineHeight(22)
          .fontColor(this.dk(C_TEXT))
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(this.dk(C_BG))
  }

  // 先查本地缓存（本轮新回复直接有），没有再问 server 要（历史气泡）
  private async openThinking(item: ChatItem): Promise<void> {
    const cached = this.thinkingCache.get(item.key);
    if (cached !== undefined) {
      this.thinkingText = cached || '（这条没留下想法）';
      this.thinkingOpen = true;
      return;
    }
    if (!item.msgId) {
      this.thinkingText = '（这条没有想法记录）';
      this.thinkingOpen = true;
      return;
    }
    const req = http.createHttp();
    try {
      const res = await req.request(THINKING_URL + `?chat_id=${item.msgId}`, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as ThinkingResp;
        const t = d.thinking ?? '（这条没留下想法）';
        this.thinkingCache.set(item.key, t);
        this.thinkingText = t;
        this.thinkingOpen = true;
      } else {
        this.thinkingText = '（想法没取到，再点一次）';
        this.thinkingOpen = true;
      }
    } catch (err) {
      this.thinkingText = '（想法没取到，检查网络）';
      this.thinkingOpen = true;
    } finally {
      req.destroy();
    }
  }

  // ── 日常页（9-12 家主令：打卡+心情合体）——上打卡下心情，一页滚到底 ──
  @Builder
  DailyPage() {
    Column() {
      Row() {
        Text('🏠 日常')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 4 })

      Scroll() {
        Column() {
          this.CheckinPage()
          Divider()
            .color(this.dk(C_DOT_BORDER))
            .margin({ left: M_PAGE, right: M_PAGE })
          this.MoodPage()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.dk(C_BG))
  }

  @Builder
  CheckinPage() {
    Column() {
      Row() {
        Text('✓ 打卡')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      if (this.checkinDetailId >= 0) {
        this.CheckinDetailPage()
      } else {
      // ── 今日进度环（CHECKIN-2）：完成 N/M——打一项亮一格，漏了就是漏了（不许补打） ──
      Row({ space: 14 }) {
        Progress({ value: this.checkinDoneCount(), total: this.checkinTotalCount() > 0 ? this.checkinTotalCount() : 1, type: ProgressType.Ring })
          .width(64)
          .height(64)
          .color(this.dk(C_ACCENT))
          .backgroundColor(this.dk(C_CARD))
          .style({ strokeWidth: 6 })
        Column({ space: 3 }) {
          Text(`今天 ${this.checkinDoneCount()}/${this.checkinTotalCount()}`)
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))
          Text(this.checkinTotalCount() > 0 ? `完成 ${this.checkinDoneCount()}/${this.checkinTotalCount()} 项` : '还没有打卡项')
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_4))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 2, bottom: 6 })

      Text('点按打卡，长按归档（归档不删历史）')
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_5))
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })

      if (this.checkinMsg) {
        Text(this.checkinMsg)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_3))
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })
      }

      // 内层不再用 List（9-12 修「日常页滚不动」：嵌套可滚组件抢手势，统一外层滚）
      Column({ space: 8 }) {
        ForEach(this.checkinItems, (item: CheckinItem) => {
            Row() {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(item.name)
                    .fontSize(FS_BODY)
                    .fontColor(this.dk(C_TEXT))
                  if (this.streakOf(item.id) >= 2) {
                    Text(`🔥 连续 ${this.streakOf(item.id)} 天`)
                      .fontSize(FS_AUX)
                      .fontColor(this.dk(C_ACCENT))
                  }
                }
                if (item.target_time) {
                  Text(`目标 ${item.target_time}`)
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_5))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.checkedToday.includes(item.id)) {
                Text('已打 ✓')
                  .fontSize(FS_SUB)
                  .fontColor(this.dk(C_OK))
                  .padding({ left: 12, right: 4 })
              } else {
                Button('打卡')
                  .fontSize(FS_SUB)
                  .height(40)
                  .fontColor(this.dk(C_WHITE))
                  .backgroundColor(this.checkinBusy ? this.dk(C_DISABLED) : this.dk(C_ACCENT))
                  .borderRadius(R_PILL)
                  .enabled(!this.checkinBusy)   // 9-18 App深搜修（DS-05）：在途置灰防连点
.stateStyles({ pressed: pressDim, normal: pressFull })
                  .onClick(() => {
                    this.checkinTapTs = Date.now();   // LAY-07：点「打卡」就是打卡，别顺带把详情也开了
                    this.doCheckin(item);
                  })
              }

              // 右侧箭头 → 项详情（CHECKIN-2）：点开看这个月的月历热力图
              // LAY-07（9-23）：箭头补竖 padding ≥40vp；整行也可点进详情（长按归档保留）
              Text('›')
                .fontSize(22)
                .fontColor(this.dk(C_TEXT_5))
                .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.checkinDetailId = item.id;
                })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(this.dk(C_PANEL))
            .borderRadius(R_MD)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              // LAY-07：整行点开详情；刚点过「打卡」的那一下不算（点击是否冒泡到这儿都稳）
              if (Date.now() - this.checkinTapTs < 500) {
                return;
              }
              this.checkinDetailId = item.id;
            })
            .gesture(LongPressGesture().onAction(() => {
              this.confirmArchive(item);
            }))
        }, (item: CheckinItem) => `${item.id}`)

        // 打卡项增删走姐姐（9-2 #总）：页内不再自助，跟姐姐说一声就办了
        Text('想加项、想去项？跟姐姐说一声就好')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 4 })
      }   // else（列表态）收口——CHECKIN-2
    }
    .width('100%')
    .padding({ top: 12 })   // 常驻分页后系统自动避让，不再吃模态避让区
    .backgroundColor(this.dk(C_BG))
    .onAppear(() => {
      this.fetchCheckinData();
      this.fetchMonthCheckins();   // CHECKIN-2（9-13）：进打卡页顺手拉月视图（失败静默保留旧数据）
    })
  }

  // ── 项详情（CHECKIN-2）：月历热力图。7 列网格、本月实际天数；打过=墨色圆点、漏打=空——
  // 灰格子点了没反应（不许补打：漏了就是灰格子，账本是诚实的） ──
  @Builder
  CheckinDetailPage() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('‹ 返回')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_ACCENT))
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })   // LAY-07：触摸目标补到 ≥40vp
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.checkinDetailId = -1;
          })
        Text(this.detailName())
          .fontSize(FS_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
      }
      .width('100%')

      Text(`本月 ${this.detailDays().length} 天 · 最长 🔥${this.detailBest()} 天`)
        .fontSize(FS_SUB)
        .fontColor(this.dk(C_TEXT_2))
        .width('100%')

      Column({ space: 6 }) {
        ForEach(this.detailWeeks(), (row: number[]) => {
          Row({ space: 6 }) {
            ForEach(row, (d: number) => {
              Stack() {
                Text(`${d}`)
                  .fontSize(FS_AUX)
                  .fontColor(this.detailHasDay(d) ? this.dk(C_WHITE) : this.dk(C_TEXT_5))
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor(this.detailHasDay(d) ? this.dk(C_ACCENT) : this.dk(C_CARD))
            }, (d: number) => `${d}`)
          }
          .width('100%')
        }, (row: number[]) => `r${row[0]}`)
      }
      .width('100%')

      if (this.detailDays().length === 0) {
        Text('这个月还空着——今天打上，第一格就亮。')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  // 拉在册打卡项 + 今日已打，合成"已打"状态
  private async fetchCheckinData(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(CHECKIN_ITEMS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as CheckinItemsResp;
        this.checkinItems = d.items ?? [];
      } else {
        this.checkinMsg = `打卡项没拉下来：HTTP ${res.responseCode}`;
      }
    } catch (err) {
      this.checkinMsg = '打卡项没拉下来（检查 Tailscale 和 server）';
    } finally {
      req.destroy();
    }
    const req2 = http.createHttp();
    try {
      const res = await req2.request(CHECKINS_TODAY_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as TodayCheckinsResp;
        this.checkedToday = (d.checkins ?? []).map((c: TodayCheckin) => c.item_id);
      }
    } catch (err) {
      // 已打状态拉不到就只显示未打，不阻断
    } finally {
      req2.destroy();
    }
  }

  // CHECKIN-2（9-13）：拉当月月视图——卡片上的连续🔥与项详情的热力图都吃这份数
  private async fetchMonthCheckins(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(CHECKINS_MONTH_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as MonthCheckinsResp;
        this.monthItems = d.items ?? [];
      }
    } catch (err) {
      // 静默：月视图是锦上添花，不挡打卡主流程（保留旧数据）
    } finally {
      req.destroy();
    }
  }

  // CHECKIN-2：进度环与连续🔥的小账房
  private checkinDoneCount(): number {
    let n = 0;
    for (let i = 0; i < this.checkinItems.length; i++) {
      if (this.checkedToday.includes(this.checkinItems[i].id)) {
        n++;
      }
    }
    return n;
  }

  private checkinTotalCount(): number {
    return this.checkinItems.length;
  }

  private streakOf(itemId: number): number {
    for (let i = 0; i < this.monthItems.length; i++) {
      if (this.monthItems[i].item_id === itemId) {
        return this.monthItems[i].streak;
      }
    }
    return 0;
  }

  // CHECKIN-2 项详情取数（月视图没拉到就先空着——灰着是灰着）
  private detailName(): string {
    for (let i = 0; i < this.checkinItems.length; i++) {
      if (this.checkinItems[i].id === this.checkinDetailId) {
        return this.checkinItems[i].name;
      }
    }
    return '';
  }

  private detailDays(): number[] {
    for (let i = 0; i < this.monthItems.length; i++) {
      if (this.monthItems[i].item_id === this.checkinDetailId) {
        return this.monthItems[i].days;
      }
    }
    return [];
  }

  private detailBest(): number {
    for (let i = 0; i < this.monthItems.length; i++) {
      if (this.monthItems[i].item_id === this.checkinDetailId) {
        return this.monthItems[i].best;
      }
    }
    return 0;
  }

  private detailHasDay(d: number): boolean {
    return this.detailDays().includes(d);
  }

  private detailMonthDays(): number {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  }

  private detailWeeks(): number[][] {
    const total = this.detailMonthDays();
    const out: number[][] = [];
    let row: number[] = [];
    for (let d = 1; d <= total; d++) {
      row.push(d);
      if (row.length === 7) {
        out.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      out.push(row);
    }
    return out;
  }

  private async doCheckin(item: CheckinItem): Promise<void> {
    if (this.checkinBusy) {
      return;   // 9-18 App深搜修（DS-05）：响应落地前再点会被闸住，同日不再落重复记录
    }
    this.checkinBusy = true;
    const checkinBody: CheckinReqBody = { item_id: item.id };
    const req = http.createHttp();
    try {
      const res = await req.request(CHECKIN_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(checkinBody),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.checkedToday = this.checkedToday.concat(item.id);
        this.checkinMsg = `已打卡：${item.name} ${this.nowTime()}`;
        this.fetchMonthCheckins();   // CHECKIN-2（9-13）：打卡成功后顺手刷新月视图（连续🔥涨一格）
      } else if (res.responseCode === 404) {
        this.checkinMsg = `「${item.name}」已归档，列表刷新一下`;
        this.fetchCheckinData();
      } else {
        this.checkinMsg = `没打上：HTTP ${res.responseCode}，再点一次`;
      }
    } catch (err) {
      this.checkinMsg = '没打上，网络不通时再点一次';
    } finally {
      req.destroy();
      this.checkinBusy = false;   // 9-18 App深搜修（DS-05）：无论成败都放闸
    }
  }

  private confirmArchive(item: CheckinItem): void {
    AlertDialog.show({
      title: `归档「${item.name}」？`,
      message: '归档后列表里不再出现，历史打卡记录还在',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '归档',
        fontColor: this.dk(C_ACCENT),
        action: () => {
          this.archiveCheckinItem(item);
        }
      }
    });
  }

  private async archiveCheckinItem(item: CheckinItem): Promise<void> {
    const archiveBody: ArchiveReqBody = { id: item.id };
    const req = http.createHttp();
    try {
      const res = await req.request(CHECKIN_ARCHIVE_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(archiveBody),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.checkinMsg = `已归档：${item.name}`;
        this.checkedToday = this.checkedToday.filter((id: number) => id !== item.id);
        this.fetchCheckinData();
      } else {
        this.checkinMsg = `归档没成：HTTP ${res.responseCode}`;
      }
    } catch (err) {
      this.checkinMsg = '归档没成，网络不通时再试';
    } finally {
      req.destroy();
    }
  }

  @Builder
  MsgBubble(item: ChatItem) {
    if (item.who === '系统') {
      // 系统提示：居中灰色小字
      Row() {
        Text(item.text)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (item.who === '思考') {
      // 思考步骤卡（9-12 时间线版）：占位「叫姐姐中…」→活跃卡计时→封口「思考了 Ns」，
      // 点一下展开流式原文尾段（Kimi 步骤卡同款）；全文走 💭 看想法
      Row() {
        Text(!this.thinkPeek
          ? (item.thinkDone || item.time === '叫姐姐中…' ? `💭 ${item.time}`
            : `💭 姐姐思考中… ${this.thinkingSec.toFixed(1)}s`)
          : `💭 ${item.text.length > 300 ? '…' + item.text.substring(item.text.length - 300) : item.text}`)
          .fontSize(!this.thinkPeek ? FS_BODY : FS_AUX)
          .fontColor(this.dk(C_TEXT_3))
          .padding(12)
          .backgroundColor(this.dk(C_WHITE))
          .border({ width: 1, color: this.dk(C_HER_EDGE) })
          .borderRadius({ topLeft: R_XL, topRight: R_XL, bottomLeft: R_TAIL, bottomRight: R_XL })
          .onClick(() => {
            this.thinkPeek = !this.thinkPeek;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    } else if (item.who === '工具') {
      // 工具步骤卡（9-12 时间线，Kimi 客户端式）：🔧 调用工具 XX——独立小卡一眼可见
      Row({ space: 6 }) {
        Text(`🔧 ${item.text}`)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_2))
          .constraintSize({ maxWidth: '78%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    } else if (item.who === '姐姐' && item.text.startsWith('（姐姐掉线了')) {
      // 掉线错误记录：淡化成小字灰显，不折叠、不占气泡
      Row() {
        Text(item.text)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .lineHeight(18)
          .constraintSize({ maxWidth: '78%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    } else if (item.who === '小乖') {
      // 小乖：靠右奶咖气泡 + 下方时间小字
      Row() {
        Column() {
          Column({ space: 6 }) {
            if (item.imageUrl) {
              if (this.imgErrKeys.includes(item.imageUrl)) {
                this.ImgGoneTip()   // FE3-08（9-23）：图没取到就直说（门锁/隧道），不静默裂图
              } else {
                Image(item.imageUrl)
                  .constraintSize({ maxWidth: 220 })
                  .borderRadius(R_MD)
                  .objectFit(ImageFit.Contain)
                  .onClick(() => {
                    this.imgPreviewUrl = item.imageUrl;   // FE-02 ②：点图看大图
                  })
                  .onError(() => {
                    this.markImgErr(item.imageUrl);
                  })
              }
            }
            if (item.fileName) {
              Text(`📄 ${item.fileName}`)
                .fontSize(FS_SUB)
                .fontColor(this.dk(C_TEXT))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (item.text) {
              Text(item.text)
                .fontSize(FS_BODY)
                .lineHeight(24)
                .fontColor(this.dk(C_TEXT))
                .gesture(LongPressGesture().onAction(() => {
                  this.copyBubbleText(item.text);   // FE-02 ③：长按正文复制
                }))
            }
          }
          .alignItems(HorizontalAlign.End)
          .padding(12)
          .backgroundColor(this.dk(C_BUBBLE_ME))
          .borderRadius({ topLeft: R_XL, topRight: R_XL, bottomLeft: R_XL, bottomRight: R_TAIL })

          Text(item.time)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_5))
            .margin({ top: 4, right: 2 })
        }
        .alignItems(HorizontalAlign.End)
        .constraintSize({ maxWidth: '78%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    } else {
      // 姐姐：靠左白气泡细边框 + 下方时间小字
      Row() {
        Column() {
          // 图书证使用卡（FE-03 v2）：回复气泡上方单独画、默认可见不折叠——💭 折叠的只是思考链原文。
          // 只读工具显示友好名；动作工具友好名后跟内容摘要（纸条 40 字/项名/文件名），不再直出 JSON。
          if (item.tools && item.tools.length > 0) {
            Column({ space: 4 }) {
              ForEach(item.tools, (t: ToolUseInfo, idx: number) => {
                Row({ space: 6 }) {
                  Text(`${this.toolCn(t.name)} ${this.toolSummary(t.name, t.args)}`.trim())
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_3))
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('已完成')
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_5))
                }
                .width('100%')
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .backgroundColor(this.dk(C_CARD))
                .borderRadius(R_SM)
              }, (t: ToolUseInfo, idx: number) => `${t.name}-${t.rounds}-${idx}`)
            }
            .width('100%')
            .margin({ bottom: 4 })
          }

          Column({ space: 6 }) {
            if (item.imageUrl) {
              if (this.imgErrKeys.includes(item.imageUrl)) {
                this.ImgGoneTip()   // FE3-08（9-23）：图没取到就直说（门锁/隧道），不静默裂图
              } else {
                Image(item.imageUrl)
                  .constraintSize({ maxWidth: 220 })
                  .borderRadius(R_MD)
                  .objectFit(ImageFit.Contain)
                  .onClick(() => {
                    this.imgPreviewUrl = item.imageUrl;   // FE-02 ②：点图看大图
                  })
                  .onError(() => {
                    this.markImgErr(item.imageUrl);
                  })
              }
            }
            if (item.text) {
              Text(item.text)
                .fontSize(FS_BODY)
                .lineHeight(24)
                .fontColor(this.dk(C_TEXT))
                .gesture(LongPressGesture().onAction(() => {
                  this.copyBubbleText(item.text);   // FE-02 ③：长按正文复制
                }))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor(this.dk(C_WHITE))
          .border({ width: 1, color: this.dk(C_HER_EDGE) })
          .borderRadius({ topLeft: R_XL, topRight: R_XL, bottomLeft: R_TAIL, bottomRight: R_XL })

          Text(item.time)
            .fontSize(FS_AUX)
            .fontColor(this.dk(C_TEXT_5))
            .margin({ top: 4, left: 2 })

          if (item.hasThinking) {
            Text('💭 看看想法')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_ACCENT))
              .margin({ top: 4, left: 2 })
              .padding({ top: 8, bottom: 8, left: 14, right: 14 })
              .backgroundColor(this.dk(C_CARD))
              .borderRadius(R_LG)
              .onClick(() => {
                this.openThinking(item);
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: '78%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
  }

  private nowTime(): string {
    const d = new Date();
    const h = d.getHours();
    const m = d.getMinutes();
    return `${h < 10 ? '0' + h : h}:${m < 10 ? '0' + m : m}`;
  }

  private toolCn(name: string): string {
    if (name === 'search_chats') {
      return '📖 翻聊天记录';
    }
    if (name === 'search_diary') {
      return '📔 翻日记';
    }
    if (name === 'search_archive') {
      return '🗂 翻档案';
    }
    // 手表已清退（9-23）；这两条标签保留——历史消息里的工具卡还靠它显示中文
    if (name === 'get_heart_rate') {
      return '❤️ 看了眼你的心跳';
    }
    if (name === 'request_heart') {
      return '💓 姐姐想听你的心跳';
    }
    if (name === 'get_checkins') {
      return '✓ 看了眼打卡';
    }
    // ── FE-03 补全：十六只图书证每只都有人话名（与 server LIBRARY_TOOLS 一一对照）──
    if (name === 'search_events') {
      return '📜 翻大事记';
    }
    if (name === 'search_memory') {
      return '🔍 翻了翻咱家记忆';
    }
    if (name === 'get_notes') {
      return '📝 看了眼小本本';
    }
    if (name === 'read_letters') {
      return '✉️ 拆开你的来信';
    }
    if (name === 'jot_down') {
      return '📝 悄悄记了一笔';
    }
    if (name === 'favorite_photo') {
      return '🖼 收进了收藏夹';
    }
    if (name === 'add_checkin_item') {
      return '✓ 加了个打卡项';
    }
    if (name === 'archive_checkin_item') {
      return '📦 归档了打卡项';
    }
    if (name === 'write_diary') {
      return '📔 写了篇日记';
    }
    if (name === 'compose_letter') {
      return '💌 写了封长信';
    }
    if (name === 'send_email') {
      return '📧 寄了封真信';
    }
    return name;
  }

  // ── FE-03 要求2：动作工具的内容摘要——args 是 JSON 串，解析出人话；解析不动就空着只显示友好名 ──
  private toolSummary(name: string, argsJson: string): string {
    let a: Record<string, string> = {};
    try {
      a = JSON.parse(argsJson) as Record<string, string>;
    } catch (err) {
      return '';
    }
    if (name === 'jot_down') {
      const t = a['text'] ?? '';
      return t.length > 40 ? t.substring(0, 40) + '…' : t;   // 记的纸条前 40 字
    }
    if (name === 'add_checkin_item' || name === 'archive_checkin_item') {
      return a['name'] ?? '';   // 打卡项名
    }
    if (name === 'favorite_photo') {
      return a['name'] ?? '';   // 照片文件名
    }
    return '';
  }

  private appendMsg(who: string, text: string, imageUrl: string, time?: string, tools?: ToolUseInfo[],
                    hasThinking?: boolean, msgId?: number, fileName?: string): string {
    const item: ChatItem = {
      key: `k${this.keySeq++}`,
      who: who,
      text: text,
      imageUrl: imageUrl,
      time: time ?? this.nowTime(),
      tools: tools,
      msgId: msgId,
      hasThinking: hasThinking,
      fileName: fileName,
    };
    this.chatData.append(item);
    this.scrollToEnd();
    return item.key;
  }

  // 贴底（9-26 审计修 P3）：原「100ms 一把梭」——列表刚追加、还没长出条数时那一把空放，
  // 气泡就停在半空。改成有界重试：数出来了才滚，最多试 6 次（约 600ms）收手；已贴底的照旧。
  private scrollToEnd(tries: number = 0): void {
    setTimeout(() => {
      const n = this.chatData.totalCount();
      if (n > 0) {
        this.scroller.scrollToIndex(n - 1);
      } else if (tries < 6) {
        this.scrollToEnd(tries + 1);
      }
    }, 100);
  }

  // ── 上下文面板 ──
  private togglePanel(): void {
    this.panelOpen = !this.panelOpen;
    if (this.panelOpen) {
      this.fetchStatus();   // 9-2 #12：常开 statusTimer 已接管周期刷新，开面板只立即补一次
    }
  }

  // 9-18 优化批二：一键拉耳朵——POST 后缓一拍再刷状态（server 侧拉桥握手要几秒）
  private async raiseBridge(): Promise<void> {
    if (this.bridgeBusy) {
      return;
    }
    this.bridgeBusy = true;
    this.bridgeMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(BRIDGE_UP_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: '{}',
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as BridgeUpResp;
        this.bridgeMsg = d.msg ?? (d.ok === true ? '耳朵拉起来了' : '没拉动');
        setTimeout(() => {
          this.fetchStatus();
        }, 2000);
      } else {
        this.bridgeMsg = `没拉起来（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.bridgeMsg = '没拉起来（网络没通）';
    } finally {
      req.destroy();
      this.bridgeBusy = false;
    }
  }

  private async fetchStatus(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(STATUS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as StatusResp;
        this.stNow = d.now ?? '—';
        this.stWeather = d.weather ?? '—';
        if (d.loc) {
          const coord = `北纬 ${d.loc.lat.toFixed(4)}，东经 ${d.loc.lon.toFixed(4)}`;
          this.stPlace = d.loc.place ? `${d.loc.place}（${coord}）` : coord;
          this.stLocTime = d.loc.time ?? '';
        } else {
          this.stPlace = '—';
          this.stLocTime = '';
        }
        this.stChats = d.chats_today !== undefined ? `${d.chats_today}` : '—';
        this.asleep = d.asleep ?? false;
        // 9-4 自由发挥包：server 心电图 + 收藏夹计数
        if (d.server_up_min !== undefined && d.server_up_min !== null) {
          const h = Math.floor(d.server_up_min / 60);
          const mins = d.server_up_min % 60;
          this.stServer = `${d.server_up_since ?? ''} 开工，跑了 ${h > 0 ? h + ' 小时 ' : ''}${mins} 分`;
        } else {
          this.stServer = '—';
        }
        this.stFav = d.favorites_count !== undefined ? `${d.favorites_count}` : '—';
        this.stLetters = d.letters_unread ?? 0;   // 9-9 家主信箱行
        // 9-17 夜·状态栏：Garden 耳朵（唤醒桥）在不在岗 + 今日园子动静
        const gBridge = d.garden_bridge === true;
        const gToday = d.garden_today;
        this.stBridgeUp = gBridge;   // 9-18：拉桥按钮据此显隐
        if (gToday !== undefined && gToday !== null) {
          this.stGarden = `${gBridge ? '耳朵在岗 ✓' : '耳朵未挂'} · 今日园子 ${gToday} 条`;
        } else {
          this.stGarden = gBridge ? '耳朵在岗 ✓' : '耳朵未挂';
        }
        // 9-23 B2-2：散步状态条——三闸现值只读投影；键缺/值 null 整行不出（旧 server 兼容）
        const gw = d.garden_walk;
        if (gw && gw.walks_today !== undefined && gw.walks_today !== null
          && gw.walk_allowed !== undefined && gw.walk_allowed !== null) {
          this.stWalk = `🚶 散步：今日 ${gw.walks_today} 次 · ${gw.walk_allowed ? '现在可以出门溜达' : '刚回过家，先歇歇'}`;
        } else {
          this.stWalk = '';
        }
        // 9-18 优化批一：最近一条来信指纹——她说「你说过 X」时一眼对账
        if (d.last_letter) {
          const ll = d.last_letter;
          const atFull = ll.at ?? '';
          const at = atFull.length >= 16 ? atFull.substring(11, 16) : atFull;
          this.stLetter = `${at} #${ll.id} ${ll.md5 ?? ''}「${ll.peek ?? ''}」`;
        } else {
          this.stLetter = '—';
        }
        // 引擎仪表（9-10）：她的想念值 + Seline 事实句（只报事实不打分）
        if (d.longing_p !== undefined && d.longing_p !== null) {
          this.stLonging = d.longing_p;
        } else {
          this.stLonging = -1;
        }
        const facts = d.rhythm_7d;
        if (facts && facts.letters !== null && facts.letters !== undefined) {
          const avgTxt = (facts.avg_reply_min !== null && facts.avg_reply_min !== undefined)
            ? `，平均 ${facts.avg_reply_min} 分钟回她` : '';
          this.stFacts = `近 7 天：她主动开口 ${facts.letters} 次，你回了 ${facts.replies ?? '—'} 次${avgTxt}`;
        } else {
          this.stFacts = '';
        }
        // 9-18 #15·想念仪表：引擎刚才在想什么——整个键缺席（旧 server）就整行不出，绝不报错
        const why = d.why_now;
        if (why) {
          const wLast = why.last ?? '';
          if (wLast !== '') {
            this.stWhyNow = `🫀 引擎最近：${wLast}（近7天 开口×${why.opens_7d ?? '—'}·忍住×${why.holds_7d ?? '—'}）`;
          } else {
            this.stWhyNow = '🫀 引擎：还没照过面';
          }
        } else {
          this.stWhyNow = '';
        }
        // 9-23 能上批 c：对账观测（obs_7d 十键→三行人话，零新请求）——
        // 全 0 不出行、键缺整段不出（旧 server 上想念卡一字不变）；RV-01 起键名照服务端实测（claim_*/l2_*）
        this.stObs1 = '';
        this.stObs2 = '';
        this.stObs3 = '';
        const obs = d.obs_7d;
        if (obs) {
          const claimN = obs.claim_named ?? 0;
          const passN = obs.claim_passed ?? 0;
          const shadowN = obs.claim_shadow ?? 0;
          const heldN = obs.claim_held ?? 0;
          if (claimN + passN + shadowN + heldN > 0) {
            this.stObs1 = `🛡 对账（近 7 天）：提名 ${claimN} · 放行 ${passN} · 影子 ${shadowN} · 打回 ${heldN}`;
          }
          const fakeN = obs.fake_tool ?? 0;
          const recallN = obs.recall ?? 0;
          const recallHitN = obs.recall_hit ?? 0;
          if (fakeN + recallN + recallHitN > 0) {
            this.stObs2 = `🧰 假工具调用拦下 ${fakeN} 次 · 开场检索 ${recallN} 次（命中 ${recallHitN} 次）`;
          }
          const classN = obs.l2_in_class ?? 0;
          const sleptN = obs.l2_just_slept ?? 0;
          const idleN = obs.l2_idle_boost ?? 0;
          if (classN + sleptN + idleN > 0) {
            this.stObs3 = `🕰 时机感知：上课压 ${classN} · 刚睡压 ${sleptN} · 闲抬 ${idleN}`;
          }
        }
        // 9-26：线头盒观测（悬线数/最老几天）——只报事实不打分；键缺/空盒不出行（照 obs 家风）
        this.stThreads = '';
        const th = d.threads;
        if (th && th.open !== undefined && th.open !== null && th.open > 0) {
          const od = (th.oldest_days !== undefined && th.oldest_days !== null)
            ? `，最老一条挂了 ${th.oldest_days} 天` : '';
          this.stThreads = `🧵 线头盒：悬着 ${th.open} 条${od}`;
        }
        // 9-26：她此刻（只用服务端给的人话句，不摆裸数值）——server_only=true 只给家主看
        this.stState = '';
        const sta = d.state;
        if (sta && sta.line !== undefined && sta.line !== null && sta.line !== '') {
          this.stState = `💗 她此刻：${sta.line}`;
        }
        // 9-26 W2：家里两本账（近 7 天说了多少、她主动几次、引擎多少笔）——只报事实，空则不出
        this.stLedger = '';
        const lg = d.ledger;
        if (lg && ((lg.his ?? 0) + (lg.hers ?? 0) + (lg.proactive ?? 0) > 0)) {
          // 9-26 修（审计 P2-2）：条件补 proactive（有主动开口但对话投为 0 时也该出行）；
          // 行尾附「账自 since 起记」——影子账不是从开天辟地记的，别让读数显得比实际全。
          const days = lg.days ?? 7;
          const tok = (lg.in_tokens ?? 0) / 10000;
          const _since = (lg.since !== undefined && lg.since !== null && lg.since !== '')
            ? `（账自 ${lg.since} 起记）` : '';
          this.stLedger = `📒 家里的账 · 近 ${days} 天：说了 ${(lg.his ?? 0) + (lg.hers ?? 0)} 句`
            + `（你 ${lg.his ?? 0} · 她 ${lg.hers ?? 0}）· 她主动开口 ${lg.proactive ?? 0} 次`
            + ` · 引擎 ${lg.calls ?? 0} 笔${_since}`;
        }
        this.fetchPromise();
        this.pushCard();
      } else {
        this.clearStatusLines();
      }
    } catch (err) {
      this.clearStatusLines();
    } finally {
      req.destroy();
    }
  }

  // 9-26 修（审计 P2-1）：取不到状态时把**所有**读数一起复位——
  // 原只复位 7 项，新增的三行仪表（🧵/💗/📒）与 why_now/longing 等会留着旧值装作还在。
  private clearStatusLines(): void {
    this.stNow = '—';
    this.stWeather = '—';
    this.stPlace = '—';
    this.stChats = '—';
    this.stObs1 = '';
    this.stObs2 = '';
    this.stObs3 = '';
    this.stWhyNow = '';
    this.stFacts = '';
    this.stLonging = -1;
    this.stThreads = '';
    this.stState = '';
    this.stLedger = '';
    this.stWalk = '';
  }

  // ── 桌面卡片推送：写 preferences（系统定时刷新读它），并主动 updateForm 已添加的卡片 ──
  private pushCard(): void {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      const lamp = this.asleep ? '☾ 睡了' : '● 醒着';
      const first = new Date(2026, 7, 24).getTime();   // 咱家第一天 2026-08-24
      const dayNo = `${Math.floor((Date.now() - first) / 86400000) + 1}`;
      let lastReply = '姐姐在这儿';
      const allMsgs = this.chatData.getAll();
      for (let i = allMsgs.length - 1; i >= 0; i--) {
        const m = allMsgs[i];
        if (m.who === '姐姐' && !m.text.startsWith('（姐姐掉线了')) {
          lastReply = m.text.split('\n')[0];
          break;
        }
      }
      prefs.putSync('statusLamp', lamp);
      prefs.putSync('dayNo', dayNo);
      prefs.putSync('lastReply', lastReply);
      prefs.flushSync();
      const raw = prefs.getSync('zanjia_form_ids', '[]') as string;
      const ids = JSON.parse(raw) as string[];
      if (ids.length > 0) {
        const obj: Record<string, string> = {
          'statusLamp': lamp,
          'dayNo': dayNo,
          'lastReply': lastReply
        };
        const data = formBindingData.createFormBindingData(obj);
        for (const id of ids) {
          formProvider.updateForm(id, data);
        }
      }
    } catch (err) {
      // 卡片推送失败不影响主链路
    }
  }

  // ── 明日约定：读今天最新日记里的〔明日约定〕段，纯显示 ──
  private async fetchPromise(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(TODAY_DIARY_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as PromiseResp;
        this.stPromise = d.promise ?? '—';
        // FE-02 门楣：同一趟请求顺手取日记首句（server 只加不改的 first 字段），没有就藏
        this.lintelText = d.first ?? '';
      } else {
        this.stPromise = '—';
        this.lintelText = '';
      }
    } catch (err) {
      this.stPromise = '—';
      this.lintelText = '';
    } finally {
      req.destroy();
    }
  }

  // ── 晚安（FE-02 要求8）：先二次确认——熄灯是仪式，不是手滑。取消无副作用 ──
  private confirmGoodnight(): void {
    AlertDialog.show({
      title: '熄灯确认',
      message: '要熄灯跟姐姐说晚安了吗？🌙',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '再等等',
        action: () => {
        }
      },
      secondaryButton: {
        value: '说晚安',
        fontColor: this.dk(C_ACCENT),
        action: () => {
          this.sayGoodnight();
        }
      }
    });
  }

  // ── 晚安 ──
  // 9-12 修误判：熄灯要等姐姐把今天的日记写完（server 侧跑模型，最长 300s），
  // 旧版 30s 就超时报「姐姐没睡着」——其实她正写着呢。readTimeout 放到 320s 对齐，
  // 文案也改诚实：超时≠没睡着，别再骗人。
  private async sayGoodnight(): Promise<void> {
    if (this.goodnightBusy) {
      return;
    }
    this.goodnightBusy = true;
    this.goodnightMsg = '熄灯中……姐姐在写今天的日记（最长三分钟），别连点';
    const req = http.createHttp();
    try {
      const res = await req.request(GOODNIGHT_URL, {
        method: http.RequestMethod.POST,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: 320000   // 与 server api_timeout 300s 对齐 + 余量
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as GoodnightResp;
        this.asleep = true;
        const parts: string[] = [];
        if (d.diary) {
          parts.push(d.diary);
        }
        if (d.note) {
          parts.push(d.note);
        }
        this.goodnightMsg = parts.join(' ');
      } else {
        this.goodnightMsg = `姐姐那边没接住（HTTP ${res.responseCode}），再点一次`;
      }
    } catch (err) {
      const code = (err as BusinessError).code ?? 0;
      if (code === 2300025 || code === 2300028) {
        // 超时/读超时：server 多半还在写日记——她已经动笔了，别再点
        this.goodnightMsg = '姐姐还在写今天的日记（没超时完成），稍等一分钟再看；别连点，日记不会丢';
      } else {
        this.goodnightMsg = '网络没通，再点一次';
      }
    } finally {
      req.destroy();
      this.goodnightBusy = false;
    }
  }

  // ── 心情页（9-9 心情曲线 v2）：情绪河 canvas + 打卡（chips→浓度→备注）+ 最近文字流 ──
  private moodCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private moodCanvasReady: boolean = false;
  private moodFullCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private moodFullReady: boolean = false;

  // 横屏全看：先切窗口方向再开全屏模态——canvas 挂载时已是横屏（2848px≈990vp 宽）
  private openRiverFull(): void {
    try {
      window.getLastWindow(getContext(this)).then((win) => {
        return win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      }).then(() => {
        this.riverFullOpen = true;
      }).catch(() => {
        this.riverFullOpen = true;   // 方向切不动也照样看（竖屏下仍比内嵌大）
      });
    } catch (err) {
      this.riverFullOpen = true;
    }
  }

  private closeRiverFull(): void {
    this.riverFullOpen = false;
    // 9-18 修复批八（APP2-03）：先清点缓存/选中序号——它们记的是大画布（≈990vp）几何，
    // 内嵌画布（≈330vp）拿去点星会"点了没反应"或弹错卡；宁可不反应，不弹错
    this.tappedIdx = -1;
    this.riverDots = [];
    this.usedKeys = [];
    try {
      // 方向还回去（工程未锁方向，交还系统自定）；方向回正、内嵌画布尺寸定下来后重画内嵌河——
      // 不重画，内嵌河的画与点缓存就一直对不上（redrawRiver 的触发点一个都不沾关闭路径）
      window.getLastWindow(getContext(this)).then((win) => {
        return win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
      }).then(() => {
        if (!this.riverFullOpen) {
          this.drawMoodRiver();
        }
      }).catch(() => {
        if (!this.riverFullOpen) {
          this.drawMoodRiver();   // 方向没回成也照画：画布尺寸没变，重画一次不亏
        }
      });
    } catch (err) {
      this.drawMoodRiver();
    }
  }

  @Builder
  MoodPage() {
    Column({ space: 10 }) {
      Row() {
        Text('💗 心情')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text('一滴墨一个心情，浓度定沉浮')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
      }
      .width('100%')

      // 内层不再自带 Scroll（9-12 修「日常页滚不动」：嵌套滚动手势打架，统一由日常页外层滚）
      Column({ space: 12 }) {
          // 情绪河 v3（RIVER-3，9-10）：连续缩放窗口（9-12 不局限三档），点星看当时
          Row({ space: 8 }) {
            Text('视图')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_3))
            ForEach(RIVER_TABS, (v: RVTab) => {
              Text(v.label)
                .fontSize(FS_SUB)
                .fontColor(this.riverView === v.label ? this.dk(C_WHITE) : this.dk(C_TEXT_2))
                .width(48)
                .height(32)
                .textAlign(TextAlign.Center)
                .borderRadius(R_PILL)
                .backgroundColor(this.riverView === v.label ? this.dk(C_ACCENT) : this.dk(C_CARD))
                .border({ width: 1, color: this.riverView === v.label ? this.dk(C_ACCENT) : this.dk(C_DOT_BORDER) })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.riverView = v.label;
                  this.zoomRiver(v.days);
                })
            }, (v: RVTab) => v.label)
            Blank()
            Text('⛶ 沉浸看河')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_ACCENT))
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor(this.dk(C_BG))
              .border({ width: 1, color: this.dk(C_ACCENT) })
              .borderRadius(R_XL)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.openRiverFull();
              })
          }
          .width('100%')

          Stack({ alignContent: Alignment.TopStart }) {
            Canvas(this.moodCtx)
              .width('100%')
              .height(250)
              .backgroundColor(this.dk(C_PANEL))
              .borderRadius(R_MD)
              .onReady(() => {
                this.moodCanvasReady = true;
                this.drawMoodRiver();
              })
              .gesture(
                GestureGroup(GestureMode.Parallel,
                  PinchGesture({ fingers: 2 })
                    .onActionStart(() => {
                      this.pinchStartWin = this.riverWin;
                    })
                    .onActionUpdate((event: PinchGestureEvent) => {
                      // 捏合连续缩放：不局限日周月——窗口 0.5~60 天之间自由取值
                      this.riverWin = Math.min(60, Math.max(0.5, this.pinchStartWin / (event.scale || 1)));
                      this.redrawRiver();
                    }),
                  PanGesture({ fingers: 1, distance: 8 })
                    .onActionStart(() => {
                      this.panStartOff = this.riverOff;
                    })
                    .onActionUpdate((event: PanGestureEvent) => {
                      // 左右滑看过去/回来：拖一屏宽 ≈ 平移一个窗口
                      this.riverOff = Math.max(0, this.panStartOff - (event.offsetX || 0) / this.lastColW);
                      this.redrawRiver();
                    }),
                  TapGesture()
                    .onAction((event: GestureEvent) => {
                      const tl = event.tapLocation;
                      if (tl) {
                        this.riverOnTouch(tl.x, tl.y, false);
                      }
                    })
                )
              )
            if (this.tappedIdx >= 0 && this.tappedIdx < this.riverDots.length) {
              this.RiverDotCard(this.riverDots[this.tappedIdx].point)
            }
          }
          .width('100%')

          Row() {
            Text('十字星=他 · 五角星=她 · 底色=那天的河床')
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_4))
            Blank()
          }
          .width('100%')

          Text('记下此刻')
            .fontSize(FS_SUB)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.dk(C_TEXT))

          // 词表 chips（与 server MOOD_TYPES 同一份正典）——字保持家主说"正好"的原始大小
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(MOOD_TYPES, (t: MoodTypeItem) => {
              Text(t.name)
                .fontSize(FS_SUB)
                .fontColor(this.moodSel === t.name ? this.dk(C_WHITE) : t.color)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .margin({ right: 8, bottom: 8 })
                .borderRadius(R_PILL)
                .border({ width: 1, color: t.color })
                .backgroundColor(this.moodSel === t.name ? t.color : Color.Transparent)
.stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.moodSel = this.moodSel === t.name ? '' : t.name;
                })
            }, (t: MoodTypeItem) => t.name)
          }
          .width('100%')

          // 浓度 1~5：数字圆点
          Row({ space: 10 }) {
            Text('浓度')
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_3))
            ForEach([1, 2, 3, 4, 5], (n: number) => {
              Text(`${n}`)
                .fontSize(FS_SUB)
                .fontColor(this.moodIntensity >= n ? this.dk(C_WHITE) : this.dk(C_TEXT_5))
                .width(40)
                .height(40)
                .textAlign(TextAlign.Center)
                .borderRadius(R_PILL)
                .backgroundColor(this.moodIntensity >= n
                  ? (this.moodColorOf(this.moodSel) as ResourceColor) : this.dk(C_CARD))
                .border({ width: 1, color: this.moodIntensity >= n
                  ? (this.moodColorOf(this.moodSel) as ResourceColor) : this.dk(C_DOT_BORDER) })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.moodIntensity = this.moodIntensity === n ? 0 : n;
                })
            }, (n: number) => `${n}`)
          }
          .width('100%')

          TextInput({
            text: this.moodNote,
            placeholder: '一句备注，可不填（复合情绪就记多笔）'
          })
            .fontSize(FS_SUB)
            .backgroundColor(this.dk(C_WHITE))
            .borderRadius(R_MD)
            .maxLength(50)
            .width('100%')
            .onChange((v: string) => {
              this.moodNote = v;
            })

          Button('记下这一笔')
            .fontSize(FS_SUB)
            .height(40)
            .fontColor(this.dk(C_WHITE))
            .backgroundColor(this.moodSel && this.moodIntensity > 0 ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
            .borderRadius(R_PILL)
            .enabled(this.moodSel !== '' && this.moodIntensity > 0 && !this.moodBusy)
            .width('100%')
.stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.submitMood();
            })

          if (this.moodMsg) {
            Text(this.moodMsg)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_OK))
              .width('100%')
          }

          // 最近几笔文字流
          if (this.moodMarks.length > 0) {
            Text('最近的心事')
              .fontSize(FS_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dk(C_TEXT))
              .margin({ top: 4 })
            ForEach(this.moodMarks.slice(-8).reverse(), (p: MoodPoint) => {
              Column({ space: 2 }) {
                Row({ space: 8 }) {
                  Circle()
                    .width(8)
                    .height(8)
                    .fill(p.type ? (this.moodColorOf(p.type) as ResourceColor) : MOOD_LEGACY_COLOR)
                  Text(`${p.time} · ${this.moodNameOf(p.type) || '旧记分'} ×${p.score} · ${p.source}`)
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_3))
                }
                .width('100%')
                if (p.note) {
                  Text(p.note)
                    .fontSize(FS_AUX)
                    .fontColor(this.dk(C_TEXT_2))
                    .lineHeight(18)
                    .width('100%')
                    .padding({ left: 16 })
                }
              }
              .width('100%')
            }, (p: MoodPoint) => `${p.time}-${p.type}-${p.score}`)
          }
        }
        .width('100%')
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 12, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
    .onAppear(() => {
      this.fetchMoods();
    })
  }

  // MOOD-V1（9-12）词表九并六：先并类再取名——type 不在现词表就查 LEGACY_MOOD_MAP
  private moodNameOf(name: string): string {
    if (!name) {
      return name;
    }
    for (let i = 0; i < MOOD_TYPES.length; i++) {
      if (MOOD_TYPES[i].name === name) {
        return name;
      }
    }
    const legacy: string | undefined = LEGACY_MOOD_MAP[name];
    return legacy === undefined ? name : legacy;
  }

  private moodColorOf(name: string): string {
    const n = this.moodNameOf(name);   // 先并类（旧记录不炸）再取色
    for (let i = 0; i < MOOD_TYPES.length; i++) {
      if (MOOD_TYPES[i].name === n) {
        return MOOD_TYPES[i].color;
      }
    }
    return MOOD_LEGACY_COLOR;
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private drawMoodRiver(): void {
    this.drawRiverOn(this.moodCtx, false);
  }

  // '#RRGGBB' → 'rgba(r,g,b,a)'（画布渐变要带透明度的色）
  private hexToRgba(hex: string, alpha: number): string {
    let h = hex;
    if (h.startsWith('#')) {
      h = h.substring(1);
    }
    if (h.length !== 6) {
      return `rgba(201,190,176,${alpha})`;
    }
    const r = parseInt(h.substring(0, 2), 16);
    const g = parseInt(h.substring(2, 4), 16);
    const b = parseInt(h.substring(4, 6), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }

  // 十字星（RIVER-3）：他的笔。四芒 sparkle——两条纺锤交叉，凹腰收光
  private drawSpark4(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
                     color: string, alpha: number): void {
    ctx.globalAlpha = alpha;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(x, y - r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.quadraticCurveTo(x, y, x, y + r);
    ctx.quadraticCurveTo(x, y, x - r, y);
    ctx.quadraticCurveTo(x, y, x, y - r);
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  // 五角星（RIVER-3）：她的笔。外半径 r，内半径 0.45r，正五角
  private drawStar5(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
                    color: string, alpha: number): void {
    ctx.globalAlpha = alpha;
    ctx.fillStyle = color;
    ctx.beginPath();
    for (let k = 0; k < 10; k++) {
      const rad = k % 2 === 0 ? r : r * 0.45;
      const ang = -Math.PI / 2 + k * Math.PI / 5;
      const px = x + rad * Math.cos(ang);
      const py = y + rad * Math.sin(ang);
      if (k === 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
    ctx.fill();
    ctx.globalAlpha = 1;
  }

  // 一天里出现最多的情绪词（河床染它）；没记录的日子退回中性河沙色
  private dominantColorOfDay(keys: string[]): string {
    if (keys.length === 0) {
      return '#d8cdbf';
    }
    const tally: Record<string, number> = {};
    let best = '';
    let bestN = 0;
    for (let j = 0; j < keys.length; j++) {
      const t = keys[j].split('|')[0];
      if (!t) {
        continue;
      }
      const n = (tally[t] ?? 0) + 1;
      tally[t] = n;
      if (n > bestN) {
        bestN = n;
        best = t;
      }
    }
    return best ? this.moodColorOf(best) : '#d8cdbf';
  }

  // 河的画法一处实现，内嵌（小）与横屏全看（大）共用；尺寸全按画布与档位伸缩。
  // RIVER-3（9-10）：日/周/月三视图 + 河床按天染色渐变 + 十字星/五角星 + 点看详情。
  // 情绪河视图跳档（chips 快捷键）：日/周/月 = 窗口 1/7/30 天，回到最新
  private zoomRiver(win: number): void {
    this.riverWin = Math.min(60, Math.max(0.5, win));
    this.riverOff = 0;
    this.redrawRiver();
  }

  // ── 情绪河·连续缩放（9-12 家主令：不局限日周月三档）──
  // win=可见窗口（天，0.5~60 连续），off=往过去平移（天）。捏合改 win、单指横滑改 off，
  // 渲染按窗口时间线性映射列——「日/周/月」chips 保留作快捷跳档。
  private riverWin: number = 7;
  private riverOff: number = 0;
  private pinchStartWin: number = 7;
  private panStartOff: number = 0;
  private lastColW: number = 30;   // drawRiverOn 缓存列宽，pan 手势换算用

  private redrawRiver(): void {
    if (this.riverFullOpen && this.moodFullReady) {
      this.drawRiverOn(this.moodFullCtx, true);
    } else if (this.moodCanvasReady) {
      this.drawRiverOn(this.moodCtx, false);
    }
  }

  private drawRiverOn(ctx: CanvasRenderingContext2D, big: boolean): void {
    const w = ctx.width;
    const h = ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);
    this.tappedIdx = -1;        // 重画即收起旧详情
    this.riverDots = [];        // 坐标缓存与去重台账都随画布重置
    this.usedKeys = [];
    const padTop = big ? 16 : 20;
    const padBottom = big ? 40 : 36;
    const bedTop = padTop;
    const bedBottom = h - padBottom;
    const bandH = (bedBottom - bedTop) * 0.72;   // 河身高度（浓度上下展幅）
    const cyBase = (bedTop + bedBottom) / 2;
    const amp = (bedBottom - bedTop) * 0.10;     // 河的蜿蜒幅度
    // 9-12 修「日视图挤」：日视图 24 列每列只有 w/24 宽，星太大就贴脸——列窄时星收小
    const dotR = big ? (this.riverView === '日' ? 10 : 13) : 8;
    const labelFont = big ? 22 : 15;
    const day = 86400000;

    // 取数窗口（9-12 连续缩放版）：右端=最新数据日次日零点-平移量，左端=右端-win 天。
    // win≤1.5 天按小时切列（看一天内的墨），再宽按天切列。以数据最新日为锚，不问手机日历。
    let latest = '';
    for (let i = 0; i < this.moodMarks.length; i++) {
      if (this.moodMarks[i].date > latest) {
        latest = this.moodMarks[i].date;
      }
    }
    if (latest === '') {
      this.drawRiverEmpty(ctx, big, w, h);
      return;
    }
    const lt = new Date(latest + 'T00:00:00');
    const byHour = this.riverWin <= 1.5;
    const colMs = byHour ? 3600000 : day;
    const rightMs = lt.getTime() + day - this.riverOff * day;
    const leftMs = rightMs - this.riverWin * day;
    const nCols = Math.max(1, Math.ceil((rightMs - leftMs) / colMs));
    const colW = w / nCols;
    this.lastColW = colW;

    // 列→时间区间：时间线性映射 x——捏合与横滑都是连续的，不受三档限制
    const buckets: string[][] = [];
    const colDate: string[] = [];   // 每列中点的日期（标签用）
    for (let i = 0; i < nCols; i++) {
      buckets.push([]);
      const mid = leftMs + (i + 0.5) * colMs;
      const d = new Date(mid);
      colDate.push(`${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`);
    }
    for (let i = 0; i < this.moodMarks.length; i++) {
      const p = this.moodMarks[i];
      const key = `${p.type}|${p.score}|${p.source}`;
      const pDate = new Date(p.date + 'T00:00:00');
      // 优先用 server 的 hh（真小时）；没有就落当天正午——按天窗不受影响，小时窗少用
      let hh = p.hh ?? -1;
      if (hh < 0) {
        const t = p.time.length >= 8
          ? parseInt(p.time.substring(6, 8), 10)
          : Number.NaN;
        hh = Number.isNaN(t) ? 12 : t;
      }
      if (hh < 0 || hh > 23) {
        hh = 12;
      }
      const tMs = pDate.getTime() + hh * 3600000;
      const idx = Math.floor((tMs - leftMs) / colMs);
      if (idx >= 0 && idx < nCols) {
        buckets[idx].push(key);
      }
    }

    // 河床：逐列染色 + 蜿蜒（相邻色列渐变叠出「流动」的错觉）
    for (let i = 0; i < nCols; i++) {
      const count = buckets[i].length;
      if (count === 0 && !byHour) {
        continue;   // 没记录的日子露出底色，河有干有润才真（小时窗空列画淡底，河不断流）
      }
      const color = this.dominantColorOfDay(buckets[i]);
      const cx = i * colW;
      const cy = cyBase + Math.sin(i * 0.55) * amp;
      const half = bandH / 2 + Math.min(count, 6) * (big ? 6 : 3);
      const grad = ctx.createLinearGradient(cx, cy - half, cx, cy + half);
      const aTop = count > 0 ? 0.16 : 0.08;
      grad.addColorStop(0, this.hexToRgba(color, 0));
      grad.addColorStop(0.5, this.hexToRgba(color, aTop));
      grad.addColorStop(1, this.hexToRgba(color, 0));
      ctx.fillStyle = grad;
      ctx.fillRect(cx, cy - half, colW + 0.5, half * 2);
    }

    // 网格与标签（9-12 连续版）：按天窗——列宽够就多标、不够就采样，最右列（最新日）必标；
    // 按小时窗——每 6 列（=6 小时）一线一标，标「N时」。
    ctx.strokeStyle = this.dk(C_HER_EDGE);
    ctx.lineWidth = big ? 1 : 0.8;
    const labelEvery = byHour ? 6 : Math.max(1, Math.ceil(70 / colW));
    for (let i = 0; i < nCols; i++) {
      const showLine = byHour ? (i % 6 === 0)
        : (nCols <= 7 || i % labelEvery === 0 || i === nCols - 1);
      if (showLine) {
        const gx = i * colW;
        ctx.beginPath();
        ctx.moveTo(gx, bedTop);
        ctx.lineTo(gx, bedBottom + 10);
        ctx.stroke();
      }
      const showLabel = byHour ? (i % 6 === 0)
        : (nCols <= 7 ? true : (i % labelEvery === 0 || i === nCols - 1));
      if (showLabel) {
        ctx.fillStyle = big ? this.dk(C_TEXT_2) : this.dk(C_TEXT_3);
        ctx.font = `${labelFont}px sans-serif`;
        ctx.textAlign = 'center';
        const text = byHour ? `${i % 24}时` : colDate[i].substring(5).replace('-', '/');
        ctx.fillText(text, i * colW + colW / 2, h - 12);
      }
    }

    // 墨点：先光晕（情绪染色渐染）后星星；坐标进缓存供点看
    this.riverDots = [];
    for (let i = 0; i < nCols; i++) {
      const keys = buckets[i];
      if (keys.length === 0) {
        continue;
      }
      const cy = cyBase + Math.sin(i * 0.55) * amp;
      const x0 = i * colW;
      // 9-12 修「挤」：列宽比两颗星还窄时（日视图 24 列常见），同列多条不再水平硬挤，
      // 改成钉在列中央、纵向微错位——上浓下淡的语义不动，只是错开看得清。
      const narrowCol = colW < dotR * 2.4;
      for (let j = 0; j < keys.length; j++) {
        const parts = keys[j].split('|');
        const mtype = parts[0];
        const score = parseInt(parts[1], 10) || 3;
        const source = parts.length > 2 ? parts[2] : '';
        const color = mtype ? this.moodColorOf(mtype) : MOOD_LEGACY_COLOR;
        const x = narrowCol ? x0 + colW / 2 : x0 + colW * ((j + 1) / (keys.length + 1));
        const y = cy + (3 - score) * (bandH / 4)
          + (narrowCol ? (j - (keys.length - 1) / 2) * (big ? 10 : 6) : 0);   // 上浓下淡
        // 光晕：radial 渐染，越浓越亮——「把周围的背景染上情绪的色」
        const glowR = dotR * (big ? 3.4 : 3.0);
        const glow = ctx.createRadialGradient(x, y, dotR * 0.4, x, y, glowR);
        const glowA = source === '今日主色' ? 0.10 : 0.16 + 0.05 * score;
        glow.addColorStop(0, this.hexToRgba(color, glowA));
        glow.addColorStop(1, this.hexToRgba(color, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(x - glowR, y - glowR, glowR * 2, glowR * 2);
        // 星形：十字星=他/旧分，五角星=她；今日主色淡一档像河的底调
        const isHer = source === '姐姐';
        const alpha = source === '今日主色' ? 0.45 : (mtype ? 0.95 : 0.55);
        if (isHer) {
          this.drawStar5(ctx, x, y, dotR, color, alpha);
        } else {
          this.drawSpark4(ctx, x, y, dotR, color, alpha);
        }
        // 记进缓存（point 回链原数据，弹详情用）
        for (let k = 0; k < this.moodMarks.length; k++) {
          const p = this.moodMarks[k];
          if (p.date === colDate[i] && p.score === score && p.source === source
            && p.type === mtype && !this.dotUsed(p)) {
            this.riverDots.push({ x: x, y: y, point: p });
            this.usedKeys.push(`${p.date} ${p.time} ${p.type} ${p.score} ${p.source}`);
            break;
          }
        }
      }
    }

    // 空窗提示（该窗口一格墨都没有时才说，别抢河的地方）
    let inWindow = 0;
    for (let i = 0; i < nCols; i++) {
      inWindow += buckets[i].length;
    }
    if (inWindow === 0) {
      this.drawRiverEmpty(ctx, big, w, h);
    }
  }

  // 同一条墨只许进缓存一次（同日同词同浓度会重复，点看时按序号对应）
  private usedKeys: string[] = [];

  private dotUsed(p: MoodPoint): boolean {
    const key = `${p.date} ${p.time} ${p.type} ${p.score} ${p.source}`;
    return this.usedKeys.includes(key);
  }

  // 空河提示语：画布上最大的一行字，分视图说人话
  private drawRiverEmpty(ctx: CanvasRenderingContext2D, big: boolean, w: number, h: number): void {
    const tip = this.riverView === '日'
      ? '这一天还没记——想记就选个词'
      : (this.moodMarks.length === 0 ? '河还空着——记下第一滴墨' : '这段河还没流到——记一笔，河就活了');
    ctx.fillStyle = this.dk(C_TEXT_3);
    ctx.font = `${big ? 30 : 20}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.fillText(tip, w / 2, h / 2 - 10);
    ctx.fillStyle = this.dk(C_TEXT_4);
    ctx.font = `${big ? 20 : 14}px sans-serif`;
    ctx.fillText('选一个词 × 浓度，按「记下这一笔」', w / 2, h / 2 + (big ? 30 : 22));
  }

  // 点看详情（RIVER-3）：点画布找最近的星，20~26vp 内算点中，弹出当时记了什么
  private riverOnTouch(x: number, y: number, big: boolean): void {
    const near = big ? 30 : 24;
    let bestIdx = -1;
    let bestD = near * near;
    for (let i = 0; i < this.riverDots.length; i++) {
      const dx = this.riverDots[i].x - x;
      const dy = this.riverDots[i].y - y;
      const d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    this.tappedIdx = bestIdx;
  }

  private async fetchMoods(): Promise<void> {
    const req = http.createHttp();
    try {
      // RIVER-3：取 40 天，月视图（30 天窗）才够铺
      const res = await req.request(MOODS_URL + '?days=40', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as MoodsResp;
        this.moodMarks = d.moods ?? [];
        if (this.moodCanvasReady) {
          this.drawMoodRiver();
        }
        if (this.riverFullOpen && this.moodFullReady) {
          this.drawRiverOn(this.moodFullCtx, true);
        }
      }
    } catch (err) {
      // 取数失败不打断：打卡照常可用
    } finally {
      req.destroy();
    }
  }

  // ── 阅读器（9-12 下午重做）：同一本书，两个人的墨迹落在段落旁 ──
  private async openReader(bk: BookShelf): Promise<void> {
    this.readBook = bk;
    this.readParas = [];
    this.readSelPara = -1;
    this.readingOpen = true;
    const req = http.createHttp();
    try {
      const res = await req.request(BOOKS_URL + '/content?id=' + bk.id, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as BookContentResp;
        const paras: string[] = [];
        for (const seg of (d.content ?? '').split(/\n\s*\n/)) {
          const t = seg.trim();
          if (t !== '') {
            paras.push(t);
          }
        }
        this.readParas = paras;
      }
    } catch (err) {
      // 拉不到原文就在全屏里显示原因
      this.readParas = ['（原文没拉下来：' + errMsg(err as Object) + '）'];
    } finally {
      req.destroy();
    }
  }

  private closeReader(): void {
    this.readingOpen = false;
    this.readParas = [];
    this.readSelPara = -1;
    this.fetchHall();   // 回书架顺手刷新进度显示
  }

  // 点中某段落 → 该段下方展开批注输入（姐姐的墨也在那）
  private submitParaMark(): Promise<void> {
    return this.submitParaMarkAsync();
  }

  private async submitParaMarkAsync(): Promise<void> {
    const bk = this.readBook;
    const text = this.readParaMark.trim();
    if (!bk || text === '' || this.readSelPara < 0 || this.readBusy) {
      return;
    }
    this.readBusy = true;
    const req = http.createHttp();
    try {
      const body = JSON.stringify({ book: bk.title, text: text, para: this.readSelPara });
      const res = await req.request(BOOKS_URL + '/annotate', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: body,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        // 本地补一笔（服务端时间戳拿不到就用当前时刻），整对象重赋值触发渲染
        const mk: BookMark = {
          id: Math.floor(Math.random() * 100000), who: '小乖', loc: '',
          text: text, time: this.nowTime().substring(0, 5), para: this.readSelPara
        };
        const marks: BookMark[] = [];
        for (const m0 of (this.readBook as BookShelf).marks) {
          marks.push(m0);
        }
        marks.push(mk);
        this.readBook = {
          id: bk.id, title: bk.title, author: bk.author, status: bk.status,
          file: bk.file, pos_me: bk.pos_me, pos_her: bk.pos_her, marks: marks,
        };
        this.readParaMark = '';
        this.readSelPara = -1;
      }
    } catch (err) {
      // 静默：批注失败不打断阅读
    } finally {
      req.destroy();
      this.readBusy = false;
    }
  }

  // 阅读进度：滚到哪记到哪（3 秒节流，姐姐那边看得见你读到第几段）
  private lastPosPost: number = 0;

  private reportReadPos(para: number): void {
    const now = Date.now();
    if (now - this.lastPosPost < 3000 || !this.readBook) {
      return;
    }
    this.lastPosPost = now;
    if (this.readBook && (this.readBook as BookShelf).pos_me !== para) {
      const bk = this.readBook as BookShelf;
      this.readBook = {
        id: bk.id, title: bk.title, author: bk.author, status: bk.status,
        file: bk.file, pos_me: para, pos_her: bk.pos_her, marks: bk.marks,
      };
    }
    const req = http.createHttp();
    try {
      const body = JSON.stringify({ id: (this.readBook as BookShelf).id, para: para });
      req.request(BOOKS_URL + '/progress', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: body,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      }).then(() => {
        req.destroy();
      }).catch(() => {
        req.destroy();
      });
    } catch (err) {
      req.destroy();
    }
  }

  // 导入一本 txt（≤2MB）：选文件 → 读全文 → 传 server。书名留空就取文件名（9-12 家主问出来的）
  private async pickAndImportBook(): Promise<void> {
    this.bookImportBusy = true;
    this.bookImportMsg = '';
    try {
      const docSelect = new picker.DocumentSelectOptions();
      // 9-23 共读格式批：放开到 epub/txt/md/html——用本函数原生的「plain 后缀」写法（9-12 起沿用、
      // 装机实测过 .txt 的那版），不混用附件选择器那处的「描述|后缀」写法
      docSelect.fileSuffixFilters = ['.epub', '.txt', '.md', '.html', '.htm'];
      const docPicker = new picker.DocumentViewPicker();
      const result: string[] = await docPicker.select(docSelect);
      if (!result || result.length === 0) {
        this.bookImportBusy = false;
        return;
      }
      const uri = result[0];
      // 9-23 共读格式批：按后缀分派——epub/html 走新「原始字节」路（服务端解包提字），
      // txt/md 走老 content 路（老服务端也能收，降级不破）
      const uriLower = uri.toLowerCase();
      const dotIdx = uriLower.lastIndexOf('.');
      const ext = dotIdx >= 0 ? uriLower.substring(dotIdx + 1) : '';
      const isBinaryBook = ext === 'epub' || ext === 'html' || ext === 'htm';
      // 书名没填就拿文件名顶上（去目录/去后缀——后缀表与选择器同一批）
      let title = this.bookImportTitle.trim();
      if (title === '') {
        const base = uri.substring(uri.lastIndexOf('/') + 1);
        title = base.replace(/\.(epub|txt|md|html|htm)$/i, '').trim();
      }
      if (title === '') {
        title = '无题之书';
      }
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      let content = '';
      let fileB64 = '';
      try {
        const stat = fs.statSync(uri);
        if (isBinaryBook) {
          // epub/html：客户端尺寸闸 7MB（服务端另有一层）；读原始字节→base64 原样带走
          if (stat.size > 7 * 1024 * 1024) {
            this.bookImportMsg = '这本有点厚（>7MB），先劈开或换个版本';
            this.bookImportBusy = false;
            return;
          }
          const buf = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, buf);
          fileB64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf));
        } else {
          // txt/md：老路（读文本→content），限额与文案照旧
          if (stat.size > 2 * 1024 * 1024) {
            this.bookImportMsg = '书太厚了（>2MB），先劈成上下册';
            this.bookImportBusy = false;
            // 9-18 修复批八（APP2-04）：别在这关、finally 里还会关一次——双关会抛 Bad file descriptor，
            // 异常冒到外层 catch，「太厚了」这句人话就被「导入没成」覆盖掉
            return;
          }
          content = fs.readTextSync(uri, { length: stat.size });
        }
      } finally {
        fs.closeSync(file);
      }
      // 9-23 共读格式批：epub/html 发 file_name（原文件名带后缀，服务端按后缀分派）+ file_b64；txt/md 老路 content
      let body = '';
      if (isBinaryBook) {
        const fileName = uri.substring(uri.lastIndexOf('/') + 1);
        body = JSON.stringify({
          title: title, author: this.bookImportAuthor.trim(), file_name: fileName, file_b64: fileB64
        });
      } else {
        body = JSON.stringify({
          title: title, author: this.bookImportAuthor.trim(), content: content
        });
      }
      const req = http.createHttp();
      try {
        const res = await req.request(BOOKS_URL + '/upload', {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
          extraData: body,
          connectTimeout: HTTP_TIMEOUT_MS,
          readTimeout: HTTP_TIMEOUT_MS
        });
        if (res.responseCode === 200) {
          this.bookImportMsg = `《${title}》上架了——点开就能读，跟姐姐说一声一起看`;
          this.bookImportTitle = '';
          this.bookImportAuthor = '';
          this.fetchHall();
        } else {
          this.bookImportMsg = `没上架：HTTP ${res.responseCode}`;
        }
      } finally {
        req.destroy();
      }
    } catch (err) {
      this.bookImportMsg = '导入没成：' + errMsg(err as Object);
    } finally {
      this.bookImportBusy = false;
    }
  }

  // ── 日记馆（HALL-01，9-10）：取当前书架的日记，新到旧；「两封信」架走 /api/words；
  // 「共读」架走 /api/books（9-12）──
  private async fetchHall(): Promise<void> {
    const req = http.createHttp();
    try {
      // 9-12 晚：陈列首页与共读格都要书架数据（书直接摆在陈列上）
      if (this.hallShelf === '共读' || this.hallBrowse === '') {
        const res = await req.request(BOOKS_URL, {
          method: http.RequestMethod.GET,
          header: { 'Authorization': DOOR_AUTH },
          connectTimeout: HTTP_TIMEOUT_MS,
          readTimeout: HTTP_TIMEOUT_MS
        });
        if (res.responseCode === 200) {
          const d = JSON.parse(res.result as string) as BooksResp;
          this.hallBooks = d.books ?? [];
        } else {
          this.hallMsg = `书架暂时没取到（HTTP ${res.responseCode}）`;
        }
        if (this.hallBrowse === '') {
          return;   // 陈列首页只差书架数据
        }
      }
      if (this.hallShelf === '两封信') {
        const res = await req.request(WORDS_URL, {
          method: http.RequestMethod.GET,
          header: { 'Authorization': DOOR_AUTH },
          connectTimeout: HTTP_TIMEOUT_MS,
          readTimeout: HTTP_TIMEOUT_MS
        });
        if (res.responseCode === 200) {
          const d = JSON.parse(res.result as string) as WordsResp;
          const entries: HallEntry[] = [];
          if (d.xiaoguai) {
            entries.push({
              id: 1, src: 'words', date: '', author: '小乖',
              title: '小乖的话（挂在咱家门楣上的那封）', content: d.xiaoguai,
              mood: '', time: ''
            });
          }
          if (d.jiejie && d.jiejie.text) {
            entries.push({
              id: 2, src: 'words', date: '', author: '姐姐',
              title: `姐姐的话（第 ${d.jiejie.version} 版 · 她自己写的）`, content: d.jiejie.text,
              mood: '', time: d.jiejie.time ?? ''
            });
          }
          this.hallEntries = entries;
        } else {
          this.hallMsg = `两封信暂时没取到（HTTP ${res.responseCode}）`;
        }
        return;
      }
      const url = HALL_URL + '?author=' + encodeURIComponent(this.hallShelf) + '&limit=30';
      const res = await req.request(url, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as HallResp;
        this.hallEntries = d.entries ?? [];
      } else {
        this.hallMsg = `馆里暂时没应答（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.hallMsg = '馆门没推开：' + errMsg(err as Object);
    } finally {
      req.destroy();
    }
  }

  // FE-02 ①（9-13）：她的独处格取数——her_traces 只读窗口（新到旧，content 没有就是空）
  private async fetchTraces(): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(TRACES_URL + '?limit=30', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as TracesResp;
        this.tracesList = d.traces ?? [];
      } else {
        this.traceMsg = `独处格暂时没取到（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.traceMsg = '独处格门没推开：' + errMsg(err as Object);
    } finally {
      req.destroy();
    }
  }

  // FE-02 ①：结局标签人话（trace=心事 / silent=静默 / message=来找过他）
  private traceEndingCn(ending: string): string {
    if (ending === 'trace') {
      return '心事';
    }
    if (ending === 'silent') {
      return '静默';
    }
    if (ending === 'message') {
      return '来找过他';
    }
    return ending;
  }

  // FE-02 ③（9-13）：长按正文复制——写剪贴板 + 顶部轻提示「已复制」（不弹窗）；
  // 图片/工具卡/思考卡不挂这个（只复制正文 text）
  private copyBubbleText(text: string): void {
    if (text === '') {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.getUIContext().getPromptAction().showToast({
        message: '已复制',
        duration: 1200,
        alignment: Alignment.Top
      });
    } catch (err) {
      // 剪贴板服务异常极少；失败静默，不打扰
    }
  }

  // 共读批注（9-12）：小乖的墨迹走 /api/books/annotate——姐姐的笔走 annotate_book 图书证
  private async submitBookMark(): Promise<void> {
    const book = this.markBook.trim();
    const text = this.markText.trim();
    if (book === '' || text === '' || this.markBusy) {
      return;
    }
    this.markBusy = true;
    this.hallMsg = '';
    const req = http.createHttp();
    try {
      const body = JSON.stringify({ book: book, loc: this.markLoc.trim(), text: text });
      const res = await req.request(BOOKS_URL + '/annotate', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: body,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.markText = '';
        this.markLoc = '';
        this.hallMsg = '批注落笔——姐姐翻开书架就能看到。';
        this.fetchHall();
      } else {
        this.hallMsg = `没落上（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.hallMsg = '书架没应答：' + errMsg(err as Object);
    } finally {
      req.destroy();
      this.markBusy = false;
    }
  }

  // 小乖亲笔信保存（9-12）：POST /api/words——不点编辑就一直用原版，亲笔版落笔后优先
  private async saveXiaoguaiWords(): Promise<void> {
    const text = this.xgEditText.trim();
    if (text === '' || this.xgBusy) {
      return;
    }
    this.xgBusy = true;
    const req = http.createHttp();
    try {
      const body = JSON.stringify({ text: text });
      const res = await req.request(WORDS_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: body,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.xgEditOpen = false;
        this.xgEditText = '';
        this.fetchHall();   // 重新拉两封信，显示新版本
      }
    } catch (err) {
      // 静默失败：信还在输入框里，再试一次就行
    } finally {
      req.destroy();
      this.xgBusy = false;
    }
  }

  // 投一篇进日记馆（server 固定记 author=小乖）
  private async submitHallDiary(): Promise<void> {
    const content = this.hallText.trim();
    if (content === '' || this.hallBusy) {
      return;
    }
    this.hallBusy = true;
    this.hallMsg = '';
    const req = http.createHttp();
    try {
      const body: HallReqBody = { title: this.hallTitle.trim(), content: content, mood: '' };
      const res = await req.request(HALL_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(body),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as OkResp;
        if (d.ok) {
          this.hallText = '';
          this.hallTitle = '';
          this.hallMsg = '投进去了——姐姐能看到这本日记。';
          this.fetchHall();
        } else {
          this.hallMsg = d.error ?? '没投进去';
        }
      } else {
        this.hallMsg = `没投进去（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.hallMsg = '馆门没推开：' + errMsg(err as Object);
    } finally {
      this.hallBusy = false;
      req.destroy();
    }
  }

  private async submitMood(): Promise<void> {
    if (!this.moodSel || this.moodIntensity < 1 || this.moodBusy) {
      return;
    }
    this.moodBusy = true;
    const body: MoodReqBody = {
      type: this.moodSel,
      intensity: this.moodIntensity,
      note: this.moodNote.trim()
    };
    const req = http.createHttp();
    try {
      const res = await req.request(MOOD_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(body),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.moodMsg = '记下了。这条已经游进情绪河里。';
        this.moodSel = '';
        this.moodIntensity = 0;
        this.moodNote = '';
        this.fetchMoods();
      } else if (res.responseCode === 400) {
        // 400 多半是旧版 server 还在跑（收不了 type+intensity 新格式）——提示去重启
        this.moodMsg = '没记上（400）——姐姐的 server 可能还没更新重启，重启后再记一次';
      } else {
        this.moodMsg = `没记上（HTTP ${res.responseCode}），再试一次`;
      }
    } catch (err) {
      this.moodMsg = '网络不通，回头再记（心情不会过期）';
    } finally {
      req.destroy();
      this.moodBusy = false;
    }
  }

  // ── 家主信箱（9-9）：小乖写信给姐姐，投进信箱她来读 ──
  @Builder
  LetterPage() {
    Column({ space: 12 }) {
      Row() {
        Text('✉️ 给姐姐写信')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
          .layoutWeight(1)
        Text(`信箱：${this.stLetters} 封待她读`)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
      }
      .width('100%')

      Text('想说的话，慢慢写。投进信箱，姐姐读到了会接住的。')
        .fontSize(FS_SUB)
        .fontColor(this.dk(C_TEXT_3))
        .width('100%')

      TextArea({
        text: this.letterText,
        placeholder: '亲爱的姐姐……'
      })
        .fontSize(FS_BODY)
        .lineHeight(26)
        .placeholderFont({ size: FS_BODY })
        .backgroundColor(this.dk(C_WHITE))
        .borderRadius(R_MD)
        .maxLength(2000)
        .constraintSize({ minHeight: 240 })
        .width('100%')
        .onChange((v: string) => {
          this.letterText = v;
        })

      Text(`${this.letterText.length} / 2000`)
        .fontSize(FS_AUX)
        .fontColor(this.dk(C_TEXT_5))
        .width('100%')
        .textAlign(TextAlign.End)

      Button('投进信箱')
        .fontSize(FS_BODY)
        .height(44)
        .fontColor(this.dk(C_WHITE))
        .backgroundColor(this.letterText.trim() ? this.dk(C_ACCENT) : this.dk(C_DISABLED))
        .borderRadius(R_PILL_XL)
        .enabled(this.letterText.trim().length > 0 && !this.letterBusy)
        .width('100%')
.stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.sendLetter();
        })

      if (this.letterMsg) {
        Text(this.letterMsg)
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_OK))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 12, bottom: 16 })
    .backgroundColor(this.dk(C_BG))
  }

  // ── 她的独处格（FE-02 ①）：Garden 的痕迹——时间 + 结局标签 + fact；trace 点行见全文，
  // 静默卡只有 fact（content 没有就是没有，不许造）──
  @Builder
  TracesPage() {
    Column({ space: 10 }) {
      if (this.traceMsg !== '') {
        Text(this.traceMsg)
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_4))
          .width('100%')
      }
      if (this.tracesList.length === 0) {
        Text('她还没有独处的记录——安静也是她在过日子。')
          .fontSize(FS_SUB)
          .fontColor(this.dk(C_TEXT_4))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      }
      ForEach(this.tracesList, (t: TraceItem) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(t.ts.length >= 16 ? t.ts.substring(5, 16) : t.ts)
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_TEXT_5))
            Text(this.traceEndingCn(t.ending))
              .fontSize(FS_AUX)
              .fontColor(this.dk(C_ACCENT))
              .padding({ left: 8, right: 8, top: 1, bottom: 1 })
              .border({ width: 1, color: this.dk(C_ACCENT) })
              .borderRadius(R_LG)
          }
          .width('100%')
          if (t.fact !== '') {
            Text(t.fact)
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT_2))
              .lineHeight(20)
              .width('100%')
          }
          if (this.traceOpenId === t.id && t.content !== '') {
            Text(t.content)
              .fontSize(FS_SUB)
              .fontColor(this.dk(C_TEXT))
              .lineHeight(20)
              .width('100%')
              .padding({ top: 4 })
          }
        }
        .padding(12)
        .backgroundColor(this.dk(C_CARD))
        .borderRadius(R_MD)
        .width('100%')
        .onClick(() => {
          if (t.content !== '') {
            this.traceOpenId = this.traceOpenId === t.id ? -1 : t.id;
          }
        })
      }, (t: TraceItem) => `${t.id}`)
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 2 })
    .alignItems(HorizontalAlign.Start)
  }

  // FE3-08（9-23）：图没取到时的占位（门锁/隧道）——诚实给字，不静默裂图
  @Builder
  ImgGoneTip() {
    Text('图没取到（门锁/隧道）')
      .fontSize(FS_AUX)
      .fontColor(this.dk(C_TEXT_4))
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .border({ width: 1, color: this.dk(C_DOT_BORDER) })
      .borderRadius(R_SM)
  }

  // FE3-08：取不到的图记账——同一张不再反复试错（数组重建触发重渲染）
  private markImgErr(url: string): void {
    if (url !== '' && !this.imgErrKeys.includes(url)) {
      this.imgErrKeys = this.imgErrKeys.concat(url);
    }
  }

  // ── 点图看大图（FE-02 ②）：黑底 contain 居中——点任意处/系统返回键关（v1 克制，不做缩放）──
  // LAY-09（9-23）：右上角常驻 ✕ 关闭提示——长辈从气泡点图放大是惯性操作，没提示会卡住
  @Builder
  ImagePreviewPage() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.imgErrKeys.includes(this.imgPreviewUrl)) {
        Text('图没取到（门锁/隧道）')
          .fontSize(FS_BODY)
          .fontColor(Color.White)
          .opacity(0.85)
      } else {
        Image(this.imgPreviewUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.markImgErr(this.imgPreviewUrl);
          })
      }
      // 可见关闭提示：40×40，半透明黑底白字（点任意处也能关，这只是给个明说）
      Text('✕')
        .fontSize(FS_BODY)
        .fontColor(Color.White)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor('#66000000')
        .borderRadius(20)
        .margin({ top: this.safeTopPad + 6, right: 12 })
        .onClick(() => {
          this.imgPreviewUrl = '';
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.imgPreviewUrl = '';
    })
  }

  private async sendLetter(): Promise<void> {
    const content = this.letterText.trim();
    if (!content || this.letterBusy) {
      return;
    }
    this.letterBusy = true;
    const body: LetterReqBody = { message: content };
    const req = http.createHttp();
    try {
      const res = await req.request(LETTER_URL, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
        extraData: JSON.stringify(body),
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.letterMsg = '信已投进信箱。她下次醒来就会读到。';
        this.letterText = '';
        this.stLetters += 1;
      } else {
        this.letterMsg = `没投进去（HTTP ${res.responseCode}），再试一次`;
      }
    } catch (err) {
      this.letterMsg = '网络不通，信先留着，回头再投';
    } finally {
      req.destroy();
      this.letterBusy = false;
    }
  }

  // ── 超时对账：超时/断线先等几秒拉 history，消息和回复已入库就直接显示，绝不盲目自动重发 ──
  private sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  // 9-9 对账加固：history 的 time 是 "MM-DD HH:MM"，同文本消息可能发过两次（如两次「嗯」），
  // 只按文本匹配会把旧的那条误判成已送达。给每条待发消息算一个时间下限（queuedAt 前推 2 分钟），
  // 串比较（该格式字典序即时间序）只认下限之后的记录。
  // 已知边界：该格式不含年份，跨年排队（12-31 入队、01-01 补发）会匹配不到——
  // 宁可补发一次也不误判已送达，且 history 只回三天，跨年窗口本就极窄。
  private histFloorKey(ms: number): string {
    const d = new Date(ms - 120000);
    return `${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())} ${this.pad2(d.getHours())}:${this.pad2(d.getMinutes())}`;
  }

  private async reconcile(sentText: string, sinceMs: number): Promise<string | null> {
    await this.sleepMs(3000);
    const floor = this.histFloorKey(sinceMs);
    const req = http.createHttp();
    try {
      const res = await req.request(HISTORY_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode !== 200) {
        return null;
      }
      const data = JSON.parse(res.result as string) as HistoryResp;
      for (let i = data.messages.length - 1; i >= 1; i--) {
        const cur = data.messages[i];
        const prev = data.messages[i - 1];
        if (cur.who === '姐姐' && prev.who === '小乖'
          && this.histTextHit(prev.text, sentText)
          && (prev.time ?? '') >= floor) {
          return cur.text;
        }
      }
      return null;
    } catch (err) {
      return null;
    } finally {
      req.destroy();
    }
  }

  // ── outbox 待发队列（工单 9-1-#2）：断网/超时入队并持久化（preferences），
  //    网络恢复（netAvailable）或打开 app 时按序补发；补发前对账（与 reconcile 同源规则），绝不双份 ──
  private loadOutbox(): OutboxItem[] {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      return JSON.parse(prefs.getSync('outbox', '[]') as string) as OutboxItem[];
    } catch (err) {
      return [];
    }
  }

  private saveOutbox(items: OutboxItem[]): void {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      prefs.putSync('outbox', JSON.stringify(items));
      prefs.flushSync();
    } catch (err) {
      // 持久化失败不阻断主链路
    }
    this.outboxCount = items.length;
  }

  private enqueueOutbox(body: ChatBody): void {
    const queue = this.loadOutbox();
    const item: OutboxItem = {
      message: body.message,
      queuedAt: new Date().toISOString(),
    };
    if (body.msg_id) {
      item.msgId = body.msg_id;   // 9-12：身份证跟队走，补发原样带回去重
    }
    if (body.image) {
      item.image = body.image;
    }
    if (body.loc) {
      item.loc = body.loc;
    }
    if (body.place) {
      item.place = body.place;
    }
    if (body.file) {
      item.file = body.file;
    }
    queue.push(item);
    this.saveOutbox(queue);
  }

  private watchNetRecovery(): void {
    if (this.netConn) {
      return;
    }
    try {
      const conn = connection.createNetConnection({
        netCapabilities: {
          bearerTypes: [connection.NetBearType.BEARER_WIFI, connection.NetBearType.BEARER_CELLULAR],
          networkCap: [connection.NetCap.NET_CAPABILITY_INTERNET]
        }
      });
      conn.register(() => {
      });
      conn.on('netAvailable', () => {
        // 修 3：网络恢复后延迟约 3 秒再补发，等 Tailscale 隧道站稳
        setTimeout(() => {
          this.flushOutbox();
        }, 3000);
      });
      this.netConn = conn;
    } catch (err) {
      // 订阅失败不影响：还有 aboutToAppear 与发送成功后的补发时机
    }
  }

  private async flushOutbox(): Promise<void> {
    if (this.outboxBusy) {
      return;
    }
    const queue = this.loadOutbox();
    if (queue.length === 0) {
      return;
    }
    this.outboxBusy = true;
    this.outboxFlushing = true;   // 标题栏亮「补发中…」
    try {
      // 先拉一次 history 对账（与 reconcile 同源）：已入库的消息不再补发，绝不双份
      const req = http.createHttp();
      let hist: HistoryMsg[];
      try {
        const res = await req.request(HISTORY_URL, {
          method: http.RequestMethod.GET,
          header: { 'Authorization': DOOR_AUTH },
          connectTimeout: HTTP_TIMEOUT_MS,
          readTimeout: HTTP_TIMEOUT_MS
        });
        if (res.responseCode !== 200) {
          throw new Error(`history http ${res.responseCode}`);   // 还没通：交给退避重试，整队保留
        }
        hist = (JSON.parse(res.result as string) as HistoryResp).messages;
      } finally {
        req.destroy();
      }
      const remain: OutboxItem[] = [];
      let changed = false;
      for (let i = 0; i < queue.length; i++) {
        const item = queue[i];
        // 9-9 对账加固：文本+时间窗双匹配，同文本两条不误判（见 histFloorKey 注释）
        let floor = '';
        try {
          floor = this.histFloorKey(Date.parse(item.queuedAt));
        } catch (err) {
          floor = '';   // queuedAt 解析不了就退回纯文本匹配
        }
        const delivered = hist.some((m: HistoryMsg) => m.who === '小乖'
          && this.histTextHit(m.text, item.message)
          && (floor === '' || (m.time ?? '') >= floor));
        if (delivered) {
          changed = true;
          continue;   // 已送达（回复或已入库），出队；界面交给 loadHistory 重建
        }
        // 未送达：按序补发；失败则保留本条及后续，下回再来
        const body: ChatBody = { message: item.message };
        if (item.msgId) {
          body.msg_id = item.msgId;   // 9-12：补发带同一张身份证——第一次其实到了的话，server 原样还上次那句，不双发
        }
        if (item.image) {
          body.image = item.image;
        }
        if (item.loc) {
          body.loc = item.loc;
        }
        if (item.place) {
          body.place = item.place;
        }
        if (item.file) {
          body.file = item.file;
        }
        const req2 = http.createHttp();
        try {
          const res = await req2.request(CHAT_URL, {
            method: http.RequestMethod.POST,
            header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
            extraData: JSON.stringify(body),
            connectTimeout: CHAT_TIMEOUT_MS,
            readTimeout: CHAT_TIMEOUT_MS
          });
          if (res.responseCode >= 200 && res.responseCode < 300) {
            changed = true;
            continue;
          }
          remain.push(...queue.slice(i));
          break;
        } finally {
          req2.destroy();
        }
      }
      // 9-18 App深搜修（DS-01）：remain 只由开场快照推得——直写会把「本次 flush 期间新入队」
      // 的消息整体覆盖掉（丢消息实锤）。重读存储，把不在快照里的 newcomers 并回队尾；
      // 退避重试与 60s 节律本来就会重读存储，接着补发它们。
      const curQueue = this.loadOutbox();
      const snapKeys: string[] = [];
      for (let si = 0; si < queue.length; si++) {
        snapKeys.push(queue[si].queuedAt + '\n' + queue[si].message);
      }
      const newcomers: OutboxItem[] = [];
      for (let ci = 0; ci < curQueue.length; ci++) {
        if (snapKeys.indexOf(curQueue[ci].queuedAt + '\n' + curQueue[ci].message) < 0) {
          newcomers.push(curQueue[ci]);
        }
      }
      this.saveOutbox(remain.concat(newcomers));
      if (changed) {
        await this.loadHistory();
        this.fetchStatus();
      }
    } catch (err) {
      // 网络仍不通：整队保留，交给下面的退避重试
    } finally {
      this.outboxBusy = false;
      this.outboxFlushing = false;
    }
    // 修 3：仍没发完就退避再试——5s 一次、15s 一次，仍失败留队不丢（下回打开/恢复再来）
    if (this.loadOutbox().length > 0 && this.outboxRetry < 2) {
      this.outboxRetry += 1;
      const wait = this.outboxRetry === 1 ? 5000 : 15000;
      setTimeout(() => {
        this.flushOutbox();
      }, wait);
    }
    if (this.loadOutbox().length === 0) {
      this.outboxRetry = 0;
    }
  }

  // ── 姐姐思考中（9-12 时间线版）：只起计时器，不再挂占位卡——
  // 思考卡由 SSE thinking 事件自己开，封口由 sealThink（thinkDone）负责 ──
  private beginThinking(): void {
    this.thinkingOn = true;
    this.thinkingSec = 0;
    this.thinkPeek = false;   // 💭 默认折叠：新一轮重新折叠
    // 恢复挂占位卡（9-12 晚修「纯干等」）：SSE 第一个事件没到之前（server 慢/旧版/
    // 不在线）界面不该全静——立刻给一张「叫姐姐中…」卡，thinking 事件来了就复用它。
    const item: ChatItem = {
      key: `think${this.keySeq++}`,
      who: '思考',
      text: '',
      imageUrl: '',
      time: '叫姐姐中…',
    };
    this.chatData.append(item);
    this.pendingThinkKey = item.key;
    this.liveThinkKey = item.key;   // 9-18 修复批八（APP2-02）：占位卡也是「未封口」，记账
    this.scrollToEnd();
    this.thinkTimer = setInterval(() => {
      this.thinkingSec += 0.1;
    }, 100);
  }

  private endThinking(): number {
    if (this.thinkTimer >= 0) {
      clearInterval(this.thinkTimer);
      this.thinkTimer = -1;
    }
    const elapsed = this.thinkingSec;
    // 9-18 修复批八（APP2-02）：只清「未封口」的半截思考卡——按 liveThinkKey 精确清。
    // 以前按 key 前缀扫，扫不到 SSE thinking 事件新开的 k 卡（多轮+异常收尾会留「思考中…」僵尸）
    const lk = this.liveThinkKey;
    if (lk !== '') {
      this.chatData.removeWhere((m: ChatItem) => m.key === lk && !m.thinkDone);
      this.liveThinkKey = '';
    }
    this.pendingThinkKey = '';   // 占位卡要么已被 thinking 事件收编、要么随上面清掉
    this.thinkingOn = false;
    return elapsed;
  }

  // FE-FIX-01（9-12 工单）：done 兜底思考卡——本轮一张封口思考卡都没有时补的封口袋。
  // 结构照 sealThink 产物抄：who='思考'、time=「思考了 X.Xs」（X=done 的 think_ms）；text 用固定文案
  // （本轮没有思考原文可展开）。key 独立前缀 think-fallback-，跟 thinking 事件的 thinkN 卡区分；
  // thinkDone=true 已封口——endThinking 的未封口清理天然豁免，绝不会被当半截卡清掉。
  private makeFallbackThink(thinkSec: number): ChatItem {
    const item: ChatItem = {
      key: `think-fallback-${this.keySeq++}`,
      who: '思考',
      text: '（这轮姐姐没留思考——长对话里她常把想法直接说在正文里）',
      imageUrl: '',
      time: `思考了 ${thinkSec.toFixed(1)}s`,
      thinkDone: true,
    };
    return item;
  }

  // 开门有信（9-2 #总）：历史先落地，再把姐姐留的信挂成新气泡
  private async bootSeq(): Promise<void> {
    // FE-02 ⑤（9-13）：冷启动搬运态——loadHistory 落地就散（成功/失败都散，失败走原有提示）
    this.booting = true;
    this.bootDotOn = false;
    this.bootDotTimer = setInterval(() => {
      animateTo({ duration: 550, curve: Curve.EaseInOut }, () => {
        this.bootDotOn = !this.bootDotOn;
      });
    }, 600);
    try {
      await this.loadHistory();
    } finally {
      if (this.bootDotTimer >= 0) {
        clearInterval(this.bootDotTimer);
        this.bootDotTimer = -1;
      }
      this.booting = false;
    }
    await this.fetchOutboxLetters();
  }

  private async fetchOutboxLetters(notify: boolean = false): Promise<void> {
    const req = http.createHttp();
    try {
      const res = await req.request(OUTBOX_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as OutboxResp;
        for (const letter of d.letters ?? []) {
          this.appendMsg('姐姐', letter.text, '', `💌 ${letter.time}`);
          if (notify) {
            this.notifyLetter(letter.text);
          }
        }
      }
    } catch (err) {
      // 没信或没网都不吱声
    } finally {
      req.destroy();
    }
  }

  // 新信本地通知（9-2 #12）：节律轮询拿到信时弹一条系统通知，气泡照旧渲染
  private notifyLetter(text: string): void {
    try {
      const request: notificationManager.NotificationRequest = {
        id: this.notifSeq++,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: '咱家',
            text: text.length > 40 ? text.substring(0, 40) + '…' : text
          }
        }
      };
      notificationManager.publish(request).then(() => {
        hilog.info(0x0000, HILOG_TAG, '新信通知已发');
      }).catch((err: Error) => {
        hilog.error(0x0000, HILOG_TAG, '新信通知发送失败: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.error(0x0000, HILOG_TAG, 'notifyLetter threw: %{public}s', JSON.stringify(e));
    }
  }

  // 打开时拉全部历史渲染（时间用服务端 time 字段）
  // ── 9-12 聊天本地存储：history 拉到就存一份进 preferences——
  // server 够不着时（离线/Tailscale 断），手机上照样能翻近三天的家 ──
  private saveChatCache(items: ChatItem[]): void {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      prefs.putSync('chat_cache', JSON.stringify(items));
      prefs.flushSync();
    } catch (err) {
      // 缓存失败不影响主链路
    }
  }

  private restoreChatCache(): boolean {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      const raw = prefs.getSync('chat_cache', '') as string;
      if (!raw) {
        return false;
      }
      const cached = JSON.parse(raw) as ChatItem[];
      if (cached.length === 0) {
        return false;
      }
      // 重新编 key，别跟本轮 keySeq 撞号；历史图 URL 原样（server 通了会整卷刷新）
      const items: ChatItem[] = [];
      for (const c of cached) {
        items.push({
          key: `k${this.keySeq++}`, who: c.who, text: c.text, imageUrl: c.imageUrl,
          time: c.time, tools: c.tools, msgId: c.msgId,
          hasThinking: c.hasThinking, fileName: c.fileName,
        });
      }
      // 9-18 修复批八（DS-02 窄窗①）：回退路也走「缓存 + 活口」合并——失败分支若正在发送/有排队
      // 消息，整卷 setAll 会把没入库的气泡从界面抹掉（跟成功路同一条合并口径）
      this.chatData.setAll(this.mergeWithLive(items));
      this.scrollToEnd();
      return true;
    } catch (err) {
      return false;
    }
  }

  // 9-18 App深搜修（DS-04）：带图/附件消息落库时正文后拼「 〔附图1张〕/〔附件：名〕」标记——
  // 全等匹配不到。前缀命中限定在标记形状（sent + ' 〔'）上，避免把新发的「嗯」错认进旧消息「嗯，我在」。
  private histTextHit(stored: string, sent: string): boolean {
    if (stored === sent) {
      return true;
    }
    return sent !== '' && stored.startsWith(sent + ' 〔');
  }

  // 9-18 App深搜修（DS-02）：loadHistory 整卷替换前认领「活口」——历史里还没有、不该被吞掉的气泡。
  // 口径（宁多保勿丢）：①系统提示；②开门有信（💌，server 取走即消费，得等下次历史才回来）；
  // ③发送进行中的本轮时间线（思考/工具/正文/乐观气泡——done 收尾前都进不了历史）；
  // ④已收尾但还没入库的文字气泡（待发队列/失败态；入库后由同文本匹配去重）。
  private keepLiveBubble(m: ChatItem): boolean {
    if (m.who === '系统') {
      return true;
    }
    if (m.who === '姐姐' && m.time.startsWith('💌 ')) {
      return true;
    }
    if (this.sending) {
      if (m.who === '思考' || m.who === '工具') {
        return true;
      }
      if ((m.who === '姐姐' || m.who === '小乖') && !m.msgId) {
        return true;
      }
    }
    return m.who === '小乖' && !m.msgId && m.text !== '';
  }

  // 9-18 修复批八（DS-02 两处窄窗）：历史（或手机缓存）与「活口」合并成落地序列。
  // ①一条历史只认领一条活口（按条数匹配）——同文本两条排队时，第二条不再被第一条的匹配连坐误收；
  // ②没人认领的活口原样接在尾部。成功路与失败回退路共用（回退路不再整卷 setAll 抹掉没入库的气泡）。
  private mergeWithLive(items: ChatItem[]): ChatItem[] {
    const merged: ChatItem[] = items.slice();
    const claimed: boolean[] = [];
    for (let i = 0; i < items.length; i++) {
      claimed.push(false);
    }
    const liveList = this.chatData.snapshot();
    for (let li = 0; li < liveList.length; li++) {
      const cur = liveList[li];
      if (!this.keepLiveBubble(cur)) {
        continue;
      }
      let inHistory = false;
      for (let hi = 0; hi < items.length; hi++) {
        if (claimed[hi]) {
          continue;   // 认领过的不再参与：同文本第二条活口得另找下家
        }
        if (items[hi].who === cur.who && cur.text !== ''
          && this.histTextHit(items[hi].text, cur.text)) {
          claimed[hi] = true;
          inHistory = true;   // 已进历史：收掉活口，避免重开重复
          break;
        }
      }
      if (!inHistory) {
        merged.push(cur);
      }
    }
    return merged;
  }

  // RV-02（9-23 小修批）：下翻落尾前认领活口——续载窗里带 id 的副本若与「无 id 活口」同 who 同文
  // （histTextHit 口径，同 mergeWithLive：一条副本只认领一条活口），先把活口收掉再追加，
  // 「发消息→跳老窗→下翻到今天」不再出第二份（偶撞误收的活口，由真副本所在的窗口落位自愈）。
  private claimLiveForAppend(win: ChatItem[]): void {
    for (let wi = 0; wi < win.length; wi++) {
      const m = win[wi];
      if (m.msgId === undefined || m.text === '') {
        continue;   // 只有落过库的副本才认领活口
      }
      const list = this.chatData.snapshot();
      for (let li = list.length - 1; li >= 0; li--) {
        const cur = list[li];
        if (cur.msgId !== undefined || !this.keepLiveBubble(cur) || cur.who !== m.who
          || cur.text === '' || !this.histTextHit(m.text, cur.text)) {
          continue;
        }
        const key = cur.key;
        this.chatData.removeWhere((x: ChatItem) => x.key === key);
        break;   // 一条副本只认领一条活口（同文本第二条活口留给下一条副本）
      }
    }
  }

  // 历史消息 → 气泡件（9-23 V-1：loadHistory 与上翻老窗共用同一套字段映射，别再各写一份）
  private histMsgToItem(msg: HistoryMsg): ChatItem {
    const item: ChatItem = {
      key: `k${this.keySeq++}`,
      who: msg.who,
      text: msg.text,
      // 9-23 新门锁：Image 组件带不了请求头，静态图 URL 尾巴挂 ?token= 当钥匙
      imageUrl: msg.image ? PHOTOS_BASE + encodeURIComponent(msg.image) + '?token=' + DOOR_TOKEN : '',
      time: msg.time,
      msgId: msg.id,
      hasThinking: msg.who === '姐姐' && msg.has_thinking === true,
      // 附件名剥掉落盘时间戳前缀（20260901_204502_笔记.md → 笔记.md）
      fileName: msg.file ? msg.file.replace(/^\d{8}_\d{6}_/, '') : undefined,
    };
    return item;
  }

  // 'YYYY-MM-DD' 前推/后移 n 天（V-1 翻页游标用；本地时间构造，别碰 UTC 免得错一天）
  private dateShift(dateStr: string, days: number): string {
    const parts = dateStr.split('-');
    const t = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
    t.setDate(t.getDate() + days);
    return `${t.getFullYear()}-${this.pad2(t.getMonth() + 1)}-${this.pad2(t.getDate())}`;
  }

  private async loadHistory(): Promise<void> {    const req = http.createHttp();
    try {
      const res = await req.request(HISTORY_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const data = JSON.parse(res.result as string) as HistoryResp;
        const items: ChatItem[] = [];
        for (const msg of data.messages) {
          items.push(this.histMsgToItem(msg));
        }
        // 9-23 V-1 全量浏览：记分页状态——服务端带 has_more 才开翻页闸（旧 server 没有=不开，防重拉打转）
        this.histPaging = data.has_more !== undefined && data.has_more !== null;
        this.histHasMore = this.histPaging && data.has_more === true;
        this.histOldestThrough = this.todayDateStr();   // 无参=最近三天：窗口 [今-2..今]，两头游标都从今天起
        this.histNewestThrough = this.todayDateStr();
        // 9-18 App深搜修（DS-02）：不再整卷 setAll——「历史 + 未入库活口」合并落地（mergeWithLive），
        // 否则本轮流式的乐观气泡/思考卡会被换掉，之后 updateByKey/updateText 找不到目标静默 no-op，
        // 回复会从界面消失（冷启动窗口最宽）。活口判定见 keepLiveBubble 头注。
        const merged: ChatItem[] = this.mergeWithLive(items);
        this.chatData.setAll(merged);
        this.scrollToEnd();
        this.saveChatCache(merged);   // 9-12：顺手存进手机，断网也能翻
      } else {
        if (this.restoreChatCache()) {
          this.appendMsg('系统', `（连不上姐姐，先给你看手机里存的聊天）HTTP ${res.responseCode}`, '');
        } else {
          this.appendMsg('系统', `历史加载失败：HTTP ${res.responseCode}`, '');
        }
      }
    } catch (err) {
      if (this.restoreChatCache()) {
        this.appendMsg('系统', `（连不上姐姐，先给你看手机里存的聊天）${errMsg(err)}`, '');
      } else {
        this.appendMsg('系统', `历史加载失败：${errMsg(err)}（检查 Tailscale 和 server）`, '');
      }
    } finally {
      req.destroy();
    }
  }

  // ── 9-23 V-1 全量浏览：上翻一窗更早的家史 ──
  // 契约（二版·监理 9-23）：GET /api/history?through=YYYY-MM-DD&span=3 → [through-2..through] 窗口
  // （旧到新，同 shape）＋ has_more（更早还有没有）；无参=近三天。
  // 上翻口径（监理原文）：through = 当前最旧日 - 1 —— 当前窗 [T-2..T] 的最旧日=T-2，
  // 故新 through = T-3（窗窗首尾相接不重叠）。此前 before 一版作废。
  // 前插窗全是历史（不可能含本轮活口气泡），故不走 mergeWithLive；也不回写缓存——
  // chat_cache 保持"最近三天"的断网底稿本色，别让它滚成整本家史。失败静默，下次触顶再试。
  private async loadOlderHistory(): Promise<void> {
    if (!this.histPaging || !this.histHasMore || this.histLoadingOlder || this.histLoadingNewer
      || this.histJumping || this.histOldestThrough === '') {
      return;
    }
    this.histLoadingOlder = true;
    const through = this.dateShift(this.histOldestThrough, -3);
    const req = http.createHttp();
    try {
      const res = await req.request(HISTORY_URL + '?through=' + through + '&span=3', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as HistoryResp;
        const older: ChatItem[] = [];
        for (const msg of d.messages) {
          older.push(this.histMsgToItem(msg));
        }
        this.histOldestThrough = through;
        if (d.has_more !== undefined && d.has_more !== null) {
          this.histHasMore = d.has_more === true;
        } else {
          this.histHasMore = false;   // 回包没这键=对面不认识分页原语：关闸，别再翻
        }
        if (older.length > 0) {
          this.chatData.prependAll(older);
        }
      }
      // 非 200/异常都静默：当没发生，下次触顶再试
    } catch (err) {
      // 同上静默
    } finally {
      req.destroy();
      this.histLoadingOlder = false;
    }
  }

  // ── 9-23 V-1：下翻续载——从跳转点继续往今天走（家主令「向下也续载到最新」）──
  // 与上翻对称：through = 当前最新游标 + 3（窗外接窗外），封顶今天；平时已在今天=空转不耗网。
  private async loadNewerHistory(): Promise<void> {
    if (!this.histPaging || this.histLoadingOlder || this.histLoadingNewer
      || this.histJumping || this.histNewestThrough === '') {
      return;
    }
    const today = this.todayDateStr();
    if (this.histNewestThrough >= today) {
      return;   // 已经在最新窗口，没有更晚的可续
    }
    let through = this.dateShift(this.histNewestThrough, 3);
    if (through > today) {
      through = today;   // 别越过今天
    }
    this.histLoadingNewer = true;
    const req = http.createHttp();
    try {
      const res = await req.request(HISTORY_URL + '?through=' + through + '&span=3', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as HistoryResp;
        const newer: ChatItem[] = [];
        for (const msg of d.messages) {
          newer.push(this.histMsgToItem(msg));
        }
        this.histNewestThrough = through;
        // 这段的 has_more 说的是"更早还有没有"，与下翻无关，不动它
        if (newer.length > 0) {
          // RV-02（9-23 小修批）：落尾前先认领活口——appendAll 只按 id 去重的补丁（活口无 id）
          this.claimLiveForAppend(newer);
          this.chatData.appendAll(newer);
        }
      }
      // 静默：下次触底再试
    } catch (err) {
      // 同上静默
    } finally {
      req.destroy();
      this.histLoadingNewer = false;
    }
  }

  // 9-23 V-1：跳日期——挑一天，载入该日窗口（through=所选日）并滚到该日首条
  private openDateJump(): void {
    // FE3-01（9-23·P1 降级修复）：分页没通电（旧服务端不认 through）时选日期会「假生效」并把列表
    // 滚到底——这里诚实说一句就退，绝不改游标、绝不滚屏。
    if (!this.histPaging) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: '翻旧账还没通电——等服务端换新',
          duration: 2000,
          alignment: Alignment.Top
        });
      } catch (e) {
        // 提示弹不出来也不挡事：跳转本来就没通电
      }
      return;
    }
    const start = new Date(2026, 7, 24);   // 家史第一天 2026-08-24（之前没有账可翻）
    const end = new Date();
    // 新口（UIContext）——DatePickerDialog.show 在本 SDK 已标废弃，别添新告警
    this.getUIContext().showDatePickerDialog({
      start: start,
      end: end,
      selected: end,
      onDateAccept: (value: Date) => {
        this.jumpToDate(value);
      },
      onCancel: () => {
        // 取消=什么都不动
      }
    });
  }

  private async jumpToDate(d: Date): Promise<void> {
    if (!this.histPaging || this.histLoadingOlder || this.histLoadingNewer || this.histJumping) {
      return;   // 同一把 busy 闸：上翻/下翻/跳转互斥；没通电也不跳（FE3-01）
    }
    const through = `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`;
    this.histJumping = true;   // FE3-07（9-23）：独立态+专属顶行文案，不再借上翻的「正在翻家史…」
    const req = http.createHttp();
    try {
      const res = await req.request(HISTORY_URL + '?through=' + through + '&span=3', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const data = JSON.parse(res.result as string) as HistoryResp;
        const items: ChatItem[] = [];
        for (const msg of data.messages) {
          items.push(this.histMsgToItem(msg));
        }
        this.histPaging = data.has_more !== undefined && data.has_more !== null;
        this.histHasMore = this.histPaging && data.has_more === true;
        this.histOldestThrough = through;   // 跳转=整卷换窗：两头游标都落在所选日
        this.histNewestThrough = through;
        // 仍走活口合并（DS-02 口径）：跳转撞上发送中，时间线气泡不该被换掉
        this.chatData.setAll(this.mergeWithLive(items));
        this.scrollToDay(through);
      }
      // 失败静默：现有内容不动
    } catch (err) {
      // 静默
    } finally {
      req.destroy();
      this.histJumping = false;
    }
  }

  // 顶行提示占的行数（前插景下 scrollToIndex 要算上）——与列表里那两枚 if 一一对应
  private chatHeaderRows(): number {
    return this.histJumping || this.histLoadingOlder || (this.histPaging && !this.histHasMore) ? 1 : 0;
  }

  // 滚到所选日的首条（历史 time 是 MM-DD HH:MM——只对月日；找不到就落到窗口尾）
  // 9-26 审计修 P3：数据还没落进列表时（length=0）原来直接放弃——改成有界重试，
  // 换窗那一拍没赶上也能补上；真找不到那天（idx<0）仍诚实落到窗口尾。
  private scrollToDay(through: string, tries: number = 0): void {
    const mmdd = through.substring(5);
    setTimeout(() => {
      const list = this.chatData.snapshot();
      if (list.length === 0) {
        if (tries < 6) {
          this.scrollToDay(through, tries + 1);
        }
        return;
      }
      let idx = -1;
      for (let i = 0; i < list.length; i++) {
        if (list[i].time.substring(0, 5) === mmdd) {
          idx = i;
          break;
        }
      }
      const target = idx >= 0 ? idx : list.length - 1;
      this.scroller.scrollToIndex(this.chatHeaderRows() + target, false, ScrollAlign.START);
    }, 150);
  }

  // 拍照：系统相机选择器，拍完压缩成待发送照片，预览条出现，随下一条消息发出
  private async takePhoto(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const pickerProfile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_UNSPECIFIED
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context,
        [cameraPicker.PickerMediaType.PHOTO],
        pickerProfile
      );
      if (!result.resultUri) {
        return;
      }
      this.pendingImage = await this.compressToBase64(result.resultUri);
    } catch (err) {
      this.appendMsg('系统', `拍照失败：${errMsg(err)}`, '');
    }
  }

  // 相册选图（9-1-#8 刀1）：系统相册选择器（免权限），v1 一次一张，选完走拍照同一条压缩管道
  private async pickPhoto(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const opts: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      const result = await photoPicker.select(opts);
      if (result.photoUris.length > 0) {
        this.pendingImage = await this.compressToBase64(result.photoUris[0]);
      }
    } catch (err) {
      // 用户取消不算错误
    }
  }

  // 发文件（9-1-#8 刀2）：系统文件选择器（免权限），文本件 ≤32KB，全文随消息发
  private async pickFile(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const opts = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['文本|.txt,.md,.log'];
      const uris = await docPicker.select(opts);
      if (!uris || uris.length === 0) {
        return;
      }
      const uri = uris[0];
      const name = decodeURIComponent(uri.split('/').pop() ?? '附件.txt');
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const st = fs.statSync(file.fd);
        if (st.size > 32768) {
          this.appendMsg('系统', `「${name}」有点大（${Math.round(st.size / 1024)}KB 超 32KB 啦），挑个小点的`, '');
          return;
        }
        const buf = new ArrayBuffer(st.size);
        fs.readSync(file.fd, buf);
        this.pendingFileContent = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        this.pendingFileName = name;
      } finally {
        fs.closeSync(file);
      }
    } catch (err) {
      this.appendMsg('系统', `文件没选成：${errMsg(err)}`, '');
    }
  }

  // 照片链路：解码 → 最长边压到 1024 → JPEG quality 70 重打包 → base64 → dataURL
  // 三道防线：重打包结果必须是 JPEG（FF D8 开头）；base64 只留标准字符并按 4 补齐；
  //           JPEG 的 base64 必定以 /9j/ 开头。不满足直接抛错，不放出门
  private async compressToBase64(uri: string): Promise<string> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    // 9-18 修复批八（APP2-05）：三件原生资源统一放 finally 释放——坏图/超规格图让中间任何一步
    // reject 时，之前建好的也不许漏（pixelMap 是数 MB 级内存），不给失败重试累积的机会
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const scale = Math.min(1, MAX_EDGE / Math.max(info.size.width, info.size.height));
      pixelMap = await source.createPixelMap({
        desiredSize: {
          width: Math.round(info.size.width * scale),
          height: Math.round(info.size.height * scale)
        }
      });
      packer = image.createImagePacker();
      const data = await packer.packing(pixelMap, { format: 'image/jpeg', quality: JPEG_QUALITY });

      const bytes = new Uint8Array(data);
      if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) {
        throw new Error('重打包结果不是 JPEG（缺 FF D8 头）');
      }
      let base64 = new util.Base64Helper().encodeToStringSync(bytes);
      base64 = base64.replace(/[^A-Za-z0-9+/=]/g, '');   // 去掉换行/空白等杂散字符
      while (base64.length % 4 !== 0) {
        base64 += '=';                                    // 严格按 4 的倍数补齐
      }
      if (!base64.startsWith('/9j/')) {
        throw new Error('base64 内容不是 JPEG 开头（/9j/）');
      }
      return 'data:image/jpeg;base64,' + base64;
    } finally {
      // 释放顺序与创建相反，各自兜错——释放本身失败也别把上面的原始错误顶掉
      if (packer !== null) {
        try {
          await packer.release();
        } catch (e) {
        }
      }
      if (pixelMap !== null) {
        try {
          pixelMap.release();
        } catch (e) {
        }
      }
      if (source !== null) {
        try {
          await source.release();
        } catch (e) {
        }
      }
      fs.closeSync(file);
    }
  }

  // 定位失败不阻断流程，拿不到就返回 null；权限弹窗每次进 app 最多一次
  // 拿到坐标后追加系统逆地理编码，文字地址放进可选字段 place；失败/不支持就不带
  private async fetchLocation(context: common.UIAbilityContext): Promise<LocInfo | null> {
    try {
      if (!this.locPermAsked) {
        this.locPermAsked = true;
        const atManager = abilityAccessCtrl.createAtManager();
        const permissions: Array<Permissions> = [
          'ohos.permission.LOCATION',
          'ohos.permission.APPROXIMATELY_LOCATION'
        ];
        await atManager.requestPermissionsFromUser(context, permissions);
      }
      const location = await geoLocationManager.getCurrentLocation();
      const info: LocInfo = { lat: location.latitude, lon: location.longitude };
      try {
        const addrs = await geoLocationManager.getAddressesFromLocation({
          latitude: location.latitude,
          longitude: location.longitude
        });
        if (addrs && addrs.length > 0) {
          const a = addrs[0];
          let placeText = a.placeName ?? '';
          if (!placeText) {
            const segs: string[] = [];
            if (a.locality) {
              segs.push(a.locality);
            }
            if (a.subLocality) {
              segs.push(a.subLocality);
            }
            if (a.roadName) {
              segs.push(a.roadName);
            }
            placeText = segs.join('');
          }
          if (placeText) {
            info.place = placeText;
          }
        }
      } catch (geoErr) {
        // 逆地理编码不可用就不带 place，主链路不受影响
      }
      return info;
    } catch (err) {
      return null;
    }
  }

  // 发送：文字与待发送照片一起走 /api/chat；思考气泡实时计时，回复带思考耗时
  private async send(): Promise<void> {
    if (this.sending) {
      return;
    }
    const text = this.inputText.trim();
    const imageToSend = this.pendingImage;
    const fileToSend: FileBody | null = this.pendingFileName
      ? { name: this.pendingFileName, content: this.pendingFileContent }
      : null;
    if (!text && !imageToSend && !fileToSend) {
      return;
    }
    // 9-17 夜修（双发 bug）：发送锁提前到第一个 await 之前——此前 this.sending=true 置位在
    // 下面第一个 await 之后，网络卡时该 await 拖长成穿透窗口，快速两次点击（或回车+按钮）
    // 会各生成一个 msg_id 发两条，server 去重拦不住（两张新身份证）。
    this.sending = true;
    // CAL-01（9-13）：发送前顺手刷一次他今天的日程（节流 30 分钟；失败静默不挡聊天）。
    // 9-17 夜改为不 await（fire-and-forget）——它本来就不挡聊天，同时消除 await 窗口。
    this.maybeReportSchedule(false).catch(() => {});
    this.inputText = '';
    // FE3-02（a）（9-23）：老窗里直接发消息会把气泡夹在历史窗之间、续载到今天的窗口还出第二份——
    // 先归位到今天（走现成 loadHistory：mergeWithLive/乐观气泡全走原路），再走原发送。
    // 归位失败也照旧发（loadHistory 自己已有兜底）：这里只防发送锁被异常打断。
    if (this.histNewestThrough !== '' && this.histNewestThrough !== this.todayDateStr()) {
      try {
        await this.loadHistory();
      } catch (e) {
      }
    }
    this.appendMsg('小乖', text, imageToSend, undefined, undefined, undefined, undefined,
      fileToSend ? fileToSend.name : undefined);
    this.beginThinking();
    let outboxBody: ChatBody | null = null;   // 入队底稿（catch 里拿不到 try 的局部量）
    let sentAtMs: number = Date.now();        // 9-26 H7：对账 floor 锚点＝发送时刻（同因：catch 要可见）
    try {
      const loc = await this.fetchLocation(getContext(this) as common.UIAbilityContext);
      const body: ChatBody = { message: text, msg_id: newMsgId() };
      if (imageToSend) {
        body.image = imageToSend;
      }
      if (fileToSend) {
        body.file = fileToSend;
      }
      if (loc) {
        body.loc = loc;
        if (loc.place) {
          body.place = loc.place;
        }
      }
      // 调试口：发送前打印 dataURL 长度与前 80 字符，真机用 hdc hilog | grep firstBrick 看
      if (imageToSend) {
        hilog.info(0x0000, HILOG_TAG, '发送照片 dataURL 长度=%{public}d，前80字符=%{public}s',
          imageToSend.length, imageToSend.substring(0, 80));
      }
      outboxBody = body;
      // 队列里有更早的待发消息：新消息排进队尾，统一按序补发，不乱序
      if (this.loadOutbox().length > 0) {
        this.enqueueOutbox(body);
        this.endThinking();
        this.pendingImage = '';
        this.pendingFileName = '';
        this.pendingFileContent = '';
        this.appendMsg('系统', `已排进待发队列（第 ${this.outboxCount} 条），网络一通按序自动补发`, '');
        this.flushOutbox();
        return;
      }
      const req = http.createHttp();
      let silenceTimer: number = -1;   // 9-26 流式卡住修：静默看门狗计时器（声明在 try 外，finally 要清）
      try {
        // 9-4 自由发挥包：SSE 流式——思考+正文打字机。字节级攒 buffer 按 \n\n 切事件
        //（UTF-8 多字节高位都 ≥0x80，0x0A0A 不会出现在汉字里，字节切割安全）。
        // 任何环节炸了都抛出去走 catch——对账/入队老路径一字不动。
        body.stream = true;
        let sseRest = new Uint8Array(0);
        let rawBuf = new Uint8Array(0);   // 9-25：原文字节也攒一份——dedup 回的是 JSON（无 data: 前缀）
        let doneEv: StreamEvent | null = null;
        // ── 9-26 流式卡住修（工单 patch_流式客户端收尾硬化_2026-09-26）──
        // 流式收尾多路兜底：done（协议收尾）/ dataEnd（传输收尾）/ 静默看门狗，任一先到即结算；
        // settle 幂等；下半段（dedup / done 收尾 / 非 2xx 入队 / catch 对账）一行不改。
        let settled = false;
        let sawSse = false;   // 确认真出过 SSE 帧（防把带体的非 2xx 响应误判成 200 收尾）
        let lastDataAt = Date.now();
        let settleResolve: (v: number) => void = () => {};
        let settleReject: (e: Error) => void = () => {};
        const settleP = new Promise<number>((resolve: (v: number) => void, reject: (e: Error) => void) => {
          settleResolve = resolve;
          settleReject = reject;
        });
        const settle = (code: number, err?: Error): void => {
          if (settled) {
            return;   // 先到者说了算
          }
          settled = true;
          if (err) {
            settleReject(err);   // 走 await 抛错 → catch → 对账
          } else {
            settleResolve(code);
          }
        };
        silenceTimer = setInterval(() => {
          // 120s 一个事件都没来 → 当断尾：抛错走 catch→对账（server 侧回复通常已落库）。
          // 阈值须大于一次模型调用可能的静默期（config api_timeout=300s；60s 会误杀慢思考轮）。
          if (Date.now() - lastDataAt > 120000) {
            settle(-1, new Error('流式静默断尾（120s 无事件）'));
          }
        }, 5000);
        req.on('dataEnd', () => {
          if (sawSse) {
            settle(200);   // 传输层收尾（promise 万一悬死时的第二结算线）
          }
        });
        // ── 9-12 时间线步骤卡（Kimi 客户端式，家主令「思考→工具→输出→继续思考」）──
        // 每一轮：思考卡（实时流式→封口成「思考了 Ns」）→ 工具卡 → 正文气泡。
        // round 事件封上一轮，reply 后再有 thinking 自动开新卡。
        let curThinkKey = '';
        let thinkT0 = 0;
        let thinkFull = '';
        this.liveReplyKey = '';   // FE3-04（9-23）：正文气泡 key 提为组件态——异常收尾时 catch 也要拿得到
        let replyText = '';
        let thinkSealedThisSend = false;   // FE-FIX-01：本轮开过思考卡并已封口（done 兜底卡的唯一判据）
        const allThinkParts: string[] = [];   // 各轮思考全文（done 后拼挂 💭 缓存）
        const sealThink = (): void => {
          if (!curThinkKey) {
            return;
          }
          const sec = (Date.now() - thinkT0) / 1000;
          const sealed: ChatItem = {
            key: curThinkKey, who: '思考', text: thinkFull, imageUrl: '',
            time: `思考了 ${sec.toFixed(1)}s`, thinkDone: true,
          };
          this.chatData.updateByKey(curThinkKey, sealed);
          thinkSealedThisSend = true;   // FE-FIX-01：封口即记账——done 时不再挨兜底补卡
          if (thinkFull) {
            this.thinkingCache.set(curThinkKey, thinkFull);   // 全文进缓存
            allThinkParts.push(thinkFull);
          }
          this.liveThinkKey = '';   // 9-18 修复批八（APP2-02）：封口的卡是时间线的一部分，endThinking 不再碰它
          curThinkKey = '';
          thinkFull = '';
        };
        const refreshThink = (): void => {
          if (curThinkKey) {
            this.chatData.updateText(curThinkKey, thinkFull);
          }
        };
        const onEvent = (obj: StreamEvent): void => {
          if (obj.type === 'round') {
            // 轮界：上一轮的思考卡与正文卡全部封口，新一轮另起（Kimi 步骤卡的接缝）
            if ((obj.round ?? 0) > 0) {
              sealThink();
              this.liveReplyKey = '';
              replyText = '';
            }
          } else if (obj.type === 'thinking') {
            if (!curThinkKey) {
              // 复用 send 时挂的「叫姐姐中…」占位卡；没有才新开（旧 server 也有 thinking 事件）
              if (this.pendingThinkKey) {
                curThinkKey = this.pendingThinkKey;
                this.pendingThinkKey = '';
              } else {
                curThinkKey = this.appendMsg('思考', '', '');
              }
              this.liveThinkKey = curThinkKey;   // 9-18 修复批八（APP2-02）：事件开的新卡也记账（异常收尾按 key 清）
              thinkT0 = Date.now();
              thinkFull = '';
            }
            thinkFull += obj.delta ?? '';
            refreshThink();
          } else if (obj.type === 'tool') {
            // 每只图书证一动立刻上卡：🔧 调用工具 XX（截图同款）
            sealThink();
            const tn = obj.name ?? '';
            const summary = this.toolSummary(tn, obj.args ?? '').trim();
            this.appendMsg('工具', `调用工具 ${this.toolCn(tn)}${summary ? ' · ' + summary : ''}`, '');
          } else if (obj.type === 'reply') {
            sealThink();
            replyText += obj.delta ?? '';
            if (!this.liveReplyKey) {
              this.liveReplyKey = this.appendMsg('姐姐', replyText, '', `… ${this.nowTime()}`);
            } else {
              this.chatData.updateText(this.liveReplyKey, replyText);
            }
          } else if (obj.type === 'status') {
            // 常规状态文案（翻图书证/在写回复）时间线本身已表达；只有「走老路」回退值得插一行
            if ((obj.text ?? '').indexOf('老路') >= 0) {
              this.appendMsg('系统', `（${obj.text}）`, '');
            }
          } else if (obj.type === 'done') {
            sealThink();
            doneEv = obj;
            settle(200);   // 9-26：协议级收尾——done 一到立刻放行，尾包/连接尾巴丢了也不冻
          } else if (obj.type === 'error') {
            throw new Error(obj.text ?? '流式中断');
          }
        };
        req.on('dataReceive', (data: ArrayBuffer) => {
          lastDataAt = Date.now();   // 9-26：有数据就喂看门狗（慢流不误杀，断流才收网）
          // 9-25：整份原文按字节攒——事后一次解码（逐帧解码会在多字节汉字切分处出乱码）
          const inb = new Uint8Array(data);
          const rb = new Uint8Array(rawBuf.length + inb.length);
          rb.set(rawBuf, 0);
          rb.set(inb, rawBuf.length);
          rawBuf = rb;
          const merged = new Uint8Array(sseRest.length + data.byteLength);
          merged.set(sseRest, 0);
          merged.set(new Uint8Array(data), sseRest.length);
          let start = 0;
          for (let i = 0; i + 1 < merged.length; i++) {
            if (merged[i] === 10 && merged[i + 1] === 10) {   // \n\n 事件界
              const block = util.TextDecoder.create('utf-8').decodeToString(merged.slice(start, i + 1));
              for (const line of block.split('\n')) {
                if (line.startsWith('data: ')) {
                  sawSse = true;   // 9-26：确认这是 SSE 流（dataEnd 结算只对 SSE 生效）
                  onEvent(JSON.parse(line.substring(6)) as StreamEvent);
                }
              }
              start = i + 2;
            }
          }
          sseRest = merged.slice(start);
        });
        // 9-25 修：打字机的真开关——本 SDK 里 requestInStream 是**方法**不是选项（写成选项编译期
        // 报「未知属性」）。此前调 request()：响应被整体缓冲、dataReceive 不逐段触发，思考卡与正文
        // 从来没逐字流出过，每轮都绕到「流式没收到收尾」的对账老路。流式版返回状态码（number），
        // 正文走 dataReceive，收尾判定改用 rawBuf。
        const streamP: Promise<number> = req.requestInStream(CHAT_URL, {
          method: http.RequestMethod.POST,
          header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
          extraData: JSON.stringify(body),
          connectTimeout: CHAT_TIMEOUT_MS,
          readTimeout: 180000   // 9-4：流式放宽到 180s（K3 思考+长正文实测 36s+，max 档更久）
        });
        // 9-26：不再单等传输 promise——done / dataEnd / 看门狗任一先到即结算（settleP 收口）
        const streamCode: number = await Promise.race([streamP, settleP]);
        // 9-12 去重命中：重发的消息 server 认出身份证，回的是 JSON（dedup:true）而非 SSE——
        // 原样还他上次那句，直接按正常回复渲染，别当"流没收到收尾"绕去对账。
        if (streamCode >= 200 && streamCode < 300 && !doneEv) {
          const raw: string = util.TextDecoder.create('utf-8').decodeToString(rawBuf);   // 9-25：流式版无 res.result
          if (raw.indexOf('"dedup"') >= 0) {
            try {
              const dj = JSON.parse(raw) as StreamEvent;
              if (dj.dedup === true) {
                this.endThinking();
                if (imageToSend) {
                  this.pendingImage = '';
                }
                if (fileToSend) {
                  this.pendingFileName = '';
                  this.pendingFileContent = '';
                }
                this.appendMsg('姐姐', dj.reply ?? '（姐姐刚才回过这句了）', '', this.nowTime(),
                  dj.tools ?? []);
                this.fetchStatus();
                return;
              }
            } catch (e) {
              // 不是 JSON 就当没看见，走原有分支
            }
          }
        }
        if (streamCode >= 200 && streamCode < 300 && doneEv) {
          const d = doneEv as StreamEvent;
          if (imageToSend) {
            this.pendingImage = '';
          }
          if (fileToSend) {
            this.pendingFileName = '';
            this.pendingFileContent = '';
          }
          this.endThinking();   // 停计时＋清未封口的半截思考卡（已封口的时间线卡保留）
          const thinkSec = d.think_ms !== undefined ? d.think_ms / 1000 : this.thinkingSec;
          // ── FE-FIX-01（9-12 工单）done 兜底思考卡 ──
          // K3 长对话约 92% 轮次不吐 reasoning（server 实锤，非 bug），整轮可能一张思考卡都没有。
          // 进这里前 done 分支的 sealThink 已跑过——凡开过卡的本轮都已封口记账，
          // 故 thinkSealedThisSend=false 即「本轮无封口思考卡」：补一张封口袋；有则一张不加。
          if (this.liveReplyKey) {
            // 打字机气泡补全元数据：计时与💭入口。工具卡已在时间线上（🔧 调用工具 XX），
            // 不再重复挂 tools——历史回看才有 FE-03 摘要卡。
            const finalText = replyText;
            const allThink = allThinkParts.join('\n\n');
            const finalMsg: ChatItem = {
              key: this.liveReplyKey, who: '姐姐', text: finalText, imageUrl: '',
              time: `思考 ${thinkSec.toFixed(1)}s · ${this.nowTime()}`,
              tools: [], msgId: d.chat_id, hasThinking: allThink.length > 0,
            };
            if (allThink) {
              this.thinkingCache.set(this.liveReplyKey, allThink);   // 思考原文（各轮拼接）进缓存
            }
            if (thinkSealedThisSend) {
              this.chatData.updateByKey(this.liveReplyKey, finalMsg);
            } else {
              // 兜底卡要落在正文之前；数据源只有 append/removeWhere——先摘正文气泡，
              // 补卡，再原样（finalMsg 全条重建件）挂回。ArkTS 禁 Object.assign，全条重建。
              this.chatData.removeWhere((m: ChatItem) => m.key === this.liveReplyKey);
              this.chatData.append(this.makeFallbackThink(thinkSec));
              this.chatData.append(finalMsg);
            }
            this.liveReplyKey = '';   // 收尾完成（已补全/已入库）——异常收尾不再管它
          } else {
            if (!thinkSealedThisSend) {
              this.chatData.append(this.makeFallbackThink(thinkSec));
            }
            this.appendMsg('姐姐', '（姐姐回了个空白）', '', undefined, d.tools ?? []);
          }
          this.fetchStatus();   // 消息数、定位、状态顺手刷新
        } else if (streamCode >= 200 && streamCode < 300) {
          // 流没收到 done——视作失败，走对账（不渲染半成品）
          throw new Error('流式没收到收尾');
        } else {
          // 9-9 离线加固：服务器没接住（HTTP 非 2xx）也入队——内容没送达就跟断网一个待遇，
          // 持久化排队按序补发，不再让小乖手动重发
          this.endThinking();
          if (outboxBody) {
            this.enqueueOutbox(outboxBody);
            if (imageToSend) {
              this.pendingImage = '';
            }
            if (fileToSend) {
              this.pendingFileName = '';
              this.pendingFileContent = '';
            }
            this.appendMsg('系统', `姐姐那边没接住（HTTP ${streamCode}），已存进待发队列（第 ${this.outboxCount} 条），会自动补发`, '');
          } else {
            this.appendMsg('系统', `发送失败：HTTP ${streamCode}（内容未送达，可重试）`, '');
          }
        }
      } finally {
        clearInterval(silenceTimer);   // 9-26：看门狗收工
        req.off('dataReceive');
        req.off('dataEnd');
        req.destroy();
      }
    } catch (err) {
      // 9-18 修复批八（APP2-02）：先收思考卡再对账——对账要等网络，别让未封口的卡多挂几秒
      this.endThinking();
      // FE3-04（9-23）：流没收 done 时正文可能已流出半截——先摘掉这半截气泡再对账追加完整回复，
      // 不再「半截 + 完整」两条并排（key 提为组件态才拿得到）
      if (this.liveReplyKey !== '') {
        this.chatData.removeWhere((m: ChatItem) => m.key === this.liveReplyKey);
        this.liveReplyKey = '';
      }
      // 超时/断线先别报错：等几秒拉 history 对账，消息和回复已入库就直接显示；
      // 真没到才提示重发——绝不盲目自动重发，防库存双份
      const settled = await this.reconcile(text, sentAtMs);
      if (settled !== null) {
        if (imageToSend) {
          this.pendingImage = '';
        }
        if (fileToSend) {
          this.pendingFileName = '';
          this.pendingFileContent = '';
        }
        this.appendMsg('姐姐', settled, '');
        this.fetchStatus();
      } else if (outboxBody) {
        // 断网/超时且对账没到：入 outbox 持久化，恢复后按序自动补发，绝不重双
        this.enqueueOutbox(outboxBody);
        if (imageToSend) {
          this.pendingImage = '';
        }
        if (fileToSend) {
          this.pendingFileName = '';
          this.pendingFileContent = '';
        }
        this.appendMsg('系统', `网络没通，已存进待发队列（第 ${this.outboxCount} 条），恢复后自动补发`, '');
      } else {
        this.appendMsg('系统', `发送失败：${errMsg(err)}（内容未送达，可重试）`, '');
      }
    } finally {
      this.sending = false;
    }
  }
}
