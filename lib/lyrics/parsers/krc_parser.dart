// Ported from Lyricify.Lyrics.Helper/Parsers/KrcParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import 'dart:convert';

import '../decrypters/krc/model.dart' as krc_model;
import '../helpers/general/string_helper.dart';
import '../helpers/offset_helper.dart';
import '../json_utils.dart';
import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import '../models/track_metadata.dart';
import 'attributes_helper.dart';

class KrcParser {
  static LyricsData parse(String krc) {
    final data = LyricsData();
    final additionalInfo = KrcAdditionalInfo()
      ..attributes = <MapEntry<String, String>>[];
    data.file = FileInfo()
      ..type = LyricsTypes.krc
      ..syncTypes = SyncTypes.syllableSynced
      ..additionalInfo = additionalInfo;
    data.trackMetadata = BasicTrackMetadata();

    final lyricsLines = getSplitedKrc(krc);

    final offset =
        AttributesHelper.parseGeneralAttributesToLyricsData(data, lyricsLines);

    final lyrics = parseLyricsFromLines(lyricsLines, offset);
    if (KrcTranslationParser.checkKrcTranslation(krc)) {
      final lyricsTrans = KrcTranslationParser.getTranslationFromKrc(krc);
      if (lyricsTrans != null) {
        for (var i = 0;
            i < lyrics.length && i < lyricsTrans.length;
            i++) {
          var t = lyricsTrans[i];
          t = t != '//' ? t : '';
          lyrics[i] = FullSyllableLineInfo.fromLineWith(
            lineInfo: lyrics[i] as SyllableLineInfo,
            chineseTranslation: t,
          );
        }
      }
    }

    data.lines = lyrics;

    return data;
  }

  static List<LineInfo> parseLyrics(String krc) {
    final lyricsLines = getSplitedKrcWithoutInfoLine(krc);
    final lyrics = parseLyricsFromLines(lyricsLines);

    if (KrcTranslationParser.checkKrcTranslation(krc)) {
      final lyricsTrans = KrcTranslationParser.getTranslationFromKrc(krc);
      if (lyricsTrans != null) {
        for (var i = 0;
            i < lyrics.length && i < lyricsTrans.length;
            i++) {
          var t = lyricsTrans[i];
          t = t != '//' ? t : '';
          lyrics[i] = FullSyllableLineInfo.fromLineWith(
            lineInfo: lyrics[i] as SyllableLineInfo,
            chineseTranslation: t,
          );
        }
      }
    }

    return lyrics;
  }

  static List<LineInfo> parseLyricsFromLines(
    List<String> lyricsLines, [
    int? offset,
  ]) {
    final lyrics = <LineInfo>[];

    for (final line in lyricsLines) {
      if (line.startsWith('[')) {
        final l = parseLyricsLine(line);
        if (l != null) {
          lyrics.add(l);
        }
      }
    }

    if (offset != null && offset != 0) {
      OffsetHelper.addOffset(lyrics, offset);
    }

    return lyrics;
  }

  static List<String> getSplitedKrc(String krc) {
    final lines = krc.replaceAll('\r\n', '\n').replaceAll('\r', '').split('\n');
    final stringBuilder = StringBuffer();
    for (final line in lines) {
      if (line.startsWith('[')) {
        stringBuilder.writeln(line);
      }
    }
    return stringBuilder
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '')
        .split('\n');
  }

  static List<String> getSplitedKrcWithoutInfoLine(String krc) {
    final lines = krc.replaceAll('\r\n', '\n').replaceAll('\r', '').split('\n');
    final stringBuilder = StringBuffer();
    for (final line in lines) {
      if (line.startsWith('[') &&
          line.length >= 5 &&
          StringHelper.isNumber(line[1])) {
        stringBuilder.writeln(line);
      }
    }
    return stringBuilder
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '')
        .split('\n');
  }

  static SyllableLineInfo? parseLyricsLine(String line) {
    final words = line.substring(line.indexOf(']') + 1).split(',0>');
    if (words.isEmpty) return null;
    final lineTime = line.substring(1, line.indexOf(']')).split(',');
    final lineStart = int.parse(lineTime[0]);

    final syllables = <SyllableInfo>[];

    var time = words[0].substring(1).split(',');
    var start = int.parse(time[0]);
    var duration = int.parse(time[1]);
    for (var i = 1; i < words.length; i++) {
      var word = words[i];
      if (word.contains('<')) {
        word = word.substring(0, word.lastIndexOf('<'));
      }
      syllables.add(TextSyllableInfo(
        word,
        lineStart + start,
        lineStart + start + duration,
      ));
      if (words[i].contains('<')) {
        time = words[i].substring(words[i].lastIndexOf('<') + 1).split(',');
        start = int.parse(time[0]);
        duration = int.parse(time[1]);
      }
    }
    return SyllableLineInfo(syllables);
  }
}

class KrcTranslationParser {
  static bool checkKrcTranslation(String krc) {
    if (!krc.contains('[language:')) return false;

    try {
      var language =
          krc.substring(krc.indexOf('[language:') + '[language:'.length);
      language = language.substring(0, language.indexOf(']'));
      final decode = utf8.decode(base64.decode(language));

      final translation = krc_model.KugouTranslation.fromJson(
        asObj(jsonDecode(decode)),
      );
      if (translation.content != null && translation.content!.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// 提取 KRC 中的翻译
  /// @param krc KRC 歌词
  /// @returns 翻译 List，若无翻译，则返回 null
  static List<String>? getTranslationFromKrc(String krc) {
    if (!krc.contains('[language:')) return null;

    var language =
        krc.substring(krc.indexOf('[language:') + '[language:'.length);
    language = language.substring(0, language.indexOf(']'));
    final decode = utf8.decode(base64.decode(language));

    final translation =
        krc_model.KugouTranslation.fromJson(asObj(jsonDecode(decode)));

    if (translation.content == null || translation.content!.isEmpty) {
      return null;
    }

    try {
      final result = <String>[];
      krc_model.ContentItem? content;
      for (final item in translation.content!) {
        if (item.type == 1) {
          content = item;
          break;
        }
      }
      if (content == null) return null;

      for (var i = 0; i < content.lyricContent!.length; i++) {
        result.add(content.lyricContent![i]![0]);
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  /// 提取 KRC 中的翻译原始数据
  /// @param krc KRC 歌词
  /// @returns 翻译 List，若无翻译，则返回 null
  static krc_model.KugouTranslation? getTranslationRawFromKrc(String krc) {
    if (!krc.contains('[language:')) return null;

    var language =
        krc.substring(krc.indexOf('[language:') + '[language:'.length);
    language = language.substring(0, language.indexOf(']'));
    final decode = utf8.decode(base64.decode(language));

    return krc_model.KugouTranslation.fromJson(asObj(jsonDecode(decode)));
  }
}
