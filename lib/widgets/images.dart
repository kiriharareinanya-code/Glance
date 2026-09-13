/// 插件用的图片缓存。
///
/// 为什么要有这么一层：插件的 UI 树每次 render 都会走一遍 JSON.stringify，
/// 而一张专辑封面是十几万字节。把字节塞进树里等于每秒把它序列化十次，
/// 卡片必卡。所以约定：**插件永远只拿到一个字符串 key**，字节由宿主取、
/// 宿主解码、宿主缓存，`image` 节点按 key 查表。
///
/// 容量刻意很小：封面这类图一次只显示一张，留几张是为了切歌时不闪。
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class WidgetImages {
  WidgetImages._();

  /// 最多留几张。超了就丢最早放进来的。
  static const int _capacity = 4;

  /// 解码长边上限（px）。封面在卡片上最大也就 ~120px 逻辑像素，
  /// 高 DPI 2~3 倍取 256 绰绰有余；原图动辄 1000²+，不解码到这个尺寸
  /// 每张白占 4~8MB。
  static const int _maxDecodeEdge = 256;

  static final Map<String, ui.Image> _cache = {};
  static final List<String> _order = [];

  /// 有图片进出时通知界面重画。key 变了但 Flutter 不知道，光靠插件 render
  /// 是不够的——封面是异步解码完才进缓存的，那时这一帧早画完了。
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static bool has(String key) => _cache.containsKey(key);

  static ui.Image? get(String key) => _cache[key];

  /// 把已解码的图片放进缓存。同 key 重复放会替换并释放旧的。
  static void put(String key, ui.Image image) {
    final old = _cache[key];
    if (old != null) {
      _order.remove(key);
      old.dispose();
    }
    _cache[key] = image;
    _order.add(key);
    while (_order.length > _capacity) {
      final drop = _order.removeAt(0);
      _cache.remove(drop)?.dispose();
    }
    revision.value++;
  }

  /// 解码一段编码过的图片字节（JPEG/PNG 之类，不是裸像素）并入缓存。
  /// 解码失败返回 false，调用方据此决定是否回退到占位图。
  ///
  /// 内存：按 [_maxDecodeEdge] 降采样解码。SMTC 给的封面动辄 1000²~1400²，
  /// 原分辨率解码一张就是 4~8MB，而显示尺寸只有几十 px——白占。
  static Future<bool> decodeAndPut(String key, Uint8List bytes) async {
    if (bytes.isEmpty) return false;
    try {
      // 等比降采样到"长边 ≤ 256"：先拿原始尺寸再算目标，小图原样解码
      // （TargetImageSize 不给值 = 保持原尺寸，绝不放大）。原图动辄
      // 1000²+，不解码到这个尺寸每张白占 4~8MB，而显示尺寸只有几十 px。
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (int w, int h) {
          if (w <= _maxDecodeEdge && h <= _maxDecodeEdge) {
            return const ui.TargetImageSize();
          }
          final k = _maxDecodeEdge / (w > h ? w : h);
          return ui.TargetImageSize(
              width: (w * k).round(), height: (h * k).round());
        },
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      put(key, frame.image);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 仅供测试：清空缓存
  @visibleForTesting
  static void clear() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _order.clear();
    revision.value++;
  }
}
