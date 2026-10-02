// ── 门牌墙全屏页 WallPage（9-30 第 2 批·整页外提）──────────────────────────
// 从 pages/Index.ets 的 @Builder WallPage() 原样搬出（行为逐字未改）。
import { dkColor } from '../common/theme';
import { WallPin } from '../model/apiTypes';
import {
  C_BG, C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_5, C_CARD, C_ACCENT,
  FS_TITLE, FS_SUB, FS_AUX, R_SM, M_PAGE
} from '../common/AppStyles';

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

@Component
export struct WallPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop wallBusy: boolean = false;
  @Prop wallMsg: string = '';
  @Prop wallPins: WallPin[] = [];
  @Link wallOpen: boolean;
  onRefresh: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text('🧱 门牌墙')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(this.wallBusy ? '取墙中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.wallBusy)
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
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
              .width('100%')
          } else {
            ForEach(this.wallPins, (p: WallPin, i: number) => {
              Row({ space: 8 }) {
                Text(`${i + 1}`)
                  .fontSize(FS_AUX)
                  .fontColor(dkColor(C_TEXT_5, this.nightPref))
                Text(p.content ?? '')
                  .fontSize(FS_AUX)
                  .fontColor(dkColor(C_TEXT_2, this.nightPref))
                  .lineHeight(18)
                  .layoutWeight(1)
              }
              .width('100%')
              .padding(10)
              .backgroundColor(dkColor(C_CARD, this.nightPref))
              .borderRadius(R_SM)
            }, (p: WallPin) => `${p.pin_id}`)
          }
          Text('门牌墙只读：她每天开场看到的就是这些。')
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_5, this.nightPref))
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
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
