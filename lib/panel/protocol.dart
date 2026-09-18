/// 面板 IPC 协议：帧格式、版本、方法名、错误码。
///
/// ## 传输
///
/// **Unix domain socket**（Windows 10 1803+ / `AF_UNIX`）——实测 Dart 在
/// Windows 上可用。选它而不是命名管道的原因：`dart:io` 没有命名管道 API，
/// 而 UDS 两侧都原生支持；且它没有端口占用、不弹防火墙、文件权限即访问
/// 控制、进程退出即释放。
///
/// 路径：`<userdata>/panel.sock`（便携模型：跟着 exe 走，见 core/paths.dart）。
/// 每次核心启动前先删掉残留的 socket 文件（上次崩溃留下的）。
///
/// ## 帧格式
///
/// NDJSON：一行一条 UTF-8 JSON 消息，行尾 `\n`。三种消息：
///
/// ```jsonc
/// {"id":1,"m":"cards.list","p":{}}          // 请求（面板 → 核心）
/// {"id":1,"ok":true,"r":{...}}              // 响应（成功）
/// {"id":1,"ok":false,"err":{"code":"...","msg":"..."}}   // 响应（失败）
/// {"e":"cards.changed","p":{...}}           // 事件（核心 → 面板，无 id）
/// ```
///
/// 请求/响应靠 `id` 配对（面板自己发号）。事件是核心单方面推送。
///
/// ## 握手
///
/// 连接后**第一条必须是** `hello`，带协议版本与 token：
///
/// ```json
/// {"id":1,"m":"hello","p":{"protocol":1,"token":"<hex>"}}
/// ```
///
/// token 由核心每次启动随机生成，启动面板进程时经命令行传给它。校验失败
/// 直接断连。**信任边界说明**：这挡住的是"同一个用户下的其他进程乱连"，
/// 不是跨用户攻击（同用户本来就能读对方内存）；设置面板这个量级够了。
///
/// ## 版本
///
/// 面板与核心**一起发版**（不做热更新），所以正常情况下版本永远一致。
/// 保留版本号是为了开发期：手头有个旧面板 exe 时，握手会明确报不匹配，
/// 而不是让某个方法神秘地返回 null。
library;

import 'dart:convert';

/// 协议版本。**不兼容改动必须 +1**（字段改名、语义变化、方法参数变化）；
/// 只加方法或只加可选字段不用改。
const int kPanelProtocolVersion = 1;

/// 方法名。字符串常量集中在这里，两侧（Dart / C++）都照抄这一张表。
class PanelMethod {
  PanelMethod._();

  // —— 握手与元信息 ——
  static const hello = 'hello';
  static const appInfo = 'app.info';
  static const appQuit = 'app.quit';
  static const ping = 'panel.ping';

  // —— 插件 ——
  static const pluginsList = 'plugins.list';

  // —— 全局设置（schema 驱动，见 settings_schema.dart）——
  static const settingsSchema = 'settings.schema';
  static const settingsGet = 'settings.get';
  static const settingsSet = 'settings.set';

  // —— 卡片 ——
  static const cardsList = 'cards.list';
  static const cardsAdd = 'cards.add';
  static const cardsRemove = 'cards.remove';
  static const cardsSetSize = 'cards.setSize';
  static const cardsSetSetting = 'cards.setSetting';

  // —— 壁纸 ——
  static const wallpaperGet = 'wallpaper.get';
}

/// 事件名（核心 → 面板）。面板拿到不认识的 `e` 应直接忽略——这样核心加
/// 新事件不会让旧面板崩。
class PanelEvent {
  PanelEvent._();

  /// 卡片增删 / 移动 / 改尺寸 / 改设置，或布局对账后位置变了
  static const cardsChanged = 'cards.changed';

  /// 全局设置变化（含从托盘或别处改的）
  static const settingsChanged = 'settings.changed';

  /// 壁纸或取色结果变化
  static const wallpaperChanged = 'wallpaper.changed';

  /// 核心要求面板把自己拉到前台（用户又点了一次托盘"设置"）
  static const activate = 'activate';
}

/// 错误码。面板按 code 分支，msg 只用来显示。
class PanelErrorCode {
  PanelErrorCode._();

  static const badRequest = 'bad_request'; // 参数缺失 / 类型不对
  static const noHandshake = 'no_handshake'; // 没先 hello
  static const badToken = 'bad_token';
  static const badVersion = 'bad_version';
  static const notFound = 'not_found'; // 卡片 / 插件不存在
  static const rejected = 'rejected'; // 合法但被拒（如没有空闲屏可放）
  static const unsupported = 'unsupported'; // 核心没实现这个方法
  static const internal = 'internal';
}

/// 处理器抛这个 → 变成 `{"ok":false,"err":{...}}`。其他异常一律归 internal。
class PanelError implements Exception {
  PanelError(this.code, this.msg);

  final String code;
  final String msg;

  @override
  String toString() => 'PanelError($code): $msg';
}

/// 编码一条消息为"一行 + \n"。
String encodeLine(Map<String, Object?> msg) => '${jsonEncode(msg)}\n';

/// 把一条收到的行解析成 map。解析失败返回 null（调用方回 bad_request 或忽略）。
Map<String, Object?>? decodeLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return null;
  try {
    final v = jsonDecode(t);
    if (v is! Map) return null;
    return v.cast<String, Object?>();
  } catch (_) {
    return null;
  }
}
