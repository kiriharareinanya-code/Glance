/// 图标形变（morph）：icon 节点的图标名在两次重绘之间变化时
/// （todo 勾选 circle → check_circle、歌词 play ↔ pause），在 Material 的
/// SVG path 之间做一次平滑形变，而不是硬切。
///
/// 实现走 iconic_morph 的 IconicShapeMorph（"兄弟图标"形变：共享轮廓保持
/// 不动、差异特征点对点形变）。几何数据不读资源文件——内嵌的 path 字符串
/// 通过 IconGeometry.resolver 喂给它，键是 'icon:<名字>'。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconic_morph/iconic_morph.dart';

import 'node_anim.dart' show kNodeMorphDuration;

/// 可形变图标的 path 数据（Material Icons，24×24 viewBox，填充型）。
///
/// 只收"会发生状态切换"的图标——静态图标没必要走形变管线，
/// 字体渲染更省事。新增的图标必须是单条 flat path（iconic_morph
/// 的解析器不展开 g/rect 等原语）。
const Map<String, List<String>> kMorphIconPaths = {
  'circle': [
    'M12 2C6.47 2 2 6.47 2 12s4.47 10 10 10 10-4.47 10-10S17.53 2 12 2z'
        'm0 18c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8z'
  ],
  'check_circle': [
    'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z'
        'm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z'
  ],
  'play': ['M8 5v14l11-7z'],
  'pause': ['M6 19h4V5H6v14zm8-14v14h4V5h-4z'],
  'check': ['M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z'],
  'close': [
    'M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 '
        '12 13.41 17.59 19 19 17.59 13.41 12z'
  ],
  'add': ['M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z'],
};

/// 名字在形变表里就返回 IconGeometry 的键，否则 null（回退字体图标）
String? morphIconKey(String? name) =>
    name != null && kMorphIconPaths.containsKey(name) ? 'icon:$name' : null;

bool _resolverInstalled = false;

/// 让 IconGeometry 认识 'icon:xxx' 这种键：返回内嵌的 path 数据；
/// 其他键返回 null，回落到默认的资源加载，不影响包自带的演示图标。
void ensureMorphIconResolver() {
  if (_resolverInstalled) return;
  _resolverInstalled = true;
  IconGeometry.resolver = (asset) async {
    if (!asset.startsWith('icon:')) return null;
    final d = kMorphIconPaths[asset.substring(5)];
    if (d == null) return null;
    return (viewBox: 24.0, isFill: true, pathData: d);
  };
}

/// 形变播完后切回静态渲染的延迟：形变时长 + 一拍缓冲。
/// 派生自 kNodeMorphDuration——改形变时长这里自动跟着走，
/// 别把它当独立的可调参数。
final Duration kMorphSettleDelay =
    kNodeMorphDuration + const Duration(milliseconds: 40);

/// icon 节点的渲染组件：名字没变或在形变表之外时等同原来的字体图标；
/// 名字变化且两端都有 path 数据时，从旧图标形变到新图标。
///
/// 静止态直接用 IconImage.svg 渲染（path 和字体字形同源，观感一致）；
/// 这样不需要 AnimatedIcon 那套控制器，状态只有"静止/正在形变"两种。
class MorphableIcon extends StatefulWidget {
  const MorphableIcon({
    super.key,
    required this.name,
    required this.size,
    required this.color,
    required this.animate,
    required this.fallback,
  });

  final String? name;
  final double size;
  final Color color;

  /// 跟随全局"动画效果"开关；关掉时图标切换仍然是硬切
  final bool animate;

  /// 名字不在形变表里时用的字体图标（node.dart 原来的 _icon 映射结果）
  final IconData fallback;

  @override
  State<MorphableIcon> createState() => _MorphableIconState();
}

class _MorphableIconState extends State<MorphableIcon> {
  /// 静止态当前显示的图标名
  String? _rest;

  /// 形变起点；null 表示当前静止
  String? _from;

  /// 重放计数：同一对 from→to 反复切换时，靠它把 morph 组件的 key 顶起来重播
  int _replay = 0;

  /// 形变播完后把渲染切回静态 IconImage 的定时器。
  ///
  /// 必须切回去：IconicShapeMorph 的画笔把填充图标画成描边轮廓（空心），
  /// 静态 IconImage 是实心填充——形变结束就定格在 morph 上，按钮外观会
  /// 随"最近一次交互"在空心/实心之间横跳（切歌后暂停键变了样就是它）。
  /// 统一定格在静态渲染上，任何时刻静止外观都一致。
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    ensureMorphIconResolver();
    _rest = widget.name;
  }

  void _startSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = Timer(kMorphSettleDelay, () {
      if (mounted && _from != null) setState(() => _from = null);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(MorphableIcon old) {
    super.didUpdateWidget(old);
    if (widget.name == _rest) return;
    // 起点取"当前画面上那一个"（_rest），不能用 _from：_from 是上一次形变
    // 的起点，形变得久它就过期了——勾选之后 _from 还停在 circle，再取消时
    // 算出的 from 和目标同名，动画直接被跳过。这就是"确认有动画、取消却
    // 硬切"的原因。用 _rest 时两个方向完全对称。
    final from = _rest;
    if (widget.animate &&
        morphIconKey(from) != null &&
        morphIconKey(widget.name) != null &&
        from != widget.name) {
      setState(() {
        _from = from;
        _rest = widget.name;
        _replay++;
      });
      _startSettleTimer();
    } else {
      _settleTimer?.cancel();
      setState(() {
        _from = null;
        _rest = widget.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final toKey = morphIconKey(widget.name);
    if (toKey == null) {
      // 形变表之外的名字：维持原来的字体图标渲染
      return Icon(widget.fallback, size: widget.size, color: widget.color);
    }
    final fromKey = morphIconKey(_from);
    if (_from != null && fromKey != null && _from != widget.name) {
      // 播一次后定格在目标图标；key 里带 _replay，同一对图标反复切换时重播
      return IconicShapeMorph(
        fromKey,
        toKey,
        key: ValueKey('morph:$_from>${widget.name}:$_replay'),
        size: widget.size,
        color: widget.color,
        colorEnd: widget.color,
        chromeColor: widget.color,
        duration: kNodeMorphDuration,
      );
    }
    return IconImage.svg(
      '<svg viewBox="0 0 24 24" fill="#000">'
      '<path d="${kMorphIconPaths[widget.name]!.join(' ')}"/></svg>',
      size: widget.size,
      color: widget.color,
    );
  }
}
