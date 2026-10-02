// ── 共读书架阅读器 ReaderPage（9-30 第 2 批·中档外提）──────────────────────
// 从 pages/Index.ets 的 @Builder ReaderPage() 原样搬出（行为逐字未改）。
// 口径：
//   · `readerScroller` 是**共享实例**（父在「开卷」时也用它 scrollToIndex 回位）——用**普通成员**接进来
//     （非装饰成员可由父初始化，实例同一个，两边都指得对；@Prop 反而会拷一份，不能用）；
//   · `readerFirstIdx` 父只「读」（回位用）、本页只「写」——本页不持有，改成 onIndexChange 回调报上去
//     （避免把父的 plain 成员升 @State，惹出每次滚动索引变化都重渲染整树的代价）；
//   · readSelPara / readParaMark 本页会写 → @Link；批注整形 paraMarksOf 改显式入参文件级函数。
import { dkColor } from '../common/theme';
import { BookMark, BookShelf } from '../model/apiTypes';
import {
  C_BG, C_ACCENT, C_CARD, C_DISABLED, C_TEXT, C_TEXT_2, C_TEXT_4, C_WHITE,
  FS_BODY, FS_SUB, FS_AUX, R_SM, R_MD, R_PILL, M_PAGE
} from '../common/AppStyles';

/** 这一段的批注（原 Index.paraMarksOf，改显式入参：书）+ 两个人的墨迹都挂着 */
function paraMarksOfBook(book: BookShelf | null, i: number): BookMark[] {
  if (!book) {
    return [];
  }
  const out: BookMark[] = [];
  for (const mk of book.marks) {
    if (mk.para === i) {
      out.push(mk);
    }
  }
  return out;
}

@Component
export struct ReaderPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeLeftPad: number = 0;
  @Prop safeTopPad: number = 28;
  @Prop readBusy: boolean = false;
  @Prop readParas: string[] = [];
  @Prop readBook: BookShelf | null = null;
  @Link readSelPara: number;
  @Link readParaMark: string;
  scroller: Scroller = new Scroller();     // 与父共享同一实例（父开卷时也用它回位）
  onClose: () => void = () => {};
  onIndexChange: (idx: number) => void = () => {};
  onSubmitMark: () => void = () => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Text('✕')
          .fontSize(FS_BODY)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onClose();
          })
        Text(this.readBook ? `《${(this.readBook as BookShelf).title}》` : '')
          .fontSize(FS_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.readBook ? `她读到 ${(this.readBook as BookShelf).pos_her ?? 0}` : '')
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_4, this.nightPref))
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 4 })

      List({ space: 10, scroller: this.scroller }) {
        ForEach(this.readParas, (p: string, i: number) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(p)
                .fontSize(FS_BODY)
                .lineHeight(26)
                .fontColor(dkColor(C_TEXT, this.nightPref))
                .width('100%')
                .padding({ left: 4, right: 4 })
                .onClick(() => {
                  this.readSelPara = this.readSelPara === i ? -1 : i;
                  this.readParaMark = '';
                })
              // 这一段的批注（两个人的墨迹都挂着）
              ForEach(paraMarksOfBook(this.readBook, i), (mk: BookMark) => {
                Column({ space: 2 }) {
                  Text(`${mk.who === '姐姐' ? '👩 姐姐' : '🐱 我'}${mk.time === '' ? '' : ' · ' + mk.time}`)
                    .fontSize(FS_AUX)
                    .fontColor(mk.who === '姐姐' ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_TEXT_4, this.nightPref))
                  Text(mk.text)
                    .fontSize(FS_SUB)
                    .fontColor(dkColor(C_TEXT_2, this.nightPref))
                    .lineHeight(18)
                    .width('100%')
                }
                .padding(8)
                .backgroundColor(mk.who === '姐姐' ? dkColor(C_BG, this.nightPref) : dkColor(C_CARD, this.nightPref))
                .borderRadius(R_SM)
                .width('100%')
              }, (mk: BookMark) => `${mk.id}-${mk.text}`)
              // 点中的段：就地落笔
              if (this.readSelPara === i) {
                Row({ space: 8 }) {
                  TextInput({ placeholder: '在这段旁边落一笔……', text: this.readParaMark })
                    .fontSize(FS_SUB)
                    .backgroundColor(dkColor(C_WHITE, this.nightPref))
                    .borderRadius(R_MD)
                    .layoutWeight(1)
                    .onChange((v: string) => {
                      this.readParaMark = v;
                    })
                  Button(this.readBusy ? '…' : '落笔')
                    .fontSize(FS_SUB)
                    .height(36)
                    .fontColor(dkColor(C_WHITE, this.nightPref))
                    .backgroundColor(this.readParaMark.trim() !== '' && !this.readBusy
                      ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DISABLED, this.nightPref))
                    .borderRadius(R_PILL)
                    .enabled(this.readParaMark.trim() !== '' && !this.readBusy)
                    .onClick(() => {
                      this.onSubmitMark();
                    })
                }
                .width('100%')
              }
            }
            .width('100%')
          }
        }, (p: string, i: number) => `${i}-${p}`)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, bottom: 10 })
      .onScrollIndex((start: number) => {
        this.onIndexChange(start);   // 9-29：父本地记一份——退出再进要回到这里
      })
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    // LAY-01（9-23·P0 修复）：全屏模态不吃系统默认安全区——顶部避让照 ThinkingPage，
    // 横屏左右照 RiverFullPage（此前阅读器是全家唯一漏网的，「✕」与书名会被状态栏压住）
    .padding({ left: this.safeLeftPad, right: this.safeLeftPad, top: this.safeTopPad })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
