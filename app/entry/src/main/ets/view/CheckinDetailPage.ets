// ── 打卡详情页 CheckinDetailPage（9-30 第 2 批·整页外提）────────────────────
// 从 pages/Index.ets 的 @Builder CheckinDetailPage() 原样搬出（行为逐字未改）。
// 口径：本页专用的整形函数（原 detailName/Days/Best/HasDay/Weeks）一并搬进来当文件级函数，
//       入参走显式参数（不再隐式读 this）；detailMonthDays 已在 common/format。
import { dkColor } from '../common/theme';
import { detailMonthDays } from '../common/format';
import { CheckinItem, MonthCheckinItem } from '../model/apiTypes';
import {
  C_ACCENT, C_CARD, C_TEXT, C_TEXT_2, C_TEXT_5, C_WHITE, FS_BODY, FS_SUB, FS_AUX, M_PAGE
} from '../common/AppStyles';

@Styles
function pressDim() {
  .opacity(0.7)
}

@Styles
function pressFull() {
  .opacity(1)
}

function detailNameOf(items: CheckinItem[], id: number): string {
  for (let i = 0; i < items.length; i++) {
    if (items[i].id === id) {
      return items[i].name;
    }
  }
  return '';
}

function detailDaysOf(items: MonthCheckinItem[], id: number): number[] {
  for (let i = 0; i < items.length; i++) {
    if (items[i].item_id === id) {
      return items[i].days;
    }
  }
  return [];
}

function detailBestOf(items: MonthCheckinItem[], id: number): number {
  for (let i = 0; i < items.length; i++) {
    if (items[i].item_id === id) {
      return items[i].best;
    }
  }
  return 0;
}

function detailWeeksOf(): number[][] {
  const total = detailMonthDays();
  const now = new Date();
  const firstDow: number = new Date(now.getFullYear(), now.getMonth(), 1).getDay();   // 0=周日
  const out: number[][] = [];
  let row: number[] = [];
  // 10-02 修：按 1 号的真实星期对齐（原从 1 号起每 7 个硬切，整月周列都错位）。0＝空占位。
  for (let b = 0; b < firstDow; b++) {
    row.push(0);
  }
  for (let d = 1; d <= total; d++) {
    row.push(d);
    if (row.length === 7) {
      out.push(row);
      row = [];
    }
  }
  if (row.length > 0) {
    while (row.length < 7) {
      row.push(0);
    }
    out.push(row);
  }
  return out;
}

const WEEKDAY_CN: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@Component
export struct CheckinDetailPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop checkinItems: CheckinItem[] = [];
  @Prop monthItems: MonthCheckinItem[] = [];
  @Link checkinDetailId: number;

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('‹ 返回')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })   // LAY-07：触摸目标补到 ≥40vp
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.checkinDetailId = -1;
          })
        Text(detailNameOf(this.checkinItems, this.checkinDetailId))
          .fontSize(FS_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
      }
      .width('100%')

      Text(`本月 ${detailDaysOf(this.monthItems, this.checkinDetailId).length} 天 · 最长 🔥${detailBestOf(this.monthItems, this.checkinDetailId)} 天`)
        .fontSize(FS_SUB)
        .fontColor(dkColor(C_TEXT_2, this.nightPref))
        .width('100%')

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          ForEach(WEEKDAY_CN, (w: string) => {
            Text(w)
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_5, this.nightPref))
              .width(32)
              .textAlign(TextAlign.Center)
          }, (w: string, wi: number) => `wk${wi}`)
        }
        .width('100%')

        ForEach(detailWeeksOf(), (row: number[], ri: number) => {
          Row({ space: 6 }) {
            ForEach(row, (d: number, di: number) => {
              Stack() {
                Text(d === 0 ? '' : `${d}`)
                  .fontSize(FS_AUX)
                  .fontColor(detailDaysOf(this.monthItems, this.checkinDetailId).includes(d)
                    ? dkColor(C_WHITE, this.nightPref) : dkColor(C_TEXT_5, this.nightPref))
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor(d === 0 ? dkColor(C_CARD, this.nightPref) : (detailDaysOf(this.monthItems, this.checkinDetailId).includes(d)
                ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_CARD, this.nightPref)))
              .opacity(d === 0 ? 0 : 1)
            }, (d: number, di: number) => `${di}-${d}`)
          }
          .width('100%')
        }, (row: number[], ri: number) => `r${ri}-${row.join('-')}`)
      }
      .width('100%')

      if (detailDaysOf(this.monthItems, this.checkinDetailId).length === 0) {
        Text('这个月还空着——今天打上，第一格就亮。')
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_5, this.nightPref))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: 2 })
    .alignItems(HorizontalAlign.Start)
  }
}
