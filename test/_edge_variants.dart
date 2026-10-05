/// 一次性对比工具（用完即删）：把**几种边框画法**并排渲染成 PNG。
///
/// 为什么要这么干：边框是纯视觉判断，靠"改参数 → 编译 → 部署 → 截图"
/// 一轮要一分半，试错代价太高。这里直接在同一张图里画四种方案，
/// 背景用深色 + 卡片透出的蓝（贴近用户的真实环境），一次就能定型。
///
/// 跑法：flutter test test/_edge_variants.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 方案的绘制函数签名。
typedef Painter = void Function(Canvas canvas, Size size, double radius);

/// 用户卡片透出的底色（深蓝，来自壁纸）。
const Color _cardBase = Color(0xFF1B3A5E);

void main() {
  test('渲染四种边框方案对比图', () async {
    // 每格 320x180，2x2 排列
    const cellW = 320.0;
    const cellH = 180.0;
    const radius = 18.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 整张图铺深色（模拟桌面）
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, cellW * 2, cellH * 2),
      Paint()..color = const Color(0xFF141414),
    );

    final variants = <String, Painter>{
      'A 单层(现在)': _single,
      'B 主边+3层淡晕': _softStack,
      'C 粗边+微模糊': _blurredEdge,
      'D 亮边+内侧暗槽': _groove,
    };

    var i = 0;
    for (final entry in variants.entries) {
      final ox = (i % 2) * cellW;
      final oy = (i ~/ 2) * cellH;
      canvas.save();
      canvas.translate(ox + 24, oy + 24);
      const r = Rect.fromLTWH(0, 0, cellW - 48, cellH - 48);
      // 卡片本体（半透明蓝）
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(radius)),
        Paint()..color = _cardBase,
      );
      entry.value(canvas, r.size, radius);
      canvas.restore();
      i++;
    }

    final img = await recorder.endRecording().toImage(
          (cellW * 2).toInt(),
          (cellH * 2).toInt(),
        );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('test/_edge_variants.png');
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('已输出 ${out.path}');

    // 图例写进测试名里，方便对照
    // ignore: avoid_print
    print('左上 A / 右上 B / 左下 C / 右下 D');
  });
}

const double _a = 0.122; // 与 CardView._edge 的基准一致

/// A：现在线上跑的——一圈均匀细边。
void _single(Canvas canvas, Size size, double radius) {
  _ring(canvas, size, radius, 0.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 1.65));
}

/// B：主边 + 内侧三条极淡的晕环（全部落在 4px 内）。
/// 想用"累积的极淡"代替"一条明显的线"来产生层次。
void _softStack(Canvas canvas, Size size, double radius) {
  _ring(canvas, size, radius, 0.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 1.5));
  _ring(canvas, size, radius, 1.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 0.45));
  _ring(canvas, size, radius, 2.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 0.28));
  _ring(canvas, size, radius, 3.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 0.18));
}

/// C：粗边 + 小半径模糊。边缘柔和，靠"虚实"而不是"线条数"做层次。
void _blurredEdge(Canvas canvas, Size size, double radius) {
  final r = RRect.fromRectAndRadius(
    (Offset.zero & size).deflate(1),
    Radius.circular(radius),
  );
  canvas.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
      ..color = const Color(0xFFFFFFFF).withValues(alpha: _a * 1.9),
  );
}

/// D：亮边 + 内侧一圈暗槽（用暗而不是亮来做"厚度"）。
void _groove(Canvas canvas, Size size, double radius) {
  _ring(canvas, size, radius, 0.5,
      const Color(0xFFFFFFFF).withValues(alpha: _a * 1.65));
  _ring(canvas, size, radius, 1.5,
      const Color(0xFF000000).withValues(alpha: _a * 1.5));
  _ring(canvas, size, radius, 2.5,
      const Color(0x00000000));
}

void _ring(Canvas canvas, Size size, double radius, double inset, Color c) {
  final r = (radius - inset).clamp(0.0, double.infinity);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(inset),
      Radius.circular(r),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c,
  );
}
