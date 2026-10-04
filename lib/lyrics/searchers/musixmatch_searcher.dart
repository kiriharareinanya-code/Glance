// Ported from Lyricify.Lyrics.Helper/Searchers/MusixmatchSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// 改写说明：C# 的类方法 SearchForResults 翻成 Dart 顶层方法；
// 对象初始化器 `new MusixmatchSearchResult(t) { MatchType = ... }`
// 翻成先建对象再 setMatchType。
library;

import '../models/track_metadata.dart';
import '../providers/web/musixmatch/api.dart' as mx;
import '../providers/web/providers.dart';
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'musixmatch_search_result.dart';
import 'searchers.dart';

class MusixmatchSearcher implements ISearcher {
  final mx.Api api;

  MusixmatchSearcher() : this.withApi(Providers.musixmatchApi);

  MusixmatchSearcher.withApi(this.api);

  @override
  String get name => 'Musixmatch';

  @override
  String get displayName => 'Musixmatch';

  @override
  Searchers get searcherType => Searchers.musixmatch;

  @override
  Future<ISearchResult?> searchForResult(TrackMetadata track,
      [MatchType? minimumMatch]) async {
    final result = await searchForResultsByTrack(track);
    if (result.isEmpty) return null;
    if (minimumMatch != null &&
        (result[0].matchType?.index ?? -1) < minimumMatch.index) {
      return null;
    }
    return result[0];
  }

  @override
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]) async {
    return await searchForResultsWithTrackArtist(
            track.title ?? '', track.artist ?? '', track.durationMs) ??
        <ISearchResult>[];
  }

  /// 上游 SearchForResults(string track, string artist, int? duration = null)
  Future<List<ISearchResult>?> searchForResultsWithTrackArtist(
      String track, String artist, [int? durationMs]) async {
    final search = <ISearchResult>[];
    try {
      final result = await api.getTrack(track, artist,
          durationMs == null ? null : durationMs ~/ 1000);
      final t = result?.message?.body?.track;
      if (t == null) return null;
      final r = MusixmatchSearchResult.fromTrack(t);
      // 上游用 Header.Confidence 换算档位：1000=Perfect，>=950=VeryHigh…
      final confidence = result!.message?.header?.confidence ?? 0;
      r.setMatchType(matchTypeOfConfidence(confidence));
      search.add(r);
    } catch (_) {
      return null;
    }
    return search;
  }

  /// 上游的 Confidence → MatchType switch
  static MatchType matchTypeOfConfidence(int confidence) {
    if (confidence == 1000) return MatchType.perfect;
    if (confidence >= 950) return MatchType.veryHigh;
    if (confidence >= 900) return MatchType.high;
    if (confidence >= 750) return MatchType.prettyHigh;
    if (confidence >= 600) return MatchType.medium;
    if (confidence >= 400) return MatchType.low;
    if (confidence >= 200) return MatchType.veryLow;
    return MatchType.noMatch;
  }

  /// 上游 SearchForResultsAsync(keyword, track, artist, durationMs)
  Future<List<ISearchResult>> searchForResultsAsync(
      String? keyword, String? track, String? artist,
      int? durationMs) async {
    final tracks = await api.searchTracksAsync(keyword, track, artist,
        durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : null);
    final results = <ISearchResult>[
      for (final t in tracks) MusixmatchSearchResult.fromTrack(t),
    ];
    if (track == null || track.isEmpty) return results;
    final metadata = BasicTrackMetadata()
      ..title = track
      ..artist = artist
      ..durationMs = durationMs;
    for (final r in results) {
      r.setMatchType(CompareHelper.compareTrack(metadata, r));
    }
    results.sort((a, b) =>
        (b.matchType?.index ?? -1).compareTo(a.matchType?.index ?? -1));
    return results;
  }

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) {
    return searchForResultsAsync(searchString, null, null, null);
  }
}
