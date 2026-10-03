// Ported from Lyricify.Lyrics.Helper/Parsers/LyricifySyllableParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../helpers/general/string_helper.dart';
import '../helpers/offset_helper.dart';
import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import '../models/track_metadata.dart';
import 'attributes_helper.dart';

class LyricifySyllableParser {
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
    final list = <SyllableLineInfoWithSubLineState>[];

    for (final line in lines) {
      final item = parseLyricsLine(line);
      if (item != null) {
        list.add(item);
      }
    }

    final newList = setBackgroundVocalsInfo(list);

    if (offset != null && offset != 0) {
      OffsetHelper.addOffset(newList, offset);
    }

    return newList;
  }

  static List<LineInfo> setBackgroundVocalsInfo(
    List<SyllableLineInfoWithSubLineState> list,
  ) {
    for (var i = 1; i < list.length; i++) {
      if (list[i].isBackgroundVocals == true) {
        list[i - 1].subLine =
            SyllableLineInfoWithSubLineState.getSyllableLineInfo(list[i]);
        list.removeAt(i--);
      }
    }

    bool isNotBackgroundVocals(SyllableLineInfoWithSubLineState line) =>
        line.isBackgroundVocals == null && !line.isBracketedLyrics ||
        line.isBackgroundVocals == false;
    for (var i = 1; i < list.length; i++) {
      if (list[i].isBackgroundVocals == null && list[i].isBracketedLyrics) {
        if (isNotBackgroundVocals(list[i - 1]) && list[i - 1].subLine == null) {
          if (i >= list.length || isNotBackgroundVocals(list[i + 1])) {
            list[i - 1].subLine =
                SyllableLineInfoWithSubLineState.getSyllableLineInfo(list[i]);
            list.removeAt(i--);
          }
        }
      }
    }

    final lines = <LineInfo>[];
    for (var i = 0; i < list.length; i++) {
      lines.add(SyllableLineInfoWithSubLineState.getSyllableLineInfo(list[i]));
    }
    return lines;
  }

  static SyllableLineInfoWithSubLineState? parseLyricsLine(String line) {
    final lyricItems = <SyllableInfo>[];
    final lineInfo = SyllableLineInfoWithSubLineState();

    if (line.contains(']')) {
      final properties = line.substring(0, line.indexOf(']'));
      if (properties.length > 1 &&
          StringHelper.isNumber(properties.substring(1))) {
        final p = int.parse(properties.substring(1));

        if (p >= 6) {
          lineInfo.isBackgroundVocals = true;
        } else if (p >= 3) {
          lineInfo.isBackgroundVocals = false;
        }

        switch (p % 3) {
          case 0:
            lineInfo.lyricsAlignment = LyricsAlignment.unspecified;
            break;
          case 1:
            lineInfo.lyricsAlignment = LyricsAlignment.left;
            break;
          case 2:
            lineInfo.lyricsAlignment = LyricsAlignment.right;
            break;
        }
      }
      line = line.substring(line.indexOf(']') + 1);
    }

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

    lineInfo.syllables = <SyllableInfo>[...lyricItems];
    return lineInfo;
  }
}

class SyllableLineInfoWithSubLineState extends SyllableLineInfo {
  SyllableLineInfoWithSubLineState([super.syllables]);

  bool? isBackgroundVocals;

  bool get isBracketedLyrics =>
      (text.startsWith('(') || text.startsWith('（')) &&
      (text.endsWith(')') || text.endsWith('）'));

  ///
  static SyllableLineInfo getSyllableLineInfo(
    SyllableLineInfoWithSubLineState syllableLineInfoWithSubLineState,
  ) {
    final line = SyllableLineInfo(syllableLineInfoWithSubLineState.syllables);
    line.lyricsAlignment = syllableLineInfoWithSubLineState.lyricsAlignment;
    line.subLine = syllableLineInfoWithSubLineState.subLine;
    return line;
  }
}
