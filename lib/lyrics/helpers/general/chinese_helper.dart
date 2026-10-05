// Ported from Lyricify.Lyrics.Helper/Helpers/General/ChineseHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `Microsoft.International.Converters.TraditionalChineseToSimplifiedConverter.ChineseConverter`
//                                     `ChineseConverter.convertToXxxChinese`；
//
library;

import 'chinese_converter_tables.dart';

class ChineseHelper {
  /// Simplified Chinese to Traditional Chinese
  static String s2T(String? text) {
    if (text == null) return '';
    return ChineseConverter.convertToTraditionalChinese(text);
  }

  /// Traditional Chinese to Simplified Chinese
  static String t2S(String? text) {
    if (text == null) return '';
    return ChineseConverter.convertToSimplifiedChinese(text);
  }

  /// Simplified Chinese to Traditional Chinese
  ///
  static String s2TInPlace(String? text) {
    if (text == null) return '';
    return s2T(text);
  }

  /// Traditional Chinese to Simplified Chinese
  ///
  static String t2SInPlace(String? text) {
    if (text == null) return '';
    return t2S(text);
  }

  /// Simplified Chinese to Traditional Chinese
  ///
  /// `ChineseHelper.toTC(text, force)`。
  static String toTC(String? text, [bool force = false]) {
    if (text == null) return '';
    if (force) text = s2T(text);
    return ChineseConverter.convertToTraditionalChinese(text);
  }

  /// Traditional Chinese to Simplified Chinese
  ///
  static String toSC(String? text, [bool force = false]) {
    if (text == null) return '';
    if (!force) return ChineseConverter.convertToSimplifiedChinese(text);
    // PERF: the original ran `t2S(text)` and then *unconditionally* ran
    // `convertToSimplifiedChinese` again on the result, i.e. two full
    // dictionary passes per call. `convertToSimplifiedChinese` is idempotent
    // (verified exhaustively over every BMP code unit: C(C(c)) == C(c) for all
    // 65503 of them, and the four force-only replacements below cannot
    // reintroduce a convertible character), so the second pass is a no-op and
    // the result is bit-for-bit identical.
    return t2S(text)
        .replaceAll('藉', '借')
        .replaceAll('咀', '嘴')
        .replaceAll('昇', '升')
        .replaceAll('髒', '脏');
  }

  static bool isTraditional(String? text) {
    if (text == null) return false;
    final sc = toSC(text);
    final length = text.length < sc.length ? text.length : sc.length;
    for (var i = 0; i < length; i++) {
      final cu = text.codeUnitAt(i);
      if (cu >= 0x4e00 && cu <= 0x9fff && text[i] != sc[i]) return true;
    }
    return false;
  }
}

class ChineseConverter {
  static Map<int, String>? _chsToChtDict;
  static Map<int, String>? _chtToChsDict;

  static String convertToSimplifiedChinese(String? str) {
    _ensureDictionary();
    return _convertByDictionary(str, _chtToChsDict!);
  }

  static String convertToTraditionalChinese(String? str) {
    _ensureDictionary();
    return _convertByDictionary(str, _chsToChtDict!);
  }

  static String _convertByDictionary(String? str, Map<int, String> dict) {
    if (str == null || str.isEmpty) return '';

    final info = _parseTextElementStarts(str);
    if (info.length < 2) {
      if (str.length == info.length) {
        final resChar = dict[str.codeUnitAt(0)];
        if (resChar != null) {
          return resChar;
        }
      }
      return str;
    }

    final sb = StringBuffer();

    for (var i = 0; i < info.length; i++) {
      final startIdx = info[i];
      int length;

      if (i != info.length - 1) {
        length = info[i + 1] - startIdx;
      } else {
        length = str.length - startIdx;
      }

      if (length == 1) {
        final oriChar = str[startIdx];
        final resChar = dict[str.codeUnitAt(startIdx)];
        if (resChar != null) {
          sb.write(resChar);
        } else {
          sb.write(oriChar);
        }
      } else {
        sb.write(str.substring(startIdx, startIdx + length));
      }
    }

    return sb.toString();
  }

  static void _ensureDictionary() {
    if (_chsToChtDict != null && _chtToChsDict != null) return;

    if (kChsWord.length != kChtWord.length) {
      throw ArgumentError('kChsWord / kChtWord 长度不一致');
    }

    final chsToCht = <int, String>{};
    final chtToChs = <int, String>{};
    for (var i = 0; i < kChsWord.length; i++) {
      chsToCht.putIfAbsent(kChsWord.codeUnitAt(i), () => kChtWord[i]);
      chtToChs.putIfAbsent(kChtWord.codeUnitAt(i), () => kChsWord[i]);
    }
    _chsToChtDict = chsToCht;
    _chtToChsDict = chtToChs;
  }

  static List<int> _parseTextElementStarts(String str) {
    final starts = <int>[];
    var i = 0;
    while (i < str.length) {
      starts.add(i);
      var j = i + 1;
      final cu = str.codeUnitAt(i);
      if (cu >= 0xD800 && cu <= 0xDBFF && j < str.length) {
        final lo = str.codeUnitAt(j);
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          j++;
        }
      }
      while (j < str.length && _isCombiningMark(str.codeUnitAt(j))) {
        j++;
      }
      i = j;
    }
    return starts;
  }

  static bool _isCombiningMark(int cu) =>
      (cu >= 0x0300 && cu <= 0x036F) || // Combining Diacritical Marks
      (cu >= 0x0483 && cu <= 0x0489) || // Cyrillic
      (cu >= 0x0591 && cu <= 0x05BD) ||
      (cu >= 0x0610 && cu <= 0x061A) ||
      (cu >= 0x064B && cu <= 0x065F) ||
      (cu >= 0x0670 && cu <= 0x0670) ||
      (cu >= 0x06D6 && cu <= 0x06DC) ||
      (cu >= 0x0900 && cu <= 0x0903) ||
      (cu >= 0x1AB0 && cu <= 0x1AFF) || // Combining Diacritical Marks Extended
      (cu >= 0x1DC0 && cu <= 0x1DFF) || // Combining Diacritical Marks Supplement
      (cu >= 0x20D0 && cu <= 0x20FF) || // Combining Diacritical Marks for Symbols
      (cu >= 0xFE00 && cu <= 0xFE0F) || // Variation Selectors
      (cu >= 0xFE20 && cu <= 0xFE2F) || // Combining Half Marks
      (cu >= 0x1F3FB && cu <= 0x1F3FF) || // Emoji Modifier Fitzpatrick (肤色)
      (cu == 0x200D); // Zero Width Joiner
}
