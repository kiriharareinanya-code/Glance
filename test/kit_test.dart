/// kit.dart 共享件的行为测试。
///
/// node.dart（JSON 树解释器）随协议退役删除后，其中仍然有效的行为契约
/// 在这里以"直接泵 widget"的方式延续：
///   - 颜色解析：#RGB / #RRGGBB / #RRGGBBAA，以及"6 位色不能被当成
///     RRGGBBAA 旋转"的回归（蓝色曾被渲染成粉色）；
///   - PluginSlider：拖动按松手位置回调 0..1；置灰后不接收拖动；
///   - TapFeedback：按压反馈不挡交互；
///   - FlipTransition：翻页换值；关动画直接换值。
library;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/widgets/flip_transition.dart';
import 'package:vectra/widgets/kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nodeColor', () {
    test('#RGB 三位展开', () {
      expect(nodeColor('#F00'), const Color(0xFFFF0000));
    });

    test('#RRGGBB 补不透明 alpha', () {
      expect(nodeColor('#29B6F6'), const Color(0xFF29B6F6));
    });

    test('#RRGGBBAA（alpha 在后）', () {
      expect(nodeColor('#FFFFFF33'), const Color(0x33FFFFFF));
      // RRGGBBAA 语义下 'D9000000' = R=D9,G=00,B=00,A=00（全透明）。
      // todo 删除按钮的旧底色就是这个值——原生重写保持逐字节一致，
      // 这里锁住语义，防止有人"顺手修正"成 AARRGGBB 造成行为漂移。
      expect(nodeColor('#D9000000'), const Color(0x00D90000));
    });

    test('6 位色值不能被当成 RRGGBBAA 旋转（蓝色曾被渲染成粉色）', () {
      // 6 位补 alpha 后必须是 FF 前缀；若再走一次 RRGGBBAA 旋转，
      // #29B6F6 会变成 #F6FF29B6（粉紫色）。
      final c = nodeColor('#29B6F6');
      expect((c.r * 255.0).round(), 0x29);
      expect((c.g * 255.0).round(), 0xB6);
      expect((c.b * 255.0).round(), 0xF6);
      expect((c.a * 255.0).round(), 0xFF);
    });
  });

  group('withGaps', () {
    testWidgets('在相邻孩子之间插入间隔', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: withGaps(
              [const Text('a'), const Text('b'), const Text('c')],
              10,
            ),
          ),
        ),
      ));
      final a = tester.getTopLeft(find.text('a')).dy;
      final b = tester.getTopLeft(find.text('b')).dy;
      final c = tester.getTopLeft(find.text('c')).dy;
      expect(b - a, greaterThan(10));
      expect(c - b, greaterThan(10));
    });
  });

  group('PluginSlider', () {
    testWidgets('拖动后按松手位置回调 0..1', (tester) async {
      double? reported;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: PluginSlider(
              value: 0,
              height: 4,
              color: Colors.white,
              background: const Color(0x22FFFFFF),
              enabled: true,
              onChanged: (v) => reported = v,
            ),
          ),
        ),
      ));

      final bar = find.byType(PluginSlider);
      final center = tester.getCenter(bar);
      final g = await tester.startGesture(center,
          kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await tester.pump();
      await g.moveTo(center + const Offset(100, 0)); // 拖到中点偏右
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(reported, isNotNull);
      expect(reported!, greaterThan(0.4));
      expect(reported!, lessThanOrEqualTo(1.0));
    });

    testWidgets('置灰后不接收拖动', (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: PluginSlider(
              value: 0,
              height: 4,
              color: Colors.white,
              background: const Color(0x22FFFFFF),
              enabled: false,
              onChanged: (_) => called = true,
            ),
          ),
        ),
      ));

      final center = tester.getCenter(find.byType(PluginSlider));
      final g = await tester.startGesture(center,
          kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await tester.pump();
      await g.moveTo(center + const Offset(100, 0));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(called, isFalse, reason: 'disabled 的滑条不能回调');
    });
  });

  group('TapFeedback', () {
    testWidgets('按压反馈不挡交互（点得到也回调）', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TapFeedback(
              animate: true,
              onTap: () => taps++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(TapFeedback));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('onTap 为 null 时也能渲染（纯展示态）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TapFeedback(
            animate: false,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('FlipTransition', () {
    testWidgets('值变化走机械翻页并精确到位', (tester) async {
      var value = '07';
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, s) {
            set = s;
            return FlipTransition(
              value: value,
              textBuilder: (v) => Text(v,
                  style: const TextStyle(
                      fontSize: 58,
                      fontFamily: 'TsukushiBMaru',
                      fontFeatures: [FontFeature.tabularFigures()])),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('07'), findsOneWidget);

      set(() => value = '08');
      await tester.pump();
      // 翻页中途旧值/新值同时存在（上半页/下半页）
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('08'), findsOneWidget);
      expect(find.text('07'), findsNothing,
          reason: '翻页结束后旧值必须退场');
    });

    testWidgets('关闭动画时直接换值（不翻）', (tester) async {
      var value = '07';
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, s) {
            set = s;
            return FlipTransition(
              value: value,
              animate: false,
              textBuilder: (v) => Text(v, style: const TextStyle(fontSize: 20)),
            );
          }),
        ),
      ));

      set(() => value = '08');
      await tester.pump();
      expect(find.text('08'), findsOneWidget);
      expect(find.text('07'), findsNothing);
    });
  });

  group('NodeIcon', () {
    testWidgets('未知名字落到兜底图标且不崩', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: NodeIcon(
              name: 'no_such_icon',
              size: 16,
              color: Colors.white,
              animate: false),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('名字变化触形变渲染（circle ↔ check_circle）', (tester) async {
      var name = 'circle';
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, s) {
            set = s;
            return NodeIcon(
                name: name, size: 16, color: Colors.white, animate: false);
          }),
        ),
      ));
      await tester.pumpAndSettle();

      set(() => name = 'check_circle');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
