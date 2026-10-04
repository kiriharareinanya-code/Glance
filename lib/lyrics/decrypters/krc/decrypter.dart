// Ported from Lyricify.Lyrics.Helper/Decrypter/Krc/Decrypter.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

import 'dart:convert';
import 'dart:io';

class Decrypter {
  static final List<int> decryptKey = [
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, //
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
  ];

  /// 解密 KRC 歌词
  /// @param encryptedLyrics 加密的歌词
  /// @returns 解密后的 KRC 歌词
  static String? decryptLyrics(String encryptedLyrics) {
    final data = base64.decode(encryptedLyrics).sublist(4);
    final buffer = List<int>.from(data);

    for (var i = 0; i < buffer.length; ++i) {
      buffer[i] = (buffer[i] ^ decryptKey[i % decryptKey.length]) & 0xFF;
    }

    // 上游 Decrypter/Krc/Decrypter.cs:24-25
    //   var res = Encoding.UTF8.GetString(SharpZipLibDecompress(data));
    //   return res[1..];
    //
    // PORT NOTE: .NET 的 `Encoding.UTF8.GetString` **不会**丢弃 UTF-8 BOM，
    // BOM 会被解码成 U+FEFF 这个字符，所以上游 `res[1..]` 砍掉的正是这个 BOM，
    // 明文仍以 '[' 开头。Dart 的 `utf8.decode` 会直接把 BOM 吃掉，若照抄
    // `substring(1)` 就会多吃一个字符（'[' 被砍掉）。这里按上游语义先把 BOM
    // 还原成字符，再执行 `res[1..]`。
    final bytes = sharpZipLibDecompress(buffer);
    final res =
        _hasUtf8Bom(bytes)
            ? '\u{FEFF}${utf8.decode(bytes)}'
            : utf8.decode(bytes);
    return res.substring(1);
  }

  static List<int> sharpZipLibDecompress(List<int> data) =>
      ZLibDecoder().convert(data);

  static bool _hasUtf8Bom(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
}
