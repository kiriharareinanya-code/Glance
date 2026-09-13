/// 弹簧滚动容器（Spring slide）。
///
/// 用途：歌词换句时整列歌词**纵向滚动**——上一句往上退出、这一句顶到
/// 高亮位，位置之间用阻尼弹簧过渡（起步快、末段轻微过冲后回稳）。
///
/// 和"淡入淡出"的区别（这是关键）：淡入是每行文字原地换掉，再各自淡出
/// 淡入，**没有任何位移**，看起来是"跳"；滚动是内容整体平移，高亮行的
/// 位置变化被真实地画出来，才有"翻上去"的物理感。
///
/// 实现要点：调用方（歌词组件）不重建行内容，只把**目标偏移量**给它；
/// 这个 widget 用 AnimationController + Tween 在"上一次的偏移"和"新的
/// 偏移"之间插值。中途再来一次换句时，从**当前动画位置**接着走，不会
/// 跳回起点（连续换句不会闪）。
///
/// 闪白红线：本项目当年因为真实渲染下内容交叉过渡闪白而整体移除过这类
/// 动画（见 node.dart _child 注释）。所以这里**只做 Transform.translate**，
/// 不裁剪、不叠 Opacity、不动图层合成路径——平移不改绘制内容，不会触发
/// 当年的闪白机制。是否启用仍由调用方显式声明。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一次滚动过渡的时长。比属性过渡（260ms）略长，让回弹看得清。
const Duration kSpringDuration = Duration(milliseconds: 420);

/// 阻尼弹簧曲线：从 0 出发冲到 1，轻微过冲后回稳。
///
/// 用标准衰减振荡 `1 - e^(-k t)·cos(w t)` 归一化，保证 t=0→0、t=1→1；
/// 再叠一点可控过冲让"弹"更明确（纯阻尼曲线在 w 偏小时过冲不明显）。
class SpringCurve extends Curve {
  const SpringCurve({this.overshoot = 0.06, this.oscillations = 0.8});

  /// 过冲幅度（相对位移的比例）。越大越"弹"，0.06 是"有物理感但不夸张"。
  final double overshoot;

  /// 振荡次数：越大尾巴越多，越小越干脆
  final double oscillations;

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    const damp = 6.0;
    final w = math.pi * 2 * oscillations;
    double raw(double x) => 1 - math.exp(-damp * x) * math.cos(w * x);
    final r0 = raw(0);
    final r1 = raw(1);
    var v = (raw(t) - r0) / (r1 - r0);
    v += overshoot * math.exp(-5.0 * t) * math.sin(math.pi * t);
    return v;
  }
}

/// 让 [child] 按 [offset] 做弹簧式纵向平移。
///
/// [offset] 是**绝对目标位移**（像素，负值=内容往上走）。值变化时从当前
/// 实际位置弹簧到新位置；值不变则完全静止（不占帧、不重绘）。
class SpringSlide extends StatefulWidget {
  const SpringSlide({
    super.key,
    required this.offset,
    required this.child,
    this.animate = true,
    this.duration = kSpringDuration,
    this.curve = const SpringCurve(),
  });

  /// 目标纵向位移（像素）。调用方按"行高 × 行序号"算出即可。
  final double offset;

  final Widget child;

  /// 跟随全局"动画效果"开关：关掉时直接到位，不滑
  final bool animate;
  final Duration duration;
  final Curve curve;

  @override
  State<SpringSlide> createState() => _SpringSlideState();
}

class _SpringSlideState extends State<SpringSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _anim;

  /// 动画的起点（上一次实际显示到的位置）
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.offset;
    _anim = AlwaysStoppedAnimation(_from);
    _ac = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1;
  }

  @override
  void didUpdateWidget(SpringSlide old) {
    super.didUpdateWidget(old);
    if (widget.offset == old.offset) return;
    if (!widget.animate) {
      // 关掉动画：直接到位，并把动画位置同步过去
      _from = widget.offset;
      _anim = AlwaysStoppedAnimation(_from);
      _ac.value = 1;
      return;
    }
    // 从"当前实际位置"出发而不是从上一个目标出发——连续换句时
    // 不会出现位置跳回起点再追过去
    _from = _anim.value;
    _anim = Tween<double>(begin: _from, end: widget.offset)
        .animate(CurvedAnimation(parent: _ac, curve: widget.curve));
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
    if (!widget.animate) {
      return Transform.translate(
        offset: Offset(0, widget.offset),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _anim,
      // child 不参与重建——每帧只有 Transform 在变
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: child,
      ),
    );
  }
}
