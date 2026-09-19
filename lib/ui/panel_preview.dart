/// 组件库里的概览预览。
///
/// **这是一张静态图，不是实时预览。**
///
/// 以前这里挂的是真实控制器（时钟在走、天气在拉 API、歌词在读 SMTC），
/// 好处是"所见即所得"，代价是三个真实问题：
///   1. 组件库一打开就有 N 个组件同时发网络请求、同时起定时器，
///      页面滚一圈还容易留下孤儿 Timer；
///   2. 天气这类依赖网络的数据在离线/被墙时预览直接变成"天气不可用"，
///      用户看到的不是组件长什么样，而是"这个组件坏了"；
///   3. 每次切回组件库都会重新挂载、重新请求一遍。
///
/// 按反馈要求改成写死的静态概览图：零请求、零定时器、随版本一起更新。
/// 图片由 `test/gen_previews_test.dart` 用真实组件离线渲染生成（真实字体、
/// 真实布局，所见即组件在桌面上的样子），产物在 `assets/previews/<id>.png`。
///
/// **统一画布**：全部组件都按同一块 4x4（484×484）画布渲染（与生成器的
/// `_previewGrid` 保持一致）。统一前每张图按各自 defaultSize 出图，摆在一起
/// 大小不一、字体缩放基准也不齐；统一后任何组件的字距/字号在图里的相对
/// 比例完全一致，展示端也能按同一个宽高比排布。
library;

import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../widgets/spec.dart';

/// 概览图的绘制基准（2 倍图，见 gen_previews_test.dart 的 pixelRatio）。
/// 用固定尺寸 + FittedBox 等比缩放，任何卡片宽度下都不会糊或裁。
const double _artScale = 2;

/// 概览图的统一画布规格 —— 必须和生成器（test/gen_previews_test.dart
/// 的 `_previewGrid`）保持一致，否则图会被拉伸或留缝。
const GridSize kPreviewGrid = GridSize(4, 4);

class BuiltinPreview extends StatelessWidget {
  const BuiltinPreview({super.key, required this.spec, this.light = false});

  final BuiltinSpec spec;

  /// 面板当前是不是浅色。概览图按这个挑深色版还是浅色版。
  final bool light;

  /// 概览图的资源路径。概览图有两套——深色 `<id>.png`、浅色 `<id>-light.png`，
  /// 由生成器一次生成。缺图时返回空串，调用方退回占位。
  static String assetPath(String id, {bool light = false}) =>
      light ? 'assets/previews/$id-light.png' : 'assets/previews/$id.png';

  @override
  Widget build(BuildContext context) {
    final px = sizeToPx(kPreviewGrid);
    final path = assetPath(spec.id, light: light);
    // 占位（缺图兜底）也跟着明暗走，浅色面板上白 24% 的图标会直接看不见
    final ghost = light ? Colors.black26 : Colors.white24;
    final ghostText = light
        ? Colors.black.withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: 0.38);
    // 概览图自带整块底色，跟卡片底色只差一档，不描一圈几乎分不出边界
    final hairline = light
        ? Colors.black.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.10);

    return SizedBox(
      width: px.w,
      height: px.h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        // errorBuilder：万一某个新组件还没来得及生成图（或者图被删了），
        // 显示一个明确的占位，而不是让 Image 抛异常刷满控制台。
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              path,
              width: px.w,
              height: px.h,
              filterQuality: FilterQuality.medium,
              // 概览图是静态资产：深浅两套随面板明暗挑（见 assetPath），
              // 内容写死、运行时零请求零定时器。
              errorBuilder: (context, error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 20, color: ghost),
                    const SizedBox(height: 6),
                    Text('暂无概览图',
                        style: TextStyle(fontSize: 11, color: ghostText)),
                  ],
                ),
              ),
            ),
            // 1px 发丝描边压在图上（在 ClipRRect 内侧画，圆角处正好贴合）。
            // 只是给截图一个清晰的轮廓，不用颜色说话。
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hairline),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 概览图的原始像素尺寸（供外层按需布局；不依赖 BuildContext）。
///
/// 统一画布后所有组件同宽同高，调用方不再需要按组件区分比例。
Size previewAspect() {
  final px = sizeToPx(kPreviewGrid);
  return Size(px.w * _artScale, px.h * _artScale);
}
