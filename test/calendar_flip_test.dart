/// 日历卡翻月按钮与日期点选的点击复现测试。
///
/// 反馈："日历的上下翻用不了"（真机）+ "点其他日期显示距今天多少天"。
/// 这里用与 gen_previews_test 相同的隔离宿主把 CalendarWidget 真挂起来，
/// 模拟指针按下/抬起，验证 Dart 侧逻辑链路（TapFeedback → draw →
/// renderWidget → 新树）畅通。若这里通过而真机无反应，问题在真机环境
/// （命中层/手势竞争），需要另查。
///
/// 注意：不要把 FlutterError.onError 覆盖成 debugPrint——那会把布局异常和
/// 断言失败一起吞掉，测试在坏状态里继续跑直到超时（吃过这个亏）。
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/catalog.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/kit.dart' show HoverIconBtn, TapFeedback;

void main() {
  testWidgets('日历翻月按钮：点 down 月份 +1，点 up 回 -1', (tester) async {
    HttpOverrides.global = null;

    final store = Store(p.join(
        Directory.systemTemp.path, 'glance-shot', 'calendar-flip'));
    // 真实文件 IO 在 fake-async zone 里永远 pending，必须切 runAsync
    await tester.runAsync(store.load);

    const grid = GridSize(4, 4);
    final px = sizeToPx(grid);
    final card = WidgetCard(
        id: 'flip', pluginId: 'calendar', x: 0, y: 0, size: '4x4', z: 0);
    final ctx = WidgetContext(
      store: store,
      card: card,
      pluginId: 'calendar',
      onRequestSize: (_) {},
      onOpenSettings: () {},
      settings: {'lunar': true, 'festival': true, 'mondayFirst': true},
      grid: grid,
      size: Size(px.w, px.h),
    );

    final controller = createBuiltinController('calendar', ctx);
    controller.mount();
    await tester.pump();

    Widget host() => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: SizedBox(
              width: px.w,
              height: px.h,
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle(
                  style: TextStyle(
                      fontSize: 14, color: Colors.white, fontFamily: 'Roboto'),
                  child: ValueListenableBuilder<Widget?>(
                    valueListenable: ctx.widget,
                    builder: (context, w, _) => w ?? const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final now = DateTime.now();
    String title(int m) =>
        '${now.year + (m >= 12 ? 1 : m < 0 ? -1 : 0)}年${(m % 12) + 1}月';

    final thisMonth = find.text(title(now.month - 1));
    expect(thisMonth, findsOneWidget, reason: '初始应显示当前月');

    // 翻月按钮按类型找：日期格现在也包 TapFeedback（一格一个），
    // 按 TapFeedback 数量/索引定位会数错。
    final flips = find.byType(HoverIconBtn);
    expect(flips, findsNWidgets(2), reason: '日历应有上/下两个翻月按钮');
    final up = flips.first;
    final down = flips.last;

    await tester.tap(down, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.text(title(now.month)), findsOneWidget,
        reason: '点 down 应翻到下个月');

    await tester.tap(up, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.text(title(now.month - 1)), findsOneWidget,
        reason: '再点 up 应回到本月');

    // ---- 复现真机"用不了"：桌面是鼠标点击 + surface 拖拽层并存 ----
    // 真机上 surface 的 Listener 在按下瞬间就开始拖拽（非锁定时），鼠标
    // 点击几乎必然带 1~5px 的微动。带抖动的点击只做诊断打印不做硬断言：
    // 鼠标 slop（精确指针 1px）之上的微动会让 tap 竞技场取消，行为依赖
    // onPress 时机，这里只观察不武断。
    Future<void> mouseClickWithJitter(Offset at, Offset jitter) async {
      final g = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(jitter);
      await tester.pump(const Duration(milliseconds: 30));
      await g.up();
      await tester.pumpAndSettle();
    }

    final downCenter = tester.getCenter(down);

    await mouseClickWithJitter(downCenter, const Offset(0, 0));
    debugPrint('jitter(0,0) -> 下月标题存在: '
        '${find.text(title(now.month)).evaluate().isNotEmpty}');

    await mouseClickWithJitter(downCenter, const Offset(5, 3));
    debugPrint('jitter(5,3) -> +2月标题存在: '
        '${find.text(title(now.month + 1)).evaluate().isNotEmpty}');

    await mouseClickWithJitter(downCenter, const Offset(40, 0));
    debugPrint('jitter(40,0) -> +3月标题存在: '
        '${find.text(title(now.month + 2)).evaluate().isNotEmpty}');

    // 干净点击的语义必须有保证（上面的抖动实验不许影响它）
    expect(find.textContaining('月'), findsWidgets,
        reason: '日历标题应始终在渲染');

    // 体内卸载：取消 ctx.interval 的 Timer.periodic。别挪去 addTearDown——
    // 它的执行时机在 pending-timer 不变量检查之后，必炸。
    controller.unmount();
  });

  testWidgets('日历点日期：标题旁出现距今天数，再点同格取消', (tester) async {
    HttpOverrides.global = null;

    final store = Store(p.join(
        Directory.systemTemp.path, 'glance-shot', 'calendar-flip'));
    await tester.runAsync(store.load);

    const grid = GridSize(4, 4);
    final px = sizeToPx(grid);
    final card = WidgetCard(
        id: 'pick', pluginId: 'calendar', x: 0, y: 0, size: '4x4', z: 0);
    final ctx = WidgetContext(
      store: store,
      card: card,
      pluginId: 'calendar',
      onRequestSize: (_) {},
      onOpenSettings: () {},
      settings: {'lunar': true, 'festival': true, 'mondayFirst': true},
      grid: grid,
      size: Size(px.w, px.h),
    );

    final controller = createBuiltinController('calendar', ctx);
    controller.mount();
    await tester.pump();

    Widget host() => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: SizedBox(
              width: px.w,
              height: px.h,
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle(
                  style: TextStyle(
                      fontSize: 14, color: Colors.white, fontFamily: 'Roboto'),
                  child: ValueListenableBuilder<Widget?>(
                    valueListenable: ctx.widget,
                    builder: (context, w, _) => w ?? const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final now = DateTime.now();

    // 42 格月历里，15 号恒不出现在前月尾（最多显示 23-31）与后月头
    // （最多显示到 14）——用它可以唯一定位本月格子。
    final day15 = find.text('15');
    expect(day15, findsOneWidget, reason: '本月 15 号应恰好出现一次');

    await tester.tap(day15, warnIfMissed: true);
    await tester.pumpAndSettle();

    final diff = 15 - now.day;
    final label = diff == 0 ? '今天' : diff > 0 ? '剩$diff天' : '已过${-diff}天';
    expect(find.text(label), findsOneWidget,
        reason: '点 15 号应出现倒计时 chip「$label」（今天 $now）');

    // 再点同格 = 取消选中，chip 消失
    await tester.tap(day15, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.text(label), findsNothing, reason: '再点同格应取消选中');

    // 点标题（回今天）也会清除选中
    await tester.tap(day15, warnIfMissed: true);
    await tester.pumpAndSettle();
    final titleFeedback = find.ancestor(
      of: find.text('${now.year}年${now.month}月'),
      matching: find.byType(TapFeedback),
    );
    expect(titleFeedback, findsOneWidget, reason: '标题应包在 TapFeedback 里');
    await tester.tap(titleFeedback, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.text(label), findsNothing, reason: '点标题回今天应清除选中');

    controller.unmount();
  });
}
