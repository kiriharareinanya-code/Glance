/// 插件注册表：**全项目唯一 import 具体插件实现的地方**。
///
/// 这是"组合根"（composition root）——壳（面板、桌面层、卡片主体）只认
/// [kPlugins] 里的清单和 [createPluginController]，永远不 import
/// `widgets/builtin/**`。这条边界由 test/architecture_test.dart 守卫。
///
/// 加一个插件的完整步骤（两处，都在插件侧）：
///   1. 在 `widgets/builtin/<名字>.dart` 里写好实现 + `k<名字>Manifest`
///      常量 + `PluginController <名字>Plugin(WidgetContext ctx)` 工厂；
///   2. 在本文件 import 它，往 [kPlugins] 和工厂表各加一行。
/// 面板、卡片主体、桌面层**不需要任何改动**。
library;

import 'builtin/basic.dart'
    show clockPlugin, kClockManifest, kTodoManifest, todoPlugin;
import 'builtin/calendar.dart' show calendarPlugin, kCalendarManifest;
import 'builtin/lyrics.dart' show kLyricsManifest, lyricsPlugin;
import 'builtin/weather.dart' show kWeatherManifest, weatherPlugin;
import 'plugin_api.dart';

/// 全部插件的清单（面板"组件库"页按 name 排序展示，桌面层查尺寸约束）
const List<PluginManifest> kPlugins = [
  kClockManifest,
  kWeatherManifest,
  kTodoManifest,
  kCalendarManifest,
  kLyricsManifest,
];

/// id → 工厂。id 与清单里的 id 一一对应。
final Map<String, PluginFactory> _factories = {
  'clock': clockPlugin,
  'weather': weatherPlugin,
  'todo': todoPlugin,
  'calendar': calendarPlugin,
  'lyrics': lyricsPlugin,
};

/// 按 id 查找清单；找不到返回 null（放置过的组件不可能出现这种情况，
/// 除非配置来自更新的版本）。
PluginManifest? pluginById(String id) {
  for (final p in kPlugins) {
    if (p.id == id) return p;
  }
  return null;
}

/// 全部插件，按名称排序（面板"组件库"页的展示顺序）。
List<PluginManifest> pluginCatalog() {
  final list = List<PluginManifest>.from(kPlugins)
    ..sort((a, b) => a.name.compareTo(b.name));
  return list;
}

/// 按 id 取工厂；未知 id 返回 null。守卫测试用它断言"清单里的每个插件
/// 都登记了工厂"——不需要真造一个 ctx。
PluginFactory? pluginFactoryById(String id) => _factories[id];

/// 造一个插件控制器。未知 id 直接抛——调用方必须先经 [pluginById] 校验
/// （卡片主体就是这么做的：查不到清单就渲染错误态）。
PluginController createPluginController(String id, WidgetContext ctx) {
  final f = pluginFactoryById(id);
  if (f == null) {
    throw ArgumentError('未知插件：$id');
  }
  return f(ctx);
}
