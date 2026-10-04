// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/Helper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'model.dart';

abstract class QqMusicLyricsApi {
  Future<SongResponse?> getSong(String mid);

  Future<QqLyricsResponse?> getLyricsAsync(String id);
}

class Helper {
  static QqMusicLyricsApi? qqMusicApi;

  /// 通过 Mid 获取解密后的歌词
  /// @param id QQ 音乐歌曲 Mid
  static Future<QqLyricsResponse?> getLyricsByMid(String mid) async {
    final song = await qqMusicApi!.getSong(mid);
    if (song == null || song.data.isEmpty) return null;
    final id = song.data[0].id;
    return qqMusicApi!.getLyricsAsync(id!);
  }

  static Future<QqLyricsResponse?> getLyricsByMidAsync(String mid) =>
      getLyricsByMid(mid);

  /// 通过 ID 获取解密后的歌词
  /// @param id QQ 音乐歌曲 ID
  static Future<QqLyricsResponse?> getLyrics(String id) =>
      qqMusicApi!.getLyricsAsync(id);

  static Future<QqLyricsResponse?> getLyricsAsync(String id) =>
      qqMusicApi!.getLyricsAsync(id);
}
