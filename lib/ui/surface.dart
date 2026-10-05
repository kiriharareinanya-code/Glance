/// 桌面层：所有磁贴都画在这一个全屏透明窗口里。
///
/// 与 Electron 版最大的结构差异：那边一个磁贴一个窗口，拖拽要跨进程同步，
/// 于是有心跳、看门狗、指针捕获丢失的一堆补丁。这里全在同一个窗口内，
/// 指针事件不会跨窗口丢失，那套补丁整体不需要。
///
/// 但保留两条兜底，它们防的是真实存在的情况：
///   - 指针键位为 0 却没收到 up（在别的窗口上松手）-> 立即结束拖拽
///   - pointerCancel（被系统抢走，例如触摸手势升级）-> 立即结束拖拽
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../core/hit.dart';
import '../core/logger.dart';
import '../core/perf_probe.dart';  // 【临时诊断】
import '../core/snap.dart' as snap;
import '../model/card.dart';
import '../model/settings.dart';
import '../native/native_bridge.dart';
import '../widgets/kit.dart' show NodePointer;
import '../store/store.dart';
import 'card_view.dart';
import 'guides.dart';

/// 触摸长按进入编辑模式的时长
const Duration kLongPress = Duration(milliseconds: 500);

/// 长按期间允许的最大位移，超过就判定为滑动，交给插件
const double kLongPressSlop = 10;

/// 编辑模式无操作后自动退出
const Duration kEditIdle = Duration(seconds: 8);

class DesktopSurface extends StatefulWidget {
  const DesktopSurface({
    super.key,
    required this.state,
    required this.store,
    required this.buildPluginBody,
    this.onCardSecondaryTap,
    this.onCardAnchor,
  });

  final AppState state;
  final Store store;

  /// 卡片内容由外部注入（原生组件）
  final Widget Function(WidgetCard card, Size size) buildPluginBody;

  /// 右键卡片：打开控制面板并定位到这张卡片
  final void Function(WidgetCard card)? onCardSecondaryTap;

  /// 卡片落位之后记一次"它现在在哪块屏的哪个位置"。
  ///
  /// 由外层实现：显示器矩形和窗口矩形都在 app_root 那边缓存着，
  /// 这里再问一遍 native 只是重复。落点不记的话，下次接屏/拔屏时这张卡
  /// 会按**上一个**落点被钉回去。
  final void Function(WidgetCard card)? onCardAnchor;

  // 这里原先有个 extraHit：当年 AI 侧边栏和磁贴共用一个窗口时，
  // 用它把侧边栏矩形并进窗口区域。侧边栏拆成独立窗口之后就没人再传了，
  // 一直是死代码，已删除。

  @override
  State<DesktopSurface> createState() => DesktopSurfaceState();
}

class DesktopSurfaceState extends State<DesktopSurface> {
  AppSettings get _settings => widget.state.settings;
  List<WidgetCard> get _cards => widget.state.cards;

  // 拖拽会话
  int? _dragPointer;
  WidgetCard? _dragCard;
  Offset _grabOffset = Offset.zero;
  bool _moved = false;

  /// 整场拖拽里只有被拖的那张卡在动，其余卡片一动不动。
  ///
  /// 所以这份"别人在哪"的矩形表在按下那一刻算一次就够，不必每帧重建 ——
  /// 每帧重建等于每帧 N 次 Rect 分配，拖得越久越像在自己给自己制造垃圾。
  List<snap.Rect> _dragOthers = const [];

  /// 拖拽期间的窗口可视范围，同样按下时取一次（拖拽中窗口尺寸不会变）。
  Size _dragBounds = Size.zero;

  /// 每张卡一份的位置信号。
  ///
  /// 这是本文件最重要的一次结构性调整：以前拖拽每来一个 pointer move 就
  /// setState 整个 surface，于是**每帧**都要重建 Stack 里全部 N 张卡——
  /// 不光是定位那一行，是每张卡的 CardView 和插件正文（buildPluginBody）
  /// 全部重跑一遍。5 张卡就是每帧 5 份插件渲染树，帧预算直接被吃光。
  ///
  /// 现在位置只写进这一个 notifier，由 [_CardTile] 自己监听：被拖的那张卡
  /// 重建，其余卡片连 build 都不会进。surface 本身在拖拽期间一次也不重建。
  final Map<String, ValueNotifier<Offset>> _pos =
      <String, ValueNotifier<Offset>>{};

  /// 正在被拖的卡片 id（null = 没在拖）。
  ///
  /// 拖拽期间所有卡片的位移动画都必须掐成零时长（见 [_animDuration] 的说明：
  /// 跟手的和缓动的放在一起，整屏看起来在颤）。把它做成 notifier 而不是字段，
  /// 是为了让"开始拖/结束拖"这两个瞬间不必重建整个 surface 就能生效。
  final ValueNotifier<String?> _dragId = ValueNotifier<String?>(null);

  /// 吸附辅助线。拖拽中每帧都在变，同样走 notifier，免得为它重建整个 surface。
  final ValueNotifier<List<snap.Guide>> _guides =
      ValueNotifier<List<snap.Guide>>(const []);

  // 触摸编辑模式
  String? _editingId;
  Offset? _touchStart;

  // 用可取消的 Timer 而不是 Future.delayed：后者撤不掉，widget 销毁后仍会触发，
  // 既是资源泄漏，也会让 widget 测试因"仍有未完成的 Timer"整体失败。
  Timer? _longPressTimer;
  Timer? _editIdleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clampIntoScreen();
      _pushRegion();
    });
  }

  /// 把跑到屏幕外的卡片拉回来。
  ///
  /// 卡片整个落到可视区之外就再也够不着了：看不见，也就点不到、拖不动。
  /// 换分辨率、调大网格单元、插拔显示器都可能造成这种情况。
  void _clampIntoScreen() {
    final bounds = MediaQuery.of(context).size;
    var changed = false;
    for (final c in _cards) {
      final size = _px(c);
      final nx = snap.clamp(c.x, 0, math.max(0.0, bounds.width - size.w));
      final ny = snap.clamp(c.y, 0, math.max(0.0, bounds.height - size.h));
      if (nx != c.x || ny != c.y) {
        _setPos(c, nx, ny);
        changed = true;
      }
    }
    if (changed) {
      Log.i('surface', '有卡片超出可视区，已拉回');
      widget.store.save(widget.state);
      setState(() {});
    }
  }

  @override
  @override
  void dispose() {
    _longPressTimer?.cancel();
    _editIdleTimer?.cancel();
    // 子元素在这个 State 的 dispose 之前就已经 unmount 掉了，它们的监听器
    // 也都摘干净了，所以这里销毁信号是安全的。
    _dragId.dispose();
    _guides.dispose();
    for (final n in _pos.values) {
      n.dispose();
    }
    _pos.clear();
    super.dispose();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  // ---------------- 位置信号 ----------------

  /// 挪动一张卡：数据字段和位置信号必须一起改，两边分家会让
  /// "存档里的坐标"和"屏幕上的坐标"慢慢对不上。
  ///
  /// 注意这里**故意不调 setState**：坐标只影响 [_CardTile] 内部的
  /// AnimatedPositioned，让它自己重建就够了，拖拽时不必重建整面墙。
  void _setPos(WidgetCard c, double x, double y) {
    c.x = x;
    c.y = y;
    _pos[c.id]?.value = Offset(x, y);
  }

  @override
  void didUpdateWidget(DesktopSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外层（显示器插拔对账、面板改网格尺寸…）会直接改 card.x/y。改了就得把
    // 位置信号拉齐，否则卡片数据已经挪了、tile 还按旧坐标画，动画会把它从
    // 旧位置慢慢挪过来——看起来像"自己飘了一下"。
    for (final c in _cards) {
      _pos[c.id]?.value = Offset(c.x, c.y);
    }
    // 卡片被删掉后，它的信号没人用了，放掉（量级极小，但别让 Map 无限长）
    if (_pos.length != _cards.length) {
      final alive = {for (final c in _cards) c.id};
      _pos.removeWhere((id, n) {
        if (alive.contains(id)) return false;
        n.dispose();
        return true;
      });
    }
  }

  double get _dpr => MediaQuery.of(context).devicePixelRatio;

  PxSize _px(WidgetCard c) => c.pxSize(_settings.gridCell, _settings.gridGap);

  /// 把卡片矩形推给 native。对外公开，供外层在需要时确定性地重推一次。
  void pushRegion() => _pushRegion();

  /// 上一次推给 native 的几何快照，用来判断"卡片形状到底变没变"。
  ///
  /// 这里存的是数值而不是一串拼出来的签名文本：这份检查在**每次 surface 重建
  /// 之后**都要问一遍，而重建虽然比从前少了（拖拽不再重建整面墙），加卡/删卡/
  /// 改尺寸/面板改设置这些路径仍然会触发。每次现拼一个几百字节的字符串只为
  /// 跟上一轮比一比，是纯浪费——比对本身不分配，需要更新时才回填。
  final List<Object> _geomSnapshot = <Object>[];

  /// 会影响窗口区域的所有量：每张卡片的位置和尺寸，加上圆角与缩放。
  /// 这些里面任何一个变了，native 那边的裁剪就过期了。
  ///
  /// 返回 true 表示和 [_geomSnapshot] 对不上（也就是几何变了）。
  bool _geometryChanged() {
    final cards = _cards;
    if (_geomSnapshot.length != 2 + cards.length * 5) return true;
    var i = 0;
    if (_geomSnapshot[i++] != _settings.cardRadius) return true;
    if (_geomSnapshot[i++] != _dpr) return true;
    for (final c in cards) {
      final s = _px(c);
      if (_geomSnapshot[i++] != c.id) return true;
      if (_geomSnapshot[i++] != c.x) return true;
      if (_geomSnapshot[i++] != c.y) return true;
      if (_geomSnapshot[i++] != s.w) return true;
      if (_geomSnapshot[i++] != s.h) return true;
    }
    return false;
  }

  void _rememberGeometry() {
    _geomSnapshot
      ..clear()
      ..addAll(<Object>[_settings.cardRadius, _dpr]);
    for (final c in _cards) {
      final s = _px(c);
      _geomSnapshot.addAll(<Object>[c.id, c.x, c.y, s.w, s.h]);
    }
  }

  /// 每帧落定后自检一次：卡片几何变了就把新区域推给 native。
  ///
  /// 做成"自动对账"而不是让每个调用方各自记得推，是因为漏推的代价既隐蔽又严重：
  /// 窗口被 SetWindowRgn 硬裁成卡片矩形的并集，区域之外既不绘制也不接收输入。
  /// 区域一旦过期，新加的卡片画了也会被裁掉——看不见，也点不到；而桌面上一张
  /// 卡片都没有的时候，连"拖一下别的卡片顺带把区域刷新掉"这条退路都没有，
  /// 只能重启。
  ///
  /// 这不是假想的风险：加卡、删卡、插件请求改尺寸、面板里改网格/圆角，
  /// 四条路径全都漏推过（见本次提交）。与其在每条路径末尾各加一行、
  /// 且指望以后每个新路径都记得加，不如让 surface 自己盯着几何对账。
  void _syncRegion() {
    if (!mounted) return;
    // 拖拽期间 native 那边是整窗放开的（见 _onPointerMove 与 _endDrag 的注释），
    // 这时推区域等于把卡片重新裁回去，会拖到一半"卡"住。松手时 _endDrag 补推。
    if (_dragCard != null) return;
    if (!_geometryChanged()) return;
    _pushRegion();
  }

  void _pushRegion() {
    final cards = <HitRect>[
      for (final c in _cards)
        HitRect(
          id: c.id,
          x: c.x,
          y: c.y,
          w: _px(c).w,
          h: _px(c).h,
          z: c.z.toDouble(),
        ),
    ];
    // 显式推送也要记账，否则自动对账会以为区域还是旧的，白推一次
    _rememberGeometry();
    NativeBridge.setRegion(
      cards: cards,
      // 辅助线只在拖拽时出现，而拖拽期间区域整窗放开，无需为它加矩形
      extra: const [],
      radius: _settings.cardRadius,
      devicePixelRatio: _dpr,
    );
  }

  /// 命中：返回指针下最上层的卡片
  WidgetCard? _cardAt(Offset p) {
    final rects = [
      for (final c in _cards)
        HitRect(
            id: c.id,
            x: c.x,
            y: c.y,
            w: _px(c).w,
            h: _px(c).h,
            z: c.z.toDouble()),
    ];
    final id = topmostAt(p.dx, p.dy, rects, radius: _settings.cardRadius);
    if (id == null) return null;
    return _cards.firstWhere((c) => c.id == id);
  }

  void _raise(WidgetCard card) {
    final maxZ = _cards.fold<int>(0, (m, c) => c.z > m ? c.z : m);
    if (card.z != maxZ) card.z = maxZ + 1;
  }

  // ---------------- 指针 ----------------

  void _onPointerDown(PointerDownEvent e) {
    // 插件里的滑条之类控件已经接管了这次指针，就不要再拖卡片。
    // 指针事件是从最内层往外派发的，所以这里读到的一定是插件刚置的位。
    // 少了这一条，拖进度条会把整张卡片一起拖走。
    if (NodePointer.isGrabbed(e.pointer)) return;

    final card = _cardAt(e.localPosition);
    if (card == null) return;

    final isTouch = e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.stylus;

    // 右键卡片 = 打开这张卡片的设置
    if (!isTouch && (e.buttons & kSecondaryButton) != 0) {
      widget.onCardSecondaryTap?.call(card);
      return;
    }

    // 只有左键能拖。漏掉这条判断的后果是实打实的：右键菜单、中键等任何按键
    // 都会启动一次拖拽，卡片被悄悄挪走。（实测右键点在卡片上就把布局搞乱了）
    if (!isTouch && (e.buttons & kPrimaryButton) == 0) return;

    setState(() => _raise(card));

    if (_settings.locked) return;

    if (isTouch) {
      // 手机桌面的语义：轻点交给插件，长按才进编辑模式，编辑模式下直接拖
      if (_editingId == card.id) {
        _beginDrag(e, card);
        return;
      }
      _touchStart = e.position;
      _cancelLongPress();
      _longPressTimer = Timer(kLongPress, () {
        _longPressTimer = null;
        if (!mounted) return;
        setState(() => _editingId = card.id);
        _scheduleEditIdle();
      });
      return;
    }

    _beginDrag(e, card);
  }

  void _beginDrag(PointerEvent e, WidgetCard card) {
    // 拖拽期间不再改窗口区域：每帧 SetWindowRgn 会与绘制打架，拖出残影
    NativeBridge.setDragging(true);
    _dragPointer = e.pointer;
    _dragCard = card;
    _grabOffset = e.localPosition - Offset(card.x, card.y);
    _moved = false;
    // 吸附和防重叠都要拿"别人在哪"。整场拖拽只有被拖的这张在动，所以这两样
    // 拖拽期间不变——按下时取一次即可，不必每个 pointer move 重算一遍。
    _dragOthers = [
      for (final c in _cards)
        if (c.id != card.id) snap.Rect(c.x, c.y, _px(c).w, _px(c).h),
    ];
    _dragBounds = MediaQuery.of(context).size;
    // 拖拽期间所有卡片的位移动画掐成零（见 _animDuration）。走 notifier 而不是
    // setState：这一次全量重建是必要的，但只有"开始拖"这一次。
    _dragId.value = card.id;
  }

  void _onPointerMove(PointerMoveEvent e) {
    // 长按未触发时，移动超过阈值就当作滑动，取消长按
    if (_longPressTimer != null && _touchStart != null) {
      if ((e.position - _touchStart!).distance > kLongPressSlop) {
        _cancelLongPress();
      }
    }

    if (_dragPointer != e.pointer || _dragCard == null) return;

    // 已经松手却没收到 up（在别的窗口上松开）——立刻收尾，否则卡片粘在指针上
    if (e.buttons == 0 && e.kind == PointerDeviceKind.mouse) {
      _endDrag();
      return;
    }

    final card = _dragCard!;
    final size = _px(card);
    final target = e.localPosition - _grabOffset;

    // _dragOthers / _dragBounds 在 _beginDrag 里取过一次，整场拖拽不变
    final others = _dragOthers;
    final bounds = _dragBounds;
    late final snap.SnapResult r;
    if (_settings.snapEnabled) {
      r = snap.resolve(
        snap.Rect(target.dx, target.dy, size.w, size.h),
        others,
        threshold: _settings.snapThreshold,
        gutter: _settings.gridGap.toDouble(),
        bounds: (w: bounds.width, h: bounds.height),
      );
    } else {
      r = snap.SnapResult(
        x: snap.clamp(target.dx, 0, bounds.width - size.w),
        y: snap.clamp(target.dy, 0, bounds.height - size.h),
        guides: const [],
        snappedX: false,
        snappedY: false,
      );
    }

    // 磁贴不许互相覆盖——反馈原文就是"多个小组件之间可以覆…"。候选落点
    // 若压在别的卡片上，就**分轴退回**：能走的那一轴继续跟手，被挡的那一轴
    // 保持原位。比整体退回原地方便得多，手感接近 2D 平台游戏的贴墙滑动。
    var nx = r.x;
    var ny = r.y;
    bool overlapped(double x, double y) {
      final t = snap.Rect(x, y, size.w, size.h);
      for (final o in others) {
        if (t.x < o.right && t.right > o.x && t.y < o.bottom && t.bottom > o.y) {
          return true;
        }
      }
      return false;
    }

    // 前置条件"当前位置没叠着"很关键：旧布局、或者上次拖动中途强退留下的
    // 重叠，必须放行，否则这张卡永远拖不出来。挡重叠是为了"别叠出新的"，
    // 不是把已经叠着的锁死。
    if (!overlapped(card.x, card.y) && overlapped(nx, ny)) {
      if (!overlapped(nx, card.y)) {
        ny = card.y; // 只有横向能走
      } else if (!overlapped(card.x, ny)) {
        nx = card.x; // 只有纵向能走
      } else {
        nx = card.x;
        ny = card.y; // 两个方向都被挡，这次原地不动
      }
    }
    final stuck = nx != r.x || ny != r.y;

    // 坐标只写进被拖那张卡自己的位置信号，由 _CardTile 重建它自己。
    // 这里**不再 setState**——整面墙一帧都不必重建，其余卡片连 build 都不进。
    _setPos(card, nx, ny);
    // 位置被挡回去时，原来算出来的对齐线已经不成立了，别再画
    _guides.value = stuck ? const [] : r.guides;
    _moved = true;
    // 这里刻意不调 _pushRegion()：区域已整窗放开，拖拽结束时再恢复
  }

  void _onPointerUp(PointerEvent e) {
    _cancelLongPress();
    if (_dragPointer == e.pointer) _endDrag();
  }

  void _endDrag() {
    final moved = _moved;
    final card = _dragCard;
    _dragPointer = null;
    _dragCard = null;
    _moved = false;
    _dragOthers = const [];
    // 恢复位移动画（一次全量 tile 重建）。先清 _dragCard 再动信号，
    // 这样紧接着的 _pushRegion 才不会被"拖拽中"这条挡掉。
    _dragId.value = null;
    _guides.value = const [];
    // 先关拖拽模式，再推区域，否则 native 会因为仍在拖拽而跳过这次裁剪
    NativeBridge.setDragging(false).then((_) => _pushRegion());
    if (moved && card != null) {
      // 先认家再存盘：存下去的必须是"落点 + 落点所在的屏"这一对，
      // 只存坐标的话，下次布局一变就没法把它放回用户放的地方
      widget.onCardAnchor?.call(card);
    }
    if (moved) widget.store.save(widget.state);
    // 只记落点，不记过程：拖动中每帧都记的话，一次拖拽就能刷几百行，
    // 真正有用的信息反而被冲掉了。
    if (moved && card != null) {
      Log.i('surface',
          '拖动 ${card.pluginId}(${card.id}) 落到 ${card.x.round()},${card.y.round()}');
    }
    if (_editingId != null) _scheduleEditIdle();
  }

  void _scheduleEditIdle() {
    _editIdleTimer?.cancel();
    _editIdleTimer = Timer(kEditIdle, () {
      _editIdleTimer = null;
      if (!mounted) return;
      setState(() => _editingId = null);
    });
  }

  /// 拖拽中的卡片不能有位置动画：动画会让它落后于指针。
  /// 其它卡片、以及松手之后，都用缓动过渡。
  ///
  /// 注：这行曾经被 `【临时定位C】` 改成开头的 `return Duration.zero` 来隔离
  /// 性能问题，后来忘了撤——后果是**卡片位移动画、以及设置里那个
  /// 「动画效果」开关全部失效**（260ms 缓动永远走不到）。现已恢复。
  Duration _animDuration(WidgetCard card) {
    if (!_settings.animations) return Duration.zero;
    // 拖拽期间**所有**卡片一律零时长，不只是被拖的那张。
    //
    // 反馈 Fb0025：拖拽时 UI 会晃动。被拖的卡片是跟手的（零时长），旁边的
    // 卡片却在用 260ms 缓动慢慢挪位——一动一静放在一起，整屏看起来就在颤。
    // 拖拽时把其它卡片的动画也掐掉，画面就干净了。想要彻底关掉这个动效的
    // 话，设置里那个"动画效果（拖拽缓动与插件内容切换）"开关一直都在。
    if (_dragCard != null) return Duration.zero;
    return const Duration(milliseconds: 260);
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.hit('Surface');
    // 卡片几何可能刚被外层改过（加卡/删卡/改尺寸/面板里改网格），
    // 等这一帧落定之后跟 native 对一次账。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRegion());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      // Stack 里全是 Positioned 子节点时，自身会塌缩成约束允许的最小尺寸，
      // 外层 Listener 也就没有命中面积，指针事件永远进不来。必须撑满。
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final card in _sortedByZ())
            _CardTile(
              // key 必须按卡片身份给。子节点是按 z 排序的，按下任意一张卡片都会
              // 改变 z、从而改变列表顺序；没有 key 时 Flutter 按下标复用 element，
              // 同一个 tile 会被换给另一张卡片，于是它从旧卡片的
              // 位置动画到新卡片的位置 —— 表现为按下去的瞬间"抽一下"。
              key: ValueKey(card.id),
              card: card,
              position: _posOf(card),
              // 拖拽信号：非 null 表示"有人在拖"，位移动画要掐成零时长
              dragId: _dragId,
              settings: _settings,
              dataDir: widget.store.dir,
              editing: _editingId == card.id,
              duration: _animDuration(card),
              buildPluginBody: widget.buildPluginBody,
            ),
          // 辅助线自带一层重绘边界：它拖动时每帧都变，没有边界就会把整面墙
          // 的图层拖脏，让已经优化好的卡片绘制白做。
          RepaintBoundary(
            child: ValueListenableBuilder<List<snap.Guide>>(
              valueListenable: _guides,
              builder: (context, guides, _) => GuidesLayer(guides: guides),
            ),
          ),
        ],
      ),
    );
  }

  /// 取出（必要时创建）这张卡的位置信号。
  ///
  /// build 里只读不写：万一这里发现信号和数据对不上，也只是"下一帧被
  /// [didUpdateWidget] 拉齐"，绝不在 build 中途 notify 监听器。
  ValueNotifier<Offset> _posOf(WidgetCard c) {
    final n = _pos[c.id];
    if (n != null) return n;
    final created = ValueNotifier(Offset(c.x, c.y));
    _pos[c.id] = created;
    return created;
  }

  List<WidgetCard> _sortedByZ() {
    final list = [..._cards];
    list.sort((a, b) => a.z.compareTo(b.z));
    return list;
  }
}

/// 桌面层里的一张卡片。
///
/// 单独拆出来的唯一理由是**重建范围**：它自己监听 [position]，被拖的时候只有
/// 它这一棵子树会重建，桌面层（以及其余 N-1 张卡）连 build 都不进。拆之前
/// 一次拖拽要重建全部卡片，卡片一多插件正文（歌词/天气/日历）每帧都得重画，
/// 60fps 的帧预算（16.7ms）根本不够分。
class _CardTile extends StatelessWidget {
  const _CardTile({
    super.key,
    required this.card,
    required this.position,
    required this.dragId,
    required this.settings,
    required this.dataDir,
    required this.editing,
    required this.duration,
    required this.buildPluginBody,
  });

  final WidgetCard card;

  /// 卡片位置。被拖时由 [DesktopSurfaceState._setPos] 每帧写入。
  final ValueNotifier<Offset> position;

  /// 正在被拖的卡片 id；非 null 时位移动画一律零时长
  final ValueNotifier<String?> dragId;

  final AppSettings settings;
  final String dataDir;
  final bool editing;
  final Duration duration;
  final Widget Function(WidgetCard card, Size size) buildPluginBody;

  PxSize get _px => card.pxSize(settings.gridCell, settings.gridGap);

  @override
  Widget build(BuildContext context) {
    // 两层监听：拖拽状态只在外层变（一次拖拽两次），位置在内层变（每帧）。
    // 合成一个 listenable 反而更贵——每帧都要重新订阅一遍。
    return ValueListenableBuilder<String?>(
      valueListenable: dragId,
      builder: (context, dragging, _) => ValueListenableBuilder<Offset>(
        valueListenable: position,
        builder: (context, pos, _) {
          final size = _px;
          // 正在拖的那张必须零时长：动画会让它落后于指针，手感立刻就散了。
          // 其余卡片也一样——一动一静放在一起，整屏看起来就在颤（见 _animDuration）。
          final dur = dragging != null ? Duration.zero : duration;
          return AnimatedPositioned(
            duration: dur,
            curve: Curves.easeOutCubic,
            left: pos.dx,
            top: pos.dy,
            // RepaintBoundary：拖一张卡片时其余卡片的图层可以直接复用，
            // 不必跟着整屏重绘。没有它，2560x1440 下每帧都要重画所有卡片，
            // 掉帧就表现为拖影。
              child: RepaintBoundary(
                child: AnimatedSize(
                  // 同上：这行也被 `【临时定位C】` 掐成了 Duration.zero。
                  // 原值是 `animations ? 280ms : Duration.zero`，恢复后
                  // 「动画效果」开关才同时管到位移（260ms）和尺寸（280ms）。
                  duration: settings.animations
                      ? const Duration(milliseconds: 280)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                child: CardView(
                  card: card,
                  settings: settings,
                  dataDir: dataDir,
                  width: size.w,
                  height: size.h,
                  editing: editing,
                  // 插件按尺寸自己排版（比如歌词卡按高度算能放几行），
                  // 给它的必须是刨掉 CardView 内边距之后的真实可用尺寸，
                  // 不然算出来的内容天生比卡片能装下的更高，底部溢出。
                  child: buildPluginBody(
                    card,
                    Size(
                      math.max(0, size.w - CardView.contentPadding.horizontal),
                      math.max(0, size.h - CardView.contentPadding.vertical),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
