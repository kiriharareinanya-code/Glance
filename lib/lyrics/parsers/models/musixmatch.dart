// Ported from Lyricify.Lyrics.Helper/Parsers/Models/Musixmatch.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

class RichSyncedLine {
  RichSyncedLine();

  factory RichSyncedLine.fromJson(Map<String, dynamic> j) {
    final self = RichSyncedLine();
    self.timeStart = _asDouble(j['ts']);
    self.timeEnd = _asDouble(j['te']);
    self.words = _asList(j['l']).map((e) => Word.fromJson(_asMap(e))).toList();
    self.text = j['x'] == null ? null : '${j['x']}';
    return self;
  }

  double timeStart = 0;

  double timeEnd = 0;

  List<Word>? words;

  String? text;
}

class Word {
  Word();

  factory Word.fromJson(Map<String, dynamic> j) {
    final self = Word();
    self.chars = j['c'] == null ? null : '${j['c']}';
    self.position = _asDouble(j['o']);
    return self;
  }

  String? chars;

  double position = 0;
}

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
