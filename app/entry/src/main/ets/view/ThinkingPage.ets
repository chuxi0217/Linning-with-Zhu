// ── 思考链全屏页 ThinkingPage（9-30 第 2 批·整页外提）──────────────────────
// 从 pages/Index.ets 的 @Builder ThinkingPage() 原样搬出（行为逐字未改）。
// 外提口径（house 范式，见 common/theme.ets 头注 / pages/InfoPage.ets）：
//   · nightPref 本来就是 @StorageProp —— 子组件自己声明一份，**不占父参数**；
//   · this.dk(c) → dkColor(c, this.nightPref)（common/theme 外提就是为了这个）；
//   · 只读的父状态走 @Prop；本页会写的（页面开关）走 @Link，父侧传 $xxx。
import { dkColor } from '../common/theme';
import { C_BG, C_TEXT, C_ACCENT, FS_TITLE, FS_SUB, M_PAGE } from '../common/AppStyles';

// @Styles 不能跨文件——house 惯例：本文件本地重声明一份，与 Index.ets 里那对逐字一致。
@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

@Component
export struct ThinkingPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop thinkingText: string = '';
  @Link thinkingOpen: boolean;

  build() {
    Column() {
      Row() {
        Text('💭 姐姐刚才的想法')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text('关闭')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
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
          .fontColor(dkColor(C_TEXT, this.nightPref))
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
