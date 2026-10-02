// ── 聊天数据源 ChatDataSource（9-30 第 1 批拆分）─────────────────────────
// 从 pages/Index.ets 原样搬出：LazyForEach 的 IDataSource 适配器。
// 行为逐字未改（搬家而已）。
import { ChatItem } from './apiTypes';

// ── 聊天数据源（FE-02 要求6）：LazyForEach 的 IDataSource 适配器。
// 数组是唯一真相，每次变更按需通知监听者——消息列表按需构建，一屏气泡一建，
// 不再一次性铺满全天历史（低内存、首屏快，滚动丝滑）。 ──
export class ChatDataSource implements IDataSource {
  private items: ChatItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatItem {
    return this.items[index];
  }

  getAll(): ChatItem[] {
    return this.items;
  }

  // 9-18 App深搜修（DS-02）：历史卷落地前认领活口用——浅拷一份当前列表（后续改列表不动这份快照）
  snapshot(): ChatItem[] {
    return this.items.slice();
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notify(fn: (l: DataChangeListener) => void): void {
    for (let i = 0; i < this.listeners.length; i++) {
      fn(this.listeners[i]);
    }
  }

  append(item: ChatItem): void {
    this.items.push(item);
    this.notify((l: DataChangeListener) => l.onDataAdd(this.items.length - 1));
  }

  setAll(items: ChatItem[]): void {
    this.items = items;
    this.notify((l: DataChangeListener) => l.onDataReloaded());
  }

  // FE3-02（b）（9-23）：续载去重——服务端 id 唯一，已在列表里的同一条账不再接第二份。
  // 无 id 的活口气泡（乐观气泡/时间线卡）不在此列，仍走 mergeWithLive 的认领口径。
  private hasMsgId(id: number): boolean {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].msgId === id) {
        return true;
      }
    }
    return false;
  }

  // 9-23 V-1 全量浏览：老窗前插（旧在前）——倒序逐条 onDataAdd(0)，让列表
  // maintainVisibleContentPosition 能按"插入在可视区外"维持眼前这屏（整卷 reload 会顶走位置）
  prependAll(arr: ChatItem[]): void {
    if (arr.length === 0) {
      return;
    }
    for (let i = arr.length - 1; i >= 0; i--) {
      const m = arr[i];
      if (m.msgId !== undefined && this.hasMsgId(m.msgId)) {
        continue;   // FE3-02（b）：已经有这条账了，跳过
      }
      this.items.unshift(m);
      this.notify((l: DataChangeListener) => l.onDataAdd(0));
    }
  }

  // 9-23 V-1：下翻续载——尾部顺序追加（与 prependAll 对称）
  appendAll(arr: ChatItem[]): void {
    for (let i = 0; i < arr.length; i++) {
      const m = arr[i];
      if (m.msgId !== undefined && this.hasMsgId(m.msgId)) {
        continue;   // FE3-02（b）：老窗续载到今天的窗口时，同一句话不再出现第二份
      }
      this.items.push(m);
      this.notify((l: DataChangeListener) => l.onDataAdd(this.items.length - 1));
    }
  }

  removeWhere(pred: (m: ChatItem) => boolean): void {
    for (let i = this.items.length - 1; i >= 0; i--) {
      if (pred(this.items[i])) {
        this.items.splice(i, 1);
        this.notify((l: DataChangeListener) => l.onDataDelete(i));
      }
    }
  }

}
