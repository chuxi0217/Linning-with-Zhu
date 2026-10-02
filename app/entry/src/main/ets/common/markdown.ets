// ── Markdown 轻渲染·解析器（9-30 第 1 批拆分）───────────────────────────
// 从 pages/Index.ets 原样搬出：子集解析（标题/粗斜/行内码/列表/引用/分隔线/代码块）。
// 用场：档案馆开卷 / 周报开卷；聊天、日记、信件、她的原话一律不走这里（一个字不改）。
// 行为逐字未改（搬家而已）。

// ═══════════ 📖 Markdown 轻渲染 · A 段（模块级：解析器）═══════════
// （9-27 夜 图书管理员批）用场：档案馆开卷 / 周报开卷——家里很多文件是 md，
// 开卷按格式渲染；聊天/日记/信件/她的原话一律不走这里（一个字不改）。
// 子集：标题 #~###### · 粗体 **…** · 斜体 *…* · 行内代码 `…` · 无序列表 - * + ·
//       有序列表 1. 1、1) · 引用 > · 分隔线 --- *** ___ · 代码块 ```。
// 表格/嵌套引用暂不渲染（按原文显示）。零第三方依赖。
// 粘贴位置：Index.ets 顶部常量区（建议 const TT_TIME_CAP 那行之后，空一行）。
export interface MdSeg {
  t: string;     // 文本
  b: boolean;    // 粗
  i: boolean;    // 斜
  c: boolean;    // 行内代码
}

export interface MdBlock {
  k: number;      // 0=段落 1=标题 2=列表项 3=引用 4=分隔线 5=代码块
  lv: number;     // 标题 1~6；列表缩进 0/1
  t: string;      // 原文
  segs: MdSeg[];  // 行内分段（解析一次，渲染零成本）
}

export function mdInline(s: string): MdSeg[] {
  const out: MdSeg[] = [];
  const parts: string[] = s.split(/(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/);
  for (let i = 0; i < parts.length; i++) {
    const p: string = parts[i];
    if (p === '') {
      continue;
    }
    if (p.length > 4 && p.startsWith('**') && p.endsWith('**')) {
      const sg: MdSeg = { t: p.slice(2, p.length - 2), b: true, i: false, c: false };
      out.push(sg);
    } else if (p.length > 2 && p.startsWith('`') && p.endsWith('`')) {
      const sg: MdSeg = { t: p.slice(1, p.length - 1), b: false, i: false, c: true };
      out.push(sg);
    } else if (p.length > 2 && p.startsWith('*') && p.endsWith('*')) {
      const sg: MdSeg = { t: p.slice(1, p.length - 1), b: false, i: true, c: false };
      out.push(sg);
    } else {
      const sg: MdSeg = { t: p, b: false, i: false, c: false };
      out.push(sg);
    }
  }
  return out;
}

export function mdParse(src: string): MdBlock[] {
  const out: MdBlock[] = [];
  const lines: string[] = (src === undefined || src === null ? '' : src).split('\n');
  let inCode: boolean = false;
  let codeBuf: string = '';
  for (let i = 0; i < lines.length; i++) {
    const raw: string = lines[i];
    const t: string = raw.trim();
    if (t.startsWith('```')) {   // 代码块围栏
      if (inCode) {
        const b0: MdBlock = { k: 5, lv: 0, t: codeBuf, segs: [] };
        out.push(b0);
        codeBuf = '';
        inCode = false;
      } else {
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      codeBuf = codeBuf === '' ? raw : codeBuf + '\n' + raw;
      continue;
    }
    if (t === '') {
      continue;   // 空行=块分隔（渲染靠块间距）
    }
    if (t === '---' || t === '***' || t === '___') {
      const b4: MdBlock = { k: 4, lv: 0, t: '', segs: [] };
      out.push(b4);
      continue;
    }
    if (t.charAt(0) === '#') {   // 标题（#后必须有空格，保护 #标签）
      let lv: number = 0;
      while (lv < t.length && t.charAt(lv) === '#') {
        lv++;
      }
      if (lv <= 6 && lv < t.length && (t.charAt(lv) === ' ' || t.charAt(lv) === '　')) {
        const ht: string = t.slice(lv + 1).trim();
        const b1: MdBlock = { k: 1, lv: lv, t: ht, segs: mdInline(ht) };
        out.push(b1);
        continue;
      }
    }
    if (t.charAt(0) === '>') {   // 引用
      let s0: string = t;
      while (s0.startsWith('>')) {
        s0 = s0.slice(1).trim();
      }
      if (s0 === '') {
        continue;
      }
      const b3: MdBlock = { k: 3, lv: 0, t: s0, segs: mdInline(s0) };
      out.push(b3);
      continue;
    }
    if (t.length > 2 && (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('+ '))) {
      let indent: number = 0;   // 缩进数（两个空格以上=二级）
      while (indent < raw.length
             && (raw.charAt(indent) === ' ' || raw.charAt(indent) === '　' || raw.charAt(indent) === '\t')) {
        indent++;
      }
      const lt: string = t.slice(2).trim();
      const b2: MdBlock = { k: 2, lv: indent >= 2 ? 1 : 0, t: lt, segs: mdInline(lt) };
      out.push(b2);
      continue;
    }
    let d: number = 0;   // 有序列表：1. 1、1)
    while (d < t.length && t.charAt(d) >= '0' && t.charAt(d) <= '9') {
      d++;
    }
    if (d > 0 && d <= 2 && d < t.length) {
      const ch: string = t.charAt(d);
      let bodyStart: number = -1;
      if (ch === '、') {
        bodyStart = d + 1;
      } else if ((ch === '.' || ch === ')') && d + 1 < t.length && t.charAt(d + 1) === ' ') {
        bodyStart = d + 2;
      }
      if (bodyStart > 0 && bodyStart < t.length) {
        const ot: string = t.slice(0, d) + '. ' + t.slice(bodyStart).trim();
        const b2o: MdBlock = { k: 2, lv: 0, t: ot, segs: mdInline(ot) };
        out.push(b2o);
        continue;
      }
    }
    const bp: MdBlock = { k: 0, lv: 0, t: t, segs: mdInline(t) };   // 普通段落
    out.push(bp);
  }
  if (inCode && codeBuf !== '') {
    const b5: MdBlock = { k: 5, lv: 0, t: codeBuf, segs: [] };
    out.push(b5);
  }
  return out;
}
