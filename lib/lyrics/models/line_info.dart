/// Ported from Lyricify.Lyrics.Helper/Models/ILineInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
/// Ported from Lyricify.Lyrics.Helper/Models/LineInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///   LineInfo         → TextLineInfo
///   SyllableLineInfo → SyllableLineInfo
///   IFullLineInfo    → FullLineInfoMixin
///   FullLineInfo     → FullTextLineInfo
///   FullSyllableLineInfo → FullSyllableLineInfo
///
/// **为什么音节类型还留着**（逐字功能已下线）：
/// KRC/YRC/QRC/TTML 这几种逐字格式，行文本和行时间是**从音节累积出来的**
/// ——`SyllableLineInfo.text` = 拼所有音节的 text，`startTime` = 第一个音节的
/// 起点。逐字功能删掉后仍然要靠它才能把这类文件解析出正确的行内容。
/// 它现在只是解析层的**中间产物**：管线末端由
/// `SyncDowngrade.downgradeToLineSyncedList` 统一降级成 [TextLineInfo]
/// （见 `engine.dart` 的 `_optimize`），之后全流程不再有音节。
///
/// 所以这里是"解析得出来"和"用得上"两件事——前者还需要，后者已经没有了。
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

/// **仅供解析层使用**：见文件头说明。渲染层永远看不到这个类型——
/// `SyncDowngrade` 会在管线末端把它降级成 [TextLineInfo]。
class SyllableLineInfo extends LineInfo {
  // PORT NOTE（别名语义）: 上游 `LineInfo.cs:54-57` 的构造是
  // `Syllables = syllables.ToList();`——**复制**一份。这里也复制，
  // 否则调用方复用并 Clear/Remove 源 List 时，已经建好的行会被连坐清空
  // （YrcParser.cs:196/326 就是紧接着 Clear() 的那种用法）。
  SyllableLineInfo([List<SyllableInfo>? syllables])
      : syllables = syllables == null
            ? <SyllableInfo>[]
            : List<SyllableInfo>.of(syllables);

  List<SyllableInfo> syllables;

  String? _text;
  int? _startTime;
  int? _endTime;

  @override
  String get text => _text ??= SyllableHelper.getTextFromSyllableList(syllables);

  @override
  int? get startTime =>
      _startTime ??= syllables.isEmpty ? null : syllables.first.startTime;

  // PORT NOTE（空音节）: 上游 `ILineInfo`/`LineInfo.cs` 取 `Syllables.First()`，
  // 空列表会抛 InvalidOperationException。这里返回 null 而不是抛——
  // 这是本移植里**有意**的偏离：解析器会产生"有行、无音节"的行（例如 YRC 的
  // 信息行），抛异常会让整个文件解析失败。Dart 里用可空类型表达同一件事更自然。

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

/// **仅供解析层使用**，见文件头说明。
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
