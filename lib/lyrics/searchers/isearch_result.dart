// Ported from Lyricify.Lyrics.Helper/Searchers/ISearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
// **interface internal member**（`internal void SetMatchType(CompareHelper.MatchType?)`），
//
// `string[]? AlbumArtists` → `List<String>? albumArtists`；
part of 'isearcher.dart';

abstract class ISearchResult {
  ISearcher get searcher;

  String get title;

  List<String> get artists;

  String get artist => artists.join(', ');

  String get album;

  List<String>? get albumArtists;

  /// 专辑艺人名
  String get albumArtist => (albumArtists ?? <String>[]).join(', ');

  int? get durationMs;

  MatchType? get matchType;

  /// 设置匹配程度
  void setMatchType(MatchType? matchType);
}
