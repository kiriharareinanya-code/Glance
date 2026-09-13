/// 歌词卡片的滚动布局与换句动画约定。
///
/// 三个回归点：
///   1. **等高行**：滚动模型要求所有行一样高，否则滑动时行距会抖。
///      译文不再撑高行，而是压成小字叠在正文下面。
///   2. **滚动偏移**：换句时整列歌词平移 `-(窗口起点 × 行高)`，由 'slide'
///      节点做弹簧过渡——不是每行原地换词（那样没有位移，看起来是"跳"）。
///   3. **译文空白**：以前只要开「显示翻译」当前行就恒占双语高度，而
///      网易云多数歌没有 tlyric，导致整片留白。现在行高统一，不再有
///      这个空白。
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

  test('换句时整列平移 -(窗口起点 × 行高)', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': false});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(12));

    w.debugPaint(0);
    var slide = findSlide(ctx.tree.value!);
    expect(slide, isNotNull, reason: '歌词区必须包在 slide 节点里');
    expect(slide!['v'], 0, reason: '第一行偏移应为 0');

    w.debugPaint(5);
    slide = findSlide(ctx.tree.value!);
    final base = w.debugWindowBase;
    expect(base, greaterThan(0), reason: '到第 5 行窗口应该已经前移');
    expect(slide!['v'], -(base * w.debugLineContext).toDouble(),
        reason: '偏移必须等于 -(窗口起点 × 行高)，滑动才对得上位置');
  });

  test('槽位数 = 可见行数 + 2（滚动时上下各多铺一行）', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': false});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(12));
    w.debugPaint(3);

    expect(w.debugSlotCount, w.debugVisibleLines + 2);
  });

  test('开了翻译但当前行没有译文时，不预留任何空白', () {
    final (w, ctx) = mountLyrics(
        size: const Size(300, 340), settings: const {'trans': true});
    addTearDown(() {
      ctx.unmount();
    });
    w.debugSetLyrics(lines(10)); // 全部无译文
    w.debugPaint(0);

    expect(w.debugHasTrans, isFalse, reason: '这行没有译文');
    final hs = rowHeights(ctx.tree.value!);
    expect(hs.toSet().length, 1);
    expect(hs.first, w.debugLineContext, reason: '无译文就没有双语预留');
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
