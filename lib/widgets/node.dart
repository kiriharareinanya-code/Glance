/// 声明式 UI 协议：插件不碰 DOM，也碰不到 Flutter，只返回一棵 JSON 描述的树。
///
/// 这是 Flutter 版与 Electron 版最根本的差异。那边插件直接拿 HTMLElement 往里
/// 塞 DOM；Dart 是 AOT 编译的，release 版没法加载第三方 Dart 代码，所以插件
/// 只能"描述"界面，由宿主翻译成 Flutter widget。
///
/// 节点类型故意保持小：够画完 4 个官方插件即可。多加一种类型就多一份要长期
/// 兼容的协议表面。
///
/// 动画有两档，都由插件显式声明：
///   - 根节点 `key`：整卡内容切换时交叉淡入（日历翻月把 key 设成 "2026-8"；
///     歌词切歌把 key 设成歌名|歌手）
///   - `flip` 节点：3D X 轴翻转（从下往上），带淡入淡出
///   - `slide` 节点：纵向弹簧滚动（歌词换句时整列歌词平移到下一句）
///   - text 节点 `trans`：`true` 交叉淡入 / `'flip'` 机械翻页
///   - 节点 `animKey`：**已禁用**（真实渲染下换行动画闪白，见 _child 注释），
///     字段保留在协议里兼容旧插件，宿主不再产生动画
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'images.dart';
import 'flip_transition.dart';
import 'morph_icons.dart';
import 'node_anim.dart';
import 'spring_transition.dart';

/// 事件回调：插件在树里声明 {"t":"tap","id":"h1"}，点中时回调 h1
typedef NodeEvent = void Function(String handlerId, Map<String, Object?> payload);

/// 插件内部控件正在接管这次指针操作，桌面层不要把它当成"拖动卡片"。
///
/// 背景：DesktopSurface 在整个桌面上挂了一个 Listener，指针在卡片上按下就开始
/// 拖卡片。这对点击没问题（没移动就不算拖），但对滑条是致命的——拖进度条会
/// 把整张卡片一起拖走。
///
/// Flutter 的指针事件是**从最内层往外层**依次派发的，所以滑条在自己的
/// onPointerDown 里置位，外层 Listener 随后就能读到。
class NodePointer {
  NodePointer._();

  /// 正在被插件控件抓住的指针 id；null 表示没有
  static int? grabbedPointer;

  static bool isGrabbed(int pointer) => grabbedPointer == pointer;
}

class NodeView extends StatefulWidget {
  const NodeView({
    super.key,
    required this.tree,
    required this.onEvent,
    this.animate = true,
  });

  /// 插件返回的 UI 树；null 表示还没渲染出内容
  final Map<String, Object?>? tree;
  final NodeEvent onEvent;

  /// 是否允许内容切换动画（全局设置里可以关）
  final bool animate;

  @override
  State<NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends State<NodeView> {
  /// 输入框控制器按节点 id 复用，否则每次重建都会丢失光标与内容
  final Map<String, TextEditingController> _controllers = {};

  /// 本次 render 用到的输入框 id（_input 里登记，build 末尾做差分）
  final Set<String> _usedInputIds = {};

  /// 退出服役的控制器排队延迟销毁。不能立即 dispose：根 key 交叉淡入时
  /// 旧子树还活着 260ms，里面的 TextField 可能还攥着这个控制器——
  /// 600ms > 交叉淡入全程，足够安全。
  final List<(TextEditingController, Timer)> _retiringControllers = [];

  /// 差分清理：这次 render 没再出现的 id 进入退役队列（插件删了输入框、
  /// 列表滚动导致节点换 id 等）。不清理的话 Map 只进不出，长会话慢慢漏。
  void _pruneControllers() {
    _controllers.removeWhere((id, c) {
      if (_usedInputIds.contains(id)) return false;
      final timer = Timer(const Duration(milliseconds: 600), () {
        c.dispose();
        _retiringControllers.removeWhere((e) => e.$1 == c);
      });
      _retiringControllers.add((c, timer));
      return true;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final (c, timer) in _retiringControllers) {
      timer.cancel();
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tree = widget.tree;
    if (tree == null) {
      return const SizedBox.shrink();
    }
    // 默认前景色取自外层 DefaultTextStyle（CardView 会按卡片底色明暗设定），
    // 插件显式写的颜色仍然优先。
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 13, decoration: TextDecoration.none),
      child: Builder(builder: (ctx) {
        // 前景色作为参数显式下传（fg），原子渲染器不再读 State 可变字段——
        // 渲染函数保持纯函数，主题色的来源一眼可见。
        final fg = DefaultTextStyle.of(ctx).style.color ?? Colors.white;
        _usedInputIds.clear();
        final content = _build(tree, fg);
        _pruneControllers();

        // 内容切换动画必须由插件显式声明：根节点带 key 时才做交叉淡入。
        // 不能对每次 render 都动画——时钟每秒重绘一次，那样会一直在闪。
        // 日历翻月时把 key 设成 "2026-8"，就只在真正换月时过渡。
        final key = _str(tree['key']);
        if (!widget.animate || key == null) return content;
        return AnimatedSwitcher(
          duration: kNodeAnimDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(key), child: content),
        );
      }),
    );
  }

  // ------------------------------------------------------------------
  // 取值助手：插件是 JS 写的，数字可能是 int 也可能是 double，统统按 num 读
  // ------------------------------------------------------------------

  double? _num(Object? v) => v is num ? v.toDouble() : null;
  String? _str(Object? v) => v is String ? v : null;

  List<Map<String, Object?>> _children(Object? v) {
    if (v is! List) return const [];
    return [
      for (final c in v)
        if (c is Map) c.cast<String, Object?>()
    ];
  }

  Widget _build(Map<String, Object?> n, Color fg) {
    switch (_str(n['t'])) {
      case 'col':
        return _flexBox(n, Axis.vertical, fg);
      case 'row':
        return _flexBox(n, Axis.horizontal, fg);
      case 'text':
        return _text(n, fg);
      case 'box':
        return _box(n, fg);
      case 'flex':
        return Expanded(
          flex: (_num(n['f']) ?? 1).round(),
          child: _child(n, fg),
        );
      case 'spacer':
        return const Spacer();
      case 'gap':
        final s = _num(n['v']) ?? 8;
        return SizedBox(width: s, height: s);
      case 'grid':
        return _grid(n, fg);
      case 'tap':
        return _tap(n, fg);      case 'input':
        return _input(n, fg);
      case 'divider':
        return Container(
          height: 1,
          color: _color(n['color']) ?? const Color(0x1AFFFFFF),
          margin: const EdgeInsets.symmetric(vertical: 4),
        );
      case 'progress':
        // 进度值做过渡：歌词/播客卡片每秒推一次进度，硬切会看到刻度在跳。
        // TweenAnimationBuilder 在目标值变化时从当前动画位置接着追，
        // 连续更新也不会回退或抖动。
        final value = (_num(n['v']) ?? 0).clamp(0.0, 1.0);
        final color = _color(n['color']) ?? const Color(0xFF7CC7FF);
        final height = _num(n['h']) ?? 4.0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(
                begin: widget.animate ? null : value, end: value),
            duration: widget.animate ? kNodeAnimDuration : Duration.zero,
            curve: kNodeAnimCurve,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: height,
              backgroundColor: const Color(0x22FFFFFF),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        );
      case 'scroll':
        return SingleChildScrollView(child: _child(n, fg));
      case 'stack':
        return Stack(children: [for (final c in _children(n['children'])) _build(c, fg)]);
      case 'icon':
        // 可形变的图标（circle/check_circle、play/pause 等）走 MorphableIcon：
        // 插件重绘导致图标名变化时做一次 SVG path 形变；其余名字维持字体渲染。
        // 颜色也做过渡（待办勾选的红↔绿、歌词按钮的禁用灰↔白），否则图标
        // 在形变、颜色却啪一下切换，两段动画打架。
        final iconName = _str(n['v']);
        return NodeAnimatedColor(
          color: _color(n['color']) ?? fg.withValues(alpha: 0.75),
          animate: widget.animate,
          builder: (context, color) => MorphableIcon(
            name: iconName,
            size: _num(n['size']) ?? 16,
            color: color,
            animate: widget.animate,
            fallback: _icon(iconName),
          ),
        );
      case 'image':
        return _image(n, fg);
      case 'slider':
        return _slider(n);
      case 'flip':
        return _flip(n, fg);
      case 'slide':
        // 纵向弹簧滚动：{t:'slide', 'v': 目标像素偏移, child}。
        // 歌词换句靠它把整列歌词平移到下一句，而不是每行原地换词。
        // 只做 Transform.translate，不裁剪、不叠透明度——平移不改绘制
        // 内容，不会触发当年那个闪白机制（见 _child 注释）。
        return SpringSlide(
          offset: _num(n['v']) ?? 0,
          animate: widget.animate,
          child: _child(n, fg),
        );
      default:
        // 未知节点不该让整张卡片崩掉
        return const SizedBox.shrink();
    }
  }

  Widget _child(Map<String, Object?> n, Color fg) {
    final c = n['child'];
    // animKey 字段保留在协议里（兼容旧插件），但**不再产生动画**：
    // 真实渲染下换行动画（_SlideSwap，见 git 历史 18ca340/dc2a61b）会闪白
    // 约 200ms——用户多轮实测所有过渡形式（滑动/淡入淡出）都闪，而
    // 无动画版本不闪。换行改回原地替换（内容直接平移到新位置）。
    // 要恢复动画前，必须先在真实渲染环境定位闪白机制（flutter_test 的
    // toImage 对 TransformLayer 有固有伪影，测试里无法复现真实渲染）。
    return c is Map ? _build(c.cast<String, Object?>(), fg) : const SizedBox.shrink();
  }

  /// 3D Y 轴翻转：children[0] 前脸，children[1] 后脸。
  /// flipKey 变化时触发 180° 翻转，中间点切换显示面。
  Widget _flip(Map<String, Object?> n, Color fg) {
    final kids = _children(n['children']);
    final front = kids.isNotEmpty ? _build(kids.first, fg) : const SizedBox.shrink();
    final back = kids.length > 1 ? _build(kids[1], fg) : const SizedBox.shrink();
    final flipKey = _str(n['flipKey']);
    if (!widget.animate || flipKey == null) return front;
    return _FlipSwap(
      flipKey: flipKey,
      front: front,
      back: back,
    );
  }

  Widget _flexBox(Map<String, Object?> n, Axis axis, Color fg) {
    final gap = _num(n['gap']) ?? 0;
    final kids = _children(n['children']);
    final widgets = <Widget>[];
    for (var i = 0; i < kids.length; i++) {
      if (i > 0 && gap > 0) {
        widgets.add(SizedBox(
            width: axis == Axis.horizontal ? gap : 0,
            height: axis == Axis.vertical ? gap : 0));
      }
      widgets.add(_build(kids[i], fg));
    }
    final cross = _crossAlign(_str(n['cross']));
    final mainName = _str(n['main']);
    final main = _mainAlign(mainName);
    // main 只要不是默认的 start，就必须让容器撑满主轴，否则 between / around /
    // center / end 全是空操作——容器缩到内容大小，压根没有多余空间可分配。
    // 实测：歌词卡片里"当前时间 | 总时长"那一行用了 between，却挤在一起显示成
    // "0:033:43"。
    //
    // 代价：撑满要求父节点在主轴上有确定尺寸。放进 scroll 这种无界容器里会报错，
    // 但那本来就是写错了——无限高的容器里谈"垂直居中"没有意义。
    final size = mainName == null || mainName == 'start'
        ? MainAxisSize.min
        : MainAxisSize.max;
    return axis == Axis.vertical
        ? Column(
            crossAxisAlignment: cross,
            mainAxisAlignment: main,
            mainAxisSize: size,
            children: widgets)
        : Row(
            crossAxisAlignment: cross,
            mainAxisAlignment: main,
            mainAxisSize: size,
            children: widgets);
  }

  CrossAxisAlignment _crossAlign(String? v) => switch (v) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        'stretch' => CrossAxisAlignment.stretch,
        _ => CrossAxisAlignment.start,
      };

  MainAxisAlignment _mainAlign(String? v) => switch (v) {
        'center' => MainAxisAlignment.center,
        'end' => MainAxisAlignment.end,
        'between' => MainAxisAlignment.spaceBetween,
        'around' => MainAxisAlignment.spaceAround,
        _ => MainAxisAlignment.start,
      };

  Widget _text(Map<String, Object?> n, Color fg) {
    final w = _num(n['weight'])?.round();
    final style = TextStyle(
      fontSize: _num(n['size']) ?? 13,
      height: _num(n['lh']),
      fontWeight: w == null ? null : _weight(w),
      // font 字段：插件想换字体时显式指定 family（比如时钟用圆体数字）。
      // 不传就继承卡片默认字体（全局字体，见 card_view），老插件行为不变。
      fontFamily: _str(n['font']),
      color: (_color(n['color']) ?? fg)
          .withValues(alpha: _num(n['opacity']) ?? 1.0),
      // glow 字段：文字辉光（霓虹效果）。给颜色就发光，sigma 控制光晕
      // 半径（默认 8）。两层 shadow 叠加——内层实、外层虚，做出光晕
      // 渐变而不是一圈生硬的描边。歌词插件用它在"正在唱"那一行上。
      shadows: n['glow'] == null
          ? null
          : _glow(_color(n['glow']) ?? fg, _num(n['glowSigma']) ?? 8),
      fontFeatures: n['mono'] == true
          ? const [FontFeature.tabularFigures()]
          : null,
      // spacing 字段：字间距（px）。中文小字（农历、日期）加一点点间距
      // 就没那么挤；不传为 null，维持系统默认。
      letterSpacing: _num(n['spacing']),
      decoration: n['strike'] == true
          ? TextDecoration.lineThrough
          : TextDecoration.none,
    );

    // 抽成"给一个字符串就画出来"的回调：翻页过渡要同时画旧值和新值
    // （各自取上半/下半页），没法只拿一个现成的 Text。
    Widget buildText(String value) => Text(
          value,
          maxLines: _num(n['maxLines'])?.round(),
          overflow: n['maxLines'] != null ? TextOverflow.ellipsis : null,
          textAlign: switch (_str(n['align'])) {
            'center' => TextAlign.center,
            'end' => TextAlign.end,
            _ => TextAlign.start,
          },
          // 样式交给外层（AnimatedDefaultTextStyle）以便过渡；关闭动画时
          // 直接把 style 挂在 Text 上，省一层。
          style: widget.animate ? null : style,
        );

    final text = buildText(_str(n['v']) ?? '');

    // AnimatedDefaultTextStyle：文字颜色/透明度/字重/删除线在两次 render
    // 之间变化时平滑过渡。待办项"划掉"和歌词"当前行高亮"都是这条路径——
    // 以前颜色、删除线是硬切，一眼能看出状态被替换而不是被改变。
    //
    // 字体继承：style 里的 fontFamily 多半是 null（继承卡片字体），如果直接
    // 把它塞给 AnimatedDefaultTextStyle，这层 DefaultTextStyle 会**遮住**
    // 外面卡片设的字体环境——Text 向上合并时只会合并到这一层为止，
    // fontFamily 是 null 就落回全局默认字体，卡片的圆体字全丢了。
    // 所以先把当前环境样式整个解析进来（base.merge），再以 inherit:false
    // 定稿，让这一层就是"最终答案"而不是"又一层部分答案"。
    if (!widget.animate) return text;
    final resolved = DefaultTextStyle.of(context).style.merge(style).copyWith(
          inherit: false,
        );
    // 文字内容变化过渡：**必须由插件显式声明**（trans: true / 'flip'）——
    // 这个项目当年专门移除过内容切换动画（真实渲染下闪白，见文件尾部
    // 注释），测试也锁着"替换瞬间旧内容必须退场"的契约。时钟数字这类
    // 固定位置的值才声明 trans，过渡才不会在别处复活闪白。
    // AnimatedSwitcher 对内容没变的重绘不会重播——key 相同直接复用。
    // trans 是布尔开关，别用 _str 读（它只认 String，bool 永远落空）
    // trans 有两种模式：
    //   true     交叉淡入 + 轻微上移（通用，适合日期/星期这类文字）
    //   'flip'   机械翻页（时钟数字用，见 flip_transition.dart）
    if (n['trans'] == 'flip') {
      return AnimatedDefaultTextStyle(
        duration: kNodeAnimDuration,
        curve: kNodeAnimCurve,
        style: resolved,
        softWrap: true,
        child: FlipTransition(
          value: _str(n['v']) ?? '',
          textBuilder: buildText,
        ),
      );
    }
    if (n['trans'] != true) {
      return AnimatedDefaultTextStyle(
        duration: kNodeAnimDuration,
        curve: kNodeAnimCurve,
        style: resolved,
        softWrap: true,
        child: text,
      );
    }
    return AnimatedDefaultTextStyle(
      duration: kNodeAnimDuration,
      curve: kNodeAnimCurve,
      style: resolved,
      softWrap: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (c, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(anim),
            child: c,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_str(n['v']) ?? ''),
          child: text,
        ),
      ),
    );
  }

  /// 两层 shadow 做"贴着笔画"的辉光。
  ///
  /// 之前犯过的错：三层 + 5 倍半径的扩散光，光晕从笔画向外铺几十像素，
  /// 整行文字的区域都被照亮，看起来是"这一行整体加亮"而不是"字在发光"。
  /// 发光感来自"光紧贴轮廓、快速衰减"——内层（0.6x）几乎是描边级的实光，
  /// 外层（1.8x）才是光晕，再往外就没有了。sigma 由调用方按字号给，
  /// 大字给 8~10、小字给 4~5，让光晕半径始终小于字间距。
  List<Shadow> _glow(Color color, double sigma) {
    final base = color.withValues(alpha: (color.a * 0.9).clamp(0.0, 1.0));
    return [
      Shadow(color: base, blurRadius: sigma * 0.6),
      Shadow(color: base.withValues(alpha: base.a * 0.45), blurRadius: sigma * 1.8),
    ];
  }

  FontWeight _weight(int w) {
    const map = {
      100: FontWeight.w100, 200: FontWeight.w200, 300: FontWeight.w300,
      400: FontWeight.w400, 500: FontWeight.w500, 600: FontWeight.w600,
      700: FontWeight.w700, 800: FontWeight.w800, 900: FontWeight.w900,
    };
    return map[(w ~/ 100) * 100] ?? FontWeight.w400;
  }

  EdgeInsets _pad(Object? v) {
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List && v.length == 2) {
      return EdgeInsets.symmetric(
          vertical: (v[0] as num).toDouble(), horizontal: (v[1] as num).toDouble());
    }
    if (v is List && v.length == 4) {
      return EdgeInsets.fromLTRB(
        (v[3] as num).toDouble(), (v[0] as num).toDouble(),
        (v[1] as num).toDouble(), (v[2] as num).toDouble(),
      );
    }
    return EdgeInsets.zero;
  }

  Widget _box(Map<String, Object?> n, Color fg) {
    // AnimatedContainer：插件重绘时底色/圆角/内边距/尺寸的变化会自己滑过去。
    // 待办勾选项的灰底变化、歌词卡按钮的禁用态底变化都靠这一处——
    // 以前是硬切，同一张卡片上"图标在形变、底色却啪一下"很违和。
    final animate = widget.animate;
    Widget w = AnimatedContainer(
      duration: animate ? kNodeAnimDuration : Duration.zero,
      curve: kNodeAnimCurve,
      width: _num(n['w']),
      height: _num(n['h']),
      padding: _pad(n['pad']),
      alignment: n['center'] == true ? Alignment.center : null,
      // clip:true 给固定宽高的盒子裁掉超出部分。插件按估算的文字尺寸给
      // 每一行分配固定高度时，字体真实行高和插件估的数字对不上是常态
      // （不同语言/字重的行高差异本来就没法在 JS 里精确算出来）——与其让
      // 估算误差累加成一整块内容顶穿卡片底边（RenderFlex 的溢出警告只在
      // debug 下画出来，release 下用户看到的是内容被无声裁掉，同样难看），
      // 不如让每个盒子自己兜底裁一刀，误差只会体现成"这一行文字被裁了
      // 一两像素"，而不是"歌词区整体溢出卡片"。
      clipBehavior: n['clip'] == true ? Clip.hardEdge : Clip.none,
      decoration: BoxDecoration(
        color: _color(n['bg']),
        borderRadius: BorderRadius.circular(_num(n['radius']) ?? 0),
        border: n['border'] == null
            ? null
            : Border.all(color: _color(n['border']) ?? Colors.white24, width: 1),
      ),
      // 关键：clipBehavior 会在孩子外面套一层 ClipPath，而 ClipPath 传下去的
      // 是**松约束**（0<=w<=可用宽）。外层 Column 是 MainAxisSize.min +
      // crossAxisAlignment.start，拿到松约束就缩到自己最宽那行文字的宽度
      // （实测歌词取景框塌成 85.5px、单行塌成 48.8px），整块歌词被挤成
      // 左侧一条细缝，看起来就是"歌词区一片空白"。
      //
      // 所以裁切盒必须自己把**横向约束收紧**：给个 infinity 宽的 SizedBox，
      // 让孩子的宽度确定下来（高度仍由盒子的 h 决定）。
      //
      // 高度方向反过来：裁切盒**允许孩子超出**。取景框的高度是外层 flex
      // 给的、事先算不准（歌词区的头部随卡片尺寸变），而里面滚动的整列
      // 歌词天然比取景框高——这正是"取景框"存在的意义。若把高度收紧了，
      // 内层 Column 会报 RenderFlex overflow（debug 黄黑条，release 无声
      // 裁掉）。用 OverflowBox 把孩子的高度约束放开，让它按natural size
      // 布局，再由 ClipPath 裁掉越界部分。
      child: n['child'] == null
          ? null
          : (n['clip'] == true
              ? SizedBox(
                  width: double.infinity,
                  child: OverflowBox(
                    minHeight: 0,
                    maxHeight: double.infinity,
                    alignment: Alignment.topCenter,
                    child: _child(n, fg),
                  ),
                )
              : _child(n, fg)),
    );
    // 渐变遮罩：顶部和底部淡出，让滚出视口的内容自然消失。
    // fade 是遮罩渐变的相对高度比例（0~0.5），默认 0.15。
    if (n['gradientMask'] == true) {
      final fade = _num(n['fade']) ?? 0.15;
      w = ShaderMask(
        shaderCallback: (rect) {
          final f = fade.clamp(0.01, 0.45);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, f, 1.0 - f, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: w,
      );
    }
    return w;
  }

  /// 固定列数的网格。用 Column+Row 而不是 GridView：日历要的是确定的行列，
  /// 而且卡片里不需要滚动虚拟化。
  Widget _grid(Map<String, Object?> n, Color fg) {
    final cols = (_num(n['cols']) ?? 7).round().clamp(1, 12);
    final gap = _num(n['gap']) ?? 4;
    // fill：让各行均分可用高度。放在 flex 里却不开这个的话，网格会缩在顶部，
    // 卡片放大后中间留一大块空白。
    final fill = n['fill'] == true;
    final kids = _children(n['children']);
    final rows = <Widget>[];
    for (var i = 0; i < kids.length; i += cols) {
      final slice = kids.sublist(i, (i + cols).clamp(0, kids.length));
      final cells = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0 && gap > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(
          child: j < slice.length ? _build(slice[j], fg) : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty && gap > 0) rows.add(SizedBox(height: gap));
      rows.add(fill ? Expanded(child: Row(children: cells)) : Row(children: cells));
    }
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: rows,
    );
  }

  Widget _tap(Map<String, Object?> n, Color fg) {
    final id = _str(n['id']);
    return _TapFeedback(
      animate: widget.animate,
      onTap: id == null ? null : () => widget.onEvent(id, const {}),
      child: _child(n, fg),
    );
  }

  Widget _input(Map<String, Object?> n, Color fg) {
    final id = _str(n['id']) ?? 'input';
    _usedInputIds.add(id);
    final value = _str(n['value']) ?? '';
    final ctrl = _controllers.putIfAbsent(id, () => TextEditingController(text: value));
    // 插件主动改了值（例如提交后清空）才覆盖，避免打字时被回写打断
    if (ctrl.text != value && !(n['live'] == true)) {
      ctrl.value = TextEditingValue(
          text: value, selection: TextSelection.collapsed(offset: value.length));
    }
    final submit = _str(n['submit']);
    // 输入框的颜色全部从 fg 派生（fg 是卡片前景色，深浅色自动翻转）：
    // 提示文字、填充底色、光标都跟着明暗走，否则浅色卡上硬编码的白色
    // 提示和底纹会看不见（todo 添加框踩过）。
    return TextField(
      controller: ctrl,
      style: TextStyle(fontSize: _num(n['size']) ?? 13, color: fg),
      cursorColor: fg.withValues(alpha: 0.8),
      cursorHeight: (_num(n['size']) ?? 13) + 2,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        hintText: _str(n['placeholder']),
        hintStyle: TextStyle(color: fg.withValues(alpha: 0.35), fontSize: 12),
        filled: true,
        fillColor: fg.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onSubmitted: submit == null
          ? null
          : (text) {
              widget.onEvent(submit, {'value': text});
              ctrl.clear();
            },
    );
  }

  /// 图片节点：{t:'image', key, w, h, radius, fit}
  ///
  /// 插件只给 key，不给字节。字节由宿主取、解码、缓存（见 WidgetImages 的
  /// 注释：一张封面十几万字节，塞进 UI 树等于每次 render 都序列化一遍）。
  /// key 查不到就画一个占位方块——封面是异步解码的，第一帧必然还没有。
  Widget _image(Map<String, Object?> n, Color fg) {
    final key = _str(n['key']);
    final w = _num(n['w']);
    final h = _num(n['h']);
    final radius = _num(n['radius']) ?? 0;

    // 监听缓存版本号：图片解码完成时这一帧早就画过了，不重建就永远是占位图
    return ValueListenableBuilder<int>(
      valueListenable: WidgetImages.revision,
      builder: (context, _, child) {
        final current = key == null ? null : WidgetImages.get(key);
        final Widget child;
        if (current == null) {
          child = Container(
            width: w,
            height: h,
            color: const Color(0x14FFFFFF),
            alignment: Alignment.center,
            child: Icon(Icons.music_note_rounded,
                size: (w ?? 32) * 0.32, color: fg.withValues(alpha: 0.25)),
          );
        } else {
          child = RawImage(
            image: current,
            width: w,
            height: h,
            fit: switch (_str(n['fit'])) {
              'contain' => BoxFit.contain,
              'fill' => BoxFit.fill,
              _ => BoxFit.cover,
            },
            filterQuality: FilterQuality.medium,
          );
        }
        // 换歌时封面是异步解码的：占位图 → 封面直接闪一下很生硬。
        // 交叉淡入 260ms，封面晚到也能平滑补上；关掉动画时保持直切。
        final Widget framed = radius <= 0
            ? child
            : ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: child,
              );
        if (!widget.animate) return framed;
        return AnimatedSwitcher(
          duration: kNodeAnimDuration,
          switchInCurve: kNodeAnimCurve,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (c, anim) =>
              FadeTransition(opacity: anim, child: c),
          child: KeyedSubtree(
            key: ValueKey(current == null ? 'ph:${w}x$h' : 'img:$key'),
            child: framed,
          ),
        );
      },
    );
  }

  /// 可拖动的滑条：{t:'slider', id, v, h, color, bg, enabled}
  ///
  /// 与 progress 的区别就是能拖。做成独立节点而不是给 progress 加属性，
  /// 是因为它要维护"拖拽中"的本地状态，和只读的进度条不是一回事。
  Widget _slider(Map<String, Object?> n) {
    final id = _str(n['id']);
    final enabled = n['enabled'] != false && id != null;
    return _PluginSlider(
      value: (_num(n['v']) ?? 0).clamp(0.0, 1.0),
      height: _num(n['h']) ?? 4,
      color: _color(n['color']) ?? const Color(0xFF7CC7FF),
      background: _color(n['bg']) ?? const Color(0x22FFFFFF),
      enabled: enabled,
      onChanged: enabled ? (v) => widget.onEvent(id, {'value': v}) : null,
    );
  }

  IconData _icon(String? name) => iconDataFor(name);

  /// 支持 #RGB / #RRGGBB / #RRGGBBAA
  Color? _color(Object? v) {
    if (v is num) return Color(v.toInt());
    if (v is! String || v.isEmpty) return null;
    var s = v.startsWith('#') ? v.substring(1) : v;
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
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }
}

/// 滑条本体。
///
/// 拖拽期间用本地值跟手，松手才把结果回调给插件——插件那边是异步的
/// （seek 要经过通道到 native 再到播放器），等它回来再更新的话，
/// 手指在拖、条却一顿一顿地追，手感立刻就散了。
class _PluginSlider extends StatefulWidget {
  const _PluginSlider({
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
  State<_PluginSlider> createState() => _PluginSliderState();
}

class _PluginSliderState extends State<_PluginSlider> {
  /// 拖拽中的本地值；null 表示没在拖，显示插件给的值
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
///
/// 控制器值 0 = 前脸静止，1 = 后脸静止。
/// 翻到后脸：forward(0→1)；翻回前脸：reverse(1→0)。
/// value < 0.5 显示前脸，>= 0.5 显示后脸，两面各自做 rotateX + 淡入淡出。
class _FlipSwap extends StatefulWidget {
  const _FlipSwap({
    required this.flipKey,
    required this.front,
    required this.back,
  });

  final String flipKey;
  final Widget front;
  final Widget back;

  @override
  State<_FlipSwap> createState() => _FlipSwapState();
}

class _FlipSwapState extends State<_FlipSwap>
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
  void didUpdateWidget(_FlipSwap old) {
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

/// 上浮切换动画（_SlideSwap）已在 dc2a61b 之后被移除：真实渲染下换行动画
/// 会闪白约 200ms（所有过渡形式：滑动 / 淡入淡出都闪，无动画版本不闪）。
/// 需要恢复动画时从 git 历史（18ca340 引入、dc2a61b 纯滑动）取回实现，
/// 但必须先定位真实渲染的闪白机制——flutter_test 的 toImage 对
/// TransformLayer 有固有伪影（最小化 SlideTransition 对照实验同样全空白），
/// 测试环境无法复现/验证真实渲染。换行现在走原地替换。

/// 可点元素的按压反馈：按下轻微缩小 + 变淡，松手弹回。
///
/// 苹果 HIG 的触感语言——"按下去有东西让位给你"。以前 tap 节点按下毫无
/// 反应，上一曲/下一曲点了像没点上。scale 收着放（0.96）不抢戏：大区域
/// （整行待办）和小按钮（媒体控制）用同一个量级都不会夸张。
class _TapFeedback extends StatefulWidget {
  const _TapFeedback({
    required this.child,
    required this.animate,
    this.onTap,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onTap;

  @override
  State<_TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<_TapFeedback> {
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
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _pressed = false),
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

/// 图标名 → 字体图标。形变表（morph_icons.dart 的 kMorphIconPaths）里的
/// 名字也会走到这里作为兜底——两份表的一致性由 test/memory_test.dart 的
/// morphNamesHaveFontFallback 锁住。
@visibleForTesting
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
