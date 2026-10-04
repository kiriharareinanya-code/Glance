// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/NameMatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
library;

import '../../../helpers/general/chinese_helper.dart';
import '../../../helpers/general/string_helper.dart';

  /// 比较曲目名或专辑名匹配程度
  /// @param name1 原曲目名
  /// @param name2 搜索得到的曲目名
  /// @returns 名称匹配程度
NameMatchType? compareName(String? name1, String? name2) {
  if (isNullOrWhiteSpace(name1) || isNullOrWhiteSpace(name2)) return null;

  String? normalizeName(String? name) {
    return StringHelper.removeDuoSpaces(ChineseHelper.toSC(name, true)
        .toLowerCase()
        .trim()
        .replaceAll('’', "'")
        .replaceAll('，', ',')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('[', '(')
        .replaceAll(']', ')'))
        .replaceAll(' (', '(')
        .replaceAll('( ', '(')
        .replaceAll(' )', ')');
  }

  name1 = normalizeName(name1) ?? '';
  name2 = normalizeName(name2) ?? '';

  // 伴奏/纯音乐不是"歌"：同一首歌的伴奏版常常和原歌标题几乎一样，
  // 反而比"中文译名"的真人唱版更像（实测《昔涟》只得 medium，
  // 而「昔涟 (中文和声伴奏)」「Ripples of Past Reverie (英文和声伴奏)」
  // 都拿到 veryHigh）。这里先摘掉这些标记再比，并降档处理。
  String stripInstrumental(String s) => s
      .replaceAll(RegExp(r'\((?:[^()]*)(?:伴奏|纯音乐|纯乐曲| instrumental| inst| off vocal| no vocals| karaoke)[^()]*\)'), '')
      .replaceAll(RegExp(r'\[[^\[\]]*(?:伴奏|纯音乐| instrumental)[^\[\]]*\]'), '')
      .replaceAll(RegExp(r'伴奏版|纯音乐版| instrumental version'), '')
      .trim();

  final orig1 = name1;
  final orig2 = name2;
  name1 = normalizeName(stripInstrumental(name1)) ?? '';
  name2 = normalizeName(stripInstrumental(name2)) ?? '';
  final strippedAny = (name1 != normalizeName(orig1)) ||
      (name2 != normalizeName(orig2));

  if (name1 == name2) {
    // 至少一方是伴奏版时降档：伴奏不是我们要的歌词来源
    return strippedAny ? NameMatchType.high : NameMatchType.perfect;
  }

  name1 = name1.replaceAll('acoustic version', 'acoustic');
  name2 = name2.replaceAll('acoustic version', 'acoustic');

  if ('${name1.replaceAll(' - ', ' (').trim()})'.replaceAll(' ', '') ==
      '${name2.replaceAll(' - ', ' (').trim()})'.replaceAll(' ', '')) {
    return NameMatchType.veryHigh;
  }

  bool specialCompare(String str1, String str2, String special) {
    special = '($special';
    final c1 = str1.contains(special);
    final c2 = str2.contains(special);
    if (c1 && !c2 && str1.substring(0, str1.indexOf(special)).trim() == str2) {
      return true;
    }
    if (c2 && !c1 && str2.substring(0, str2.indexOf(special)).trim() == str1) {
      return true;
    }
    return false;
  }

  bool singleSpecialCompare(String str1, String str2, String special) {
    special = '($special';
    if (str1.contains(special) &&
        str2.contains(special) &&
        str1.substring(0, str1.indexOf(special)).trim() ==
            str2.substring(0, str2.indexOf(special)).trim()) {
      return true;
    }
    return false;
  }

  bool duoSpecialCompare(
      String str1, String str2, String special1, String special2) {
    special1 = '($special1';
    special2 = '($special2';
    if (str1.contains(special1) &&
        str2.contains(special2) &&
        str1.substring(0, str1.indexOf(special1)).trim() ==
            str2.substring(0, str2.indexOf(special2)).trim()) {
      return true;
    }
    if (str1.contains(special2) &&
        str2.contains(special1) &&
        str1.substring(0, str1.indexOf(special2)).trim() ==
            str2.substring(0, str2.indexOf(special1)).trim()) {
      return true;
    }
    return false;
  }

  bool bracketsCompare(String str1, String str2) {
    if (str1.contains('(') &&
        !str2.contains('(') &&
        str1.substring(0, str1.indexOf('(')).trim() == str2) {
      return true;
    }
    if (str2.contains('(') &&
        !str1.contains('(') &&
        str2.substring(0, str2.indexOf('(')).trim() == str1) {
      return true;
    }
    return false;
  }

  if (specialCompare(name1, name2, 'deluxe')) return NameMatchType.veryHigh;
  if (specialCompare(name1, name2, 'explicit')) return NameMatchType.veryHigh;
  if (specialCompare(name1, name2, 'special edition')) {
    return NameMatchType.veryHigh;
  }
  if (specialCompare(name1, name2, 'bonus track')) {
    return NameMatchType.veryHigh;
  }
  if (specialCompare(name1, name2, 'feat')) return NameMatchType.veryHigh;
  if (specialCompare(name1, name2, 'with')) return NameMatchType.veryHigh;

  if (duoSpecialCompare(name1, name2, 'feat', 'explicit')) {
    return NameMatchType.high;
  }
  if (duoSpecialCompare(name1, name2, 'with', 'explicit')) {
    return NameMatchType.high;
  }
  if (singleSpecialCompare(name1, name2, 'feat')) return NameMatchType.high;
  if (singleSpecialCompare(name1, name2, 'with')) return NameMatchType.high;

  if (bracketsCompare(name1, name2)) return NameMatchType.medium;

  var count = 0;
  if (name1.length == name2.length) {
    for (var i = 0; i < name1.length; i++) {
      if (name1[i] == name2[i]) count++;
    }

    if ((count / name1.length >= 0.8 && name1.length >= 4) ||
        (count / name1.length >= 0.5 &&
            name1.length >= 2 &&
            name1.length <= 3)) {
      return NameMatchType.high;
    }
  }

  NameMatchType result;
  final sim = StringHelper.computeTextSame(name1, name2, true);
  if (sim > 90) {
    result = NameMatchType.veryHigh;
  } else if (sim > 80) {
    result = NameMatchType.high;
  } else if (sim > 68) {
    result = NameMatchType.medium;
  } else if (sim > 55) {
    result = NameMatchType.low;
  } else {
    result = NameMatchType.noMatch;
  }

  // 伴奏/纯音乐统一降一档。
  //
  // 为什么必须在出口做：伴奏版的标题往往**和原歌几乎完全一致**
  // （《Ripples of Past Reverie (英文和声伴奏)》vs 原歌），而真人唱的中文
  // 译名版（《昔涟》）和英文原名毫无字面关联，只能拿到 medium。逐条比较
  // 的话伴奏版永远赢，而它的歌词只有「纯音乐，请欣赏」一行。
  if (result != NameMatchType.noMatch &&
      (_isInstrumental(orig1) || _isInstrumental(orig2))) {
    result = _downgrade(result);
  }
  return result;
}

final _instrumentalRe = RegExp(
    r'(伴奏|纯音乐|纯乐曲| instrumental|inst|off vocal|no vocals|karaoke|伴奏版)',
    caseSensitive: false);

bool _isInstrumental(String s) => _instrumentalRe.hasMatch(s);

/// 降一档（noMatch 保持不变）。
NameMatchType _downgrade(NameMatchType t) {
  switch (t) {
    case NameMatchType.perfect:
      return NameMatchType.veryHigh;
    case NameMatchType.veryHigh:
      return NameMatchType.high;
    case NameMatchType.high:
      return NameMatchType.medium;
    case NameMatchType.medium:
      return NameMatchType.low;
    case NameMatchType.low:
    case NameMatchType.noMatch:
      return NameMatchType.noMatch;
  }
}

  /// 名称匹配程度
enum NameMatchType {
  perfect,
  veryHigh,
  high,
  medium,
  low,
  noMatch(-1);

  const NameMatchType([this.value]);

  final int? value;
}

extension NameMatchTypeScore on NameMatchType {
  int get matchScore {
    switch (this) {
      case NameMatchType.perfect:
        return 7;
      case NameMatchType.veryHigh:
        return 6;
      case NameMatchType.high:
        return 5;
      case NameMatchType.medium:
        return 4;
      case NameMatchType.low:
        return 2;
      case NameMatchType.noMatch:
        return 0;
    }
  }
}

/// 名称匹配程度得分
int matchScoreOfName(NameMatchType? matchType) => matchType?.matchScore ?? 0;

/// C# `string.IsNullOrWhiteSpace(string?)`。
bool isNullOrWhiteSpace(String? value) =>
    value == null || value.trim().isEmpty;
