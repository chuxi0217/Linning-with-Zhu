// ── 点图看大图 ImagePreviewPage（9-30 第 2 批·整页外提）────────────────────
// 从 pages/Index.ets 的 @Builder ImagePreviewPage() 原样搬出（行为逐字未改）。
// 口径：imgPreviewUrl 本页会写（关闭/点任意处）→ @Link；imgErrKeys 只读 → @Prop；
//       markImgErr 是父的方法 → onImgErr 回调。本页没有 dk() 用法（黑底纯白字）。
import { FS_BODY } from '../common/AppStyles';

@Component
export struct ImagePreviewPage {
  @Prop safeTopPad: number = 28;
  @Prop imgErrKeys: string[] = [];
  @Link imgPreviewUrl: string;
  onImgErr: (url: string) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.imgErrKeys.includes(this.imgPreviewUrl)) {
        Text('图没取到（门锁/隧道）')
          .fontSize(FS_BODY)
          .fontColor(Color.White)
          .opacity(0.85)
      } else {
        Image(this.imgPreviewUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .onError(() => {
            this.onImgErr(this.imgPreviewUrl);
          })
      }
      // 可见关闭提示：40×40，半透明黑底白字（点任意处也能关，这只是给个明说）
      Text('✕')
        .fontSize(FS_BODY)
        .fontColor(Color.White)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor('#66000000')
        .borderRadius(20)
        .margin({ top: this.safeTopPad + 6, right: 12 })
        .onClick(() => {
          this.imgPreviewUrl = '';
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onClick(() => {
      this.imgPreviewUrl = '';
    })
  }
}
