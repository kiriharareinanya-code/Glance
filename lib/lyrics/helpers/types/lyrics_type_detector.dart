// Ported from Lyricify.Lyrics.Helper/Helpers/Types/LyricsTypeDetector.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   `RegexOptions.Compiled | RegexOptions.CultureInvariant | RegexOptions.Multiline`
//   `Newtonsoft.Json.Linq`（`JObject.Parse` / `GetValue(name, OrdinalIgnoreCase)` /
//   `System.Xml.Linq`（`XDocument.Parse(s, LoadOptions.PreserveWhitespace)`）→
//   `string.Equals(x, y, StringComparison.OrdinalIgnoreCase)` → `_equalsIgnoreCase`；
//
// （`Lrc` / `LyricifyLines` / `LyricifySyllable` / `Qrc` / `Krc` / `Yrc` / `Ttml` /
// `isTtml` / `isAppleJson` / `isSpotify` / `isMusixmatch` / `isLyricifyLines` /
library;

import 'dart:convert';

import 'package:xml/xml.dart';

import '../../models/lyrics_types.dart';

class LyricsTypeDetector {
  LyricsTypeDetector._();

  static const String ttmlNamespace = 'http://www.w3.org/ns/ttml';

  static final RegExp _lrcLine = RegExp(
    r'^[ \t]*(?:\[\d+:\d{1,2}(?:[.:]\d{1,3})?\])+[^\r\n]*',
    multiLine: true,
  );

  static final RegExp _bracketedLine = RegExp(
    r'^[ \t]*\[\d+,\d+\][^\r\n]*',
    multiLine: true,
  );

  static final RegExp _qrcLine = RegExp(
    r'^[ \t]*\[\d+,\d+\][^\r\n]*\(-?\d+,\d+\)[^\r\n]*',
    multiLine: true,
  );

  static final RegExp _krcLine = RegExp(
    r'^[ \t]*\[\d+,\d+\]<-?\d+,\d+,\d+>[^\r\n]*',
    multiLine: true,
  );

  static final RegExp _yrcLine = RegExp(
    r'^[ \t]*\[\d+,\d+\]\(-?\d+,\d+,\d+\)[^\r\n]*',
    multiLine: true,
  );

  static final RegExp _lyricifySyllableLine = RegExp(
    r'^[ \t]*\[\d+\][^\r\n]*\(-?\d+,\d+\)[^\r\n]*',
    multiLine: true,
  );

  static final RegExp _anySyllableTiming =
      RegExp(r'(?:\(-?\d+,\d+(?:,\d+)?\)|<-?\d+,\d+,\d+>)');

  static final RegExp _qrcFullFallback = RegExp(
    r'<Lyric_1\b[^>]*\bLyricContent\s*=',
    caseSensitive: false,
  );

  ///
  static LyricsRawTypes detect(String input) {
    if (input.trim().isEmpty) return LyricsRawTypes.unknown;

    var structuredType = _getJsonType(input);
    if (structuredType != LyricsRawTypes.unknown) return structuredType;

    structuredType = _getXmlType(input);
    if (structuredType != LyricsRawTypes.unknown) return structuredType;

    if (_hasLyricifyLinesTypeMarker(input)) {
      return LyricsRawTypes.lyricifyLines;
    }
    if (isKrc(input)) return LyricsRawTypes.krc;
    if (isYrc(input)) return LyricsRawTypes.yrc;
    if (isLyricifySyllable(input)) return LyricsRawTypes.lyricifySyllable;
    if (isQrc(input)) return LyricsRawTypes.qrc;
    if (isLyricifyLines(input)) return LyricsRawTypes.lyricifyLines;
    if (isLrc(input)) return LyricsRawTypes.lrc;

    return LyricsRawTypes.unknown;
  }

  static bool isLrc(String input) => _lrcLine.hasMatch(input);

  static bool isLyricifyLines(String input) {
    if (_hasLyricifyLinesTypeMarker(input)) return true;

    return _bracketedLine.hasMatch(input) &&
        !_anySyllableTiming.hasMatch(input);
  }

  static bool isLyricifySyllable(String input) =>
      _lyricifySyllableLine.hasMatch(input);

  static bool isQrc(String input) => _qrcLine.hasMatch(input);

  static bool isQrcFull(String input) =>
      _getXmlType(input) == LyricsRawTypes.qrcFull;

  static bool isKrc(String input) => _krcLine.hasMatch(input);

  static bool isYrc(String input) => _yrcLine.hasMatch(input);

  static bool isYrcFull(String input) =>
      _getJsonType(input) == LyricsRawTypes.yrcFull;

  static bool isTtml(String input) =>
      _getXmlType(input) == LyricsRawTypes.ttml;

  static bool isAppleJson(String input) =>
      _getJsonType(input) == LyricsRawTypes.appleJson;

  static bool isSpotify(String input) =>
      _getJsonType(input) == LyricsRawTypes.spotify;

  static bool isMusixmatch(String input) =>
      _getJsonType(input) == LyricsRawTypes.musixmatch;


  /// `input.IndexOf("[type:LyricifyLines]", StringComparison.OrdinalIgnoreCase) >= 0`。
  static bool _hasLyricifyLinesTypeMarker(String input) =>
      input.toLowerCase().contains('[type:lyricifylines]');

  static LyricsRawTypes _getJsonType(String input) {
    final trimmedStart = input.trimLeft();
    if (trimmedStart.isEmpty || trimmedStart[0] != '{') {
      return LyricsRawTypes.unknown;
    }

    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map) return LyricsRawTypes.unknown;
      root = decoded.cast<String, dynamic>();
    } catch (_) {
      return LyricsRawTypes.unknown;
    }

    if (_isAppleJson(root)) return LyricsRawTypes.appleJson;
    if (_isSpotify(root)) return LyricsRawTypes.spotify;
    if (_isMusixmatch(root)) return LyricsRawTypes.musixmatch;
    if (_isYrcFull(root)) return LyricsRawTypes.yrcFull;

    return LyricsRawTypes.unknown;
  }

  static LyricsRawTypes _getXmlType(String input) {
    final trimmedStart = input.trimLeft();
    if (trimmedStart.isEmpty || trimmedStart[0] != '<') {
      return LyricsRawTypes.unknown;
    }

    try {
      final document = XmlDocument.parse(input);
      XmlElement? root;
      for (final child in document.children) {
        if (child is XmlElement) {
          root = child;
          break;
        }
      }
      if (root == null) return LyricsRawTypes.unknown;

      for (final element in _descendantsAndSelf(root)) {
        if (_equalsIgnoreCase(element.name.local, 'Lyric_1') &&
            element.attributes.any(
              (attribute) =>
                  _equalsIgnoreCase(attribute.name.local, 'LyricContent'),
            )) {
          return LyricsRawTypes.qrcFull;
        }
      }

      if (_equalsIgnoreCase(root.name.local, 'tt') &&
          (root.name.namespaceUri ?? '') == ttmlNamespace) {
        return LyricsRawTypes.ttml;
      }
    } catch (_) {
      if (_qrcFullFallback.hasMatch(input)) return LyricsRawTypes.qrcFull;
    }

    return LyricsRawTypes.unknown;
  }

  static bool _isAppleJson(Map<String, dynamic> root) {
    final data = _get(root, 'data');
    if (data is! List) return false;

    for (final item in _objectsIn(data)) {
      if (_isSyllableLyricsItem(item)) return true;

      final relationships = _asObject(_get(item, 'relationships'));
      if (relationships == null) continue;
      final syllableLyrics = _asObject(_get(relationships, 'syllable-lyrics'));
      if (syllableLyrics == null) continue;
      final relationshipData = _get(syllableLyrics, 'data');
      if (relationshipData is! List) continue;

      if (_objectsIn(relationshipData).any(_isSyllableLyricsItem)) return true;
    }

    return false;
  }

  static bool _isSyllableLyricsItem(Map<String, dynamic> item) {
    final type = _valueString(_get(item, 'type'));
    if (type != null &&
        type.isNotEmpty &&
        !_equalsIgnoreCase(type, 'syllable-lyrics')) {
      return false;
    }

    final attributes = _asObject(_get(item, 'attributes'));
    if (attributes == null) return false;
    return _hasNonEmptyString(attributes, 'ttml') ||
        _hasNonEmptyString(attributes, 'ttmlLocalizations');
  }

  static bool _isSpotify(Map<String, dynamic> root) {
    final lyrics = _asObject(_get(root, 'lyrics'));
    if (lyrics == null) return false;
    return _get(lyrics, 'syncType') is String && _get(lyrics, 'lines') is List;
  }

  static bool _isMusixmatch(Map<String, dynamic> root) {
    final message = _asObject(_get(root, 'message'));
    if (message == null) return false;
    final body = _asObject(_get(message, 'body'));
    if (body == null) return false;
    final calls = _asObject(_get(body, 'macro_calls'));
    if (calls == null) return false;

    return _get(calls, 'track.richsync.get') != null ||
        _get(calls, 'track.subtitles.get') != null ||
        _get(calls, 'track.lyrics.get') != null;
  }

  static bool _isYrcFull(Map<String, dynamic> root) {
    final yrc = _asObject(_get(root, 'yrc'));
    if (yrc == null) return false;
    return _get(yrc, 'lyric') is String;
  }

  /// `!string.IsNullOrWhiteSpace(Get(value, propertyName)?.Value<string>())`。
  static bool _hasNonEmptyString(
    Map<String, dynamic> value,
    String propertyName,
  ) {
    final v = _valueString(_get(value, propertyName));
    return v != null && v.trim().isNotEmpty;
  }

  /// `value.GetValue(propertyName, StringComparison.OrdinalIgnoreCase)`。
  ///
  static dynamic _get(Map<String, dynamic>? value, String propertyName) {
    if (value == null) return null;

    if (value.containsKey(propertyName)) return value[propertyName];

    final lower = propertyName.toLowerCase();
    for (final entry in value.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  static Map<String, dynamic>? _asObject(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static Iterable<Map<String, dynamic>> _objectsIn(List<dynamic> list) =>
      list.whereType<Map>().map((e) => e.cast<String, dynamic>());

  static String? _valueString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    return null;
  }

  ///
  static Iterable<XmlElement> _descendantsAndSelf(XmlElement root) sync* {
    yield root;
    yield* root.descendantElements;
  }

  /// `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`。
  static bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();
}
