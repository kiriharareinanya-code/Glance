// Ported from Lyricify.Lyrics.Helper/Decrypter/Krc/Model.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../json_utils.dart';

class KugouLyricsResponse {
  KugouLyricsResponse([
    this.content,
    this.info,
    this.source,
    this.status = 0,
    this.contentType = 0,
    this.errorCode = 0,
    this.format,
  ]);

  factory KugouLyricsResponse.fromJson(Map<String, dynamic> j) =>
      KugouLyricsResponse(
        asStr(j['content']),
        asStr(j['info']),
        asStr(j['_source']),
        asInt(j['status']),
        asInt(j['contenttype']),
        asInt(j['error_code']),
        asStr(j['fmt']),
      );

  /// `[JsonProperty("content")]`
  String? content;

  /// `[JsonProperty("info")]`
  String? info;

  String? source;

  /// `[JsonProperty("status")]`
  int status;

  /// `[JsonProperty("contenttype")]`
  int contentType;

  /// `[JsonProperty("error_code")]`
  int errorCode;

  /// `[JsonProperty("fmt")]`
  String? format;
}

class KugouTranslation {
  KugouTranslation([List<ContentItem>? content, this.version = 0])
      : content = content ?? <ContentItem>[];

  factory KugouTranslation.fromJson(Map<String, dynamic> j) {
    final content = <ContentItem>[];
    for (final item in asArr(j['content'])) {
      content.add(ContentItem.fromJson(asObj(item)));
    }
    return KugouTranslation(content, asInt(j['version']));
  }

  /// `[JsonProperty("content")]`
  List<ContentItem>? content;

  /// `[JsonProperty("version")]`
  int version;
}

class ContentItem {
  ContentItem([
    this.language = 0,
    this.type = 0,
    List<List<String>?>? lyricContent,
  ]) : lyricContent = lyricContent ?? <List<String>?>[];

  factory ContentItem.fromJson(Map<String, dynamic> j) {
    final lyricContent = <List<String>?>[];
    for (final line in asArr(j['lyricContent'])) {
      if (line == null) {
        lyricContent.add(null);
      } else {
        lyricContent.add(<String>[
          for (final cell in asArr(line)) asStr(cell),
        ]);
      }
    }
    return ContentItem(
      asInt(j['language']),
      asInt(j['type']),
      lyricContent,
    );
  }

  /// `[JsonProperty("language")]`
  int language;

  /// `[JsonProperty("type")]`
  int type;

  /// `[JsonProperty("lyricContent")]`
  List<List<String>?>? lyricContent;
}
