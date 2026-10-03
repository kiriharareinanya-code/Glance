// Ported from Lyricify.Lyrics.Helper/Parsers/MusixmatchParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//   `JObject.Parse(rawJson)` + `jsonObj?["message"]?["body"]?["macro_calls"]` →
//   `track.Language = new() { language }` → `[language]`。
library;

import 'dart:convert';

import '../json_utils.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import '../models/track_metadata.dart';
import 'lrc_parser.dart';
import 'models/musixmatch.dart';

class MusixmatchParser {
  ///
  static LyricsData? parse(String rawJson, [bool ignoreSyllable = false]) {
    final jsonObj = _tryDecodeObject(rawJson);
    if (jsonObj == null) return null;
    final callsValue = jget(jsonObj, 'message.body.macro_calls');
    if (callsValue is! Map) return null;
    final calls = asObj(callsValue);


    final trackGetRichsync = asObj(calls['track.richsync.get']);
    if (!ignoreSyllable && _checkHeader200(trackGetRichsync)) {
      final body = _getBody(trackGetRichsync);
      final richsync = asObj(body['richsync']);
      final lyrics = asStr(richsync['richsync_body']);

      if (lyrics.isNotEmpty) {
        final list = _decodeRichSyncedLines(lyrics);
        if (list != null) {
          final lines = <LineInfo>[];
          for (final line in list) {
            final syllables = <SyllableInfo>[];
            final start = (line.timeStart * 1000).toInt();
            final words = line.words ?? const <Word>[];
            for (var i = 0; i < words.length; i++) {
              syllables.add(TextSyllableInfo(
                words[i].chars ?? '',
                start + (words[i].position * 1000).toInt(),
                i + 1 < words.length
                    ? start + (words[i + 1].position * 1000).toInt()
                    : (line.timeEnd * 1000).toInt(),
              ));
            }
            lines.add(SyllableLineInfo(syllables));
          }

          final lyricsData = LyricsData();
          lyricsData.file = FileInfo();
          lyricsData.lines = lines;
          lyricsData.trackMetadata = BasicTrackMetadata();
          lyricsData.file!.type = LyricsTypes.musixmatch;
          lyricsData.file!.syncTypes = SyncTypes.syllableSynced;
          final language = richsync['richssync_language'] != null
              ? asStr(richsync['richssync_language'])
              : (richsync['richsync_language'] != null
                  ? asStr(richsync['richsync_language'])
                  : null);
          if (language != null) {
            lyricsData.trackMetadata!.language = [language];
          }
          return lyricsData;
        }
      }
    }

    final trackGetSubtitles = asObj(calls['track.subtitles.get']);
    if (_checkHeader200(trackGetSubtitles)) {
      final body = _getBody(trackGetSubtitles);
      final list = asArr(body['subtitle_list']);
      if (list.isNotEmpty) {
        final first = asObj(list[0]);
        final subtitle = asObj(first['subtitle']);
        final subtitleBodyValue = subtitle['subtitle_body'];
        final subtitleBody =
            subtitleBodyValue == null ? null : asStr(subtitleBodyValue);
        if (subtitleBody != null && subtitleBody.isNotEmpty) {
          final lines = LrcParser.parseLyrics(subtitleBody);
          final lyricsData = LyricsData();
          lyricsData.file = FileInfo();
          lyricsData.lines = lines;
          lyricsData.trackMetadata = BasicTrackMetadata();
          lyricsData.file!.type = LyricsTypes.musixmatch;
          lyricsData.file!.syncTypes = SyncTypes.lineSynced;
          final languageValue = subtitle['subtitle_language'];
          final language = languageValue == null ? null : asStr(languageValue);
          if (language != null) {
            lyricsData.trackMetadata!.language = [language];
          }
          return lyricsData;
        }
      }
    }

    final trackGetLyrics = asObj(calls['track.lyrics.get']);
    if (_checkHeader200(trackGetLyrics)) {
      final body = _getBody(trackGetLyrics);
      final lyricsObj = asObj(body['lyrics']);
      final lyricsBodyValue = lyricsObj['lyrics_body'];
      final lyricsBody = lyricsBodyValue == null ? null : asStr(lyricsBodyValue);

      if (lyricsBody != null && lyricsBody.isNotEmpty) {
        final list = lyricsBody
            .trim()
            .split('\n')
            .map((line) => TextLineInfo(line) as LineInfo)
            .toList();

        final lyricsData = LyricsData();
        lyricsData.file = FileInfo();
        lyricsData.lines = list;
        lyricsData.file!.type = LyricsTypes.musixmatch;
        lyricsData.file!.syncTypes = SyncTypes.unsynced;
        return lyricsData;
      }
    }

    return null;
  }
}

Map<String, dynamic> _getMessage(Map<String, dynamic> call) =>
    asObj(call['message']);

Map<String, dynamic> _getBody(Map<String, dynamic> call) =>
    asObj(_getMessage(call)['body']);

///
bool _checkHeader200(Map<String, dynamic> getObj) {
  final headerValue = _getMessage(getObj)['header'];
  if (headerValue is! Map) return false;
  final header = headerValue.cast<String, dynamic>();
  if (header['status_code'] is! int) return false;
  if (header['status_code'] != 200) return false;
  return true;
}

Map<String, dynamic>? _tryDecodeObject(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  } catch (_) {
    return null;
  }
}

List<RichSyncedLine>? _decodeRichSyncedLines(String lyrics) {
  try {
    final decoded = jsonDecode(lyrics);
    if (decoded is! List) return null;
    return [
      for (final e in decoded)
        RichSyncedLine.fromJson(
            e is Map ? e.cast<String, dynamic>() : <String, dynamic>{}),
    ];
  } catch (_) {
    return null;
  }
}
