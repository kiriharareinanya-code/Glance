// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/Model.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../json_utils.dart';

class QqLyricsResponse {
  QqLyricsResponse([this.lyrics, this.trans]);

  factory QqLyricsResponse.fromJson(Map<String, dynamic> j) =>
      QqLyricsResponse(asStr(j['lyrics']), asStr(j['trans']));

  String? lyrics;

  String? trans;
}

class SongResponse {
  SongResponse([this.code = 0, List<Song>? data]) : data = data ?? <Song>[];

  factory SongResponse.fromJson(Map<String, dynamic> j) {
    final data = <Song>[];
    for (final item in asArr(j['data'])) {
      data.add(Song.fromJson(asObj(item)));
    }
    return SongResponse(asInt(j['code']), data);
  }

  int code;

  List<Song> data;
}

class Song {
  Song([this.id]);

  factory Song.fromJson(Map<String, dynamic> j) => Song(asStr(j['id']));

  String? id;
}
