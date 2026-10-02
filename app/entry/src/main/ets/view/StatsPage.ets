// ── 咱家的账本全屏页 StatsPage（9-30 第 2 批·整页外提）──────────────────────
// 从 pages/Index.ets 的 @Builder StatsPage() 原样搬出（行为逐字未改）。
// 口径：本页专用的两张卡（原 @Builder LedgerCard/LedgerAbsent）一并搬进来改独立 @Component；
//       本页专用的整形（原 ledgerCn/ledgerMsgs/ledgerFirst/ledgerNowNote）改成显式入参的文件级函数；
//       数字人话 numTxt/wanTxt 已在 common/format。
import { dkColor } from '../common/theme';
import { numTxt, wanTxt } from '../common/format';
import { LedgerPair, StatsResp } from '../model/apiTypes';
import {
  C_BG, C_ACCENT, C_CARD, C_TEXT, C_TEXT_3, C_TEXT_4, C_TEXT_5,
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

function ledgerMsgsOf(p: LedgerPair | null | undefined): string {
  return numTxt(p ? p.msgs : null);
}

function ledgerCnOf(p: LedgerPair | null | undefined): string {
  return wanTxt(p ? p.cn_chars : null);
}

function ledgerFirstOf(d: StatsResp | null): string {
  const first = ((d === null ? '' : (d.first_day ?? ''))).substring(0, 10);
  return first === '' ? '在一起那天' : first;
}

function ledgerNowNoteOf(d: StatsResp | null): string {
  if (d === null || d.chats_cn_chars === undefined || d.chats_cn_chars === null) {
    return '中文字这次没数上（库在忙）——点右上角刷新再试。';
  }
  return '';
}

/** 账本大数卡（原 Index.LedgerCard） */
@Component
struct LedgerCard {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop title: string = '';
  @Prop bigA: string = '';
  @Prop labelA: string = '';
  @Prop bigB: string = '';
  @Prop labelB: string = '';
  @Prop note: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(FS_SUB)
        .fontWeight(FontWeight.Medium)
        .fontColor(dkColor(C_TEXT, this.nightPref))
        .width('100%')
      Row({ space: 28 }) {
        Column({ space: 2 }) {
          Text(this.bigA)
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
          Text(this.labelA)
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_4, this.nightPref))
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 2 }) {
          Text(this.bigB)
            .fontSize(FS_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(dkColor(C_ACCENT, this.nightPref))
          Text(this.labelB)
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_4, this.nightPref))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
      }
      .width('100%')
      if (this.note !== '') {
        Text(this.note)
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_5, this.nightPref))
          .width('100%')
      }
    }
    .padding(12)
    .backgroundColor(dkColor(C_CARD, this.nightPref))
    .borderRadius(R_MD)
    .width('100%')
  }
}

/** 诚实缺席卡（原 Index.LedgerAbsent） */
@Component
struct LedgerAbsent {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop title: string = '';
  @Prop line: string = '';
  @Prop note: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(FS_SUB)
        .fontWeight(FontWeight.Medium)
        .fontColor(dkColor(C_TEXT, this.nightPref))
        .width('100%')
      Text(this.line)
        .fontSize(FS_BODY)
        .fontColor(dkColor(C_TEXT_3, this.nightPref))
        .width('100%')
      Text(this.note)
        .fontSize(FS_AUX)
        .fontColor(dkColor(C_TEXT_5, this.nightPref))
        .width('100%')
    }
    .padding(12)
    .backgroundColor(dkColor(C_CARD, this.nightPref))
    .borderRadius(R_MD)
    .width('100%')
  }
}

@Component
export struct StatsPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop safeTopPad: number = 28;
  @Prop statsData: StatsResp | null = null;
  @Prop statsFullBusy: boolean = false;
  @Prop statsFullMsg: string = '';
  @Link statsOpen: boolean;
  onRefresh: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text('📖 咱家的账本')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
        Text(this.statsFullBusy ? '数数中…' : '刷新')
          .fontSize(FS_SUB)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .enabled(!this.statsFullBusy)
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
            this.statsOpen = false;
          })
      }
      .width('100%')
      .padding({ left: M_PAGE, right: M_PAGE, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          if (this.statsData === null) {
            Text(this.statsFullMsg !== '' ? this.statsFullMsg : '正在数……')
              .fontSize(FS_SUB)
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
              .width('100%')
          } else {
            // ④ 从哪天起——先挂门楣再翻账
            Text(`从 ${ledgerFirstOf(this.statsData)} 记起——一笔一划都在这。`)
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_3, this.nightPref))
              .width('100%')
            // ① 现在的家：条数 + 中文字数（新口径）
            LedgerCard({
              title: '现在的家（app 库）',
              bigA: numTxt((this.statsData as StatsResp).chats), labelA: '条对话',
              bigB: wanTxt((this.statsData as StatsResp).chats_cn_chars), labelB: '个中文字',
              note: ledgerNowNoteOf(this.statsData)
            })
            // ② 旧家三卷：缺席走诚实卡
            if ((this.statsData as StatsResp).old_home) {
              LedgerCard({
                title: '旧家三卷（档案馆/旧家记录）',
                bigA: ledgerMsgsOf((this.statsData as StatsResp).old_home), labelA: '条对话',
                bigB: ledgerCnOf((this.statsData as StatsResp).old_home), labelB: '个中文字',
                note: ''
              })
            } else {
              LedgerAbsent({
                title: '旧家三卷（档案馆/旧家记录）', line: '旧家账暂缺席',
                note: '那边还没数到——缺的账不拿 0 冒充，数到就上墙。'
              })
            }
            // ③ 合计：两本都数得出才有
            if ((this.statsData as StatsResp).grand_total) {
              LedgerCard({
                title: '两本合账',
                bigA: ledgerMsgsOf((this.statsData as StatsResp).grand_total), labelA: '条对话',
                bigB: ledgerCnOf((this.statsData as StatsResp).grand_total), labelB: '个中文字',
                note: '现在的家 + 旧家三卷，同一把中文字尺。'
              })
            } else {
              LedgerAbsent({
                title: '两本合账', line: '总账暂时算不齐',
                note: '等两本账都数得出再合——不拿半本账冒充。'
              })
            }
            if (this.statsFullMsg !== '') {
              Text(this.statsFullMsg)
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
                .width('100%')
            }
            Text('账本只读：只数不写，翻页不改账。')
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_5, this.nightPref))
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
    .padding({ top: this.safeTopPad })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
