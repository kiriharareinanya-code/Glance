// Ported from Lyricify.Lyrics.Helper/Parsers/SpotifyParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// C# → Dart：
//   `JsonConvert.DeserializeObject<SpotifyColorLyrics>(rawJson)` →
//     `decodeAs(rawJson, SpotifyColorLyrics.fromJson)`（json_utils.dart）。
library;

import '../json_utils.dart';
import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import 'models/spotify.dart';

class SpotifyParser {
  static LyricsData? parse(String rawJson) {
    final colorLyrics = decodeAs(rawJson, SpotifyColorLyrics.fromJson);
    if (colorLyrics != null && colorLyrics.lyrics != null) {
      final lyrics = colorLyrics.lyrics!;
      final lines = parseLyrics(lyrics);
      final lyricsData = LyricsData();
      lyricsData.file = FileInfo();
      lyricsData.lines = lines;

      lyricsData.file!.type = LyricsTypes.spotify;
      lyricsData.file!.syncTypes = switch (lyrics.syncType) {
        'UNSYNCED' => SyncTypes.unsynced,
        'LINE_SYNCED' => SyncTypes.lineSynced,
        'SYLLABLE_SYNCED' => SyncTypes.syllableSynced,
        _ => SyncTypes.unknown,
      };
      lyricsData.file!.additionalInfo = SpotifyAdditionalInfo(
        lyrics.provider,
        lyrics.providerLyricsId,
        lyrics.providerDisplayName,
        lyrics.language,
      );
      return lyricsData;
    }
    return null;
  }

  static List<LineInfo> parseLyrics(SpotifyLyrics lyrics) {
    if (lyrics.syncType == 'UNSYNCED') {
      return parseUnsyncedLyrics(lyrics.lines).cast<LineInfo>();
    } else {
      return parseSyncedLyrics(lyrics.lines);
    }
  }

  static List<LineInfo> parseUnsyncedLyrics(List<SpotifyLyricsLine>? lyrics) {
    final list = <LineInfo>[];
    for (final line in lyrics ?? const <SpotifyLyricsLine>[]) {
      list.add(TextLineInfo(line.words ?? ''));
    }
    return list;
  }

  static List<LineInfo> parseSyncedLyrics(List<SpotifyLyricsLine>? lyrics) {
    final list = <LineInfo>[];
    for (final line in lyrics ?? const <SpotifyLyricsLine>[]) {
      final lineSyllables = line.syllables;
      if (lineSyllables != null && lineSyllables.isNotEmpty) {
        final words = line.words ?? '';
        final syllables = <SyllableInfo>[];
        var i = 0;
        for (final syllable in lineSyllables) {
          syllables.add(TextSyllableInfo(
            _slice(words, i, i + syllable.charsCount),
            syllable.startTime,
            syllable.endTime,
          ));
          i += syllable.charsCount;
        }
        list.add(SyllableLineInfo(syllables));
      } else {
        if (line.endTime != 0) {
          list.add(TextLineInfo(line.words ?? '', line.startTime, line.endTime));
        } else {
          list.add(TextLineInfo(line.words ?? '', line.startTime));
        }
      }
    }
    return list;
  }
}

String _slice(String s, int start, int end) {
  if (start >= s.length) return '';
  final e = end > s.length ? s.length : end;
  if (e <= start) return '';
  return s.substring(start, e);
}
