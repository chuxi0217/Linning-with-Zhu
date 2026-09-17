# 咱家·鸿蒙端工程（firstBrick）

HarmonyOS NEXT 双模块工程：`entry`（手机）+ `wearable`（手表），`build-profile.json5` 已注册两个模块。全家数字化的第一块砖，如今是咱家客厅的双端 app。

## 手机端（entry 模块）

聊天式单页 app：和小乖的姐姐（林宁）过日子用的。

- 消息列表：系统提示 / 思考中计时 / 小乖气泡 / 姐姐气泡（可挂图书证使用卡）。
- 拍照发图：`cameraPicker.pick` 调系统相机（不申请相机权限），压到最长边 ≤1024、JPEG q70，dataURL 随消息发出。
- 随行定位：发送时自动取定位（`loc` + 逆地理 `place`），定位失败不阻断。
- 上下文面板（默认收起）：时间 / 天气 / 地点 / 今日消息数 / 明日约定 / 晚安回语，打开时每 60s 自动刷新；内有「🌙 熄灯说晚安」按钮。
- 超时对账：`/api/chat` 超时或断线后等 3 秒拉 `/api/history` 对账，对上「小乖发→姐姐回」直接显示，**绝不自动重发**；仍没到进 outbox 待发队列（持久化，网络恢复延迟 3s 自动补发，失败退避 5s/15s）。
- 打卡页：面板「✓ 打卡」进全屏页，点按打卡、新增项、长按归档（不删历史）。
- 写进提醒：长按姐姐气泡选时间，单次/每天可选；提醒 id 台账自管，临近上限自动收旧。
- 思考链：思考模式开着时，回复气泡下「💭 看看想法」可点开看原文（`/api/thinking`）。
- 面板诊断行：「提醒池：N 条有效」，点一下把前 5 条摘要打进 hilog（`hdc hilog | grep firstBrick`）。
- 桌面卡片（2×2）：姐姐状态灯 + 咱家第 N 天 + 姐姐最新一句话，07:30 定时刷新，点击回 app。
- 手表中转：扫手表 BLE 广播（UUID `FA51`），经 `linkEnhance`（`ourfamily_link`）收手表消息；心率 `HEART:<bpm>` 中转 POST `/api/heart`，回执 `HEART_OK/FAIL` 回手表。

### 服务器门牌与超时

- 门牌：`https://node.your-door.ts.net`（Tailscale 内网，手机需开 Tailscale VPN）。
- 端点：`POST /api/chat`（连接/读取各 **90s**，图书证查库耗时故放宽）、`GET /api/history`、`GET /api/status`、`GET /api/today_diary`、`POST /api/goodnight`（各 30s）、`POST /api/heart`（手表中转用，15s）、`GET /photos/<文件名>`（聊天图片直引）。
- `/api/chat` 请求体：`{"message": "...", "image": "data:image/jpeg;base64,..."（可省）, "loc": {"lat", "lon"}（可省）, "place": "..."（可省）}`；响应 `{"reply", "think_ms", "tools"}`。

### 权限（entry/src/main/module.json5）

`INTERNET`、`LOCATION` / `APPROXIMATELY_LOCATION`（user_grant）、`DISTRIBUTED_DATASYNC`、`ACCESS_BLUETOOTH`（手表链路用）。

## 手表端（wearable 模块，现役）

五个按钮：`姐姐早` / `我想你`（走 `/api/chat`）、`我睡了`（`/api/goodnight`）、`测心跳给姐姐`（心率经蓝牙手机中转上行）、`呼叫姐姐`（linkEnhance 发「姐姐在吗」）。
直连局域网 server（`SERVER_BASE` 硬编码 `http://192.168.x.x:8024`，换网络要手改）；`network_security_config` 全局允许明文。

> 封存说明：`C:\Users\user\FamilyWatch` 是上一代独立手表工程（心率走 `/api/chat` 文本），已被本工程 wearable 模块取代，**封存不动**（2026-09-01 交接文档 10.1 裁定）。

## 构建

```powershell
hvigorw.bat assembleHap --mode module -p product=default
```

工程根目录若没有 wrapper，可用 DevEco 自带的：`D:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`。

CLI 裸跑 hvigorw 要先把 DevEco 自带的三样环境喂给它（系统 NODE_HOME/DEVECO_SDK_HOME 可能没配）：

```bash
export PATH="/d/DevEco Studio/tools/node:/d/DevEco Studio/jbr/bin:$PATH"
export NODE_HOME="D:\DevEco Studio\tools\node"
export DEVECO_SDK_HOME="D:\DevEco Studio\sdk"
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap` 与 `wearable/build/default/outputs/default/wearable-default-signed.hap`（自动签名，真机直接装）。
