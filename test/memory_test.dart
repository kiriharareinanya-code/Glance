// 内存优化的回归测试。
//
// 对应本次内存审计的修复点：封面降采样、卸载插件的内存清理。
// 每条都盯着"优化不能改变行为"：图能显示、数据能释放。
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart' show Icons;
import 'package:vectra/plugin/images.dart';
import 'package:vectra/plugin/morph_icons.dart' show kMorphIconPaths;
import 'package:vectra/plugin/node.dart' show iconDataFor;
import 'package:vectra/store/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('封面解码降采样', () {
    setUp(() => PluginImages.clear());
    tearDown(() => PluginImages.clear());

    /// 造一张 w×h 的纯色 PNG（走真实的 PNG 编码 → 解码链路）
    Future<Uint8List> pngBytes(int w, int h) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..color = const ui.Color(0xFF29B6F6));
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return data!.buffer.asUint8List();
    }

    test('超大原图解码后长边不超过 256（原分辨率一张白占 4~8MB）', () async {
      final bytes = await pngBytes(1200, 800);
      expect(await PluginImages.decodeAndPut('cover', bytes), isTrue);

      final img = PluginImages.get('cover')!;
      expect(img.width, lessThanOrEqualTo(256),
          reason: '解码必须降采样到显示尺寸量级，不能按原图 1200px 全量驻留');
      expect(img.height, lessThanOrEqualTo(256));
      // 宽高比保持（1200x800 = 3:2）
      expect(img.width / img.height, closeTo(1.5, 0.05));
    });

    test('小于上限的图不放大', () async {
      final bytes = await pngBytes(64, 64);
      expect(await PluginImages.decodeAndPut('small', bytes), isTrue);
      final img = PluginImages.get('small')!;
      expect(img.width, lessThanOrEqualTo(64));
      expect(img.height, lessThanOrEqualTo(64));
    });

    test('LRU 淘汰依旧生效（容量 4）', () async {
      for (var i = 0; i < 6; i++) {
        final bytes = await pngBytes(64, 64);
        expect(await PluginImages.decodeAndPut('k$i', bytes), isTrue);
      }
      expect(PluginImages.get('k0'), isNull, reason: '最早的应该被挤出去');
      expect(PluginImages.get('k5'), isNotNull);
    });
  });

  test('形变表的名字都有字体兜底（图标双表不漂移）', () {
    // play/pause 这些名字同时存在于字体表（iconDataFor）和形变表
    // （kMorphIconPaths）——字体表那份是形变不可用时的兜底。
    // 哪天有人从字体表删掉一个名字而忘了形变表，兜底就会渲染成方块。
    for (final name in kMorphIconPaths.keys) {
      expect(iconDataFor(name), isNot(Icons.square_outlined),
          reason: '$name 在形变表里但字体表没有兜底条目');
    }
  });

  group('卸载插件的内存清理', () {
    test('uninstall 后内存里的 pluginData 同步清掉', () async {
      final dir = Directory.systemTemp.createTempSync('vectra-mem');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = Store(dir.path);
      final state = await store.load();

      state.pluginData['weather'] = {'city': '北京'};
      state.pluginData['todo'] = {'items': <Object?>[]};

      await store.uninstall('weather');

      expect(state.pluginData.containsKey('weather'), isFalse,
          reason: '卸载后内存总表必须同步清掉，否则这份 kv 会持到进程退出');
      expect(state.pluginData.containsKey('todo'), isTrue,
          reason: '卸载别的插件不能殃及无辜');
    });
  });
}
