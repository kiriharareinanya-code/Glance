/// 机械翻页过渡（翻页时钟效果）。
///
/// 值变化时把文字当成一张"页"来翻：上半页绕中轴向前翻下去（露出下面
/// 新的上半页），落到中线后下半页再从后面翻上来压住旧的下半页——就是
/// 机场翻牌显示器和机械翻页钟的那套动作。
///
/// 为什么做成"半页裁剪 + 绕中轴旋转"而不是简单的高度压缩：纯高度压缩
/// 看着像纵向擦除，不像翻页。绕 X 轴转的时候页面会透视收缩，再配一层
/// 随角度变化的压暗（越接近侧立越暗），才有"一张纸在翻"的物理感。
///
/// 时间分配（前一半翻下、后一半翻上）与缓动（下落加速、上升减速）都是
/// 照着机械翻页的观感调的：下落是重力、上升是阻尼，反过来会显得弹。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一次完整翻页的时长。机械翻页钟大约是 0.3~0.5s 一位，
/// 比属性过渡（260ms）慢一点，看得清"翻"这个动作。
const Duration kFlipDuration = Duration(milliseconds: 420);

/// 翻页面的最大压暗强度。再深就变成"黑块"而不是"背光的纸"了。
const double kFlipShade = 0.38;

/// 值变化时做机械翻页过渡。
///
/// [textBuilder] 由调用方提供：同一个样式、给定字符串就能画出文字。
/// 翻页需要**同时**画出旧值和新值（各自取上半/下半），所以必须是回调
/// 而不是现成的 Widget。
class FlipTransition extends StatefulWidget {
  const FlipTransition({
    super.key,
    required this.value,
    required this.textBuilder,
    this.animate = true,
    this.duration = kFlipDuration,
  });

  final String value;
  final Widget Function(String value) textBuilder;

  /// 跟随全局"动画效果"开关：关掉时直接换值，不翻
  final bool animate;
  final Duration duration;

  @override
  State<FlipTransition> createState() => _FlipTransitionState();
}

class _FlipTransitionState extends State<FlipTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late String _shown;

  /// 正在退场的旧值。null 表示没在翻页（静止态）。
  String? _prev;

  @override
  void initState() {
    super.initState();
    _shown = widget.value;
    _ac = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        // 翻完就把旧值丢掉：这个项目的契约是"过渡结束后旧内容必须退场"，
        // 留着会在下一次翻页时把上一轮的残影一起画出来
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _prev = null);
        }
      });
  }

  @override
  void didUpdateWidget(FlipTransition old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (!widget.animate) {
      _prev = null;
      _shown = widget.value;
      return;
    }
    // 从"当前显示的"翻到新值。连续变化（秒针来不及翻完就到下一秒）时
    // 旧值直接替换成上一轮的目标值，动画从头开始——不会累积一段排队。
    _prev = _shown;
    _shown = widget.value;
    _ac
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prev = _prev;
    if (!widget.animate || prev == null || prev == _shown) {
      return widget.textBuilder(_shown);
    }

    final oldText = widget.textBuilder(prev);
    final newText = widget.textBuilder(_shown);

    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        final t = _ac.value;
        // 前 50%：上半页翻下；后 50%：下半页翻上
        final fall = Curves.easeIn.transform((t / 0.5).clamp(0.0, 1.0));
        final rise = Curves.easeOutCubic
            .transform(((t - 0.5) / 0.5).clamp(0.0, 1.0));

        return Stack(
          children: [
            // 尺寸由完整的新值文字决定（不可见）；其余层都是同尺寸的半页
            Opacity(opacity: 0, child: newText),

            // 上半静态页：新值的上半页，旧的上半页翻走后露出来的就是它
            _page(newText, top: true, shade: 0),

            // 下半静态页：**整段动画都保持旧值**，由上升页翻下来盖住它。
            // 这里如果在中线切换成新值，中线那一刻上升页正好侧立（看不见），
            // 下半数字会凭空跳一下——实测能看出来，所以换成"旧值垫底、
            // 新页落上去"，落定瞬间（t=1）再整体切成静止态，像素完全一致。
            _page(oldText, top: false, shade: 0),

            // 下落页：旧值的上半页，绕中轴 0 → -90°
            if (t < 0.5)
              _flap(
                oldText,
                top: true,
                angle: -math.pi / 2 * fall,
                shade: kFlipShade * math.sin(fall * math.pi / 2),
              ),

            // 上升页：新值的下半页，绕中轴 +90° → 0
            if (t >= 0.5)
              _flap(
                newText,
                top: false,
                angle: math.pi / 2 * (1 - rise),
                shade: kFlipShade * math.sin((1 - rise) * math.pi / 2),
              ),
          ],
        );
      },
    );
  }

  /// 一整页里的上半页或下半页
  Widget _page(Widget text, {required bool top, required double shade}) {
    return ClipRect(
      clipper: _HalfClipper(top: top),
      child: shade <= 0.001
          ? text
          : Stack(
              fit: StackFit.passthrough,
              children: [
                text,
                Positioned.fill(
                  child: ColoredBox(color: Color.fromRGBO(0, 0, 0, shade)),
                ),
              ],
            ),
    );
  }

  /// 会翻的那半页：绕中轴旋转，带一点点透视（没有透视看着像平面压缩）
  Widget _flap(Widget text,
      {required bool top, required double angle, required double shade}) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateX(angle),
      child: _page(text, top: top, shade: shade),
    );
  }
}

/// 裁出上半页或下半页
class _HalfClipper extends CustomClipper<Rect> {
  const _HalfClipper({required this.top});

  final bool top;

  @override
  Rect getClip(Size size) => top
      ? Rect.fromLTWH(0, 0, size.width, size.height / 2)
      : Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2);

  @override
  bool shouldReclip(_HalfClipper oldClipper) => oldClipper.top != top;
}
