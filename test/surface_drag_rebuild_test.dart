/// 拖拽卡片时的重建范围。
///
/// 这组测试盯的是一次性能改造的**回归护栏**，不是功能：以前拖一张卡会
/// setState 整个 surface，于是每来一个 pointer move 都要重建全部 N 张卡的
/// 插件正文；改成"每张卡自带位置信号、只有被拖的那张重建"之后，必须证明
/// 重建范围真的收窄了——否则这个优化等于没做，而且退回去也没人会发现。
///
/// 顺带钉住两件容易踩的事：
///   - Stack 的直接子节点换成了 ValueListenableBuilder，里面才是
///     AnimatedPositioned。这条组合必须成立（ParentDataWidget 不能被夹在
///     会产出 RenderObject 的 widget 中间），否则整面墙起不来。
///   - 一次拖拽里"其余卡片矩形"只在按下时算一次，所以必须证明第二轮拖拽
///     拿到的是新一轮的矩形，而不是上一场拖拽留下的。
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/model/settings.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/ui/surface.dart';

/// 每个插件正文被 build 了几次。重建范围就是这里的计数。
class _BuildTally {
  final Map<String, int> counts = <String, int>{};

  int of(String id) => counts[id] ?? 0;

  void clear() => counts.clear();
}

class _Env {
  _Env(this.state, this.tally);

  final AppState state;
  final _BuildTally tally;

  PxSize get cardSize =>
      sizeToPx('2x2', state.settings.gridCell, state.settings.gridGap);

  Offset centerOf(int index) {
    final c = state.cards[index];
    return Offset(c.x + cardSize.w / 2, c.y + cardSize.h / 2);
  }
}

Future<_Env> _pumpSurface(WidgetTester tester, {int cardCount = 3}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('vectra/native'),
    (call) async => null,
  );
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vectra/native'), null);
  });

  // 拖完会走 Store.save（去抖 300ms）。给个临时目录，别把 config.json
  // 写进仓库里；顺带这个去抖 Timer 也需要在测试里等掉，否则会以
  // "还有未完成的 Timer" 让整条测试失败。
  final tmp = Directory.systemTemp.createTempSync('vectra_surface_test');
  addTearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });
  final store = Store(tmp.path);

  // 一行铺开，互不重叠，免得吸附/防重叠把它们推来推去
  const stride = 250.0;
  final state = AppState(
    settings: AppSettings(),
    cards: [
      for (var i = 0; i < cardCount; i++)
        WidgetCard(
          id: 'c$i',
          pluginId: 'demo',
          x: i * stride,
          y: 0,
          size: '2x2',
          z: i,
        ),
    ],
  );
  final tally = _BuildTally();

  await tester.pumpWidget(MaterialApp(
    home: DesktopSurface(
      state: state,
      store: store,
      buildPluginBody: (card, size) => Builder(builder: (context) {
        tally.counts[card.id] = (tally.counts[card.id] ?? 0) + 1;
        return const SizedBox.shrink();
      }),
    ),
  ));
  await tester.pump();

  return _Env(state, tally);
}

/// 拖一次，并返回**移动阶段**各张卡的重建次数。
///
/// 按下和松手各有一次全量重建（按下要抬 z、松手要把位移动画恢复回去），
/// 那两次是一次性的开销，不是我们要盯的东西——真正要盯的是"每来一个
/// pointer move 重建了几棵树"。所以计数窗口只框住中间那段。
Future<Map<String, int>> _dragAndCount(_Env env, WidgetTester tester,
    Offset from, Offset to,
    {int steps = 8}) async {
  final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump(); // pointer down：命中 → 抬 z → 进入拖拽
  env.tally.clear(); // 计数窗口从"开始移动"算起

  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump();
  }
  final during = Map<String, int>.from(env.tally.counts);

  await g.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // 等掉存盘去抖
  return during;
}

void main() {
  testWidgets('拖一张卡：移动过程中只有被拖的那张重建', (tester) async {
    final env = await _pumpSurface(tester, cardCount: 3);

    // 往下拖：c0 下方是空的，不会被防重叠挡住
    final from = env.centerOf(0);
    final during =
        await _dragAndCount(env, tester, from, from + const Offset(0, 160));

    expect(during['c0'] ?? 0, greaterThan(0),
        reason: '被拖的卡片必须跟着指针重建（壁纸切片取的源矩形随位置变）');
    expect(during['c1'] ?? 0, 0, reason: '没动的卡片不该被重建');
    expect(during['c2'] ?? 0, 0, reason: '没动的卡片不该被重建');
  });

  testWidgets('移动阶段的重建次数只跟帧数走，不跟卡片数放大',
      (tester) async {
    final env = await _pumpSurface(tester, cardCount: 5);

    final from = env.centerOf(0);
    final during = await _dragAndCount(env, tester, from,
        from + const Offset(0, 200),
        steps: 10);

    final dragged = during['c0'] ?? 0;
    expect(dragged, greaterThan(0));
    // 改造前这里会是 50 上下（10 帧 × 5 张卡）。
    expect(dragged, lessThan(30), reason: '重建范围应与卡片总数无关，实得 $dragged');

    final others = <String>['c1', 'c2', 'c3', 'c4']
        .fold<int>(0, (a, id) => a + (during[id] ?? 0));
    expect(others, 0, reason: '其余卡片的重建次数合计必须为 0，实得 $others');
  });

  testWidgets('落点写进了卡片数据', (tester) async {
    final env = await _pumpSurface(tester, cardCount: 2);
    final c0 = env.state.cards.first;
    final before = Offset(c0.x, c0.y);

    final from = env.centerOf(0);
    await _dragAndCount(env, tester, from, from + const Offset(0, 150));

    expect(Offset(c0.x, c0.y), isNot(before), reason: '落点必须写进数据');
  });

  testWidgets('第二轮拖拽拿的是新一轮的矩形，不吃上一场的缓存',
      (tester) async {
    final env = await _pumpSurface(tester, cardCount: 2);

    // 第一场：把 c0 拖到下方
    var from = env.centerOf(0);
    await _dragAndCount(env, tester, from, from + const Offset(0, 150));
    // 第二场：拖 c1
    from = env.centerOf(1);
    final during =
        await _dragAndCount(env, tester, from, from + const Offset(0, 150));

    expect(during['c1'] ?? 0, greaterThan(0), reason: '第二轮要能拖动');
    expect(during['c0'] ?? 0, 0,
        reason: 'c0 静止了，第二场拖拽不该再重建它（矩形缓存串味会在这里露馅）');
  });
}
