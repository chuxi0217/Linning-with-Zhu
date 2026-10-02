// ── 文案 / 数字 / 时间整形（9-30 第 3 批拆分·纯函数零依赖）──────────────────
// 从 pages/Index.ets 的 struct 方法原样外提（这些方法原本就不碰 this）：
//   toolCn/toolSummary 工具名与摘要人话 · fmtSize/numTxt/wanTxt 数字
//   nowTime/sleepMs 时间 · histTextHit 历史命中 · traceEndingCn 痕迹收尾
//   moodNameOf 情绪名 · detailMonthDays 打卡月历 · httpErrMsg 服务端错误人话
//   mechTextToLines 家的体检文案整形
// 行为逐字未改（搬家而已）：Index 里不留壳，调用点 this.x( → x( 同名直调。
import { MOOD_TYPES, LEGACY_MOOD_MAP, OkResp } from '../model/apiTypes';

export function toolCn(name: string): string {
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

export function toolSummary(name: string, argsJson: string): string {
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

export function fmtSize(n?: number | null): string {
  if (n === undefined || n === null) {
    return '';
  }
  return n >= 1024 ? `${Math.round(n / 1024)} KB` : `${n} 字节`;
}

export function numTxt(n?: number | null): string {
  return n === undefined || n === null ? '—' : `${n}`;
}

export function wanTxt(n?: number | null): string {
  return n === undefined || n === null ? '—' : `${(n / 10000).toFixed(1)} 万`;
}

export function nowTime(): string {
  const d = new Date();
  const h = d.getHours();
  const m = d.getMinutes();
  return `${h < 10 ? '0' + h : h}:${m < 10 ? '0' + m : m}`;
}

export function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => resolve(), ms);
  });
}

export function histTextHit(stored: string, sent: string): boolean {
  if (stored === sent) {
    return true;
  }
  return sent !== '' && stored.startsWith(sent + ' 〔');
}

export function traceEndingCn(ending: string): string {
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

export function moodNameOf(name: string): string {
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

export function detailMonthDays(): number {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
}

export function httpErrMsg(raw: string, fallback: string): string {
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

export function mechTextToLines(text: string): string[] {
  const out: string[] = [];
  const rows: string[] = text.split('\n');
  for (let i = 0; i < rows.length; i++) {
    const ln: string = rows[i].trim();
    if (ln === '' || ln.startsWith('|---') || ln.startsWith('| ---')) {
      continue;
    }
    if (!ln.startsWith('|')) {
      out.push('　' + ln);
      continue;
    }
    const cells: string[] = ln.split('|');
    const parts: string[] = [];
    for (let k = 0; k < cells.length; k++) {
      const c: string = cells[k].trim();
      if (c !== '') {
        parts.push(c);
      }
    }
    if (parts.length === 0 || parts[0] === '开关名' || parts[0] === '键名') {
      continue;   // 表头跳过
    }
    let line: string = '　' + parts[0];
    if (parts.length >= 3) {
      line += ` ＝ ${parts[2]}`;
    }
    if (parts.length >= 5 && parts[4] !== '—' && parts[4] !== '') {
      line += `　（${parts[4]}）`;
    }
    out.push(line);
  }
  return out;
}
