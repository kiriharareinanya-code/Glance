// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/Decrypter.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
/// `List&lt;List&lt;List&lt;int&gt;&gt;&gt;` / `List&lt;List&lt;int&gt;&gt;`。
library;

import 'dart:convert';
import 'dart:io';

import 'des_helper.dart';

/// Top-level entry point so `compute()` can ship this to another isolate.
///
/// `compute` requires a **top-level or static** function that can cross an
/// isolate boundary: a closure or a bound method that captures state cannot.
/// [Decrypter.decryptLyrics] is pure and its `(String) -> String?` signature is
/// entirely sendable, so a one-line top-level forwarder is all it takes.
/// This file deliberately stays free of any `package:flutter` import so the
/// decrypter remains usable from plain Dart.
String? decryptQrcLyrics(String encryptedLyrics) =>
    Decrypter.decryptLyrics(encryptedLyrics);

class Decrypter {
  static final List<int> qqKey = ascii.encode(r'!@#)(*$%123ZXC!@!@#)(NHL');

  /// PERF: the 3DES key schedule is a pure function of [qqKey], and
  /// [DESHelper.tripleDESCrypt] only ever *reads* it. Rebuilding the
  /// 3 x 16 x 6 schedule (49 list allocations plus ~2300 bit permutations)
  /// on every decrypt is pure waste, so build it once, lazily.
  static final List<List<List<int>>> _qqKeySchedule = _buildQqKeySchedule();

  static List<List<List<int>>> _buildQqKeySchedule() {
    final schedule = <List<List<int>>>[];
    for (var i = 0; i < 3; i++) {
      final layer = <List<int>>[];
      for (var j = 0; j < 16; j++) {
        layer.add(List<int>.filled(6, 0));
      }
      schedule.add(layer);
    }
    DESHelper.tripleDESKeySetup(qqKey, schedule, DESHelper.decrypt);
    return schedule;
  }

  /// 解密 QRC 歌词
  /// @param encryptedLyrics 加密的歌词
  /// @returns 解密后的 QRC 歌词
  static String? decryptLyrics(String encryptedLyrics) {
    final encryptedTextByte = hexStringToByteArray(encryptedLyrics);
    final data = List<int>.filled(encryptedTextByte.length, 0);
    final schedule = _qqKeySchedule;

    // PERF: the old loop allocated `List<int>.filled(8, 0)` (the output) *and*
    // `encryptedTextByte.sublist(i)` (the input) for every 8-byte block, i.e.
    // 2 lists per block -> up to 20k allocations for a 80 kB payload. Both are
    // now hoisted out of the loop and reused; the block copy is 8 int writes.
    final blockIn = List<int>.filled(8, 0);
    final blockOut = List<int>.filled(8, 0);
    for (var i = 0; i < encryptedTextByte.length; i += 8) {
      for (var j = 0; j < 8; j++) {
        blockIn[j] = encryptedTextByte[i + j];
      }
      DESHelper.tripleDESCrypt(blockIn, blockOut, schedule);
      for (var j = 0; j < 8; j++) {
        data[i + j] = blockOut[j];
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
