// 图标形变（MorphableIcon）的回归测试。
//
// 守的点：名字变化时要真的换到形变组件（IconicShapeMorph），静止时是
// IconImage，形变表之外的名字回退字体图标——三条路径都不能炸。
import 'package:fluent_ui/fluent_ui.dart' hide Icon;
import 'package:flutter/material.dart' show Icon, Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/iconic_morph.dart';
import 'package:vectra/plugin/morph_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => FluentApp(
        home: Center(child: child),
      );

  MorphableIcon icon(String name, {bool animate = true}) => MorphableIcon(
        name: name,
        size: 24,
        color: const Color(0xFFFFFFFF),
        animate: animate,
        fallback: Icons.square_outlined,
      );

  testWidgets('静止态渲染 IconImage，不启动形变', (tester) async {
    await tester.pumpWidget(wrap(icon('circle')));
    await tester.pumpAndSettle();

    expect(find.byType(IconImage), findsOneWidget);
    expect(find.byType(IconicShapeMorph), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('名字变化（circle → check_circle）触发一次形变', (tester) async {
    await tester.pumpWidget(wrap(icon('circle')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(icon('check_circle')));
    await tester.pump(); // 触发 didUpdateWidget

    expect(find.byType(IconicShapeMorph), findsOneWidget,
        reason: '两端都有 path 数据的切换要走形变，不该硬切');

    // 播完动画组件仍定格在目标图标上，不报错
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消（check_circle → circle）也要有形变，与确认对称', (tester) async {
    await tester.pumpWidget(wrap(icon('check_circle')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(icon('circle')));
    await tester.pump();

    expect(find.byType(IconicShapeMorph), findsOneWidget,
        reason: '取消和确认只是方向不同，视觉反馈必须对称——不能只有确认有动画');
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认/取消来回切换，每一次都要形变（起点不能用过期值）',
      (tester) async {
    // 这条守的是"只有第一次有动画"的老毛病：形变的起点取了上一次形变的
    // 起点（过期值），第二次切换时起点正好等于目标，动画被整段跳过。
    await tester.pumpWidget(wrap(icon('circle')));
    await tester.pumpAndSettle();

    for (final name in ['check_circle', 'circle', 'check_circle', 'circle']) {
      await tester.pumpWidget(wrap(icon(name)));
      await tester.pump();
      expect(find.byType(IconicShapeMorph), findsOneWidget,
          reason: '切到 $name 时应该有形变，连着切也不能退化成硬切');
      // 播完再切下一次，模拟真实点击的节奏
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('形变播完后回到静态渲染（静止外观统一，不再空心/实心横跳）',
      (tester) async {
    await tester.pumpWidget(wrap(icon('play')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(icon('pause')));
    await tester.pump();
    expect(find.byType(IconicShapeMorph), findsOneWidget);

    // 形变时长 + 缓冲之后应切回 IconImage——morph 画笔把填充图标画成描边
    // 轮廓，定格在 morph 上会让按钮外观随最近一次交互横跳
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(IconicShapeMorph), findsNothing,
        reason: '静止时必须是静态渲染，保证图标外观永远一致');
    expect(find.byType(IconImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全局动画关闭时切换是硬切，不走形变', (tester) async {
    await tester.pumpWidget(wrap(icon('circle', animate: false)));
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(icon('check_circle', animate: false)));
    await tester.pump();

    expect(find.byType(IconicShapeMorph), findsNothing,
        reason: '设置里关了动画，形变就不能再出现');
    expect(find.byType(IconImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('形变表之外的名字回退字体图标', (tester) async {
    await tester.pumpWidget(wrap(icon('sun')));
    await tester.pumpAndSettle();

    expect(find.byType(Icon), findsOneWidget,
        reason: '不在 kMorphIconPaths 里的名字要用原来的字体图标');
    expect(find.byType(IconImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('形变键只对注册过的名字生效', () {
    expect(morphIconKey('circle'), 'icon:circle');
    expect(morphIconKey('check_circle'), 'icon:check_circle');
    expect(morphIconKey('play'), 'icon:play');
    expect(morphIconKey('pause'), 'icon:pause');
    expect(morphIconKey('sun'), isNull);
    expect(morphIconKey(null), isNull);
    expect(morphIconKey('definitely-not-an-icon'), isNull);
  });
}
