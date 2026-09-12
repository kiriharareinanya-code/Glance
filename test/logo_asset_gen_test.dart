// Logo 资源生成器（手动跑，不进 CI 断言）：
//
//   flutter test test/logo_asset_gen_test.dart
//
// 项目里没有 SVG 光栅化工具链（也没有 flutter_svg 依赖），而关于页渲染的是
// PNG，所以用 Flutter 自己的 Canvas 按 assets/branding/glance-mark.svg 的数
// 字重画一遍并导出 PNG——两个文件是同一份几何，改一边要同步另一边。
//
// 配色（低饱和、放松）：夜蓝底 #16263C、山脊 #3A5470 / #2A4058 / #1E3145、
// 月光暖米白 #F1E8D6。山脊只靠明度分层，不加第二种色相——这是"高级感"
// 的来源：不靠饱和度与对比度，靠层次。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 三层山脊：平滑肩线的山峰（不用尖角折线，尖角会让画面变紧张）
Path _ridges() => Path()
  ..moveTo(2, 96)
  ..lineTo(20, 74)
  ..quadraticBezierTo(26, 67, 32, 74)
  ..lineTo(48, 92)
  ..lineTo(68, 70)
  ..quadraticBezierTo(74, 63, 80, 70)
  ..lineTo(98, 90)
  ..lineTo(126, 72)
  ..lineTo(126, 126)
  ..lineTo(2, 126)
  ..close();

Path _ridgesMid() => Path()
  ..moveTo(2, 108)
  ..lineTo(26, 86)
  ..quadraticBezierTo(32, 79, 38, 86)
  ..lineTo(60, 106)
  ..lineTo(84, 82)
  ..quadraticBezierTo(90, 75, 96, 82)
  ..lineTo(126, 100)
  ..lineTo(126, 126)
  ..lineTo(2, 126)
  ..close();

Path _ridgesNear() => Path()
  ..moveTo(2, 118)
  ..lineTo(34, 100)
  ..quadraticBezierTo(40, 96, 46, 100)
  ..lineTo(74, 118)
  ..lineTo(104, 100)
  ..quadraticBezierTo(110, 96, 116, 100)
  ..lineTo(126, 108)
  ..lineTo(126, 126)
  ..lineTo(2, 126)
  ..close();

/// 按 SVG 的 128 坐标系绘制标记；[scale] 决定输出像素。
/// [light] 为 true 时用浅色版配色（晨雾）。
Future<Uint8List> _renderMark(double scale,
    {bool light = false, bool simple = false}) async {
  const s = 128.0;
  final px = s * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, px, px));
  canvas.scale(scale);

  final tile = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 2, 124, 124), const Radius.circular(30));
  canvas.drawRRect(
      tile,
      Paint()
        ..color = light ? const Color(0xFFEDF1F5) : const Color(0xFF16263C));

  // 月亮、星星、山脊都要被圆角卡片裁掉多余部分
  canvas.save();
  canvas.clipRRect(tile);

  canvas.drawCircle(const Offset(84, 44), 26,
      Paint()..color = (light ? const Color(0xFFC9A96A) : const Color(0xFFF1E8D6))
          .withValues(alpha: light ? 0.18 : 0.12));
  canvas.drawCircle(const Offset(84, 44), 19,
      Paint()..color = light ? const Color(0xFFF0DDB4) : const Color(0xFFF1E8D6));

  if (!simple) {
    final star = light ? const Color(0xFF9AB0C2) : const Color(0xFFDDE5EE);
    canvas.drawCircle(const Offset(26, 34), 1.6,
        Paint()..color = star.withValues(alpha: light ? 0.7 : 0.55));
    canvas.drawCircle(const Offset(46, 24), 1.2,
        Paint()..color = star.withValues(alpha: light ? 0.5 : 0.4));

    canvas.drawPath(
        _ridges(),
        Paint()
          ..color = light ? const Color(0xFFC3D0DC) : const Color(0xFF3A5470));
  }
  canvas.drawPath(
      _ridgesMid(),
      Paint()
        ..color = light ? const Color(0xFFA7BACB) : const Color(0xFF2A4058));
  canvas.drawPath(
      _ridgesNear(),
      Paint()
        ..color = light ? const Color(0xFF86A2B8) : const Color(0xFF1E3145));

  canvas.restore();

  final img = await recorder.endRecording().toImage(px.round(), px.round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  // 图标要的尺寸档：Windows 会按 DPI/场景自己挑（任务栏 32、托盘 16、
  // 资源管理器大图标 256）。16px 是下限，必须还能看出"月亮+山"。
  const icoSizes = [16, 24, 32, 48, 64, 128, 256];

  testWidgets('生成 assets/logo.png（来源：assets/branding/glance-mark.svg）',
      (tester) async {
    await tester.runAsync(() async {
      await File('assets/logo.png').writeAsBytes(await _renderMark(6));
      await File('assets/branding/glance-mark-128.png')
          .writeAsBytes(await _renderMark(1));
      await File('assets/branding/glance-mark-light-128.png')
          .writeAsBytes(await _renderMark(1, light: true));

      // ICO 用的各档 PNG 帧，交给 tool/make_icons.py 装进 ICO 容器
      final iconsDir = Directory('assets/branding/ico-frames');
      if (!iconsDir.existsSync()) iconsDir.createSync(recursive: true);
      for (final size in icoSizes) {
        // ≤24px 走简化版：去掉星星和最远那层山脊，否则缩到 16px 糊成一团
        final bytes = await _renderMark(size / 128, simple: size <= 24);
        await File('${iconsDir.path}/mark-$size.png').writeAsBytes(bytes);
      }

      // ignore: avoid_print
      print('已生成 assets/logo.png（768px）、两版 128px、'
          'assets/branding/ico-frames/mark-{${icoSizes.join(",")}}.png');
    });
  });
}
