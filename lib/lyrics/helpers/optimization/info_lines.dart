// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/InfoLines.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   `NeedsToSC()`：`text.ToSC()` → `ChineseHelper.toSC(text)`；`ToSC(true)` →
//   `StringHelper.HasChinese(...)` → `StringHelper.hasChinese(...)`。
//   `Regex.Split(titleLower, " - ", RegexOptions.IgnoreCase)` → `titleLower.split(...)`。
//   `s.Contains(x, StringComparison.OrdinalIgnoreCase)` → [_containsIgnoreCase]。
//
//   `CheckInfoLines(LyricsData)`                    → [checkInfoLines]
//   `CheckInfoLines(List<ILineInfo>, ITrackMetadata?)` → [checkInfoLinesList]
//   `GetHeadingInfoLinesCount(LyricsData)`                    → [getHeadingInfoLinesCount]
//   `GetHeadingInfoLinesCount(List<ILineInfo>, ITrackMetadata?)` → [getHeadingInfoLinesCountList]
//   `GetEndingInfoLinesCount(LyricsData)`                    → [getEndingInfoLinesCount]
//   `GetEndingInfoLinesCount(List<ILineInfo>, ITrackMetadata?)` → [getEndingInfoLinesCountList]
//
//
library;

import '../../models/line_info.dart';
import '../../models/lyrics_data.dart';
import '../../models/track_metadata.dart';
import '../general/chinese_helper.dart';
import '../general/string_helper.dart';

class InfoLines {
  InfoLines._();

  static List<bool> checkInfoLines(LyricsData lyrics) =>
      checkInfoLinesList(lyrics.lines ?? <LineInfo>[], lyrics.trackMetadata);

  static int getHeadingInfoLinesCount(LyricsData lyrics) =>
      getHeadingInfoLinesCountList(
        lyrics.lines ?? <LineInfo>[],
        lyrics.trackMetadata,
      );

  static int getEndingInfoLinesCount(LyricsData lyrics) =>
      getEndingInfoLinesCountList(
        lyrics.lines ?? <LineInfo>[],
        lyrics.trackMetadata,
      );

  /// Returns a bool list with the same length as [lines]:
  /// true => info/credit/claiming line
  ///
  static List<bool> checkInfoLinesList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    final n = lines.length;
    final flags = List<bool>.filled(n, false);
    if (n == 0) return flags;

    final startCount = getHeadingInfoLinesCountList(lines, trackInfo);
    final endCount = getEndingInfoLinesCountList(lines, trackInfo);

    for (var i = 0; i < startCount && i < n; i++) {
      flags[i] = true;
    }

    for (var i = n - endCount; i < n; i++) {
      if (i >= 0) flags[i] = true;
    }

    // Middle part
    final midStart = _clampInt(startCount, 0, n);
    final midEndExclusive = _clampInt(n - endCount, 0, n);

    for (var i = midStart; i < midEndExclusive; i++) {
      final text = _getLineText(lines[i]);
      if (isInfoLine(text, trackInfo)) {
        flags[i] = true;
      }
    }

    return flags;
  }

  static int getHeadingInfoLinesCountList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    if (lines.isEmpty) return 0;

    // Special-case: "Title + Artist"
    var i = 0;
    if (trackInfo != null && lines.isNotEmpty) {
      final first = _getLineText(lines[0]);

      if (_looksLikeTitleAndArtistLine(first, trackInfo)) {
        i++;
      } else if (i == 0 && lines.length >= 3) {
        if (isInfoLine(_getLineText(lines[1]), trackInfo)) {
          i += 2;
        }
      }
    }

    for (; i < lines.length; i++) {
      final text = _getLineText(lines[i]);

      if (text.trim().isEmpty) {
        if (_hasUpcomingInfo(lines, i, trackInfo)) continue;

        break;
      }

      if (isInfoLine(text, trackInfo)) continue;

      if (i + 1 < lines.length &&
          isInfoLine(_getLineText(lines[i + 1]), trackInfo)) {
        i++;
        continue;
      }

      break;
    }

    return i;
  }

  static int getEndingInfoLinesCountList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    if (lines.isEmpty) return 0;

    var count = 0;

    for (var i = lines.length - 1; i >= 0; i--) {
      final text = _getLineText(lines[i]);

      if (text.trim().isEmpty) {
        if (_hasPreviousInfo(lines, i, trackInfo)) {
          count++;
          continue;
        }
        break;
      }

      if (isInfoLine(text, trackInfo)) {
        count++;
        continue;
      }

      break;
    }

    return count;
  }

  static bool isInfoLine(String? text, [TrackMetadata? trackInfo]) {
    if (text == null || text.trim().isEmpty) return false;

    final str = ChineseHelper.toSC(text.replaceAll('：', ': ')).trim();

    if (_looksLikeArtistSpeakerLabel(text, trackInfo)) {
      return false;
    }

    if (_isStringTencentClaiming(str)) {
      return true;
    }

    if (_isStringCreditBy(str)) {
      return true;
    }

    final hitDict = _containsAnyKeyword(str, titleLineInfoDict);
    final hasColon = str.contains(':') || str.contains('：');

    if (!hitDict || !hasColon) {
      return _isStringCopyrightClaiming(str);
    }

    return true;
  }

  static final List<String> titleLineInfoDict = <String>[
    'OA',
    'OP',
    'OT',
    'PV',
    'SP',
    'A&R',
    'PGM',
    'ISRC',
    'Bass',
    'Drum',
    'Pads',
    'Brass',
    'Cello',
    'Choir',
    'Horns',
    'Mixed',
    'Mixer',
    'Piano',
    'Synth',
    'Viola',
    'Vocal',
    'Winds',
    'Kobza',
    'Assist',
    'Violin',
    'Mixing',
    'String',
    'Guitar',
    'Master',
    'Chorus',
    'Record',
    'violins',
    'Arrange',
    'Conduct',
    'Editing',
    'Hormony',
    'Ocarina',
    'Produce',
    'Strings',
    'Whistle',
    'Stylist',
    'Engineer',
    'Keyboard',
    'Director',
    'Harmonica',
    'Mastering',
    'Recording',
    'Balalaika',
    'Percussion',
    'Programing',
    'Production',
    'Programming',
    'Additional programming',
    'Irish whistle',
  ];

  static String _getLineText(LineInfo? line) => line?.text ?? '';

  static bool _containsAny(String s, List<String> parts) {
    final lowered = s.toLowerCase();
    for (final p in parts) {
      if (p.isEmpty) continue;
      if (lowered.contains(p.toLowerCase())) return true;
    }
    return false;
  }

  static bool _containsAnyKeyword(String s, List<String> dict) {
    if (dict.isEmpty) return false;

    final lowered = s.toLowerCase();
    for (var i = 0; i < dict.length; i++) {
      final k = dict[i];
      if (k.trim().isEmpty) continue;

      if (lowered.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  static bool _hasUpcomingInfo(
    List<LineInfo> lines,
    int index,
    TrackMetadata? trackInfo,
  ) {
    var seen = 0;
    for (var i = index + 1; i < lines.length && seen < 2; i++) {
      final t = _getLineText(lines[i]);
      if (t.trim().isEmpty) continue;
      seen++;
      if (isInfoLine(t, trackInfo)) return true;
    }
    return false;
  }

  static bool _hasPreviousInfo(
    List<LineInfo> lines,
    int index,
    TrackMetadata? trackInfo,
  ) {
    var seen = 0;
    for (var i = index - 1; i >= 0 && seen < 2; i--) {
      final t = _getLineText(lines[i]);
      if (t.trim().isEmpty) continue;
      seen++;
      if (isInfoLine(t, trackInfo)) return true;
    }
    return false;
  }

  static bool _looksLikeArtistSpeakerLabel(
    String raw,
    TrackMetadata? trackInfo,
  ) {
    // If any artist equals "Artist:" then NOT titleline
    final t = raw.trim();
    if (!t.endsWith(':')) return false;

    // Multi-artist
    if (trackInfo is TrackMultiArtistMetadata && trackInfo.artists.isNotEmpty) {
      for (final artist in trackInfo.artists) {
        if (artist.trim().isEmpty) continue;
        if (_equalsIgnoreCase('${artist.trim()}:', t)) return true;
      }
    }

    // Single artist
    final single = trackInfo?.artist;
    if (single != null && single.trim().isNotEmpty) {
      if (_equalsIgnoreCase('${single.trim()}:', t)) return true;
    }

    return false;
  }

  static bool _looksLikeTitleAndArtistLine(
    String line,
    TrackMetadata trackInfo,
  ) {
    if (line.trim().isEmpty) return false;

    final lineNorm = line.toLowerCase().replaceAll('’', "'");
    final titleNorm = ChineseHelper
        .toSC((trackInfo.title ?? '').toLowerCase(), true)
        .replaceAll('’', "'");
    final artistNorm = ChineseHelper
        .toSC((trackInfo.artist ?? '').toLowerCase(), true)
        .replaceAll('’', "'")
        .replaceAll(', ', '/');

    final titleHit = _containsTitle(lineNorm, titleNorm);
    final artistHit = _containsArtists(lineNorm, trackInfo, artistNorm);

    if (titleHit && artistHit) return true;

    if ((trackInfo.title ?? '').contains(' - ')) {
      final parts = (trackInfo.title ?? '')
          .toLowerCase()
          .replaceAll('’', "'")
          .split(RegExp(' - ', caseSensitive: false));
      if (parts.isNotEmpty) {
        final t0 = parts[0];
        if (t0.trim().isNotEmpty &&
            lineNorm.contains(t0) &&
            lineNorm.contains(artistNorm)) {
          return true;
        }
      }
    }

    if (StringHelper.hasChinese(trackInfo.title ?? '')) {
      if (line.contains(ChineseHelper.toSC(trackInfo.title ?? '')) &&
          line.contains(ChineseHelper.toSC(trackInfo.artist ?? ''))) {
        return true;
      }
    }

    return false;
  }

  static bool _containsTitle(String lineLower, String titleLower) {
    if (titleLower.trim().isEmpty) return false;
    if (lineLower.contains(titleLower)) return true;

    // line has "(...)" => compare before '('
    final idx = lineLower.indexOf('(');
    if (idx > 0) {
      final before = lineLower.substring(0, idx);
      if (before.contains(titleLower)) return true;
    }

    // title has "(...)" => compare before '('
    final tIdx = titleLower.indexOf('(');
    if (tIdx > 0) {
      final before = titleLower.substring(0, tIdx).trim();
      if (before.isNotEmpty && lineLower.contains(before)) return true;
    }

    // title has " - " => compare before " - "
    final dash = titleLower.indexOf(' - ');
    if (dash > 0) {
      final before = titleLower.substring(0, dash).trim();
      if (before.isNotEmpty && lineLower.contains(before)) return true;
    }

    return false;
  }

  static bool _containsArtists(
    String lineLower,
    TrackMetadata trackInfo,
    String singleArtistNorm,
  ) {
    if (singleArtistNorm.trim().isNotEmpty &&
        lineLower.contains(singleArtistNorm)) {
      return true;
    }

    if (trackInfo is TrackMultiArtistMetadata && trackInfo.artists.isNotEmpty) {
      var hit = 0;
      for (final a in trackInfo.artists) {
        if (a.trim().isEmpty) continue;
        final norm = ChineseHelper.toSC(a.toLowerCase(), true)
            .replaceAll('’', "'")
            .replaceAll(', ', '/');
        if (norm.isNotEmpty && lineLower.contains(norm)) hit++;
      }

      if (hit > 1 || (hit == 1 && trackInfo.artists.length == 1)) {
        return true;
      }
    }

    return false;
  }

  static bool _isStringTencentClaiming(String str) {
    final s = ChineseHelper.toSC(str);
    return (s.contains('腾讯') || s.contains('TME')) &&
        s.contains('享有') &&
        s.contains('翻译') &&
        s.contains('权');
  }

  static bool _isStringCreditBy(String str) {
    if (_containsAny(str, ['st:', 'or:', 'Lyrics:', ' by:', ' By:'])) {
      return true;
    }

    if (_containsIgnoreCase(str, 'er:') &&
        !_containsIgnoreCase(str, 'Tedder:') &&
        !_containsIgnoreCase(str, 'Bieber:')) {
      return true;
    }

    return false;
  }

  static bool _isStringCopyrightClaiming(String str) {
    var score = 0;
    if (str.contains('未经')) score++;
    if (str.contains('许可')) score++;
    if (str.contains('授权')) score++;
    if (str.contains('不得')) score++;
    if (str.contains('请勿')) score++;
    if (str.contains('使用')) score++;
    if (str.contains('版权')) score++;

    return score >= 4;
  }

  /// `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`。
  static bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  /// `str.Contains(x, StringComparison.OrdinalIgnoreCase)`。
  static bool _containsIgnoreCase(String str, String value) =>
      str.toLowerCase().contains(value.toLowerCase());

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
