// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/XmlUtils.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'package:xml/xml.dart';

class XmlUtils {
  static final RegExp ampRegex =
      RegExp('&(?![a-zA-Z]{2,6};|#[0-9]{2,4};)');

  static final RegExp quotRegex = RegExp(
    '(\\s+[\\w:.-]+\\s*=\\s*")(([^"]*)((")((?!\\s+[\\w:.-]+\\s*=\\s*"|\\s*(?:/?|\\?)>))[^"]*)*)"',
  );

  static XmlDocument create(String content) {
    content = removeIllegalContent(content);

    content = replaceAmp(content);

    final contentWithQuot = replaceQuot(content);

    try {
      return XmlDocument.parse(contentWithQuot);
    } catch (_) {
      return XmlDocument.parse(content);
    }
  }

  static String replaceAmp(String content) {
    // replace & symbol
    return content.replaceAll(ampRegex, '&amp;');
  }

  static String replaceQuot(String content) {
    final sb = StringBuffer();

    var currentPos = 0;
    for (final match in quotRegex.allMatches(content)) {
      sb.write(content.substring(currentPos, match.start));

      //     .Replace("\"", "&quot;").Replace("<", "&lt;")) + "\""`。
      final f =
          '${match.group(1)!}${match.group(2)!.replaceAll('"', '&quot;').replaceAll('<', '&lt;')}"';

      sb.write(f);
      currentPos = match.end;
    }

    sb.write(content.substring(currentPos));

    return sb.toString();
  }

  static String removeIllegalContent(String content) {
    int left = 0, i = 0;
    while (i < content.length) {
      if (content[i] == '<') {
        left = i;
      }

      if (i > 0 && content[i] == '>' && content[i - 1] == '/') {
        final part = content.substring(left, i + 1);

        if (part.contains('=') &&
            part.indexOf('=') == part.lastIndexOf('=')) {
          final part1 = content.substring(left, left + part.indexOf('='));
          if (!part1.trim().contains(' ')) {
            content = content.substring(0, left) + content.substring(i + 1);
            i = 0;
            continue;
          }
        }
      }

      i++;
    }

    return content.trim();
  }

  ///
  static void recursionFindElement(
    XmlNode xmlNode,
    Map<String, String> mappingDict,
    Map<String, XmlNode> resDict,
  ) {
    String? nodeName;
    if (xmlNode is XmlElement) {
      nodeName = xmlNode.name.local;
    } else if (xmlNode is XmlText) {
      nodeName = '#text';
    }
    final value = nodeName == null ? null : mappingDict[nodeName];
    if (value != null) {
      resDict[value] = xmlNode;
    }

    if (xmlNode.children.isEmpty) {
      return;
    }

    for (var i = 0; i < xmlNode.children.length; i++) {
      recursionFindElement(xmlNode.children[i], mappingDict, resDict);
    }
  }
}
