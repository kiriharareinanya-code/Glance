/// 未知组件时卡片上那个错误框的行为约定。
///
/// 组件内置化之后不再有"JS 运行时挂载失败"这种事，外层的自动重试机制
/// 也随之移除；剩下的唯一错误路径是配置里出现了未知组件 id（比如配置
/// 来自更新的版本）——这时要给一句人话，而不是把 id 裸露给用户。
///
/// 网络类错误由组件自己的错误视图负责（天气卡有完整的错误/重试态），
/// 不在本文件覆盖范围内。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/core/splash_gate.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/model/settings.dart';
import 'package:vectra/widgets/builtin_card_body.dart';
import 'package:vectra/store/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SplashGate.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('vectra/native'), (call) async => null);
  });

  tearDown(SplashGate.resetForTest);

  Future<void> pumpCard(WidgetTester tester, {String pluginId = 'ghost'}) async {
    final tmp = Directory.systemTemp.createTempSync('vectra-card-body');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 248,
          height: 248,
          child: BuiltinCardBody(
            // 这个 id 不在内置清单里，一定找不到
            card: WidgetCard(
                id: 'c1', pluginId: pluginId, x: 0, y: 0, size: '2x2', z: 1),
            size: const Size(248, 248),
            store: Store(tmp.path),
            state: AppState(settings: AppSettings(), cards: []),
            onRequestSize: (_) {},
            onOpenSettings: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('未知组件时，卡片上是一句人话，而不是把内部 id 裸露给用户',
      (tester) async {
    await pumpCard(tester);

    // 标题给的是"哪个组件出问题了"
    expect(find.textContaining('出错了'), findsOneWidget);
    // 错误文案不该把内部 id 打出来
    expect(find.textContaining('找不到插件'), findsNothing);
  });

  testWidgets('没有重试/详情按钮：内置组件不存在"重试能救回来"的失败路径',
      (tester) async {
    await pumpCard(tester);

    expect(find.text('重试'), findsNothing);
    expect(find.text('详情'), findsNothing);
  });

  testWidgets('错误框在最小的卡片里也放得下', (tester) async {
    // 卡片可以小到 2x2 配小网格，而长 id 会撑出一条长错误信息。
    // 溢出的部分会被窗口区域裁掉，用户就看不见发生了什么。
    final tmp = Directory.systemTemp.createTempSync('vectra-card-small');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: BuiltinCardBody(
              card: WidgetCard(
                  id: 'c1',
                  // 长 id 撑出一条长错误信息
                  pluginId: 'a-plugin-with-a-very-long-identifier-name-here',
                  x: 0,
                  y: 0,
                  size: '2x2',
                  z: 1),
              size: const Size(120, 120),
              store: Store(tmp.path),
              state: AppState(settings: AppSettings(), cards: []),
              onRequestSize: (_) {},
              onOpenSettings: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: '错误框不该溢出');
  });
}
