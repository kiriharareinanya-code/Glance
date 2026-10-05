/// 滚轮浏览的**视觉证据**（生成 PNG，自证用，不是常规断言测试）。
///
/// 断言测试能证明"偏移算对了、alpha 对了"，但证明不了"排出来好不好看"。
/// 这里把**真实组件**在几个滚动位置上截成 PNG，改完 UI 自己看一眼——
/// 不用等用户反馈，也不依赖当时在放什么歌（真实设备上多半查不到歌词）。
///
///     flutter test test/lyrics_browse_shot_test.dart
///     -> test/_browse_shots/{00,01,02,03}.png
@Tags(['gen'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/spec.dart';

const _outDir = 'test/_browse_shots';

/// 一首 28 行的中文歌（够长才有滚动空间），内容照《昔涟》前几句的样式编。
const _words = [
  '曾许下心愿 等待你的出现',
  '褪色的秋千 有本书会纪念',
  '我循着时间 捡起梦的照片',
  '风把名字念得很轻很轻',
  '路灯下的影子被拉得很长',
  '你说的话都变成了星光',
  '翻过这一页就是天涯',
  '各自安睡不必再见',
  '那些场面早已随风而散',
  '只有旋律还在原地',
  '窗台的雨停了又落',
  '我把沉默折成纸飞机',
  '它飞过唱针与山谷',
  '落在你看不见的年份',
  '多年后翻出来还是温的',
  '字迹褪成了浅灰色',
  '春天的信使正在路上',
  '它会替你敲开那扇门',
  '门后是海还是荒原',
  '都无所谓了',
  '因为你已经走过',
  '走过有雪的山脊',
  '走过无人的站台',
  '走过所有该告别的人',
  '最后只剩下一首歌',
  '陪你把夜熬到天明',
  '然后安静地各自老去',
  '而我会一直记得这个下午',
];

String _line(int i) => _words[i];

LyricsWidget _controller(String dir) {
  final spec = kBuiltinSpecs.firstWhere((s) => s.id == 'lyrics');
  final ctx = WidgetContext(
    store: Store(dir),
    card: WidgetCard(
        id: 'shot', pluginId: 'lyrics', x: 0, y: 0,
        size: const GridSize(5, 4).toString(), z: 0),
    pluginId: 'lyrics',
    onRequestSize: (_) {},
    onOpenSettings: () {},
    settings: spec.defaultSettings(),
    grid: const GridSize(5, 4),
    size: const Size(560, 400),
  );
  return LyricsWidget(ctx)
    ..debugSetLyrics([
      // 行距 1000ms，与 debugBuildFull 的 `position: idx * 1000` 对齐
      for (var i = 0; i < _words.length; i++) LrcLine(t: i * 1000, s: _line(i)),
    ]);
}

Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  // toImage / toByteData 必须包在 runAsync 里：它们要等真实的光栅线程回调，
  // 留在 fake-async zone 会永远 pending（测试直接挂住不报错，很难查）。
  final img = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2.0)))!;
  final bytes =
      await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png));
  final f = File(p.join(_outDir, '$name.png'));
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('写出 ${f.path} (${img.width}x${img.height})');
}

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
  testWidgets('生成滚轮浏览的视觉证据', (tester) async {
    final dir = p.join(Directory.systemTemp.path, 'glance-browse-shot');
    await tester.runAsync(() => Store(dir).load());
    final c = _controller(dir);
    await tester.runAsync(() async => c.debugPublishFull(9));

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 560,
            height: 400,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF16181C)),
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 14, color: Colors.white),
                child: ValueListenableBuilder<Widget?>(
                  valueListenable: c.debugWidgetChannel,
                  builder: (_, w, _) => w ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    // 00：跟随时（焦点在正在唱的第 10 句）
    await shoot(tester, key, '00-follow');

    // 01：往下滚 3 格 = 6 行
    for (var i = 0; i < 3; i++) {
      await wheel(tester, 120);
    }
    await shoot(tester, key, '01-scrolled-down');

    // 02：再往下滚 3 格（共 12 行）
    for (var i = 0; i < 3; i++) {
      await wheel(tester, 120);
    }
    await shoot(tester, key, '02-scrolled-more');

    // 03：往回滚 4 格 —— 必须能滚回去，且回到浏览位置而不是直接跳回
    for (var i = 0; i < 4; i++) {
      await wheel(tester, -120);
    }
    await shoot(tester, key, '03-scrolled-back');

    // 04：停手 4 秒后自动回到正在唱的那行。
    // **必须 pump 到弹簧走完**：回归跟随时 `browsing` 由 true 翻成 false，
    // 于是 SpringSlide 重新拿到动画许可，从浏览位置弹回跟随位置。只 pump
    // 一帧的话内容还停在半路——状态变量已经是对的（base/offset 都归位），
    // 但画出来的是弹簧中途的位置，看着像"高亮丢了"。
    c.debugExpireBrowse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await shoot(tester, key, '04-expired-back-to-follow');
  });
}
