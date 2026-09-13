/// 歌词卡片的布局与换词动画约定。
///
/// 两个回归点：
///   1. **译文空白**：以前只要开了「显示翻译」，当前行就恒占双语高度，
///      而网易云大多数歌没有 tlyric——于是几乎每一行都空出一行译文的
///      格子。现在没有译文就收回单行高度，省下的空间多显示一行歌词。
///   2. **弹簧换词**：当前行换词走 trans:'spring'，但其余行必须保持
///      原地替换（内容切换动画当年因真实渲染闪白被整体移除过，只有
///      显式声明的节点才允许过渡）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/node.dart';
import 'package:vectra/store/store.dart';

import 'dart:io';

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

  /// 造一个 lyrics 控制器并挂载，返回它 + 它最新渲染的树
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

  /// 从树里找到歌词区：现在的 debugPaint 直接渲染歌词区本身，
  /// 所以根节点就是它。
  Map<String, Object?>? findLyricArea(Map<String, Object?> tree) => tree;

  /// 收集树里所有 text 节点的 trans 字段
  List<Object?> collectTrans(Map<String, Object?> tree) {
    final out = <Object?>[];
    void walk(Object? n) {
      if (n is Map) {
        if (n['t'] == 'text') out.add(n['trans']);
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

  test('开了翻译但当前行没有译文时，不预留双语高度', () {
    final (w, ctx) = mountLyrics(
      size: const Size(300, 300),
      settings: const {'trans': true},
    );
    addTearDown(() { ctx.unmount(); });

    // 塞一份「有行、但没有任何译文」的歌词：模拟网易云只有 lrc、无 tlyric
    w.debugSetLyrics([
      LrcLine(t: 0, s: '第一行'),
      LrcLine(t: 1000, s: '第二行'),
      LrcLine(t: 2000, s: '第三行'),
      LrcLine(t: 3000, s: '第四行'),
      LrcLine(t: 4000, s: '第五行'),
      LrcLine(t: 5000, s: '第六行'),
      LrcLine(t: 6000, s: '第七行'),
    ]);
    w.debugPaint(0);

    final area = findLyricArea(ctx.tree.value!);
    expect(area, isNotNull, reason: '有歌词时应渲染歌词区');
    // 当前行高度 == 上下文行高度（都是单行），说明没给译文留白
    expect(w.debugLineCurrent, w.debugLineContext,
        reason: '无译文时当前行不应占双语高度');
  });

  test('开了翻译且当前行确实有译文时才占双语高度', () {
    final (w, ctx) = mountLyrics(
      size: const Size(300, 300),
      settings: const {'trans': true},
    );
    addTearDown(() { ctx.unmount(); });

    w.debugSetLyrics([
      LrcLine(t: 0, s: 'line one', tr: '第一行'),
      LrcLine(t: 1000, s: 'line two'),
    ]);
    w.debugPaint(0);

    expect(w.debugLineCurrent, greaterThan(w.debugLineContext),
        reason: '当前行有译文时必须占双语高度，否则译文会被裁掉');
  });

  test('无译文那行省下的高度换来更多可见歌词行', () {
    // 同一尺寸下：无译文时可见行数 >= 有译文时
    final (w1, ctx1) = mountLyrics(
      size: const Size(300, 340),
      settings: const {'trans': true},
    );
    addTearDown(() { ctx1.unmount(); });
    w1.debugSetLyrics([
      LrcLine(t: 0, s: 'a'),
      LrcLine(t: 1, s: 'b'),
      LrcLine(t: 2, s: 'c'),
      LrcLine(t: 3, s: 'd'),
      LrcLine(t: 4, s: 'e'),
      LrcLine(t: 5, s: 'f'),
      LrcLine(t: 6, s: 'g'),
      LrcLine(t: 7, s: 'h'),
      LrcLine(t: 8, s: 'i'),
      LrcLine(t: 9, s: 'j'),
    ]);
    w1.debugPaint(0);
    final noTrans = w1.debugVisibleLines;

    final (w2, ctx2) = mountLyrics(
      size: const Size(300, 340),
      settings: const {'trans': true},
    );
    addTearDown(() { ctx2.unmount(); });
    w2.debugSetLyrics([
      LrcLine(t: 0, s: 'a', tr: '甲'),
      LrcLine(t: 1, s: 'b', tr: '乙'),
      LrcLine(t: 2, s: 'c', tr: '丙'),
      LrcLine(t: 3, s: 'd', tr: '丁'),
      LrcLine(t: 4, s: 'e', tr: '戊'),
      LrcLine(t: 5, s: 'f', tr: '己'),
      LrcLine(t: 6, s: 'g', tr: '庚'),
      LrcLine(t: 7, s: 'h', tr: '辛'),
      LrcLine(t: 8, s: 'i', tr: '壬'),
      LrcLine(t: 9, s: 'j', tr: '癸'),
    ]);
    w2.debugPaint(0);
    final withTrans = w2.debugVisibleLines;

    expect(noTrans, greaterThanOrEqualTo(withTrans),
        reason: '无译文时当前行更矮，应能多显示（或至少不减少）歌词行');
  });

  test('只有当前行声明 trans:spring，上下文行不动画', () {
    final (w, ctx) = mountLyrics(
      size: const Size(300, 340),
      settings: const {'trans': false},
    );
    addTearDown(() { ctx.unmount(); });

    w.debugSetLyrics([
      LrcLine(t: 0, s: 'a'),
      LrcLine(t: 1, s: 'b'),
      LrcLine(t: 2, s: 'c'),
      LrcLine(t: 3, s: 'd'),
      LrcLine(t: 4, s: 'e'),
      LrcLine(t: 5, s: 'f'),
      LrcLine(t: 6, s: 'g'),
    ]);
    w.debugPaint(2); // 让第 3 行成为当前行

    final trans = collectTrans(ctx.tree.value!);
    final springs = trans.where((e) => e == 'spring').length;
    expect(springs, 1, reason: '只能有当前行这一个 spring，其余行原地替换');
  });

  testWidgets('节点层：trans:spring 的文字换值走弹簧过渡而不是硬切', (tester) async {
    var v = '1';
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SizedBox(
            width: 200,
            height: 60,
            child: NodeView(
              tree: {'t': 'text', 'v': v, 'trans': 'spring'},
              onEvent: (_, _) {}),
          );
        }),
      ),
    ));

    // 内容变了：进入过渡态，旧值应还在（不是硬切）
    set(() => v = '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    set(() => v = '2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // 过渡中：新旧内容至少有一个可见，绝不能出现两帧都空
    expect(find.text('2'), findsOneWidget);
    // 走完动画后只剩新值
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('节点层：没声明 trans 的文字仍是原地替换', (tester) async {
    var v = 'a';
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return SizedBox(
            width: 200,
            height: 60,
            child: NodeView(
              tree: {'t': 'text', 'v': v},
              onEvent: (_, _) {}),
          );
        }),
      ),
    ));

    set(() => v = 'b');
    await tester.pump();
    expect(find.text('a'), findsNothing, reason: '未声明 trans 必须原地替换');
    expect(find.text('b'), findsOneWidget);
  });
}
