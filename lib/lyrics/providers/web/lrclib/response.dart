// Ported from Lyricify.Lyrics.Helper/Providers/Web/LRCLIB/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';

class SearchResultItem {
  SearchResultItem({
    required this.id,
    required this.name,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    required this.plainLyrics,
    required this.syncedLyrics,
  });

  /// `[JsonProperty("id")]`
  final int id;

  /// `[JsonProperty("name")]`
  final String name;

  /// `[JsonProperty("trackName")]`
  final String trackName;

  /// `[JsonProperty("artistName")]`
  final String artistName;

  /// `[JsonProperty("albumName")]`
  final String albumName;

  /// `[JsonProperty("duration")]`
  final double duration;

  /// `[JsonProperty("instrumental")]`
  final bool instrumental;

  /// `[JsonProperty("plainLyrics")]`
  final String? plainLyrics;

  /// `[JsonProperty("syncedLyrics")]`
  final String? syncedLyrics;

  factory SearchResultItem.fromJson(Map<String, dynamic> j) => SearchResultItem(
        id: asInt(j['id']),
        name: asStr(j['name']),
        trackName: asStr(j['trackName']),
        artistName: asStr(j['artistName']),
        albumName: asStr(j['albumName']),
        duration: asDouble(j['duration']),
        instrumental: asBool(j['instrumental']),
        plainLyrics: j['plainLyrics'] == null ? null : asStr(j['plainLyrics']),
        syncedLyrics: j['syncedLyrics'] == null ? null : asStr(j['syncedLyrics']),
      );
}

class GetLyricResult {
  GetLyricResult({
    required this.id,
    required this.name,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.duration,
    required this.instrumental,
    required this.plainLyrics,
    required this.syncedLyrics,
  });

  /// `[JsonProperty("id")]`
  final int id;

  /// `[JsonProperty("name")]`
  final String name;

  /// `[JsonProperty("trackName")]`
  final String trackName;

  /// `[JsonProperty("artistName")]`
  final String artistName;

  /// `[JsonProperty("albumName")]`
  final String albumName;

  /// `[JsonProperty("duration")]`
  final double duration;

  /// `[JsonProperty("instrumental")]`
  final bool instrumental;

  /// `[JsonProperty("plainLyrics")]`
  final String? plainLyrics;

  /// `[JsonProperty("syncedLyrics")]`
  final String? syncedLyrics;

  factory GetLyricResult.fromJson(Map<String, dynamic> j) => GetLyricResult(
        id: asInt(j['id']),
        name: asStr(j['name']),
        trackName: asStr(j['trackName']),
        artistName: asStr(j['artistName']),
        albumName: asStr(j['albumName']),
        duration: asDouble(j['duration']),
        instrumental: asBool(j['instrumental']),
        plainLyrics: j['plainLyrics'] == null ? null : asStr(j['plainLyrics']),
        syncedLyrics: j['syncedLyrics'] == null ? null : asStr(j['syncedLyrics']),
      );
}
