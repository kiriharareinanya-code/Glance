/// 组件库里的实时预览。
///
/// 用一个独立的控制器 + 隔离宿主把组件真实跑起来：时钟会走、天气会拉数、
/// 歌词会读媒体状态——预览是真的，不是静态图。宿主挂在临时目录的 Store 上，
/// 不碰真实 pluginData；离开组件库页时随 widget 销毁，定时器一起回收。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/grid.dart';
import '../model/card.dart';
import '../store/store.dart';
import '../widgets/catalog.dart';
import '../widgets/context.dart';
import '../widgets/node.dart';
import '../widgets/spec.dart';

class BuiltinPreview extends StatefulWidget {
  const BuiltinPreview({super.key, required this.spec});

  final BuiltinSpec spec;

  @override
  State<BuiltinPreview> createState() => _BuiltinPreviewState();
}

class _BuiltinPreviewState extends State<BuiltinPreview> {
  BuiltinController? _controller;
  WidgetContext? _ctx;
  PxSize _px = const PxSize(200, 200);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    // 预览跑在 ListView 里，滚出屏幕会被 element 回收、dispose 直接到这边
    // （不经过组件库页的 state.dispose）——必须在这里把定时器收干净，否则
    // 真实运行下滚一圈就是一堆孤儿 Timer（时钟秒针、歌词轮询、天气刷新）。
    // 组件库页切页时元素树整体销毁，控制器的 [unmount] 是幂等的，双保险无害。
    _controller?.unmount();
    super.dispose();
  }

  void _boot() async {
    final grid = parseSize(widget.spec.defaultSize) ?? const GridSize(2, 2);
    final px = sizeToPx(grid);
    if (!mounted) return;
    _px = px;

    // 隔离宿主：临时目录的 Store + 一张假卡片。预览的 storage 读写落在
    // 临时目录里，不会进真实 pluginData；http / 媒体状态是真能力（要的就是真预览）。
    final store = Store(p.join(
        Directory.systemTemp.path, 'vectra-preview', widget.spec.id));
    // 关键：必须等 load() 回来。它会扫描 plugindata/ 下的 `.json.broken-*`
    // 残留并 rename，那些是真实文件 I/O；不等就是让元素在挂载中被回收，
    // ctx 的定时器随之失去 owner（测试里表现为"树销毁后仍有 pending Timer"）。
    await store.load();
    if (!mounted) return;

    final card = WidgetCard(
        id: 'preview',
        pluginId: widget.spec.id,
        x: 0,
        y: 0,
        size: widget.spec.defaultSize,
        z: 0);
    final ctx = WidgetContext(
      store: store,
      card: card,
      pluginId: widget.spec.id,
      onRequestSize: (_) {},
      onOpenSettings: () {},
      settings: widget.spec.defaultSettings(),
      grid: grid,
      size: Size(px.w.toDouble(), px.h.toDouble()),
    );

    final controller = createBuiltinController(widget.spec.id, ctx);
    try {
      controller.mount();
    } catch (_) {
      return;
    }
    if (!mounted) {
      controller.unmount();
      return;
    }
    setState(() {
      _controller = controller;
      _ctx = ctx;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // 首帧就换成一个不会被打断的骨架：mount() 是异步的，等 store.load()
      // 回来时元素可能已经被滚出视口回收——那种情况下 ctx 挂着真定时器却
      // 没有任何 owner 去收，就是孤儿。守门禁在这里。
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(
          child: Icon(Icons.hourglass_empty_rounded, size: 20, color: Colors.white24),
        ),
      );
    }
    final ctx = _ctx;
    if (ctx == null) return const SizedBox(width: 200, height: 200);
    // 固定成组件的默认尺寸，外层 FittedBox 负责等比缩小
    return SizedBox(
      width: _px.w,
      height: _px.h,
      // 面板跑在 FluentApp 里，没有 Material 祖先；树里的 input 节点
      // 渲染 Material 的 TextField，缺 Material 会抛异常。透明 Material 只补
      // 祖先链、不画任何东西。
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: const Color(0x0A000000),
            child: ValueListenableBuilder<Map<String, Object?>?>(
              valueListenable: ctx.tree,
              builder: (context, tree, _) => NodeView(
                tree: tree,
                onEvent: (_, _) {}, // 预览不响应交互
                animate: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
