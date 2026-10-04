// Ported from Lyricify.Lyrics.Helper/Searchers/LRCLIBSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// 改写说明：C# 的 `SearchForResults(string searchString)` 翻成同名方法；
// 关键词按空格对半分成歌名/歌手（parts.Length/2），失败再整串重试。
library;

import '../models/track_metadata.dart';
import '../providers/web/providers.dart';
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'lrclib_search_result.dart';
import 'searchers.dart';

class LRCLIBSearcher implements ISearcher {

  @override
  String get name => 'LRCLIB';

  @override
  String get displayName => 'LRCLIB';

  @override
  Searchers get searcherType => Searchers.lrclib;

  @override
  Future<ISearchResult?> searchForResult(TrackMetadata track,
      [MatchType? minimumMatch]) async {
    final results = await searchForResultsByTrack(track);
    if (results.isEmpty) return null;
    if (minimumMatch != null &&
        (results[0].matchType?.index ?? -1) < minimumMatch.index) {
      return null;
    }
    return results[0];
  }

  @override
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]) async {
    final byName = await _search(track.title ?? '', track.artist ?? '');
    if (byName.isNotEmpty) return _rank(track, byName);
    final byKeyword = await _search('${track.title ?? ''} ${track.artist ?? ''}', null);
    if (byKeyword.isNotEmpty) return _rank(track, byKeyword);
    return <ISearchResult>[];
  }

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    // 上游：按空格对半分，前半歌名后半歌手；两段以上才拆
    final parts = searchString
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    var trackName = searchString;
    String? artistName;
    if (parts.length >= 2) {
      final mid = parts.length ~/ 2;
      trackName = parts.take(mid).join(' ');
      artistName = parts.skip(mid).join(' ');
    }
    var results = await _search(trackName, artistName);
    if (results.isEmpty) {
      results = await _search(searchString, null);
    }
    if (results.isEmpty) return null;
    return results;
  }

  Future<List<ISearchResult>> _search(String track, String? artist) async {
    final items = await Providers.lrclibApi.search(track, artist);
    if (items == null || items.isEmpty) return <ISearchResult>[];
    return [for (final it in items) LRCLIBSearchResult.fromItem(it)];
  }

  List<ISearchResult> _rank(TrackMetadata track, List<ISearchResult> results) {
    for (final r in results) {
      r.setMatchType(CompareHelper.compareTrack(track, r));
    }
    results.sort((a, b) =>
        (b.matchType?.index ?? -1).compareTo(a.matchType?.index ?? -1));
    return results;
  }
}
