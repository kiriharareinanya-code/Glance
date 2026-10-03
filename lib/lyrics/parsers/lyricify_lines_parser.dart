// Ported from Lyricify.Lyrics.Helper/Parsers/LyricifyLinesParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../helpers/general/string_helper.dart';
import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/track_metadata.dart';
import 'attributes_helper.dart';

class LyricifyLinesParser {
  static LyricsData parse(String lyrics) {
    final lyricsLines =
        lyrics.replaceAll('[type:LyricifyLines]', '').trim().split('\n').toList();
    final data = LyricsData();
    data.trackMetadata = BasicTrackMetadata();
    data.file = FileInfo()
      ..syncTypes = SyncTypes.lineSynced
      ..type = LyricsTypes.lyricifyLines
      ..additionalInfo = (GeneralAdditionalInfo()..attributes = []);

    final offset =
        AttributesHelper.parseGeneralAttributesToLyricsData(data, lyricsLines);

    final lines = parseLyrics(lyricsLines, offset);
    data.lines = <LineInfo>[...lines];

    return data;
  }

  static List<TextLineInfo> parseLyrics(List<String> lines, [int? offset]) {
    offset ??= 0;
    final lyricsArray = <TextLineInfo>[];
    for (final line in lines) {
      if (!line.startsWith('[') ||
          !line.contains(',') ||
          !line.contains(']')) {
        continue;
      }
      try {
        final begin = int.parse(StringHelper.between(line, '[', ','));
        final end = int.parse(StringHelper.between(line, ',', ']'));
        final text = line.substring(line.indexOf(']') + 1).trim();
        final lineInfo = TextLineInfo();
        lineInfo.text = text;
        lineInfo.startTime = begin - offset;
        lineInfo.endTime = end - offset;
        lyricsArray.add(lineInfo);
      } catch (_) {}
    }
    return lyricsArray;
  }
}
