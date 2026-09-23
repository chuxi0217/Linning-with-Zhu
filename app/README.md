# 咱家·鸿蒙端工程（firstBrick）

HarmonyOS NEXT 双模块工程：`entry`（手机）+ `wearable`（手表，已弃置留档）。
全家数字化的第一块砖，如今是咱家客厅的 app。

## 手机端（entry 模块）

聊天式单页 app：和「姐姐」（示例人格：林宁）过日子用的。

- 消息列表：系统提示 / 思考中计时 / 小乖气泡 / 姐姐气泡（可挂图书证使用卡）。
- 拍照发图：`cameraPicker.pick` 调系统相机（不申请相机权限），压到最长边 ≤1024、JPEG q70，dataURL 随消息发出。
- 随行定位：发送时自动取定位（`loc` + 逆地理 `place`），定位失败不阻断。
- 上下文面板（默认收起）：时间 / 天气 / 地点 / 今日消息数 / 明日约定 / 晚安回语，打开时每 60s 自动刷新；内有「🌙 熄灯说晚安」按钮（晚安入口全家只此一枚）。
- 超时对账：`/api/chat` 超时或断线后等 3 秒拉 `/api/history` 对账，对上「小乖发→姐姐回」直接显示，**绝不自动重发**；仍没到进 outbox 待发队列（持久化，网络恢复延迟 3s 自动补发，失败退避 5s/15s）。
- 打卡页：面板「✓ 打卡」进全屏页，点按打卡、新增项、长按归档（不删历史）。
- 写进提醒：长按姐姐气泡选时间，单次/每天可选；提醒 id 台账自管，临近上限自动收旧。
- 思考链：思考模式开着时，回复气泡下「💭 看看想法」可点开看原文（`/api/thinking`）。
- 桌面卡片（2×2）：姐姐状态灯 + 咱家第 N 天 + 姐姐最新一句话，07:30 定时刷新，点击回 app。
- 书房：日记馆 / 两封信（帽 2000，保存写通「小乖的话.md」）/ 信箱 / 她的独处 / 共读（txt/md/epub）/ 档案馆 / 照片墙 / 门牌墙 / 周报（只读）。
- 手表相关（BLE 扫描、心率上报中转）已于 9-23 整链清退——见下。

### 服务器门牌与超时

- 门牌：`Index.ets` 顶部 `BASE_URL` 默认 `https://your-door.example`（**占位——换成你家的门牌**：
  VPS 域名 / Tailscale / 局域网 IP 都行；设置页可切换、带「测一测」探活）。
- 门锁（选配）：门牌若挂在 Caddy Basic 门锁后，所有请求带 `Authorization: Basic <Base64(用户名:密码)>`；
  图片走 `?token=<同一把密码>` 后门（Image 组件带不了请求头）。占位符在 `Index.ets` 顶部，钥匙自己保管、不进仓。
- 端点：`POST /api/chat`（连接/读取各 **90s**，图书证查库耗时故放宽）、`GET /api/history`、`GET /api/status`、`GET /api/today_diary`、`POST /api/goodnight`（各 30s）、`GET /photos/<文件名>`（图片直引，可带 `?token=`）。
- `/api/chat` 请求体：`{"message": "...", "image": "data:image/jpeg;base64,..."（可省）, "loc": {"lat", "lon"}（可省）, "place": "..."（可省）, "file": {"name","b64"}（可省，附件/epub）}`；响应 `{"reply", "think_ms", "tools"}`。

### 权限（entry/src/main/module.json5）

`INTERNET`、`LOCATION` / `APPROXIMATELY_LOCATION`（user_grant）。
（9-23 手表清退：`DISTRIBUTED_DATASYNC`、`ACCESS_BLUETOOTH` 已摘除。）

## 手表端（wearable 模块，已弃置留档）

原五个按钮（姐姐早 / 我想你 / 我睡了 / 测心跳给姐姐 / 呼叫姐姐）与 BLE 中转链路，已随手表端弃置
整体停用；手机侧中转代码、权限，以及服务端心率/睡眠端点与两只相关图书证，已于 9-23 清退干净。
`wearable/` 模块代码留档，等智能戒指接棒。

> 更早一代的独立手表工程已封存（2026-09-01 交接裁定），本工程 wearable 模块是它的并入版。

## 构建

```powershell
hvigorw.bat assembleHap --mode module -p product=default -p module=entry@default
```

工程根目录若没有 wrapper，可用 DevEco 自带的：`<DevEco 安装目录>/tools/hvigor/bin/hvigorw.bat`。

CLI 裸跑 hvigorw 要先把 DevEco 自带的三样环境喂给它（系统 NODE_HOME/DEVECO_SDK_HOME 可能没配）：

```bash
export PATH="<DevEco 安装目录>/tools/node:<DevEco 安装目录>/jbr/bin:$PATH"
export NODE_HOME="<DevEco 安装目录>\tools\node"
export DEVECO_SDK_HOME="<DevEco 安装目录>\sdk"
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`（自动签名，真机直接装；
签名配置请用 DevEco 自动生成——`build-profile.json5` 里已留占位说明，不随仓发布任何证书与口令）。
