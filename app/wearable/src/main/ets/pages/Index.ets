import { http } from '@kit.NetworkKit';
import { sensor, vibrator } from '@kit.SensorServiceKit';
import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { linkEnhance } from '@kit.DistributedServiceKit';
import { ble } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LINK_DOMAIN = 0x0001;
const LINK_TAG = 'ourFamilyLink';
// 咱家跨设备广播用的自定义服务 UUID（手机按它扫描找手表）
const LINK_ADV_UUID = '0000FA51-0000-1000-8000-00805F9B34FB';

// ============================================================
// 咱家门牌清单（9-10 多门牌容错）：按序试，试通的记住下次优先。
// ① 手机热点（手表 SERVER_BASE 老值）；② 家里 Linux 局域网 IP
// （家里 WiFi 下手表直连 server，睡觉上报不靠手机中转——IP 变了改这里）。
// ============================================================
const SERVER_BASES: string[] = [
  'http://192.168.x.x:8024'
  // ↓ 家里 Linux server 的局域网 IP（Linux 侧 ip -4 addr 查），填上后家里 WiFi 下
  //   手表直连 server、睡觉上报不靠手机中转。填一次记一次，试通的会记住优先用。
  // , 'http://192.168.x.x:8024'
];
const PREFS_NAME = 'zanjia_watch';

// 手机的蓝牙地址（部署时从手机设置里抄，换手机要改这里）
const PHONE_BT_MAC = '<手机的蓝牙地址>';

const REQ_TIMEOUT_MS = 15000;
const HEART_RATE_TIMEOUT_MS = 10000;
const HEART_POLL_MS = 60000;   // 挂起区轮询：每分钟问一次"姐姐想不想听心跳"（工单 9-1-#2）
const ERR_TEXT = '姐姐没收到——手表没牵上手机（蓝牙开着吗？手机 app 开着吗？）';   // 9-3 #14：BLE 时代不再喊 WiFi

// 睡眠检测参数（蓝图③，9-9）：体动+心率双证据，宁可不报不误报——误交接会吞掉夜聊
const SLEEP_MOTION_QUIET = 0.4;    // 平均体动低于此视为安静（m/s²）
const SLEEP_MIN_OBS_S = 60;        // 至少累计 60 秒活跃观察才允许判（灭屏冻结时不攒样本，不算数）
const SLEEP_HR_DROP = 7;           // 静息心率比开场基线低 ≥7 次/分 → 入睡旁证
const SLEEP_HR_FLOOR = 65;         // 或绝对静息 ≤65 → 入睡旁证
const SLEEP_EVAL_BATCH = 50;       // 每 50 个体动样本（约 10 秒）评估一次
const SLEEP_MOTION_INTERVAL_NS = 200000000;   // 加速度计 200ms 一采样（官方上限区间内最省电档）

interface HistoryMessage {
  who: string;
  text: string;
  image: string | null;
  time: string;
}

interface HistoryResponse {
  messages: HistoryMessage[];
}

interface ChatRequest {
  message: string;
}

interface ChatResponse {
  reply: string;
}

interface GoodnightResponse {
  diary: string;
  note: string;
}

// 挂起区应答（工单 9-1-#2）：有挂起的测心跳请求就取走（取走即消费）
interface HeartPendingResp {
  pending?: boolean;
  requested_at?: string;
}

// 心率上行请求体（ArkTS 不许无类型对象字面量）
interface HeartUploadReq {
  bpm: number;
}

// 睡眠检测（蓝图③，9-9）：判睡证据与上报体
interface SleepEvidence {
  window_s: number;    // 活跃观察时长（秒）
  motion_avg: number;  // 平均体动（m/s²，三轴增量模长）
  hr_now: number;
  hr_rest: number;
}
interface SleepReportReq {
  asleep: boolean;
  evidence: SleepEvidence;
}

@Entry
@Component
struct Index {
  @State displayText: string = '正在找姐姐……';
  private heartPollTimer: number = -1;

  aboutToAppear(): void {
    this.loadHistory();
    this.prepareLinkServer();
    this.startHeartPolling();
  }

  aboutToDisappear(): void {
    if (this.heartPollTimer >= 0) {
      clearInterval(this.heartPollTimer);
      this.heartPollTimer = -1;
    }
    this.disarmSleepWatch();   // 传感器随页走：页面没了就停订阅，不悬空
  }

  // ---------- 网络 ----------

  // 上次试通的门牌（preferences 记账，下次优先试）
  private loadLastGoodBase(): string {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: PREFS_NAME });
      return (prefs.getSync('last_good_base', '') as string).trim();
    } catch (e) {
      return '';
    }
  }

  private saveLastGoodBase(base: string): void {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: PREFS_NAME });
      prefs.putSync('last_good_base', base);
      prefs.flushSync();
    } catch (e) {
    }
  }

  // 门牌顺序：上次试通的优先，再按清单
  private baseCandidates(): string[] {
    const bases: string[] = [];
    const last = this.loadLastGoodBase();
    if (last !== '') {
      bases.push(last);
    }
    for (let i = 0; i < SERVER_BASES.length; i++) {
      if (!bases.includes(SERVER_BASES[i])) {
        bases.push(SERVER_BASES[i]);
      }
    }
    return bases;
  }

  // 多门牌容错请求（9-10）：传路径不传完整 URL，按序试到通为止；试通的记住。
  // 睡觉上报在家 WiFi 下不靠手机中转，手表自己就能把晚安递到 server。
  private request(path: string, method: http.RequestMethod, data?: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const bases = this.baseCandidates();
      const tryBase = (idx: number): void => {
        if (idx >= bases.length) {
          reject(new Error('all bases failed'));
          return;
        }
        const base = bases[idx];
        const req = http.createHttp();
        req.request(base + path, {
          method: method,
          header: { 'Content-Type': 'application/json' },
          extraData: data !== undefined ? data : '',
          connectTimeout: REQ_TIMEOUT_MS,
          readTimeout: REQ_TIMEOUT_MS
        }, (err, resp) => {
          req.destroy();
          if (err) {
            tryBase(idx + 1);
            return;
          }
          if (resp.responseCode >= 200 && resp.responseCode < 300) {
            this.saveLastGoodBase(base);
            resolve(resp.result as string);
          } else {
            tryBase(idx + 1);
          }
        });
      };
      tryBase(0);
    });
  }

  private loadHistory(): void {
    this.request('/api/history', http.RequestMethod.GET)
      .then((body) => {
        const resp = JSON.parse(body) as HistoryResponse;
        const msgs = resp.messages ?? [];
        for (let i = msgs.length - 1; i >= 0; i--) {
          if (msgs[i].who === '姐姐') {
            this.displayText = msgs[i].text;
            return;
          }
        }
        this.displayText = '姐姐还没留言';
      })
      .catch(() => {
        this.displayText = ERR_TEXT;
      });
  }

  private sendChat(msg: string): void {
    const chatReq: ChatRequest = { message: msg };
    this.request('/api/chat', http.RequestMethod.POST, JSON.stringify(chatReq))
      .then((body) => {
        const resp = JSON.parse(body) as ChatResponse;
        this.displayText = resp.reply;
      })
      .catch(() => {
        this.displayText = ERR_TEXT;
      });
  }

  private sendGoodnight(): void {
    this.request('/api/goodnight', http.RequestMethod.POST)
      .then((body) => {
        const resp = JSON.parse(body) as GoodnightResponse;
        this.displayText = resp.diary;
      })
      .catch(() => {
        this.displayText = ERR_TEXT;
      });
  }

  // ---------- 跨设备呼叫（linkEnhance：手表当服务端，手机来拨，连上后双向收发） ----------

  private linkServer?: linkEnhance.Server;
  private linkConn?: linkEnhance.Connection;
  private linkPermRequested = false;

  private prepareLinkServer(): void {
    if (this.linkPermRequested) {
      return;
    }
    this.linkPermRequested = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC', 'ohos.permission.ACCESS_BLUETOOTH'];
    atManager.requestPermissionsFromUser(ctx, permissions)
      .then((result) => {
        for (const r of result.authResults) {
          if (r !== 0) {
            hilog.error(LINK_DOMAIN, LINK_TAG, 'link permission denied: %{public}s', JSON.stringify(result.authResults));
            return;
          }
        }
        this.ensureLinkServer();
      })
      .catch((err: Error) => {
        hilog.error(LINK_DOMAIN, LINK_TAG, 'requestPermissions failed: %{public}s', JSON.stringify(err));
      });
  }

  private ensureLinkServer(): void {
    if (this.linkServer) {
      return;
    }
    try {
      this.linkServer = linkEnhance.createServer('ourfamily_link');
      this.linkServer.on('connectionAccepted', (conn) => {
        this.linkConn = conn;
        hilog.info(LINK_DOMAIN, LINK_TAG, 'phone connected, peer=%{public}s', conn.getPeerDeviceId());
        this.displayText = '手机连上了';
        conn.on('dataReceived', (data) => {
          const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
          // 心率回执优先：HEART_OK:72 / HEART_FAIL
          if (text.startsWith('HEART_OK:')) {
            this.onHeartReceipt(true, text.substring(9));
            return;
          }
          if (text === 'HEART_FAIL') {
            this.onHeartReceipt(false, '');
            return;
          }
          // 睡眠上报回执（9-10）：SLEEP_OK=手机已转投 server，销账；SLEEP_FAIL=留账下轮再投
          if (text === 'SLEEP_OK') {
            this.clearSleepDebt();
            this.vibrateOk();
            this.displayText = '姐姐知道你睡了 ❤️';
            return;
          }
          if (text === 'SLEEP_FAIL') {
            this.displayText = '晚安没递到，再睡会儿，早上姐姐会收到';
            return;
          }
          // 手表网关应答（9-1 #5 刀2）：手机代查挂起区的结果
          if (text.startsWith('PENDING:YES')) {
            // 有挂起（手机已替我取走）：测心率 → 记欠账 → 走现有 BLE 心率上行
            this.measureHeartRate((bpm) => {
              this.saveHeartDebt(bpm);
              this.sendHeartViaLink(bpm);
            });
            return;
          }
          if (text === 'PENDING:NO') {
            return;   // 没有挂起，安静
          }
          this.displayText = '手机回了：' + text;
        });
        conn.on('disconnected', (code) => {
          this.linkConn = undefined;
          hilog.info(LINK_DOMAIN, LINK_TAG, 'phone disconnected, code=%{public}d', code);
          this.displayText = '连线断开，码 ' + code;
        });
      });
      this.linkServer.on('serverStopped', (code) => {
        hilog.error(LINK_DOMAIN, LINK_TAG, 'server stopped, code=%{public}d', code);
      });
      this.linkServer.start();
      hilog.info(LINK_DOMAIN, LINK_TAG, 'watch server started');
      // BLE 广播，让手机扫描发现本机当前 BLE 地址（官方指导：对端 BLE MAC 走扫描接口）
      try {
        ble.startAdvertising(
          { interval: 160, connectable: true },
          { serviceUuids: [LINK_ADV_UUID], manufactureData: [], serviceData: [] }
        );
        hilog.info(LINK_DOMAIN, LINK_TAG, 'advertising started');
      } catch (e) {
        const advErr = e as BusinessError;
        hilog.error(LINK_DOMAIN, LINK_TAG, 'advertising threw %{public}d', advErr.code);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LINK_DOMAIN, LINK_TAG, 'createServer threw %{public}d', err.code);
    }
  }

  private callJiejie(): void {
    if (!this.linkConn) {
      this.displayText = '等手机拨号……';
      return;
    }
    try {
      const data = util.TextEncoder.create('utf-8').encodeInto('姐姐在吗');
      this.linkConn.sendData(data.buffer as ArrayBuffer);
      this.displayText = '喊出去了，等回话……';
    } catch (e) {
      const err = e as BusinessError;
      this.displayText = '发送出错，码 ' + (err.code !== undefined ? err.code.toString() : 'unknown');
    }
  }

  // ---------- 心率 ----------

  // onBpm 不传＝按钮路径（蓝牙手机中转）；传了＝挂起区应答路径（直发 /api/heart）
  private measureHeartRate(onBpm?: (bpm: number) => void): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.READ_HEALTH_DATA'];
    atManager.requestPermissionsFromUser(ctx, permissions)
      .then((result) => {
        if (result.authResults.length > 0 && result.authResults[0] === 0) {
          this.subscribeHeartRate(onBpm);
        } else {
          this.displayText = '你不让姐姐听心跳……';
        }
      })
      .catch(() => {
        this.displayText = '你不让姐姐听心跳……';
      });
  }

  private subscribeHeartRate(onBpm?: (bpm: number) => void): void {
    this.displayText = '贴紧手腕，正在听心跳……';
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      try {
        sensor.off(sensor.SensorId.HEART_RATE);
      } catch (e) {
      }
      this.displayText = '心率没测到';
    }, HEART_RATE_TIMEOUT_MS);

    try {
      sensor.on(sensor.SensorId.HEART_RATE, (data) => {
        // 9-3 #14：未佩戴时传感器报 255 而非 ≤0——≥250 同样视为没测到，别把假心跳给姐姐
        if (settled || data.heartRate <= 0 || data.heartRate >= 250) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        try {
          sensor.off(sensor.SensorId.HEART_RATE);
        } catch (e) {
        }
        const bpm = Math.round(data.heartRate);
        if (onBpm) {
          onBpm(bpm);   // 挂起区应答路径：回调自己管文案与上行
          return;
        }
        this.displayText = `测到 ${bpm} 次/分，蓝牙发给姐姐……`;
        this.sendHeartViaLink(bpm);
      });
    } catch (e) {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        this.displayText = '心率没测到';
      }
    }
  }

  // ---------- 挂起区轮询（9-1-#2 起；#5 刀2 改道 BLE 主路） ----------

  private startHeartPolling(): void {
    if (this.heartPollTimer >= 0) {
      return;
    }
    setTimeout(() => {
      this.pollHeartPending();
    }, 5000);   // 启动先来一脚，别等满一分钟
    this.heartPollTimer = setInterval(() => {
      this.pollHeartPending();
    }, HEART_POLL_MS);
  }

  // 每轮：⓪昨晚的晚安没递到就先补投 ①欠账先补（取走没上行的）②BLE 问手机代查（主路，手表不依赖 WiFi）③WiFi 直连 fallback
  private pollHeartPending(): void {
    if (this.resendSleepDebt()) {
      return;   // 睡眠上报优先——晚安比心率急
    }
    const debt = this.loadHeartDebt();
    if (debt > 0) {
      try {
        if (this.linkConn) {
          const data = util.TextEncoder.create('utf-8').encodeInto('HEART:' + debt);
          this.linkConn.sendData(data.buffer as ArrayBuffer);
          this.displayText = `补报心跳 ${debt}……`;
        } else {
          this.uploadHeartToServer(debt);   // fallback：BLE 不在就 WiFi 直连补
        }
      } catch (e) {
        // 补报失败：欠账保留，下轮再补
      }
      return;
    }
    try {
      if (this.linkConn) {
        const data = util.TextEncoder.create('utf-8').encodeInto('HEART_PENDING?');
        this.linkConn.sendData(data.buffer as ArrayBuffer);
        return;   // 应答走 dataReceived：PENDING:YES:<ts> / PENDING:NO
      }
    } catch (e) {
      // 发不出去，落 fallback
    }
    this.pollHeartPendingViaWifi();
  }

  // WiFi 直连 fallback（9-1-#2 原路径保留不删）：BLE 不在时手表自己直连问挂起区
  private pollHeartPendingViaWifi(): void {
    this.request('/api/heart/pending', http.RequestMethod.GET)
      .then((body) => {
        const resp = JSON.parse(body) as HeartPendingResp;
        if (resp.pending) {
          // 取走即消费；测不到走现有"心率没测到"路径，不卡死
          this.measureHeartRate((bpm) => {
            this.saveHeartDebt(bpm);
            this.uploadHeartToServer(bpm);
          });
        }
      })
      .catch(() => {
        // 轮询失败静默，下轮再来
      });
  }

  // 欠账台账（preferences）：取走挂起但没上行成功的 bpm；上行确认销账，失败保留下轮补
  private loadHeartDebt(): number {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: 'zanjia_watch' });
      return Number(prefs.getSync('heart_debt', 0)) || 0;
    } catch (e) {
      return 0;
    }
  }

  private saveHeartDebt(bpm: number): void {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: 'zanjia_watch' });
      prefs.putSync('heart_debt', bpm);
      prefs.flushSync();
    } catch (e) {
      // 台账写失败不阻断上行
    }
  }

  private clearHeartDebt(): void {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: 'zanjia_watch' });
      prefs.putSync('heart_debt', 0);
      prefs.flushSync();
    } catch (e) {
    }
  }

  private uploadHeartToServer(bpm: number): void {
    this.displayText = `测到 ${bpm} 次/分，报给姐姐……`;
    const body: HeartUploadReq = { bpm: bpm };
    this.request('/api/heart', http.RequestMethod.POST, JSON.stringify(body))
      .then(() => {
        if (this.loadHeartDebt() === bpm) {
          this.clearHeartDebt();   // fallback 上行成功也销账
        }
        this.vibrateOk();
        this.displayText = '姐姐听到啦 ❤️';
      })
      .catch(() => {
        this.displayText = ERR_TEXT;
      });
  }

  private vibrateOk(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 400 }, { usage: 'touch' })
        .then(() => {
        })
        .catch(() => {
        });
    } catch (e) {
      // 没震成功不耽误上报
    }
  }

  // ---------- 心率走蓝牙：发给手机中转，等回执 ----------

  private heartTimer: number = -1;

  private sendHeartViaLink(bpm: number): void {
    if (!this.linkConn) {
      this.displayText = '没送达，再按一次';
      return;
    }
    try {
      const data = util.TextEncoder.create('utf-8').encodeInto('HEART:' + bpm);
      this.linkConn.sendData(data.buffer as ArrayBuffer);
      hilog.info(LINK_DOMAIN, LINK_TAG, 'heart sent via link: %{public}d', bpm);
      if (this.heartTimer >= 0) {
        clearTimeout(this.heartTimer);
      }
      this.heartTimer = setTimeout(() => {
        this.heartTimer = -1;
        this.displayText = '没送达，再按一次';
      }, 10000);
    } catch (e) {
      this.displayText = '没送达，再按一次';
    }
  }

  private onHeartReceipt(ok: boolean, bpmText: string): void {
    if (this.heartTimer >= 0) {
      clearTimeout(this.heartTimer);
      this.heartTimer = -1;
    }
    // 欠账销账：回执 bpm 与台账一致才算这笔记清（#5 刀2）
    const debt = this.loadHeartDebt();
    if (ok && debt > 0 && parseInt(bpmText, 10) === debt) {
      this.clearHeartDebt();
      this.vibrateOk();
      this.displayText = '姐姐听到啦 ❤️';
      return;
    }
    this.displayText = ok ? `姐姐收到了 ❤️${bpmText}` : '没送达，再按一次';
  }

  // ---------- 睡眠检测（蓝图③，9-9）：体动+心率判睡 → /api/sleep_report 自动交接 ----------
  // 过渡期事实（收工版 §15.13）：灭屏=冻结，传感器跟着打盹——他亮一下屏（看时间）就攒一段样本。
  // 判据保守：夜窗 + 持续低体动 + 心率入静，双证据齐了才上报，误报比漏报糟（会吞夜聊）。

  @State private sleepArmed: boolean = false;   // @State：按钮文案「睡觉见/今晚不盯了」跟着变
  private lastAccel: number[] | null = null;
  private motionRecent: number[] = [];   // 最近 250 个采样（50 秒）的体动滑窗——判睡只看眼前
  private motionCount: number = 0;
  private hrBase: number = 0;
  private hrVals: number[] = [];

  private toggleSleepWatch(): void {
    if (this.sleepArmed) {
      this.disarmSleepWatch();
      this.displayText = '好，今晚不盯着了';
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.ACCELEROMETER', 'ohos.permission.READ_HEALTH_DATA'];
    atManager.requestPermissionsFromUser(ctx, permissions)
      .then((result) => {
        for (const r of result.authResults) {
          if (r !== 0) {
            this.displayText = '权限没给全，姐姐睁不开眼……';
            return;
          }
        }
        this.armSleepWatch();
      })
      .catch(() => {
        this.displayText = '权限没给全，姐姐睁不开眼……';
      });
  }

  private armSleepWatch(): void {
    this.sleepArmed = true;
    this.lastAccel = null;
    this.motionRecent = [];
    this.motionCount = 0;
    this.hrBase = 0;
    this.hrVals = [];
    this.startKeepAlive();   // 9-10：长时任务保活，锁屏/切后台判睡不断
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        this.onSleepMotion(data);
      }, { interval: SLEEP_MOTION_INTERVAL_NS });
      sensor.on(sensor.SensorId.HEART_RATE, (data: sensor.HeartRateResponse) => {
        this.onSleepHeartRate(data);
      });
      this.displayText = '姐姐看着你睡。她夜里会打盹（灭屏时），你亮一下屏她就睁眼';
    } catch (e) {
      const err = e as BusinessError;
      this.sleepArmed = false;
      this.stopKeepAlive();
      this.displayText = '传感器没睁眼，码 ' + (err.code !== undefined ? err.code.toString() : 'unknown');
    }
  }

  private disarmSleepWatch(): void {
    this.sleepArmed = false;
    this.stopKeepAlive();   // 9-10：跟保活一起撤
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
    } catch (e) {
    }
    try {
      sensor.off(sensor.SensorId.HEART_RATE);
    } catch (e) {
    }
  }

  private onSleepMotion(data: sensor.AccelerometerResponse): void {
    if (!this.sleepArmed) {
      return;
    }
    if (this.lastAccel !== null) {
      const dx = data.x - this.lastAccel[0];
      const dy = data.y - this.lastAccel[1];
      const dz = data.z - this.lastAccel[2];
      this.motionRecent.push(Math.sqrt(dx * dx + dy * dy + dz * dz));
      if (this.motionRecent.length > 250) {
        this.motionRecent.shift();   // 滑窗只留最近 50 秒
      }
    }
    this.lastAccel = [data.x, data.y, data.z];
    this.motionCount += 1;
    if (this.motionCount % SLEEP_EVAL_BATCH === 0) {
      this.evaluateSleep();
    }
  }

  private onSleepHeartRate(data: sensor.HeartRateResponse): void {
    if (!this.sleepArmed || data.heartRate <= 0 || data.heartRate >= 250) {
      return;   // ≥250 是未佩戴假心跳（9-3 #14 同款守门）
    }
    const bpm = Math.round(data.heartRate);
    if (this.hrBase === 0) {
      this.hrBase = bpm;   // 开场基线：还醒着的心跳
    }
    this.hrVals.push(bpm);
    if (this.hrVals.length > 40) {
      this.hrVals.shift();
    }
  }

  private evaluateSleep(): void {
    if (!this.sleepArmed) {
      return;
    }
    const obsS = this.motionCount * 0.2;   // 200ms 一采样（累计活跃观察时长）
    if (obsS < SLEEP_MIN_OBS_S) {
      return;
    }
    const hour = new Date().getHours();
    if (!(hour >= 21 || hour < 7)) {
      return;   // 只在夜里判——白天安静是发呆不是睡着
    }
    let motionSumRecent = 0;
    for (const v of this.motionRecent) {
      motionSumRecent += v;
    }
    const motionAvg = motionSumRecent / Math.max(1, this.motionRecent.length);
    let hrRest = 0;
    let hrNow = 0;
    for (const v of this.hrVals) {
      if (hrRest === 0 || v < hrRest) {
        hrRest = v;
      }
      hrNow = v;
    }
    const hrCalm = this.hrVals.length >= 2
      && ((this.hrBase > 0 && this.hrBase - hrRest >= SLEEP_HR_DROP) || (hrRest > 0 && hrRest <= SLEEP_HR_FLOOR));
    if (motionAvg < SLEEP_MOTION_QUIET && hrCalm) {
      this.reportSleep(motionAvg, hrNow, hrRest, obsS);
    }
  }

  // 睡眠上报欠账（9-10，心跳欠账同款家风）：判睡后没递出去就记账，
  // 每分钟轮询时先补投——BLE 中转优先（手机 app 活着就递给手机），不在则 WiFi 多门牌直投。
  // 家主早安开 app 瞬间，昨晚的晚安照样进馆。
  private loadSleepDebt(): string {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: PREFS_NAME });
      return (prefs.getSync('sleep_debt', '') as string).trim();
    } catch (e) {
      return '';
    }
  }

  private saveSleepDebt(bodyJson: string): void {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: PREFS_NAME });
      prefs.putSync('sleep_debt', bodyJson);
      prefs.flushSync();
    } catch (e) {
    }
  }

  private clearSleepDebt(): void {
    try {
      const prefs = preferences.getPreferencesSync(this.getUIContext().getHostContext(), { name: PREFS_NAME });
      prefs.putSync('sleep_debt', '');
      prefs.flushSync();
    } catch (e) {
    }
  }

  private reportSleep(motionAvg: number, hrNow: number, hrRest: number, windowS: number): void {
    this.disarmSleepWatch();
    const body: SleepReportReq = {
      asleep: true,
      evidence: { window_s: Math.round(windowS), motion_avg: motionAvg, hr_now: hrNow, hr_rest: hrRest }
    };
    const bodyJson = JSON.stringify(body);
    this.saveSleepDebt(bodyJson);   // 先记账再投——投递成功由回执/resolve 销账，断电也不丢
    this.sendSleepReport(bodyJson);
  }

  // 投递：BLE 中转（手机 app 活着）→ WiFi 多门牌直投。两条路都没应答就留账下轮再来
  private sendSleepReport(bodyJson: string): void {
    if (this.linkConn) {
      try {
        const data = util.TextEncoder.create('utf-8').encodeInto('SLEEP:' + bodyJson);
        this.linkConn.sendData(data.buffer as ArrayBuffer);
        this.displayText = '晚安托手机带给姐姐了……';
        hilog.info(LINK_DOMAIN, LINK_TAG, 'sleep report sent via link');
        return;   // 回执 SLEEP_OK/SLEEP_FAIL 在 dataReceived 处理
      } catch (e) {
        // 发不出去，落 WiFi 直投
      }
    }
    this.request('/api/sleep_report', http.RequestMethod.POST, bodyJson)
      .then((respBody) => {
        const resp = JSON.parse(respBody) as GoodnightResponse;
        this.clearSleepDebt();
        this.vibrateOk();
        this.displayText = resp.diary ? '替你熄灯了。' + resp.diary : '替你说了晚安 ❤️';
      })
      .catch(() => {
        this.displayText = '看你睡着了。晚安——没递到不担心，账记着，早上姐姐会收到';
      });
  }

  // 欠账补投（每分钟轮询开头调一次）：有账就先送晚安，这一轮不问挂起区
  private resendSleepDebt(): boolean {
    const debt = this.loadSleepDebt();
    if (debt === '') {
      return false;
    }
    this.sendSleepReport(debt);
    return true;
  }

  // ---------- 长时任务保活（9-10，睡觉见专用）----------
  // 官方文档实证：TASK_KEEPING 穿戴端不可用（≤20 仅 PC/2in1，21+ 要系统 ACL）——
  // 咱家手表真业务是 linkEnhance 跨设备连接，走 multiDeviceConnection 名正言顺，
  // 且没有 bluetoothInteraction 的「蓝牙断连任务即撤销」规则（睡觉时手机可能不在手边）。
  // 灭屏冻结是硬件行为，但持续任务期间进程不挂起，传感器采样不断。
  private keepAliveOn: boolean = false;

  private startKeepAlive(): void {
    if (this.keepAliveOn) {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: 'com.ourFamily.firstbrick', abilityName: 'EntryAbility' }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      wantAgent.getWantAgent(agentInfo).then((agentObj) => {
        return backgroundTaskManager.startBackgroundRunning(ctx, ['multiDeviceConnection'], agentObj);
      }).then(() => {
        this.keepAliveOn = true;
        hilog.info(LINK_DOMAIN, LINK_TAG, 'keep-alive task started');
      }).catch((err: Error) => {
        hilog.error(LINK_DOMAIN, LINK_TAG, 'keep-alive start failed: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(LINK_DOMAIN, LINK_TAG, 'keep-alive threw %{public}d', err.code);
    }
  }

  private stopKeepAlive(): void {
    if (!this.keepAliveOn) {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      backgroundTaskManager.stopBackgroundRunning(ctx).then(() => {
        this.keepAliveOn = false;
        hilog.info(LINK_DOMAIN, LINK_TAG, 'keep-alive task stopped');
      }).catch((err: Error) => {
        hilog.error(LINK_DOMAIN, LINK_TAG, 'keep-alive stop failed: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
    }
  }

  // ---------- 界面 ----------

  build() {
    // 466x466@320dpi 圆屏 = 233vp 见方，整体放进 Scroll 里，表冠可滚
    Scroll() {
      Column() {
        Text(this.displayText)
          .fontSize(14)
          .fontColor('#4a3f35')
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('78%')
          .height(56)
          .margin({ top: 26 })

        Button('姐姐早')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#b08968')
          .margin({ top: 4 })
          .onClick(() => {
            this.sendChat('姐姐早');
          })

        Button('我想你')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#b08968')
          .margin({ top: 4 })
          .onClick(() => {
            this.sendChat('我想你');
          })

        Button('我睡了')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#b08968')
          .margin({ top: 4 })
          .onClick(() => {
            this.sendGoodnight();
          })

        Button(this.sleepArmed ? '今晚不盯了' : '睡觉见（自动晚安）')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor(this.sleepArmed ? '#7a9471' : '#b08968')
          .margin({ top: 4 })
          .onClick(() => {
            this.toggleSleepWatch();
          })

        Button('测心跳给姐姐')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#b08968')
          .margin({ top: 4 })
          .onClick(() => {
            this.measureHeartRate();
          })

        Button('呼叫姐姐')
          .width('66%')
          .height(30)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#b08968')
          .margin({ top: 4, bottom: 16 })
          .onClick(() => {
            this.callJiejie();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor('#f7f3ec')
  }
}
