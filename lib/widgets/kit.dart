/// 内置组件的原生渲染共享件。
///
/// JSON 树协议退役后，node.dart 里仍被组件直接使用的零件搬到这里：
/// 进度条（含与卡片拖拽协作的指针抓取）、按压反馈、3D 翻面、图标表、
/// 颜色/辉光解析。组件渲染层（renderWidget 通道）与它们的关系是
/// "库与用户"，不再有任何解释器。
library;

import 'package:flutter/material.dart';

import 'morph_icons.dart' show MorphableIcon;
import 'node_anim.dart' show NodeAnimatedColor;

/// 正在被插件控件抓住的指针 id；null 表示没有。
///
/// 进度条按下时登记，外层桌面层（surface.dart）看到登记就让这次拖拽
/// 归输入框，不触发卡片移动。
class NodePointer {
  NodePointer._();

  static int? grabbedPointer;

  static bool isGrabbed(int pointer) => grabbedPointer == pointer;
}

/// 解析组件用的颜色字符串：#RGB / #RRGGBB / #RRGGBBAA（8 位时 alpha 在后，
/// 与历史协议一致）。
Color nodeColor(String hex) {
  var s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length == 6) {
    // 补上不透明的 alpha，此时已经是 AARRGGBB，不能再往下走
    s = 'FF$s';
  } else if (s.length == 8) {
    // 输入是 RRGGBBAA，Flutter 要 AARRGGBB
    s = s.substring(6) + s.substring(0, 6);
  }
  // 上面两个分支必须互斥。写成两个独立的 if 会让 6 位色补完 alpha 后
  // 又被当成 RRGGBBAA 旋转一次：#29B6F6 会变成 #F6FF29B6，蓝色渲染成粉色。
  return Color(int.parse(s, radix: 16));
}

FontWeight nodeWeight(int w) {
  const map = {
    100: FontWeight.w100, 200: FontWeight.w200, 300: FontWeight.w300,
    400: FontWeight.w400, 500: FontWeight.w500, 600: FontWeight.w600,
    700: FontWeight.w700, 800: FontWeight.w800, 900: FontWeight.w900,
  };
  return map[(w ~/ 100) * 100] ?? FontWeight.w400;
}

/// 两层 shadow 做"贴着笔画"的辉光（霓虹效果）。
///
/// 之前犯过的错：三层 + 5 倍半径的扩散光，光晕从笔画向外铺几十像素，
/// 整行文字的区域都被照亮，看起来是"这一行整体加亮"而不是"字在发光"。
/// 发光感来自"光紧贴轮廓、快速衰减"——内层（0.6x）几乎是描边级的实光，
/// 外层（1.8x）才是光晕，再往外就没有了。
List<Shadow> nodeGlow(Color color, double sigma) {
  final base = color.withValues(alpha: (color.a * 0.9).clamp(0.0, 1.0));
  return [
    Shadow(color: base, blurRadius: sigma * 0.6),
    Shadow(
        color: base.withValues(alpha: base.a * 0.45),
        blurRadius: sigma * 1.8),
  ];
}

/// 图标名 → 字体图标。形变表（morph_icons.dart 的 kMorphIconPaths）里的
/// 名字也会走到这里作为兜底——两份表的一致性由 test/memory_test.dart 的
/// morphNamesHaveFontFallback 锁住。
IconData iconDataFor(String? name) => switch (name) {
      'check' => Icons.check,
      'check_circle' => Icons.check_circle_outline,
      'circle' => Icons.circle_outlined,
      'close' => Icons.close,
      'add' => Icons.add,
      'refresh' => Icons.refresh,
      'left' => Icons.chevron_left,
      'right' => Icons.chevron_right,
      'up' => Icons.arrow_drop_up,
      'down' => Icons.arrow_drop_down,
      // 天气图标：真正的气象语义图标（rain=水滴、storm=雷暴），
      // 别用 grain/flash_on 这种名字对不上的通用符号硬凑
      'sun' => Icons.wb_sunny_outlined,
      'moon' => Icons.nights_stay_outlined,
      'cloud' => Icons.cloud_outlined,
      'cloud_sun' => Icons.wb_cloudy_outlined,
      'rain' => Icons.water_drop_outlined,
      'snow' => Icons.ac_unit,
      'sleet' => Icons.cloudy_snowing,
      'fog' => Icons.foggy,
      'storm' => Icons.thunderstorm_outlined,
      'thermostat' => Icons.thermostat_outlined,
      'air' => Icons.air,
      'settings' => Icons.settings,
      // 媒体控制
      'play' => Icons.play_arrow_rounded,
      'pause' => Icons.pause_rounded,
      'prev' => Icons.skip_previous_rounded,
      'next' => Icons.skip_next_rounded,
      'music' => Icons.music_note_rounded,
      _ => Icons.square_outlined,
    };

/// 组件图标：形变表里的名字（play↔pause、circle↔check_circle 等）随
/// 重绘做 SVG path 形变，颜色变化也做过渡——待办勾选的红↔绿、歌词按钮
/// 的禁用灰↔白，都是"图标在形变、颜色却啪一下切"很违和，所以一起动画。
class NodeIcon extends StatelessWidget {
  const NodeIcon({
    super.key,
    required this.name,
    required this.size,
    required this.color,
    required this.animate,
  });

  final String name;
  final double size;
  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return NodeAnimatedColor(
      color: color,
      animate: animate,
      builder: (context, c) => MorphableIcon(
        name: name,
        size: size,
        color: c,
        animate: animate,
        fallback: iconDataFor(name),
      ),
    );
  }
}

/// 把 [gap] 插进相邻孩子之间（纵向列表用 SizedBox(height) 的等价物）。
/// 横向行传 `horizontal: true`。
List<Widget> withGaps(List<Widget> kids, double gap,
    {bool horizontal = false}) {
  return [
    for (var i = 0; i < kids.length; i++) ...[
      if (i > 0) SizedBox(width: horizontal ? gap : null, height: horizontal ? null : gap),
      kids[i],
    ]
  ];
}

/// 进度条：细条 + 拖拽本地值跟手。
///
/// 拖拽期间用本地值跟手，松手才把结果回调给组件——组件那边是异步的
/// （seek 要经过通道到 native 再到播放器），等它回来再更新的话，
/// 手指在拖、条却一顿一顿地追，手感立刻就散了。
class PluginSlider extends StatefulWidget {
  const PluginSlider({
    super.key,
    required this.value,
    required this.height,
    required this.color,
    required this.background,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final double height;
  final Color color;
  final Color background;
  final bool enabled;
  final ValueChanged<double>? onChanged;

  @override
  State<PluginSlider> createState() => _PluginSliderState();
}

class _PluginSliderState extends State<PluginSlider> {
  /// 拖拽中的本地值；null 表示没在拖，显示组件给的值
  double? _dragging;

  /// 命中判定要比视觉高，否则 4px 高的条根本按不中
  static const double _hitHeight = 20;

  void _update(double dx, double width) {
    if (width <= 0) return;
    setState(() => _dragging = (dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Listener(
          // 按下的瞬间就要声明"这次指针归我"，外层桌面层随后才读得到。
          // 放到 onPointerMove 里就晚了——那时卡片拖拽已经开始了。
          onPointerDown: widget.enabled
              ? (e) {
                  NodePointer.grabbedPointer = e.pointer;
                  _update(e.localPosition.dx, width);
                }
              : null,
          onPointerMove: widget.enabled
              ? (e) {
                  if (!NodePointer.isGrabbed(e.pointer)) return;
                  _update(e.localPosition.dx, width);
                }
              : null,
          onPointerUp: widget.enabled
              ? (e) {
                  if (!NodePointer.isGrabbed(e.pointer)) return;
                  NodePointer.grabbedPointer = null;
                  final done = _dragging;
                  setState(() => _dragging = null);
                  if (done != null) widget.onChanged?.call(done);
                }
              : null,
          onPointerCancel: widget.enabled
              ? (e) {
                  if (!NodePointer.isGrabbed(e.pointer)) return;
                  NodePointer.grabbedPointer = null;
                  setState(() => _dragging = null);
                }
              : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: _hitHeight,
            width: double.infinity,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: widget.background,
                      borderRadius: BorderRadius.circular(widget.height / 2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: widget.height,
                      decoration: BoxDecoration(
                        color: widget.enabled
                            ? widget.color
                            : widget.color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(widget.height / 2),
                      ),
                    ),
                  ),
                  // 拖拽中才显示滑块，平时保持截图里那种干净的细条
                  if (_dragging != null)
                    Align(
                      alignment: Alignment(v * 2 - 1, 0),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 3D X 轴翻转切换（从下往上翻）：前脸 ↔ 后脸。
class FlipSwap extends StatefulWidget {
  const FlipSwap({
    super.key,
    required this.flipKey,
    required this.front,
    required this.back,
  });

  final String flipKey;
  final Widget front;
  final Widget back;

  @override
  State<FlipSwap> createState() => _FlipSwapState();
}

class _FlipSwapState extends State<FlipSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 600),
    vsync: this,
  );

  String? _prevKey;

  static const _pi = 3.141592653589793;

  @override
  void initState() {
    super.initState();
    _prevKey = widget.flipKey;
  }

  @override
  void didUpdateWidget(FlipSwap old) {
    super.didUpdateWidget(old);
    if (widget.flipKey != _prevKey) {
      _prevKey = widget.flipKey;
      // value=0 在前脸 → forward 到 1（翻到后脸）
      // value=1 在后脸 → reverse 到 0（翻回前脸）
      if (_ctrl.value < 0.5) {
        _ctrl.forward(from: 0.0);
      } else {
        _ctrl.reverse(from: 1.0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_ctrl.value);
        // t=0 → 前脸静止（0°），t=1 → 后脸静止（0°）
        // 前脸：0→π 旋转（翻倒），后脸：-π→0 旋转（翻正）
        final frontAngle = t * _pi;
        final backAngle = t * _pi - _pi;
        // opacity 跟着角度走：接近侧视（π/2）时最透明
        final frontOpacity = (1.0 - t).clamp(0.0, 1.0);
        final backOpacity = t.clamp(0.0, 1.0);
        return Stack(
          children: [
            // 前脸：t<0.5 时可见，t>=0.5 时隐藏
            if (t < 0.5)
              Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(frontAngle),
                child: Opacity(opacity: frontOpacity, child: widget.front),
              ),
            // 后脸：t>=0.5 时可见，t<0.5 时隐藏
            if (t >= 0.5)
              Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(backAngle),
                child: Opacity(opacity: backOpacity, child: widget.back),
              ),
          ],
        );
      },
    );
  }
}

/// 可点元素的按压反馈：按下轻微缩小 + 变淡，松手弹回。
///
/// 苹果 HIG 的触感语言——"按下去有东西让位给你"。以前 tap 节点按下毫无
/// 反应，上一曲/下一曲点了像没点上。scale 收着放（0.96）不抢戏：大区域
/// （整行待办）和小按钮（媒体控制）用同一个量级都不会夸张。
class TapFeedback extends StatefulWidget {
  const TapFeedback({
    super.key,
    required this.child,
    required this.animate,
    this.onTap,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onTap;

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pressed = _pressed && widget.animate;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: pressed ? 0.96 : 1.0,
        duration: widget.animate
            ? const Duration(milliseconds: 130)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: pressed ? 0.8 : 1.0,
          duration: widget.animate
              ? const Duration(milliseconds: 130)
              : Duration.zero,
          child: widget.child,
        ),
      ),
    );
  }
}
