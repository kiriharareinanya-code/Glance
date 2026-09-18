/// 组件库里的实时预览。
///
/// 用一个独立的控制器 + 隔离宿主把组件真实跑起来：时钟会走、天气会拉数、
/// 歌词会读媒体状态——预览是真的，不是静态图。宿主挂在临时目录的 Store 上，
/// 不碰真实 pluginData；离开组件库页时随 widget 销毁，定时器一起回收。
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/grid.dart';
import '../core/paths.dart';
import '../model/card.dart';
import '../store/store.dart';
import '../widgets/catalog.dart';
import '../widgets/context.dart';
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
  bool _failed = false;

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

    // 隔离宿主：一张假卡片 + 自己的 Store 目录。预览的 storage 落在
    // `userdata/preview-cache/<组件 id>/` 下，不碰真实 pluginData；
    // http / 媒体状态是真能力（要的就是真预览）。
    //
    // 早先这里挂的是 `Directory.systemTemp`——切走组件库页再回来，预览整个
    // 重挂一次，拿到的又是全新空缓存，组件只好再拉一遍数据（反馈 Fb0008：
    // "为什么页面每次切回组件列表……卡片都会重新加载获取一次信息"）。
    // 换成固定目录后，组件自己写的 cache（天气卡就是这么缓存的）能命中。
    final store =
        Store(p.join(AppPaths.root, 'preview-cache', widget.spec.id));
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
    // 预览是静态缩略图：动画全关（原生通道读 ctx.animate，JSON 通道
    // 由下面 NodeView 的 animate:false 承接）。
    ctx.animate = false;
    try {
      controller.mount();
    } catch (_) {
      // mount 炸了以前是"静默 return"：_ready 永远是 false，界面就永久停在
      // 沙漏上——反馈里那句"预览预览了个寂寞"多半就是这个。改成记一笔失败，
      // 顺手把半挂上去的控制器收干净，别留孤儿定时器。
      try {
        controller.unmount();
      } catch (_) {}
      if (mounted) setState(() => _failed = true);
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
    if (_failed) {
      // 明确的失败占位：比一个永远转不完的沙漏诚实
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_rounded,
                  size: 20, color: Colors.white24),
              SizedBox(height: 6),
              Text('预览不可用',
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
      );
    }
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
            // 原生渲染通道：组件直接产出 Flutter Widget（协议已退役）。
            child: ValueListenableBuilder<Widget?>(
              valueListenable: ctx.widget,
              builder: (context, native, _) => native ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
