/// 切歌时"旧歌词不清掉"这条规则的判定测试。
///
/// 用户实拍截图揪出来的 bug：切到一首**没有歌词**的曲子（纯音乐）后，
/// 屏幕上一直挂着**上一首歌**的词，歌词和声音完全对不上。
///
/// 根因不是"忘了清"，而是当初为了解决另一个问题**故意不清**：SMTC 标题
/// 会在「XXX - Chinese Ver.」和「XXX (Honkai Star Rail)」之间跳变，同一次
/// 切歌会以两个不同的 key 各触发一次搜索，第二次失败如果把歌词清掉，
/// 用户看到的就是歌词凭空消失。
///
/// 所以判据不能是"这次搜索有没有成功"，而必须是"新 key 和正在显示的这份
/// 歌词是不是同一首歌"——由 [_isSameSong] 按**时长**判定（标题正是会跳变的
/// 那部分，拿它判会把两种情况混成一团）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/spec.dart';

/// 这组用例只测 [_isSameSong] 的**判据**（经 debugWouldKeepOnMiss 转出），
/// 不渲染、不联网，所以宿主给个最简的隔离 ctx 就够。
WidgetContext _ctx() => WidgetContext(
      store: Store('.'),
      card: WidgetCard(
          id: 't', pluginId: 'lyrics', x: 0, y: 0,
          size: const GridSize(4, 4).toString(), z: 0),
      pluginId: 'lyrics',
      onRequestSize: (_) {},
      onOpenSettings: () {},
      settings: kBuiltinSpecs.firstWhere((s) => s.id == 'lyrics')
          .defaultSettings(),
      grid: const GridSize(4, 4),
      size: const Size(420, 460),
    );

void main() {
  // key 格式：标题|歌手|时长秒
  group('同一首歌的标题跳变：保留已显示的歌词', () {
    test('标题变体（Chinese Ver. → 副标题版），时长相同 → 保留', () {
      final c = LyricsWidget(_ctx())
        ..debugSetLyricKey('昔涟 - Chinese Ver.|张韶涵, HOYO-MiX|187');
      expect(c.debugWouldKeepOnMiss('昔涟 (Honkai Star Rail)|张韶涵|187'),
          isTrue,
          reason: '同一首歌的标题跳变，第二次搜索失败不该把歌词清掉');
    });

    test('歌手字段轻微差异（feat. 标注、多人合唱分隔符），时长相同 → 保留',
        () {
      final c = LyricsWidget(_ctx())
        ..debugSetLyricKey('CYNICAL.CYNICAL|Toiki|180');
      expect(c.debugWouldKeepOnMiss('CYNICAL.CYNICAL (feat. Such)|Toiki|180'),
          isTrue);
    });

    test('时长差 1 秒（采样误差）仍算同一首', () {
      final c = LyricsWidget(_ctx())..debugSetLyricKey('A|X|200');
      expect(c.debugWouldKeepOnMiss('A|X|201'), isTrue,
          reason: 'SMTC 上报的时长有舍入误差，差 1 秒不该判成不同歌');
    });
  });

  group('真的换了另一首没歌词的曲子：必须清掉', () {
    test('时长不同 → 清掉（用户实拍截图的那个 bug）', () {
      final c = LyricsWidget(_ctx())
        ..debugSetLyricKey('留存|王菲|252');
      expect(c.debugWouldKeepOnMiss('Pure Music|Unknown|180'), isFalse,
          reason: '换了另一首却没歌词，屏幕上不能留着上一首的词');
    });

    test('时长差 2 秒以上 → 清掉', () {
      final c = LyricsWidget(_ctx())..debugSetLyricKey('A|X|200');
      expect(c.debugWouldKeepOnMiss('B|Y|202'), isFalse);
    });

    test('时长缺失（0）→ 清掉：宁可显示"没歌词"也不显示上一首', () {
      final c = LyricsWidget(_ctx())..debugSetLyricKey('A|X|200');
      expect(c.debugWouldKeepOnMiss('A|X|0'), isFalse);
    });

    test('新 key 格式残缺（没有时长段）→ 清掉', () {
      final c = LyricsWidget(_ctx())..debugSetLyricKey('A|X|200');
      expect(c.debugWouldKeepOnMiss('A'), isFalse);
    });

    test('显示中的歌词来自空 key（还没拿到任何歌词）→ 清掉', () {
      final c = LyricsWidget(_ctx());
      expect(c.debugLyricKey, isEmpty);
      expect(c.debugWouldKeepOnMiss('A|X|200'), isFalse);
    });
  });

  group('时长相同的不同歌（低概率碰撞）：按保留处理', () {
    test('明确记录这个取舍：宁可留着，也不该把对的清成错的', () {
      final c = LyricsWidget(_ctx())..debugSetLyricKey('歌一|甲|210');
      // 恰好同秒长的另一首：极罕见（时长的毫秒部分通常不同）
      expect(c.debugWouldKeepOnMiss('歌二|乙|210'), isTrue);
    });
  });
}
