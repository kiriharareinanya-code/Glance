// Ported from Lyricify.Lyrics.Helper/Providers/Web/AppleMusic/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';

// ===== /v1/me/storefront =====
class StorefrontResponse {
  StorefrontResponse({required this.data});

  factory StorefrontResponse.fromJson(Map<String, dynamic> j) =>
      StorefrontResponse(
        data: j['data'] is List
            ? [for (final e in asArr(j['data'])) StorefrontData.fromJson(asObj(e))]
            : null,
      );

  List<StorefrontData>? data;
}

class StorefrontData {
  StorefrontData({required this.id, required this.attributes});

  factory StorefrontData.fromJson(Map<String, dynamic> j) => StorefrontData(
        id: asStr(j['id']),
        attributes: j['attributes'] == null
            ? null
            : StorefrontAttributes.fromJson(asObj(j['attributes'])),
      );

  String id;

  StorefrontAttributes? attributes;
}

class StorefrontAttributes {
  StorefrontAttributes({required this.defaultLanguageTag});

  factory StorefrontAttributes.fromJson(Map<String, dynamic> j) =>
      StorefrontAttributes(defaultLanguageTag: asStr(j['defaultLanguageTag']));

  String defaultLanguageTag;
}

// ===== /v1/catalog/{storefront}/search =====
class SearchResponse {
  SearchResponse({required this.results});

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
        results: j['results'] == null
            ? null
            : SearchResults.fromJson(asObj(j['results'])),
      );

  SearchResults? results;
}

class SearchResults {
  SearchResults({required this.songs});

  factory SearchResults.fromJson(Map<String, dynamic> j) => SearchResults(
        songs:
            j['songs'] == null ? null : SongsContainer.fromJson(asObj(j['songs'])),
      );

  SongsContainer? songs;
}

class SongsContainer {
  SongsContainer({required this.data});

  factory SongsContainer.fromJson(Map<String, dynamic> j) => SongsContainer(
        data: j['data'] is List
            ? [for (final e in asArr(j['data'])) SongData.fromJson(asObj(e))]
            : null,
      );

  List<SongData>? data;
}

class SongData {
  SongData({required this.id, required this.attributes});

  factory SongData.fromJson(Map<String, dynamic> j) => SongData(
        id: asStr(j['id']),
        attributes: j['attributes'] == null
            ? null
            : SongAttributes.fromJson(asObj(j['attributes'])),
      );

  String id;

  SongAttributes? attributes;
}

class SongAttributes {
  SongAttributes({required this.name, required this.artistName, required this.albumName, required this.durationInMillis});

  factory SongAttributes.fromJson(Map<String, dynamic> j) => SongAttributes(
        name: asStr(j['name']),
        artistName: asStr(j['artistName']),
        albumName: asStr(j['albumName']),
        durationInMillis: asInt(j['durationInMillis']),
      );

  String name;

  String artistName;

  String albumName;

  int durationInMillis;
}

class LyricResponse {
  LyricResponse({required this.data});

  factory LyricResponse.fromJson(Map<String, dynamic> j) => LyricResponse(
        data: j['data'] is List
            ? [for (final e in asArr(j['data'])) LyricSongData.fromJson(asObj(e))]
            : null,
      );

  List<LyricSongData>? data;

  String? ttml;

  void normalizeTtml() {
    ttml = null;

    final data = this.data;
    if (data == null || data.isEmpty) return;

    final song = data[0];
    final rel = song.relationships;
    if (rel == null) return;

    final syll = rel.syllableLyrics;
    final syllData = syll?.data;
    if (syllData == null || syllData.isEmpty) return;

    final attr = syllData[0].attributes;
    if (attr == null) return;

    var ttmlValue = attr.ttmlLocalizations;

    if (_isNullOrWhiteSpace(ttmlValue)) {
      ttmlValue = attr.ttml;
    }

    if (!_isNullOrWhiteSpace(ttmlValue) &&
        ttmlValue.contains('begin=') &&
        ttmlValue.contains('end=')) {
      ttml = ttmlValue;
    }
  }

  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;
}

class LyricSongData {
  LyricSongData({required this.relationships});

  factory LyricSongData.fromJson(Map<String, dynamic> j) => LyricSongData(
        relationships: j['relationships'] == null
            ? null
            : LyricRelationships.fromJson(asObj(j['relationships'])),
      );

  LyricRelationships? relationships;
}

class LyricRelationships {
  LyricRelationships({required this.syllableLyrics, required this.lyrics});

  factory LyricRelationships.fromJson(Map<String, dynamic> j) =>
      LyricRelationships(
        syllableLyrics: j['syllable-lyrics'] == null
            ? null
            : LyricContainer.fromJson(asObj(j['syllable-lyrics'])),
        lyrics: j['lyrics'] == null
            ? null
            : LyricContainer.fromJson(asObj(j['lyrics'])),
      );

  LyricContainer? syllableLyrics;

  LyricContainer? lyrics;
}

class LyricContainer {
  LyricContainer({required this.data});

  factory LyricContainer.fromJson(Map<String, dynamic> j) => LyricContainer(
        data: j['data'] is List
            ? [for (final e in asArr(j['data'])) LyricData.fromJson(asObj(e))]
            : null,
      );

  List<LyricData>? data;
}

class LyricData {
  LyricData({required this.attributes});

  factory LyricData.fromJson(Map<String, dynamic> j) => LyricData(
        attributes: j['attributes'] == null
            ? null
            : LyricAttributes.fromJson(asObj(j['attributes'])),
      );

  LyricAttributes? attributes;
}

class LyricAttributes {
  LyricAttributes({required this.ttml, required this.ttmlLocalizations});

  factory LyricAttributes.fromJson(Map<String, dynamic> j) => LyricAttributes(
        ttml: asStr(j['ttml']),
        ttmlLocalizations: asStr(j['ttmlLocalizations']),
      );

  String ttml;

  String ttmlLocalizations;
}
