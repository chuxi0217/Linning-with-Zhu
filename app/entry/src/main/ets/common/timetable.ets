// ── 课表 CAL-02 纯解析器（9-30 第 1 批拆分）────────────────────────────
// 从 pages/Index.ets 原样搬出：节次时间正典 + 纯解析/格式化（无副作用、不碰 this）。
// 【注意】#region/#endregion CAL-02 沙盘转译区 标记随本文件整体搬走（成对、未被拆散），
// 沙盘 _t_cal02 的机械转译仍按这对标记找；改写法请保持简式（不用箭头函数、不碰 this 与外部状态）。
// 行为逐字未改（搬家而已）。
import { ScheduleItem } from '../model/apiTypes';

// ─────── CAL-02（9-13）课表本地化：节次时间正典 + 纯解析 ───────
// #region CAL-02 沙盘转译区（纯函数、无副作用；_t_cal02 按此标记机械转译跑断言）
// 改写法请保持简式：不用箭头函数、对象字面量单行、不碰 this 与外部状态

// 节次时间正典（1=08:00-08:45 … 13=21:20-22:05）：与上报共用一份，硬编码就在这里。
// 9-18 家主定口径：1-8 不动；新插 9=18:10-18:50、10=18:50-19:30（课外活动那档）；
// 原 9-11 顺延成 11-13（19:40-20:25 / 20:30-21:15 / 21:20-22:05）——全校表共 13 节。
export const PERIOD_SLOTS: string[] = [
  '08:00-08:45', '08:55-09:40', '10:00-10:45', '10:55-11:40',
  '14:30-15:15', '15:20-16:05', '16:25-17:10', '17:15-18:00',
  '18:10-18:50', '18:50-19:30', '19:40-20:25', '20:30-21:15', '21:20-22:05',
];

// 周名表：下标跟 Date.getDay() 同规（周日=0 … 周六=6）
export const WEEK_CN: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

export interface TtSeg {
  ok: boolean;     // 这一段看懂没有
  from: number;    // 起节（1~13；直写时间的段为 0）
  to: number;      // 止节（含；直写时间的段为 0）
  title: string;   // 课名 + 可选 @地点（原文保留）
  time?: string;   // 9-18 直写时间档：规整成 HH:MM-HH:MM（有它就不走节次正典）
}

export interface TtEntry {
  dow: number;     // 哪一天（周日=0 … 周六=6）
  from: number;
  to: number;
  title: string;
  time?: string;   // 9-18 直写时间档：原样上报、原样回写
}

export interface TtParse {
  entries: TtEntry[];   // 全周所有课（不分今天）
  good: number;         // 看懂的行数
  bad: string[];        // 没看懂的行（原样逐行列出——不许静默吞）
}

// 一段课次：「1-2节 高数」「1-2 高数」「3节 英语」「3 英语」都认；节次只认 1~13。
// 9-18 新档：段首数字后面直接跟冒号的，按「直写时间」走（18:10-19:30 课外活动）——不再当节次；
// 冒号半角「:」全角「：」都算（中文输入法的真实输入）。
export function parseTimetableSegment(seg: string): TtSeg {
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
export function pad2(n: number): string {
  if (n < 10) {
    return '0' + n;
  }
  return '' + n;
}

// 冒号容错：半角「:」和全角「：」都算——中文输入法打出来是后者（只在本解析里判，不动课名文本里的标点）
export function isColon(c: string): boolean {
  return c === ':' || c === '：';
}

// 9-18 直写时间一段：「18:10-19:30 课外活动」「9:05~10:05 早读」都认，规整成 HH:MM-HH:MM（补零）。
// 进来时第一段小时已经吃在 h0~i0、i0 正指着冒号；分隔符 - 或 ~ 都算。
// 半截时间（18:10-、9:05、25:00-26:00、起≥止）一律 ok=false——进「没看懂」名单，不许静默吞。
export function parseTimeSegment(seg: string, h0: number, i0: number): TtSeg {
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
export function parseTimetable(raw: string): TtParse {
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
export function pickTimetableToday(parsed: TtParse, dow: number): ScheduleItem[] {
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

export function timetableCmpTime(x: ScheduleItem, y: ScheduleItem): number {
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
export function ttEntryCmp(a: TtEntry, b: TtEntry): number {
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
export function serializeTimetable(entries: TtEntry[]): string {
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
export function ttMin(t: string): number {
  return ((t.charCodeAt(0) - 48) * 10 + (t.charCodeAt(1) - 48)) * 60
    + (t.charCodeAt(3) - 48) * 10 + (t.charCodeAt(4) - 48);
}

// 分钟数 → 「HH:MM」（补零借正典区的 pad2）
export function ttHHMM(minute: number): string {
  return pad2(Math.floor(minute / 60)) + ':' + pad2(minute % 60);
}

export const TT_TIME_CAP: number = 23 * 60 + 55;   // 时间控件天花板 23:55：分一次走 5 格，这是最后一格

// 走一步（±5 分钟 / ±1 小时），钳在 00:00~23:55：
// 跨位自动进位（08:55+5=09:00、08:00−5=07:55），顶到边就停住——UI 只产 24 小时制合法值
export function ttStep(t: string, deltaMin: number): string {
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
export function ttClosestPeriod(t1: string, t2: string): number[] {
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
