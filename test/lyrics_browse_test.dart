/// 歌词卡的**滚轮浏览**行为测试（`lib/widgets/builtin/lyrics.dart`）。
///
/// 这个功能全靠"滚得动、滚得对、滚得回来"成立，所以测试不去断言内部字段
/// 快照，而是发**真的滚轮事件**（走 `TestGesture` 的指针通道，和桌面上一致，
/// 命中测试也一起覆盖），然后量**真实渲染出来的文字**：滚下去要能看到后面的
/// 句子，滚回来要能回到原来的句子，停手之后要自动回到正在唱的那行。
///
/// 每条用例对应一个真实踩过的坑：
///   - 方向别反：往下滚看的是**后面**的歌词；
///   - 焦点层级要跟着视口走：不然滚到的行全是 0.14 透明度，等于看不见；
///   - 偏移要双向：曾经被夹成 `[0, …]`，永远滚不回上一句；
///   - 触控板细粒度滚动要能累积：每格都 round 成 0 就"推了没反应"；
///   - 停手 [_browseHoldMs] 要自动回到跟随。
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/spec.dart';

/// 演示歌词：下标即行号，方便断言"屏幕上第几行是第几句"。
///
/// 行距必须是 **1000ms**：`debugBuildFull(idx)` 造的假媒体快照把播放位置
/// 定在 `idx * 1000`，之后每次 `_paint` 都会用 `_view.indexAt(pos)` 重算行号。
/// 行距一旦不是 1000，重算出的行号就和传进去的 idx 对不上（曾出现"初始
/// 焦点在第四句、一滚滚轮却跳到第一句"的假象）。
///
/// 30 行是刻意的：歌词区在这个画布下约 9 行可见，歌得**足够长**才有
/// 真实的滚动空间。12 行时整首歌几乎一屏装下，上下都顶到边界，"能不能滚"
/// 根本测不出来（曾因此让"滚不动"的用例也显示为通过）。
String _line(int i) => '第${i + 1}句 歌词内容';

/// 找歌词组件的 spec（内置表里按 id 取）。
BuiltinSpec _lyricsSpec() =>
    kBuiltinSpecs.firstWhere((s) => s.id == 'lyrics');

/// 隔离宿主：假卡片 + 独立 Store（临时目录），不碰真实 pluginData。
LyricsWidget _makeController(String dir) {
  final spec = _lyricsSpec();
  final ctx = WidgetContext(
    store: Store(dir),
    card: WidgetCard(
        id: 'browse',
        pluginId: 'lyrics',
        x: 0,
        y: 0,
        size: const GridSize(4, 4).toString(),
        z: 0),
    pluginId: 'lyrics',
    onRequestSize: (_) {},
    onOpenSettings: () {},
    settings: spec.defaultSettings(),
    grid: const GridSize(4, 4),
    size: const Size(420, 460),
  );
  final c = LyricsWidget(ctx)
    ..debugSetLyrics([
      // 行距 1000ms：与 debugBuildFull 的 `position: idx * 1000` 对齐，
      // 否则 _paint 用 indexAt(pos) 重算出的行号会和传入的 idx 不一致。
      for (var i = 0; i < _count; i++) LrcLine(t: i * 1000, s: _line(i)),
    ]);
  return c;
}

/// 把组件挂起来并 pump，返回控制器。
///
/// 画布用竖长条：歌词区要够高才能同时看见好几行，行数太少就谈不上"浏览"。
///
/// **必须走 `ValueListenableBuilder(ctx.widget)` 这条真实通道**（和
/// `builtin_card_body.dart` 里桌面上的宿主一模一样）：`_paint` 是通过
/// `ctx.renderWidget()` 写进这个 notifier 来重绘的。如果测试直接
/// `pumpWidget(debugBuildFull(...))` 拿一棵静态树，滚轮触发的重绘就写进了
/// 没人监听的 notifier——屏幕上的树永远不变，测试会误判成"滚轮没反应"。
Future<LyricsWidget> pumpLyrics(
  WidgetTester tester, {
  int startLine = 3,
}) async {
  final dir = p.join(Directory.systemTemp.path, 'glance-browse-test');
  await tester.runAsync(() => Store(dir).load());
  final c = _makeController(dir);
  // 先构建一次并写进 ctx.widget，notifier 才有初值（真实宿主也是这样：
  // mount 里第一次 renderWidget 把空态推进来）。
  await tester.runAsync(() async => c.debugPublishFull(startLine));

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Center(
      child: SizedBox(
        width: 420,
        height: 460,
        // 组件文字色走宿主 DefaultTextStyle
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 14, color: Colors.white),
          child: ValueListenableBuilder<Widget?>(
            valueListenable: c.debugWidgetChannel,
            builder: (_, w, _) => w ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return c;
}

/// 演示歌词共多少行（见 [_line] 的注释：必须够长才有真实滚动空间）。
const _count = 30;

/// 屏幕上**当前渲染出来**的歌词行文本（按渲染树顺序）。
///
/// 刻意从渲染树读而不是读 `_lines`：这个功能的成败全在"用户眼睛看到什么"，
/// 内部数组对得上不代表画出来对得上（透明度、裁剪、弹簧位置都影响可见性）。
List<String> visibleLines(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null && _isLyric(t.data!)) t.data!,
    ];

/// 是不是演示歌词里的一句（按下标判断，避开控制条上的时间等文本）。
bool _isLyric(String s) =>
    RegExp(r'^第\d+句 歌词内容$').hasMatch(s);

/// 第 [i] 句在屏幕上的不透明度（没渲染出来返回 null）。
double? alphaOf(WidgetTester tester, int i) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data == _line(i)) return t.style?.color?.a;
  }
  return null;
}

/// 屏幕上**最亮**（不透明度最高）的那一行，也就是焦点行，返回其下标。
///
/// 焦点层级用 alpha 区分。只断言"某行存在"抓不到焦点 bug——所有行都在树上，
/// 只是有的太淡看不见。浏览时最淡的档位是 0.14，几乎不可读。
int? focusIndex(WidgetTester tester) {
  int? best;
  var bestAlpha = -1.0;
  for (var i = 0; i < _count; i++) {
    final a = alphaOf(tester, i);
    if (a == null) continue;
    if (a > bestAlpha) {
      bestAlpha = a;
      best = i;
    }
  }
  return best;
}

/// 往歌词区发一格滚轮。[dy] > 0 = 往下滚（看后面的歌词）。
///
/// 走**真实指针通道**（`PointerScrollEvent` 经 `handlePointerEvent` 派发），
/// 和桌面上一致，命中测试一并覆盖；直接调 `_onWheel` 会绕过命中测试，
/// 测不到 Listener 到底挂没挂对、会不会被上层手势截走。
Future<void> wheel(WidgetTester tester, double dy) async {
  final center = tester.getCenter(find.byType(DefaultTextStyle).last);
  tester.binding.handlePointerEvent(PointerScrollEvent(
    position: center,
    scrollDelta: Offset(0, dy),
    kind: PointerDeviceKind.mouse,
  ));
  await tester.pump();
}

void main() {
  // 一格 Windows 滚轮 = 120 刻度；组件按 60 刻度一行，所以一格 = 两行。
  const oneNotch = 120.0;

  testWidgets('往下滚能看到后面的歌词（窗口真的下移）', (tester) async {
    final w = await pumpLyrics(tester, startLine: 10);
    expect(focusIndex(tester), 10, reason: '起点高亮在第 11 句（正在唱的那行）');
    final baseBefore = w.debugWindowBase;

    // 两格 = 4 行。**不能只滚一格**：锚点把当前行放在第 2 个可见行，
    // 滚 2 行恰好让窗口顶端落回当前行本身，看着像"没动"——那是巧合，
    // 不是 bug。滚 4 行才能真正越过它。
    await wheel(tester, oneNotch * 2);

    expect(w.debugWindowBase, greaterThan(baseBefore),
        reason: '窗口必须真的往下移（内容要能滚到后面去）');
    expect(w.debugWindowBase, baseBefore + 4,
        reason: '一格滚轮 = 两行，滚两格就该下移四行');
    expect(w.debugBrowseOffset, greaterThan(0));
  });

  testWidgets('往回滚能回到之前的歌词（偏移是双向的）', (tester) async {
    final w = await pumpLyrics(tester, startLine: 15);
    expect(focusIndex(tester), 15);

    await wheel(tester, -oneNotch);
    final back = focusIndex(tester);
    expect(back, isNot(15), reason: '往回滚窗口确实动了');
    expect(back, lessThan(15), reason: '往回滚要看到**前面**的歌词');
    expect(w.debugBrowseOffset, lessThan(0),
        reason: '往回滚必须产生负偏移（曾被夹成只能单向往后翻）');

    await wheel(tester, oneNotch);
    expect(focusIndex(tester), 15, reason: '往回滚必须能回到原处');
    expect(w.debugBrowseOffset, 0);
  });

  testWidgets('浏览时整列**均匀可读**，不给任何行高亮', (tester) async {
    final w = await pumpLyrics(tester, startLine: 2);
    for (var i = 0; i < 5; i++) {
      await wheel(tester, oneNotch);
    }
    // 滚远了，正在唱的那行（第 3 句）已经不在视口里 —— 此时**没有任何行**
    // 该有高亮：整列同一档亮度，用户要的是一份平铺的歌词列表。
    expect(w.debugWindowBase, greaterThan(2));
    final alphas = <double>[];
    for (var i = 0; i < _count; i++) {
      final a = alphaOf(tester, i);
      if (a != null) alphas.add(a);
    }
    expect(alphas, isNotEmpty, reason: '视口里总该有几行字');
    for (final a in alphas) {
      expect(a, closeTo(0.82, 0.01),
          reason: '浏览时每行都该是同一个可读档位（不能有高亮行）');
    }
  });

  testWidgets('浏览时若正在唱的那行仍在视口内，只有它带辉光', (tester) async {
    await pumpLyrics(tester, startLine: 10);
    // 只滚一点点，保证第 11 行仍留在视口里
    await wheel(tester, 60);
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final glowing = <String>[];
    for (final t in texts) {
      if (t.data == null || !_isLyric(t.data!)) continue;
      if ((t.style?.shadows ?? const []).isNotEmpty) glowing.add(t.data!);
    }
    expect(glowing, <String>[_line(10)],
        reason: '辉光= 正在唱，浏览期间也只能是正在唱的那一行');
  });

  testWidgets('滚到歌尾会停住，不会越界', (tester) async {
    final w = await pumpLyrics(tester, startLine: 20);
    for (var i = 0; i < 20; i++) {
      await wheel(tester, oneNotch);
    }
    final range = w.debugBrowseRange;
    expect(w.debugBrowseOffset, lessThanOrEqualTo(range.last),
        reason: '偏移不能超过歌尾允许的上界');
    expect(w.debugBrowseOffset, range.last,
        reason: '滚到底应该正好停在歌尾（上界）');
    expect(visibleLines(tester), contains(_line(_count - 1)),
        reason: '滚到歌尾时最后一句要还在屏幕上');
  });

  testWidgets('滚到歌头会停住，不会越界', (tester) async {
    final w = await pumpLyrics(tester, startLine: 10);
    for (var i = 0; i < 20; i++) {
      await wheel(tester, -oneNotch);
    }
    expect(w.debugBrowseOffset, w.debugBrowseRange.first,
        reason: '滚到歌头应该正好停在歌头（下界）');
    expect(visibleLines(tester), contains(_line(0)),
        reason: '滚到歌头时第一句要还在屏幕上');
  });

  testWidgets('触控板细粒度滚动会累积，不会"推了没反应"', (tester) async {
    final w = await pumpLyrics(tester, startLine: 15);
    // 一次只给 10 刻度（远小于一行的 60），连发 6 次 = 60 刻度 = 整整一行。
    for (var i = 0; i < 6; i++) {
      await wheel(tester, 10);
    }
    expect(w.debugBrowseOffset, 1,
        reason: '细粒度滚动必须累加到一整行才生效（浮点差一丝就永远差一行）');
  });

  testWidgets('停手之后自动回到正在唱的那行', (tester) async {
    final w = await pumpLyrics(tester, startLine: 10);
    await wheel(tester, oneNotch * 3);
    expect(w.debugBrowseOffset, greaterThan(0));
    expect(focusIndex(tester), isNot(10));

    w.debugExpireBrowse(); // 模拟停手超过 4 秒
    await tester.pump();

    expect(w.debugBrowseOffset, 0, reason: '停手后必须回到自动跟随');
    expect(focusIndex(tester), 10,
        reason: '回到跟随后焦点必须重新落在正在唱的那行');
    expect(alphaOf(tester, 10), closeTo(1.0, 0.01));
  });

  testWidgets('浏览偏移会被夹在可浏览范围内，窗口不会滚出歌外',
      (tester) async {
    final w = await pumpLyrics(tester, startLine: 15);
    final range = w.debugBrowseRange;
    expect(range.first, lessThan(0), reason: '必须能往回滚（负偏移）');
    expect(range.last, greaterThan(0), reason: '必须能往后滚（正偏移）');

    // 疯狂乱滚之后，窗口顶端仍然落在 [0, 歌尾] 内。
    for (final dy in [oneNotch, -oneNotch, oneNotch * 3, -oneNotch * 4]) {
      await wheel(tester, dy);
      expect(w.debugWindowBase, greaterThanOrEqualTo(0),
          reason: '窗口顶端不能越过歌头');
      expect(w.debugWindowBase, lessThanOrEqualTo(_count),
          reason: '窗口顶端不能越过歌尾');
    }
  });
}
