// ── 档案馆全屏页 ArchivePage（9-30 第 2 批·中档外提）──────────────────────
// 从 pages/Index.ets 的 @Builder ArchivePage() 原样搬出（行为逐字未改）。
// 口径：阅读态的全文交给自足组件 MdReader（md 缓存已收编进去，本页不再碰缓存）；
//       本页会写的三个（archiveOpen / archDocTitle / archDocText）走 @Link；
//       取数是父的方法 → 三个回调；本页专用的分组整形改成显式入参的文件级函数。
import { dkColor } from '../common/theme';
import { fmtSize } from '../common/format';
import { ArchiveItem, CardGroup, CardItem } from '../model/apiTypes';
import { MdReader } from './MdReader';
import {
  C_BG, C_ACCENT, C_CARD, C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4, C_TEXT_5,
  FS_TITLE, FS_BODY, FS_SUB, FS_AUX, R_MD, M_PAGE
} from '../common/AppStyles';

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

/** 卷名清单（原 Index.archGroupsList）——卡片馆单列，其余按 group 去重 */
function archGroupsListOf(items: ArchiveItem[]): string[] {
  const out: string[] = [];
  for (const it of items) {
    const g = it.group ?? '未归类';
    if (g.indexOf('卡片') >= 0) {
      continue;
    }
    if (out.indexOf(g) < 0) {
      out.push(g);
    }
  }
  return out;
}

/** 某一卷的条目（原 Index.archItemsOf） */
function archItemsOfGroup(items: ArchiveItem[], g: string): ArchiveItem[] {
  const out: ArchiveItem[] = [];
  for (const it of items) {
    const itg = it.group ?? '未归类';
    if (itg === g && itg.indexOf('卡片') < 0) {
      out.push(it);
    }
  }
  return out;
}

@Component
export struct ArchivePage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop archBusy: boolean = false;
  @Prop archCards: CardGroup[] = [];
  @Prop archItems: ArchiveItem[] = [];
  @Prop archMsg: string = '';
  @Link archiveOpen: boolean;
  @Link archDocTitle: string;
  @Link archDocText: string;
  onRefresh: () => void = () => {};
  onOpenCard: (c: CardItem) => void = () => {};
  onOpenDoc: (name: string) => void = () => {};

  build() {
    Column() {
      if (this.archDocTitle !== '') {
        // 阅读态：返回 + 卷题 + 全文滚动（长文可滚）
        Row({ space: 10 }) {
          Text('‹ 返回')
            .fontSize(FS_SUB)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })   // LAY-07：触摸目标补到 ≥40vp
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.archDocTitle = '';
              this.archDocText = '';
            })
          Text(this.archDocTitle)
            .fontSize(FS_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_TEXT, this.nightPref))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // LAY-10（9-23）：阅读态给个进度感——卷题旁挂字数（本地 length，零接口）
          if (this.archDocText !== '' && this.archDocText !== '正在开卷……') {
            Text(`· ${this.archDocText.length} 字`)
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_4, this.nightPref))
          }
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 6 })

        Scroll() {
          MdReader({ text: this.archDocText })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        // 列表态
        Row() {
          Text('🗄 档案馆')
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_TEXT, this.nightPref))
            .layoutWeight(1)
          Text(this.archBusy ? '开门中…' : '刷新')
            .fontSize(FS_SUB)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .enabled(!this.archBusy)
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
              this.archiveOpen = false;
            })
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

        Scroll() {
          Column({ space: 12 }) {
            // ① 卡片馆（现成 /api/cards）
            if (this.archCards.length > 0) {
              Text('🗂 卡片馆')
                .fontSize(FS_SUB)
                .fontWeight(FontWeight.Medium)
                .fontColor(dkColor(C_TEXT, this.nightPref))
                .width('100%')
              ForEach(this.archCards, (g: CardGroup) => {
                Column({ space: 4 }) {
                  Text(`${g.key ?? ''} · ${g.cards ? g.cards.length : 0} 张`)
                    .fontSize(FS_AUX)
                    .fontColor(dkColor(C_TEXT_3, this.nightPref))
                    .width('100%')
                  ForEach(g.cards ?? [], (c: CardItem) => {
                    Row({ space: 8 }) {
                      Text(c.id ?? '')
                        .fontSize(FS_AUX)
                        .fontColor(dkColor(C_TEXT_4, this.nightPref))
                      Text(c.title ?? '')
                        .fontSize(FS_SUB)
                        .fontColor(dkColor(C_TEXT_2, this.nightPref))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text('开 ›')
                        .fontSize(FS_AUX)
                        .fontColor(dkColor(C_ACCENT, this.nightPref))
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor(dkColor(C_CARD, this.nightPref))
                    .borderRadius(R_MD)
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.onOpenCard(c);
                    })
                  }, (c: CardItem) => `${g.key}-${c.id}`)
                }
                .width('100%')
              }, (g: CardGroup) => `${g.key}`)
            }

            // ②-⑤ 周卷 / 旧家三卷 / 全档案续页 / 大事记卷（/api/archive，服务端下一批）
            if (archGroupsListOf(this.archItems).length > 0) {
              ForEach(archGroupsListOf(this.archItems), (g: string) => {
                Column({ space: 4 }) {
                  Text(g)
                    .fontSize(FS_SUB)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(dkColor(C_TEXT, this.nightPref))
                    .width('100%')
                  ForEach(archItemsOfGroup(this.archItems, g), (it: ArchiveItem) => {
                    Row({ space: 8 }) {
                      Text(it.name ?? '')
                        .fontSize(FS_SUB)
                        .fontColor(dkColor(C_TEXT_2, this.nightPref))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (it.size !== undefined && it.size !== null) {
                        Text(fmtSize(it.size))
                          .fontSize(FS_AUX)
                          .fontColor(dkColor(C_TEXT_4, this.nightPref))
                      }
                      Text('开 ›')
                        .fontSize(FS_AUX)
                        .fontColor(dkColor(C_ACCENT, this.nightPref))
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor(dkColor(C_CARD, this.nightPref))
                    .borderRadius(R_MD)
                    .stateStyles({ pressed: pressDim, normal: pressFull })
                    .onClick(() => {
                      this.onOpenDoc(it.name ?? '');
                    })
                  }, (it: ArchiveItem) => `${g}-${it.name}`)
                }
                .width('100%')
              }, (g: string) => g)
            } else if (!this.archBusy) {
              Text(this.archMsg !== '' ? this.archMsg : '这间屋还没开门')
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
                .width('100%')
            }
            Text('档案只读：翻卷不改字。')
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
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.safeTopPad })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
