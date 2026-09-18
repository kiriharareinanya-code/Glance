# 面板 IPC 协议

控制面板（WinUI3 原生程序 `panel.exe`）与核心（`glance.exe`，Flutter）之间的
通信协议。**核心是服务端，面板是客户端**。

---

## 为什么长这样

| 决定 | 原因 |
|---|---|
| 面板独立进程 | 面板要用 C++/WinUI3 重写；Flutter 与 WinUI3 抢同一个窗口/合成器，同进程不现实 |
| 核心做服务端 | 面板是按需启动的（点托盘"设置"），核心一直在跑。核心持有 token 与 socket 路径，启动面板时递过去，不需要"发现已运行实例"的逻辑 |
| **Unix domain socket** | 实测 Dart 在 Windows 上可用；没有端口占用、不弹防火墙、文件权限即访问控制、进程退出即释放。命名管道被排除——`dart:io` 没有对应 API |
| NDJSON 一行一帧 | 两侧都好实现（C++ 侧拿 `std::getline` 就能解析），能用 `nc`/日志直接看 |
| **schema 驱动** | 面板不硬编码任何设置项/插件：`plugins.list` 与 `settings.schema` 拉下来，按 `type` 渲染控件。**加插件、加设置项都不用改面板** |
| 不做热更新 | 面板与核心一起发版（Flutter 是 AOT，运行时加载不了 Dart 代码）。所以协议版本不匹配是开发期问题，不是线上问题 |

---

## 传输与握手

```
路径：<userdata>/panel.sock          # userdata = glance.exe 同目录下的 userdata\
                                      # 路径超过 100 字符时退到 %TEMP%\vectra-panel.sock
```

核心启动面板进程时**通过命令行**把端点信息递过去：

```
panel.exe --socket <path> --token <hex>
```

面板连上来后，**第一条消息必须是 `hello`**：

```jsonc
{"id":1,"m":"hello","p":{"protocol":1,"token":"<hex>"}}
```

- `token` 每次核心启动重新随机（32 位十六进制）。
- 校验失败 → 回一条错误后**直接断开**。
- **信任边界**：这挡住的是"同一用户下其他进程乱连"，不是跨用户攻击
  （同用户本来就能读对方内存）。设置面板这个量级够了。

> 开发期调试：核心会把 `{socket, token}` 写进 `<userdata>/panel-ipc.json`，
> `tool/panel_cli.dart` 与 `nc` 式的调试都靠它。生产环境这一份是给开发者用的，
> 面板进程本身不走这条路。

---

## 帧格式

```jsonc
// 请求（面板 → 核心）：id 由面板自己发号，用于配对响应
{"id":1,"m":"cards.list","p":{}}

// 响应（成功）
{"id":1,"ok":true,"r":{ /* 方法自己的返回体 */ }}

// 响应（失败）
{"id":1,"ok":false,"err":{"code":"bad_request","msg":"缺少参数 id"}}

// 事件（核心 → 面板，单方面推送，没有 id）
{"e":"cards.changed","p":{}}
```

**解析要求**（C++ 侧照着做）：

- 按 `\n` 切行；一行的 JSON 可能被 TCP/UDS 拆成多个读事件，**必须自己缓冲**。
- 收到不认识的 `e`（事件）**直接忽略**；收到不认识的方法名回 `unsupported`。
- 收到解析不了的行：回 `bad_request`，**不要断开**（除非是握手阶段）。
- 面板应当**容忍新增字段**（核心加字段不改版本号）。

### 错误码

| code | 含义 | 面板该怎么做 |
|---|---|---|
| `bad_request` | 参数缺失/类型不对/值非法 | 显示错误，修正参数后重试 |
| `no_handshake` | 没先 `hello` | 说明面板有 bug（连接会被断开） |
| `bad_token` | token 不对 | 提示"核心重启过"，重新由核心拉起 |
| `bad_version` | 协议版本不匹配 | 提示版本不匹配（不该出现在发行版里） |
| `not_found` | 卡片/插件/设置项不存在 | 刷新状态后重试 |
| `rejected` | 合法但被拒（如没有空闲屏可放卡） | 显示 msg 给用户 |
| `unsupported` | 核心没实现这个方法 | 隐藏对应入口 |
| `internal` | 核心侧异常 | 显示 msg（通常是 bug） |

### 版本

`hello` 里带 `protocol`。**不兼容改动 +1**（字段改名、语义变化、参数变化）；
加方法或加可选字段不改。不匹配就握手失败——比让某个方法神秘返回 null 好。

---

## 方法表

### 元信息

| 方法 | 参数 | 返回 |
|---|---|---|
| `hello` | `protocol` `token` | `{protocol, core:{version, displayVersion}}` |
| `app.info` | — | `{version, displayVersion, userDataDir, plugins, cards}` |
| `app.quit` | — | `{quitting:true}`（响应发出后退；走与托盘"退出"同一条路） |
| `panel.ping` | — | `{pong:true, t:<ms>}` |

### 插件

| 方法 | 参数 | 返回 |
|---|---|---|
| `plugins.list` | — | `{plugins:[PluginManifest…]}` |

`PluginManifest`：

```jsonc
{
  "id": "clock",                    // snake_case，稳定标识
  "name": "时钟",
  "version": "2.0.0",               // 插件自己的版本，与核心版本无关
  "description": "数字时钟与日期",
  "icon": "🕐",                     // 目前是 emoji；面板可直接渲染
  "sizes": ["2x2","3x2","3x3","4x2"],// 允许的卡片尺寸（grid 单位）
  "defaultSize": "2x2",
  "settings": [ /* 见"设置 schema" */ ]
}
```

### 全局设置

| 方法 | 参数 | 返回 |
|---|---|---|
| `settings.schema` | — | `{groups:[{id, title, fields:[…]}]}` |
| `settings.get` | — | `{values:{key:value, …}}` |
| `settings.set` | `key` `value` | `{key, value}`（`value` 是**归一化后**的值） |

### 卡片

| 方法 | 参数 | 返回 |
|---|---|---|
| `cards.list` | — | `{grid:{cell,gap}, displays:[…], cards:[…], canAdd:{pluginId:bool}}` |
| `cards.add` | `pluginId` | `{id, card}` |
| `cards.remove` | `id` | `{id}` |
| `cards.setSize` | `id` `size` | `{id, size}` |
| `cards.setSetting` | `id` `key` `value` | `{id, key}` |

`cards.list` 里的元素：

```jsonc
{
  "id": "c_1726…", "pluginId": "clock", "pluginName": "时钟",
  "size": "3x3", "sizes": ["2x2","3x3","4x2"],   // 这张卡可以改成哪些尺寸
  "x": 120, "y": 80,                              // 窗口内逻辑像素（左上角）
  "w": 348, "h": 348,                             // 按 grid.cell/gap 算出的像素尺寸
  "z": 1, "monitorId": "\\\\.\\DISPLAY1",
  "settings": {"seconds": false}
}
```

`displays` 元素：`{id, x, y, w, h}`（**虚拟屏物理像素**，设备名形如 `\\.\DISPLAY1`）。
面板画"我们的卡片摆在哪块屏"时用得上。

### 壁纸

| 方法 | 参数 | 返回 |
|---|---|---|
| `wallpaper.get` | — | `{source, dominant, brightness}` |

`dominant` 是 `#RRGGBB` 或 null（还没算出来）；`brightness` 是 0~1。

---

## 事件

| 事件 | 触发时机 |
|---|---|
| `cards.changed` | 卡片增删、改尺寸、改设置，或布局对账后位置变了 |
| `settings.changed` | 全局设置变化（含从托盘或 Flutter 面板改的） |
| `wallpaper.changed` | 壁纸或取色结果变化 |
| `activate` | 核心要求面板把自己拉到前台（用户又点了一次托盘"设置"） |

收到事件的正确反应是**重新拉一次相关状态**（`cards.list` / `settings.get`），
而不是试图从事件体里增量推断——事件体当前是空的，将来最多带"哪些 key 变了"
这类提示。这样语义简单、不会因为漏字段导致状态漂移。

---

## 设置 schema（面板渲染控件的依据）

`settings.schema` 返回分组（`appearance` 外观 / `layout` 布局 / `update` 更新），
每组一组字段。字段形状与插件的 `settings` **完全一致**：

```jsonc
{
  "key": "gridCell", "type": "number", "label": "网格单元",
  "desc": "卡片尺寸按格数乘以这个值",
  "min": 40, "max": 320, "step": 2,
  "value": 112                         // 当前值（面板用它初始化控件）
}
```

| type | 面板控件 | 附加字段 |
|---|---|---|
| `boolean` | 开关 | — |
| `number` | 滑条（按 min/max/step） | `min` `max` `step` |
| `text` | 文本框 | `placeholder`（可选） |
| `select` | 下拉框 | `options:[{value,label}]` |
| `color` | 取色器 | —（值形如 `#RRGGBB` 或 ARGB 整数） |

**面板不要自己校验后就写回**：核心侧会二次校验（越界夹到范围、select 值必须在
选项里、颜色必须是合法格式），非法值回 `bad_request`。以返回的归一化值为准。

---

## 典型流程

```
1. 核心启动 → 绑 socket → 写 panel-ipc.json
2. 用户点托盘"设置"
   核心：连着的面板？→ 推 activate；没有 → 启动 panel.exe（带 --socket/--token）
3. 面板：connect → hello → app.info + plugins.list + cards.list + settings.schema
4. 用户改"网格间距" → settings.set {key:"gridGap", value:20}
   → 核心写盘、重新布局、广播 settings.changed
5. 用户点"添加时钟" → cards.add {pluginId:"clock"} → 核心找落点放卡
   → 广播 cards.changed → 面板重新 cards.list
6. 用户关面板 → 面板进程退出（核心照常跑）
```

---

## 开发期怎么试

```bash
dart run tool/panel_cli.dart info          # 版本、插件数、卡片数
dart run tool/panel_cli.dart plugins       # 插件清单（含设置 schema）
dart run tool/panel_cli.dart schema        # 全局设置 schema
dart run tool/panel_cli.dart settings      # 读全部设置
dart run tool/panel_cli.dart set gridCell 128
dart run tool/panel_cli.dart cards
dart run tool/panel_cli.dart add clock
dart run tool/panel_cli.dart rm <cardId>
dart run tool/panel_cli.dart size <cardId> 3x3
dart run tool/panel_cli.dart card-set <id> seconds true
dart run tool/panel_cli.dart watch         # 看事件推送
dart run tool/panel_cli.dart call <method> '{"…":…}'
```

契约测试在 `test/panel_protocol_test.dart`——**那份测试就是协议的权威定义**
（握手、鉴权、每个方法的返回形状、错误码、事件），C++ 侧照它实现即可对齐。

### C++/WinUI3 侧实现提示

- 连接用 WinSock 的 `AF_UNIX`（Windows 10 1803+）：`socket(AF_UNIX, SOCK_STREAM, 0)`
  然后 `connect` 到 `sockaddr_un`。**别忘了 `#include <afunix.h>`**。
- 用 `--socket` / `--token` 两个命令行参数（`CommandLineToArgvW` 或 WinUI3 的
  `AppInstance` 参数都能取到），**不要**去读 `panel-ipc.json`（那是给 CLI 调试用的）。
- 收包要自己缓冲成行；建议单线程读循环 + 把事件投递到 UI 线程（`DispatcherQueue`）。
- 事件到达后重新拉状态，别做增量推断（见"事件"一节）。
- 组件库的**实时预览不做**：原生面板渲染不了 Flutter widget。当前约定是显示
  静态图（`icon` + 描述 + 尺寸 + 设置项）。将来若要"真预览"，走
  "核心把预览区渲染成位图低频推送"这条路（需要在协议里加 `preview.*` 方法）。

## 尚未实现（面板可以先用静态信息顶上）

| 能力 | 说明 |
|---|---|
| 卡片拖拽/移动 | 现在只能改尺寸与设置；拖拽在磁贴窗口上用鼠标直接拖（不需要面板） |
| 壁纸选择 | `wallpaper.get` 只读。要"换壁纸"得加 `wallpaper.pick`（走核心的原生文件对话框） |
| 更新检查/安装 | 面板要显示更新状态得加 `update.check` / `update.install` |
| 预览位图 | 见上 |
