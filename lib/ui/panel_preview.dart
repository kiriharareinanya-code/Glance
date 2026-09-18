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
/// 图片由 `tools/gen_previews.py` 离线生成，产物在 `assets/previews/<id>.png`。
/// 组件的真实外观仍然可以在桌面上放置后查看，这里只负责"让人认出来是什么"。
library;

import 'package:flutter/material.dart';

import '../core/grid.dart';
import '../widgets/spec.dart';

/// 概览图的绘制基准（2 倍图，见 gen_previews.py 的 SCALE）。
/// 用固定尺寸 + FittedBox 等比缩放，任何卡片宽度下都不会糊或裁。
const double _artScale = 2;

class BuiltinPreview extends StatelessWidget {
  const BuiltinPreview({super.key, required this.spec});

  final BuiltinSpec spec;

  /// 概览图的资源路径。缺图时返回空串，调用方退回占位。
  static String assetPath(String id) => 'assets/previews/$id.png';

  @override
  Widget build(BuildContext context) {
    final grid = parseSize(spec.defaultSize) ?? const GridSize(2, 2);
    final px = sizeToPx(grid);
    final path = assetPath(spec.id);

    return SizedBox(
      width: px.w,
      height: px.h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        // errorBuilder：万一某个新组件还没来得及生成图（或者图被删了），
        // 显示一个明确的占位，而不是让 Image 抛异常刷满控制台。
        child: Image.asset(
          path,
          width: px.w,
          height: px.h,
          filterQuality: FilterQuality.medium,
          // 概览图是**静态数据**，不随主题变化——图片里的卡片底色就是
          // 组件在桌面上的样子（深色玻璃）。这里不做任何染色。
          errorBuilder: (context, error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_outlined,
                    size: 20, color: Colors.white24),
                const SizedBox(height: 6),
                Text('暂无概览图',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.38))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 概览图的原始像素尺寸（供外层按需布局；不依赖 BuildContext）。
Size previewAspect(String id, String defaultSize) {
  final grid = parseSize(defaultSize) ?? const GridSize(2, 2);
  final px = sizeToPx(grid);
  return Size(px.w * _artScale, px.h * _artScale);
}
