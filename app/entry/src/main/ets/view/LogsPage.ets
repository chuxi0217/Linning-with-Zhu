// ── 工地日志全屏页 LogsPage（9-30 第 2 批·整页外提）────────────────────────
// 从 pages/Index.ets 的 @Builder LogsPage() 原样搬出（行为逐字未改）。
// 口径：nightPref 自取 · dk→dkColor · 刷新是父的方法（要用门牌/钥匙）→ 回调接进来。
import { dkColor } from '../common/theme';
import { C_BG, C_TEXT, C_TEXT_2, C_ACCENT, FS_TITLE, FS_SUB, FS_AUX, M_PAGE } from '../common/AppStyles';

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

@Component
export struct LogsPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop logsBusy: boolean = false;
  @Prop logsText: string = '';
  @Link logsOpen: boolean;
  onRefresh: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text('📜 工地日志')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(this.logsBusy ? '取日志中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.logsBusy)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.onRefresh();
          })
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
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
          .fontColor(dkColor(C_TEXT_2, this.nightPref))
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
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
