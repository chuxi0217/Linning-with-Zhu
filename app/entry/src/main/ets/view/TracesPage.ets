// ── 她的独处（痕迹列表）TracesPage（9-30 第 2 批·整页外提）──────────────────
// 从 pages/Index.ets 的 @Builder TracesPage() 原样搬出（行为逐字未改）。
// 口径：nightPref 自取（@StorageProp）· this.dk() → dkColor() · 只读走 @Prop · 本页会写的走 @Link。
import { dkColor } from '../common/theme';
import { traceEndingCn } from '../common/format';
import { TraceItem } from '../model/apiTypes';
import {
  C_ACCENT, C_CARD, C_TEXT, C_TEXT_2, C_TEXT_4, C_TEXT_5,
  FS_AUX, FS_SUB, R_LG, R_MD, M_PAGE
} from '../common/AppStyles';

@Component
export struct TracesPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop traceMsg: string = '';
  @Prop tracesList: TraceItem[] = [];
  @Link traceOpenId: number;

  build() {
    Column({ space: 10 }) {
      if (this.traceMsg !== '') {
        Text(this.traceMsg)
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_4, this.nightPref))
          .width('100%')
      }
      if (this.tracesList.length === 0) {
        Text('她还没有独处的记录——安静也是她在过日子。')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_TEXT_4, this.nightPref))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 24 })
      }
      ForEach(this.tracesList, (t: TraceItem) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text((t.ts ?? '').length >= 16 ? (t.ts ?? '').substring(5, 16) : (t.ts ?? ''))
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_5, this.nightPref))
            Text(traceEndingCn(t.ending))
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_ACCENT, this.nightPref))
              .padding({ left: 8, right: 8, top: 1, bottom: 1 })
              .border({ width: 1, color: dkColor(C_ACCENT, this.nightPref) })
              .borderRadius(R_LG)
          }
          .width('100%')
          if (t.fact !== '') {
            Text(t.fact)
              .fontSize(FS_SUB)
              .fontColor(dkColor(C_TEXT_2, this.nightPref))
              .lineHeight(20)
              .width('100%')
          }
          if (this.traceOpenId === t.id && t.content !== '') {
            Text(t.content)
              .fontSize(FS_SUB)
              .fontColor(dkColor(C_TEXT, this.nightPref))
              .lineHeight(20)
              .width('100%')
              .padding({ top: 4 })
          }
        }
        .padding(12)
        .backgroundColor(dkColor(C_CARD, this.nightPref))
        .borderRadius(R_MD)
        .width('100%')
        .onClick(() => {
          if (t.content !== '') {
            this.traceOpenId = this.traceOpenId === t.id ? -1 : t.id;
          }
        })
      }, (t: TraceItem) => `${t.id}`)
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 2 })
    .alignItems(HorizontalAlign.Start)
  }
}
