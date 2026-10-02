// ── 课表图形化编辑器 KbEditPage（9-30 第 2 批·中档外提）────────────────────
// 从 pages/Index.ets 整块收编：@Builder KbEditPage / KbDayRow / KbTBtn ＋ 10 个 kb* 方法
// ＋ Index 里那一族 kb* 状态（kbEntries/kbBadLines/kbSel/kbName/kbFrom/kbTo/kbTimeMode/kbTFrom/kbTTo）。
//
// 【为什么整块收】：编辑器的全部状态与逻辑**只服务它自己**（Index 里没有任何别人碰 kb*），
//   收进来自足；父只剩「开/关」「把草稿交出去存」两件事——这是状态归位的最典型一例。
//
// 【口径】：
//   · 打开时由本组件自己 parseTimetable(draft)（父不再预解析）；
//   · 保存时把拼好的文本与改名条数交回父（父存偏好 + 出校验提示）；
//   · nightPref 自取；this.dk() → dkColor()；@Styles 本地重声明（不能跨文件）。
import { dkColor } from '../common/theme';
import { PERIOD_SLOTS, WEEK_CN, TtEntry, parseTimetable, serializeTimetable, ttMin, ttStep, ttClosestPeriod } from '../common/timetable';
import {
  C_BG, C_ACCENT, C_CARD, C_DISABLED, C_DOT_BORDER, C_TEXT, C_TEXT_2, C_TEXT_3, C_TEXT_4, C_WHITE,
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

@Component
export struct KbEditPage {
  @StorageProp('nightPref') nightPref: string = 'auto';
  @Prop draft: string = '';
  @Prop safeTopPad: number = 28;
  onClose: () => void = () => {};
  onSave: (text: string, renamed: number) => void = () => {};

  // ── 编辑器自己的状态（原 Index 的 kb* 一族）──
  @State kbEntries: TtEntry[] = [];
  @State kbBadLines: string[] = [];
  @State kbSel: number = -1;
  @State kbName: string = '';
  @State kbFrom: number = 1;
  @State kbTo: number = 2;
  @State kbTimeMode: boolean = false;
  @State kbTFrom: string = '08:00';
  @State kbTTo: string = '09:40';

  // 打开时自己解析草稿（等价于原 Index.openKbEditor）
  aboutToAppear(): void {
    const parsed = parseTimetable(this.draft);
    const arr: TtEntry[] = [];
    for (let i = 0; i < parsed.entries.length; i++) {
      arr.push({ dow: parsed.entries[i].dow, from: parsed.entries[i].from,
        to: parsed.entries[i].to, title: parsed.entries[i].title, time: parsed.entries[i].time });
    }
    this.kbEntries = arr;
    this.kbBadLines = parsed.bad;   // 9-18 修复批八（APP2-01）：坏行带进编辑器（面板列出），保存时拼回
    this.kbSel = -1;
  }

  private kbDayList(d: number): TtEntry[] {
    const out: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].dow === d) {
        out.push(this.kbEntries[i]);
      }
    }
    return out;
  }

  private kbIndexOf(d: number, k: number): number {
    let seen = 0;
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].dow === d) {
        if (seen === k) {
          return i;
        }
        seen = seen + 1;
      }
    }
    return -1;
  }

  private kbAdd(d: number): void {
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (this.kbEntries[i].title.trim().length > 0) {
        arr.push(this.kbEntries[i]);   // 加新课前先丢弃没落格的草稿（等于放弃未保存的编辑）
      }
    }
    if (this.kbTimeMode) {
      // 9-18：时间模式下加课——草稿直接按直写时间立（from/to 归 0，沿用既有约定），默认 08:00-09:40
      arr.push({ dow: d, from: 0, to: 0, title: '', time: '08:00-09:40' });
      this.kbTFrom = '08:00';
      this.kbTTo = '09:40';
    } else {
      arr.push({ dow: d, from: 1, to: 2, title: '' });
    }
    this.kbEntries = arr;
    this.kbSel = arr.length - 1;
    this.kbName = '';
    this.kbFrom = 1;
    this.kbTo = 2;
  }

  private kbPick(i: number): void {
    const e = this.kbEntries[i];
    this.kbSel = i;
    this.kbName = e.title;
    this.kbFrom = e.from;
    this.kbTo = e.to;
    if (this.kbFrom < 1) {
      this.kbFrom = 1;   // 9-18 直写时间条目（from=0）：节次控件给安全初值——防编辑面板取正典节次时越界
    }
    if (this.kbTo < 1) {
      this.kbTo = 2;
    }
    const t: string | undefined = e.time;
    if (t !== undefined && t.length > 0) {
      // 9-18：点开直写时间条目——回填原时间、直接以时间模式打开（节次控件只是安全占位）
      this.kbTimeMode = true;
      this.kbTFrom = t.substring(0, 5);
      this.kbTTo = t.substring(6, 11);
    } else {
      this.kbTimeMode = false;
    }
  }

  private kbStep(fromSide: boolean, delta: number): void {
    if (fromSide) {
      let v = this.kbFrom + delta;
      if (v < 1) {
        v = 1;
      }
      if (v > 13) {
        v = 13;
      }
      this.kbFrom = v;
      if (this.kbTo < v) {
        this.kbTo = v;
      }
    } else {
      let v = this.kbTo + delta;
      if (v < 1) {
        v = 1;
      }
      if (v > 13) {
        v = 13;
      }
      this.kbTo = v;
      if (this.kbFrom > v) {
        this.kbFrom = v;
      }
    }
  }

  private kbSetTimeMode(on: boolean): void {
    if (on === this.kbTimeMode) {
      return;
    }
    if (on) {
      this.kbTFrom = PERIOD_SLOTS[this.kbFrom - 1].split('-')[0];
      this.kbTTo = PERIOD_SLOTS[this.kbTo - 1].split('-')[1];
    } else {
      const k = ttClosestPeriod(this.kbTFrom, this.kbTTo);
      this.kbFrom = k[0];
      this.kbTo = k[1];
    }
    this.kbTimeMode = on;
  }

  private kbTStep(fromSide: boolean, hourStep: boolean, delta: number): void {
    const d = (hourStep ? 60 : 5) * delta;
    if (fromSide) {
      this.kbTFrom = ttStep(this.kbTFrom, d);
    } else {
      this.kbTTo = ttStep(this.kbTTo, d);
    }
    if (ttMin(this.kbTTo) <= ttMin(this.kbTFrom)) {
      this.kbTTo = ttStep(this.kbTFrom, 5);
    }
    if (ttMin(this.kbTTo) <= ttMin(this.kbTFrom)) {
      this.kbTFrom = ttStep(this.kbTTo, -5);
    }
  }

  private kbApply(): void {
    const name = this.kbName.trim();
    if (this.kbSel < 0 || this.kbSel >= this.kbEntries.length || name === '') {
      return;
    }
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (i === this.kbSel) {
        if (this.kbTimeMode) {
          // 9-18 时间模式：直写时间条目（from/to 归 0，沿用既有约定）——取代旧的「只改名保留时间」hack
          arr.push({ dow: this.kbEntries[i].dow, from: 0, to: 0, title: name,
            time: this.kbTFrom + '-' + this.kbTTo });
        } else {
          // 节次模式：写节次、不带 time（切回节次=接受丢直写时间，回正典节次）
          arr.push({ dow: this.kbEntries[i].dow, from: this.kbFrom,
            to: this.kbTo, title: name });
        }
      } else {
        arr.push(this.kbEntries[i]);
      }
    }
    this.kbEntries = arr;
    this.kbSel = -1;
  }

  private kbDelete(): void {
    if (this.kbSel < 0 || this.kbSel >= this.kbEntries.length) {
      return;
    }
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      if (i !== this.kbSel) {
        arr.push(this.kbEntries[i]);
      }
    }
    this.kbEntries = arr;
    this.kbSel = -1;
  }

  private kbSaveAll(): void {
    // 9-18 修复批八（APP2-01）：课名里的「，」「；」是格式的分段符，存下去这条课会整行解析失败——
    // 存前换成「·」（比拒绝少一次往返，提示语里说一声）
    let renamed = 0;
    const arr: TtEntry[] = [];
    for (let i = 0; i < this.kbEntries.length; i++) {
      const e = this.kbEntries[i];
      const t = e.title.split('，').join('·').split('；').join('·');
      if (t !== e.title) {
        renamed = renamed + 1;
      }
      arr.push({ dow: e.dow, from: e.from, to: e.to, title: t, time: e.time });
    }
    let text = serializeTimetable(arr);
    if (this.kbBadLines.length > 0) {
      // 没看懂的行原样拼回尾部：编辑器只管它看懂的条目，坏行不许被它无声抹掉
      text = text + (text === '' ? '' : '\n') + this.kbBadLines.join('\n');
    }
    // 交给父：存偏好 + 校验提示 + 改名说明（timetableMsg 显示在设置页），并关掉本页
    this.onSave(text, renamed);
  }

  @Builder
  KbDayRow(d: number) {
    Column({ space: 4 }) {
      Row() {
        Text(WEEK_CN[d])
          .fontSize(FS_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .width(56)
        Blank()
        Text('＋ 加课')
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_ACCENT, this.nightPref))
          .padding({ left: 10, right: 4, top: 6, bottom: 6 })
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbAdd(d);
          })
      }
      .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.kbDayList(d), (t: TtEntry, k: number) => {
          Text(`${t.time !== undefined && t.time.length > 0 ? t.time : t.from + '-' + t.to} ${t.title === '' ? '新课…' : t.title}`)
            .fontSize(FS_AUX)
            .fontColor(t.title === '' ? dkColor(C_TEXT_4, this.nightPref) : dkColor(C_ACCENT, this.nightPref))
            .backgroundColor(dkColor(C_WHITE, this.nightPref))
            .borderRadius(R_PILL)
            .border({ width: 1, color: dkColor(C_DOT_BORDER, this.nightPref) })
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ right: 6, bottom: 6 })
            .stateStyles({ pressed: pressDim, normal: pressFull })
            .onClick(() => {
              const idx = this.kbIndexOf(d, k);
              if (idx >= 0) {
                this.kbPick(idx);
              }
            })
        }, (t: TtEntry, k: number) => `${d}-${k}-${t.title}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  KbTBtn(fromSide: boolean, hourStep: boolean, delta: number) {
    Text(delta > 0 ? '＋' : '−')
      .fontSize(FS_BODY)
      .fontColor(dkColor(C_ACCENT, this.nightPref))
      .padding({ left: 10, right: 10, top: 2, bottom: 2 })
      .backgroundColor(dkColor(C_BG, this.nightPref))
      .borderRadius(R_PILL)
      .stateStyles({ pressed: pressDim, normal: pressFull })
      .onClick(() => {
        this.kbTStep(fromSide, hourStep, delta);
      })
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Text('📅 周课表')
          .fontSize(FS_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(dkColor(C_TEXT, this.nightPref))
          .layoutWeight(1)
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
      // 9-18 修复批八（APP2-01）：没看懂的行摆在明面上——保存时会原样拼回文本尾部，不动它们
      if (this.kbBadLines.length > 0) {
        Column({ space: 3 }) {
          Text(`${this.kbBadLines.length} 行没看懂（原样保留，保存时一起留着）：`)
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_3, this.nightPref))
            .width('100%')
          ForEach(this.kbBadLines, (b: string) => {
            Text(b)
              .fontSize(FS_AUX)
              .fontColor(dkColor(C_TEXT_4, this.nightPref))
              .width('100%')
          }, (b: string, i: number) => `kbBad${i}_${b}`)
        }
        .width('100%')
        .padding(10)
        .backgroundColor(dkColor(C_CARD, this.nightPref))
        .borderRadius(R_MD)
      }
      Scroll() {
        Column({ space: 10 }) {
          // 显示顺序：周一最上、周日收尾（下标仍是 getDay 规矩=周天0，只是铺排顺序换了，语义不动）
          ForEach([1, 2, 3, 4, 5, 6, 0], (d: number) => {
            this.KbDayRow(d)
          }, (d: number) => `${d}`)
        }
        .width('100%')
        .padding({ bottom: 6 })
      }
      .layoutWeight(1)
      if (this.kbSel >= 0 && this.kbSel < this.kbEntries.length) {
        Column({ space: 6 }) {
          Text(`编辑「${WEEK_CN[this.kbEntries[this.kbSel].dow]}」这一门`)
            .fontSize(FS_AUX)
            .fontColor(dkColor(C_TEXT_2, this.nightPref))
            .width('100%')
          TextInput({ placeholder: '课程名（地点可写在里面，如 高数 @十教）', text: this.kbName })
            .fontSize(FS_SUB)
            .backgroundColor(dkColor(C_WHITE, this.nightPref))
            .borderRadius(R_MD)
            .width('100%')
            .onChange((v: string) => {
              this.kbName = v;
            })
          // 模式切换（KB-TIME，9-18）：按节次走正典 1~13；按时间直写 HH:MM（课外活动等不定节次的课）
          Row({ space: 8 }) {
            Text('按节次')
              .fontSize(FS_SUB)
              .fontColor(!this.kbTimeMode ? dkColor(C_WHITE, this.nightPref) : dkColor(C_TEXT_2, this.nightPref))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(R_PILL)
              .backgroundColor(!this.kbTimeMode ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_BG, this.nightPref))
              .border({ width: 1, color: !this.kbTimeMode ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DOT_BORDER, this.nightPref) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbSetTimeMode(false);
              })
            Text('按时间')
              .fontSize(FS_SUB)
              .fontColor(this.kbTimeMode ? dkColor(C_WHITE, this.nightPref) : dkColor(C_TEXT_2, this.nightPref))
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(R_PILL)
              .backgroundColor(this.kbTimeMode ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_BG, this.nightPref))
              .border({ width: 1, color: this.kbTimeMode ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DOT_BORDER, this.nightPref) })
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbSetTimeMode(true);
              })
            Blank()
          }
          .width('100%')
          if (!this.kbTimeMode) {
            Row({ space: 6 }) {
              Text('从')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
              Text('−')
                .fontSize(FS_BODY)
                .fontColor(dkColor(C_ACCENT, this.nightPref))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(true, -1);
                })
              Text(`${this.kbFrom}`)
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT, this.nightPref))
              Text('＋')
                .fontSize(FS_BODY)
                .fontColor(dkColor(C_ACCENT, this.nightPref))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(true, 1);
                })
              Text('到')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
              Text('−')
                .fontSize(FS_BODY)
                .fontColor(dkColor(C_ACCENT, this.nightPref))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(false, -1);
                })
              Text(`${this.kbTo}`)
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT, this.nightPref))
              Text('＋')
                .fontSize(FS_BODY)
                .fontColor(dkColor(C_ACCENT, this.nightPref))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .stateStyles({ pressed: pressDim, normal: pressFull })
                .onClick(() => {
                  this.kbStep(false, 1);
                })
              Text(`${PERIOD_SLOTS[this.kbFrom - 1].split('-')[0]}~${PERIOD_SLOTS[this.kbTo - 1].split('-')[1]}`)
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          } else {
            Row({ space: 6 }) {
              Text('从')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
              Text('时')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
              this.KbTBtn(true, true, -1)
              this.KbTBtn(true, true, 1)
              Text('分')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
              this.KbTBtn(true, false, -1)
              this.KbTBtn(true, false, 1)
              Text(this.kbTFrom)
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT, this.nightPref))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
            Row({ space: 6 }) {
              Text('到')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_3, this.nightPref))
              Text('时')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
              this.KbTBtn(false, true, -1)
              this.KbTBtn(false, true, 1)
              Text('分')
                .fontSize(FS_AUX)
                .fontColor(dkColor(C_TEXT_4, this.nightPref))
              this.KbTBtn(false, false, -1)
              this.KbTBtn(false, false, 1)
              Text(this.kbTTo)
                .fontSize(FS_SUB)
                .fontColor(dkColor(C_TEXT, this.nightPref))
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          }
          Row({ space: 8 }) {
            Button('删除这条')
              .fontSize(FS_SUB)
              .height(40)
              .fontColor(dkColor(C_TEXT_2, this.nightPref))
              .backgroundColor(dkColor(C_BG, this.nightPref))
              .border({ width: 1, color: dkColor(C_DOT_BORDER, this.nightPref) })
              .borderRadius(R_PILL)
              .layoutWeight(1)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbDelete();
              })
            Button('落格（保存这条）')
              .fontSize(FS_SUB)
              .height(40)
              .fontColor(dkColor(C_WHITE, this.nightPref))
              .backgroundColor(this.kbName.trim() !== '' ? dkColor(C_ACCENT, this.nightPref) : dkColor(C_DISABLED, this.nightPref))
              .borderRadius(R_PILL)
              .enabled(this.kbName.trim() !== '')
              .layoutWeight(1)
              .stateStyles({ pressed: pressDim, normal: pressFull })
              .onClick(() => {
                this.kbApply();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(dkColor(C_CARD, this.nightPref))
        .borderRadius(R_MD)
      } else {
        Text('点课程格子改课，或点某天的「＋ 加课」。')
          .fontSize(FS_AUX)
          .fontColor(dkColor(C_TEXT_4, this.nightPref))
          .width('100%')
      }
      Row({ space: 8 }) {
        Button('不改了')
          .fontSize(FS_SUB)
          .height(42)
          .fontColor(dkColor(C_TEXT_2, this.nightPref))
          .backgroundColor(dkColor(C_CARD, this.nightPref))
          .borderRadius(R_PILL)
          .layoutWeight(1)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.onClose();
          })
        Button('保存课表')
          .fontSize(FS_SUB)
          .height(42)
          .fontColor(dkColor(C_WHITE, this.nightPref))
          .backgroundColor(dkColor(C_ACCENT, this.nightPref))
          .borderRadius(R_PILL)
          .layoutWeight(1)
          .stateStyles({ pressed: pressDim, normal: pressFull })
          .onClick(() => {
            this.kbSaveAll();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: M_PAGE, right: M_PAGE, top: this.safeTopPad, bottom: 16 })
    .backgroundColor(dkColor(C_BG, this.nightPref))
  }
}
