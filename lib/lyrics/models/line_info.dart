/// Ported from Lyricify.Lyrics.Helper/Models/ILineInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
/// Ported from Lyricify.Lyrics.Helper/Models/LineInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///   LineInfo         → TextLineInfo
///   SyllableLineInfo → SyllableLineInfo
///   IFullLineInfo    → FullLineInfoMixin
///   FullLineInfo     → FullTextLineInfo
///   FullSyllableLineInfo → FullSyllableLineInfo
library;

import '../helpers/general/math_helper.dart';
import '../helpers/general/string_helper.dart';
import 'syllable_info.dart';

enum LyricsAlignment { unspecified, left, right }

abstract class LineInfo implements Comparable<LineInfo> {
  String get text;

  int? get startTime;

  int? get endTime;

  LyricsAlignment get lyricsAlignment;

  set lyricsAlignment(LyricsAlignment value);

  LineInfo? get subLine;

  set subLine(LineInfo? value);

  int? get duration {
    final s = startTime;
    final e = endTime;
    if (s == null || e == null) return null;
    return e - s;
  }

  int? get startTimeWithSubLine => MathHelper.min(startTime, subLine?.startTime);

  int? get endTimeWithSubLine => MathHelper.max(endTime, subLine?.endTime);

  int? get durationWithSubLine {
    final s = startTimeWithSubLine;
    final e = endTimeWithSubLine;
    if (s == null || e == null) return null;
    return e - s;
  }

  String get fullText {
    final sub = subLine;
    if (sub == null) return text;

    final sb = StringBuffer();
    final subStart = sub.startTime;
    final myStart = startTime;
    if (subStart != null && myStart != null && subStart < myStart) {
      sb.write('(');
      sb.write(StringHelper.removeFrontBackBrackets(sub.text));
      sb.write(') ');
      sb.write(text.trim());
    } else {
      sb.write(text.trim());
      sb.write(' (');
      sb.write(StringHelper.removeFrontBackBrackets(sub.text));
      sb.write(')');
    }
    return sb.toString();
  }

  @override
  int compareTo(LineInfo other) {
    final a = startTime;
    final b = other.startTime;
    if (a == null || b == null) return 0;
    if (a == b) return 0;
    return a < b ? -1 : 1;
  }
}

class TextLineInfo extends LineInfo {
  TextLineInfo([this.text = '', this.startTime, this.endTime]);

  @override
  String text;

  @override
  int? startTime;

  @override
  int? endTime;

  @override
  LyricsAlignment lyricsAlignment = LyricsAlignment.unspecified;

  @override
  LineInfo? subLine;
}

class SyllableLineInfo extends LineInfo {
  SyllableLineInfo([List<SyllableInfo>? syllables])
      : syllables = syllables ?? <SyllableInfo>[];

  List<SyllableInfo> syllables;

  String? _text;
  int? _startTime;
  int? _endTime;

  @override
  String get text => _text ??= SyllableHelper.getTextFromSyllableList(syllables);

  @override
  int? get startTime =>
      _startTime ??= syllables.isEmpty ? null : syllables.first.startTime;

  @override
  int? get endTime =>
      _endTime ??= syllables.isEmpty ? null : syllables.last.endTime;

  @override
  LyricsAlignment lyricsAlignment = LyricsAlignment.unspecified;

  @override
  LineInfo? subLine;

  bool get isSyllable => syllables.isNotEmpty;

  void refreshProperties() {
    _text = null;
    _startTime = null;
    _endTime = null;
  }
}

mixin FullLineInfoMixin on LineInfo {
  Map<String, String> translations = <String, String>{};

  String? pronunciation;

  String? get chineseTranslation => translations['zh'];

  set chineseTranslation(String? value) {
    if (value == null || value.isEmpty) {
      translations.remove('zh');
    } else {
      translations['zh'] = value;
    }
  }
}

class FullTextLineInfo extends TextLineInfo with FullLineInfoMixin {
  FullTextLineInfo();

  FullTextLineInfo.fromLine(TextLineInfo lineInfo) {
    text = lineInfo.text;
    startTime = lineInfo.startTime;
    endTime = lineInfo.endTime;
    lyricsAlignment = lineInfo.lyricsAlignment;
    subLine = lineInfo.subLine;
  }
}

class FullSyllableLineInfo extends SyllableLineInfo with FullLineInfoMixin {
  FullSyllableLineInfo();

  FullSyllableLineInfo.fromLine(SyllableLineInfo lineInfo) {
    lyricsAlignment = lineInfo.lyricsAlignment;
    subLine = lineInfo.subLine;
    syllables = lineInfo.syllables;
  }

  FullSyllableLineInfo.fromLineWith({
    required SyllableLineInfo lineInfo,
    String? chineseTranslation,
    String? pronunciation,
  }) {
    lyricsAlignment = lineInfo.lyricsAlignment;
    subLine = lineInfo.subLine;
    syllables = lineInfo.syllables;
    if (chineseTranslation != null && chineseTranslation.isNotEmpty) {
      translations['zh'] = chineseTranslation;
    }
    if (pronunciation != null && pronunciation.isNotEmpty) {
      this.pronunciation = pronunciation;
    }
  }
}
