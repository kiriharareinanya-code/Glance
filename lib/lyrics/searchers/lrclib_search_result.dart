// Ported from Lyricify.Lyrics.Helper/Searchers/LRCLIBSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../providers/web/lrclib/response.dart' as lrclib;
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'lrclib_searcher.dart';

class LRCLIBSearchResult extends ISearchResult {
  LRCLIBSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
  );


  /// Dart DTO
  factory LRCLIBSearchResult.fromItem(dynamic item) => LRCLIBSearchResult(
        item.trackName as String,
        _splitArtists(item.artistName as String? ?? ''),
        (item.albumName as String?) ?? '',
        null,
        ((item.duration as num?)?.toInt() ?? 0) * 1000,
        (item.id as num?)?.toInt() ?? 0,
      );

  static List<String> _splitArtists(String artistName) {
    return artistName
        .split(RegExp(r', | & | feat\. | ft\. '))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  ISearcher get searcher => LRCLIBSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final int id;

  @override
  final List<String>? albumArtists;

  @override
  final int? durationMs;

  MatchType? _matchType;

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) {
    _matchType = matchType;
  }
}
