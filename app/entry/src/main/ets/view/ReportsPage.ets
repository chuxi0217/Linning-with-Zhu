// ── 周报阅读器 ReportsPage（9-30 第 2 批·中档外提）──────────────────────────
// 从 pages/Index.ets 的 @Builder ReportsPage() 原样搬出（行为逐字未改）。
// 口径：阅读态全文交给自足组件 MdReader；本页会写的 repOpen/repTab/repDocId/repDocText 走 @Link；
//       取数是父的方法 → 两个回调；本页专用的分栏整形改成显式入参的文件级函数。
import { dkColor } from '../common/theme';
import { LibReportItem } from '../model/apiTypes';
import { MdReader } from './MdReader';
import {
  C_BG, C_ACCENT, C_CARD, C_DOT_BORDER, C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4, C_TEXT_5, C_WHITE,
  FS_TITLE, FS_BODY, FS_SUB, FS_AUX, R_MD, R_PILL, M_PAGE
} from '../common/AppStyles';

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

/** 按分栏筛条目（原 Index.repItemsOfTab） */
function repItemsOfTabOf(items: LibReportItem[], tab: string): LibReportItem[] {
  const out: LibReportItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const st = items[i].status ?? '';
    const hit = tab === '待审' ? st.indexOf('入库') < 0 : st.indexOf('入库') >= 0;
    if (hit) {
      out.push(items[i]);
    }
  }
  return out;
}

@Component
export struct ReportsPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop repBusy: boolean = false;
  @Prop repMsg: string = '';
  @Prop repItems: LibReportItem[] = [];
  @Prop repDocTitle: string = '';
  @Prop repDocStatus: string = '';
  @Link repOpen: boolean;
  @Link repTab: string;
  @Link repDocId: number;
  @Link repDocText: string;
  onRefresh: () => void = () => {};
  onOpenReport: (it: LibReportItem) => void = () => {};

  build() {
    Column() {
      if (this.repDocId >= 0) {
        // 阅读态：返回 + 题 + 字数 + 全文滚动（照档案馆家风）
        Row({ space: 10 }) {
          Text('‹ 返回')
            .fontSize(FS_SUB)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              this.repDocId = -1;
              this.repDocTitle = '';
              this.repDocText = '';
              this.repDocStatus = '';
            })
          Text(this.repDocTitle === '' ? '周报' : this.repDocTitle)
            .fontSize(FS_BODY)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_TEXT, this.nightPref))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.repDocStatus !== '') {
            Text(this.repDocStatus)
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_4, this.nightPref))
          }
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 10, bottom: 6 })

        Scroll() {
          MdReader({ text: this.repDocText })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      } else {
        // 列表态：标题 + 刷新 + 关闭 → chips → 列表
        Row() {
          Text('🗂 周报')
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_TEXT, this.nightPref))
            .layoutWeight(1)
          Text(this.repBusy ? '取稿中…' : '刷新')
            .fontSize(FS_SUB)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .enabled(!this.repBusy)
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
              this.repOpen = false;
            })
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

        Row({ space: 8 }) {
          ForEach(['待审', '已入库'], (t: string) => {
            Text(t)
              .fontSize(FS_SUB)
              .fontColor(this.repTab === t ? dkColor(C_WHITE, this.nightPref) : dkColor(C_TEXT_2, this.nightPref))
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(R_PILL)
              .backgroundColor(this.repTab === t ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_CARD, this.nightPref))
              .border({
                width: 1,
                color: this.repTab === t ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DOT_BORDER, this.nightPref)
              })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.repTab = t;
              })
          }, (t: string) => t)
          Blank()
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })

        Scroll() {
          Column({ space: 8 }) {
            if (repItemsOfTabOf(this.repItems, this.repTab).length === 0) {
              Text(this.repBusy ? '取稿中…'
                : (this.repMsg !== '' ? this.repMsg : '这周还没交稿（周日 21 点）'))
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
                .width('100%')
            } else {
              ForEach(repItemsOfTabOf(this.repItems, this.repTab), (it: LibReportItem) => {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(it.date ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(dkColor(C_TEXT_4, this.nightPref))
                    Text(it.kind ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(dkColor(C_TEXT_4, this.nightPref))
                    Blank()
                    Text(it.status ?? '')
                      .fontSize(FS_AUX)
                      .fontColor(dkColor(C_ACCENT, this.nightPref))
                  }
                  .width('100%')
                  Text((it.title ?? '') === '' ? '（无题）' : (it.title ?? ''))
                    .fontSize(FS_SUB)
                    .fontColor(dkColor(C_TEXT, this.nightPref))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width('100%')
                .padding(10)
                .backgroundColor(dkColor(C_CARD, this.nightPref))
                .borderRadius(R_MD)
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.onOpenReport(it);
                })
              }, (it: LibReportItem) => `${it.id}-${it.status}`)
            }
            Text('只读：终审是姐姐的笔，这里不代签。')
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
