/// 弹簧过渡（Spring transition）。
///
/// 换行/换词时让新内容带着一点"弹进来"的物理感：新内容从下方滑入并淡入，
/// 位移用一个带阻尼的弹簧曲线收尾（末段轻微过冲后回稳）；旧内容同时淡出
/// 并略微上移退场。和 [FlipTransition] 一样，它是**自包含**的——值变了
/// 才动，静止时就是普通文字，调用方不需要自己记旧值。
///
/// 为什么用弹簧而不是 easeOutCubic：
///   - 属性过渡（颜色/字号）要的是"到位即停"，缓出最合适，弹一下反而躁；
///   - 但"换行"是内容位移，物理上更像被推上来的，收尾带一点点回弹会显得
///     有质量感——这正是要的"弹簧动画"。
/// 过冲幅度刻意压得很小（约 5%），只在最后一小段回稳，不会看着抖。
///
/// 闪白红线：本项目当年因为真实渲染下**内容交叉过渡闪白**而整体移除过
/// 这类动画（见 node.dart _child 注释）。所以这里和 trans:true 一样是
/// **显式声明**才生效（歌词当前行才传 'spring'），时钟每秒重绘的节点
/// 不声明就永远是硬切。实现上只对**位移 + 透明度**做过渡，不做裁剪，
/// 避免复现当年的闪白机制。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一次换行过渡的时长。比属性过渡（260ms）略长，让回弹看得清。
const Duration kSpringDuration = Duration(milliseconds: 380);

/// 阻尼弹簧曲线：位移从 0 出发冲到 1，略微过冲（约 5%）后回稳到 1。
///
/// 用"1 - 衰减振荡"的标准形式：1 - e^(-k t) · cos(w t)，再做归一化，
/// 保证 t=0 时为 0、t=1 时为 1。相位/阻尼按手感调成"起步快、末段轻轻一弹"。
class SpringCurve extends Curve {
  const SpringCurve({this.overshoot = 0.05, this.oscillations = 0.85});

  /// 过冲幅度（相对位移的比例）
  final double overshoot;

  /// 振荡次数：越大尾巴越多，越小越干脆
  final double oscillations;

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    // 归一化衰减振荡：raw(t) = 1 - e^(-d t) cos(w t)
    const damp = 6.0;
    final w = math.pi * 2 * oscillations;
    double raw(double x) => 1 - math.exp(-damp * x) * math.cos(w * x);
    final r0 = raw(0);
    final r1 = raw(1);
    var v = (raw(t) - r0) / (r1 - r0);
    // 叠一点可控过冲，让"弹"更明确（原始阻尼曲线在 w 偏小时过冲不明显）
    v += overshoot * math.exp(-5.0 * t) * math.sin(math.pi * t);
    return v;
  }
}

/// 值变化时做弹簧过渡。
///
/// [childBuilder] 由调用方提供：给定一个 Widget 就包好。这里不限制内容
/// 类型（歌词行是 col，也可能只是 text），所以直接吃 Widget。
class SpringTransition extends StatefulWidget {
  const SpringTransition({
    super.key,
    required this.value,
    required this.child,
    this.animate = true,
    this.duration = kSpringDuration,
    this.offset = 0.35,
    this.curve = const SpringCurve(),
  });

  /// 用于判定"内容变了"的键。值变化触发一次过渡。
  final Object? value;

  /// 当前内容
  final Widget child;

  /// 跟随全局"动画效果"开关：关掉时直接换值，不弹
  final bool animate;
  final Duration duration;

  /// 进场时的起始纵向偏移（相对自身高度的比例）。正数=从下方滑入。
  final double offset;

  final Curve curve;

  @override
  State<SpringTransition> createState() => _SpringTransitionState();
}

class _SpringTransitionState extends State<SpringTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1; // 首帧不上动画，直接是静止态
  }

  @override
  void didUpdateWidget(SpringTransition old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (!widget.animate) {
      _ac.value = 1;
      return;
    }
    _ac
      ..duration = widget.duration
      ..forward(from: 0); // 从 0 重放：新内容带着弹簧滑入
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) return widget.child;
    return AnimatedBuilder(
      animation: _ac,
      // child 参数让 widget.child 不被每帧重建——只有外面两层动
      child: widget.child,
      builder: (context, child) {
        // 用公开的 transform()——transformInternal 是 Curve 的受保护成员
        final t = widget.curve.transform(_ac.value);
        // 位移：offset → 0。曲线里含过冲，末段会微微越过 0 再回稳。
        final dy = widget.offset * (1 - t) * 48;
        return Opacity(
          // 透明度用同一进度但收得更快，避免末段还在半透明
          opacity: Curves.easeOut.transform(_ac.value).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: child,
          ),
        );
      },
    );
  }
}
