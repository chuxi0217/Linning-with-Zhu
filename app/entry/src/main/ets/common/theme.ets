// ── 主题与文本工具·纯函数（9-29 拆分前置）────────────────────────────────────
// 为什么外提：页面要拆成独立 .ets 文件时，**组件的实例方法（原 Index.dk / Index.errMsg）
// 别的文件调不到**。这两只是纯函数（只认入参 + AppStorage），搬出来谁都能 import。
// 行为与原实现逐字等价，Index.ets 里保留同名壳转调（老调用点一行不动）。
import { NIGHT_MAP } from './AppStyles';

/** 夜间配色：关=原色；开/跟随系统深色=查夜表（查不到就回原色）。等价于原 Index.dk(c)。 */
export function dkColor(c: string, nightPref: string): string {
  const dark: boolean = nightPref === 'on'
    || (nightPref === 'auto' && (AppStorage.get<boolean>('sysDark') ?? false));
  if (!dark) {
    return c;
  }
  const n: string | undefined = NIGHT_MAP[c];
  return n === undefined ? c : n;
}

/** 错误人话（等价于原 Index.ets 的 errMsg）：Error 取 message，其余 JSON 化。 */
export function errText(err: Object): string {
  if (err instanceof Error) {
    return err.message;
  }
  return JSON.stringify(err);
}
