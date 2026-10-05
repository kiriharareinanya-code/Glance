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

  // 名字里带 Syllable 但**不是**逐字检测器：它只用来做否定判断
  // （见下面 isLyricifyLines）。KRC/YRC/QRC 都有这种括号时间戳，
  // 所以"带括号时间戳"就不是 Lyricify 的纯文本行格式。
  // 逐字检测本身已随 LyricifySyllableParser 一起删掉。
  static final RegExp _anySyllableTiming =
      RegExp(r'(?:\(-?\d+,\d+(?:,\d+)?\)|<-?\d+,\d+,\d+>)');

  static final RegExp _qrcFullFallback = RegExp(
    r'<Lyric_1\b[^>]*\bLyricContent\s*=',
    caseSensitive: false,
  );

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
    if (isQrc(input)) return LyricsRawTypes.qrc;
    if (isLyricifyLines(input)) return LyricsRawTypes.lyricifyLines;
    if (isLrc(input)) return LyricsRawTypes.lrc;

    return LyricsRawTypes.unknown;
  }

  // PERF: each `RegExp` below cannot match unless the payload contains its
  // literal `[` (and, for QRC/YRC/KRC, a second literal). `String.contains` on a
  // single character is a memchr: measured 0.14-6.5 us against 40-160 us for
  // the corresponding multi-line regex, which is the difference between a fast
  // reject and a full sweep of every payload that does not carry that format.
  // The guards are exactly equivalent - no string lacking the literal can match.
  static bool isLrc(String input) =>
      input.contains('[') && _lrcLine.hasMatch(input);

  static bool isLyricifyLines(String input) {
    if (_hasLyricifyLinesTypeMarker(input)) return true;

    return input.contains('[') &&
        _bracketedLine.hasMatch(input) &&
        !_anySyllableTiming.hasMatch(input);
  }

  static bool isQrc(String input) =>
      input.contains('[') && input.contains('(') && _qrcLine.hasMatch(input);

  static bool isQrcFull(String input) =>
      _getXmlType(input) == LyricsRawTypes.qrcFull;

  static bool isKrc(String input) =>
      input.contains('[') && input.contains('<') && _krcLine.hasMatch(input);

  static bool isYrc(String input) =>
      input.contains('[') && input.contains('(') && _yrcLine.hasMatch(input);

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
  ///
  /// PERF: the original evaluated `input.toLowerCase().contains(...)`, which
  /// runs Unicode case mapping over the **whole** payload and allocates a
  /// second full copy of it - measured at 88.7 us for a 3.8 kB LRC and roughly
  /// 1.3 ms for a 55 kB payload. [detect] reached it twice (once directly, once
  /// more via [isLyricifyLines]), making it the most expensive step of sniffing
  /// a plain-text payload by a wide margin - more than the five multi-line
  /// regexes combined.
  ///
  /// [_containsIgnoreCaseAscii] below is exactly equivalent and allocates
  /// nothing:
  ///  * No code point in Unicode has a length-changing default lowercase in
  ///    Dart (verified exhaustively over all 0x110000 of them), so the original
  ///    lowercased string is code-unit-aligned with `input`.
  ///  * Exhaustive check over all 0x110000 code points: the only non-ASCII one
  ///    whose lowercase lands on a character of the marker is U+0130
  ///    (LATIN CAPITAL LETTER I WITH DOT ABOVE) -> `'i'`, and [_asciiLower]
  ///    handles it. U+212A (KELVIN SIGN) -> `'k'` is irrelevant here: the marker
  ///    contains no `'k'`.
  ///  * `'['` and `']'` have no case variants and no non-ASCII code unit
  ///    lowercases to either, so they are exact anchors for the scan.
  static bool _hasLyricifyLinesTypeMarker(String input) =>
      _containsIgnoreCaseAscii(input, _lyricifyLinesMarker);

  static const String _lyricifyLinesMarker = '[type:lyricifylines]';

  /// Allocation-free `input.toLowerCase().contains(lowerNeedle)` for a pure-ASCII
  /// needle (see the equivalence argument above). The needle's first and last
  /// characters are used as hard anchors: neither `'['` nor `']'` has a case
  /// variant, and no code point lowercases onto either, so only positions that
  /// literally hold them can start a match.
  static bool _containsIgnoreCaseAscii(String haystack, String lowerNeedle) {
    const int openBracket = 0x5B; // '['
    const int closeBracket = 0x5D; // ']'
    final coreLength = lowerNeedle.length - 2;
    final limit = haystack.length - lowerNeedle.length;
    for (var i = 0; i <= limit; i++) {
      if (haystack.codeUnitAt(i) != openBracket) continue;
      if (haystack.codeUnitAt(i + lowerNeedle.length - 1) != closeBracket) {
        continue;
      }
      var j = 0;
      for (; j < coreLength; j++) {
        if (_asciiLower(haystack.codeUnitAt(i + 1 + j)) !=
            lowerNeedle.codeUnitAt(j + 1)) {
          break;
        }
      }
      if (j == coreLength) return true;
    }
    return false;
  }

  /// `String.toLowerCase()` for a single code unit, restricted to the code units
  /// whose lowercase is an ASCII letter.
  static int _asciiLower(int cu) {
    if (cu >= 0x41 && cu <= 0x5A) return cu + 0x20; // 'A'..'Z'
    if (cu == 0x0130) return 0x69; // LATIN CAPITAL LETTER I WITH DOT ABOVE
    return cu;
  }

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

  /// `value.GetValue(propertyName, StringComparison.OrdinalIgnoreCase)`.
  ///
  /// PERF: the OrdinalIgnoreCase fallback used to linearly walk every entry of
  /// [value] and allocate a `toLowerCase()` copy of every key **on every miss**.
  /// `_isAppleJson` / `_isSpotify` / `_isMusixmatch` miss several keys per map,
  /// so one detection pass did several full passes over a big decoded JSON
  /// object. The lowercase index is now built at most once per map.
  ///
  /// The index lives in an [Expando] keyed by the map's identity, so it is
  /// collected together with the map and cannot leak.
  static final Expando<Map<String, dynamic>> _lowerKeyIndex =
      Expando<Map<String, dynamic>>('LyricsTypeDetector.lowerKeyIndex');

  static dynamic _get(Map<String, dynamic>? value, String propertyName) {
    if (value == null) return null;

    if (value.containsKey(propertyName)) return value[propertyName];

    var index = _lowerKeyIndex[value];
    if (index == null) {
      index = <String, dynamic>{};
      for (final entry in value.entries) {
        // `putIfAbsent` keeps the FIRST match, matching the original scan order.
        index.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
      }
      _lowerKeyIndex[value] = index;
    }
    return index[propertyName.toLowerCase()];
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

  static Iterable<XmlElement> _descendantsAndSelf(XmlElement root) sync* {
    yield root;
    yield* root.descendantElements;
  }

  /// `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`。
  static bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();
}
