// Ported from Lyricify.Lyrics.Helper/Parsers/QrcParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../helpers/offset_helper.dart';
import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import '../models/track_metadata.dart';
import 'attributes_helper.dart';

class QrcParser {
  static LyricsData parse(String lyrics) {
    final lyricsLines = lyrics.trim().split('\n').toList();
    final data = LyricsData();
    data.trackMetadata = BasicTrackMetadata();
    data.file = FileInfo()
      ..type = LyricsTypes.qrc
      ..syncTypes = SyncTypes.syllableSynced
      ..additionalInfo = (GeneralAdditionalInfo()..attributes = []);

    final offset =
        AttributesHelper.parseGeneralAttributesToLyricsData(data, lyricsLines);

    final lines = parseLyrics(lyricsLines, offset);

    data.lines = lines;
    return data;
  }

  static List<LineInfo> parseLyrics(List<String> lines, [int? offset]) {
    final list = <SyllableLineInfo>[];

    for (final line in lines) {
      final item = parseLyricsLine(line);
      if (item != null) {
        list.add(item);
      }
    }

    final returnList = <LineInfo>[...list];
    if (offset != null && offset != 0) {
      OffsetHelper.addOffset(returnList, offset);
    }

    return returnList;
  }

  static SyllableLineInfo? parseLyricsLine(String line) {
    if (line.contains(']')) {
      line = line.substring(line.indexOf(']') + 1);
    }

    final lyricItems = <SyllableInfo>[];
    final matches = RegExp(r'(.*?)\((\d+),(\d+)\)').allMatches(line);

    for (final match in matches) {
      if (match.groupCount == 3) {
        final text = match.group(1)!;
        final startTime = int.parse(match.group(2)!);
        final duration = int.parse(match.group(3)!);

        final endTime = startTime + duration;

        lyricItems.add(TextSyllableInfo(text, startTime, endTime));
      }
    }

    return SyllableLineInfo(lyricItems);
  }
}
