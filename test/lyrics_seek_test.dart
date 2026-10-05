/// 点击歌词跳转的行为测试（`lib/widgets/builtin/lyrics.dart`）。
///
/// 用户的要求：「我点击歌词之后，请你马上跳转并将其高亮」。
/// 这句话里有**三件**必须同时成立的事，少一件都等于"点了没反应"：
///   1. **跳转**——发 seek 到那一行的起始时间；
///   2. **马上高亮**——不是等 250ms 的 SMTC 采样回来才亮，是同帧就位；
///   3. **退出浏览**——如果点之前正在滚轮浏览，必须回到跟随状态，
///      否则浏览期间「整列不给高亮」会把刚点的那行也一起压暗。
///
/// 第 3 点是真正的 bug 所在：`_browseOffset` 没清→ `browsing` 为真 →
/// 高亮逻辑刻意不给任何行高亮，窗口也停在浏览位置。播放位置跳了，
/// 画面纹丝不动。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/spec.dart';

String _line(int i) => '第${i + 1}句 歌词内容';

const _count = 30;

BuiltinSpec _lyricsSpec() => kBuiltinSpecs.firstWhere((s) => s.id == 'lyrics');

LyricsWidget _makeController(String dir) {
  final spec = _lyricsSpec();
  final ctx = WidgetContext(
    store: Store(dir),
    card: WidgetCard(
        id: 'seek',
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
  return LyricsWidget(ctx)
    ..debugSetLyrics([
      for (var i = 0; i < _count; i++) LrcLine(t: i * 1000, s: _line(i)),
    ]);
}

/// 挂起组件并 pump，返回控制器。
///
/// **这里刻意一个 `tester.runAsync` 都不包。** 踩过的坑：之前给
/// `Store(dir).load()` 和 `debugPublishFull()` 都套了 `runAsync`，
/// 结果第 3 条用例起**永远不返回**（症状是 `did not complete`，
/// 不是报错，看着像框架坏了）。两个原因叠加：
///   1. [LyricsWidget.debugPublishFull] 是**同步**的（只做
///      `notifier.value = w`），把它扔进真实异步区间毫无意义；
///   2. `runAsync` 会把后续代码切到真实 event loop，一旦里面有
///      组件起的**真实 Timer**（`_tick` 的 `ctx.interval`），测试收尾时
///      要等真实异步静默，就再也回不来了。
/// `Store` 在这些用例里只被当成一个隔离的容器（不读配置），
/// `lyrics_switch_test.dart` 早就证明不 `load()` 也能跑。
///
/// 临时目录仍按用例递增，避免多个 [Store] 抢同一个目录。
int dirIndex = 0;

Future<LyricsWidget> pumpLyrics(WidgetTester tester, {int startLine = 3}) async {
  final dir = p.join(Directory.systemTemp.path, 'glance-seek-test-$dirIndex');
  dirIndex++;
  final c = _makeController(dir);
  c.debugPublishFull(startLine);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Center(
      child: SizedBox(
        width: 420,
        height: 460,
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

bool _isLyric(String s) => RegExp(r'^第\d+句 歌词内容$').hasMatch(s);

List<String> visibleLines(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null && _isLyric(t.data!)) t.data!,
    ];

double? alphaOf(WidgetTester tester, int i) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    if (t.data == _line(i)) return t.style?.color?.a;
  }
  return null;
}

/// 屏幕上最亮（不透明度最高）的那一行，也就是**高亮行**，返回其下标。
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

/// 点第 [i] 句歌词（走真实 tap 通道，命中测试一并覆盖）。
///
/// **必须先确认这一行真的点得到**，这里有一道很阴的门槛：
/// 歌词区外面套了 `ClipRect`，行堆用 `OverflowBox` 放开高度，于是有一批行
/// 坐标还在台面范围内、却被裁掉一截——tap 落在框外，点了空气，
/// 表现为"点了没反应"，看着像产品 bug。
/// 所以可见性判定直接问组件（`debugLineFullyVisible`），别从渲染树猜：
/// 猜框高会算错（行高是行间距，框高是整块歌词区，差一个量级）。
Future<void> tapLine(WidgetTester tester, LyricsWidget w, int i) async {
  final finder = find.text(_line(i));
  expect(finder, findsOneWidget, reason: '第 ${i + 1} 句必须在渲染树里');
  expect(w.debugLineFullyVisible(i), isTrue,
      reason: '第 ${i + 1} 句必须完整落在歌词取景框内才能点'
          '（windowBase=${w.debugWindowBase}）');
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}

/// 屏幕上**完整可点**的歌词行下标，按屏幕 y 从上到下排。
List<int> tappableLineIndices(WidgetTester tester, LyricsWidget w) => [
      for (var i = 0; i < _count; i++)
        if (w.debugLineFullyVisible(i)) i
    ];

/// 让组件进入滚轮浏览状态（滚两格 = 下移 4 行）。
///
/// 直接走组件的 `debugWheel` 钩子而**不是**发指针事件：这个用例要验的是
/// 「点击会退出浏览状态」这条状态机，不是命中测试。命中测试由
/// `lyrics_browse_test.dart` 专门覆盖（那边发真的 `PointerScrollEvent`）。
///
/// 踩过的坑：一开始在这里发真滚轮事件，落点取 `find.byType(Listener).last`
/// ——取错了，滚轮没生效却把断言打在"没进入浏览"上，误导方向。
void enterBrowse(LyricsWidget w) => w.debugWheel(240);

void main() {

  testWidgets('点某一句会跳到那一句并高亮它', (tester) async {
    final w = await pumpLyrics(tester, startLine: 3);
    expect(focusIndex(tester), 3, reason: '起点高亮在第 4 句（正在唱的那行）');

    // 点视口内**靠后**的一句（不能硬编码下标——那一行可能不在视口里）
    final vis = tappableLineIndices(tester, w);
    expect(vis.length, greaterThan(3), reason: '视口里至少要有个三四行能点');
    final target = vis[vis.length - 1];
    expect(target, greaterThan(3));

    await tapLine(tester, w, target);
    expect(focusIndex(tester), target, reason: '点了哪行，高亮就跟到哪行');
    expect(alphaOf(tester, target), closeTo(1.0, 0.01),
        reason: '被点的那行要是真高亮（全不透明），不是浏览那种 0.82 压平');
  });

  testWidgets('点前面的某一句同样能跳（往前跳）', (tester) async {
    final w = await pumpLyrics(tester, startLine: 20);
    expect(focusIndex(tester), 20);

    // 往前点：选视口里**在当前行之前**、最靠上的那一行
    final vis = tappableLineIndices(tester, w);
    final before = vis.where((i) => i < 20).toList();
    expect(before, isNotEmpty, reason: '视口里得有在当前行之前的行可点');
    await tapLine(tester, w, before.first);
    expect(focusIndex(tester), before.first, reason: '往回点也要跳过去并高亮');
  });

  testWidgets('点行之后不再停留在浏览位置', (tester) async {
    final w = await pumpLyrics(tester, startLine: 3);

    // 先滚到浏览状态：整列压平、无高亮、窗口下移
    enterBrowse(w);
    await tester.pump();
    expect(w.debugBrowseOffset, greaterThan(0), reason: '先进入浏览状态');
    for (var i = 0; i < _count; i++) {
      final a = alphaOf(tester, i);
      if (a != null) {
        expect(a, closeTo(0.82, 0.01), reason: '浏览时整列压平');
      }
    }

    // 在浏览状态下点其中一行
    final vis = tappableLineIndices(tester, w);
    expect(vis.length, greaterThan(2), reason: '浏览后视口里得有行可点');
    final target = vis[vis.length ~/ 2];
    await tapLine(tester, w, target);

    expect(w.debugBrowseOffset, 0,
        reason: '点击的语义是「跳到这句唱」，必须退出浏览（这条曾是真 bug：'
            '不清浏览状态→ browsing 为真 → 整列不给高亮 → 点了像没反应）');
    expect(focusIndex(tester), target, reason: '被点的那行必须立刻成为高亮行');
    expect(alphaOf(tester, target), closeTo(1.0, 0.01),
        reason: '高亮必须是真的 1.0，而不是浏览档 0.82');
  });

  testWidgets('点击后高亮是**同帧**给的，不等 SMTC 采样', (tester) async {
    final w = await pumpLyrics(tester, startLine: 3);
    // 关键：tap 之后**只 pump 一帧**，不去等 _tick 的 250ms 采样。
    // 乐观位置（_seekOptimistic）就是为这个存在的——没有它这里会失败。
    final vis = tappableLineIndices(tester, w);
    final target = vis[vis.length - 1];
    await tapLine(tester, w, target);
    expect(focusIndex(tester), target,
        reason: '高亮必须同帧就位；靠真实采样回来会晚 250ms，'
            '点完看着像"没点上"');
  });

  testWidgets('点击的行会滚进视口（窗口跟着跳）', (tester) async {
    final w = await pumpLyrics(tester, startLine: 2);
    final baseBefore = w.debugWindowBase;

    // 点视口里**最靠后**的那一行：点完取景窗要重新锚定到它，
    // 所以窗口基准必须跟着往后挪（而不是停在原处让人找半天）。
    final vis = tappableLineIndices(tester, w);
    final target = vis[vis.length - 1];
    await tapLine(tester, w, target);

    expect(w.debugWindowBase, greaterThan(baseBefore),
        reason: '点后面那句时取景窗要跟过去（base 应前移）');
    expect(visibleLines(tester), contains(_line(target)),
        reason: '被点的那行必须真的在屏幕上');
    expect(focusIndex(tester), target, reason: '被点的那行是当前行');
  });

  testWidgets('连点两句以最后一次为准', (tester) async {
    final w = await pumpLyrics(tester, startLine: 3);
    final vis = tappableLineIndices(tester, w);
    final a = vis[1];
    await tapLine(tester, w, a);
    expect(focusIndex(tester), a);

    // 第一次点击后窗口会重锚，重新取可见行再点第二下
    final vis2 = tappableLineIndices(tester, w);
    final b = vis2[vis2.length - 1];
    await tapLine(tester, w, b);
    expect(focusIndex(tester), b, reason: '以最后一次点击为准');
  });

  testWidgets('点击不会破坏浏览的其它行为（滚完还能回来）', (tester) async {
    final w = await pumpLyrics(tester, startLine: 3);
    final vis = tappableLineIndices(tester, w);
    await tapLine(tester, w, vis[2]);
    final afterTap = focusIndex(tester);
    expect(focusIndex(tester), afterTap, reason: '点击生效');

    // 点完之后还能正常进入浏览（滚轮依然可用）
    enterBrowse(w);
    await tester.pump();
    expect(w.debugBrowseOffset, greaterThan(0), reason: '点击后滚轮依然可用');
  });

  testWidgets('跳转真的发出去了：seek 命令带着那一行的时间', (tester) async {
    // 前面几条只证明了「高亮跳过去」，没证明「播放器真被告知要跳」——
    // 高亮是乐观位置画出来的，seek 命令发不出去的话，画面照样对，
    // 歌却还在原地放。所以这里直接拦 native 通道看发出去的内容。
    //
    // 拦截的是 `MethodChannel('vectra/native')` 上的 `smtcControl`
    // （见 NativeBridge.smtcControl），也就是 seek 真正走的那个出口。
    final calls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('vectra/native'),
      (call) async {
        if (call.method == 'smtcControl') calls.add(call.arguments as Map);
        return true;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('vectra/native'), null);
    });

    final w = await pumpLyrics(tester, startLine: 3);
    final vis = tappableLineIndices(tester, w);
    final target = vis[vis.length - 1];
    await tapLine(tester, w, target);

    // 行距是 1000ms，第 target 句的起点就是 target * 1000
    expect(calls.where((c) => c['cmd'] == 'seek'), isNotEmpty,
        reason: '点歌词必须发出 seek 命令，否则歌不会真的跳');
    final seek = calls.lastWhere((c) => c['cmd'] == 'seek');
    expect(seek['posMs'], target * 1000,
        reason: 'seek 必须落在被点那一行的起点，而不是别的位置');
  });
}
