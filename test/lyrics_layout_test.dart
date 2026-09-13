/// 歌词卡片的滚动布局与换句动画约定。
///
/// 回归点：
///   1. **等高行**：滚动模型要求所有行一样高，否则滑动时行距会抖。
///   2. **滚动偏移**：换句时整列歌词平移 `-(窗口起点 × 行高)`，由 'slide'
///      节点做弹簧过渡——不是每行原地换词（那样没有位移，看起来是"跳"）。
///   3. **译文空白**：以前只要开「显示翻译」当前行就恒占双语高度，而
///      网易云多数歌没有 tlyric，导致整片留白。现在只有这首歌**确实有
///      译文**时才用双语行高，否则一点都不留。
///   4. **横向铺满**：`clip:true` 的盒子会在孩子外面套 ClipPath，传下去
///      的是**松宽度约束**——内层 Column 会缩到最宽文字的宽度，整块歌词
///      塌成左边一条细缝，看起来"一片空白"（真实 bug）。裁切盒必须自己
///      把宽度撑满。
///   5. **不溢出**：取景框高度必须 ≥ 内层行堆的总高，否则 RenderFlex
///      报溢出（实测 38~60px）并且滚动时边缘露白。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/node.dart';
import 'package:vectra/store/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Store store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vectra-lyrics');
    store = Store(tmp.path);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  (LyricsWidget, WidgetContext) mountLyrics({
    required Size size,
    Map<String, Object?> settings = const {},
  }) {
    final ctx = WidgetContext(
      store: store,
      card: WidgetCard(
          id: 'c1', pluginId: 'lyrics', x: 0, y: 0, size: '5x3', z: 1),
      pluginId: 'lyrics',
      onRequestSize: (_) {},
      onOpenSettings: () {},
      settings: settings,
      grid: const GridSize(5, 3),
      size: size,
    );
    final w = LyricsWidget(ctx);
    w.mount();
    return (w, ctx);
  }

  List<LrcLine> lines(int n, {String? trans}) => [
        for (var i = 0; i < n; i++)
          LrcLine(t: i * 1000, s: '第$i行', tr: trans ?? ''),
      ];

  /// 找树里第一个 slide 节点
  Map<String, Object?>? findSlide(Map<String, Object?> tree) {
    Map<String, Object?>? hit;
    void walk(Object? n) {
      if (hit != null) return;
      if (n is Map) {
        if (n['t'] == 'slide') {
          hit = n.cast<String, Object?>();
          return;
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(tree);
    return hit;
  }

  /// 收集歌词行盒子的高度
  List<int> rowHeights(Map<String, Object?> tree) {
    final out = <int>[];
    void walk(Object? n) {
      if (n is Map) {
        if (n['t'] == 'tap' && n['child'] is Map) {
          final box = n['child'] as Map;
          if (box['h'] is num) out.add((box['h'] as num).toInt());
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(tree);
    return out;
  }

  test('所有歌词行等高——滚动时行距才不会抖', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    addTearDown(() {
      ctx.unmount();
    });

    w.debugSetLyrics([
      LrcLine(t: 0, s: 'line one', tr: '第一行'),
      LrcLine(t: 1000, s: 'line two'),
      LrcLine(t: 2000, s: 'line three'),
      LrcLine(t: 3000, s: 'line four'),
      LrcLine(t: 4000, s: 'line five'),
      LrcLine(t: 5000, s: 'line six'),
      LrcLine(t: 6000, s: 'line seven'),
      LrcLine(t: 7000, s: 'line eight'),
    ]);
    w.debugPaint(0);

    final hs = rowHeights(ctx.tree.value!);
    expect(hs, isNotEmpty);
    expect(hs.toSet().length, 1,
        reason: '所有行必须等高，否则滑动时行距抖动（实际：$hs）');
    expect(hs.first, w.debugLineContext, reason: '行高应取单行值，译文不撑高行');
  });

  test('弹簧滚动：偏移是绝对滚动量，随换句单调增长（偏移不变=动画不启动）', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': false});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(30));

    w.debugPaint(0);
    var slide = findSlide(ctx.tree.value!);
    expect(slide, isNotNull, reason: '歌词区必须包在 slide 节点里');
    expect(slide!['v'], 0, reason: '第 0 行时窗口顶端就是 0，偏移应为 0');

    // 往后换句：偏移必须跟着变（变大），否则 SpringSlide 直接 return，
    // 弹簧永远不启动——这正是"改成常量偏移后弹簧不见了"的原因。
    w.debugPaint(5);
    final v5 = (findSlide(ctx.tree.value!)!['v'] as num).toDouble();
    expect(v5, lessThan(0), reason: '到第 5 行窗口应该已经滚动（偏移为负）');

    w.debugPaint(10);
    final v10 = (findSlide(ctx.tree.value!)!['v'] as num).toDouble();
    expect(v10, lessThan(v5),
        reason: '继续往后偏移必须继续增大，才有"滚上去"的位移可动');

    // 偏移 = -(窗口起点 × 行高)，窗口起点就是 debugWindowBase
    expect(v10, -(w.debugWindowBase * w.debugLineContext).toDouble());
  });

  // ↓ 用户真实反馈的回归：歌词在歌曲后半段"逐渐消失"。
  //   历史坑：偏移曾等于 -(base × 行高)，而行数组**也**从 base 重取，
  //   偏移被算了两遍；base 越大整列被推得越远，到后段整列飞出取景框。
  //   现在数组从 0 起铺、下标即行号，偏移是绝对滚动量，不会重复计算。
  test('歌曲任意位置（含最后一行）当前行都必须留在取景框内', () {
    const card = Size(608, 236);
    final (w, ctx) =
        mountLyrics(size: card, settings: const {'trans': false});
    final total = 40;
    w.debugSetLyrics([
      for (var i = 0; i < total; i++) LrcLine(t: i * 1000, s: 'L$i'),
    ]);

    for (final idx in [0, 1, 5, 12, 20, 30, 36, 38, total - 1]) {
      w.debugPaintFull(idx);
      final tree = ctx.tree.value!;
      final slide = findSlide(tree);
      expect(slide, isNotNull, reason: 'idx=$idx 时应能找到 slide 节点');
      final v = (slide!['v'] as num).toDouble();
      final base = w.debugWindowBase;
      // 偏移必须严格等于 -(窗口起点 × 行高)：数组从 0 起，所以"行号 × 行高"
      // 就是它在未平移坐标系里的位置，没有第二处平移。
      expect(v, -(base * w.debugLineContext).toDouble(),
          reason: 'idx=$idx 的偏移 $v 与窗口起点 $base 对不上');
      // 当前行屏上坐标 = 行号 × 行高 + v，必须落在取景框（可容忍 1px 误差）。
      final lh = w.debugLineContext;
      final onScreen = idx * lh + v;
      expect(onScreen, greaterThanOrEqualTo(-1.0),
          reason: 'idx=$idx 时当前行跑到取景框上方了（y=$onScreen）');
      expect(onScreen, lessThan(w.debugAvailHeight + 1),
          reason: 'idx=$idx 时当前行跑到取景框下方了（y=$onScreen）');
    }
    ctx.unmount();
  });

  test('槽位数按单行（行数最多的极端）备齐，运行时还会现补', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': false});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(12));
    w.debugPaint(3);

    expect(w.debugSlotCount, w.debugMaxSlotCount);
    expect(w.debugSlotCount, greaterThanOrEqualTo(w.debugVisibleLines),
        reason: '注册数必须覆盖可见行数（不够的话 _handlerFor 会现补，'
            '但初始就该备够）');
  });

  // ↓ 用户真实反馈的回归：5x2 小卡片（608x236）上歌词只剩两三行 = 不能用。
  //   真因是头部固定预留 88px（占卡片 37%）+ 又给预铺行扣了 2 行的预算。
  test('小卡片（5x2）也要显示足够多的歌词行，不能退化成字幕条', () {
    final (w, ctx) = mountLyrics(
        size: const Size(608, 236), settings: const {'trans': false});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(14));
    w.debugPaint(4);

    // 至少 4 行：小卡片上也要能看清上下文（上一句/当前句/下一句/更下一句）
    expect(w.debugVisibleLines, greaterThanOrEqualTo(4),
        reason: '5x2 卡片可见行数必须 ≥4（之前只有 2，用户直接说"不能用"）');
  });

  test('小卡片开了翻译也要能显示至少 3 行', () {
    final (w, ctx) = mountLyrics(
        size: const Size(608, 236), settings: const {'trans': true});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(14, trans: '译文'));
    w.debugPaint(4);

    expect(w.debugVisibleLines, greaterThanOrEqualTo(3),
        reason: '双语行高更大，但也不能只剩 1 行（之前就是 1）');
  });

  test('开了翻译但整首歌都没有译文时，不留任何双语空白', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(10)); // 全部无译文
    w.debugPaint(0);

    expect(w.debugHasTrans, isFalse, reason: '这行没有译文');
    expect(w.debugSongHasTrans, isFalse, reason: '整首歌都没有译文');
    final hs = rowHeights(ctx.tree.value!);
    expect(hs.toSet().length, 1);
    expect(hs.first, w.debugLineSingle,
        reason: '整首歌没译文时行高应取单行值，不留双语空白');
  });

  test('整首歌有译文时，行高统一取双语值', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(10, trans: '译文'));
    w.debugPaint(0);

    expect(w.debugSongHasTrans, isTrue);
    final hs = rowHeights(ctx.tree.value!);
    expect(hs.toSet().length, 1, reason: '所有行必须等高，译文不能只撑高当前行');
    expect(hs.first, w.debugLineBilingual);
  });

  testWidgets('真实渲染：歌词占满可用宽度，不被 ClipPath 挤成细缝', (tester) async {
    final (w, ctx) = mountLyrics(size: const Size(300, 340));
    w.debugSetLyrics([
      for (var i = 0; i < 12; i++) LrcLine(t: i * 1000, s: '第$i行歌词内容'),
    ]);
    w.debugPaintFull(4);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 340,
            // 必须监听 tree：塞快照的话后续 render 都不生效（早期踩过）。
            child: ValueListenableBuilder<Map<String, Object?>?>(
              valueListenable: ctx.tree,
              builder: (_, tree, _) => tree == null
                  ? const SizedBox.shrink()
                  : NodeView(tree: tree, onEvent: (_, _) {}),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('第4行歌词内容'), findsOneWidget,
        reason: '当前行必须真的画在屏幕上（不能整块空白）');

    // 横向铺满的判据：找行盒子（tap 的直接子 box），它应当铺满右侧列。
    // 文字本身宽度不等于行宽（Text 只占自己那几个字），所以量行盒子。
    final rowBoxes = find
        .ancestor(
            of: find.text('第5行歌词内容'),
            matching: find.byType(AnimatedContainer))
        .evaluate()
        .map((e) => (e.renderObject as RenderBox).size.width)
        .toList();
    // 祖先链里最宽的那个就是铺满列宽的行盒子
    final rowW = rowBoxes.reduce((a, b) => a > b ? a : b);
    expect(rowW, greaterThan(150),
        reason: '行盒子必须铺满右侧列（松约束下会塌成 ~48px，看起来是空白），'
            '实际祖先链宽度=$rowBoxes');

    // 所有可见歌词行应当左对齐在同一条竖线上（说明它们同宽、没有被
    // 各自文字宽度带偏）
    final l4 = tester.getTopLeft(find.text('第4行歌词内容')).dx;
    final l5 = tester.getTopLeft(find.text('第5行歌词内容')).dx;
    expect(l5, closeTo(l4, 0.5),
        reason: '各行左边缘必须对齐（塌陷时每行宽度不同会错开）');

    expect(tester.takeException(), isNull,
        reason: '取景框高度必须容得下所有行，不能 RenderFlex 溢出');

    // 必须先 unmount 再结束：mount 里开的 100ms interval 还在跑，
    // 留到 testWidgets 的末尾校验会报 "A Timer is still pending"。
    ctx.unmount();
  });

  testWidgets('真实渲染：整首歌有译文时不溢出（双语行高）', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    w.debugSetLyrics([
      for (var i = 0; i < 12; i++)
        LrcLine(t: i * 1000, s: '第$i行歌词内容', tr: '第$i行翻译文字'),
    ]);
    w.debugPaintFull(4);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 340,
            child: ValueListenableBuilder<Map<String, Object?>?>(
              valueListenable: ctx.tree,
              builder: (_, tree, _) => tree == null
                  ? const SizedBox.shrink()
                  : NodeView(tree: tree, onEvent: (_, _) {}),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('第4行歌词内容'), findsOneWidget);
    expect(find.text('第4行翻译文字'), findsOneWidget,
        reason: '当前行的译文必须显示出来');
    expect(tester.takeException(), isNull,
        reason: '正文 + 译文必须放得进双语行高，不能溢出');

    ctx.unmount();
  });

  // ↓ 用户反馈"弹簧效果又不见了"的回归。
  //   弹簧的触发条件是 SpringSlide.didUpdateWidget 里 offset 变了；
  //   偏移若恒为常量（-行高），动画根本不启动。这条在**真实渲染**里
  //   验证换句时歌词真的在动，而不只是断言"节点字段的值变了"。
  testWidgets('真实渲染：换句时歌词整列弹簧平移（不是原地换词）', (tester) async {
    final (w, ctx) = mountLyrics(size: const Size(300, 340));
    w.debugSetLyrics([
      for (var i = 0; i < 20; i++) LrcLine(t: i * 1000, s: 'L$i'),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 340,
            child: ValueListenableBuilder<Map<String, Object?>?>(
              valueListenable: ctx.tree,
              builder: (_, tree, _) => tree == null
                  ? const SizedBox.shrink()
                  : NodeView(tree: tree, onEvent: (_, _) {}),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 先让整列稳定在某个位置
    w.debugPaintFull(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final yBefore = tester.getTopLeft(find.text('L3')).dy;

    // 换句：把当前行推到第 6 句，窗口起点随之 +4 → 整列应向上滚 4 行
    w.debugPaintFull(6);
    await tester.pump();
    // 动画**进行中**（还没 settle）：位置应当介于起点和终点之间
    await tester.pump(const Duration(milliseconds: 120));
    final yMid = tester.getTopLeft(find.text('L3')).dy;
    expect(yMid, lessThan(yBefore),
        reason: '换句后必须真的在往上移动（原地换词的话位置不变）');

    await tester.pumpAndSettle();
    final yAfter = tester.getTopLeft(find.text('L3')).dy;
    final lh = w.debugLineContext;
    // 换句后窗口起点前移 4 行，L3 应恰好上移 4 行高
    expect(yAfter, closeTo(yBefore - 4 * lh, 1.0),
        reason: '弹簧终点应当正好滚过 4 行（实际 yBefore=$yBefore '
            'yAfter=$yAfter 行高=$lh）');

    ctx.unmount();
  });

  testWidgets('节点层：slide 节点按目标偏移做弹簧平移', (tester) async {
    var off = 0.0;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SizedBox(
            width: 200,
            height: 200,
            child: NodeView(
                tree: {
                  't': 'slide',
                  'v': off,
                  'child': {'t': 'text', 'v': '歌词'}
                },
                onEvent: (_, _) {}),
          );
        }),
      ),
    ));

    set(() => off = -100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getTopLeft(find.text('歌词')).dy;
    expect(mid, lessThan(0), reason: '动画中途应该已经开始往上走');
    expect(mid, greaterThan(-100.5), reason: '中途还没到位');

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('歌词')).dy, closeTo(-100, 0.5),
        reason: '动画结束必须精确到位');
  });

  testWidgets('节点层：连续换句从当前位置接着走，不跳回起点', (tester) async {
    var off = 0.0;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SizedBox(
            width: 200,
            height: 200,
            child: NodeView(
                tree: {
                  't': 'slide',
                  'v': off,
                  'child': {'t': 'text', 'v': '歌词'}
                },
                onEvent: (_, _) {}),
          );
        }),
      ),
    ));

    Offset pos() => tester.getTopLeft(find.text('歌词'));

    set(() => off = -100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final beforeSwitch = pos().dy;
    expect(beforeSwitch, lessThan(0), reason: '第一次滚动已开始');

    set(() => off = -200);
    await tester.pump();
    final justAfter = pos().dy;
    expect(justAfter, closeTo(beforeSwitch, 1.0),
        reason: '连续换句的瞬间位置必须连续，不能跳回起点');

    await tester.pumpAndSettle();
    expect(pos().dy, closeTo(-200, 0.5));
  });

  testWidgets('节点层：关闭动画时 slide 直接到位', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          height: 200,
          child: NodeView(
              tree: {
                't': 'slide',
                'v': -50.0,
                'child': {'t': 'text', 'v': '歌词'}
              },
              animate: false,
              onEvent: (_, _) {}),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.getTopLeft(find.text('歌词')).dy, closeTo(-50, 0.5));
  });
}
