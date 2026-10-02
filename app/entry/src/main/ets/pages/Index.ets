// ═══════════════════════════════════════════════════════════════════════════════
// 📖 Index.ets · 段落目录（9-30 单文件拆分后重排）
//    ⚠️ 行号是**快照**，文件一改就会漂——找东西**按名字**更稳（搜符号名即可）。
//
// 这一份文件现在是「壳」：状态 + build + 全屏页调度 + 网络/取数与业务逻辑。
// 显示层已外提（改页面去 view/，改数据形状去 model/，改纯逻辑去 common/）：
//   view/   Thinking Traces Logs Wall Letter PhotoWall ImagePreview Stats Checkin
//          CheckinDetail Reader Archive Reports KbEdit MdReader MdSegText
//   model/  apiTypes（接口＋词表）· chatDataSource
//   common/ timetable（课表解析）· markdown（md 解析）· format（文案/数字/时间）
//           draw（canvas 小件）· theme（dkColor/errText）· AppStyles（色板/字号/圆角）
//
// ── 本文件内部 ───────────────────────────────────────────────────────────────
//   L98    模块级：imports · 门牌/URL 常量 · applyServerBase · @Styles 按压样式 · errMsg 壳
//   L291   struct Index 起
//   L294   状态声明区（158 个 @State/@StorageProp：夜设、安全区、门牌快照、各页开关与数据）
//         （状态区止于 L507 附近；下面依次是各 @Builder 与 方法）
//
//   【@Builder 构建器 · 17 个】
//     L778   TabLabel(icon: string, label: string, idx: number)   13 行
//     L794   GoodnightBtn()                       16 行
//     L812   ChatView()                          374 行
//     L1188  CoverHub()                           88 行
//     L1280  XgWordsEditPage()                    70 行
//     L1360  RiverDotCard(p: MoodPoint)           40 行
//     L1403  RiverFullPage()                      98 行
//     L1505  HallPage()                          559 行
//     L2142  StatsCard()                          35 行
//     L2183  HealthPage()                         18 行
//     L2202  NightPage()                          18 行
//     L2221  NotesPage()                          18 行
//     L2491  SettingsPage()                      367 行
//     L3071  DailyPage()                          39 行
//     L3299  MsgBubble(item: ChatItem)           194 行
//     L3921  MoodPage()                          229 行
//     L5267  ImgGoneTip()                          9 行
//
//   【网络 / 取数 / 落盘 · 36 个】
//     L2066  fetchStats                           25 行
//     L2094  applyStats                           16 行
//     L2113  reloadStats                          26 行
//     L2249  fetchArchive                         31 行
//     L2285  fetchArchiveDoc                      32 行
//     L2326  fetchCards                           19 行
//     L2347  fetchFavorites                       30 行
//     L2384  fetchWall                            30 行
//     L2416  fetchReports                         27 行
//     L2910  fetchLogs                            26 行
//     L2977  postSchedule                         18 行
//     L3003  saveTimetable                        26 行
//     L3111  fetchCheckinData                     38 行
//     L3151  fetchMonthCheckins                   19 行
//     L3569  fetchStatus                         151 行
//     L3741  pushCard                             36 行
//     L3779  fetchPromise                         25 行
//     L4443  fetchMoods                           26 行
//     L4703  fetchHall                            70 行
//     L4775  fetchTraces                          21 行
//     L4809  fetchHealth                          37 行
//     L4848  pushHealthGroups                     50 行
//     L4900  fetchShadowLines                     54 行
//     L4956  fetchMechGroups                      30 行
//     L4995  fetchDream                           35 行
//     L5067  fetchNotes                           35 行
//     L5158  saveXiaoguaiWords                    28 行
//     L5360  loadOutbox                            8 行
//     L5369  saveOutbox                           10 行
//     L5405  watchNetRecovery                     24 行
//     L5621  fetchOutboxLetters                   24 行
//     L5672  saveChatCache                         9 行
//     L5819  loadHistory                          43 行
//     L5870  loadOlderHistory                     39 行
//     L5912  loadNewerHistory                     44 行
//     L6189  fetchLocation                        46 行
//
//   【其余大件（方法，前 18）】
//     L6237  send                                421 行
//     L4225  drawRiverOn                         178 行
//     L611   build                               164 行
//     L3569  fetchStatus                         151 行
//     L5430  flushOutbox                         119 行
//     L4603  pickAndImportBook                    97 行
//     L4703  fetchHall                            70 行
//     L522   aboutToAppear                        64 行
//     L6130  compressToBase64                     56 行
//     L4900  fetchShadowLines                     54 行
//     L4848  pushHealthGroups                     50 行
//     L6189  fetchLocation                        46 行
//     L5912  loadNewerHistory                     44 行
//     L5819  loadHistory                          43 行
//     L2446  openReport                           42 行
//     L4524  submitParaMarkAsync                  42 行
//     L3831  sayGoodnight                         41 行
//     L4471  openReader                           40 行
//
//   【不拆的调度器】build() · CoverHub（全屏页互斥调度）· DailyPage（按日期铺页）
// ───────────────────────────────────────────────────────────────────────────────
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
import { window, mediaquery, LengthMetrics } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import {
  C_BG, C_ACCENT, C_BUBBLE_ME, C_HER_EDGE, C_PANEL, C_WHITE, C_CARD,
  C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4, C_TEXT_5, C_OK, C_DISABLED, C_DOT_BORDER,
  FS_TITLE, FS_BODY, FS_SUB, FS_AUX, R_TAIL, R_SM, R_MD, R_LG, R_XL, R_PILL, R_PILL_XL,
  M_PAGE, NIGHT_MAP
} from '../common/AppStyles';
import { dkColor, errText } from '../common/theme';   // 9-30 拆分：纯函数外提，本文件留同名壳
import {
  toolCn, toolSummary, fmtSize, numTxt, wanTxt,
  nowTime, sleepMs, histTextHit, traceEndingCn, moodNameOf,
  detailMonthDays, httpErrMsg, mechTextToLines
} from '../common/format';
import {
  hexToRgba, drawStar5, drawSpark4
} from '../common/draw';
import {
  MoodTypeItem, MOOD_TYPES, MOOD_LEGACY_COLOR, LEGACY_MOOD_MAP, LocInfo, ChatBody,
  StreamEvent, FileBody, ScheduleItem, ScheduleBody, ToolUseInfo, HistoryMsg,
  TurnInfo, TurnTool,   // APP-01（10-01）：过程留存
  HistoryResp, StatusResp, BridgeUpResp, GoodnightResp, LogsResp, BookMark,
  BookShelf, BooksResp, TraceItem, TracesResp, RVTab, RIVER_TABS,
  PrefTab, NIGHT_PREF_TABS, BookContentResp, StatsResp, LedgerPair, ArchiveItem,
  ArchiveResp, ArchiveTextResp, CardItem, CardGroup, CardsResp, FavoritesResp,
  WallPin, WallResp, LibReportItem, LibReportsResp, LibReportDocResp, PromiseResp,
  HealthSoftTop, HealthSoftFail, HealthEmbed, HealthBackup, HealthMechFace, HealthLedgerScene,
  HealthLedger, HealthResp, ShDesire, ShSingle, ShRecall, ShHuatou,
  ShGate, ShadowsResp, MechSection, MechResp, DreamHeat, DreamMerge,
  DreamReplay, DreamNight, DreamResp, NoteItem, NotesResp, ThinkingResp,
  OutboxResp, CheckinItem, CheckinItemsResp, TodayCheckin, TodayCheckinsResp, MonthCheckinItem,
  MonthCheckinsResp, OkResp, MoodPoint, MoodsResp, MoodReqBody, RiverDot,
  HallEntry, HallResp, HallReqBody, WordsResp, LetterReqBody, CheckinReqBody,
  ArchiveReqBody, OutboxItem, ChatItem
} from '../model/apiTypes';
import { ChatDataSource } from '../model/chatDataSource';
import {
  pad2, parseTimetable, pickTimetableToday
} from '../common/timetable';
import { MdReader } from '../view/MdReader';
import { ArchivePage } from '../view/ArchivePage';
import { ReportsPage } from '../view/ReportsPage';
import { ReaderPage } from '../view/ReaderPage';
import { CheckinPage } from '../view/CheckinPage';
import { KbEditPage } from '../view/KbEditPage';
import { ThinkingPage } from '../view/ThinkingPage';
import { LogsPage } from '../view/LogsPage';
import { WallPage } from '../view/WallPage';
import { PhotoWallPage } from '../view/PhotoWallPage';
import { LetterPage } from '../view/LetterPage';
import { TracesPage } from '../view/TracesPage';
import { ImagePreviewPage } from '../view/ImagePreviewPage';
import { StatsPage } from '../view/StatsPage';
import { CheckinDetailPage } from '../view/CheckinDetailPage';
// 9-29 §12 app 显示面：只读信息页骨架（家的体检 / 夜里 / 随手记 三页共用）——拆分第一块砖
import { InfoPage, InfoGroup } from './InfoPage';

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
// ── 9-29 §12 app 显示面（家主令「能显示的都显示，除她的隐私空间」）──
// 全是只读口；隐私边界：影子读数**不带她的原文**、睡眠整理的牵线**只报条数**、台账**私档段不出**。
let HEALTH_URL: string = BASE_URL + '/api/health';     // 家的体检·观测层（9-28 柔性批；开关 health_api）
let SHADOWS_URL: string = BASE_URL + '/api/shadows';   // 家的体检·影子读数（9-29 服务端新件）
let MECH_URL: string = BASE_URL + '/api/mech';         // 家的体检·机制台账公开段（9-29 服务端新件）
let DREAM_URL: string = BASE_URL + '/api/dream';       // 夜里·睡眠整理（9-29 服务端新件）
let NOTES_URL: string = BASE_URL + '/api/notes';       // 随手记（9-9 现成，此前 app 没接）

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
  HEALTH_URL = b + '/api/health';
  SHADOWS_URL = b + '/api/shadows';
  MECH_URL = b + '/api/mech';
  DREAM_URL = b + '/api/dream';
  NOTES_URL = b + '/api/notes';
}
const HTTP_TIMEOUT_MS: number = 30000;
const CHAT_TIMEOUT_MS: number = 90000;   // /api/chat 专用：姐姐查图书证会多花时间，放宽到 90s
const HILOG_TAG: string = 'firstBrick';


// ── 轻动效（工单 FE-02）：按压反馈只动透明度——合成器逐帧廉价，120Hz 友好，不用毛玻璃不吃重阴影 ──
@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}



// 9-30 拆分：实现已外提到 common/theme（纯函数），这里只留同名壳——22 处调用点一行不动。
function errMsg(err: Object): string {
  return errText(err);
}

// 9-12 消息身份证：时间戳+随机，够防「同一条消息的两次重试」撞号——
// 去重窗口是秒级到分钟级，不需要正经 UUID。
function newMsgId(): string {
  return `m${Date.now().toString(36)}${Math.floor(Math.random() * 0xffffffff).toString(36)}`;
}





@Entry
@Component
struct Index {
  // ── 夜间模式（9-12 家主令）：关/开/跟随系统，AppStorage 持久化。
  // 跟随系统 = mediaquery 监听系统深色模式（sysDark 由 aboutToAppear 的监听器维护）──
  @StorageProp('nightPref') nightPref: string = 'auto';
  private mqListener: mediaquery.MediaQueryListener | undefined = undefined;
  // ── 9-27 打字机真修（v5）：正在流的两张卡改由 @State 驱动、在 List 尾部条件渲染 ──
  // 病因：LazyForEach 里"原地改一条"（updateText/updateByKey → onDataChange）**画不出来**——
  // 官方文档 @Builder 参数传递规则：按值传递（传变量）时参数变化**不会**引起 @Builder 内 UI 刷新；
  // 列表项 `this.MsgBubble(item)` 正是按值传。于是 177 帧 thinking、100 帧正文全到了、数据也是全的，
  // 屏上却只有创建那一刻的第 1 个字（「哈」）——"打字机从 9-12 起就没在屏幕上长过"。
  // 修法照文档原话「建议通过 this 访问组件的状态变量，而不是通过参数传递」：
  //   正在流的两张卡**不进 chatData**，读 this 上的 @State（每次 delta 赋值即重画）；
  //   封口/收尾时才 append 进 chatData（新增=onDataAdd=可见）。
  @State liveThinkOn: boolean = false;       // 有一张正在写的思考卡
  @State liveThinkStarted: boolean = false;  // 已收到过 thinking 事件（决定显示「叫姐姐中…」还是计时）
  @State liveThinkText: string = '';         // 正在流的思考原文（点开可看尾段）
  @State liveReplyOn: boolean = false;       // 有一条正在长的正文气泡
  @State liveReplyText: string = '';         // 正在流的正文
  @State liveReplyTime: string = '';         // 正文气泡的时间戳（建卡时定）
  // 夜下取色：色值在 NIGHT_MAP 里就换夜装，查不到原样——一个函数，全屋换灯。
  // 9-30 拆分：实现外提到 common/theme（纯函数，别的页面文件也能用）；这里留同名壳，
  // 474 处 this.dk(...) 调用点一行不动。
  private dk(c: string): string {
    return dkColor(c, this.nightPref);
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
  // ── outbox 待发队列（工单 9-1-#2） ──
  @State outboxCount: number = 0;
  @State outboxFlushing: boolean = false;   // 补发期间标题栏亮「补发中…」（9-1-#3）
  private outboxBusy: boolean = false;
  private outboxFetchBusy: boolean = false;   // 10-02：fetchOutboxLetters 的闸（boot＋60s 轮询别重叠）
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
  // 9-18 修复批八（APP2-01）：打开编辑器时没看懂的行——界面列出来、保存时原样拼回，
  // 编辑器只管它看得懂的条目，坏行不许被它无声抹掉（parseTimetable 的「不许静默吞」口径）
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
  // ── 9-29 §12 app 显示面（家主令「能显示的都显示，除她的隐私空间」）──
  // 三页共用只读骨架 InfoPage；取数与文案整形在这边（它手里有门牌与钥匙），组件只管画。
  @State healthOpen: boolean = false;      // 🩺 家的体检
  @State healthBusy: boolean = false;
  @State healthMsg: string = '';
  @State healthGroups: InfoGroup[] = [];
  @State nightOpen: boolean = false;       // 🌙 夜里（睡眠整理）
  @State nightBusy: boolean = false;
  @State nightMsg: string = '';
  @State nightGroups: InfoGroup[] = [];
  @State notesOpen: boolean = false;       // 📝 随手记（她的小本本）
  @State notesBusy: boolean = false;
  @State notesMsg: string = '';
  @State notesGroups: InfoGroup[] = [];
  // ── 姐姐思考中 ──
  @State thinkingSec: number = 0;
  @State thinkPeek: boolean = false;         // 💭 默认折叠（9-9）：流式思考点一下才偷看
  private locPermAsked: boolean = false;
  private scroller: Scroller = new Scroller();
  // 9-29 修（家主：「打开一个东西，退出来就回到顶点了，尤其是共读」）：
  // 共读阅读器退出会清 readParas、再开是新列表 → 位置全丢。这里记住「读到第几段」，
  // 同一本再打开时跳回那段（换书从头）。
  private readerScroller: Scroller = new Scroller();
  private readerFirstIdx: number = 0;
  private readerBookId: number = -1;
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
    if (this.bootDotTimer >= 0) {   // 10-02 修：原先漏了这个——loadHistory 卡住时页面销毁后仍 animateTo
      clearInterval(this.bootDotTimer);
      this.bootDotTimer = -1;
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
      || this.imgPreviewUrl !== '' || this.xgEditOpen || this.kbEditOpen
      || this.healthOpen || this.nightOpen || this.notesOpen, this.CoverHub, {
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
        } else if (this.healthOpen) {
          this.healthOpen = false;   // 9-29 §12：家的体检（返回键关页）
        } else if (this.nightOpen) {
          this.nightOpen = false;    // 9-29 §12：夜里
        } else if (this.notesOpen) {
          this.notesOpen = false;    // 9-29 §12：随手记
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
          // 9-27 v5：正在流的两张卡——传**对象字面量**（官方：按引用传递，仅一个参数且直接传字面量时生效），
          // 字面量里读 this 上的 @State ⇒ 每次赋值即重画。这两张卡不进 chatData，归档时才 append。
          if (this.liveThinkOn) {
            ListItem() {
              this.MsgBubble({
                key: '@live-think', who: '思考', text: this.liveThinkText, imageUrl: '',
                time: this.liveThinkStarted ? '' : '叫姐姐中…',
              })
            }
          }
          if (this.liveReplyOn) {
            ListItem() {
              this.MsgBubble({
                key: '@live-reply', who: '姐姐', text: this.liveReplyText, imageUrl: '',
                time: this.liveReplyTime,
              })
            }
          }
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
      ThinkingPage({ safeTopPad: this.safeTopPad, thinkingText: this.thinkingText, thinkingOpen: $thinkingOpen })
    } else if (this.riverFullOpen) {
      this.RiverFullPage()
    } else if (this.readingOpen) {
      ReaderPage({
        safeLeftPad: this.safeLeftPad, safeTopPad: this.safeTopPad, readBusy: this.readBusy,
        readParas: this.readParas, readBook: this.readBook,
        readSelPara: $readSelPara, readParaMark: $readParaMark, scroller: this.readerScroller,
        onClose: () => { this.closeReader(); },
        onIndexChange: (i: number) => { this.readerFirstIdx = i; this.reportReadPos(i); },
        onSubmitMark: () => { this.submitParaMark(); }
      })
    } else if (this.logsOpen) {
      LogsPage({
        safeTopPad: this.safeTopPad, logsBusy: this.logsBusy, logsText: this.logsText,
        logsOpen: $logsOpen, onRefresh: () => { this.fetchLogs(); }
      })
    } else if (this.statsOpen) {
      StatsPage({          // 9-23 B2-1：账本全屏页
        safeTopPad: this.safeTopPad, statsData: this.statsData,
        statsFullBusy: this.statsFullBusy, statsFullMsg: this.statsFullMsg,
        statsOpen: $statsOpen, onRefresh: () => { this.reloadStats(); }
      })
    } else if (this.archiveOpen) {
      ArchivePage({        // 9-23 V-2：档案馆全屏页
        safeTopPad: this.safeTopPad, archBusy: this.archBusy, archCards: this.archCards,
        archItems: this.archItems, archMsg: this.archMsg,
        archiveOpen: $archiveOpen, archDocTitle: $archDocTitle, archDocText: $archDocText,
        onRefresh: () => { this.fetchArchive(); this.fetchCards(); },
        onOpenCard: (c: CardItem) => { this.openCard(c); },
        onOpenDoc: (n: string) => { this.fetchArchiveDoc(n); }
      })
    } else if (this.favOpen && this.imgPreviewUrl === '') {
      PhotoWallPage({
        safeTopPad: this.safeTopPad, favBusy: this.favBusy, favMsg: this.favMsg,
        favPhotos: this.favPhotos, imgErrKeys: this.imgErrKeys, favOpen: $favOpen,
        imgPreviewUrl: $imgPreviewUrl,
        onRefresh: () => { this.fetchFavorites(); },
        onImgErr: (u: string) => { this.markImgErr(u); },
        favUrl: (n: string) => this.favPhotoUrl(n)
      })
    } else if (this.imgPreviewUrl !== '') {
      // FE-02 ②：点图看大图；9-23 能上批 a——照片墙里点开的图也走这里，
      // 所以大图层要排在墙前面判：关掉大图后墙还在，不会把人甩回书架
      ImagePreviewPage({
        safeTopPad: this.safeTopPad, imgErrKeys: this.imgErrKeys,
        imgPreviewUrl: $imgPreviewUrl, onImgErr: (u: string) => { this.markImgErr(u); }
      })
    } else if (this.wallOpen) {
      WallPage({
        safeTopPad: this.safeTopPad, wallBusy: this.wallBusy, wallMsg: this.wallMsg,
        wallPins: this.wallPins, wallOpen: $wallOpen, onRefresh: () => { this.fetchWall(); }
      })
    } else if (this.repOpen) {
      ReportsPage({        // 9-23 能上批 d：周报阅读器（只读）
        safeTopPad: this.safeTopPad, repBusy: this.repBusy, repMsg: this.repMsg,
        repItems: this.repItems, repDocTitle: this.repDocTitle, repDocStatus: this.repDocStatus,
        repOpen: $repOpen, repTab: $repTab, repDocId: $repDocId, repDocText: $repDocText,
        onRefresh: () => { this.fetchReports(); },
        onOpenReport: (it: LibReportItem) => { this.openReport(it); }
      })
    } else if (this.xgEditOpen) {
      this.XgWordsEditPage()    // 9-17 夜：改这封信（全屏，替代原 120vp 内联小框）
    } else if (this.kbEditOpen) {
      KbEditPage({         // 9-17 夜：周课表图形化编辑器
        draft: this.timetableDraft, safeTopPad: this.safeTopPad,
        onClose: () => { this.kbEditOpen = false; },
        onSave: (text: string, renamed: number) => {
          this.timetableDraft = text;
          this.saveTimetable();   // 老路：存偏好 + 校验提示（timetableMsg 显示在设置页）
          if (renamed > 0) {
            this.timetableMsg = this.timetableMsg
              + `（${renamed} 条课名里的「，；」已存成「·」——这俩是课表格式的分段符）`;
          }
          this.kbEditOpen = false;
        }
      })
    } else if (this.healthOpen) {
      this.HealthPage()         // 9-29 §12：🩺 家的体检（只读；三页共用 InfoPage 骨架）
    } else if (this.nightOpen) {
      this.NightPage()          // 9-29 §12：🌙 夜里（睡眠整理）
    } else if (this.notesOpen) {
      this.NotesPage()          // 9-29 §12：📝 随手记
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

  // 书脊色池：每本书按上架顺序取一色，架上看去像真的书排
  private bookSpineColors: string[] =
    ['#a86450', '#7a8a5a', '#5a6e8a', '#8a6e5a', '#6e5a8a', '#8a7a4a'];

  private bookSpineColor(i: number): string {
    return this.bookSpineColors[Math.abs(i) % this.bookSpineColors.length];
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
        Text(`${p.date.substring(5).replace('-', '/')} ${p.time} · ${moodNameOf(p.type) || '旧记分'} ×${p.score} · ${p.source}`)
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
        LetterPage({
          stLetters: this.stLetters, letterText: $letterText,
          letterMsg: this.letterMsg, letterBusy: this.letterBusy,
          onSend: () => { this.sendLetter(); }
        })
      } else if (this.hallBrowse === '她的独处') {
        TracesPage({
          traceMsg: this.traceMsg, tracesList: this.tracesList, traceOpenId: $traceOpenId
        })
      } else {
      List({ space: 12 }) {
        ForEach(this.hallEntries, (e: HallEntry) => {
          ListItem() {
            Column({ space: 6 }) {
              Row({ space: 10 }) {
                Text(e.mood ? moodNameOf(e.mood).substring(0, 1) : (e.author === '姐姐' ? '宁' : '乖'))
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
  // 总账页·缺席卡（9-23 B2-1）：账没数到就诚实说缺席，不拿 0 冒充
  // ── 咱家的账本·全屏页（9-23 B2-1：总账上墙，点开看全）——照工地日志家风带刷新/关闭 ──
  // ── 9-29 §12：三页只读信息页（骨架在 pages/InfoPage.ets；这里只做 props 装配）──
  // 拆出去的好处：这三页的排版/空态/按压反馈都在 InfoPage 一处，本文件只管"取数 + 喂进去"。
  @Builder
  HealthPage() {
    InfoPage({
      nightPref: this.nightPref,
      topPad: this.safeTopPad,
      icon: '🩺',
      title: '家的体检',
      busy: this.healthBusy,
      msg: this.healthMsg,
      groups: this.healthGroups,
      onRefresh: () => {
        this.fetchHealth();
      },
      onClose: () => {
        this.healthOpen = false;
      }
    })
  }

  @Builder
  NightPage() {
    InfoPage({
      nightPref: this.nightPref,
      topPad: this.safeTopPad,
      icon: '🌙',
      title: '夜里',
      busy: this.nightBusy,
      msg: this.nightMsg,
      groups: this.nightGroups,
      onRefresh: () => {
        this.fetchDream();
      },
      onClose: () => {
        this.nightOpen = false;
      }
    })
  }

  @Builder
  NotesPage() {
    InfoPage({
      nightPref: this.nightPref,
      topPad: this.safeTopPad,
      icon: '📝',
      title: '随手记',
      busy: this.notesBusy,
      msg: this.notesMsg,
      groups: this.notesGroups,
      onRefresh: () => {
        this.fetchNotes();
      },
      onClose: () => {
        this.notesOpen = false;
      }
    })
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
        this.archMsg = httpErrMsg(res.result as string, '这间屋还没开门');
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
        this.archDocText = '（没取到：' + httpErrMsg(res.result as string, `HTTP ${res.responseCode}`) + '）';
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
        this.repDocText = '（没取到：' + httpErrMsg(res.result as string, `HTTP ${res.responseCode}`) + '）';
      }
    } catch (err) {
      if (seq === this.repDocSeq) {
        this.repDocText = '（没取到：' + errMsg(err as Object) + '）';
      }
    } finally {
      req.destroy();
    }
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

  // ── 9-29 §12：家里的事（三只只读页入口）——家主令「能显示的都显示，除她的隐私空间」──
      Column({ space: 8 }) {
        Text('📊 家里的事（只读）')
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.dk(C_TEXT))
        Row({ space: 8 }) {
          Text('家的体检')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_WHITE))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(R_PILL)
            .backgroundColor(this.dk(C_ACCENT))
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.openHealth();
            })
          Text('夜里')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_WHITE))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(R_PILL)
            .backgroundColor(this.dk(C_ACCENT))
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.openNight();
            })
          Text('随手记')
            .fontSize(FS_SUB)
            .fontColor(this.dk(C_WHITE))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(R_PILL)
            .backgroundColor(this.dk(C_ACCENT))
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.openNotes();
            })
          Blank()
        }
        .width('100%')
        Text('只读：家的账与机制（健康 / 影子读数 / 机制台账 / 当日花费 / 睡眠整理 / 小本本）。'
          + '她的原文——走神那句、攒着的话、牵线原文、忍住档、私档——不在这三页。')
          .fontSize(FS_AUX)
          .fontColor(this.dk(C_TEXT_5))
          .width('100%')
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

  // 节流器：每天首次进入（一天一次）+ 发送前（30 分钟一次）；force=true 绕过节流（保存课表用）。
  // P-b（10-01）：课表空**也报**（items: []）——"诚实缺席"不等于"不上报"：删了课表，必须让
  //   server 收到「今天没日程」它才会清旧账；收不到"空"，它会一直记着老样子
  //   （今天「数电」事故的根：他删了课表，她照旧念着）。失败全静默，不挡聊天。
  private async maybeReportSchedule(fromEntry: boolean, force: boolean = false): Promise<void> {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      const today = this.todayDateStr();
      const lastDay = (prefs.getSync('calendar_last_day', '') as string);
      const lastTs = (prefs.getSync('calendar_last_ts', 0) as number);
      if (!force) {
        if (fromEntry && lastDay === today) {
          return;   // 今天首次进入已经报过了
        }
        if (Date.now() - lastTs < 30 * 60 * 1000) {
          return;   // 距上次上报不到 30 分钟，不重查
        }
      }
      const ttRaw = (prefs.getSync('timetable_text', '') as string);
      let items: ScheduleItem[] = [];
      if (ttRaw.trim().length !== 0) {
        items = pickTimetableToday(parseTimetable(ttRaw), new Date().getDay());
      }
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
  private openKbEditor(): void {   // 9-30 拆分：解析与编辑整套搬进 view/KbEditPage，这里只开门
    this.kbEditOpen = true;
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
    // P-b（10-01）：课表一改，**立刻**把"今天到底有没有课"如实报一次——空也报、绕过节流。
    //   删课表＝报空 → server 当场清旧账（治今天「数电」那事）。失败静默，不挡保存回执。
    this.maybeReportSchedule(false, true).then(() => {}).catch(() => {});
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
          CheckinPage({
            checkedToday: this.checkedToday, checkinBusy: this.checkinBusy,
            checkinItems: this.checkinItems, monthItems: this.monthItems,
            checkinMsg: this.checkinMsg, checkinDetailId: $checkinDetailId,
            onEnter: () => { this.fetchCheckinData(); this.fetchMonthCheckins(); },
            onCheckin: (it: CheckinItem) => { this.doCheckin(it); },
            onArchive: (it: CheckinItem) => { this.confirmArchive(it); }
          })
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


  private detailWeeks(): number[][] {
    const total = detailMonthDays();
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
        this.checkinMsg = `已打卡：${item.name} ${nowTime()}`;
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
                  Text(`${toolCn(t.name)} ${toolSummary(t.name, t.args)}`.trim())
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



  // ── FE-03 要求2：动作工具的内容摘要——args 是 JSON 串，解析出人话；解析不动就空着只显示友好名 ──

  private appendMsg(who: string, text: string, imageUrl: string, time?: string, tools?: ToolUseInfo[],
                    hasThinking?: boolean, msgId?: number, fileName?: string): string {
    const item: ChatItem = {
      key: `k${this.keySeq++}`,
      who: who,
      text: text,
      imageUrl: imageUrl,
      time: time ?? nowTime(),
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
        if (d.loc && typeof d.loc.lat === 'number' && typeof d.loc.lon === 'number') {
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
    // 10-02 修：断网时这几格原样留着旧值 → 面板会显示"假在岗"（server 跑了多久／耳朵✓／信箱N封）
    this.stServer = '—';
    this.stGarden = '—';
    this.stFav = '—';
    this.stLetter = '—';
    this.stLetters = 0;
    this.stBridgeUp = false;
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
                  Text(`${p.time} · ${moodNameOf(p.type) || '旧记分'} ×${p.score} · ${p.source}`)
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

  private moodColorOf(name: string): string {
    const n = moodNameOf(name);   // 先并类（旧记录不炸）再取色
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

  // 十字星（RIVER-3）：他的笔。四芒 sparkle——两条纺锤交叉，凹腰收光

  // 五角星（RIVER-3）：她的笔。外半径 r，内半径 0.45r，正五角

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
      grad.addColorStop(0, hexToRgba(color, 0));
      grad.addColorStop(0.5, hexToRgba(color, aTop));
      grad.addColorStop(1, hexToRgba(color, 0));
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
        glow.addColorStop(0, hexToRgba(color, glowA));
        glow.addColorStop(1, hexToRgba(color, 0));
        ctx.fillStyle = glow;
        ctx.fillRect(x - glowR, y - glowR, glowR * 2, glowR * 2);
        // 星形：十字星=他/旧分，五角星=她；今日主色淡一档像河的底调
        const isHer = source === '姐姐';
        const alpha = source === '今日主色' ? 0.45 : (mtype ? 0.95 : 0.55);
        if (isHer) {
          drawStar5(ctx, x, y, dotR, color, alpha);
        } else {
          drawSpark4(ctx, x, y, dotR, color, alpha);
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
        // 9-29 修：同一本再打开 → 跳回上次那段；换书 → 从头发。
        // 等一帧让 List 建好再跳（内容刚到，立即 scrollToIndex 会落空）。
        if (this.readerBookId === bk.id && this.readerFirstIdx > 0) {
          const jump: number = this.readerFirstIdx;
          setTimeout(() => { this.readerScroller.scrollToIndex(jump); }, 80);
        } else {
          this.readerFirstIdx = 0;
        }
        this.readerBookId = bk.id;
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
          text: text, time: nowTime().substring(0, 5), para: this.readSelPara
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

  // ══ 9-29 §12 app 显示面（家主令「能显示的都显示，除她的隐私空间」）═══════════════
  // 三页共用 pages/InfoPage 的只读骨架；**取数与文案整形都在这边**（它手里有门牌与钥匙）。
  // 隐私复核（服务端已保证，展示层再守一道）：
  //   · 影子读数只出**数**与**条数**——走神那句、攒着的话、忍住档原文一律不取不用；
  //   · 睡眠整理的牵线**只报条数**（原文归她）；台账**私档段**（密钥/单价）服务端已剔。
  private openHealth(): void {
    this.healthOpen = true;
    this.fetchHealth();
  }

  private async fetchHealth(): Promise<void> {
    if (this.healthBusy) {
      return;
    }
    this.healthBusy = true;
    this.healthMsg = '';
    const groups: InfoGroup[] = [];
    // ① 观测层 /api/health（9-28 柔性批；health_api 关着时 404，不影响下面两格）
    const req = http.createHttp();
    try {
      const res = await req.request(HEALTH_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        this.pushHealthGroups(groups, JSON.parse(res.result as string) as HealthResp);
      } else if (res.responseCode === 404) {
        this.healthMsg = '体检口没开：server 的 health_api 关着。下面照旧给影子与台账。';
      } else {
        this.healthMsg = `体检没数上来（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.healthMsg = '体检口没推开：' + errMsg(err as Object);
    } finally {
      req.destroy();
    }
    // ② 影子读数 + ③ 台账公开段（各自单独取，谁挂谁诚实说，不互相连坐）
    // 10-02 修：这两段原先不在 try/finally 内——任一处抛出会永久卡「取数中」（拒绝再刷新）
    try {
      groups.push({ title: '影子读数（今天）', lines: await this.fetchShadowLines() });
      const mech: InfoGroup[] = await this.fetchMechGroups();
      for (let i = 0; i < mech.length; i++) {
        groups.push(mech[i]);
      }
      this.healthGroups = groups;
    } finally {
      this.healthBusy = false;
    }
  }

  // 观测层 → 人话：开机 / 软失败 / 机制面（门·桥·嵌入·备份）/ 当日账
  private pushHealthGroups(groups: InfoGroup[], h: HealthResp): void {
    const up: number | null | undefined = h.server_up_min;
    groups.push({ title: '这个家（此刻）', lines: [`server 连续在岗 ${up === null || up === undefined ? '—' : `${up}`} 分钟`] });
    const sf: HealthSoftFail | null | undefined = h.soft_fail;
    if (sf === null || sf === undefined) {
      groups.push({ title: '软失败（近 7 天）', lines: ['（这一格没数到）'] });
    } else {
      const lines: string[] = [`共 ${sf.total ?? 0} 次降级（不伪装正常，坏在哪记在哪）`];
      const top: HealthSoftTop[] = sf.top3 ?? [];
      for (let i = 0; i < top.length; i++) {
        lines.push(`　${top[i].where ?? '?'}：${top[i].n ?? 0} 次`);
      }
      groups.push({ title: '软失败（近 7 天）', lines: lines });
    }
    const mf: HealthMechFace | null | undefined = h.mechanisms;
    if (mf === null || mf === undefined) {
      groups.push({ title: '机制面（在不在岗）', lines: ['（这一格没数到）'] });
    } else {
      const lines: string[] = [];
      lines.push(`反向隧道：${mf.tunnel === true ? '在跑' : '没在跑'}${mf.tunnel_up === true ? '（门真连着）' : mf.tunnel_up === false ? '（心跳新鲜但门没通）' : ''}`);
      lines.push(`Garden 桥：${mf.garden_bridge === true ? '在岗' : '不在岗'}`);
      const em: HealthEmbed | null | undefined = mf.embedding;
      lines.push(em === null || em === undefined ? '嵌入层：诚实缺席' : `嵌入层：${em.model ?? '?'} @ ${em.endpoint ?? '?'}`);
      const bk: HealthBackup | null | undefined = mf.last_backup;
      if (bk === null || bk === undefined) {
        lines.push('上次自动备份：没查到');
      } else {
        lines.push(`上次自动备份：${bk.at ?? '?'}（${bk.age_h ?? '—'} 小时前）`);
      }
      groups.push({ title: '机制面（在不在岗）', lines: lines });
    }
    const lg: HealthLedger | null | undefined = h.ledger_today;
    if (lg === null || lg === undefined) {
      groups.push({ title: '今天的账', lines: ['（这一格没数到）'] });
    } else {
      const lines: string[] = [];
      const hit: number | null | undefined = lg.cache_hit;
      lines.push(`调用 ${lg.calls ?? 0} 次 · 进 ${wanTxt(lg.in_tokens)} / 出 ${wanTxt(lg.out_tokens)} tokens`
        + `（缓存命中 ${hit === null || hit === undefined ? '—' : `${Math.round(hit * 100)}%`}）`);
      const cost: number | null | undefined = lg.cost_est;
      lines.push(cost === null || cost === undefined
        ? '估价：没配单价（私档 _price_* 空着）——只报 tokens，不造假钱'
        : `估价：约 ¥${cost.toFixed(2)}（单价取自私档，不在这儿回显）`);
      const sc: HealthLedgerScene[] = lg.scenes ?? [];
      for (let i = 0; i < sc.length; i++) {
        lines.push(`　${sc[i].scene ?? '?'}：${sc[i].calls ?? 0} 次 · 进 ${wanTxt(sc[i].in)} / 出 ${wanTxt(sc[i].out)}`);
      }
      groups.push({ title: '今天的账', lines: lines });
    }
  }

  // 影子读数 /api/shadows → 人话（**只出数与条数**）
  private async fetchShadowLines(): Promise<string[]> {
    const lines: string[] = [];
    const req = http.createHttp();
    try {
      const res = await req.request(SHADOWS_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode !== 200) {
        return [`（没数到：HTTP ${res.responseCode}）`];
      }
      const d = JSON.parse(res.result as string) as ShadowsResp;
      const de: ShDesire | null | undefined = d.desire_v2;
      if (de === null || de === undefined) {
        lines.push('欲望：这一格没数到');
      } else {
        lines.push(`欲望：D=${de.D === null || de.D === undefined ? '—' : `${de.D}`}`
          + ` · ${de.blocked_by === null || de.blocked_by === undefined ? '没被挡' : `被${de.blocked_by}挡`}`
          + ` · 今日 ${de.ticks_today ?? 0} 拍 / 掷中 ${de.fired_today ?? 0}`);
      }
      const sg: ShSingle | null | undefined = d.single;
      if (sg === null || sg === undefined) {
        lines.push('单触发：这一格没数到');
      } else {
        lines.push(`单触发：档 ${sg.tier ?? '—'} · p≈${sg.p ?? '—'}`
          + ` · ${sg.blocked_by === null || sg.blocked_by === undefined ? '没被挡' : `被「${sg.blocked_by}」挡`}`
          + ` · 今日 ${sg.ticks_today ?? 0} 拍 / 掷中 ${sg.hits_today ?? 0}`);
      }
      const rc: ShRecall | null | undefined = d.recall;
      lines.push(rc === null || rc === undefined
        ? '走神：这一格没数到'
        : `走神：今日 ${rc.walks_today ?? 0} 次（其中翻卡 ${rc.cards_today ?? 0} 次）——她想起的那句是她的，不在这页`);
      const ht: ShHuatou | null | undefined = d.huatou;
      lines.push(ht === null || ht === undefined
        ? '话头：这一格没数到'
        : `话头：今日攒 ${ht.collected_today ?? 0} / 递到眼前 ${ht.delivered_today ?? 0}`
        + ` / 真说出 ${ht.said_today ?? 0} / 忍住 ${ht.held_today ?? 0} 条（原话归她）`);
      const gt: ShGate | null | undefined = d.gate;
      if (gt === null || gt === undefined) {
        lines.push('检索门槛：这一格没数到');
      } else {
        const er: number | null | undefined = gt.empty_rate;
        lines.push(`检索门槛（近 24h）：${gt.samples_24h ?? 0} 拍 · 递 ${gt.delivered ?? 0} / 留 ${gt.kept ?? 0} / 丢 ${gt.dropped ?? 0}`
          + ` · 空手率 ${er === null || er === undefined ? '—' : `${Math.round(er * 100)}%`}`);
      }
    } catch (err) {
      return ['（影子读数没取到：' + errMsg(err as Object) + '）'];
    } finally {
      req.destroy();
    }
    return lines;
  }

  // 机制台账公开段 /api/mech → 分组（服务端已剔私档段；这里把表格行压成「名 现值」一行行）
  private async fetchMechGroups(): Promise<InfoGroup[]> {
    const out: InfoGroup[] = [];
    const req = http.createHttp();
    try {
      const res = await req.request(MECH_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode !== 200) {
        out.push({ title: '机制台账·公开段', lines: [`（没数到：HTTP ${res.responseCode}）`] });
        return out;
      }
      const d = JSON.parse(res.result as string) as MechResp;
      const secs: MechSection[] = d.sections ?? [];
      if (secs.length === 0) {
        out.push({ title: '机制台账·公开段', lines: ['（台账还没生成——跑 tools/make_mechanism_ledger.py）'] });
        return out;
      }
      for (let i = 0; i < secs.length; i++) {
        out.push({ title: secs[i].title ?? '台账', lines: mechTextToLines(secs[i].text ?? '') });
      }
    } catch (err) {
      out.push({ title: '机制台账·公开段', lines: ['（没取到：' + errMsg(err as Object) + '）'] });
    } finally {
      req.destroy();
    }
    return out;
  }

  // markdown 表格行 → 「`名` = 现值」人话行；非表格行原样（缩进两格）

  // 🌙 夜里：睡眠整理（归拢/回望给条目；**牵线只给条数**）
  private openNight(): void {
    this.nightOpen = true;
    this.fetchDream();
  }

  private async fetchDream(): Promise<void> {
    if (this.nightBusy) {
      return;
    }
    this.nightBusy = true;
    this.nightMsg = '';
    const groups: InfoGroup[] = [];
    const req = http.createHttp();
    try {
      const res = await req.request(DREAM_URL + '?nights=7', {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as DreamResp;
        const nights: DreamNight[] = d.nights ?? [];
        if (nights.length === 0) {
          this.nightMsg = '还没有睡过的记录——她夜里安静，也是好觉。';
        }
        for (let i = 0; i < nights.length; i++) {
          groups.push(this.nightToGroup(nights[i]));
        }
      } else {
        this.nightMsg = `夜里没取到（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.nightMsg = '夜里的门没推开：' + errMsg(err as Object);
    } finally {
      req.destroy();
    }
    this.nightGroups = groups;
    this.nightBusy = false;
  }

  private nightToGroup(n: DreamNight): InfoGroup {
    const lines: string[] = [];
    const heat: DreamHeat | null | undefined = n.heat;
    if (heat === null || heat === undefined) {
      lines.push('热度：这一格没数到');
    } else {
      lines.push(`热度分层：热 ${heat.hot ?? 0} / 温 ${heat.warm ?? 0} / 冷 ${heat.cold ?? 0}（若按热度分三档）`);
    }
    const mg: DreamMerge[] = n.merge ?? [];
    if (mg.length === 0) {
      lines.push('归拢：没找到要归拢的（干净）');
    } else {
      for (let i = 0; i < mg.length; i++) {
        const r: number | undefined = mg[i].ratio;
        lines.push(`归拢：${mg[i].a_ref ?? '?'}「${mg[i].a ?? ''}」× ${mg[i].b_ref ?? '?'}「${mg[i].b ?? ''}」`
          + `（相似 ${r === undefined ? '—' : r.toFixed(2)}）`);
      }
    }
    lines.push(`牵线：${n.link_n ?? 0} 条提名（牵的是她攒着的话——原文归她，不在这页）`);
    const rp: DreamReplay[] = n.replay ?? [];
    if (rp.length === 0) {
      lines.push('回望：没有要回望的旧事（干净）');
    } else {
      for (let i = 0; i < rp.length; i++) {
        lines.push(`回望：第${rp[i].day_no ?? '?'}天「${rp[i].title ?? ''}」（心情：${rp[i].mood ?? '—'}）`);
      }
    }
    return { title: `${n.date ?? '那一夜'} 那一夜`, lines: lines };
  }

  // 📝 随手记：她的小本本（近 30 天，旧到新）
  private openNotes(): void {
    this.notesOpen = true;
    this.fetchNotes();
  }

  private async fetchNotes(): Promise<void> {
    if (this.notesBusy) {
      return;
    }
    this.notesBusy = true;
    this.notesMsg = '';
    const req = http.createHttp();
    try {
      const res = await req.request(NOTES_URL, {
        method: http.RequestMethod.GET,
        header: { 'Authorization': DOOR_AUTH },
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS
      });
      if (res.responseCode === 200) {
        const d = JSON.parse(res.result as string) as NotesResp;
        const list: NoteItem[] = d.notes ?? [];
        const lines: string[] = [];
        for (let i = 0; i < list.length; i++) {
          lines.push(`${list[i].time ?? ''}　${list[i].text ?? ''}`);
        }
        if (lines.length === 0) {
          this.notesMsg = '最近 30 天她没有随手记。';
        }
        this.notesGroups = [{ title: `最近 30 天（${lines.length} 条）`, lines: lines }];
      } else {
        this.notesMsg = `随手记没取到（HTTP ${res.responseCode}）`;
      }
    } catch (err) {
      this.notesMsg = '随手记没取到：' + errMsg(err as Object);
    } finally {
      req.destroy();
    }
    this.notesBusy = false;
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
    await sleepMs(3000);
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
          && histTextHit(prev.text, sentText)
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
      // 10-02：解析失败别静默——留一行日志（原空 catch 让人以为"没待发"）
      hilog.error(0x0000, HILOG_TAG, 'outbox 解析失败（待发队列可能已损坏）: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  private saveOutbox(items: OutboxItem[]): void {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      // 10-02 修：同 chat_cache——带图待发的 base64 会撑爆单个 preferences 值（8192B）→ 剔图
      let json = JSON.stringify(items);
      json = json.replace(/"imageUrl":"data:[^"]*"/g, '"imageUrl":""');
      prefs.putSync('outbox', json);
      prefs.flushSync();
    } catch (err) {
      // 持久化失败不阻断主链路
      hilog.warn(0x0000, HILOG_TAG, 'outbox 落盘失败: %{public}s', JSON.stringify(err));
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
          && histTextHit(m.text, item.message)
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

  // ── 姐姐思考中（9-12 时间线版；9-27 v5 改 live 卡）：起计时器 ＋ 挂一张 live 思考卡兜底——
  // 第一个事件没到之前显示「叫姐姐中…」，thinking 一来就变计时逐字；封口与归档由 sealThink 负责 ──
  private beginThinking(): void {
    this.thinkingSec = 0;
    this.thinkPeek = false;   // 💭 默认折叠：新一轮重新折叠
    // 9-27 v5：占位卡不再 append 进 chatData（那样它永远不重画）——改挂 live 思考卡：
    // 读 this 的 @State，第一个事件没到之前显示「💭 叫姐姐中…」，thinking 一到就变计时＋逐字。
    this.liveThinkOn = true;
    this.liveThinkStarted = false;
    this.liveThinkText = '';
    this.liveReplyOn = false;
    this.liveReplyText = '';
    this.liveReplyTime = '';
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
    // 9-27 v5：live 思考卡不进 chatData——收工只需摘状态（未封口的半截卡自然消失，
    // 已封口的早已 append 归档，天然不受影响）。旧的按 key 清 chatData 那套随之退休。
    this.liveThinkOn = false;
    this.liveThinkStarted = false;
    this.liveThinkText = '';
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
    if (this.outboxFetchBusy) {
      return;   // 10-02 修：boot 与 60s 轮询重叠时，同一条信可能被取两遍（重复气泡＋重复通知）
    }
    this.outboxFetchBusy = true;
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
      this.outboxFetchBusy = false;
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
  // 10-02 修：preferences 单值上限 8192B——带图消息的 imageUrl 是 base64 dataURL（单张数百 KB），
  //   聊得久整份也超；原 `JSON.stringify(items)` 直接超限、putSync 抛错被空 catch 吞掉
  //   → 缓存静默不再更新（断网底稿丢）。改成：从最近往前攒、剔图、攒到 ~7500B 为止。
  private packCacheJson(items: ChatItem[]): string {
    const parts: string[] = [];
    let total = 0;
    for (let i = items.length - 1; i >= 0; i--) {
      let one = JSON.stringify(items[i]);
      one = one.replace(/"imageUrl":"data:[^"]*"/g, '"imageUrl":""');
      if (total + one.length + 1 > 7500) {
        break;
      }
      parts.unshift(one);
      total += one.length + 1;
    }
    return '[' + parts.join(',') + ']';
  }

  private saveChatCache(items: ChatItem[]): void {
    try {
      const prefs = preferences.getPreferencesSync(getContext(this), { name: 'zanjia' });
      prefs.putSync('chat_cache', this.packCacheJson(items));
      prefs.flushSync();
    } catch (err) {
      // 缓存失败不影响主链路（但不静默：留一行日志）
      hilog.warn(0x0000, HILOG_TAG, 'chat_cache 落盘失败: %{public}s', JSON.stringify(err));
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
          && histTextHit(items[hi].text, cur.text)) {
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
          || cur.text === '' || !histTextHit(m.text, cur.text)) {
          continue;
        }
        const key = cur.key;
        this.chatData.removeWhere((x: ChatItem) => x.key === key);
        break;   // 一条副本只认领一条活口（同文本第二条活口留给下一条副本）
      }
    }
  }

  // 历史消息 → 气泡件（9-23 V-1：loadHistory 与上翻老窗共用同一套字段映射，别再各写一份）
  // APP-01（10-01）：一条历史可能带着**全过程**（turns）——展开成
  // 「思考卡 / 工具卡 / 中间话 / 最终气泡」；老消息 turns 为空 → 逐字回到原来的单气泡。
  private histMsgToItems(msg: HistoryMsg): ChatItem[] {
    const out: ChatItem[] = [];
    const turns: TurnInfo[] | null | undefined = msg.turns;
    if (turns && turns.length > 0 && msg.who === '姐姐') {
      for (let ti = 0; ti < turns.length; ti++) {
        const t: TurnInfo = turns[ti];
        const th: string = t.think ? t.think : '';
        const sy: string = t.say ? t.say : '';
        const isFinal: boolean = t.final === true;
        // 思考卡：全文进 thinkingCache（key 带 chat_id + 轮号），点一下就能看——不用再走网络
        if (th.length > 0 && !isFinal) {
          const tk: string = `think-h${msg.id}-${t.r}`;
          this.thinkingCache.set(tk, th);
          out.push({ key: tk, who: '思考', text: th, imageUrl: '',
                     time: `思考 · ${msg.time}`, thinkDone: true, msgId: msg.id });
        }
        // 工具卡：调了哪只证、回了什么
        const tls: TurnTool[] | undefined = t.tools;
        if (tls) {
          for (let i = 0; i < tls.length; i++) {
            const tl: TurnTool = tls[i];
            const br: string = tl.brief ? tl.brief : '';
            out.push({ key: `tool-h${msg.id}-${t.r}-${i}`, who: '工具',
                       text: `调用工具 ${tl.name}` + (br.length > 0 ? `：${br}` : ''),
                       imageUrl: '', time: msg.time, msgId: msg.id });
          }
        }
        // 中间那段回复（不是收尾那条）——单独一个气泡，别让它丢
        if (sy.length > 0 && !isFinal) {
          out.push({ key: `say-h${msg.id}-${t.r}`, who: '姐姐', text: sy, imageUrl: '',
                     time: msg.time, msgId: msg.id });
        }
      }
    }
    out.push(this.histMsgToItem(msg));   // 收尾那条（正文气泡）照旧
    return out;
  }

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
          for (const _hi of this.histMsgToItems(msg)) {
            items.push(_hi);
          }
        }
        // 9-23 V-1 全量浏览：记分页状态——服务端带 has_more 才开翻页闸（旧 server 没有=不开，防重拉打转）
        this.histPaging = data.has_more !== undefined && data.has_more !== null;
        this.histHasMore = this.histPaging && data.has_more === true;
        this.histOldestThrough = this.todayDateStr();   // 无参=最近三天：窗口 [今-2..今]，两头游标都从今天起
        this.histNewestThrough = this.todayDateStr();
        // 9-18 App深搜修（DS-02）：不再整卷 setAll——「历史 + 未入库活口」合并落地（mergeWithLive），
        // 否则这轮刚发出去、还没入库的乐观气泡会被换掉。9-27 v5 起她的流式正文/思考卡已移出 chatData
        // （不再受整卷替换影响），但「我」那条乐观气泡仍在册，仍要护。活口判定见 keepLiveBubble 头注。
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
          for (const _hi of this.histMsgToItems(msg)) {
            older.push(_hi);
          }
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
          for (const _hi of this.histMsgToItems(msg)) {
            newer.push(_hi);
          }
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
          for (const _hi of this.histMsgToItems(msg)) {
            items.push(_hi);
          }
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
      let hardTimer: number = -1;      // 9-27 v4：总时限硬闸（防「数据一直来但事件出不来」把看门狗饿死）
      let lastWdogLog: number = 0;     // 9-27 v4：看门狗静默播报节流
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
          const silentMs = Date.now() - lastDataAt;
          if (silentMs > 120000) {
            settle(-1, new Error('流式静默断尾（120s 无事件）'));
          } else if (silentMs > 30000 && Date.now() - lastWdogLog > 30000) {
            lastWdogLog = Date.now();   // 9-27 v4 诊断：静默 >30s 才播报，且 30s 一次
          }
        }, 5000);
        hardTimer = setTimeout(() => {
          // 9-27 v4：总时限硬闸——240s 还没收尾就强制结算（防异常风暴把 lastDataAt 喂饱、看门狗饿死）。
          settle(-1, new Error('流式总时限到（240s 未收尾）'));
        }, 240000);
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
        // 9-27 v5：live 卡状态每一轮清零（beginThinking 已清过，这里再钉一次，防重入残留）
        this.liveReplyOn = false;
        this.liveReplyText = '';
        this.liveReplyTime = '';
        let replyText = '';
        let thinkSealedThisSend = false;   // FE-FIX-01：本轮开过思考卡并已封口（done 兜底卡的唯一判据）
        const allThinkParts: string[] = [];   // 各轮思考全文（done 后拼挂 💭 缓存）
        const sealThink = (): void => {
          if (!curThinkKey) {
            return;
          }
          const sec = (Date.now() - thinkT0) / 1000;
          const key = `think${this.keySeq++}`;   // 9-27 v5：新 key——归档=append（新增才可见）
          const sealed: ChatItem = {
            key: key, who: '思考', text: thinkFull, imageUrl: '',
            time: `思考了 ${sec.toFixed(1)}s`, thinkDone: true,
          };
          this.chatData.append(sealed);
          this.scrollToEnd();
          thinkSealedThisSend = true;   // FE-FIX-01：封口即记账——done 时不再挨兜底补卡
          if (thinkFull) {
            this.thinkingCache.set(key, thinkFull);   // 全文进缓存
            allThinkParts.push(thinkFull);
          }
          // live 卡收工（它本来就不在 chatData 里，归档完直接摘状态即可）
          this.liveThinkOn = false;
          this.liveThinkStarted = false;
          this.liveThinkText = '';
          curThinkKey = '';
          thinkFull = '';
        };
        const refreshThink = (): void => {
          if (curThinkKey) {
            // 9-27 v5：改 @State（不是改 chatData 里那条）→ 每帧重画
            this.liveThinkStarted = true;
            this.liveThinkText = thinkFull;
          }
        };
        const onEvent = (obj: StreamEvent): void => {
          if (obj.type === 'round') {
            // 轮界：上一轮的思考卡与正文卡全部封口，新一轮另起（Kimi 步骤卡的缝接）
            if ((obj.round ?? 0) > 0) {
              sealThink();
              // 9-27 v5：上一轮正文也得归档（append=可见）——否则换轮时它会凭空消失
              if (this.liveReplyOn) {
                this.appendMsg('姐姐', this.liveReplyText, '', this.liveReplyTime);
                this.liveReplyOn = false;
                this.liveReplyText = '';
                this.liveReplyTime = '';
              }
              replyText = '';
            }
          } else if (obj.type === 'thinking') {
            if (!curThinkKey) {
              // 9-27 v5：开一张 live 思考卡（不进 chatData）；占位显示由 liveThinkStarted 决定
              curThinkKey = '@live-think';
              this.liveThinkOn = true;
              this.liveThinkStarted = true;
              this.liveThinkText = '';
              thinkT0 = Date.now();
              thinkFull = '';
            }
            thinkFull += obj.delta ?? '';
            refreshThink();
          } else if (obj.type === 'tool') {
            // 每只图书证一动立刻上卡：🔧 调用工具 XX（截图同款）
            sealThink();
            const tn = obj.name ?? '';
            const summary = toolSummary(tn, obj.args ?? '').trim();
            this.appendMsg('工具', `调用工具 ${toolCn(tn)}${summary ? ' · ' + summary : ''}`, '');
          } else if (obj.type === 'reply') {
            sealThink();
            replyText += obj.delta ?? '';
            if (!this.liveReplyOn) {
              // 9-27 v5：正文走 live 气泡（@State 驱动 → 逐字长）
              this.liveReplyOn = true;
              this.liveReplyTime = `… ${nowTime()}`;
              this.liveReplyText = replyText;
              this.scrollToEnd();
            } else {
              this.liveReplyText = replyText;
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
            // 9-27 夜修（附录 A·潜伏）：error 事件单独走失败结算（settle 幂等）——
            // 别让逐事件 try 把它吞成一行日志、干等看门狗。
            settle(-1, new Error(obj.text ?? '流式中断'));
          }
        };
        req.on('dataReceive', (data: ArrayBuffer) => {
          lastDataAt = Date.now();   // 9-26：有数据就喂看门狗（慢流不误杀，断流才收网）
          // 9-27 v4 加固：逐帧/逐事件 try 隔离——任一帧或任一事件的异常只跳过它自己，
          // 绝不中断回调、绝不让 sseRest 停摆（旧版异常会级联：同一坏帧反复抛、done 永远到不了）。
          try {
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
                try {
                  const block = util.TextDecoder.create('utf-8').decodeToString(merged.slice(start, i + 1));
                  for (const line of block.split('\n')) {
                    if (line.startsWith('data: ')) {
                      sawSse = true;   // 9-26：确认这是 SSE 流（dataEnd 结算只对 SSE 生效）
                      try {
                        onEvent(JSON.parse(line.substring(6)) as StreamEvent);
                      } catch (eEv) {
                        console.error(`[ZJ-SSE] 事件处理异常（跳过该帧）：${eEv}`);   // 9-27 v4 诊断
                      }
                    }
                  }
                } catch (eFr) {
                  console.error(`[ZJ-SSE] 帧解析异常（跳过该帧）：${eFr}`);   // 9-27 v4 诊断
                }
                start = i + 2;   // 无论成败边界必推进：坏帧只丢它自己
              }
            }
            sseRest = merged.slice(start);
          } catch (eCb) {
            console.error(`[ZJ-SSE] dataReceive 回调异常（保底兜住，不逸出）：${eCb}`);   // 9-27 v4 诊断
          }
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
                this.appendMsg('姐姐', dj.reply ?? '（姐姐刚才回过这句了）', '', nowTime(),
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
          console.info(`[ZJ-SSE] ${replyText.length}字·兜底${(d.reply ?? '').length}字`);   // 9-27：一条一行，排障用
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
          if (this.liveReplyOn) {
            // 9-27 v5：正文卡归档——**append 进 chatData**（新增=可见），不再是"原地改"。
            // 同时补上 bug B 的兜底：done 若带全文且比本地累计更长（中途丢帧），以 done 为准。
            const finalText = (d.reply !== undefined && d.reply !== null && d.reply.length > replyText.length)
              ? d.reply : replyText;
            const allThink = allThinkParts.join('\n\n');
            const finalKey = `k${this.keySeq++}`;
            const finalMsg: ChatItem = {
              key: finalKey, who: '姐姐', text: finalText, imageUrl: '',
              time: `思考 ${thinkSec.toFixed(1)}s · ${nowTime()}`,
              tools: [], msgId: d.chat_id, hasThinking: allThink.length > 0,
            };
            if (allThink) {
              this.thinkingCache.set(finalKey, allThink);   // 思考原文（各轮拼接）进缓存
            }
            if (!thinkSealedThisSend) {
              // 兜底思考卡要落在正文之前
              this.chatData.append(this.makeFallbackThink(thinkSec));
            }
            this.chatData.append(finalMsg);
            this.scrollToEnd();
            this.liveReplyOn = false;
            this.liveReplyText = '';
            this.liveReplyTime = '';
          } else {
            if (!thinkSealedThisSend) {
              this.chatData.append(this.makeFallbackThink(thinkSec));
            }
            // 9-27 夜修（附录 A·done 自愈补全）：整轮全丢帧时也认 done 带的全文——
            // 与上面 live 分支同款「有内容用内容」，真空白才落占位（不再无视 d.reply）。
            const orphanText = (d.reply !== undefined && d.reply !== null && d.reply.length > 0)
              ? d.reply : '（姐姐回了个空白）';
            this.appendMsg('姐姐', orphanText, '', undefined, d.tools ?? []);
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
        clearTimeout(hardTimer);       // 9-27 v4：总时限硬闸收工
        req.off('dataReceive');
        req.off('dataEnd');
        req.destroy();
      }
    } catch (err) {
      console.error(`[ZJ-SSE] 进入对账：${errMsg(err)}`);   // 9-27 v4 诊断：settle 异常/收敛都到这
      // 9-18 修复批八（APP2-02）：先收思考卡再对账——对账要等网络，别让未封口的卡多挂几秒
      this.endThinking();
      // FE3-04（9-23）/ 9-27 v5：流没收 done 时正文可能已流出半截——live 卡不进 chatData，
      // 收工即消失（不再"半截+完整"两条并排；对账拿到全文再 append）
      this.liveReplyOn = false;
      this.liveReplyText = '';
      this.liveReplyTime = '';
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
