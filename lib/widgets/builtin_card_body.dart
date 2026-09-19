/// 把一张卡片和它的内置组件控制器绑在一起：挂载、渲染、主题推送、卸载。
///
/// 出错恢复的自动重试机制随 JS 运行时一起移除了——组件是编译进核心的
/// Dart 代码，不存在"挂载失败"；网络类错误由组件自己的错误视图负责
///（天气卡有完整的错误/重试态），不再需要外层兜底。
library;

import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../core/splash_gate.dart';
import '../model/card.dart';
import '../store/store.dart';
import '../ui/card_view.dart';
import '../ui/wallpaper.dart';
import 'catalog.dart';
import 'context.dart';
import 'spec.dart';

class BuiltinCardBody extends StatefulWidget {
  const BuiltinCardBody({
    super.key,
    required this.card,
    required this.size,
    required this.store,
    required this.state,
    required this.onRequestSize,
    required this.onOpenSettings,
  });

  final WidgetCard card;
  final Size size;
  final Store store;
  final AppState state;
  final void Function(String size) onRequestSize;
  final void Function() onOpenSettings;

  @override
  State<BuiltinCardBody> createState() => _BuiltinCardBodyState();
}

class _BuiltinCardBodyState extends State<BuiltinCardBody> {
  BuiltinController? _controller;
  WidgetContext? _ctx;

  /// 挂载阶段抛出的异常（理论上不该发生，兜一个底）
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _boot();
    // 壁纸一变，"莫奈取色"算出来的强调色也跟着变——组件在 mount 时
    // 拿过一次初始值，时钟这类每秒重绘的会自己读最新值；其余的等下次
    // 因别的原因重挂载（改尺寸/改设置）时生效。
    Wallpaper.dominantColor.addListener(_pushTheme);
  }

  @override
  void dispose() {
    Wallpaper.dominantColor.removeListener(_pushTheme);
    _controller?.unmount();
    super.dispose();
  }

  void _pushTheme() => _ctx?.themeAccent = _themeAccentHex();

  /// 只有用户开了"从壁纸取色"或"文字颜色也用取色"其中一个开关，才把
  /// 算出来的强调色递给组件——两个开关都关着时组件拿到 null，自己退回
  /// 写死的颜色，不会在用户没选这套风格时突然被强行换色。
  String? _themeAccentHex() {
    final s = widget.state.settings;
    if (!s.autoColorFromWallpaper && !s.autoForegroundFromWallpaper) return null;
    final c = Wallpaper.dominantColor.value;
    if (c == null) return null;

    // Material 的 tonalSpot 方案算出来的 primary 饱和度本来就压得低，
    // 直接把这个颜色当"文字色"画在卡片上时，经常又暗又灰。照搬
    // card_view.dart 里 _micaBase 的"明度推向两极"手法：只保留色相，
    // 明度按卡片背景明暗推到能读的档位，饱和度顶一个下限。
    final hsl = HSLColor.fromColor(c);
    final dark = Wallpaper.brightness.value < 0.5;
    final sat = hsl.saturation.clamp(0.55, 1.0);
    final lightness = dark ? 0.72 : 0.38;
    final vivid = HSLColor.fromAHSL(1, hsl.hue, sat, lightness).toColor();
    final hex = vivid.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return '#$hex';
  }

  /// 基线内容尺寸：按默认单元算出的内容区（刨掉卡片内边距）。
  Size get _baseContentSize {
    final grid = parseSize(widget.card.size) ?? const GridSize(2, 2);
    final px = sizeToPx(grid, kDefaultCell, widget.state.settings.gridGap);
    return Size(
      px.w - CardView.contentPadding.horizontal,
      px.h - CardView.contentPadding.vertical,
    );
  }

  void _boot() {
    final spec = builtinSpecById(widget.card.pluginId);
    if (spec == null) {
      setState(() => _loadError = '未知组件「${widget.card.pluginId}」');
      // 也算"到最终形态了"，得让启动幕布知道
      SplashGate.reportReady(widget.card.id);
      return;
    }

    final ctx = WidgetContext(
      store: widget.store,
      card: widget.card,
      pluginId: spec.id,
      onRequestSize: widget.onRequestSize,
      onOpenSettings: widget.onOpenSettings,
      settings: {
        ...spec.defaultSettings(),
        ...widget.card.settings,
      },
      grid: parseSize(widget.card.size) ?? const GridSize(2, 2),
      size: _baseContentSize,
      themeAccent: _themeAccentHex(),
    );

    final controller = createBuiltinController(spec.id, ctx);
    try {
      controller.mount();
    } catch (e) {
      ctx.unmount();
      setState(() => _loadError = '组件初始化失败：$e');
      SplashGate.reportReady(widget.card.id);
      return;
    }

    if (!mounted) {
      controller.unmount();
      return;
    }
    setState(() {
      _controller = controller;
      _ctx = ctx;
      _loadError = null;
    });
    // 组件已经跑出第一棵 UI 树，这张卡到此就算渲染好了。
    // 组件自己的网络请求不在等待范围内（见 SplashGate 的说明）。
    SplashGate.reportReady(widget.card.id);
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    if (error != null) return _errorBox(error);

    final ctx = _ctx;
    if (ctx == null) return const SizedBox.shrink();

    // 原生渲染通道：组件直接产出 Flutter Widget（JSON 树协议已退役）。
    // 动画开关在构建时推给组件（组件读 ctx.animate；与 _pushTheme 推
    // 主题色同一手法，下次重绘生效）。
    ctx.animate = widget.state.settings.animations;
    final base = _baseContentSize;
    final scale = (base.width > 0 ? widget.size.width / base.width : 1.0)
        .clamp(0.3, 3.0);
    // OverflowBox 让组件按基线尺寸排版（挣脱外层的紧约束），
    // Transform.scale 再缩到实际大小。
    //
    // 两个盒子的**嵌套顺序**是拿真机命中日志换来的教训：
    //
    // ❌ Transform > OverflowBox：OverflowBox 自身被紧约束钉成内容区宽 W，
    //    却活在 Transform 的缩放坐标系里——命中时它 size.contains 检查的
    //    是"缩放后的 W"，而绘制范围是足宽 W。scale < 1（用户网格单元
    //    小于 112 基线）时右侧 (1-scale)×W 一条内容"画得见、点不着"，
    //    日历翻月箭头"点了没反应"正是它。
    // ✅ OverflowBox > Transform：OverflowBox 在未缩放坐标系自检（整个
    //    内容区都放行），缩放坐标系里的第一道 size.contains 落在真正按
    //    基线排版的 SizedBox 上——命中边界与绘制边界同为 scale×base，
    //    完全重合。绘制结果与旧顺序一字不差。
    return OverflowBox(
      alignment: Alignment.topLeft,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: base.width,
          height: base.height,
          child: ValueListenableBuilder<Widget?>(
            valueListenable: ctx.widget,
            builder: (context, native, _) =>
                native ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// 卡片上显示的名字
  String get _displayName =>
      builtinSpecById(widget.card.pluginId)?.name ??
      widget.card.pluginId;

  /// 前景色跟着卡片走。写死白色的话，浅色壁纸配浅色云母时整个错误框都看不见
  Color get _fg =>
      DefaultTextStyle.of(context).style.color ?? Colors.white;

  Widget _errorBox(String message) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 13, color: _fg.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Flexible(
                child: Text('$_displayName 出错了',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _fg.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Text(message,
                  style: TextStyle(
                      color: _fg.withValues(alpha: 0.5),
                      fontSize: 10,
                      height: 1.35)),
            ),
          ),
        ],
      );
}
