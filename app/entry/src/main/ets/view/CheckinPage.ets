// ── 打卡全屏页 CheckinPage（9-30 第 2 批·中档外提）──────────────────────────
// 从 pages/Index.ets 的 @Builder CheckinPage() 原样搬出（行为逐字未改）。
// 口径：
//   · `checkinTapTs`（LAY-07 防「打卡顺带开详情」的落点记账）**只服务本页** → 收进本页当自己的成员，
//     Index 里那份删掉（页专用状态就该住在页里）；
//   · 检数/连续天数三个 helper 改成显式入参的文件级函数；
//   · 进页拉数据 / 打卡 / 长按归档 都是父的方法（要用门牌与钥匙）→ 三个回调；
//   · 项详情页已是独立组件，直接 import 用。
import { dkColor } from '../common/theme';
import { CheckinItem, MonthCheckinItem } from '../model/apiTypes';
import { CheckinDetailPage } from './CheckinDetailPage';
import {
  C_BG, C_ACCENT, C_CARD, C_DISABLED, C_OK, C_PANEL, C_TEXT, C_TEXT_3, C_TEXT_4, C_TEXT_5, C_WHITE,
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

/** 今日已完成数（原 Index.checkinDoneCount） */
function checkinDoneCountOf(items: CheckinItem[], checked: number[]): number {
  let n = 0;
  for (let i = 0; i < items.length; i++) {
    if (checked.includes(items[i].id)) {
      n++;
    }
  }
  return n;
}

/** 今日总项数（原 Index.checkinTotalCount） */
function checkinTotalCountOf(items: CheckinItem[]): number {
  return items.length;
}

/** 该项的连续天数（原 Index.streakOf） */
function streakOfItem(monthItems: MonthCheckinItem[], itemId: number): number {
  for (let i = 0; i < monthItems.length; i++) {
    if (monthItems[i].item_id === itemId) {
      return monthItems[i].streak;
    }
  }
  return 0;
}

@Component
export struct CheckinPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop checkedToday: number[] = [];
  @Prop checkinBusy: boolean = false;
  @Prop checkinItems: CheckinItem[] = [];
  @Prop monthItems: MonthCheckinItem[] = [];
  @Prop checkinMsg: string = '';
  @Link checkinDetailId: number;
  onEnter: () => void = () => {};
  onCheckin: (item: CheckinItem) => void = () => {};
  onArchive: (item: CheckinItem) => void = () => {};
  private checkinTapTs: number = 0;   // LAY-07：打卡按钮落点记账——防整行点击把详情顺带打开

  build() {
    Column() {
      Row() {
        Text('✓ 打卡')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      if (this.checkinDetailId >= 0) {
        CheckinDetailPage({
          checkinItems: this.checkinItems, monthItems: this.monthItems,
          checkinDetailId: $checkinDetailId
        })
      } else {
        // ── 今日进度环（CHECKIN-2）：完成 N/M——打一项亮一格，漏了就是漏了（不许补打） ──
        Row({ space: 14 }) {
          Progress({
            value: checkinDoneCountOf(this.checkinItems, this.checkedToday),
            total: checkinTotalCountOf(this.checkinItems) > 0 ? checkinTotalCountOf(this.checkinItems) : 1,
            type: ProgressType.Ring
          })
            .width(64)
            .height(64)
            .color(dkColor(C_ACCENT, this.nightPref))
            .backgroundColor(dkColor(C_CARD, this.nightPref))
            .style({ strokeWidth: 6 })
          Column({ space: 3 }) {
            Text(`今天 ${checkinDoneCountOf(this.checkinItems, this.checkedToday)}/${checkinTotalCountOf(this.checkinItems)}`)
              .fontSize(FS_TITLE)
              .fontWeight(FontWeight.Medium)
              .fontColor(dkColor(C_TEXT, this.nightPref))
            Text(checkinTotalCountOf(this.checkinItems) > 0
              ? `完成 ${checkinDoneCountOf(this.checkinItems, this.checkedToday)}/${checkinTotalCountOf(this.checkinItems)} 项`
              : '还没有打卡项')
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_4, this.nightPref))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 2, bottom: 6 })

        Text('点按打卡，长按归档（归档不删历史）')
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_5, this.nightPref))
          .width('100%')
          .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })

        if (this.checkinMsg) {
          Text(this.checkinMsg)
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_3, this.nightPref))
            .width('100%')
            .padding({ left: M_PAGE, right: M_PAGE, bottom: 6 })
        }

        // 内层不再用 List（9-12 修「日常页滚不动」：嵌套可滚组件抢手势，统一外层滚）
        Column({ space: 8 }) {
          ForEach(this.checkinItems, (item: CheckinItem) => {
            Row() {
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(item.name)
                    .fontSize(FS_BODY)
                    .fontColor(dkColor(C_TEXT, this.nightPref))
                  if (streakOfItem(this.monthItems, item.id) >= 2) {
                    Text(`🔥 连续 ${streakOfItem(this.monthItems, item.id)} 天`)
                      .fontSize(FS_AUX)
                      .fontColor(dkColor(C_ACCENT, this.nightPref))
                  }
                }
                if (item.target_time) {
                  Text(`目标 ${item.target_time}`)
                    .fontSize(FS_AUX)
                    .fontColor(dkColor(C_TEXT_5, this.nightPref))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.checkedToday.includes(item.id)) {
                Text('已打 ✓')
                  .fontSize(FS_SUB)
                  .fontColor(dkColor(C_OK, this.nightPref))
                  .padding({ left: 12, right: 4 })
              } else {
                Button('打卡')
                  .fontSize(FS_SUB)
                  .height(40)
                  .fontColor(dkColor(C_WHITE, this.nightPref))
                  .backgroundColor(this.checkinBusy ? dkColor(C_DISABLED, this.nightPref) : dkColor(C_ACCENT, this.nightPref))
                  .borderRadius(R_PILL)
                  .enabled(!this.checkinBusy)   // 9-18 App深搜修（DS-05）：在途置灰防连点
                  .stateStyles({ pressed: pressDim, normal: pressFull })
                  .onClick(() => {
                    this.checkinTapTs = Date.now();   // LAY-07：点「打卡」就是打卡，别顺带把详情也开了
                    this.onCheckin(item);
                  })
              }

              // 右侧箭头 → 项详情（CHECKIN-2）：点开看这个月的月历热力图
              // LAY-07（9-23）：箭头补竖 padding ≥40vp；整行也可点进详情（长按归档保留）
              Text('›')
                .fontSize(22)
                .fontColor(dkColor(C_TEXT_5, this.nightPref))
                .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.checkinDetailId = item.id;
                })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(dkColor(C_PANEL, this.nightPref))
            .borderRadius(R_MD)
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              // LAY-07：整行点开详情；刚点过「打卡」的那一下不算（点击是否冒泡到这儿都稳）
              if (Date.now() - this.checkinTapTs < 500) {
                return;
              }
              this.checkinDetailId = item.id;
            })
            .gesture(LongPressGesture().onAction(() => {
              this.onArchive(item);
            }))
          }, (item: CheckinItem) => `${item.id}`)

          // 打卡项增删走姐姐（9-2 #总）：页内不再自助，跟姐姐说一声就办了
          Text('想加项、想去项？跟姐姐说一声就好')
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_5, this.nightPref))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
        }
        .width('100%')
        .padding({ left: M_PAGE, right: M_PAGE, top: 4 })
      }   // else（列表态）收口——CHECKIN-2
    }
    .width('100%')
    .padding({ top: 12 })   // 常驻分页后系统自动避让，不再吃模态避让区
    .backgroundColor(dkColor(C_BG, this.nightPref))
    .onAppear(() => {
      this.onEnter();
    })
  }
}
