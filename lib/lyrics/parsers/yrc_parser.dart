// Ported from Lyricify.Lyrics.Helper/Parsers/YrcParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'dart:convert';

import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import 'models/yrc.dart';

class YrcParser {
  static LyricsData parse(String input) {
    final lyricsData = LyricsData();
    lyricsData.file = FileInfo()
      ..type = LyricsTypes.yrc
      ..syncTypes = SyncTypes.syllableSynced;
    final lines = <LineInfo>[];

    var i = 0;
    for (; i < input.length; i++) {
      if (input[i] == '{') {
        final endIndex = input.indexOf('\n', i);
        final jsonLine = input.substring(i, endIndex);
        final credits = _parseCredits(jsonLine);
        if (credits != null) {
          lines.add(TextLineInfo(
            credits.credits.map((c) => c.text).join(),
            credits.timestamp,
          ));
          lyricsData.file!.syncTypes = SyncTypes.mixedSynced;

          if (credits.credits.isNotEmpty &&
              credits.credits[0].text.startsWith('作词')) {
            lyricsData.writers = credits.credits
                .getRange(1, credits.credits.length)
                .map((c) => c.text)
                .where((t) => t != '/')
                .toList();
          }
        }
        i = endIndex;
      } else if (input[i] == '\n' || input[i] == '\r') {
        continue;
      } else {
        break;
      }
    }

    var j = input.length - 1;
    while (j >= 0 && (input[j] == '\n' || input[j] == '\r')) {
      j--;
    }
    final endCredits = <LineInfo>[];
    for (; j >= 0; j--) {
      if (input[j] == '}') {
        var startIndex = input.lastIndexOf('\n', j);
        if (startIndex == -1) {
          startIndex = 0;
        } else {
          startIndex++;
        }
        final jsonLine = input.substring(startIndex, j + 1);
        final credits = _parseCredits(jsonLine);
        if (credits != null) {
          endCredits.add(TextLineInfo(
            credits.credits.map((c) => c.text).join(),
            credits.timestamp,
          ));
          lyricsData.file!.syncTypes = SyncTypes.mixedSynced;

          if (credits.credits.isNotEmpty &&
              credits.credits[0].text.startsWith('作词')) {
            lyricsData.writers = credits.credits
                .getRange(1, credits.credits.length)
                .map((c) => c.text)
                .where((t) => t != '/')
                .toList();
          }
        }
        j = startIndex - 1;
      } else if (input[j] == '\n' || input[j] == '\r') {
        continue;
      } else {
        break;
      }
    }

    final lyricsSpan = input.substring(i, j + 1);
    final lyricsList = parseOnlyLyrics(lyricsSpan);

    lines.addAll(lyricsList);
    endCredits.replaceRange(0, endCredits.length, endCredits.reversed);
    lines.addAll(endCredits);

    lyricsData.lines = lines;
    return lyricsData;
  }

  static List<LineInfo> parseLyrics(String input) {
    final lines = <LineInfo>[];

    var i = 0;
    for (; i < input.length; i++) {
      if (input[i] == '{') {
        var endIndex = input.indexOf('\n', i);
        if (endIndex == -1) endIndex = input.length;
        final jsonLine = input.substring(i, endIndex);
        final credits = _parseCredits(jsonLine);
        if (credits != null) {
          lines.add(TextLineInfo(
            credits.credits.map((c) => c.text).join(),
            credits.timestamp,
          ));
        }
        i = endIndex;
      } else if (input[i] == '\n' || input[i] == '\r') {
        continue;
      } else {
        break;
      }
    }

    var j = input.length - 1;
    while (j >= 0 && (input[j] == '\n' || input[j] == '\r')) {
      j--;
    }
    for (; j >= 0; j--) {
      if (input[j] == '}') {
        var startIndex = input.lastIndexOf('\n', j);
        if (startIndex == -1) {
          startIndex = 0;
        } else {
          startIndex++;
        }

        j = startIndex - 1;
      } else if (input[j] == '\n' || input[j] == '\r') {
        continue;
      } else {
        break;
      }
    }
    if (j < i) j = i - 1;

    final lyricsSpan = input.substring(i, j + 1);
    final lyricsList = parseOnlyLyrics(lyricsSpan);

    lines.addAll(lyricsList);
    return lines;
  }

  /// 上游 YrcParser.cs:173 `ParseOnlyLyrics`
  ///
  /// PORT NOTE: 上游 `new SyllableLineInfo(karaokeWordInfos)` 会走
  /// Models/LineInfo.cs:54-57 的构造函数 `Syllables = syllables.ToList()`，
  /// 也就是**复制**一份；而紧接着上游 YrcParser.cs:196 / :326 立刻
  /// `karaokeWordInfos.Clear()`。Dart 的 SyllableLineInfo 构造函数保存的是同一个
  /// List 引用（lib/lyrics/models/line_info.dart，不在本 worker 的改动范围内），
  /// 直接透传会让所有已产出的行都被 Clear 成空行，所以这里显式复制。
  static List<LineInfo> parseOnlyLyrics(String input) {
    final lines = <SyllableLineInfo>[];
    final karaokeWordInfos = <SyllableInfo>[];
    var timeSpanBuilder = 0;
    final lyricStringBuilder = StringBuffer();
    var wordTimespan = 0;
    var wordDuration = 0;
    var state = CurrentState.none;
    var reachesEnd = false;
    for (var i = 0; i < input.length; i++) {
      if (i != input.length) {
        final curChar = input[i];

        if (curChar == '\n' || curChar == '\r' || i + 1 == input.length) {
          if (i + 1 < input.length) {
            if (input[i + 1] == '\n' || input[i + 1] == '\r') i++;
            karaokeWordInfos.add(TextSyllableInfo(
              lyricStringBuilder.toString(),
              wordTimespan,
              wordTimespan + wordDuration,
            ));
            lines.add(SyllableLineInfo([...karaokeWordInfos]));
            karaokeWordInfos.clear();
            lyricStringBuilder.clear();
            state = CurrentState.none;
            continue;
          }
          if (i + 1 == input.length) {
            reachesEnd = true;
          }
        }
        var caseHandled = false;
        switch (curChar) {
          case '[':
            if (state == CurrentState.lyric) {
              if (i + 1 < input.length) {
                if (!_isNumber(input[i + 1])) break;
              }
            }
            state = CurrentState.possiblyLyricTimestamp;
            caseHandled = true;
            break;
          case ',':
            if (state == CurrentState.lyric) {
              if (i + 1 < input.length) {
                if (!_isNumber(input[i + 1])) break;
              }
            }
            if (state == CurrentState.lyricTimestamp) {
              state = CurrentState.possiblyLyricDuration;
              timeSpanBuilder = 0;
            } else if (state == CurrentState.wordTimestamp) {
              state = CurrentState.possiblyWordDuration;
              wordTimespan = timeSpanBuilder;
              timeSpanBuilder = 0;
            } else {
              state = CurrentState.wordUnknownItem;
              wordDuration = timeSpanBuilder;
              timeSpanBuilder = 0;
            }
            caseHandled = true;
            break;
          case ']':
            if (state == CurrentState.lyric) {
              if (i + 1 < input.length) {
                if (!_isNumber(input[i + 1])) break;
              }
            }
            state = CurrentState.none;
            timeSpanBuilder = 0;
            caseHandled = true;
            break;
          case '(':
            if (state == CurrentState.lyric) {
              if (i + 1 < input.length) {
                if (!_isNumber(input[i + 1])) break;
                karaokeWordInfos.add(TextSyllableInfo(
                  lyricStringBuilder.toString(),
                  wordTimespan,
                  wordTimespan + wordDuration,
                ));
                lyricStringBuilder.clear();
              }
            }
            state = CurrentState.possiblyWordTimestamp;
            caseHandled = true;
            break;
          case ')':
            if (state == CurrentState.lyric) {
              if (i + 1 < input.length) {
                if (!_isNumber(input[i + 1])) break;
              }
            }
            state = CurrentState.lyric;
            caseHandled = true;
            break;
        }
        if (caseHandled) {
          continue;
        }
        switch (state) {
          case CurrentState.possiblyLyricTimestamp:
            if (_isNumber(curChar)) state = CurrentState.lyricTimestamp;
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.lyricTimestamp:
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.possiblyWordTimestamp:
            if (_isNumber(curChar)) state = CurrentState.wordTimestamp;
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.wordTimestamp:
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.possiblyLyricDuration:
            if (_isNumber(curChar)) state = CurrentState.lyricDuration;
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.lyricDuration:
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.possiblyWordDuration:
            if (_isNumber(curChar)) state = CurrentState.wordDuration;
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.wordDuration:
            timeSpanBuilder *= 10;
            timeSpanBuilder += _charToDigit(curChar);
            break;
          case CurrentState.lyric:
            if (reachesEnd && (curChar == '\n' || curChar == '\r')) break;
            lyricStringBuilder.write(curChar);
            break;
          case CurrentState.wordUnknownItem:
          case CurrentState.none:
            break;
        }
        if (reachesEnd) {
          karaokeWordInfos.add(TextSyllableInfo(
            lyricStringBuilder.toString(),
            wordTimespan,
            wordTimespan + wordDuration,
          ));
          lines.add(SyllableLineInfo([...karaokeWordInfos]));
          karaokeWordInfos.clear();
          lyricStringBuilder.clear();
        }
      }
    }
    return <LineInfo>[...lines];
  }

  static final RegExp _unicodeNumber = RegExp(r'^\p{N}$', unicode: true);

  static bool _isNumber(String curChar) {
    if (curChar.isEmpty) return false;
    final c = curChar.codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return true;
    return _unicodeNumber.hasMatch(curChar);
  }

  static int _charToDigit(String curChar) =>
      curChar.isEmpty ? 0 : curChar.codeUnitAt(0) - 0x30;

  static CreditsInfo? _parseCredits(String jsonLine) {
    try {
      final decoded = jsonDecode(jsonLine);
      if (decoded is! Map) return null;
      return CreditsInfo.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

enum CurrentState {
  none,
  lyricTimestamp,
  wordTimestamp,
  lyricDuration,
  wordDuration,
  wordUnknownItem,
  possiblyLyricDuration,
  possiblyWordDuration,
  possiblyLyricTimestamp,
  possiblyWordTimestamp,
  lyric,
}
