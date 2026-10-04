// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/MatchHelpers/ArtistMatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
library;

import '../../../helpers/general/chinese_helper.dart';


  /// 比较艺人匹配程度
  /// @param artist1 原曲目的艺人
  /// @param artist2 搜索得到的曲目的艺人
  /// @returns 艺人匹配程度
ArtistMatchType? compareArtist(List<String>? artist1, List<String>? artist2) {
  if (artist1 == null || artist2 == null) return null;

  final list1 =
      artist1.where((artist) => !artist.isNullOrWhiteSpace).toList();
  final list2 =
      artist2.where((artist) => !artist.isNullOrWhiteSpace).toList();
  if (list1.isEmpty || list2.isEmpty) return null;

  for (var i = 0; i < list1.length; i++) {
    list1[i] = ChineseHelper.toSC(list1[i].toLowerCase(), true);
  }
  for (var i = 0; i < list2.length; i++) {
    list2[i] = ChineseHelper.toSC(list2[i].toLowerCase(), true);
  }

  var count = 0;
  for (final art in list2) {
    if (list1.contains(art)) count++;
  }

  if (count == list1.length && list1.length == list2.length) {
    return ArtistMatchType.perfect;
  }

  if ((count + 1 >= list1.length && list1.length >= 2) ||
      (list1.length > 6 && count / list1.length > 0.8)) {
    return ArtistMatchType.veryHigh;
  }

  if (count == 1 && list1.length == 1 && list2.length == 2) {
    return ArtistMatchType.high;
  }

  if (list1.length > 5 &&
      (list2[0].contains('Various') || list2[0].contains('群星'))) {
    return ArtistMatchType.veryHigh;
  }

  if (list1.length > 7 && list2.length > 7 && count / list1.length > 0.66) {
    return ArtistMatchType.high;
  }

  if (list1.length == 1 && list2.length > 1 && list1[0].startsWith(list2[0])) {
    return ArtistMatchType.high;
  }

  if (list1.length == 1 &&
      list2.length > 1 &&
      list2[0].length > 3 &&
      list1[0].contains(list2[0])) {
    return ArtistMatchType.high;
  }

  if (list1.length == 1 &&
      list2.length > 1 &&
      list2[0].length > 1 &&
      list1[0].contains(list2[0])) {
    return ArtistMatchType.medium;
  }

  if (count == 1 && list1.length == 1 && list2.length >= 3) {
    return ArtistMatchType.medium;
  }

  if (count >= 2) return ArtistMatchType.low;

  return ArtistMatchType.noMatch;
}

  /// 艺人匹配程度
enum ArtistMatchType {
  perfect,
  veryHigh,
  high,
  medium,
  low,
  noMatch(-1);

  const ArtistMatchType([this.value]);

  final int? value;
}

extension ArtistMatchTypeScore on ArtistMatchType {
  int get matchScore {
    switch (this) {
      case ArtistMatchType.perfect:
        return 7;
      case ArtistMatchType.veryHigh:
        return 6;
      case ArtistMatchType.high:
        return 5;
      case ArtistMatchType.medium:
        return 4;
      case ArtistMatchType.low:
        return 2;
      case ArtistMatchType.noMatch:
        return 0;
    }
  }
}

/// 艺人匹配程度得分
int matchScoreOfArtist(ArtistMatchType? matchType) =>
    matchType?.matchScore ?? 0;


/// C# 的 `string.IsNullOrWhiteSpace` 移植：null、空串、纯空白都算空。
extension StringNullWhitespace on String? {
  bool get isNullOrWhiteSpace =>
      this == null || this!.trim().isEmpty;
}
