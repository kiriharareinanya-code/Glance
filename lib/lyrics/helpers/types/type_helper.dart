// Ported from Lyricify.Lyrics.Helper/Helpers/TypeHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   `LyricsTypes[]` → `List<LyricsTypes>`。
//
library;

import '../../models/lyrics_types.dart';
import 'lyrics_type_detector.dart';

class TypeHelper {
  TypeHelper._();

  /// 识别歌词的类型
  /// @param lyrics 歌词字符串
  /// @returns `LyricsRawTypes`, 如果没有识别成功则会返回 `LyricsRawTypes.unknown`.
  static LyricsRawTypes getLyricsTypes(String lyrics) =>
      LyricsTypeDetector.detect(lyrics);

  static LyricsTypes getLyricsType(LyricsRawTypes type) {
    switch (type) {
      case LyricsRawTypes.unknown:
        return LyricsTypes.unknown;
      case LyricsRawTypes.lyricifySyllable:
        return LyricsTypes.lyricifySyllable;
      case LyricsRawTypes.lyricifyLines:
        return LyricsTypes.lyricifyLines;
      case LyricsRawTypes.lrc:
        return LyricsTypes.lrc;
      case LyricsRawTypes.qrc:
        return LyricsTypes.qrc;
      case LyricsRawTypes.qrcFull:
        return LyricsTypes.qrc;
      case LyricsRawTypes.krc:
        return LyricsTypes.krc;
      case LyricsRawTypes.yrc:
        return LyricsTypes.yrc;
      case LyricsRawTypes.yrcFull:
        return LyricsTypes.yrc;
      case LyricsRawTypes.ttml:
        return LyricsTypes.ttml;
      case LyricsRawTypes.appleJson:
        return LyricsTypes.ttml;
      case LyricsRawTypes.spotify:
        return LyricsTypes.spotify;
      case LyricsRawTypes.musixmatch:
        return LyricsTypes.musixmatch;
    }
  }

  ///
  static LyricsRawTypes? tryParseRawType(String? name) {
    if (name == null || name.trim().isEmpty) {
      return null;
    }

    final value = name.trim();
    if (!_isDigit(value.codeUnitAt(0))) {
      final parsed = _tryParseEnumName(value);
      if (parsed != null && parsed != LyricsRawTypes.unknown) {
        return parsed;
      }
    }

    final type = _parseSpecialName(value.toUpperCase());
    return type == LyricsRawTypes.unknown ? null : type;
  }

  static String getDisplayName(LyricsRawTypes type) {
    switch (type) {
      case LyricsRawTypes.lrc:
        return 'LRC';
      case LyricsRawTypes.qrc:
        return 'QRC';
      case LyricsRawTypes.qrcFull:
        return 'QRC (Full)';
      case LyricsRawTypes.krc:
        return 'KRC';
      case LyricsRawTypes.yrc:
        return 'YRC';
      case LyricsRawTypes.yrcFull:
        return 'YRC (Full)';
      case LyricsRawTypes.ttml:
        return 'TTML';
      case LyricsRawTypes.appleJson:
        return 'Apple Music (JSON)';
      case LyricsRawTypes.lyricifyLines:
        return 'Lyricify Lines';
      case LyricsRawTypes.lyricifySyllable:
        return 'Lyricify Syllable';
      case LyricsRawTypes.musixmatch:
        return 'Musixmatch (JSON)';
      case LyricsRawTypes.spotify:
        return 'Spotify (JSON)';
      case LyricsRawTypes.unknown:
        return '';
    }
  }

  static String getRawTypeDisplayName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '';
    }

    final type = tryParseRawType(name);
    return type != null ? getDisplayName(type) : name.trim();
  }

  /// 字符串是否是指定的歌词类型
  /// @param lyrics 歌词字符串
  /// @param type 歌词类型
  static bool isLyricsType(String lyrics, Object types) {
    if (types is LyricsTypes) {
      if (types == LyricsTypes.unknown) return false;

      final rawType = getLyricsTypes(lyrics);
      return rawType != LyricsRawTypes.unknown &&
          getLyricsType(rawType) == types;
    }

    if (types is List<LyricsTypes>) {
      if (types.isEmpty) return false;

      final rawType = getLyricsTypes(lyrics);
      if (rawType == LyricsRawTypes.unknown) return false;

      final type = getLyricsType(rawType);
      return type != LyricsTypes.unknown && types.contains(type);
    }
    return false;
  }

  ///
  static LyricsRawTypes? _tryParseEnumName(String value) {
    final lower = value.toLowerCase();
    for (final type in LyricsRawTypes.values) {
      if (type.name.toLowerCase() == lower) return type;
    }
    return null;
  }

  static LyricsRawTypes _parseSpecialName(String upper) {
    switch (upper) {
      case 'QRC (FULL)':
      case 'QRC (XML)':
        return LyricsRawTypes.qrcFull;
      case 'YRC (FULL)':
      case 'YRC (JSON)':
        return LyricsRawTypes.yrcFull;
      case 'APPLE MUSIC (JSON)':
      case 'APPLE MUSIC JSON':
      case 'APPLE MUSIC':
        return LyricsRawTypes.appleJson;
      case 'LYRICIFY LINE':
      case 'LYRICIFY LINES':
        return LyricsRawTypes.lyricifyLines;
      case 'LYRICIFY SYLLABLE':
      case 'LYRICIFY SYLLABLES':
        return LyricsRawTypes.lyricifySyllable;
      case 'MUSIXMATCH (JSON)':
      case 'MUSIXMATCH JSON':
      case 'MUSIXMATCHJSON':
        return LyricsRawTypes.musixmatch;
      case 'SPOTIFY (JSON)':
      case 'SPOTIFY JSON':
      case 'SPOTIFYJSON':
        return LyricsRawTypes.spotify;
      default:
        return LyricsRawTypes.unknown;
    }
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
}
