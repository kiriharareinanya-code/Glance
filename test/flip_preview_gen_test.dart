// 翻页动效的逐帧预览生成器（手动跑，不进 CI 断言）：
//
//   flutter test test/flip_preview_gen_test.dart
//
// 翻页是"看起来对不对"的东西，断言只能锁住结构（半页在不在、旧值退不退场），
// 锁不住"中线会不会跳、透视像不像在翻"。所以这里把真实字体渲染的中间帧
// 导成 PNG，人眼过一遍。输出在 build/flip-preview/（build 目录不进 git）。
//
// 用时钟的圆体字（TsukushiBMaru），因为翻页效果是给它做的。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/plugin/flip_transition.dart';

/// 抓当前帧存成 PNG
Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('flip')));
  final bytes = await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = Directory('build/flip-preview');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  await File('${dir.path}/$name.png').writeAsBytes(bytes!);
}

void main() {
  setUpAll(() async {
    // 真实字体：不加载的话测试字体把所有字形画成实心方块，
    // 半页裁剪看不出"翻一张纸"的效果
    final loader = FontLoader('TsukushiBMaru');
    loader.addFont(rootBundle.load('assets/fonts/tsukushi_b_maru.ttf'));
    await loader.load();
  });

  // 默认跳过：全量测试不该每次都渲染 9 张 PNG。要看效果时：
  //   set FLIP_PREVIEW=1 && flutter test test/flip_preview_gen_test.dart
  final enabled = Platform.environment['FLIP_PREVIEW'] == '1';

  testWidgets('导出翻页中间帧', skip: !enabled, (tester) async {
    Widget app(String v) => MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF16263C),
            body: Center(
              child: RepaintBoundary(
                key: const Key('flip'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FlipTransition(
                    value: v,
                    textBuilder: (s) => Text(
                      s,
                      style: const TextStyle(
                        fontFamily: 'TsukushiBMaru',
                        fontSize: 120,
                        height: 1.0,
                        color: Color(0xFF7CC7FF),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app('07'));
    await tester.pump();
    await tester.pumpWidget(app('08'));
    await tester.pump(); // t = 0

    var elapsed = 0;
    await _shot(tester, 't000');
    for (final step in [60, 60, 60, 30, 30, 60, 60, 60]) {
      await tester.pump(Duration(milliseconds: step));
      elapsed += step;
      await _shot(tester, 't${elapsed.toString().padLeft(3, '0')}');
    }

    // ignore: avoid_print
    print('翻页帧已导出到 build/flip-preview/（共 ${elapsed}ms）');
    expect(elapsed, greaterThan(0));
  });
}
