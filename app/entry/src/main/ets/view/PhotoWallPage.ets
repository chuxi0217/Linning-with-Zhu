// ── 照片墙全屏页 PhotoWallPage（9-30 第 2 批·整页外提）──────────────────────
// 从 pages/Index.ets 的 @Builder PhotoWallPage() 原样搬出（行为逐字未改）。
// 口径：favOpen / imgPreviewUrl 本页会写 → @Link；imgErrKeys 只读 → @Prop；
//       favPhotoUrl（门牌+钥匙拼接）与 markImgErr 是父的方法 → 用回调接进来。
import { dkColor } from '../common/theme';
import {
  C_BG, C_TEXT, C_TEXT_3, C_TEXT_5, C_DOT_BORDER, C_ACCENT,
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
export struct PhotoWallPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop favBusy: boolean = false;
  @Prop favMsg: string = '';
  @Prop favPhotos: string[] = [];
  @Prop imgErrKeys: string[] = [];
  @Link favOpen: boolean;
  @Link imgPreviewUrl: string;
  onRefresh: () => void = () => {};
  onImgErr: (url: string) => void = () => {};
  favUrl: (name: string) => string = () => '';

  build() {
    Column() {
      Row() {
        Text('📷 照片墙')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(this.favBusy ? '翻夹中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.favBusy)
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
            this.favOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.favPhotos.length === 0) {
            Text(this.favBusy ? '翻夹中…'
              : (this.favMsg !== '' ? this.favMsg : '夹里还空着——她收藏的照片会摆在这儿'))
              .fontSize(FS_SUB)
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
              .width('100%')
          } else {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.favPhotos, (name: string) => {
                if (this.imgErrKeys.includes(this.favUrl(name))) {
                  // FE3-08 家风：取不到的那张摊个小格直说，不摆裂图
                  // RV-03（9-23 小尾批）：文案与气泡/大图统一为完整字样（96 格内至多两行）
                  Text('图没取到（门锁/隧道）')
                    .fontSize(FS_AUX)
                    .fontColor(dkColor(C_TEXT_5, this.nightPref))
                    .width(96)
                    .height(96)
                    .textAlign(TextAlign.Center)
                    .border({ width: 1, color: dkColor(C_DOT_BORDER, this.nightPref) })
                    .borderRadius(R_SM)
                    .margin({ right: 8, bottom: 8 })
                } else {
                  Image(this.favUrl(name))
                    .width(96)
                    .height(96)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(R_SM)
                    .margin({ right: 8, bottom: 8 })
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.imgPreviewUrl = this.favUrl(name);   // 复用现成大图层
                    })
                    .onError(() => {
                      this.onImgErr(this.favUrl(name));   // FE3-08 家风：取不到就记上
                    })
                }
              }, (name: string) => name)
            }
            .width('100%')
          }
          Text('照片墙只读：她收进来的照片摆在这儿，点一张看大图。')
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
