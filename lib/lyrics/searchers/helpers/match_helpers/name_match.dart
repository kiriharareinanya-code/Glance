// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/NameMatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
library;

import '../../../helpers/general/chinese_helper.dart';
import '../../../helpers/general/string_helper.dart';

///
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

  if (name1 == name2) return NameMatchType.perfect;

  name1 = name1.replaceAll('acoustic version', 'acoustic');
  name2 = name2.replaceAll('acoustic version', 'acoustic');

  if ((name1.replaceAll(' - ', ' (').trim() + ')').replaceAll(' ', '') ==
      (name2.replaceAll(' - ', ' (').trim() + ')').replaceAll(' ', '')) {
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

  if (StringHelper.computeTextSame(name1, name2, true) > 90) {
    return NameMatchType.veryHigh;
  }
  if (StringHelper.computeTextSame(name1, name2, true) > 80) {
    return NameMatchType.high;
  }
  if (StringHelper.computeTextSame(name1, name2, true) > 68) {
    return NameMatchType.medium;
  }
  if (StringHelper.computeTextSame(name1, name2, true) > 55) {
    return NameMatchType.low;
  }

  return NameMatchType.noMatch;
}

///
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

///
int matchScoreOfName(NameMatchType? matchType) => matchType?.matchScore ?? 0;

/// C# `string.IsNullOrWhiteSpace(string?)`。
bool isNullOrWhiteSpace(String? value) =>
    value == null || value.trim().isEmpty;
