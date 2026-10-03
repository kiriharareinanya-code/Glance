// Ported from Lyricify.Lyrics.Helper/Parsers/Models/Spotify.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

class SpotifyColorLyrics {
  SpotifyColorLyrics();

  factory SpotifyColorLyrics.fromJson(Map<String, dynamic> j) {
    final self = SpotifyColorLyrics();
    final lyrics = j['lyrics'];
    self.lyrics =
        lyrics is Map ? SpotifyLyrics.fromJson(lyrics.cast<String, dynamic>()) : null;
    final colors = j['colors'];
    self.colors = colors is Map
        ? SpotifyColors.fromJson(colors.cast<String, dynamic>())
        : null;
    self.hasVocalRemoval = _asBool(j['hasVocalRemoval']);
    return self;
  }

  SpotifyLyrics? lyrics;

  SpotifyColors? colors;

  bool hasVocalRemoval = false;
}

class SpotifyLyrics {
  SpotifyLyrics();

  factory SpotifyLyrics.fromJson(Map<String, dynamic> j) {
    final self = SpotifyLyrics();
    self.syncType = j['syncType'] == null ? null : '${j['syncType']}';
    self.lines = _asList(j['lines'])
        .map((e) => SpotifyLyricsLine.fromJson(_asMap(e)))
        .toList();
    self.provider = j['provider'] == null ? null : '${j['provider']}';
    self.providerLyricsId =
        j['providerLyricsId'] == null ? null : '${j['providerLyricsId']}';
    self.providerDisplayName =
        j['providerDisplayName'] == null ? null : '${j['providerDisplayName']}';
    self.syncLyricsUri =
        j['syncLyricsUri'] == null ? null : '${j['syncLyricsUri']}';
    self.isDenseTypeface = _asBool(j['isDenseTypeface']);
    self.alternatives = _asList(j['alternatives'])
        .map((e) => AlternativeItem.fromJson(_asMap(e)))
        .toList();
    self.language = j['language'] == null ? null : '${j['language']}';
    self.isRtlLanguage = _asBool(j['isRtlLanguage']);
    self.fullscreenAction =
        j['fullscreenAction'] == null ? null : '${j['fullscreenAction']}';
    return self;
  }

  String? syncType;

  List<SpotifyLyricsLine>? lines;

  String? provider;

  String? providerLyricsId;

  String? providerDisplayName;

  String? syncLyricsUri;

  bool isDenseTypeface = false;

  List<AlternativeItem>? alternatives;

  String? language;

  bool isRtlLanguage = false;

  String? fullscreenAction;
}

class SpotifyLyricsLine {
  SpotifyLyricsLine();

  factory SpotifyLyricsLine.fromJson(Map<String, dynamic> j) {
    final self = SpotifyLyricsLine();
    self.startTimeMs = j['startTimeMs'] == null ? null : '${j['startTimeMs']}';
    self.endTimeMs = j['endTimeMs'] == null ? null : '${j['endTimeMs']}';
    self.words = j['words'] == null ? null : '${j['words']}';
    final syllables = j['syllables'];
    self.syllables = syllables is List
        ? syllables.map((e) => SyllableItem.fromJson(_asMap(e))).toList()
        : null;
    return self;
  }

  String? startTimeMs;

  int get startTime => _parseIntOrZero(startTimeMs);

  String? endTimeMs;

  int get endTime => _parseIntOrZero(endTimeMs);

  String? words;

  List<SyllableItem>? syllables;
}

class SyllableItem {
  SyllableItem();

  factory SyllableItem.fromJson(Map<String, dynamic> j) {
    final self = SyllableItem();
    self.startTimeMs = j['startTimeMs'] == null ? null : '${j['startTimeMs']}';
    self.endTimeMs = j['endTimeMs'] == null ? null : '${j['endTimeMs']}';
    self.numberChars = j['numChars'] == null ? null : '${j['numChars']}';
    return self;
  }

  String? startTimeMs;

  int get startTime => _parseIntOrZero(startTimeMs);

  String? endTimeMs;

  int get endTime => _parseIntOrZero(endTimeMs);

  String? numberChars;

  int get charsCount => _parseIntOrZero(numberChars);
}

class AlternativeItem {
  AlternativeItem();

  factory AlternativeItem.fromJson(Map<String, dynamic> j) {
    final self = AlternativeItem();
    self.language = j['language'] == null ? null : '${j['language']}';
    self.lines = j['lines'] is List
        ? _asList(j['lines']).map((e) => e == null ? '' : '$e').toList()
        : null;
    self.isRtlLanguage = _asBool(j['isRtlLanguage']);
    return self;
  }

  String? language;

  List<String>? lines;

  bool isRtlLanguage = false;
}

class SpotifyColors {
  SpotifyColors();

  factory SpotifyColors.fromJson(Map<String, dynamic> j) {
    final self = SpotifyColors();
    self.background = _asInt(j['background']);
    self.text = _asInt(j['text']);
    self.highlightText = _asInt(j['highlightText']);
    return self;
  }

  int background = 0;

  int text = 0;

  int highlightText = 0;
}

int _parseIntOrZero(String? s) {
  if (s == null) return 0;
  return int.tryParse(s) ?? 0;
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

bool _asBool(dynamic v) => v is bool ? v : false;

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
