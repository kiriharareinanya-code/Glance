// Ported from Lyricify.Lyrics.Helper/Parsers/AttributesHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   `KeyValuePair<string,string>` → `MapEntry<String,String>`
//   `LyricsData.File.AdditionalInfo.Attributes` → `GeneralAdditionalInfo.attributes`
library;

import '../helpers/general/string_helper.dart';
import '../models/additional_file_info.dart';
import '../models/lyrics_data.dart';
import '../models/track_metadata.dart';

class AttributesHelper {
  ///
  ///
  static (int? offset, int index) parseGeneralAttributesToLyricsDataByInput(
    LyricsData data,
    String input,
  ) {
    int? offset;
    data.trackMetadata ??= BasicTrackMetadata();

    var index = 0;
    for (; index < input.length; index++) {
      if (input[index] == '[') {
        final endIndex = input.indexOf('\n', index);
        final infoLine = input.substring(index, endIndex);
        if (isAttributeLine(infoLine)) {
          final attribute = getAttribute(infoLine);
          switch (attribute.key) {
            case 'ar':
              data.trackMetadata!.artist = attribute.value;
              break;
            case 'al':
              data.trackMetadata!.album = attribute.value;
              break;
            case 'ti':
              data.trackMetadata!.title = attribute.value;
              break;
            case 'length':
              final result = int.tryParse(attribute.value);
              if (result != null) {
                data.trackMetadata!.durationMs = result;
              }
              break;
            case 'offset':
              try {
                offset = int.parse(attribute.value);
              } catch (_) {}
              break;
          }
          final additionalInfo = data.file!.additionalInfo;
          if (additionalInfo is GeneralAdditionalInfo) {
            additionalInfo.attributes!.add(attribute);
          }

          index = endIndex;
        } else {
          break;
        }
      } else {
        break;
      }
    }
    return (offset, index);
  }

  /// 将 Attributes 信息解析到 LyricsData 中
  /// @returns Offset 值，若 Attributes 中没有，则为 `null`
  static int? parseGeneralAttributesToLyricsData(
    LyricsData data,
    List<String> lines,
  ) {
    int? offset;
    data.trackMetadata ??= BasicTrackMetadata();
    for (var i = 0; i < lines.length; i++) {
      if (isAttributeLine(lines[i])) {
        final attribute = getAttribute(lines[i]);
        switch (attribute.key) {
          case 'ar':
            data.trackMetadata!.artist = attribute.value;
            break;
          case 'al':
            data.trackMetadata!.album = attribute.value;
            break;
          case 'ti':
            data.trackMetadata!.title = attribute.value;
            break;
          case 'length':
            final result = int.tryParse(attribute.value);
            if (result != null) {
              data.trackMetadata!.durationMs = result;
            }
            break;
          case 'offset':
            try {
              offset = int.parse(attribute.value);
            } catch (_) {}
            break;
        }
        final additionalInfo = data.file!.additionalInfo;
        if (attribute.key == 'hash' && additionalInfo is KrcAdditionalInfo) {
          additionalInfo.hash = attribute.value;
        } else if (additionalInfo is GeneralAdditionalInfo) {
          additionalInfo.attributes!.add(attribute);
        }

        lines.removeAt(i--);
      } else {
        break;
      }
    }
    return offset;
  }

  static bool isAttributeLine(String line) {
    final trimmed = line.trim(); // 防止 \r 干扰
    return trimmed.startsWith('[') &&
        trimmed.endsWith(']') &&
        trimmed.contains(':');
  }

  static MapEntry<String, String> getAttribute(String line) {
    final trimmed = line.trim(); // 防止 \r 干扰
    final key = StringHelper.between(trimmed, '[', ':');
    final value =
        trimmed.substring(trimmed.indexOf(':') + 1, trimmed.length - 1);
    return MapEntry<String, String>(key, value);
  }
}
