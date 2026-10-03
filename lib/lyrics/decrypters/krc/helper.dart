// Ported from Lyricify.Lyrics.Helper/Decrypter/Krc/Helper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import 'dart:convert';

import '../../json_utils.dart';
import '../../providers/web/base_api.dart';
import 'decrypter.dart';
import 'model.dart';

class Helper {
  ///
  static String? getLyrics(String id, String accessKey) {
    throw UnsupportedError(
      'KRC Helper.getLyrics 是同步 API，但下载歌词必须发网络请求；'
      'Dart 不能在同步方法里 await。请改用 Helper.getLyricsAsync(id, accessKey)。',
    );
  }

  ///
  static String? getEncryptedLyrics(String id, String accessKey) {
    throw UnsupportedError(
      'KRC Helper.getEncryptedLyrics 是同步 API，但下载歌词必须发网络请求；'
      'Dart 不能在同步方法里 await。请改用 Helper.getEncryptedLyricsAsync(id, accessKey)。',
    );
  }

  static Future<String?> getLyricsAsync(String id, String accessKey) async {
    final encryptedLyrics = await getEncryptedLyricsAsync(id, accessKey);
    final lyrics = Decrypter.decryptLyrics(encryptedLyrics!);
    return lyrics;
  }

  static Future<String?> getEncryptedLyricsAsync(String id, String accessKey) async {
    final response = await BaseApi.httpClient.send(
      method: 'GET',
      url: Uri.parse(
        'https://lyrics.kugou.com/download?ver=1&client=pc&id=$id&accesskey=$accessKey&fmt=krc&charset=utf8',
      ),
    );
    try {
      final decoded =
          KugouLyricsResponse.fromJson(asObj(jsonDecode(response.body)));
      return decoded.content;
    } catch (_) {
      return null;
    }
  }
}
