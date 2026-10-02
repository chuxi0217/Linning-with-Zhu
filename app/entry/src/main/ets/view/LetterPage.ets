// ── 给姐姐写信 LetterPage（9-30 第 2 批·整页外提）────────────────────────────
// 从 pages/Index.ets 的 @Builder LetterPage() 原样搬出（行为逐字未改）。
// 口径：letterText 本页要写（TextArea onChange）→ @Link；投递是父的方法 → 回调。
import { dkColor } from '../common/theme';
import {
  C_BG, C_TEXT, C_TEXT_3, C_TEXT_4, C_TEXT_5, C_WHITE, C_ACCENT, C_DISABLED, C_OK,
  FS_TITLE, FS_BODY, FS_SUB, FS_AUX, R_MD, R_PILL_XL, M_PAGE
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
export struct LetterPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop stLetters: number = 0;
  @Link letterText: string;
  @Prop letterMsg: string = '';
  @Prop letterBusy: boolean = false;
  onSend: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('✉️ 给姐姐写信')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(`信箱：${this.stLetters} 封待她读`)
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_4, this.nightPref))
      }
      .width('100%')

      Text('想说的话，慢慢写。投进信箱，姐姐读到了会接住的。')
        .fontSize(FS_SUB)
        .fontColor(dkColor(C_TEXT_3, this.nightPref))
        .width('100%')

      TextArea({
        text: this.letterText,
        placeholder: '亲爱的姐姐……'
      })
        .fontSize(FS_BODY)
        .lineHeight(26)
        .placeholderFont({ size: FS_BODY })
        .backgroundColor(dkColor(C_WHITE, this.nightPref))
        .borderRadius(R_MD)
        .maxLength(2000)
        .constraintSize({ minHeight: 240 })
        .width('100%')
        .onChange((v: string) => {
          this.letterText = v;
        })

      Text(`${this.letterText.length} / 2000`)
        .fontSize(FS_AUX)
        .fontColor(dkColor(C_TEXT_5, this.nightPref))
        .width('100%')
        .textAlign(TextAlign.End)

      Button('投进信箱')
        .fontSize(FS_BODY)
        .height(44)
        .fontColor(dkColor(C_WHITE, this.nightPref))
        .backgroundColor(this.letterText.trim() ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DISABLED, this.nightPref))
        .borderRadius(R_PILL_XL)
        .enabled(this.letterText.trim().length > 0 && !this.letterBusy)
        .width('100%')
        .stateStyles({ pressed: pressDim, normal: pressFull })
        .onClick(() => {
          this.onSend();
        })

      if (this.letterMsg) {
        Text(this.letterMsg)
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_OK, this.nightPref))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 12, bottom: 16 })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
