// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/AppleMusic.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   `StringBuilder` → `StringBuffer`（`sb.Length` → `sb.length`，`sb.Clear()` → `sb.clear()`）。
//   `char.IsWhiteSpace` / `char.IsLetterOrDigit` / `char.IsLetter` / `char.IsUpper` /
//     [_isUpper] / [_isLower] / [_isLetter]。
//
//   `PrepareLyrics(List<ILineInfo>)` → [prepareLyricsList]
//   `PrepareLyrics(ILineInfo)`       → [prepareLyrics]
//
library;

import '../../models/line_info.dart';
import '../../models/syllable_info.dart';
import 'syllable_word_merger.dart';

class AppleMusic {
  AppleMusic._();

  // =========================
  // Prepare Lyrics
  // =========================

  static void prepareLyricsList(List<LineInfo> list) {
    if (list.isEmpty) return;

    for (final line in list) {
      prepareLyrics(line);
    }
  }

  static void prepareLyrics(LineInfo line) {
    if (line is SyllableLineInfo) {
      _prepareSyllableLyrics(line);
    }

    final sub = line.subLine;
    if (sub is SyllableLineInfo) {
      _prepareSyllableLyrics(sub);
    }

    _removeRedundantTranslations(line, isBackground: false);
    if (sub != null) {
      _removeRedundantTranslations(sub, isBackground: true);
    }
  }

  static void _prepareSyllableLyrics(SyllableLineInfo line) {
    if (line.syllables.isEmpty) return;

    _trimBoundaryWhitespaces(line);

    // Step 1: expand/split within a syllable
    final expanded = <SyllableInfo>[];

    for (final s in line.syllables) {
      final text = _normalizeText(s.text);

      if (text.isEmpty) {
        expanded.add(TextSyllableInfo('', s.startTime, s.endTime));
        continue;
      }

      if (_shouldSplitToken(text)) {
        for (final part in _splitIntoTokens(text, s.startTime, s.endTime)) {
          expanded.add(part);
        }
      } else {
        expanded.add(TextSyllableInfo(text, s.startTime, s.endTime));
      }
    }

    // Step 2: merge consecutive syllables into one word via FullSyllableInfo.SubItems
    line.syllables = expanded;
    SyllableWordMerger.merge(line);
  }

  static void _removeRedundantTranslations(LineInfo line, {required bool isBackground}) {
    //
    Map<String, String>? translations;
    if (line is FullLineInfoMixin) {
      translations = line.translations;
    }

    if (translations == null || translations.isEmpty) return;

    final original = line.text;
    final originalNorm = _normalizeForCompare(original, isBackground);

    final toRemove = <String>[];

    for (final kv in translations.entries) {
      final transNorm = _normalizeForCompare(kv.value, isBackground);

      if (originalNorm == transNorm) {
        toRemove.add(kv.key);
      }
    }

    for (final key in toRemove) {
      translations.remove(key);
    }
  }

  static String _normalizeForCompare(String s, bool isBackground) {
    if (s.isEmpty) return '';

    s = s.replaceAll('\r', '').replaceAll('\n', '');
    s = _collapseSpaces(s.trim());

    if (!isBackground) return s;

    s = _stripOuterBracketsIfWrapped(s);

    s = _collapseSpaces(s.trim());
    return s;
  }

  static String _collapseSpaces(String s) {
    if (s.isEmpty) return '';

    final sb = StringBuffer();
    var prevWs = false;

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (SyllableWordMerger.isWhiteSpace(ch)) {
        if (!prevWs) {
          sb.write(' ');
          prevWs = true;
        }
      } else {
        sb.write(ch);
        prevWs = false;
      }
    }

    return sb.toString().trim();
  }

  static String _stripOuterBracketsIfWrapped(String s) {
    if (s.length < 2) return s;

    final half = s[0] == '(' && s[s.length - 1] == ')';
    final full = s[0] == '（' && s[s.length - 1] == '）';

    if (half || full) {
      return s.substring(1, s.length - 1).trim();
    }

    return s;
  }

  static void _trimBoundaryWhitespaces(SyllableLineInfo line) {
    final syllables = line.syllables;
    if (syllables.isEmpty) return;

    // ---- TrimStart on first syllable ----
    syllables[0] = _trimStartSafe(syllables[0]);

    // ---- TrimEnd on last syllable ----
    final last = syllables.length - 1;
    syllables[last] = _trimEndSafe(syllables[last]);
  }

  static SyllableInfo _trimStartSafe(SyllableInfo s) {
    if (s is TextSyllableInfo) {
      final text = s.text.trimLeft();
      if (text == s.text) return s;

      return TextSyllableInfo(text, s.startTime, s.endTime);
    }

    if (s is FullSyllableInfo && s.subItems.isNotEmpty) {
      final first = s.subItems[0];
      final trimmed = first.text.trimLeft();

      if (trimmed != first.text) {
        s.subItems[0] =
            TextSyllableInfo(trimmed, first.startTime, first.endTime);
        s.refreshProperties();
      }
      return s;
    }

    return s;
  }

  static SyllableInfo _trimEndSafe(SyllableInfo s) {
    if (s is TextSyllableInfo) {
      final text = s.text.trimRight();
      if (text == s.text) return s;

      return TextSyllableInfo(text, s.startTime, s.endTime);
    }

    if (s is FullSyllableInfo && s.subItems.isNotEmpty) {
      final last = s.subItems.length - 1;
      final item = s.subItems[last];
      final trimmed = item.text.trimRight();

      if (trimmed != item.text) {
        s.subItems[last] =
            TextSyllableInfo(trimmed, item.startTime, item.endTime);
        s.refreshProperties();
      }
      return s;
    }

    return s;
  }

  // =========================
  // Split rules
  // =========================

  static bool _shouldSplitToken(String text) {
    var zhja = 0;
    var hasLatin = false;
    var hasSpace = false;
    var hasHyphen = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ') hasSpace = true;
      if (ch == '-') hasHyphen = true;

      if (SyllableWordMerger.isChineseOrJapaneseCharacter(ch)) {
        zhja++;
      } else if (_isLatinWordChar(ch)) {
        hasLatin = true;
      }
    }

    if (zhja >= 2) return true;
    if (zhja >= 1 && hasLatin) return true;
    if (hasLatin && (hasSpace || hasHyphen)) return true;

    return false;
  }

  static List<TextSyllableInfo> _splitIntoTokens(
    String text,
    int startTime,
    int endTime,
  ) {
    final tokens = _tokenizeMixed(text);

    if (tokens.length <= 1) {
      return <TextSyllableInfo>[TextSyllableInfo(text, startTime, endTime)];
    }

    final weights = tokens.map(_tokenWeight).toList();
    var wSum = weights.fold<int>(0, (sum, w) => sum + w);
    if (wSum <= 0) wSum = tokens.length;

    final total = endTime - startTime;
    if (total <= 0) {
      return <TextSyllableInfo>[
        for (final t in tokens) TextSyllableInfo(t, startTime, endTime),
      ];
    }

    final result = <TextSyllableInfo>[];
    var allocated = 0;
    var curStart = startTime;

    for (var i = 0; i < tokens.length; i++) {
      int dur;
      if (i == tokens.length - 1) {
        dur = total - allocated;
      } else {
        dur = (total * (weights[i] / wSum)).round();
        if (dur < 1) dur = 1;

        final minRemain = tokens.length - 1 - i;
        if (allocated + dur > total - minRemain) {
          dur = total - allocated - minRemain;
        }
      }

      final curEnd = curStart + dur;
      allocated += dur;

      result.add(TextSyllableInfo(tokens[i], curStart, curEnd));
      curStart = curEnd;
    }

    return result;
  }

  /// Tokenize with "separators belong to previous token":
  /// - space ' ' appended to previous token and ends token => "word "
  /// - hyphen '-' appended to previous token and ends token => "Ooh-"
  /// - Zh/Ja split char => each char as token
  /// - Latin word => grouped
  /// - Others (including Hangul) => attach to current token if exists, else attach to previous token if any
  static List<String> _tokenizeMixed(String text) {
    final tokens = <String>[];
    final sb = StringBuffer();

    void flush() {
      if (sb.length > 0) {
        tokens.add(sb.toString());
        sb.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      final ch = text[i];

      if (ch == '\r' || ch == '\n') {
        i++;
        continue;
      }

      // Zh/Ja: per char token
      if (SyllableWordMerger.isChineseOrJapaneseCharacter(ch)) {
        flush();
        tokens.add(ch);
        i++;
        continue;
      }

      // space -> belongs to previous token end
      if (ch == ' ') {
        if (sb.length > 0) {
          sb.write(' ');
          flush();
        } else if (tokens.isNotEmpty) {
          tokens[tokens.length - 1] += ' ';
        } else {
          sb.write(' ');
        }
        i++;
        continue;
      }

      // hyphen -> belongs to previous token end, and boundary
      if (ch == '-') {
        if (sb.length > 0) {
          sb.write('-');
          flush();
        } else if (tokens.isNotEmpty) {
          tokens[tokens.length - 1] += '-';
        } else {
          sb.write('-');
        }
        i++;
        continue;
      }

      // Latin word chunk
      if (_isLatinWordChar(ch)) {
        sb.write(ch);
        i++;

        while (i < text.length) {
          final c2 = text[i];
          if (c2 == '\r' || c2 == '\n') {
            i++;
            continue;
          }
          if (_isLatinWordChar(c2)) {
            sb.write(c2);
            i++;
            continue;
          }
          break;
        }
        continue;
      }

      // other chars (punctuation / Hangul / emoji ...)
      if (sb.length > 0) {
        sb.write(ch);
      } else if (tokens.isNotEmpty) {
        // prefer attach to previous token (separator-to-previous style)
        tokens[tokens.length - 1] += ch;
      } else {
        sb.write(ch);
      }

      i++;
    }

    flush();

    return tokens.where((t) => t.isNotEmpty).toList();
  }

  static int _tokenWeight(String token) {
    for (var i = 0; i < token.length; i++) {
      if (SyllableWordMerger.isChineseOrJapaneseCharacter(token[i])) return 1;
    }

    var w = 0;
    for (var i = 0; i < token.length; i++) {
      if (SyllableWordMerger.isLetterOrDigit(token[i])) w++;
    }
    return w > 1 ? w : 1;
  }

  // =========================
  // Char classification
  // =========================

  static bool _isLatinWordChar(String ch) {
    if (SyllableWordMerger.isLetterOrDigit(ch)) return true;
    return ch == "'" || ch == '’';
  }

  static String _normalizeText(String text) =>
      text.replaceAll('\r', '').replaceAll('\n', '');

  // =========================
  // Capitalization Normalization
  // =========================

  static void capitalizationNormalization(List<LineInfo> list) {
    if (list.isEmpty) return;

    // 1) line-by-line classification
    var lowerLines = 0;
    var upperLines = 0;
    var otherLines = 0; // mixed-case or no-letter lines

    void countLine(String? text) {
      final kind = _getLineCaseKind(text);
      switch (kind) {
        case _LineCaseKind.allLower:
          lowerLines++;
          break;
        case _LineCaseKind.allUpper:
          upperLines++;
          break;
        default:
          otherLines++;
          break;
      }
    }

    for (var i = 0; i < list.length; i++) {
      final line = list[i];

      countLine(line.text);

      if (line.subLine != null) {
        countLine(line.subLine!.text);
      }
    }

    final totalLines = lowerLines + upperLines + otherLines;
    if (totalLines == 0) return;

    final lowerRatio = lowerLines / totalLines;
    final upperRatio = upperLines / totalLines;

    const threshold = 0.9;

    bool doLowerCaseFirst;
    if (upperRatio >= threshold) {
      doLowerCaseFirst = true; // mostly ALL-UPPER -> lower first
    } else if (lowerRatio >= threshold) {
      doLowerCaseFirst = false; // mostly ALL-lower -> sentence-cap only
    } else {
      // Not “mostly uniform” -> do nothing (optional: still fix standalone "i")
      // If you want, uncomment the next loop to always fix standalone i:
      /*
      for (int i = 0; i < list.Count; i++)
          list[i] = ApplyStandaloneIFix(list[i]);
      */
      return;
    }

    // 2) apply normalization to all lines (main + sub)
    for (var i = 0; i < list.length; i++) {
      list[i] = _applyCapitalization(list[i], doLowerCaseFirst);
    }
  }

  static _LineCaseKind _getLineCaseKind(String? s) {
    if (s == null || s.isEmpty) return _LineCaseKind.noLettersOrMixed;

    var hasUpper = false;
    var hasLower = false;
    var hasLetter = false;

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (!_isLetter(ch)) continue;

      hasLetter = true;
      if (_isUpper(ch)) {
        hasUpper = true;
      } else if (_isLower(ch)) {
        hasLower = true;
      }

      if (hasUpper && hasLower) return _LineCaseKind.noLettersOrMixed;
    }

    if (!hasLetter) return _LineCaseKind.noLettersOrMixed;
    if (hasUpper && !hasLower) return _LineCaseKind.allUpper;
    if (hasLower && !hasUpper) return _LineCaseKind.allLower;

    return _LineCaseKind.noLettersOrMixed;
  }

  static LineInfo _applyCapitalization(LineInfo line, bool lowerFirst) {
    // main
    final updated = _applyCapitalizationMainOnly(line, lowerFirst);

    // sub
    if (updated.subLine != null) {
      final sub = _applyCapitalizationMainOnly(updated.subLine!, lowerFirst);

      updated.subLine = sub;
    }

    return updated;
  }

  static LineInfo _applyCapitalizationMainOnly(LineInfo line, bool lowerFirst) {
    // syllable line
    if (line is SyllableLineInfo && line.syllables.isNotEmpty) {
      _applyCapitalizationToSyllables(line, lowerFirst);
      return line;
    }

    final text = line.text;
    if (text.isEmpty) return line;

    final normalized = _normalizeSentenceCasePreserveLength(text, lowerFirst);

    // mutable common types
    //
    if (line is TextLineInfo) {
      line.text = normalized;
      return line;
    }

    // fallback replace (keep timing/alignment/subline best-effort)
    final repl = TextLineInfo(
      normalized,
      line.startTime,
      line.endTime,
    )
      ..lyricsAlignment = line.lyricsAlignment
      ..subLine = line.subLine;

    if (line is FullLineInfoMixin) {
      final full = line;
      final fullRepl = FullTextLineInfo()
        ..text = repl.text
        ..startTime = repl.startTime
        ..endTime = repl.endTime
        ..lyricsAlignment = repl.lyricsAlignment
        ..subLine = repl.subLine
        ..pronunciation = full.pronunciation
        ..translations = Map<String, String>.of(full.translations);
      return fullRepl;
    }

    return repl;
  }

  static void _applyCapitalizationToSyllables(
    SyllableLineInfo line,
    bool lowerFirst,
  ) {
    final syllables = line.syllables;
    if (syllables.isEmpty) return;

    final sb = StringBuffer();
    for (var i = 0; i < syllables.length; i++) {
      sb.write(syllables[i].text);
    }

    final full = sb.toString();
    if (full.isEmpty) return;

    final normalized = _normalizeSentenceCasePreserveLength(full, lowerFirst);

    var pos = 0;
    for (var i = 0; i < syllables.length; i++) {
      final s = syllables[i];
      final oldText = s.text;
      final len = oldText.length;

      if (len <= 0) continue;
      if (pos + len > normalized.length) break;

      final part = normalized.substring(pos, pos + len);
      pos += len;

      syllables[i] = _rewriteSyllableTextPreserveStructure(s, part);
    }

    line.refreshProperties();
  }

  static SyllableInfo _rewriteSyllableTextPreserveStructure(
    SyllableInfo syllable,
    String newText,
  ) {
    if (syllable is TextSyllableInfo) {
      syllable.text = newText;
      return syllable;
    }

    if (syllable is FullSyllableInfo && syllable.subItems.isNotEmpty) {
      final sub = syllable.subItems;
      var pos = 0;

      for (var j = 0; j < sub.length; j++) {
        final t = sub[j].text;
        final len = t.length;

        if (len <= 0) continue;
        if (pos + len > newText.length) break;

        sub[j].text = newText.substring(pos, pos + len);
        pos += len;
      }

      syllable.refreshProperties();
      return syllable;
    }

    return TextSyllableInfo(newText, syllable.startTime, syllable.endTime);
  }

  static String _normalizeSentenceCasePreserveLength(
    String s,
    bool lowerFirst,
  ) {
    if (s.isEmpty) return s;

    final src = lowerFirst ? s.toLowerCase() : s;
    final sb = StringBuffer();

    var capNext = true;

    for (var i = 0; i < src.length; i++) {
      final ch = src[i];

      // optional: always fix standalone i -> I (safe, length-preserving)
      if (ch == 'i' && _isStandaloneI(src, i)) {
        sb.write('I');
        capNext = false;
        continue;
      }

      if (_isLetter(ch)) {
        if (capNext) {
          sb.write(_toUpperInvariant(ch));
          capNext = false;
        } else {
          sb.write(ch);
        }
      } else {
        sb.write(ch);
      }

      if (ch == '.' ||
          ch == '?' ||
          ch == '!' ||
          ch == '。' ||
          ch == '？' ||
          ch == '！') {
        capNext = true;
      }
    }

    return sb.toString();
  }

  static bool _isStandaloneI(String s, int index) {
    final leftOk = index == 0 || !_isLetter(s[index - 1]);
    final rightOk = index == s.length - 1 || !_isLetter(s[index + 1]);
    return leftOk && rightOk;
  }

  ///
  static bool _isLetter(String ch) {
    if (ch.isEmpty) return false;
    if (_isUpper(ch) || _isLower(ch)) return true;

    final cu = ch.codeUnitAt(0);
    return (cu >= 0x0590 && cu <= 0x05FF) || // 希伯来
        (cu >= 0x0600 && cu <= 0x06FF) || // 阿拉伯
        (cu >= 0x0E00 && cu <= 0x0E7F) || // 泰文
        (cu >= 0x3040 && cu <= 0x309F) || // 平假名
        (cu >= 0x30A0 && cu <= 0x30FF) || // 片假名
        (cu >= 0x3400 && cu <= 0x4DBF) || // CJK 扩展 A
        (cu >= 0x4E00 && cu <= 0x9FFF) || // CJK
        (cu >= 0xAC00 && cu <= 0xD7A3) || // 韩文音节
        (cu >= 0xF900 && cu <= 0xFAFF); // CJK 兼容
  }

  static bool _isUpper(String ch) {
    if (ch.isEmpty) return false;
    final upper = ch.toUpperCase();
    final lower = ch.toLowerCase();
    return upper == ch && lower != ch;
  }

  static bool _isLower(String ch) {
    if (ch.isEmpty) return false;
    final upper = ch.toUpperCase();
    final lower = ch.toLowerCase();
    return lower == ch && upper != ch;
  }

  ///
  static String _toUpperInvariant(String ch) {
    final upper = ch.toUpperCase();
    return upper.length == 1 ? upper : ch;
  }
}

enum _LineCaseKind {
  noLettersOrMixed,
  allLower,
  allUpper,
}
