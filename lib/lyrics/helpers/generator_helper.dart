// Ported from Lyricify.Lyrics.Helper/Helpers/GeneratorHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../generators/krc_generator.dart';
import '../generators/lrc_generator.dart';
import '../generators/lyricify_lines_generator.dart';
import '../generators/lyricify_syllable_generator.dart';
import '../generators/qrc_generator.dart';
import '../generators/yrc_generator.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';

class GenerateHelper {
  /// 生成歌词字符串
  /// @param lyrics 用于生成的源歌词数据
  /// @param lyricsType 需要生成的歌词字符串的类型
  /// @returns 生成出的歌词字符串，若为空或生成失败则为 `null`
  static String? generateString(LyricsData lyrics, LyricsTypes lyricsType) {
    final result = switch (lyricsType) {
      LyricsTypes.lyricifySyllable =>
        LyricifySyllableGenerator.generate(lyrics),
      LyricsTypes.lyricifyLines => LyricifyLinesGenerator.generate(lyrics),
      LyricsTypes.lrc => LrcGenerator.generate(lyrics),
      LyricsTypes.qrc => QrcGenerator.generate(lyrics),
      LyricsTypes.krc => KrcGenerator.generate(lyrics),
      LyricsTypes.yrc => YrcGenerator.generate(lyrics),
      _ => null,
    };
    if (result == null || result.trim().isEmpty) return null;
    return result;
  }
}
