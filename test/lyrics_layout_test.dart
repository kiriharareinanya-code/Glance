/// 歌词卡片的滚动布局与换句动画约定（原生 Widget 渲染版）。
///
/// 歌词组件已迁移到 `ctx.renderWidget` 通道——直接产出 Flutter Widget，
/// 不再经过 JSON 树 / NodeView。测试也随之改为**真实渲染断言**：
/// `debugBuildFull(idx)` 直接返回 Widget，测试自己 pump，既没有
/// "宿主忘了监听 tree"的快照坑，也没有"树正确但屏幕空白"的错位。
///
/// 回归点：
///   1. **等高行**：滚动模型要求所有行一样高，否则滑动时行距会抖。
///   2. **滚动偏移**：换句时整列歌词平移 `-(窗口起点 × 行高)`，由
///      SpringSlide 做弹簧过渡——不是每行原地换词（那样没有位移）。
///      偏移必须**随换句变化**，恒定的偏移 = 动画不启动（"弹簧不见了"）。
///   3. **任意位置当前行可见**：偏移曾与数组起点重复计算，歌曲后段整列
///      飞出取景框 = "歌词逐渐消失"。现在数组从 0 起铺，不变量
///      `cur×行高 + v ≡ anchor×行高` 保证任何位置都在框内。
///   4. **译文空白**：只有这首歌**确实有译文**时才用双语行高。
///   5. **横向铺满**：行宽必须撑满取景框，不能被松约束挤成细缝。
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
import 'package:vectra/widgets/spring_transition.dart';
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

  /// 把 [w] 的完整播放视图（idx 为当前句）泵进卡片尺寸的框里。
  ///
  /// 连续调用同一个 tester 时元素树原位更新（SpringSlide 的
  /// didUpdateWidget 正常触发），和真实 app 的重绘路径一致。
  Future<void> pumpCard(
      WidgetTester tester, LyricsWidget w, int idx, Size size) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: w.debugBuildFull(idx),
          ),
        ),
      ),
    ));
  }

  /// 取景框里所有行盒（SizedBox 高度 == 行高）。行盒是等高约束的载体。
  List<Size> rowBoxSizes(WidgetTester tester, double lh) {
    return find
        .byWidgetPredicate((w) => w is SizedBox && w.height == lh)
        .evaluate()
        .map((e) => (e.renderObject! as RenderBox).size)
        .toList();
  }

  testWidgets('所有歌词行等高——滚动时行距才不会抖', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    w.debugSetLyrics(lines(8, trans: '译文'));
    await pumpCard(tester, w, 0, const Size(300, 340));
    await tester.pump(const Duration(milliseconds: 600));

    expect(w.debugSongHasTrans, isTrue);
    final lh = w.debugLineBilingual.toDouble();
    final sizes = rowBoxSizes(tester, lh);
    expect(sizes.length, greaterThanOrEqualTo(w.debugVisibleLines),
        reason: '行盒数量应至少覆盖可见行数（实际 ${sizes.length}）');
    for (final s in sizes) {
      expect(s.height, closeTo(lh, 0.01),
          reason: '所有行必须等高（双语行高 $lh），否则滑动时行距抖动');
    }
    ctx.unmount();
  });

  testWidgets('弹簧滚动：偏移是绝对滚动量，随换句单调增长（偏移不变=动画不启动）',
      (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': false});
    w.debugSetLyrics(lines(30));
    await pumpCard(tester, w, 0, const Size(300, 340));

    double offset() =>
        (tester.widget(find.byType(SpringSlide)) as SpringSlide).offset;

    expect(offset(), 0, reason: '第 0 行时窗口顶端就是 0，偏移应为 0');

    // 往后换句：偏移必须跟着变（变大），否则 SpringSlide 直接 return，
    // 弹簧永远不启动——这正是"改成常量偏移后弹簧不见了"的原因。
    await pumpCard(tester, w, 5, const Size(300, 340));
    final v5 = offset();
    expect(v5, lessThan(0), reason: '到第 5 行窗口应该已经滚动（偏移为负）');

    await pumpCard(tester, w, 10, const Size(300, 340));
    final v10 = offset();
    expect(v10, lessThan(v5),
        reason: '继续往后偏移必须继续增大，才有"滚上去"的位移可动');

    // 偏移 = -(窗口起点 × 行高)，窗口起点就是 debugWindowBase
    expect(v10, -(w.debugWindowBase * w.debugLineContext).toDouble());
    ctx.unmount();
  });

  // ↓ 用户真实反馈的回归：歌词在歌曲后半段"逐渐消失"。
  //   历史坑：偏移曾等于 -(base × 行高)，而行数组**也**从 base 重取，
  //   偏移被算了两遍；base 越大整列被推得越远，到后段整列飞出取景框。
  //   现在数组从 0 起铺、下标即行号，偏移是绝对滚动量，不会重复计算。
  testWidgets('歌曲任意位置（含最后一行）当前行都必须留在取景框内', (tester) async {
    const card = Size(608, 236);
    final (w, ctx) = mountLyrics(size: card, settings: const {'trans': false});
    final total = 40;
    w.debugSetLyrics([
      for (var i = 0; i < total; i++) LrcLine(t: i * 1000, s: 'L$i'),
    ]);

    const cardKey = ValueKey('card');
    for (final idx in [0, 1, 5, 12, 20, 30, 36, 38, total - 1]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              key: cardKey,
              width: card.width,
              height: card.height,
              child: w.debugBuildFull(idx),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final cardTop = tester.getTopLeft(find.byKey(cardKey)).dy;
      final cardBot = cardTop + card.height;
      final curY = tester.getTopLeft(find.text('L$idx')).dy;
      expect(curY, greaterThanOrEqualTo(cardTop - 1),
          reason: 'idx=$idx 当前行跑到卡片上方了（y=$curY，卡 $cardTop..$cardBot）');
      expect(curY, lessThan(cardBot),
          reason: 'idx=$idx 当前行跑到卡片下方了（y=$curY，卡 $cardTop..$cardBot）');

      // 偏移不变量：严格等于 -(窗口起点 × 行高)
      final v =
          (tester.widget(find.byType(SpringSlide)) as SpringSlide).offset;
      expect(v, -(w.debugWindowBase * w.debugLineContext).toDouble(),
          reason: 'idx=$idx 的偏移 $v 与窗口起点 ${w.debugWindowBase} 对不上');
    }
    ctx.unmount();
  });

  // ↓ 用户真实反馈的回归：5x2 小卡片（608x236）上歌词只剩两三行 = 不能用。
  //   真因是头部固定预留 88px（占卡片 37%）+ 又给预铺行扣了 2 行的预算。
  testWidgets('小卡片（5x2）也要显示足够多的歌词行，不能退化成字幕条', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(608, 236), settings: const {'trans': false});
    w.debugSetLyrics(lines(14));
    await pumpCard(tester, w, 4, const Size(608, 236));
    await tester.pump(const Duration(milliseconds: 600));

    // 至少 4 行：小卡片上也要能看清上下文（上一句/当前句/下一句/更下一句）
    expect(w.debugVisibleLines, greaterThanOrEqualTo(4),
        reason: '5x2 卡片可见行数必须 ≥4（之前只有 2，用户直接说"不能用"）');
    ctx.unmount();
  });

  testWidgets('小卡片开了翻译也要能显示至少 3 行', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(608, 236), settings: const {'trans': true});
    w.debugSetLyrics(lines(14, trans: '译文'));
    await pumpCard(tester, w, 4, const Size(608, 236));
    await tester.pump(const Duration(milliseconds: 600));

    expect(w.debugVisibleLines, greaterThanOrEqualTo(3),
        reason: '双语行高更大，但也不能只剩 1 行（之前就是 1）');
    ctx.unmount();
  });

  testWidgets('开了翻译但整首歌都没有译文时，不留任何双语空白', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    w.debugSetLyrics(lines(10)); // 全部无译文
    await pumpCard(tester, w, 0, const Size(300, 340));
    await tester.pump(const Duration(milliseconds: 600));

    expect(w.debugHasTrans, isFalse, reason: '这行没有译文');
    expect(w.debugSongHasTrans, isFalse, reason: '整首歌都没有译文');
    final sizes = rowBoxSizes(tester, w.debugLineSingle.toDouble());
    expect(sizes, isNotEmpty);
    for (final s in sizes) {
      expect(s.height, closeTo(w.debugLineSingle.toDouble(), 0.01),
          reason: '整首歌没译文时行高应取单行值，不留双语空白');
    }
    ctx.unmount();
  });

  testWidgets('整首歌有译文时，行高统一取双语值', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    w.debugSetLyrics(lines(10, trans: '译文'));
    await pumpCard(tester, w, 0, const Size(300, 340));
    await tester.pump(const Duration(milliseconds: 600));

    expect(w.debugSongHasTrans, isTrue);
    final sizes = rowBoxSizes(tester, w.debugLineBilingual.toDouble());
    expect(sizes, isNotEmpty);
    for (final s in sizes) {
      expect(s.height, closeTo(w.debugLineBilingual.toDouble(), 0.01),
          reason: '所有行必须等高，译文不能只撑高当前行');
    }
    ctx.unmount();
  });

  testWidgets('真实渲染：歌词占满可用宽度，不被松约束挤成细缝', (tester) async {
    final (w, ctx) = mountLyrics(size: const Size(300, 340));
    w.debugSetLyrics([
      for (var i = 0; i < 12; i++) LrcLine(t: i * 1000, s: '第$i行歌词内容'),
    ]);
    await pumpCard(tester, w, 4, const Size(300, 340));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('第4行歌词内容'), findsOneWidget,
        reason: '当前行必须真的画在屏幕上（不能整块空白）');

    // 行盒必须铺满右侧列（松约束下会塌成最宽文字的宽度）
    final lh = w.debugLineContext.toDouble();
    final rowBoxes = find
        .ancestor(
          of: find.text('第5行歌词内容'),
          matching: find.byWidgetPredicate(
              (wgt) => wgt is SizedBox && wgt.height == lh),
        )
        .evaluate()
        .map((e) => (e.renderObject! as RenderBox).size.width)
        .toList();
    expect(rowBoxes, isNotEmpty);
    expect(rowBoxes.first, greaterThan(150),
        reason: '行盒子必须铺满右侧列（塌陷时只有文字自身宽度），实际=$rowBoxes');

    // 所有可见歌词行左边缘对齐
    final l4 = tester.getTopLeft(find.text('第4行歌词内容')).dx;
    final l5 = tester.getTopLeft(find.text('第5行歌词内容')).dx;
    expect(l5, closeTo(l4, 0.5),
        reason: '各行左边缘必须对齐（塌陷时每行宽度不同会错开）');

    expect(tester.takeException(), isNull,
        reason: '取景框高度必须容得下所有行，不能 RenderFlex 溢出');
    ctx.unmount();
  });

  testWidgets('真实渲染：整首歌有译文时不溢出（双语行高）', (tester) async {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    w.debugSetLyrics([
      for (var i = 0; i < 12; i++)
        LrcLine(t: i * 1000, s: '第$i行歌词内容', tr: '第$i行翻译文字'),
    ]);
    await pumpCard(tester, w, 4, const Size(300, 340));
    await tester.pump(const Duration(milliseconds: 600));

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
  //   验证换句时歌词真的在动，而不只是断言"字段的值变了"。
  testWidgets('真实渲染：换句时歌词整列弹簧平移（不是原地换词）', (tester) async {
    final (w, ctx) = mountLyrics(size: const Size(300, 340));
    w.debugSetLyrics([
      for (var i = 0; i < 20; i++) LrcLine(t: i * 1000, s: 'L$i'),
    ]);

    await pumpCard(tester, w, 2, const Size(300, 340));
    await tester.pumpAndSettle();
    final yBefore = tester.getTopLeft(find.text('L3')).dy;

    // 换句：把当前行推到第 6 句，窗口起点随之 +4 → 整列应向上滚 4 行
    await pumpCard(tester, w, 6, const Size(300, 340));
    // 动画**进行中**（还没 settle）：位置应当已经在移动
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
