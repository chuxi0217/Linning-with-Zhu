// ── 行内富文本子组件 MdSegText（9-30 第 1 批拆分）──────────────────────────
// 从 pages/Index.ets 原样搬出。9-28 真机修：行内样式走官方属性字符串 StyledString
//（数据对象、不是子组件树）——Text 里不放 ForEach/Span 子组件树。
// 绑定时机：官方《属性字符串》指南——API 15 起 aboutToAppear 中 setStyledString 初始化即可显示。
import { FS_TITLE, FS_BODY, FS_SUB } from '../common/AppStyles';
import { MdSeg } from '../common/markdown';
import { LengthMetrics } from '@kit.ArkUI';

// ═══════════ 📖 Markdown 轻渲染 · 子组件 MdSegText（文件级 · struct Index 同级）═══════════
// 9-28 真机修：真机上「Text 内 ForEach 生成 Span」不吃（开卷卡「正在开卷……」）——
// 官方《文本显示 (Text/Span)》：Span 只能作 Text/ContainerSpan/RichEditor 的子组件；
// 官方《场景化案例》：「Text 不支持自定义组件」（非容器组件，解析子组件时不展开）。
// 故行内样式改走官方【属性字符串 StyledString】——数据对象，不是子组件树（官方原文：
// 「拥有 Span 的所有的能力」）；块级排版照旧（标题/列表/引用/分隔线/代码块）。
// 绑定时机：官方《属性字符串》指南——API 15 起 aboutToAppear 中 setStyledString 初始化即可显示
//（本机 compatibleSdkVersion 23 ✓）。
@Component
export struct MdSegText {
  segs: MdSeg[] = [];
  baseSize: number = FS_BODY;
  baseColor: string = '#5c5348';
  codeColor: string = '#b08968';
  bold: boolean = false;
  lh: number = 23;
  private ctl: TextController = new TextController();

  private styled(): MutableStyledString {
    const ms: MutableStyledString = new MutableStyledString('');
    for (let i = 0; i < this.segs.length; i++) {
      const sg: MdSeg = this.segs[i];
      const st: TextStyle = new TextStyle({
        fontSize: LengthMetrics.vp(this.baseSize),   // TextStyle.fontSize 收 LengthMetrics（不是 number）
        fontColor: sg.c ? this.codeColor : this.baseColor,
        fontWeight: (sg.b || this.bold) ? FontWeight.Bold : FontWeight.Normal,
        fontStyle: sg.i ? FontStyle.Italic : FontStyle.Normal
      });
      const opt: StyleOptions = {
        start: 0,
        length: sg.t.length,
        styledKey: StyledStringKey.FONT,
        styledValue: st
      };
      ms.appendStyledString(new StyledString(sg.t, [opt]));
    }
    return ms;
  }

  aboutToAppear(): void {
    this.ctl.setStyledString(this.styled());
  }

  build() {
    Text(undefined, { controller: this.ctl })
      .width('100%')
      .lineHeight(this.lh)
  }
}
