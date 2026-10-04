// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/Decrypter.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
/// `List&lt;List&lt;List&lt;int&gt;&gt;&gt;` / `List&lt;List&lt;int&gt;&gt;`。
library;

import 'dart:convert';
import 'dart:io';

import 'des_helper.dart';

class Decrypter {
  static final List<int> qqKey = ascii.encode(r'!@#)(*$%123ZXC!@!@#)(NHL');

  /// 解密 QRC 歌词
  /// @param encryptedLyrics 加密的歌词
  /// @returns 解密后的 QRC 歌词
  static String? decryptLyrics(String encryptedLyrics) {
    final encryptedTextByte = hexStringToByteArray(encryptedLyrics);
    final data = List<int>.filled(encryptedTextByte.length, 0);
    final schedule = <List<List<int>>>[];
    for (var i = 0; i < 3; i++) {
      final layer = <List<int>>[];
      for (var j = 0; j < 16; j++) {
        layer.add(List<int>.filled(6, 0));
      }
      schedule.add(layer);
    }
    DESHelper.tripleDESKeySetup(qqKey, schedule, DESHelper.decrypt);
    for (var i = 0; i < encryptedTextByte.length; i += 8) {
      final temp = List<int>.filled(8, 0);
      DESHelper.tripleDESCrypt(encryptedTextByte.sublist(i), temp, schedule);
      for (var j = 0; j < 8; j++) {
        data[i + j] = temp[j];
      }
    }

    var unzip = sharpZipLibDecompress(data);

    const utf8Bom = [0xEF, 0xBB, 0xBF];
    if (unzip.length >= utf8Bom.length &&
        _sequenceEqual(unzip.sublist(0, utf8Bom.length), utf8Bom)) {
      unzip = unzip.sublist(utf8Bom.length);
    }

    final result = utf8.decode(unzip);
    return result;
  }

  static List<int> sharpZipLibDecompress(List<int> data) =>
      ZLibDecoder().convert(data);

  static List<int> hexStringToByteArray(String hexString) {
    final length = hexString.length;
    final bytes = List<int>.filled(length ~/ 2, 0);
    for (var i = 0; i < length; i += 2) {
      // PORT NOTE: C# `Convert.ToByte(hexString.Substring(i, 2), 16)`，
      bytes[i ~/ 2] = int.parse(hexString.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }

  static bool _sequenceEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
