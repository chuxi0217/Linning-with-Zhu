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
  const out: number[][] = [];
  let row: number[] = [];
  for (let d = 1; d <= total; d++) {
    row.push(d);
    if (row.length === 7) {
      out.push(row);
      row = [];
    }
  }
  if (row.length > 0) {
    out.push(row);
  }
  return out;
}

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
        ForEach(detailWeeksOf(), (row: number[]) => {
          Row({ space: 6 }) {
            ForEach(row, (d: number) => {
              Stack() {
                Text(`${d}`)
                  .fontSize(FS_AUX)
                  .fontColor(detailDaysOf(this.monthItems, this.checkinDetailId).includes(d)
                    ? dkColor(C_WHITE, this.nightPref) : dkColor(C_TEXT_5, this.nightPref))
              }
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor(detailDaysOf(this.monthItems, this.checkinDetailId).includes(d)
                ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_CARD, this.nightPref))
            }, (d: number) => `${d}`)
          }
          .width('100%')
        }, (row: number[]) => `r${row[0]}`)
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
