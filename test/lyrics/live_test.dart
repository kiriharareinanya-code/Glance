/// 真实网络端到端验证：直接驱动 LyricsEngine 走线上接口。
///
/// 用途：自己验证「这台机器 + 当前代码」能不能真的搜到歌词，
/// 不依赖桌面程序、不依赖人工点歌。跑法：
///   flutter test test/lyrics/live_test.dart
///
/// 注意：需要能直连外网（国内直连即可；Musixmatch 直连会超时，属预期）。
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/engine.dart';
import 'package:vectra/lyrics/lyrics_log.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';

void main() {
  // 把日志接到 stdout，否则探针全被 noopLog 吞掉
  lyricsLogFn = (String m, {bool warn = false}) {
    // ignore: avoid_print
    print(warn ? '[W] $m' : '  $m');
  };

  // 《昔涟》——中文版叫《昔涟》（张韶涵），与英文版《Ripples of Past Reverie》
  // 同名同时长（186s），是最难的情况：只靠标题匹配必然选错。
  const title = 'Ripples of Past Reverie - Chinese Ver.';
  const artist = 'HOYO-MiX';
  const dur = 186671;

  test('网易云单源：能否搜到中文版《昔涟》', () async {
    final engine = LyricsEngine(
      defaultMinimumMatch: MatchType.low,
    );
    final r = await engine.fetch(
      title: title,
      artist: artist,
      durationMs: dur,
      sourcePreference: 'netease',
      preferLang: 'zh',
      stripInfoLines: false,
    );
    final data = r?.data;
    final lines = data?.lines;
    // ignore: avoid_print
    print('=== 结论: ${lines == null ? '没找到' : '找到 ${lines.length} 行'} ===');
    for (final l in (lines ?? const []).take(8)) {
      // ignore: avoid_print
      print('   ${l.startTime}ms  ${l.text}');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('四源串行：auto 全走一遍，记录每源结果', () async {
    for (final pref in ['netease', 'kugou', 'lrclib']) {
      final engine = LyricsEngine(defaultMinimumMatch: MatchType.low);
      final r = await engine.fetch(
        title: title,
        artist: artist,
        durationMs: dur,
        sourcePreference: pref,
        preferLang: 'zh',
        stripInfoLines: false,
      );
      final data = r?.data;
      final lines = data?.lines;
      final n = lines?.length ?? 0;
      // ignore: avoid_print
      print('[$pref] ${n == 0 ? '无' : '$n 行  首行: ${lines!.first.text}'}');
    }
  }, timeout: const Timeout(Duration(seconds: 180)));
}
