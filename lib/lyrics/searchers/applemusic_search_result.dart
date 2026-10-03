// Ported from Lyricify.Lyrics.Helper/Searchers/AppleMusicSearchResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//
library;

import '../providers/web/applemusic/response.dart' as am;
import 'applemusic_searcher.dart';
import 'helpers/compare_helper.dart';
import 'isearcher.dart';

class AppleMusicSearchResult extends ISearchResult {
  AppleMusicSearchResult(
    this.title,
    this.artists,
    this.album,
    this.albumArtists,
    this.durationMs,
    this.id,
  );

  factory AppleMusicSearchResult.fromSongData(am.SongData song) =>
      AppleMusicSearchResult(
        song.attributes?.name ?? '',
        _isNullOrWhiteSpace(song.attributes?.artistName)
            ? <String>[]
            : splitArtists(song.attributes!.artistName),
        song.attributes?.albumName ?? '',
        null,
        song.attributes?.durationInMillis ?? 0,
        song.id,
      );

  static List<String> splitArtists(String artistName) {
    final parts = artistName
        .split(', ')
        .where((p) => p.isNotEmpty)
        .map((p) => p.trim())
        .toList();

    if (parts.isEmpty) return <String>[];

    final last = parts.last;
    final ampIndex = last.lastIndexOf(' & ');

    if (ampIndex >= 0) {
      parts.removeAt(parts.length - 1);

      final left = last.substring(0, ampIndex).trim();
      final right = last.substring(ampIndex + 3).trim();

      if (left.isNotEmpty) parts.add(left);
      if (right.isNotEmpty) parts.add(right);
    }

    return parts;
  }

  /// C# `string.IsNullOrWhiteSpace(string?)`。
  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;

  @override
  ISearcher get searcher => AppleMusicSearcher();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  final String id;

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
