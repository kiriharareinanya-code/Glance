/// 核心能力接口：面板服务要用的"域操作"。
///
/// 这一层把**传输/协议**（panel/service.dart、panel/dispatch.dart）和
/// **应用状态**（AppState / Store / native）隔开。收益有两个：
///   1. 服务层可以脱离真实应用测试（给个假 host 就行）；
///   2. 将来若要在进程内直接把同一套能力给别的 UI 用（不经 IPC），接的也是这层。
///
/// 实现方是 UI 根节点（`lib/ui/app_root.dart`）——它持有 AppState、Store、
/// 布局对账与壁纸逻辑。
library;

import '../model/card.dart';
import '../model/settings.dart';

abstract class CoreHost {
  /// 数字版本（用于比较更新），如 `0.2.126`
  String get appVersion;

  /// 展示版本，如 `Forst-0.2.126`
  String get displayVersion;

  /// 用户数据目录（面板要显示"配置在哪"，也用于定位 socket）
  String get userDataDir;

  AppSettings get settings;

  List<WidgetCard> get cards;

  /// 显示器列表：`[{id, x, y, w, h}]`（虚拟屏物理像素 + 设备名），
  /// 面板用来画"这张卡在哪块屏"。
  List<Map<String, Object?>> get displays;

  /// 还有没有空闲屏能放这个插件的卡片（面板据此禁用"添加"）
  bool canAddPlugin(String pluginId);

  /// 加一张卡；返回新建的卡片（没地方放返回 null）
  WidgetCard? addCard(String pluginId);

  /// 删一张卡；返回是否真的删掉了
  bool removeCard(String id);

  /// 改卡片尺寸（会重新对账位置）
  bool resizeCard(String id, String size);

  /// 改卡片自己的设置项
  bool setCardSetting(String id, String key, Object? value);

  /// 全局设置已经写进 [settings]，请宿主落盘并让界面生效（重新布局、
  /// 重算壁纸取色等）。[keys] 是被改动的键，宿主可按需只做相关的事。
  void onSettingsChanged(Iterable<String> keys);

  /// 壁纸现状：`{source, dominant, brightness}`（面板要展示的派生信息）
  Map<String, Object?> wallpaperInfo();

  /// 退出应用（与托盘"退出"同一条路：存盘 + 销毁托盘）
  Future<void> quit();
}
