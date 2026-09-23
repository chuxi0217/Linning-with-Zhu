// ── 全局样式常典（工单 FE-02，2026-09-09）──
// 家规正典色板一字不动，纯搬家不创新：全部页面从这里引用，改一处全局生效。
// 字号四步进：大标题 20 / 正文 16 / 次要 14 / 辅助 12（下限）——新页面不得自创字号。
// 单位军规：全局只用 vp/fp，禁写死 px（canvas 绘字是其 API 规格例外）。

// 色板（以现有页面取样为源）
export const C_BG: string = '#f7f3ec';          // 白茶底（家规正典）
export const C_ACCENT: string = '#b08968';      // 强调（姐姐的笔色，家规正典）
export const C_BUBBLE_ME: string = '#d9c7b2';   // 小乖气泡（家规正典）
export const C_HER_EDGE: string = '#ece2d4';    // 姐姐气泡描边 / 河床线（家规正典）
export const C_PANEL: string = '#fffdf9';       // 顶栏 / 面板 / 输入栏卡底
export const C_WHITE: string = '#ffffff';       // 姐姐气泡 / 输入框
export const C_CARD: string = '#f3ede4';        // 小灰卡（工具卡 / 💭入口 / 未选浓度点）
export const C_TEXT: string = '#4a4038';        // 主文字
export const C_TEXT_2: string = '#6b5d4f';      // 次文字
export const C_TEXT_3: string = '#8a7a68';      // 辅助文字
export const C_TEXT_4: string = '#a89888';      // 淡文字（页脚说明 / 睡了）
export const C_TEXT_5: string = '#b3a494';      // 时间小字 / 最淡提示
export const C_OK: string = '#7a9471';          // 成功绿（醒着 / 已打 / 记下了）
export const C_DISABLED: string = '#cbbfae';    // 禁用按钮底
export const C_DOT_BORDER: string = '#d9cbb8';  // 未选浓度点描边

// 字号步进（fp）
export const FS_TITLE: number = 20;   // 大标题
export const FS_BODY: number = 16;    // 正文
export const FS_SUB: number = 14;     // 次要
export const FS_AUX: number = 12;     // 辅助（全 UI 下限）

// 圆角（vp）：气泡大角 / 气泡收尾角 / 按钮胶囊按高度取半
export const R_TAIL: number = 4;      // 气泡靠嘴角的收尾角
export const R_SM: number = 8;        // 小卡 / 图内圆角
export const R_MD: number = 12;       // 列表卡 / 输入框 / 画布
export const R_LG: number = 14;       // 💭入口 / 返回钮 / 横屏画布
export const R_XL: number = 16;       // 气泡大角 / 面板条目
export const R_PILL: number = 20;     // 40vp 高按钮的胶囊
export const R_PILL_XL: number = 22;  // 44vp 高按钮 / 输入框的胶囊

// 间距（vp）
export const M_PAGE: number = 16;     // 左右页边距（统一 16）

// ── 夜间色板（9-12 家主令）：暖夜不纯黑——同一套家，换一盏灯 ──
// 键=日间色值正典，值=夜下对应色。Index.dk() 按色值查表，查不到原样返回。
export const NIGHT_MAP: Record<string, string> = {
  '#f7f3ec': '#1b1611',   // 白茶底 → 深咖底
  '#b08968': '#c09a72',   // 姐姐的笔色提亮一档保对比
  '#d9c7b2': '#4a3c2e',   // 小乖气泡
  '#ece2d4': '#3a3128',   // 气泡描边/河床线
  '#fffdf9': '#241e17',   // 顶栏/面板
  '#ffffff': '#2a231b',   // 气泡白/输入框
  '#f3ede4': '#251f18',   // 小灰卡
  '#4a4038': '#e6dccd',   // 主文字
  '#6b5d4f': '#c5b7a4',   // 次文字
  '#8a7a68': '#a3937f',   // 辅助文字
  '#a89888': '#7d6f5e',   // 淡文字
  '#b3a494': '#6a5d4e',   // 时间小字
  '#7a9471': '#8fae83',   // 成功绿
  '#cbbfae': '#413a30',   // 禁用底
  '#d9cbb8': '#413a30',   // 浓度点描边
  '#e9d9bd': '#2f2820',   // 书架木板
  '#c9a876': '#5a4a36',   // 书架层板
};
