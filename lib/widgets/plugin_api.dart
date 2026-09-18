/// 插件 API：壳与插件之间的**唯一契约面**。
///
/// 边界长这样（Phase 1）：
///
/// ```
///   lib/ui/**（面板、桌面层）      只 import plugin_api.dart + registry.dart
///           │
///           ▼
///   registry.dart                 ← 全项目唯一 import 具体插件实现的地方
///           │
///           ▼
///   widgets/builtin/<插件>.dart   实现 + 自己的 manifest + 自己的工厂
///           │
///           ▼
///   plugin_api.dart（本文件）      PluginManifest / PluginController / WidgetContext
///   kit.dart                       共享渲染件（滑条、按压反馈、图标…）
/// ```
///
/// 这个划分的收益是**可验证的**：架构守卫测试（test/architecture_test.dart）
/// 断言 `lib/ui/**` 永不 import `widgets/builtin/**`——面板与桌面层只认清单，
/// 加一个插件 = 加一个目录 + 在 registry 里加一行。
///
/// 关于"能不能不重新发版就更新插件"：Flutter/Dart 是 AOT 编译，运行时加载
/// 不了 Dart 代码。既然插件只由第一方编写、且跟随版本发布，就不需要脚本
/// 运行时或沙箱——插件就是普通 Dart 代码，能力不受限。
library;

import 'context.dart';

export 'context.dart' show WidgetContext;

/// 插件清单：面板/桌面层需要的**全部**静态信息。
///
/// 取代旧的 plugin.json 清单解析——插件已是编译进核心的 Dart 实现，
/// "描述"顺势变成常量。settings 的 map 形状与旧 manifest 完全一致
/// （key/type/label/desc/default/min/max/step/options），面板的设置
/// 控件按同样的规则消费，所以加设置项不需要动面板一行。
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.icon,
    required this.sizes,
    required this.defaultSize,
    this.settings = const [],
  });

  final String id;
  final String name;

  /// 插件自己的版本号。与程序版本解耦，方便在面板/关于页显示
  /// "这个组件最近更新了什么"。
  final String version;
  final String description;
  final String icon;

  /// 允许的卡片尺寸（grid 单位）
  final List<String> sizes;
  final String defaultSize;

  /// 设置项描述，见面板的设置控件渲染
  final List<Map<String, Object?>> settings;

  /// 每个设置项的默认值
  Map<String, Object?> defaultSettings() => {
        for (final f in settings) f['key'] as String: f['default'],
      };
}

/// 插件控制器契约：mount / unmount / onSettingsChange。
///
/// 定时器、网络、存储、媒体状态、渲染都通过 [ctx] 完成——插件拿不到
/// Flutter 的 BuildContext，也碰不到 AppState，能力面就是 [WidgetContext]。
abstract class PluginController {
  PluginController(this.ctx);

  final WidgetContext ctx;

  /// 挂载：起定时器、发首个请求、渲染第一帧。
  void mount();

  /// 卸载：默认交给 ctx 统一回收（定时器、在途请求、renderWidget 的死亡守门）。
  void unmount() => ctx.unmount();

  /// 面板改了设置：ctx.settings 已经更新，插件决定怎么响应
  /// （重绘 / 下次刷新生效 / 忽略）。
  void onSettingsChange() {}
}

/// 插件工厂：给一个 ctx 造出控制器。注册表按 id 找它。
typedef PluginFactory = PluginController Function(WidgetContext ctx);
