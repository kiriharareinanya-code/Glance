/// 插件节点层的动效基础设施。
///
/// 插件（JS）每次 render 都是一整棵新树，宿主照着重建——属性一变就是硬切。
/// 这里给"会随状态变化"的属性（底色、文字、颜色）统一补上过渡，插件代码
/// 不需要任何改动：勾选待办、歌词高亮换行、按钮禁用色都会自己滑过去。
///
/// 节奏按苹果 HIG 的惯例：状态切换 260ms 缓出（easeOutCubic），起步快、
/// 收尾减速，不做回弹——回弹留给手势驱动的交互，状态变化弹一下会显得躁。
library;

import 'package:flutter/material.dart';

/// 属性过渡时长（底色 / 文字 / 颜色统一）
const Duration kNodeAnimDuration = Duration(milliseconds: 260);

/// 图标形变时长。形变是"换了形状"，幅度比改个颜色大，给多一点时间——
/// 但不超过属性过渡的两倍，否则同一个勾选动作里两段动画会显得不是一套
const Duration kNodeMorphDuration = Duration(milliseconds: 360);

/// 属性过渡曲线：缓出，末段减速，视觉上"到位"比实际早一点
const Curve kNodeAnimCurve = Curves.easeOutCubic;

/// 颜色变化时做过渡的包装器。
///
/// 为什么不用 TweenAnimationBuilder：它要求调用方自己记住旧值，而这里
/// 旧值只有"上一次 build 时传进来的颜色"，正好由 State 管着最省事。
/// 用法见 node.dart 的 icon 分支。
class NodeAnimatedColor extends StatefulWidget {
  const NodeAnimatedColor({
    super.key,
    required this.color,
    required this.builder,
    this.duration = kNodeAnimDuration,
    this.curve = kNodeAnimCurve,
    this.animate = true,
  });

  final Color color;

  /// 拿到当前（过渡中的）颜色去画孩子
  final Widget Function(BuildContext context, Color color) builder;

  final Duration duration;
  final Curve curve;

  /// 关掉动画时直接给目标色（跟随全局"动画效果"开关）
  final bool animate;

  @override
  State<NodeAnimatedColor> createState() => _NodeAnimatedColorState();
}

class _NodeAnimatedColorState extends State<NodeAnimatedColor>
    with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late CurvedAnimation _curved;
  late ColorTween _tween;
  late Color _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.color;
    _ac = AnimationController(vsync: this, duration: widget.duration);
    // 曲线必须真正参与插值：早期版本在这里直接 _tween.evaluate(_ac)，
    // controller 的原始线性值喂进去了，kNodeAnimCurve 定义了却没接上——
    // 插件层的颜色过渡实际全是线性。evaluate 一律走 CurvedAnimation。
    _curved = CurvedAnimation(parent: _ac, curve: widget.curve);
    _tween = ColorTween(begin: _shown, end: _shown);
  }

  @override
  void didUpdateWidget(NodeAnimatedColor old) {
    super.didUpdateWidget(old);
    if (widget.color == old.color && widget.curve == old.curve) return;
    if (!widget.animate) {
      _shown = widget.color;
      return;
    }
    // 从"现在实际显示的颜色"出发，而不是从上一个目标出发——连点时
    // 不会出现颜色跳回再追过去
    _tween = ColorTween(begin: _shown, end: widget.color);
    // curve 变了要重建 CurvedAnimation（它持有旧 curve 的引用）
    if (widget.curve != old.curve) {
      _curved = CurvedAnimation(parent: _ac, curve: widget.curve);
    }
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
      _shown = widget.color;
      return widget.builder(context, widget.color);
    }
    return AnimatedBuilder(
      animation: _ac,
      builder: (context, _) {
        // ColorTween.lerp 在动画中途给出当前插值色（已过 easeOutCubic 曲线）
        _shown = _tween.evaluate(_curved) ?? widget.color;
        return widget.builder(context, _shown);
      },
    );
  }
}
