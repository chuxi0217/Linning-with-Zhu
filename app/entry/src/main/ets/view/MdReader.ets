// ── Markdown 开卷阅读体 MdReader（9-30 第 2 批·中档外提）────────────────────
// 从 pages/Index.ets 的「md 阅读族」整体收编：原 mdOfA / mdOfR / mdOpenBlocks 三个缓存函数
// ＋ mdKeyA/mdCacheA/mdKeyR/mdCacheR 四个共享可变成员 ＋ @Builder MdDocView(85 行)。
//
// 【为什么值得收】：档案馆（ArchivePage）和周报（ReportsPage）**共用**这套缓存——
//   两个页面互相踩对方那 4 个缓存变量，正是「改得敢吗」的病根。收成一个自足组件后：
//   缓存归本组件私有，谁开卷谁持有，另一个页面碰不到。
//
// 【口径】：
//   · 入参只有 text（@Prop）——文本一变，@Watch 重解析；组件靠 this 读自己的 @State 刷新
//     （官方《@Builder 装饰器》建议：通过 this 访问状态变量，而不是靠参数传递）；
//   · nightPref 自取；this.dk() → dkColor()；行内样式走子组件 MdSegText（属性字符串）。
import { dkColor } from '../common/theme';
import { MdBlock, mdParse } from '../common/markdown';
import { MdSegText } from './MdSegText';
import {
  C_ACCENT, C_CARD, C_DOT_BORDER, C_TEXT, C_TEXT_2, C_TEXT_3,
  FS_TITLE, FS_BODY, FS_SUB, R_SM, M_PAGE
} from '../common/AppStyles';

@Component
export struct MdReader {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop @Watch('onTextChanged') text: string = '';
  @State blocks: MdBlock[] = [];

  onTextChanged(): void {
    this.blocks = mdParse(this.text);
  }

  aboutToAppear(): void {
    this.blocks = mdParse(this.text);
  }

  build() {
    Column() {
      ForEach(this.blocks, (blk: MdBlock, idx: number) => {
        if (blk.k === 1) {
          // 标题：# 与 ## 大字，### 起小一号；字重分级
          MdSegText({
            segs: blk.segs,
            baseSize: blk.lv <= 1 ? FS_TITLE : (blk.lv === 2 ? FS_BODY : FS_SUB),
            baseColor: dkColor(C_TEXT, this.nightPref),
            codeColor: dkColor(C_ACCENT, this.nightPref),
            bold: blk.lv <= 2,
            lh: 24
          })
            .width('100%')
            .margin({ top: idx === 0 ? 0 : 12, bottom: 4 })
        } else if (blk.k === 2) {
          // 列表项：· 前缀（缩进项给全角空格）；行内样式走 MdSegText
          Row() {
            Text(blk.lv > 0 ? '　·' : '·')
              .fontSize(FS_BODY)
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
            MdSegText({
              segs: blk.segs,
              baseSize: FS_BODY,
              baseColor: dkColor(C_TEXT_2, this.nightPref),
              codeColor: dkColor(C_ACCENT, this.nightPref),
              lh: 23
            })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 3 })
        } else if (blk.k === 3) {
          // 引用：左侧竖条 + 弱化文字
          Row() {
            Text('▎')
              .fontSize(FS_BODY)
              .fontColor(dkColor(C_DOT_BORDER, this.nightPref))
            MdSegText({
              segs: blk.segs,
              baseSize: FS_BODY,
              baseColor: dkColor(C_TEXT_3, this.nightPref),
              codeColor: dkColor(C_ACCENT, this.nightPref),
              lh: 23
            })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 4 })
        } else if (blk.k === 4) {
          Divider()
            .strokeWidth(1)
            .color(dkColor(C_DOT_BORDER, this.nightPref))
            .margin({ top: 10, bottom: 10 })
        } else if (blk.k === 5) {
          // 代码块：卡片底 + 原样文本
          Text(blk.t)
            .fontSize(FS_SUB)
            .fontColor(dkColor(C_TEXT_2, this.nightPref))
            .lineHeight(21)
            .width('100%')
            .padding(10)
            .backgroundColor(dkColor(C_CARD, this.nightPref))
            .borderRadius(R_SM)
            .margin({ top: 6 })
        } else {
          // 段落
          MdSegText({
            segs: blk.segs,
            baseSize: FS_BODY,
            baseColor: dkColor(C_TEXT_2, this.nightPref),
            codeColor: dkColor(C_ACCENT, this.nightPref),
            lh: 23
          })
            .width('100%')
            .margin({ top: 4 })
        }
      }, (blk: MdBlock, idx: number) => idx + ':' + blk.k + ':' + blk.lv + ':' + blk.t)   // key 含全文：防切文档不刷新
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: M_PAGE, right: M_PAGE, bottom: 24 })
  }
}
