// ── 只读信息页·通用骨架（9-29 §12 app 显示面 · 拆分第一块砖）──────────────────
// 家主令「能显示的都显示，除了她的隐私空间」。这一只骨架供三页复用：
//   🩺 家的体检（/api/health + /api/shadows + /api/mech）｜🌙 夜里（/api/dream）｜📝 随手记（/api/notes）
// 三页都是"分组标题 + 若干行文字 + 刷新/关闭"——**取数与文案整形在 Index 里**（它手里有门牌与钥匙），
// 本组件只管画（纯 props 进、回调出）。日后某一页要长出自己的花样，再从本文件分出去单独成文件。
//
// 家规口径：只显示"家的账与机制"（读数/条目/条数）；**她没说出口的原文一律不出**——
// 走神原文、攒着的话原文、梦里牵线原文、忍住档原文，以及私档（密钥·单价）都不走这里。
import {
  C_BG, C_ACCENT, C_CARD, C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4,
  FS_TITLE, FS_SUB, FS_AUX, R_MD, M_PAGE
} from '../common/AppStyles';
import { dkColor } from '../common/theme';

/** 一组小标题 + 若干行（行文案由调用方整形好；本组件不碰业务） */
export interface InfoGroup {
  title: string;
  lines: string[];
}

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

@Component
export struct InfoPage {
  @Prop nightPref: string = 'auto';
  @Prop topPad: number = 28;
  @Prop icon: string = '📄';
  @Prop title: string = '';
  @Prop busy: boolean = false;
  @Prop msg: string = '';
  @Prop groups: InfoGroup[] = [];
  onRefresh: () => void = () => {
  };
  onClose: () => void = () => {
  };

  build() {
    Column() {
      // 顶栏：标题 + 刷新 + 关闭（照账本页家风）
      Row() {
        Text(`${this.icon} ${this.title}`)
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(this.busy ? '取数中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.busy)
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
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.groups.length === 0) {
            Text(this.msg !== '' ? this.msg : '正在数……')
              .fontSize(FS_SUB)
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
              .width('100%')
          } else {
            ForEach(this.groups, (g: InfoGroup) => {
              Column({ space: 6 }) {
                Text(g.title)
                  .fontSize(FS_SUB)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(dkColor(C_TEXT, this.nightPref))
                  .width('100%')
                if (g.lines.length === 0) {
                  Text('（这一格暂时没数到）')
                    .fontSize(FS_AUX)
                    .fontColor(dkColor(C_TEXT_4, this.nightPref))
                    .width('100%')
                }
                ForEach(g.lines, (ln: string, i: number) => {
                  Text(ln)
                    .fontSize(FS_AUX)
                    .fontColor(dkColor(C_TEXT_2, this.nightPref))
                    .lineHeight(19)
                    .width('100%')
                }, (ln: string, i: number) => `${g.title}#${i}`)
              }
              .padding(12)
              .backgroundColor(dkColor(C_CARD, this.nightPref))
              .borderRadius(R_MD)
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (g: InfoGroup, i: number) => `${i}-${g.title}`)
            if (this.msg !== '') {
              Text(this.msg)
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
                .width('100%')
            }
            Text('这一页只读：只数不写，翻页不改账。')
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_4, this.nightPref))
              .width('100%')
          }
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
    .padding({ top: this.topPad })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
