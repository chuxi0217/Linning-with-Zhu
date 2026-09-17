import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { linkEnhance } from '@kit.DistributedServiceKit';
import { ble } from '@kit.ConnectivityKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';

const DOMAIN = 0x0000;
const TAG = 'ourFamily';

// 咱家跨设备广播用的自定义服务 UUID（扫描手表广播拿到它当前的 BLE 地址）
const LINK_ADV_UUID = '0000FA51-0000-1000-8000-00805F9B34FB';
const SCAN_TIMEOUT_MS = 15000;
// 心率中转：走手机 app 现有 server 地址（与聊天主链路同一个）
// 9-1-#8 刀3 地址收编：设置页换门牌存 preferences，这里每次中转前重读
const DEFAULT_SERVER = 'https://node.your-door.ts.net';
let SERVER_BASE = DEFAULT_SERVER;
let HEART_URL = DEFAULT_SERVER + '/api/heart';
// 手表网关：代查挂起区（9-1 #5 刀 2）。GET /pending 取走即消费=替手表取走
let HEART_PENDING_URL = DEFAULT_SERVER + '/api/heart/pending';
// 睡眠上报中转（9-10）：手表判睡后 BLE 托手机转投 server（手机 app 活着就行，
// 不要求手表有 WiFi）——SLEEP:{json} 进来，SLEEP_OK/SLEEP_FAIL 回执
let SLEEP_URL = DEFAULT_SERVER + '/api/sleep_report';
const HEART_TIMEOUT_MS = 15000;

interface HeartReq {
  bpm: number;
}

interface SleepEvidence {
  window_s: number;
  motion_avg: number;
  hr_now: number;
  hr_rest: number;
}

interface SleepReportReq {
  asleep: boolean;
  evidence: SleepEvidence;
}

interface PushTokenReq {
  token: string;
}

interface PendingResp {
  pending?: boolean;
  requested_at?: string;
}

export default class EntryAbility extends UIAbility {
  private linkConn?: linkEnhance.Connection;
  private scanSettled = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    this.startLinkClient();
    this.setupPush();
  }

  // Push Kit 门铃（9-2 #13）：启动即 getToken——官方姿势：token 只在重装等场景变化，
  // 没有 tokenRefresh 回调，「启动比对 + 变了才上报」就是 HarmonyOS 上的刷新监听等价物
  private setupPush(): void {
    try {
      notificationManager.requestEnableNotification(this.context).then(() => {
        hilog.info(DOMAIN, TAG, '通知授权已开');
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, '通知授权被拒: %{public}s', JSON.stringify(err));
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestEnableNotification threw: %{public}s', JSON.stringify(e));
    }
    pushService.getToken().then((token: string) => {
      if (!token) {
        hilog.error(DOMAIN, TAG, 'getToken 返回空');
        return;
      }
      let cached = '';
      try {
        const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
        cached = (prefs.getSync('push_token', '') as string);
      } catch (e) {
      }
      if (token === cached) {
        hilog.info(DOMAIN, TAG, 'push token 无变化，不上报');
        return;
      }
      hilog.info(DOMAIN, TAG, 'push token 新拿到（前 8 位 %{public}s…），上报 server', token.substring(0, 8));
      this.reportPushToken(token);
    }).catch((err: Error) => {
      // 1000900010 = AGC 侧没配证书指纹/没开推送服务，去 hilog 看这条
      hilog.error(DOMAIN, TAG, 'getToken failed: %{public}s', JSON.stringify(err));
    });
  }

  // token 变了 → POST /api/push_token，server 同刻只留一条；上报成功才写本地缓存
  private reportPushToken(token: string): void {
    this.refreshServerUrls();
    const req = http.createHttp();
    const body: PushTokenReq = { token: token };
    req.request(SERVER_BASE + '/api/push_token', {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify(body),
      connectTimeout: HEART_TIMEOUT_MS,
      readTimeout: HEART_TIMEOUT_MS
    }, (err, resp) => {
      req.destroy();
      if (err) {
        hilog.error(DOMAIN, TAG, 'push token 上报失败: %{public}s', JSON.stringify(err));
        return;
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        try {
          const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
          prefs.putSync('push_token', token);
          prefs.flush();
        } catch (e) {
        }
        hilog.info(DOMAIN, TAG, 'push token 已上报 server');
      } else {
        hilog.error(DOMAIN, TAG, 'push token 上报 http %{public}d', resp.responseCode);
      }
    });
  }

  // 跨设备通道客户端：BLE 扫描找到手表（手表在广播 LINK_ADV_UUID），拿到它当前 BLE 地址后拨号（官方指导路径，无 UI）
  private startLinkClient(): void {
    const ctx = this.context as common.UIAbilityContext;
    const atManager = abilityAccessCtrl.createAtManager();
    const permissions: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC', 'ohos.permission.ACCESS_BLUETOOTH'];
    atManager.requestPermissionsFromUser(ctx, permissions)
      .then((result) => {
        for (const r of result.authResults) {
          if (r !== 0) {
            hilog.error(DOMAIN, TAG, 'link permission denied: %{public}s', JSON.stringify(result.authResults));
            return;
          }
        }
        this.scanAndDial();
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}s', JSON.stringify(err));
      });
  }

  private scanAndDial(): void {
    this.scanSettled = false;
    setTimeout(() => {
      if (this.scanSettled) {
        return;
      }
      this.scanSettled = true;
      try {
        ble.stopBLEScan();
      } catch (e) {
      }
      hilog.error(DOMAIN, TAG, 'scan timeout, watch not found');
      // 9-3 #14：起得太早手表还没开就会永远错过——60s 后重新扫，直到牵上手
      setTimeout(() => {
        this.scanAndDial();
      }, 60000);
    }, SCAN_TIMEOUT_MS);

    try {
      ble.on('BLEDeviceFind', (results) => {
        if (this.scanSettled || results.length === 0) {
          return;
        }
        this.scanSettled = true;
        try {
          ble.stopBLEScan();
        } catch (e) {
        }
        const mac = results[0].deviceId;
        hilog.info(DOMAIN, TAG, 'found watch by scan: %{public}s', mac);
        this.dialWatch(mac);
      });
      const filter: ble.ScanFilter = { serviceUuid: LINK_ADV_UUID };
      const scanOptions: ble.ScanOptions = { interval: 0, dutyMode: ble.ScanDuty.SCAN_MODE_LOW_LATENCY };
      ble.startBLEScan([filter], scanOptions);
      hilog.info(DOMAIN, TAG, 'scanning for watch...');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'startBLEScan failed: %{public}s', JSON.stringify(e));
    }
  }

  private dialWatch(mac: string): void {
    try {
      this.linkConn = linkEnhance.createConnection(mac, 'ourfamily_link');
      this.linkConn.on('connectResult', (result) => {
        hilog.info(DOMAIN, TAG, 'dial %{public}s success=%{public}s reason=%{public}d',
          mac, JSON.stringify(result.success), result.reason);
      });
      this.linkConn.on('dataReceived', (data) => {
        const text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(data));
        hilog.info(DOMAIN, TAG, '手表说：%{public}s', text);
        if (text.startsWith('HEART:')) {
          this.relayHeart(text.substring(6));
          return;
        }
        if (text === 'HEART_PENDING?') {
          this.proxyHeartPending();   // 手表网关：代查挂起区
          return;
        }
        if (text.startsWith('SLEEP:')) {
          this.relaySleepReport(text.substring(6));   // 9-10：睡眠上报中转
          return;
        }
        try {
          const reply = util.TextEncoder.create('utf-8').encodeInto('在');
          this.linkConn?.sendData(reply.buffer as ArrayBuffer);
          hilog.info(DOMAIN, TAG, '已回：在');
        } catch (e) {
          hilog.error(DOMAIN, TAG, 'reply failed: %{public}s', JSON.stringify(e));
        }
      });
      this.linkConn.on('disconnected', (code) => {
        hilog.info(DOMAIN, TAG, 'watch disconnected, code=%{public}d', code);
        // 9-3 #14：断了就重新扫，把手牵回来
        this.scanAndDial();
      });
      this.linkConn.connect();
      hilog.info(DOMAIN, TAG, 'dialing %{public}s ...', mac);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'dial %{public}s threw: %{public}s', mac, JSON.stringify(e));
    }
  }

  // 蓝牙中转：手表心率 → POST /api/heart → 回执经蓝牙回手表
  private relayHeart(bpmText: string): void {
    this.refreshServerUrls();
    const bpm = parseInt(bpmText, 10);
    if (isNaN(bpm) || bpm <= 0) {
      hilog.error(DOMAIN, TAG, 'heart relay bad bpm: %{public}s', bpmText);
      this.replyToWatch('HEART_FAIL');
      return;
    }
    hilog.info(DOMAIN, TAG, 'heart relay posting bpm=%{public}d', bpm);
    const req = http.createHttp();
    const body: HeartReq = { bpm: bpm };
    req.request(HEART_URL, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify(body),
      connectTimeout: HEART_TIMEOUT_MS,
      readTimeout: HEART_TIMEOUT_MS
    }, (err, resp) => {
      req.destroy();
      if (err) {
        hilog.error(DOMAIN, TAG, 'heart relay http failed: %{public}s', JSON.stringify(err));
        this.replyToWatch('HEART_FAIL');
        return;
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        hilog.info(DOMAIN, TAG, 'heart relay ok, server: %{public}s', resp.result as string);
        this.replyToWatch('HEART_OK:' + bpm);
      } else {
        hilog.error(DOMAIN, TAG, 'heart relay http %{public}d', resp.responseCode);
        this.replyToWatch('HEART_FAIL');
      }
    });
  }

  private replyToWatch(text: string): void {
    try {
      const data = util.TextEncoder.create('utf-8').encodeInto(text);
      this.linkConn?.sendData(data.buffer as ArrayBuffer);
      hilog.info(DOMAIN, TAG, 'replied to watch: %{public}s', text);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'replyToWatch failed: %{public}s', JSON.stringify(e));
    }
  }

  // 睡眠上报中转（9-10）：手表判睡后 BLE 托手机转投 /api/sleep_report。
  // server 守门（夜窗/已睡/日记在）原样生效；回执 SLEEP_OK/SLEEP_FAIL，手表没收到回执
  // 会留欠账下轮补投——双保险，晚安不会丢在半路。
  private relaySleepReport(jsonText: string): void {
    this.refreshServerUrls();
    let body: SleepReportReq;
    try {
      body = JSON.parse(jsonText) as SleepReportReq;
      if (body.asleep !== true) {
        throw new Error('asleep not true');
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'sleep relay bad body');
      this.replyToWatch('SLEEP_FAIL');
      return;
    }
    hilog.info(DOMAIN, TAG, 'sleep relay posting evidence');
    const req = http.createHttp();
    req.request(SLEEP_URL, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify(body),
      connectTimeout: HEART_TIMEOUT_MS,
      readTimeout: HEART_TIMEOUT_MS
    }, (err, resp) => {
      req.destroy();
      if (err) {
        hilog.error(DOMAIN, TAG, 'sleep relay http failed: %{public}s', JSON.stringify(err));
        this.replyToWatch('SLEEP_FAIL');
        return;
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        hilog.info(DOMAIN, TAG, 'sleep relay ok');
        this.replyToWatch('SLEEP_OK');
      } else {
        // 4xx=server 守门拒收（白天/已睡/日记在）——也算递到了，别让手表无限补投
        if (resp.responseCode >= 400 && resp.responseCode < 500) {
          hilog.info(DOMAIN, TAG, 'sleep relay rejected %{public}d (守门)', resp.responseCode);
          this.replyToWatch('SLEEP_OK');
        } else {
          this.replyToWatch('SLEEP_FAIL');
        }
      }
    });
  }

  // 设置页换门牌后这边跟着走（9-1-#8 刀3）：每次中转前重读 preferences
  private refreshServerUrls(): void {
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
      SERVER_BASE = (prefs.getSync('server_base', '') as string).trim() || DEFAULT_SERVER;
      HEART_URL = SERVER_BASE + '/api/heart';
      HEART_PENDING_URL = SERVER_BASE + '/api/heart/pending';
      SLEEP_URL = SERVER_BASE + '/api/sleep_report';
    } catch (e) {
      // 读不到就用默认门牌
    }
  }

  // 手表网关（9-1 #5 刀 2）：手表问 HEART_PENDING? → 代查 GET /api/heart/pending
  // （取走即消费=替手表取走，取走时间戳进 hilog 台账）→ 回 PENDING:YES:<ts> / PENDING:NO
  private proxyHeartPending(): void {
    this.refreshServerUrls();
    const req = http.createHttp();
    req.request(HEART_PENDING_URL, {
      method: http.RequestMethod.GET,
      connectTimeout: HEART_TIMEOUT_MS,
      readTimeout: HEART_TIMEOUT_MS
    }, (err, resp) => {
      req.destroy();
      if (err) {
        hilog.error(DOMAIN, TAG, 'pending proxy http failed: %{public}s', JSON.stringify(err));
        this.replyToWatch('PENDING:NO');
        return;
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        try {
          const d = JSON.parse(resp.result as string) as PendingResp;
          if (d.pending) {
            hilog.info(DOMAIN, TAG, '手表网关取走挂起 at %{public}s', d.requested_at ?? '');
            this.replyToWatch('PENDING:YES:' + (d.requested_at ?? ''));
          } else {
            this.replyToWatch('PENDING:NO');
          }
        } catch (e) {
          this.replyToWatch('PENDING:NO');
        }
      } else {
        hilog.error(DOMAIN, TAG, 'pending proxy http %{public}d', resp.responseCode);
        this.replyToWatch('PENDING:NO');
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}