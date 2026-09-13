/// 内置组件目录：描述与控制器的汇总入口。
///
/// 取代旧 PluginRegistry：没有扫描、没有第三方目录、没有清单解析——
/// 5 个组件全部编译进核心，这里是唯一的事实来源。
library;

import 'builtin/basic.dart';
import 'builtin/calendar.dart';
import 'builtin/lyrics.dart';
import 'builtin/weather.dart';
import 'context.dart';
import 'spec.dart';

/// 内置组件的控制器契约：mount/unmount/onSettingsChange。
/// 定时器、事件、渲染都通过 [ctx] 完成。
abstract class BuiltinController {
  BuiltinController(this.ctx);

  final WidgetContext ctx;

  void mount();
  void unmount() => ctx.unmount();
  void onSettingsChange() {}
}

/// 组件工厂。id 必须是 [kBuiltinSpecs] 里的一个。
BuiltinController createBuiltinController(String id, WidgetContext ctx) {
  switch (id) {
    case 'clock':
      return ClockWidget(ctx);
    case 'weather':
      return WeatherWidget(ctx);
    case 'todo':
      return TodoWidget(ctx);
    case 'calendar':
      return CalendarWidget(ctx);
    case 'lyrics':
      return LyricsWidget(ctx);
    default:
      throw ArgumentError('未知内置组件：$id');
  }
}

