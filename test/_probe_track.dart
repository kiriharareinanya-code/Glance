/// 一次性探针（用完即删）：列出某首歌在各源的**候选 + 打分**。
///
/// 为什么需要它：`[探针]` 日志已按用户要求清掉了（那是每首歌刷 30 行的噪音），
/// 但排查"这首歌为什么搜不到歌词"时，候选列表和每条的 matchType 正是唯一线索。
/// 这里直接驱动 SearchersHelper 走线上接口，按源打出来。
///
/// 跑法：flutter test test/_probe_track.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';
import 'package:vectra/lyrics/searchers/isearcher.dart';
import 'package:vectra/lyrics/searchers/searchers.dart';
import 'package:vectra/lyrics/searchers/searchers_helper.dart';

Future<void> _probe(String title, String artist, int durMs) async {
  // ignore: avoid_print
  print('\n══════ 探针: 「$title」/「$artist」/${durMs}ms ══════');

  final track = BasicTrackMetadata()
    ..title = title
    ..artist = artist.isEmpty ? null : artist
    ..durationMs = durMs;

  for (final s in Searchers.values) {
    final ISearcher searcher = SearchersHelper.getSearcher(s);
    List<dynamic> results;
    try {
      results = await searcher.searchForResultsByTrack(track, true) as List<dynamic>;
    } catch (e) {
      // ignore: avoid_print
      print('  ${searcher.displayName}: 异常 $e');
      continue;
    }
    if (results.isEmpty) {
      // ignore: avoid_print
      print('  ${searcher.displayName}: 无候选');
      continue;
    }
    // 按匹配度排序，只打前 8 条 —— 想知道的是"最好的那几条长什么样"
    results.sort((a, b) =>
        ((b.matchType?.value ?? -999)).compareTo(a.matchType?.value ?? -999));
    // ignore: avoid_print
    print('  ${searcher.displayName}: ${results.length} 个候选');
    for (final r in results.take(8)) {
      // ignore: avoid_print
      print('      [${r.matchType} = ${r.matchType?.value}] '
          '「${r.title}」/「${r.artist}」/${r.durationMs}ms');
    }
  }
}

void main() {
  test('探针：Golden Number / Iyowa', () async {
    await _probe('Golden Number', 'Iyowa', 187924);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('探针：Golden Number（不带歌手）', () async {
    await _probe('Golden Number', '', 187924);
  }, timeout: const Timeout(Duration(seconds: 120)));
}
