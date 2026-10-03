// Ported from Lyricify.Lyrics.Helper/Parsers/TtmlParser.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// Apple Music TTML parser。
//
//   `XDocument.Parse(s, LoadOptions.PreserveWhitespace)` → `XmlDocument.parse(s)`
//     namespaceUri: uri)` + `getAttribute(local, namespaceUri: uri)`：
//       `el.Name == NsTtml + "span"`  → `_isNs(el, _ttmlUri, 'span')`
//       `(string?)el.Attribute(NsTtml + "x")` → `_attrNs(el, _ttmlUri, 'x')`
//   `doc.Descendants(X + "p")` → `doc.descendants.whereType<XmlElement>().where(...)`。
//   `params object?[] rootsAndKeys`（FindMetadataValue）→ `List<Object?> rootsAndKeys`。
//   `Dictionary<(string type, string lang), TranslationValue>` → `Map<TranslationKey, ...>`，
library;

import 'package:xml/xml.dart';

import '../models/additional_file_info.dart';
import '../models/file_info.dart';
import '../models/line_info.dart';
import '../models/lyrics_data.dart';
import '../models/lyrics_types.dart';
import '../models/syllable_info.dart';
import '../models/track_metadata.dart';

const String _ttmlUri = 'http://www.w3.org/ns/ttml';

const String _ttmUri = 'http://www.w3.org/ns/ttml#metadata';

const String _itunesUri = 'http://music.apple.com/lyric-ttml-internal';

const String _xmlUri = 'http://www.w3.org/XML/1998/namespace';

typedef TranslationKey = ({String type, String lang});

/// `el.Name == Ns + local`。
bool _isNs(XmlElement el, String nsUri, String local) =>
    el.name == XmlName.parts(local, namespaceUri: nsUri);

/// `(string?)el.Attribute(Ns + local)`。
String? _attrNs(XmlElement el, String nsUri, String local) =>
    el.getAttribute(local, namespaceUri: nsUri);

///
String _stringValue(XmlElement element) =>
    element.descendants.whereType<XmlText>().map((t) => t.value).join();

class TtmlParser {
  static LyricsData parse(String ttml,
      [bool useEmbeddedSimplifiedChineseLyrics = true]) {
    final data = LyricsData();
    data.trackMetadata = BasicTrackMetadata();
    final file = FileInfo();
    file.type = LyricsTypes.ttml;
    file.syncTypes = SyncTypes.syllableSynced;
    final additional = GeneralAdditionalInfo();
    additional.attributes = <MapEntry<String, String>>[];
    file.additionalInfo = additional;
    data.file = file;
    data.lines = <LineInfo>[];

    if (ttml.trim().isEmpty) return data;

    XmlDocument doc;
    try {
      doc = XmlDocument.parse(ttml);
    } catch (_) {
      return data;
    }

    _parseITunesMetadata(doc, data);
    final translations = _parseTranslations(doc);
    final agents = _parseAgents(doc);
    final agentAlignment = AgentAlignmentState(agents);
    final rootLanguage = _attrNs(doc.rootElement, _xmlUri, 'lang');
    if (!useEmbeddedSimplifiedChineseLyrics &&
        _isLanguage(rootLanguage, 'zh-Hant')) {
      data.trackMetadata!.language = [rootLanguage!.trim()];
    }

    final pNodes = doc.descendants
        .whereType<XmlElement>()
        .where((e) => _isNs(e, _ttmlUri, 'p'))
        .toList();
    final alignmentEntries = <({XmlElement node, int index, int startTime})>[];
    for (var index = 0; index < pNodes.length; index++) {
      final node = pNodes[index];
      alignmentEntries.add((
        node: node,
        index: index,
        startTime: _getLineStartTime(node) ?? 2147483647, // int.MaxValue
      ));
    }
    alignmentEntries.sort((a, b) {
      final byTime = a.startTime.compareTo(b.startTime);
      if (byTime != 0) return byTime;
      return a.index.compareTo(b.index);
    });
    final alignmentByLine = <XmlElement, LyricsAlignment>{};
    for (final entry in alignmentEntries) {
      alignmentByLine[entry.node] =
          agentAlignment.getAlignment(_attrNs(entry.node, _ttmUri, 'agent'));
    }
    var anyLineSynced = false;
    var anySyllableSynced = false;

    for (final p in pNodes) {
      final key = _attrNs(p, _itunesUri, 'key') ?? p.getAttribute('key');
      final align = alignmentByLine[p] ?? LyricsAlignment.unspecified;

      final mainSyllables = <SyllableInfo>[];
      final bgSyllables = <SyllableInfo>[];
      _collectSyllablesFromNodes(p.children, mainSyllables, bgSyllables, false);

      LineInfo? line;

      if (mainSyllables.isNotEmpty) {
        anySyllableSynced = true;
        line = SyllableLineInfo(mainSyllables);
      } else {
        final begin = _parseTimeMs(p.getAttribute('begin'));
        final end = _parseTimeMs(p.getAttribute('end'));
        final text = _normalizeText(_stringValue(p)).trim();

        if (text.trim().isNotEmpty && begin != null) {
          anyLineSynced = true;
          line = TextLineInfo(text, begin, end);
        }
      }

      if (line == null) continue;

      // Alignment
      _setAlignment(line, align);

      // Background -> SubLine
      if (bgSyllables.isNotEmpty) {
        _normalizeBracketInnerSpacingForBgLyrics(bgSyllables);

        final subLine = SyllableLineInfo(bgSyllables);
        _setAlignment(subLine, align);
        _setSubLine(line, subLine);
      }

      // Translations
      if (key != null && key.isNotEmpty && translations.containsKey(key)) {
        final tmap = translations[key]!;

        // replacement: replace MAIN line only
        String? replacementText;
        List<String>? replacementSpans;
        for (final kv in tmap.entries) {
          if (!_equalsIgnoreCase(kv.key.type, 'replacement')) continue;
          if (!useEmbeddedSimplifiedChineseLyrics &&
              _isLanguage(rootLanguage, 'zh-Hant') &&
              _isLanguage(kv.key.lang, 'zh-Hans')) {
            continue;
          }
          if (kv.value.text.trim().isNotEmpty) {
            replacementText = kv.value.text;
            replacementSpans = kv.value.spanTexts;
            break;
          }
        }

        if (replacementText != null) {
          line =
              _applyReplacementMainOnly(line, replacementText, replacementSpans);
          _setAlignment(line, align);
        }

        // subtitle translations
        final subtitles = <MapEntry<TranslationKey, String>>[];
        for (final kv in tmap.entries) {
          if (_equalsIgnoreCase(kv.key.type, 'subtitle')) {
            subtitles.add(MapEntry(kv.key, kv.value.text));
          }
        }

        if (subtitles.isNotEmpty) {
          line = _applySubtitleTranslations(line, subtitles);
          _setAlignment(line, align);
        }
      }

      data.lines!.add(line);
    }

    if (anyLineSynced && anySyllableSynced) {
      data.file!.syncTypes = SyncTypes.mixedSynced;
    } else if (anyLineSynced) {
      data.file!.syncTypes = SyncTypes.lineSynced;
    } else if (anySyllableSynced) {
      data.file!.syncTypes = SyncTypes.syllableSynced;
    } else {
      data.file!.syncTypes = SyncTypes.unknown;
    }

    return data;
  }
}

// =========================
// Safe setters (ILineInfo has readonly properties)
// =========================
//

void _setAlignment(LineInfo line, LyricsAlignment alignment) {
  line.lyricsAlignment = alignment;
}

void _setSubLine(LineInfo line, LineInfo? subLine) {
  line.subLine = subLine;
}

class Agent {
  String id = '';
  String type = ''; // person/group/other/...
}

class AgentAlignmentState {
  AgentAlignmentState(List<Agent> agents) {
    _agents = <String, Agent>{};
    for (final agent in agents) {
      _agents.putIfAbsent(agent.id, () => agent);
    }
    _hasAgentMetadata = _agents.isNotEmpty;
    _isDuet = _agents.length > 1;
  }

  late final Map<String, Agent> _agents;
  late final bool _hasAgentMetadata;
  late final bool _isDuet;
  String? _currentPersonId;
  bool _isFlipped = false;

  LyricsAlignment getAlignment(String? agentId) {
    if (!_hasAgentMetadata) return LyricsAlignment.unspecified;

    if (!_isDuet) return LyricsAlignment.left;

    if (agentId != null && agentId.trim().isNotEmpty) {
      final agent = _agents[agentId.trim()];
      if (agent != null) {
        if (_equalsIgnoreCase(agent.type, 'person')) {
          if (_currentPersonId == null) {
            _currentPersonId = agent.id;
          } else if (_currentPersonId != agent.id) {
            _isFlipped = !_isFlipped;
            _currentPersonId = agent.id;
          }
        } else if (_equalsIgnoreCase(agent.type, 'group')) {
          return LyricsAlignment.left;
        } else if (_equalsIgnoreCase(agent.type, 'other')) {
          return LyricsAlignment.right;
        }
      }
    }

    return _isFlipped ? LyricsAlignment.right : LyricsAlignment.left;
  }
}

class TranslationValue {
  String text = '';
  List<String> spanTexts = <String>[];
}

// =========================
// Duet alignment
// =========================
List<Agent> _parseAgents(XmlDocument doc) {
  final agents = <Agent>[];
  for (final a in doc.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _ttmUri, 'agent'))) {
    final id = _attrNs(a, _xmlUri, 'id');
    if (id == null || id.trim().isEmpty) continue;

    final type = (a.getAttribute('type') ?? '').trim();
    agents.add(Agent()
      ..id = id.trim()
      ..type = type);
  }
  return agents;
}

// =========================
// iTunes metadata + translations
// =========================
void _parseITunesMetadata(XmlDocument doc, LyricsData data) {
  XmlElement? metadata;
  for (final e in doc.descendants.whereType<XmlElement>()) {
    if (_isNs(e, _ttmlUri, 'metadata')) {
      metadata = e;
      break;
    }
  }
  XmlElement? meta;
  for (final e in doc.descendants.whereType<XmlElement>()) {
    if (_isNs(e, _itunesUri, 'iTunesMetadata')) {
      meta = e;
      break;
    }
  }

  _parseTrackMetadata(doc, metadata, meta, data);

  if (meta == null) return;

  final leadingSilence = meta.getAttribute('leadingSilence');
  if (leadingSilence != null && leadingSilence.trim().isNotEmpty) {
    (data.file!.additionalInfo as GeneralAdditionalInfo)
        .attributes!
        .add(MapEntry('leadingSilence', leadingSilence));
  }

  final writers = meta.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _itunesUri, 'songwriter'))
      .map((x) => _stringValue(x).trim())
      .where((x) => x.trim().isNotEmpty)
      .toList();

  if (writers.isNotEmpty) data.writers = writers;
}

void _parseTrackMetadata(XmlDocument doc, XmlElement? metadata,
    XmlElement? iTunesMetadata, LyricsData data) {
  data.trackMetadata ??= BasicTrackMetadata();
  final track = data.trackMetadata!;

  _setIfEmpty((x) => track.title = x, track.title, _findMetadataValue([
    iTunesMetadata,
    metadata,
    doc.rootElement,
    'title',
    'trackTitle',
    'songTitle',
    'songName',
    'musicName'
  ]));
  _setIfEmpty((x) => track.artist = x, track.artist, _findMetadataValue([
    iTunesMetadata,
    metadata,
    doc.rootElement,
    'artist',
    'artists',
    'artistName',
    'songArtist',
    'singer',
    'performer',
    'performers'
  ]));
  _setIfEmpty(
      (x) => track.album = x,
      track.album,
      _findMetadataValue(
          [iTunesMetadata, metadata, doc.rootElement, 'album', 'albumName']));
  _setIfEmpty(
      (x) => track.albumArtist = x,
      track.albumArtist,
      _findMetadataValue([
        iTunesMetadata,
        metadata,
        doc.rootElement,
        'albumArtist',
        'albumArtistName'
      ]));
  _setIfEmpty((x) => track.isrc = x, track.isrc,
      _findMetadataValue([iTunesMetadata, metadata, doc.rootElement, 'isrc']));

  if (track.durationMs == null) {
    String? bodyDur;
    for (final x in doc.descendants
        .whereType<XmlElement>()
        .where((e) => _isNs(e, _ttmlUri, 'body'))) {
      final dur = x.getAttribute('dur');
      if (dur != null && dur.trim().isNotEmpty) {
        bodyDur = dur;
        break;
      }
    }

    final duration = _parseTimeMs(bodyDur) ??
        _parseMetadataDuration(iTunesMetadata, metadata, doc.rootElement);
    if (duration != null) track.durationMs = duration;
  }

  final rootLang = _attrNs(doc.rootElement, _xmlUri, 'lang');
  String? simplifiedReplacementLang;
  for (final x in doc.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _itunesUri, 'translation'))) {
    if (!_equalsIgnoreCase(
        (x.getAttribute('type') ?? '').trim(), 'replacement')) {
      continue;
    }
    final lang = (_attrNs(x, _xmlUri, 'lang') ?? '').trim();
    if (_isLanguage(rootLang, 'zh-Hant') && _isLanguage(lang, 'zh-Hans')) {
      simplifiedReplacementLang = lang;
      break;
    }
  }

  if (simplifiedReplacementLang != null &&
      simplifiedReplacementLang.trim().isNotEmpty) {
    track.language = ['zh-Hans'];
  } else if (rootLang != null && rootLang.trim().isNotEmpty) {
    track.language = [rootLang.trim()];
  }
}

void _setIfEmpty(
    void Function(String) setter, String? currentValue, String? newValue) {
  if ((currentValue == null || currentValue.trim().isEmpty) &&
      newValue != null &&
      newValue.trim().isNotEmpty) {
    setter(newValue.trim());
  }
}

String? _findMetadataValue(List<Object?> rootsAndKeys) {
  final roots = <XmlElement>[];
  for (final o in rootsAndKeys) {
    if (o is XmlElement && !roots.contains(o)) roots.add(o);
  }
  final keys = <String>{
    for (final o in rootsAndKeys)
      if (o is String) _normalizeMetadataKey(o).toLowerCase(),
  };

  for (final root in roots) {
    for (final element in _descendantsAndSelf(root)) {
      for (final attr in element.attributes) {
        if (keys.contains(_normalizeMetadataKey(attr.name.local).toLowerCase()) &&
            attr.value.trim().isNotEmpty) {
          return attr.value.trim();
        }
      }

      final key = _getMetadataKey(element);
      if (key != null &&
          key.trim().isNotEmpty &&
          keys.contains(_normalizeMetadataKey(key).toLowerCase())) {
        final value = _getMetadataValue(element);
        if (value != null && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      if (keys.contains(
          _normalizeMetadataKey(element.name.local).toLowerCase())) {
        final value = _getElementOwnText(element);
        if (value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
  }

  return null;
}

int? _parseMetadataDuration(
    XmlElement? root0, XmlElement? root1, XmlElement? root2) {
  for (final key in const [
    'durationMs',
    'durationInMillis',
    'duration',
    'length'
  ]) {
    final value = _findMetadataValue([root0, root1, root2, key]);
    if (value == null || value.trim().isEmpty) continue;

    final integerValue = int.tryParse(value.trim());
    if (integerValue != null &&
        (key.toLowerCase().contains('ms') ||
            key.toLowerCase().contains('millis') ||
            integerValue > 10000)) {
      return integerValue;
    }

    final parsed = _parseTimeMs(value);
    if (parsed != null) return parsed;
  }

  return null;
}

String? _getMetadataKey(XmlElement element) =>
    element.getAttribute('key') ??
    element.getAttribute('name') ??
    element.getAttribute('property');

String? _getMetadataValue(XmlElement element) =>
    element.getAttribute('value') ??
    element.getAttribute('content') ??
    _getElementOwnText(element);

String _getElementOwnText(XmlElement element) => element.children
    .whereType<XmlText>()
    .map((t) => t.value)
    .join()
    .trim();

String _xmlNodeValue(XmlNode node) =>
    node is XmlText ? node.value : (node.value ?? '');

String _normalizeMetadataKey(String key) =>
    key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

bool _isLanguage(String? lang, String languagePrefix) =>
    lang != null &&
    lang.trim().isNotEmpty &&
    (_equalsIgnoreCase(lang, languagePrefix) ||
        lang.toLowerCase().startsWith('${languagePrefix.toLowerCase()}-'));

bool _equalsIgnoreCase(String? a, String? b) =>
    a != null && b != null && a.toLowerCase() == b.toLowerCase();

Iterable<XmlElement> _descendantsAndSelf(XmlElement element) sync* {
  yield element;
  yield* element.descendants.whereType<XmlElement>();
}

Map<String, Map<TranslationKey, TranslationValue>> _parseTranslations(
    XmlDocument doc) {
  final result = <String, Map<TranslationKey, TranslationValue>>{};

  for (final translation in doc.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _itunesUri, 'translation'))) {
    final type = (translation.getAttribute('type') ?? '').trim();
    final lang = (_attrNs(translation, _xmlUri, 'lang') ?? '').trim();

    for (final textNode in translation.childElements
        .where((e) => _isNs(e, _itunesUri, 'text'))) {
      final key = (textNode.getAttribute('for') ?? '').trim();
      if (key.isEmpty) continue;

      final value = _normalizeText(_stringValue(textNode)).trim();
      if (value.isEmpty) continue;

      final map =
          result.putIfAbsent(key, () => <TranslationKey, TranslationValue>{});

      map[(type: type, lang: lang)] = TranslationValue()
        ..text = value
        ..spanTexts = _extractTimedSpanTexts(textNode);
    }
  }

  return result;
}

List<String> _extractTimedSpanTexts(XmlElement textNode) {
  return textNode.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _ttmlUri, 'span'))
      .where((x) {
        final begin = x.getAttribute('begin');
        return begin != null && begin.trim().isNotEmpty;
      })
      .map((x) => _normalizeText(_stringValue(x)))
      .where((x) => x.isNotEmpty)
      .toList();
}

// =========================
// Syllable collection (main + background)
// =========================
void _collectSyllablesFromNodes(Iterable<XmlNode> nodes,
    List<SyllableInfo> main, List<SyllableInfo> bg, bool isBackgroundContext) {
  for (final node in nodes) {
    if (node is XmlText || node is XmlCDATA) {
      _appendToPrevious(_xmlNodeValue(node), isBackgroundContext ? bg : main);
      continue;
    }

    if (node is XmlElement) {
      if (_isNs(node, _ttmlUri, 'span')) {
        final role = _attrNs(node, _ttmUri, 'role') ?? node.getAttribute('role');
        final isBg = isBackgroundContext || _equalsIgnoreCase(role, 'x-bg');

        final beginAttr = node.getAttribute('begin');
        if (beginAttr != null && beginAttr.trim().isNotEmpty) {
          final beginMs = _parseTimeMs(beginAttr);
          final endMs = _parseTimeMs(node.getAttribute('end')) ?? beginMs;

          if (beginMs != null) {
            var raw = _normalizeText(_stringValue(node));

            // Spaces belong to previous token
            raw = _moveLeadingSpacesToPrevious(raw, isBg ? bg : main);

            if (raw.isNotEmpty) {
              (isBg ? bg : main).add(TextSyllableInfo(raw, beginMs, endMs!));
            }
          }
        } else {
          // container span
          _collectSyllablesFromNodes(node.children, main, bg, isBg);
        }
      } else {
        _collectSyllablesFromNodes(
            node.children, main, bg, isBackgroundContext);
      }
    }
  }
}

void _appendToPrevious(String text, List<SyllableInfo> list) {
  if (text.isEmpty || list.isEmpty) return;
  text = _normalizeText(text);
  if (text.isEmpty) return;

  // whitespace/punct belongs to previous syllable
  final last = list.last as TextSyllableInfo;
  last.text = last.text + text;
}

String _moveLeadingSpacesToPrevious(String text, List<SyllableInfo> list) {
  if (text.isEmpty || list.isEmpty) return text;

  var i = 0;
  while (i < text.length && _isWhiteSpace(text[i])) {
    i++;
  }
  if (i == 0) return text;

  final last = list.last as TextSyllableInfo;
  last.text = last.text + text.substring(0, i);
  return text.substring(i);
}

bool _isWhiteSpace(String ch) => ch.trim().isEmpty;

void _normalizeBracketInnerSpacingForBgLyrics(List<SyllableInfo> syllables) {
  if (syllables.isEmpty) return;

  final first = syllables.first as TextSyllableInfo;
  first.text = first.text.replaceAll(RegExp(r'\s+(\(|（)'), r'$1');

  final last = syllables.last as TextSyllableInfo;
  last.text = last.text.replaceAll(RegExp(r'(\)|）)\s+'), r'$1');
}

// =========================
// Replacement / subtitle translations
// =========================
String _replacementNormalizeText(String? s) =>
    (s ?? '').replaceAll('\r', '').replaceAll('\n', '');

String _replacementNormalizeSpaces(String? s) =>
    (s ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

LineInfo _applyReplacementMainOnly(
    LineInfo line, String replacement, List<String>? replacementParts) {
  // Extract ONLY the first bracket segment (supports () and （）).
  (String, String?) splitFirstBracketSegmentKeepBrackets(String text) {
    text = _replacementNormalizeText(text);

    final m = RegExp(r'\(([^)]*)\)|（([^）]*)）').firstMatch(text);
    if (m == null) return (_replacementNormalizeSpaces(text), null);

    // matched string includes brackets already
    final bracketSeg = m.group(0)!;

    // remove only this first match
    var main = text.substring(0, m.start) + text.substring(m.end);
    main = _replacementNormalizeSpaces(main);

    return (main, bracketSeg);
  }

  // For background: remove spaces OUTSIDE brackets,
  // keep brackets themselves and inner content unchanged.
  String normalizeBracketOuterSpaces(String s) {
    s = _replacementNormalizeText(s);

    // Remove spaces before '(' or '（'
    s = s.replaceAll(RegExp(r'\s+(\(|（)'), r'$1');
    // Remove spaces after ')' or '）'
    s = s.replaceAll(RegExp(r'(\)|）)\s+'), r'$1');

    return s;
  }

  // Replace a syllable line's text with best-effort length mapping; fallback to single syllable
  SyllableLineInfo replaceSyllableLineText(
      SyllableLineInfo sLine, String newText) {
    newText = _replacementNormalizeText(newText);

    final sylls = sLine.syllables.toList();
    final lens = sylls.map((s) => s.text.length).toList();
    final totalLen = lens.fold<int>(0, (a, b) => a + b);

    if (totalLen == newText.length && totalLen > 0) {
      var idx = 0;
      final newSylls = <SyllableInfo>[];

      for (var i = 0; i < sylls.length; i++) {
        final len = lens[i];
        final chunk = len > 0 ? newText.substring(idx, idx + len) : '';
        idx += len;

        newSylls
            .add(TextSyllableInfo(chunk, sylls[i].startTime, sylls[i].endTime));
      }

      return SyllableLineInfo(newSylls);
    }

    // fallback: collapse to one syllable spanning the original line time range
    final start = sLine.startTime ?? 0;
    final end = sLine.endTime ?? start;
    return SyllableLineInfo([TextSyllableInfo(newText, start, end)]);
  }

  SyllableLineInfo? replaceSyllableLineParts(
      SyllableLineInfo sLine, List<String>? newParts) {
    if (newParts == null ||
        newParts.isEmpty ||
        newParts.length != sLine.syllables.length) {
      return null;
    }

    final newSylls = <SyllableInfo>[];
    for (var i = 0; i < sLine.syllables.length; i++) {
      final syllable = sLine.syllables[i];
      final originalText = syllable.text;
      final replacementText = _replacementNormalizeText(newParts[i]);

      final leading = RegExp(r'^\s+').firstMatch(originalText)?.group(0) ?? '';
      final trailing = RegExp(r'\s+$').firstMatch(originalText)?.group(0) ?? '';
      newSylls.add(TextSyllableInfo(leading + replacementText + trailing,
          syllable.startTime, syllable.endTime));
    }

    return SyllableLineInfo(newSylls);
  }

  // Replace a line's text (mainly for TextLineInfo)
  //
  TextLineInfo replaceLineText(TextLineInfo li, String newText) {
    li.text = _replacementNormalizeText(newText);
    return li;
  }

  replacement = _replacementNormalizeText(replacement);

  // Preserve existing subline reference (may be null)
  final existingSub = line.subLine;

  // If this line has background vocals (SubLine exists), split replacement by FIRST bracket segment:
  // - main replacement removes the bracket segment
  // - bg replacement uses the bracket segment (keeps brackets)
  var mainReplacement = replacement;
  String? bgReplacement;

  if (existingSub != null) {
    final (mainText, bracketSegmentWithBrackets) =
        splitFirstBracketSegmentKeepBrackets(replacement);
    mainReplacement = mainText;
    bgReplacement = bracketSegmentWithBrackets;

    if (bgReplacement != null && bgReplacement.trim().isNotEmpty) {
      bgReplacement = normalizeBracketOuterSpaces(bgReplacement);
    }
  }

  // ---- Apply to MAIN line ----
  LineInfo newMain;

  if (line is SyllableLineInfo) {
    newMain = replaceSyllableLineParts(
            line, existingSub == null ? replacementParts : null) ??
        replaceSyllableLineText(line, mainReplacement);
  } else {
    newMain = replaceLineText(line as TextLineInfo, mainReplacement);
  }

  // ---- Apply to SUBLINE (background) if we extracted a bracket segment and subline exists ----
  if (existingSub != null &&
      bgReplacement != null &&
      bgReplacement.trim().isNotEmpty) {
    var newSub = existingSub;

    if (existingSub is SyllableLineInfo) {
      newSub = replaceSyllableLineText(existingSub, bgReplacement);
    } else if (existingSub is TextLineInfo) {
      newSub = replaceLineText(existingSub, bgReplacement);
    }

    // Attach subline back
    newMain.subLine = newSub;
  } else {
    // Keep existing subline if any
    if (existingSub != null) {
      newMain.subLine = existingSub;
    }
  }

  return newMain;
}

LineInfo _applySubtitleTranslations(
    LineInfo line, List<MapEntry<TranslationKey, String>> subtitles) {
  final align = line.lyricsAlignment;
  final subLine = line.subLine; // may be null

  // Build lang->value map (dedupe)
  //
  // `Dictionary<string,string>(StringComparer.OrdinalIgnoreCase)` + `ContainsKey`
  final dict = <String, String>{};
  for (final kv in subtitles) {
    final langKey = _normalizeLangKey(kv.key.lang);
    dict.putIfAbsent(langKey, () => kv.value);
  }

  // Parenthesized background translations never belong to the main line,
  // even when the TTML has no corresponding background vocal syllables.
  // Only attach them to a subline when one exists.
  final bgDict = subLine != null ? <String, String>{} : null;
  for (final k in dict.keys.toList()) {
    final (mainText, bgText) = _splitSubtitleByParentheses(dict[k]!);
    if (mainText.trim().isEmpty) {
      dict.remove(k);
    } else {
      dict[k] = mainText;
    }

    if (bgDict != null && bgText != null && bgText.trim().isNotEmpty) {
      bgDict[k] = bgText;
    }
  }

  // Apply to MAIN line
  LineInfo mainOut;
  if (line is SyllableLineInfo) {
    final FullSyllableLineInfo full =
        line is FullSyllableLineInfo ? line : FullSyllableLineInfo.fromLine(line);
    for (final kv in dict.entries) {
      if (!full.translations.containsKey(kv.key)) {
        full.translations[kv.key] = kv.value;
      }
    }
    mainOut = full;
  } else {
    final FullTextLineInfo full = line is FullTextLineInfo
        ? line
        : FullTextLineInfo.fromLine(line as TextLineInfo);
    for (final kv in dict.entries) {
      if (!full.translations.containsKey(kv.key)) {
        full.translations[kv.key] = kv.value;
      }
    }
    mainOut = full;
  }

  // Apply to SUBLINE (background translation) if extracted
  if (subLine != null && bgDict != null && bgDict.isNotEmpty) {
    LineInfo subOut = subLine;

    if (subLine is SyllableLineInfo) {
      final FullSyllableLineInfo subFull = subLine is FullSyllableLineInfo
          ? subLine
          : FullSyllableLineInfo.fromLine(subLine);
      for (final kv in bgDict.entries) {
        if (!subFull.translations.containsKey(kv.key)) {
          subFull.translations[kv.key] = kv.value;
        }
      }
      subOut = subFull;
    } else if (subLine is TextLineInfo) {
      final FullTextLineInfo subFull =
          subLine is FullTextLineInfo ? subLine : FullTextLineInfo.fromLine(subLine);
      for (final kv in bgDict.entries) {
        if (!subFull.translations.containsKey(kv.key)) {
          subFull.translations[kv.key] = kv.value;
        }
      }
      subOut = subFull;
    }

    // reattach subline to main
    _setSubLine(mainOut, subOut);
  } else {
    // keep existing subline
    _setSubLine(mainOut, subLine);
  }

  // keep alignment
  _setAlignment(mainOut, align);
  return mainOut;
}

(String, String?) _splitSubtitleByParentheses(String value) {
  value = _normalizeText(value);

  final m = RegExp(r'\(([^)]*)\)|（([^）]*)）').firstMatch(value);
  if (m == null) {
    return (_normalizeSpaces(value), null);
  }

  var inner = m.group(1) ?? m.group(2) ?? '';
  inner = _normalizeSpaces(inner);

  var main = value.substring(0, m.start) + value.substring(m.end);
  main = _normalizeSpaces(main);

  return (main, inner.trim().isEmpty ? null : inner);
}

String _normalizeSpaces(String s) {
  s = s.trim();
  // collapse whitespace runs into single spaces
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

String _normalizeLangKey(String lang) {
  if (lang.trim().isEmpty) return 'und';
  lang = lang.trim();
  if (lang.toLowerCase().startsWith('zh')) return 'zh';
  return lang;
}

// =========================
// Time parsing
// =========================
String _normalizeText(String text) =>
    text.replaceAll('\r', '').replaceAll('\n', '');

int? _getLineStartTime(XmlElement line) {
  final lineStart = _parseTimeMs(line.getAttribute('begin'));
  if (lineStart != null) return lineStart;

  final spanStarts = line.descendants
      .whereType<XmlElement>()
      .where((e) => _isNs(e, _ttmlUri, 'span'))
      .map((span) => _parseTimeMs(span.getAttribute('begin')))
      .where((time) => time != null)
      .map((time) => time!)
      .toList();

  if (spanStarts.isEmpty) return null;
  return spanStarts.reduce((a, b) => a < b ? a : b);
}

int? _parseTimeMs(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  value = value.trim();

  if (value.toLowerCase().endsWith('s')) {
    value = value.substring(0, value.length - 1);
  }

  try {
    if (value.contains(':')) {
      final parts = value.split(':');
      double seconds;

      if (parts.length == 2) {
        final minutes = _parseInvariantDouble(parts[0]);
        final sec = _parseInvariantDouble(parts[1]);
        seconds = minutes * 60.0 + sec;
      } else if (parts.length == 3) {
        final hours = _parseInvariantDouble(parts[0]);
        final minutes = _parseInvariantDouble(parts[1]);
        final sec = _parseInvariantDouble(parts[2]);
        seconds = hours * 3600.0 + minutes * 60.0 + sec;
      } else {
        seconds = _parseInvariantDouble(value.replaceAll(':', '.'));
      }

      return _roundHalfAwayFromZero(seconds * 1000.0);
    }

    final s2 = _parseInvariantDouble(value);
    return _roundHalfAwayFromZero(s2 * 1000.0);
  } catch (_) {
    return null;
  }
}

double _parseInvariantDouble(String s) {
  final v = double.tryParse(s.trim());
  if (v == null) throw const FormatException('invalid double');
  return v;
}

int _roundHalfAwayFromZero(double value) {
  if (value.isNaN) throw const FormatException('NaN');
  if (value.isInfinite) throw const FormatException('Infinity');
  final floor = value.floorToDouble();
  final diff = value - floor;
  if (diff > 0.5) return (floor + 1).toInt();
  if (diff < 0.5) return floor.toInt();
  return value >= 0 ? (floor + 1).toInt() : floor.toInt();
}
