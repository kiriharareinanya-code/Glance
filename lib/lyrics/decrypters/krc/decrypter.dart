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

  ///
  static String? decryptLyrics(String encryptedLyrics) {
    final data = base64.decode(encryptedLyrics).sublist(4);
    final buffer = List<int>.from(data);

    for (var i = 0; i < buffer.length; ++i) {
      buffer[i] = (buffer[i] ^ decryptKey[i % decryptKey.length]) & 0xFF;
    }

    final res = utf8.decode(sharpZipLibDecompress(buffer));
    return res.substring(1);
  }

  static List<int> sharpZipLibDecompress(List<int> data) =>
      ZLibDecoder().convert(data);
}
