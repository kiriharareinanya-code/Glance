// Ported from Lyricify.Lyrics.Helper/Helpers/ParseHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
// `parseLyrics(String lyrics, [LyricsRawTypes? lyricsRawType])`：
//
library;

import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import 'types/type_helper.dart';
import '../parsers/krc_parser.dart';
import '../parsers/lrc_parser.dart';
import '../parsers/lyricify_lines_parser.dart';
import '../parsers/musixmatch_parser.dart';
import '../parsers/qrc_parser.dart';
import '../parsers/spotify_parser.dart';
import '../parsers/ttml_parser.dart';
import '../parsers/yrc_parser.dart';

class ParseHelper {
  ParseHelper._();

  /// 解析歌词
  /// @param lyrics 歌词字符串
  /// @returns 解析后的歌词数据
  static LyricsData? parseLyrics(
    String lyrics, [
    LyricsRawTypes? lyricsRawType,
  ]) {
    final type = lyricsRawType ?? TypeHelper.getLyricsTypes(lyrics);

    switch (type) {
      case LyricsRawTypes.lyricifyLines:
        return LyricifyLinesParser.parse(lyrics);
      case LyricsRawTypes.lrc:
        return LrcParser.parse(lyrics);
      case LyricsRawTypes.qrc:
        return QrcParser.parse(lyrics);
      case LyricsRawTypes.krc:
        return KrcParser.parse(lyrics);
      case LyricsRawTypes.yrc:
        return YrcParser.parse(lyrics);
      case LyricsRawTypes.ttml:
        return TtmlParser.parse(lyrics);
      case LyricsRawTypes.spotify:
        return SpotifyParser.parse(lyrics);
      case LyricsRawTypes.musixmatch:
        return MusixmatchParser.parse(lyrics);
      case LyricsRawTypes.unknown:
      case LyricsRawTypes.qrcFull:
      case LyricsRawTypes.yrcFull:
      case LyricsRawTypes.appleJson:
        return null;
    }
  }
}
