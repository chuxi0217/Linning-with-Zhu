@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('statusLamp') statusLamp: string = '● 醒着';
  @LocalStorageProp('dayNo') dayNo: string = '—';
  @LocalStorageProp('lastReply') lastReply: string = '姐姐在这儿';

  build() {
    Column({ space: 6 }) {
      Text(this.statusLamp)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#4a4038')
      Text(`咱家第 ${this.dayNo} 天`)
        .fontSize(12)
        .fontColor('#8a7a68')
      Text(this.lastReply)
        .fontSize(12)
        .fontColor('#6b5d4f')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(12)
    .backgroundColor('#f7f3ec')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      });
    })
  }
}
