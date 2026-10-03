// Ported from Lyricify.Lyrics.Helper/Parsers/Models/Yrc.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../json_utils.dart';

class CreditsInfo {
  CreditsInfo([this.timestamp = 0, List<Credit>? credits])
      : credits = credits ?? <Credit>[];

  factory CreditsInfo.fromJson(Map<String, dynamic> j) {
    final credits = <Credit>[];
    for (final item in asArr(j['c'])) {
      credits.add(Credit.fromJson(asObj(item)));
    }
    return CreditsInfo(asInt(j['t']), credits);
  }

  int timestamp;

  List<Credit> credits;
}

class Credit {
  Credit([this.text = '', this.image = '', this.orpheus = '']);

  factory Credit.fromJson(Map<String, dynamic> j) =>
      Credit(asStr(j['tx']), asStr(j['li']), asStr(j['or']));

  String text;

  String image;

  String orpheus;
}
