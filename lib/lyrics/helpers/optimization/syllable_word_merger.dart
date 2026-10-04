// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/SyllableWordMerger.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   `merged[^1]` → `merged[merged.length - 1]`；`SubItems.AddRange` → `List.addAll`。
library;

import '../../models/line_info.dart';
import '../../models/syllable_info.dart';

class SyllableWordMerger {
  SyllableWordMerger._();

  static void merge(SyllableLineInfo line) {
    if (line.syllables.length < 2) {
      return;
    }

    final merged = <SyllableInfo>[];
    for (final current in line.syllables) {
      if (merged.isNotEmpty &&
          _shouldMerge(merged[merged.length - 1].text, current.text)) {
        merged[merged.length - 1] = _mergeItems(
          merged[merged.length - 1],
          current,
        );
      } else {
        merged.add(current);
      }
    }

    line.syllables = merged;
    line.refreshProperties();
  }

  static bool isChineseOrJapaneseCharacter(String character) {
    if (character.isEmpty) return false;
    return _isChineseOrJapanese(character.codeUnitAt(0));
  }

  static bool isWhiteSpace(String character) {
    if (character.isEmpty) return false;
    return _isWhiteSpace(character.codeUnitAt(0));
  }

  static bool isLetterOrDigit(String character) {
    if (character.isEmpty) return false;
    return _isLetterOrDigit(character.codeUnitAt(0));
  }

  static bool _shouldMerge(String? previousText, String? currentText) {
    if (previousText == null || previousText.isEmpty) {
      return false;
    }
    if (currentText == null || currentText.isEmpty) {
      return false;
    }

    if (_isWhiteSpace(previousText.codeUnitAt(previousText.length - 1)) ||
        _isWhiteSpace(currentText.codeUnitAt(0))) {
      return false;
    }

    if (_anyChineseOrJapanese(previousText) ||
        _anyChineseOrJapanese(currentText)) {
      return false;
    }

    return _anyLetterOrDigit(previousText) && _anyLetterOrDigit(currentText);
  }

  static SyllableInfo _mergeItems(SyllableInfo previous, SyllableInfo current) {
    final currentItems = _flatten(current);
    if (previous is FullSyllableInfo) {
      previous.subItems.addAll(currentItems);
      previous.refreshProperties();
      return previous;
    }

    final items = _flatten(previous);
    items.addAll(currentItems);
    return FullSyllableInfo(items);
  }

  static List<TextSyllableInfo> _flatten(SyllableInfo item) {
    if (item is FullSyllableInfo) {
      return item.subItems
          .map((part) => TextSyllableInfo(
                part.text,
                part.startTime,
                part.endTime,
              ))
          .toList();
    }

    return <TextSyllableInfo>[
      TextSyllableInfo(item.text, item.startTime, item.endTime),
    ];
  }

  static bool _isChineseOrJapanese(int codeUnit) =>
      (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      (codeUnit >= 0x3040 && codeUnit <= 0x309F) ||
      (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) ||
      (codeUnit >= 0x31F0 && codeUnit <= 0x31FF);

  static bool _anyChineseOrJapanese(String text) {
    for (var i = 0; i < text.length; i++) {
      if (_isChineseOrJapanese(text.codeUnitAt(i))) return true;
    }
    return false;
  }

  static bool _anyLetterOrDigit(String text) {
    for (var i = 0; i < text.length; i++) {
      if (_isLetterOrDigit(text.codeUnitAt(i))) return true;
    }
    return false;
  }

  static bool _isWhiteSpace(int codeUnit) =>
      (codeUnit >= 0x0009 && codeUnit <= 0x000D) ||
      codeUnit == 0x0020 ||
      codeUnit == 0x0085 ||
      codeUnit == 0x00A0 ||
      codeUnit == 0x1680 ||
      (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
      codeUnit == 0x2028 ||
      codeUnit == 0x2029 ||
      codeUnit == 0x202F ||
      codeUnit == 0x205F ||
      codeUnit == 0x3000;

  static bool _isLetterOrDigit(int codeUnit) {
    if (codeUnit >= 0x0030 && codeUnit <= 0x0039) return true; // 0-9
    if (codeUnit >= 0x0041 && codeUnit <= 0x005A) return true; // A-Z
    if (codeUnit >= 0x0061 && codeUnit <= 0x007A) return true; // a-z
    if (codeUnit >= 0x00AA && codeUnit <= 0x00AA) return true; // ª
    if (codeUnit >= 0x00B2 && codeUnit <= 0x00B3) return true; // ²³
    if (codeUnit >= 0x00B5 && codeUnit <= 0x00B5) return true; // µ
    if (codeUnit >= 0x00B9 && codeUnit <= 0x00BA) return true; // ¹º
    if (codeUnit >= 0x00BC && codeUnit <= 0x00BE) return true; // ¼½¾
    if (codeUnit >= 0x00C0 && codeUnit <= 0x00D6) return true; // À-Ö
    if (codeUnit >= 0x00D8 && codeUnit <= 0x00F6) return true; // Ø-ö
    if (codeUnit >= 0x00F8 && codeUnit <= 0x02FF) return true; // ø-˿（含拉丁扩展 B）
    if (codeUnit >= 0x0370 && codeUnit <= 0x03FF) return true; // 希腊字母
    if (codeUnit >= 0x0400 && codeUnit <= 0x04FF) return true; // 西里尔字母
    if (codeUnit >= 0x0531 && codeUnit <= 0x058F) return true; // 亚美尼亚
    if (codeUnit >= 0x0590 && codeUnit <= 0x05FF) return true; // 希伯来
    if (codeUnit >= 0x0600 && codeUnit <= 0x06FF) return true; // 阿拉伯
    if (codeUnit >= 0x0900 && codeUnit <= 0x097F) return true; // 天城文
    if (codeUnit >= 0x0E00 && codeUnit <= 0x0E7F) return true; // 泰文
    if (codeUnit >= 0x1E00 && codeUnit <= 0x1EFF) return true; // 拉丁扩展附加
    if (codeUnit >= 0x3040 && codeUnit <= 0x309F) return true; // 平假名
    if (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) return true; // 片假名
    if (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) return true; // CJK 扩展 A
    if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) return true; // CJK
    if (codeUnit >= 0xAC00 && codeUnit <= 0xD7A3) return true; // 韩文音节
    if (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) return true; // CJK 兼容
    return false;
  }
}
