// Ported from Lyricify.Lyrics.Helper/Parsers/LrcParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/track_metadata.dart';

class LrcParser {
  static LyricsData parse(String input) {
    final lines = <TextLineInfo>[];
    final lyricCharBuffer = StringBuffer();
    var attributeName = '';
    final attributes = <MapEntry<String, String>>[];
    final trackMetadata = BasicTrackMetadata();
    var curStateStartPosition = 0;
    var timeCalculationCache = 0;
    var curTimestamps = _rentIntArray(64); // Max Count
    var curTimestamp = 0;
    var currentTimestampPosition = 0;
    var offset = 0;
    var reachesEnd = false;
    var lastCharacterIsLineBreak = false;
    var state = CurrentState.none;
    var timeStampType = TimeStampType.none;
    for (var i = 0; i < input.length; i++) {
      final curChar = input[i];
      if (state == CurrentState.lyric) {
        if (curChar != '\n' && curChar != '\r' && i + 1 < input.length) {
          lyricCharBuffer.write(curChar);
          continue;
        } else {
          if (i + 1 < input.length) {
            for (var j = 0; j < curTimestamps.length; j++) {
              if (curTimestamps[j] == -1) break;
              lines.add(TextLineInfo(
                input
                    .substring(
                      curStateStartPosition + 1,
                      i,
                    )
                    .trim(),
                curTimestamps[j] - offset,
              ));
            }
            if (input[i + 1] == '\n' || input[i + 1] == '\r') i++;
            currentTimestampPosition = 0;
            lyricCharBuffer.clear();
            // Change State
            state = CurrentState.none;
            continue;
          }
          if (i + 1 == input.length) {
            reachesEnd = true;
            if (curChar == '\r' || curChar == '\n') {
              lastCharacterIsLineBreak = true;
            } else {
              _writeLyricChar(lyricCharBuffer, reachesEnd, curChar);
            }
          }
        }
      }
      if (reachesEnd && state == CurrentState.lyric) {
        for (var j = 0; j < curTimestamps.length; j++) {
          if (curTimestamps[j] == -1) break;
          lines.add(TextLineInfo(
            _finalizeLine(
              lyricCharBuffer,
              input,
              curStateStartPosition,
              i,
              lastCharacterIsLineBreak,
            ),
            curTimestamps[j] - offset,
          ));
        }
        continue;
      }
      switch (state) {
        case CurrentState.lyric:
          _writeLyricChar(lyricCharBuffer, reachesEnd, curChar);
          break;
        case CurrentState.possiblyLyric:
          if (curChar == '[') {
            state = CurrentState.awaitingStateLyric;
          } else {
            i -= 1;
            state = CurrentState.lyric;
          }

          break;
        case CurrentState.none:
          _fill(curTimestamps, -1);
          if (curChar == '[') {
            state = CurrentState.awaitingState;
          }

          break;
        case CurrentState.awaitingState:
          if (_isDigit(curChar)) {
            // Time
            state = CurrentState.timestamp;
            timeStampType = TimeStampType.minutes;
            curStateStartPosition = i;
            curTimestamp = 0;
            i--;
          } else {
            state = CurrentState.attribute;
            curStateStartPosition = i;
          }

          break;
        case CurrentState.awaitingStateLyric:
          if (_isDigit(curChar)) {
            // Time
            state = CurrentState.timestamp;
            timeStampType = TimeStampType.minutes;
            curStateStartPosition = i;
            curTimestamp = 0;
            i--;
          } else {
            state = CurrentState.lyric;
            curStateStartPosition = i - 2;
          }

          break;
        case CurrentState.attribute:
          if (curChar == ':') {
            attributeName = input.substring(curStateStartPosition, i);
            curStateStartPosition = i + 1;
            state = CurrentState.attributeContent;
          }

          break;
        case CurrentState.attributeContent:
          if (curChar == ']') {
            String attributeValue;
            if (attributeName == 'offset') {
              offset = timeCalculationCache;
              timeCalculationCache = 0;
              attributeValue = offset.toString();
            } else {
              attributeValue = input.substring(curStateStartPosition, i);
            }
            final attribute =
                MapEntry<String, String>(attributeName, attributeValue);
            switch (attribute.key) {
              case 'ar':
                trackMetadata.artist = attribute.value;
                break;
              case 'al':
                trackMetadata.album = attribute.value;
                break;
              case 'ti':
                trackMetadata.title = attribute.value;
                break;
              case 'length':
                final result = int.tryParse(attribute.value);
                if (result != null) {
                  trackMetadata.durationMs = result;
                }
                break;
            }
            attributes.add(attribute);
            attributeName = '';
            state = CurrentState.none;
            break;
          }
          if (attributeName == 'offset') {
            timeCalculationCache =
                timeCalculationCache * 10 + _charToDigit(curChar);
            continue;
          }
          break;
        case CurrentState.timestamp:
          if (timeStampType == TimeStampType.milliseconds) {
            if (curChar != ']') {
              timeCalculationCache =
                  timeCalculationCache * 10 + _charToDigit(curChar);
              continue;
            } else {
              final pow = i - curStateStartPosition - 1; // 几位小数
              curTimestamp += timeCalculationCache * _pow10(3 - pow);
              if (currentTimestampPosition + 1 >= curTimestamps.length) {
                curTimestamps = _extendIntArrayPool(curTimestamps);
              }
              curTimestamps[currentTimestampPosition++] = curTimestamp;
              timeStampType = TimeStampType.none;
              timeCalculationCache = 0;
              curStateStartPosition = i;
              curTimestamp = 0;
              state = CurrentState.possiblyLyric;
              continue;
            }
          }
          switch (curChar) {
            case ':':
            case '.':
              if (timeStampType == TimeStampType.minutes) {
                curTimestamp = (curTimestamp + timeCalculationCache) * 60;
                timeCalculationCache = 0;
                timeStampType = TimeStampType.seconds;
                continue;
              }
              if (timeStampType == TimeStampType.seconds) {
                curTimestamp = (curTimestamp + timeCalculationCache) * 1000;
                curStateStartPosition = i;
                timeCalculationCache = 0;
                timeStampType = TimeStampType.milliseconds;
                continue;
              }
              throw RangeError('timeStampType');
            case ']':
              if (currentTimestampPosition + 1 >= curTimestamps.length) {
                curTimestamps = _extendIntArrayPool(curTimestamps);
              }
              curTimestamps[currentTimestampPosition++] =
                  (curTimestamp + timeCalculationCache) * 1000;
              timeCalculationCache = 0;
              curStateStartPosition = i;
              curTimestamp = 0;
              state = CurrentState.possiblyLyric;
              timeStampType = TimeStampType.none;
              continue;
            default:
              timeCalculationCache =
                  timeCalculationCache * 10 + _charToDigit(curChar);
              break;
          }

          break;
        // 上游 LrcParser.cs:240-241 `default: throw new ArgumentOutOfRangeException();`
        // Dart 的 switch 已穷举全部 CurrentState 成员，该分支不可达，仅为保真保留。
        // ignore: unreachable_switch_default
        default:
          throw RangeError('state');
      }
    }

    lines.sort();

    final lyricsData = LyricsData();
    lyricsData.trackMetadata = trackMetadata;
    lyricsData.lines = <LineInfo>[...lines];
    lyricsData.file = FileInfo()
      ..syncTypes = SyncTypes.lineSynced
      ..type = LyricsTypes.lrc;
    return lyricsData;
  }

  static List<LineInfo> parseLyrics(String input) {
    final lines = <TextLineInfo>[];
    final lyricCharBuffer = StringBuffer();
    var curStateStartPosition = 0;
    var timeCalculationCache = 0;
    var curTimestamps = _rentIntArray(64); // Max Count
    var curTimestamp = 0;
    var currentTimestampPosition = 0;
    var reachesEnd = false;
    var lastCharacterIsLineBreak = false;
    var state = CurrentState.none;
    var timeSpanType = TimeStampType.none;
    for (var i = 0; i < input.length; i++) {
      final curChar = input[i];
      if (state == CurrentState.lyric) {
        if (curChar != '\n' && curChar != '\r' && i + 1 < input.length) {
          lyricCharBuffer.write(curChar);
          continue;
        } else {
          if (i + 1 < input.length) {
            for (var j = 0; j < curTimestamps.length; j++) {
              if (curTimestamps[j] == -1) break;
              lines.add(TextLineInfo(
                input
                    .substring(
                      curStateStartPosition + 1,
                      i,
                    )
                    .trim(),
                curTimestamps[j],
              ));
            }
            if (input[i + 1] == '\n' || input[i + 1] == '\r') i++;
            currentTimestampPosition = 0;
            lyricCharBuffer.clear();
            // Change State
            state = CurrentState.none;
            continue;
          }
          if (i + 1 == input.length) {
            reachesEnd = true;
            if (curChar == '\r' || curChar == '\n') {
              lastCharacterIsLineBreak = true;
            }
          }
        }
      }
      if (reachesEnd) {
        for (var j = 0; j < curTimestamps.length; j++) {
          if (curTimestamps[j] == -1) break;
          lines.add(TextLineInfo(
            input
                .substring(
                  curStateStartPosition + 1,
                  i - (lastCharacterIsLineBreak ? 1 : 0),
                )
                .trim(),
            curTimestamps[j],
          ));
        }
        continue;
      }
      switch (state) {
        case CurrentState.lyric:
          _writeLyricChar(lyricCharBuffer, reachesEnd, curChar);
          break;
        case CurrentState.possiblyLyric:
          if (curChar == '[') {
            state = CurrentState.awaitingStateLyric;
          } else {
            i -= 1;
            state = CurrentState.lyric;
          }

          break;
        case CurrentState.none:
          _fill(curTimestamps, -1);
          if (curChar == '[') {
            state = CurrentState.awaitingState;
          }

          break;
        case CurrentState.awaitingState:
          if (_isDigit(curChar)) {
            // Time
            state = CurrentState.timestamp;
            timeSpanType = TimeStampType.minutes;
            curStateStartPosition = i;
            curTimestamp = 0;
            i--;
          } else {
            state = CurrentState.attribute;
            curStateStartPosition = i;
          }

          break;
        case CurrentState.awaitingStateLyric:
          if (_isDigit(curChar)) {
            // Time
            state = CurrentState.timestamp;
            timeSpanType = TimeStampType.minutes;
            curStateStartPosition = i;
            curTimestamp = 0;
            i--;
          } else {
            state = CurrentState.lyric;
            curStateStartPosition = i - 2;
          }

          break;
        case CurrentState.attribute:
          if (curChar == ':') {
            //var attr = input.Slice(curStateStartPosition, i - curStateStartPosition);
            state = CurrentState.attributeContent;
          }

          break;
        case CurrentState.attributeContent:
          if (curChar == ']') state = CurrentState.none;
          break;
        case CurrentState.timestamp:
          if (timeSpanType == TimeStampType.milliseconds) {
            if (curChar != ']') {
              timeCalculationCache =
                  timeCalculationCache * 10 + _charToDigit(curChar);
              continue;
            } else {
              final pow = i - curStateStartPosition - 1; // 几位小数
              curTimestamp += timeCalculationCache * _pow10(3 - pow);
              if (currentTimestampPosition + 1 >= curTimestamps.length) {
                curTimestamps = _extendIntArrayPool(curTimestamps);
              }
              curTimestamps[currentTimestampPosition++] = curTimestamp;
              timeSpanType = TimeStampType.none;
              timeCalculationCache = 0;
              curStateStartPosition = i;
              curTimestamp = 0;
              state = CurrentState.possiblyLyric;
              continue;
            }
          }
          switch (curChar) {
            case ':':
            case '.':
              if (timeSpanType == TimeStampType.minutes) {
                curTimestamp = (curTimestamp + timeCalculationCache) * 60;
                timeCalculationCache = 0;
                timeSpanType = TimeStampType.seconds;
                continue;
              }
              if (timeSpanType == TimeStampType.seconds) {
                curTimestamp = (curTimestamp + timeCalculationCache) * 1000;
                curStateStartPosition = i;
                timeCalculationCache = 0;
                timeSpanType = TimeStampType.milliseconds;
                continue;
              }
              throw RangeError('timeSpanType');
            case ']':
              if (currentTimestampPosition + 1 >= curTimestamps.length) {
                curTimestamps = _extendIntArrayPool(curTimestamps);
              }
              curTimestamps[currentTimestampPosition++] =
                  (curTimestamp + timeCalculationCache) * 1000;
              timeCalculationCache = 0;
              curStateStartPosition = i;
              curTimestamp = 0;
              state = CurrentState.possiblyLyric;
              continue;
            default:
              timeCalculationCache =
                  timeCalculationCache * 10 + _charToDigit(curChar);
              break;
          }

          break;
        // 上游 LrcParser.cs:446-448 `default: throw new ArgumentOutOfRangeException();`
        // Dart 的 switch 已穷举全部 CurrentState 成员，该分支不可达，仅为保真保留。
        // ignore: unreachable_switch_default
        default:
          throw RangeError('state');
      }
    }

    lines.sort();
    return <LineInfo>[...lines];
  }

  /// `if (reachesEnd && (input[i] == '\n' || input[i] == '\r')) break;`
  static void _writeLyricChar(
    StringBuffer buffer,
    bool reachesEnd,
    String curChar,
  ) {
    if (reachesEnd && (curChar == '\n' || curChar == '\r')) return;
    buffer.write(curChar);
  }

  static String _finalizeLine(
    StringBuffer buffer,
    String input,
    int curStateStartPosition,
    int i,
    bool lastCharacterIsLineBreak,
  ) {
    final text = buffer.isNotEmpty
        ? buffer.toString()
        : input.substring(
            curStateStartPosition + 1,
            i - (lastCharacterIsLineBreak ? 1 : 0),
          );
    return text.trim();
  }

  /// C# `'0' <= curChar && curChar <= '9'`
  static bool _isDigit(String curChar) {    if (curChar.isEmpty) return false;
    final c = curChar.codeUnitAt(0);
    return c >= 0x30 && c <= 0x39;
  }

  static int _charToDigit(String curChar) =>
      curChar.isEmpty ? 0 : curChar.codeUnitAt(0) - 0x30;

  static List<int> _rentIntArray(int length) {
    final array = List<int>.filled(length, 0);
    _fill(array, -1);
    return array;
  }

  static void _fill(List<int> array, int value) {
    for (var i = 0; i < array.length; i++) {
      array[i] = value;
    }
  }

  static int _pow10(int exponent) {
    if (exponent < 0) return 0;
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static List<int> _extendIntArrayPool(List<int> oldArray) {
    final newSize = oldArray.length * 2;
    final newArray = _rentIntArray(newSize);

    _fill(newArray, -1);
    final copyLength =
        oldArray.length < newSize ? oldArray.length : newSize; // Math.Min
    for (var i = 0; i < copyLength; i++) {
      newArray[i] = oldArray[i];
    }

    return newArray;
  }
}

enum CurrentState {
  none,
  awaitingState,
  awaitingStateLyric,
  attribute,
  attributeContent,
  timestamp,
  possiblyLyric,
  lyric,
}

enum TimeStampType { minutes, seconds, milliseconds, none }
