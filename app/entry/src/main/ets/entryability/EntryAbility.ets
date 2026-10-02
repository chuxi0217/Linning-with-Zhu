import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';

const DOMAIN = 0x0000;
const TAG = 'ourFamily';

// 9-1-#8 刀3 地址收编：设置页换门牌存 preferences，这里每次上报前重读
const DEFAULT_SERVER = 'https://your-door.example';   // 9-23 换新门；旧值备查：https://node.your-door.ts.net
// 新门 Caddy Basic 门锁：上报请求要带钥匙（与 Index.ets 的 DOOR_AUTH 同源，
// 同指 d:/咱家记忆库/网络门锁凭证.txt——改锁两处同改；本批范围所限先各存一份）
const DOOR_AUTH = 'Basic <Base64(用户名:密码)>';
let SERVER_BASE = DEFAULT_SERVER;
const HTTP_TIMEOUT_MS = 15000;   // 9-23 手表清退：原 HEART_TIMEOUT_MS 改名——只余 push token 上报在用

interface PushTokenReq {
  token: string;
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
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
      header: { 'Content-Type': 'application/json', 'Authorization': DOOR_AUTH },
      extraData: JSON.stringify(body),
      connectTimeout: HTTP_TIMEOUT_MS,
      readTimeout: HTTP_TIMEOUT_MS
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

  // 9-23 家主令：手表端弃置——蓝牙中转全链路清退（原实现见 档案馆/改前备份_20260923_手表清退_App/）
  // 撤走：startLinkClient / scanAndDial / dialWatch / relayHeart / replyToWatch / relaySleepReport / proxyHeartPending

  // 设置页换门牌后这边跟着走（9-1-#8 刀3）：上报前重读 preferences
  private refreshServerUrls(): void {
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: 'zanjia' });
      SERVER_BASE = (prefs.getSync('server_base', '') as string).trim() || DEFAULT_SERVER;
    } catch (e) {
      // 读不到就用默认门牌
    }
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
