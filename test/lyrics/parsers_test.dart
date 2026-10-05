// W-A 测试：解析器 + 解密器（逐行对照上游 Lyricify.Lyrics.Helper）。
//
// 断言基线来自**上游 C# 代码本身**：
//   用 `Lyricify.Lyrics.Demo` 引用的同一个 `Lyricify.Lyrics.Helper` 程序集，
//   对同一批 `RawLyrics/*.txt` 调用 LrcParser/QrcParser/KrcParser/YrcParser/
//   LyricifyLinesParser，把结果序列化成 `*.golden.json`
//   （构建/生成脚本是一次性的，不随仓库交付）。
// 所以本文件里的 `*.golden.json` 就是"上游行为"的等价物，不是我自己算的期望值。
//
// 加密向量同理：`QrcEncrypted.txt` / `KrcToken.txt` 是用上游 `DESHelper`（加密方向）
// 和 KRC 逆算法生成的密文，明文分别是 QrcDemo.txt / KrcDemo.txt；
// 生成时已用上游 Decrypter 验证过 round-trip。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/decrypters/krc/decrypter.dart' as krc_decrypter;
import 'package:vectra/lyrics/decrypters/krc/model.dart';
import 'package:vectra/lyrics/decrypters/qrc/decrypter.dart' as qrc_decrypter;
import 'package:vectra/lyrics/decrypters/qrc/xml_utils.dart';
import 'package:vectra/lyrics/models/additional_file_info.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/parsers/krc_parser.dart';
import 'package:vectra/lyrics/parsers/lrc_parser.dart';
import 'package:vectra/lyrics/parsers/lyricify_lines_parser.dart';
import 'package:vectra/lyrics/parsers/musixmatch_parser.dart';
import 'package:vectra/lyrics/parsers/qrc_parser.dart';
import 'package:vectra/lyrics/parsers/spotify_parser.dart';
import 'package:vectra/lyrics/parsers/ttml_parser.dart';
import 'package:vectra/lyrics/parsers/yrc_parser.dart';
import 'package:xml/xml.dart';

const _fixtureDir = 'test/fixtures/lyricify';

String _fixture(String name) =>
    File('$_fixtureDir/$name').readAsStringSync();

/// 读取上游解析结果的黄金 JSON。
Map<String, dynamic> _golden(String name) => jsonDecode(
      File('$_fixtureDir/$name.golden.json').readAsStringSync(),
    ) as Map<String, dynamic>;

// ---------------------------------------------------------------------------
// 把 Dart 的 LyricsData 规格化成与黄金 JSON 完全同构的 Map。
// ---------------------------------------------------------------------------

/// 行/音节的类型名映射：Dart 用宿主契约里的类名，黄金 JSON 用上游 C# 类名。
const _lineKind = <String, String>{
  'TextLineInfo': 'LineInfo',
  'SyllableLineInfo': 'SyllableLineInfo',
  'FullTextLineInfo': 'FullLineInfo',
  'FullSyllableLineInfo': 'FullSyllableLineInfo',
};

const _syllableKind = <String, String>{
  'TextSyllableInfo': 'SyllableInfo',
  'FullSyllableInfo': 'FullSyllableInfo',
};

String _enumName(Object e) {
  final name = e.toString().split('.').last;
  return name[0].toUpperCase() + name.substring(1);
}

Map<String, dynamic> _describeLine(LineInfo line) {
  final map = <String, dynamic>{
    'kind': _lineKind[line.runtimeType.toString()] ?? line.runtimeType.toString(),
    'text': line.text,
    'startTime': line.startTime,
    'endTime': line.endTime,
    'alignment': _enumName(line.lyricsAlignment),
  };
  if (line is SyllableLineInfo) {
    map['syllableCount'] = line.syllables.length;
    map['syllables'] = [
      for (final s in line.syllables)
        {
          'kind': _syllableKind[s.runtimeType.toString()] ??
              s.runtimeType.toString(),
          'text': s.text,
          'startTime': s.startTime,
          'endTime': s.endTime,
        },
    ];
  }
  if (line is FullLineInfoMixin) {
    map['translations'] =
        line.translations.isEmpty ? null : Map<String, dynamic>.from(line.translations);
    map['pronunciation'] = line.pronunciation;
  }
  if (line.subLine != null) {
    map['subLine'] = _describeLine(line.subLine!);
  }
  return map;
}

Map<String, dynamic> _describe(LyricsData data) {
  final file = data.file;
  final info = file?.additionalInfo;
  return <String, dynamic>{
    'file': file == null
        ? null
        : <String, dynamic>{
            'type': _enumName(file.type),
            'syncTypes': _enumName(file.syncTypes),
            'attributes': info is GeneralAdditionalInfo
                ? info.attributes
                    ?.map((a) => <String>[a.key, a.value])
                    .toList()
                : null,
            'krcHash': info is KrcAdditionalInfo ? info.hash : null,
          },
    'writers': data.writers,
    'trackMetadata': data.trackMetadata == null
        ? null
        : <String, dynamic>{
            'title': data.trackMetadata!.title,
            'artist': data.trackMetadata!.artist,
            'album': data.trackMetadata!.album,
            'durationMs': data.trackMetadata!.durationMs,
          },
    'lines': data.lines?.map(_describeLine).toList(),
  };
}

/// 统一的对比：失败时打印第一处差异，而不是整份 JSON。
void _expectSameAsGolden(Map<String, dynamic> actual, String name) {
  final golden = _golden(name);
  final lines = actual['lines'] as List?;
  final goldenLines = golden['lines'] as List?;
  expect(lines?.length, goldenLines?.length, reason: '$name 行数');
  for (var i = 0; i < (goldenLines?.length ?? 0); i++) {
    expect(
      jsonEncode(actual['lines'][i]),
      jsonEncode(goldenLines![i]),
      reason: '$name 第 $i 行',
    );
  }
  expect(jsonEncode(actual['file']), jsonEncode(golden['file']), reason: '$name file');
  expect(jsonEncode(actual['writers']), jsonEncode(golden['writers']),
      reason: '$name writers');
  expect(jsonEncode(actual['trackMetadata']), jsonEncode(golden['trackMetadata']),
      reason: '$name trackMetadata');
}

void main() {
  group('LrcParser', () {
    test('LrcDemo 与上游逐行一致（100 行 / 首末时间戳 / 多时间戳行）', () {
      final data = LrcParser.parse(_fixture('LrcDemo.txt'));
      _expectSameAsGolden(_describe(data), 'LrcDemo');

      final lines = data.lines!;
      expect(lines.length, 100);
      // 上游 fixture 第 3 行是 `[00:01.670][01:17.870]...`，会产生两条同文本行
      expect(lines[2].text, "Lately, I've been, I've been losing sleep");
      expect(lines[2].startTime, 1670);
      // 上游 LrcParser.cs:246 `lines.Sort()`（LineInfo.CompareTo 按 StartTime 升序，
      // 见 Models/LineInfo.cs:35-45），所以同一行里的第二个时间戳 77870 **不会**紧跟
      // 在 1670 后面，而是被排到全曲对应位置（golden 第 23 行）。
      // 第 3 行是紧接着的下一句，不是同一句的另一个时间戳。
      expect(lines[3].text, 'Dreaming about the things that we could be');
      expect(lines[3].startTime, 4850);
      expect(lines[23].text, "Lately, I've been, I've been losing sleep");
      expect(lines[23].startTime, 77870);
      expect(lines.first.startTime, 0);
      expect(lines.last.startTime, 252350);
      // LRC 只有行时间，EndTime 全为 null
      expect(lines.every((l) => l.endTime == null), isTrue);
    });

    test('offset 属性参与时间戳计算（[offset:0] 时原样）', () {
      final data = LrcParser.parse('[offset:1000]\n[00:10.000]hello');
      // 上游 LrcParser.cs:43 是 `curTimestamps[j] - offset`，offset 是**减**的：
      // [offset:1000] + 00:10.000 → 10000 - 1000 = 9000，不是 10000。
      expect(data.lines!.single.startTime, 9000);
      expect(data.trackMetadata!.durationMs, isNull);

      final shifted = LrcParser.parse('[offset:1000]\n[00:10.000]hello'.replaceAll(
        '[offset:1000]',
        '[offset:-500]',
      ));
      // 上游 LrcParser.cs:176 的累加是 `timeCalculationCache * 10 + curChar - '0'`，
      // **不认负号**：'-'(45) - '0'(48) = -3，于是 "-500" 被累成
      // (-3)*10+5=-25 → -250 → -2500，即 offset = -2500（不是 -500）。
      // 再按 :43 的 `curTimestamps[j] - offset` → 10000 - (-2500) = 12500。
      expect(shifted.lines!.single.startTime, 12500);
    });

    test('无毫秒时间戳按秒计算', () {
      final data = LrcParser.parse('[00:05]no milliseconds');
      expect(data.lines!.single.startTime, 5000);
      expect(data.lines!.single.text, 'no milliseconds');
    });

    test('parseLyrics 只返回行（不建立 LyricsData）', () {
      final lines = LrcParser.parseLyrics(_fixture('LrcDemo.txt'));
      expect(lines.length, 100);
      expect(lines.first.text, '作词 : Ryan Tedder');
      expect(lines.last.startTime, 252350);
    });
  });

  group('QrcParser', () {
    test('QrcDemo 与上游逐行一致（39 行 / 逐字音节 / 属性）', () {
      final data = QrcParser.parse(_fixture('QrcDemo.txt'));
      _expectSameAsGolden(_describe(data), 'QrcDemo');

      final lines = data.lines!.cast<SyllableLineInfo>();
      expect(lines.length, 39);
      // 上游 QrcParser.cs:69 `line = line[(line.IndexOf("]") + 1)..]` 先把
      // `[0,4390]` 这样的行前缀整段丢掉，所以逐字时间戳从 0 重新计，
      // 行的 endTime 来自最后一个音节（4384），而不是前缀里的 4390。
      // 'Stop and Stare' 是 [ti:] 元数据（trackMetadata.title），不是首行歌词文本。
      expect(lines.first.text, 'Stop And Stare - OneRepublic (共和时代)');
      expect(lines.first.startTime, 0);
      expect(lines.first.endTime, 4384);
      expect(lines.last.startTime, 212532);
      expect(lines.last.endTime, 216901);
      expect(lines.first.syllables.length, 16);

      final info = data.file!.additionalInfo as GeneralAdditionalInfo;
      expect(
        info.attributes!.map((a) => '${a.key}=${a.value}').toList(),
        ['ti=Stop and Stare', 'ar=OneRepublic', 'al=Dreaming Out Loud', 'by=', 'offset=0'],
      );
      expect(data.trackMetadata!.title, 'Stop and Stare');
      expect(data.file!.type, LyricsTypes.qrc);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
    });

    test('parseLyricsLine 的字幕时间戳从 0 重新计（上游不去 [start,dur] 前缀）', () {
      final line = QrcParser.parseLyricsLine('[0,4390]Stop(0,274) (274,274)Stare(548,274)');
      expect(line!.syllables.length, 3);
      expect(line.syllables[0].text, 'Stop');
      expect(line.syllables[0].startTime, 0);
      expect(line.syllables[0].endTime, 274);
      expect(line.syllables[2].text, 'Stare');
      expect(line.syllables[2].startTime, 548);
    });

    test('offset 不为 0 时应用到逐字音节', () {
      final data = QrcParser.parse('[offset:100]\n[0,1000]a(0,500) b(500,500)');
      final line = data.lines!.single as SyllableLineInfo;
      expect(line.syllables[0].startTime, -100);
      expect(line.syllables[0].endTime, 400);
      expect(line.syllables[1].startTime, 400);
      expect(line.syllables[1].endTime, 900);
      // SyllableLineInfo.text 由音节拼接
      expect(line.text, 'a b');
    });
  });

  group('KrcParser', () {
    test('KrcDemo 与上游逐行一致（98 行 / 翻译 / hash / 属性）', () {
      final data = KrcParser.parse(_fixture('KrcDemo.txt'));
      _expectSameAsGolden(_describe(data), 'KrcDemo');

      final info = data.file!.additionalInfo as KrcAdditionalInfo;
      expect(info.hash, '34ce9b1c75e8afa9bb0bb6571f5eb913');
      expect(
        info.attributes!.map((a) => a.key).toList(),
        ['id', 'ar', 'ti', 'by', 'al', 'sign', 'qq', 'total', 'offset', 'language'],
      );
      expect(data.trackMetadata!.artist, 'OneRepublic');
      expect(data.file!.type, LyricsTypes.krc);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);

      final lines = data.lines!.cast<SyllableLineInfo>();
      expect(lines.length, 98);
      expect(lines.first.text, 'OneRepublic - Counting Stars');
      expect(lines.first.startTime, 419);
      expect(lines.first.syllables.length, 4);
      expect(lines.last.startTime, 252601);
      // 翻译行来自 [language:] 里的 base64 JSON（type == 1 的 lyricContent 第一列）
      final full = data.lines!.cast<FullSyllableLineInfo>();
      expect(full[2].chineseTranslation, isNotNull);
      expect(full[2].chineseTranslation, '最近我总是辗转反侧 难以入眠');
      expect(
        full.where((l) => l.translations['zh'] != null).length,
        98,
      );
    });

    test('checkKrcTranslation / getTranslationFromKrc / getTranslationRawFromKrc', () {
      final krc = _fixture('KrcDemo.txt');
      expect(KrcTranslationParser.checkKrcTranslation(krc), isTrue);
      final trans = KrcTranslationParser.getTranslationFromKrc(krc);
      expect(trans, isNotNull);
      expect(trans!.length, 98);
      expect(trans[0], '  ');
      expect(trans[2], '最近我总是辗转反侧 难以入眠');

      final raw = KrcTranslationParser.getTranslationRawFromKrc(krc);
      expect(raw, isNotNull);
      expect(raw!.version, 1);
      final item = raw.content!.firstWhere((c) => c.type == 1);
      expect(item.language, 0);
      expect(item.lyricContent!.length, 98);

      expect(KrcTranslationParser.checkKrcTranslation('[ti:x]'), isFalse);
      expect(KrcTranslationParser.getTranslationFromKrc('[ti:x]'), isNull);
      expect(KrcTranslationParser.getTranslationRawFromKrc('[ti:x]'), isNull);
    });

    test('getSplitedKrc 只保留 [ 开头的行；getSplitedKrcWithoutInfoLine 还要是数字打头', () {
      final krc = _fixture('KrcDemo.txt');
      final lines = KrcParser.getSplitedKrc(krc);
      final infoLines = KrcParser.getSplitedKrcWithoutInfoLine(krc);
      // 上游 KrcParser.cs:104-123 (GetSplitedKrc) 与 :130-148
      // (GetSplitedKrcWithoutInfoLine) 都是「StringBuilder.AppendLine 拼一遍，再
      // `.Split('\n')`」，AppendLine 会在最后一行后面补一个换行，所以两边各自都会
      // 多出一个尾部空串：109 → 110，98 → 99。
      expect(lines.length, 110);
      expect(infoLines.length, 99);
      // 差的 11 条正是 WithoutInfoLine 多出来的过滤条件
      // （KrcParser.cs:139 `line[1].ToString().IsNumber()`）：
      // [id] [ar] [ti] [by] [hash] [al] [sign] [qq] [total] [offset] [language]
      expect(lines.length - infoLines.length, 11);
      // 第一行是 [id:...]，被 WithoutInfoLine 过滤掉（[i 不是数字）
      expect(lines.first, startsWith('[id:'));
      expect(infoLines.first, startsWith('['));
      expect(RegExp(r'^[0-9]$').hasMatch(infoLines.first[1]), isTrue);
    });

    test('parseLyricsLine 的逐字时间基于行首时间', () {
      final line = KrcParser.parseLyricsLine('[1000,2000]<0,500,0>He<500,700,0>llo');
      expect(line!.syllables.length, 2);
      expect(line.syllables[0].text, 'He');
      expect(line.syllables[0].startTime, 1000);
      expect(line.syllables[0].endTime, 1500);
      expect(line.syllables[1].text, 'llo');
      expect(line.syllables[1].startTime, 1500);
      expect(line.syllables[1].endTime, 2200);
    });
  });

  group('YrcParser', () {
    test('YrcDemo 与上游逐行一致（信息行 + 98 逐字行 + writers）', () {
      final data = YrcParser.parse(_fixture('YrcDemo.txt'));
      _expectSameAsGolden(_describe(data), 'YrcDemo');

      expect(data.file!.type, LyricsTypes.yrc);
      // 有信息行 → 混合同步
      expect(data.file!.syncTypes, SyncTypes.mixedSynced);
      expect(data.writers, [
        'Brent Kutzle',
        'Tyler Spry',
        'Steven Mudd',
        'Ryan Tedder',
        'Josh Varnadore',
      ]);

      final lines = data.lines!;
      expect(lines.length, 102);
      expect(lines.whereType<SyllableLineInfo>().length, 98);
      expect(lines.whereType<FullSyllableLineInfo>().length, 0);
      // 首尾各 2 条是 JSON 信息行（作词/作曲）
      expect(lines[0].text, '作词: Brent Kutzle/Tyler Spry/Steven Mudd/Ryan Tedder/Josh Varnadore');
      expect(lines[0].startTime, 0);
      expect(lines[1].text, startsWith('作曲: '));
      expect(lines[1].startTime, 1000);
      expect(lines.last.text, startsWith('作曲: '));
      expect(lines.last.startTime, 254690);
      expect(lines[2].text, "Lately, I've been, I've been losing sleep");
      expect(lines[2].startTime, 420);
      expect((lines[2] as SyllableLineInfo).syllables.length, 9);
    });

    test('parseLyrics 只解析行首信息行，不解析末尾信息行（比 parse 少 2 行）', () {
      final all = YrcParser.parseLyrics(_fixture('YrcDemo.txt'));
      // 上游 YrcParser.cs:145 注释写得很清楚：
      //   「按照原始逻辑，不解析末尾的信息行，只用于定位」
      // ParseLyrics 的倒序扫描碰到 '}' 只用来定位 json 行的起点（:143-149），
      // 并不像 Parse（:62-83）那样 new LineInfo(...) 填进 endCredits。
      // 所以 = 行首 2 条信息行 + 98 条逐字行 = 100，而不是 parse 的 102。
      expect(all.length, 100);
      expect(all.first.text, startsWith('作词: '));
      expect(all.first.startTime, 0);
      // 末行是最后一条逐字歌词（YrcDemo.txt 第 99 行），不是「作曲: ...」信息行
      expect(all.last.text, "The lessons I've learned");
      expect(all.last.startTime, 252690);
    });

    test('parseOnlyLyrics 不解析信息行', () {
      final lyrics = YrcParser.parseOnlyLyrics(
        '[420,4440](420,1320,0)Lately(1740,0,0), (1740,570,0)I\'ve ',
      );
      expect(lyrics.length, 1);
      expect((lyrics.single as SyllableLineInfo).syllables.length, 3);
      expect((lyrics.single as SyllableLineInfo).syllables[0].text, 'Lately');
    });
  });

  group('LyricifyLinesParser', () {
    test('LyricifyLinesDemo 与上游逐行一致（53 行 / begin-end 时间戳）', () {
      final data = LyricifyLinesParser.parse(_fixture('LyricifyLinesDemo.txt'));
      _expectSameAsGolden(_describe(data), 'LyricifyLinesDemo');

      expect(data.file!.type, LyricsTypes.lyricifyLines);
      expect(data.file!.syncTypes, SyncTypes.lineSynced);
      expect(data.trackMetadata!.title, 'Cruel Summer');
      expect(data.trackMetadata!.artist, 'Taylor Swift');
      expect(data.trackMetadata!.album, 'Lover');

      final lines = data.lines!.cast<TextLineInfo>();
      expect(lines.length, 53);
      expect(lines.first.text, 'Fever dream high in the quiet of the night');
      expect(lines.first.startTime, 5841);
      expect(lines.first.endTime, 8298);
      expect(lines.last.startTime, 173101);
      expect(lines.last.endTime, 175023);
    });

    test('[type:LyricifyLines] 标记行被移除且不产生歌词行', () {
      final data = LyricifyLinesParser.parse(
        '[type:LyricifyLines]\n[0,100]a\n[100,200]b',
      );
      expect(data.lines!.length, 2);
      expect(data.lines!.first.text, 'a');
    });

    test('offset 同时作用于 begin 与 end', () {
      final lines = LyricifyLinesParser.parseLyrics(
        ['[offset:100]', '[1000,2000]x'],
        100,
      );
      expect(lines.single.startTime, 900);
      expect(lines.single.endTime, 1900);
    });
  });

  group('TtmlParser', () {
    // 上游 ParseHelper.cs:33-45 的 switch 里**没有** AppleJson 分支：
    // `LyricsRawTypes.Ttml => Parsers.TtmlParser.Parse(lyrics)` 直接吃裸 TTML 字符串。
    // Apple 的 JSON 信封是 provider 侧拆的（AppleMusic/Response.cs:82-116 NormalizeTtml
    // 从 relationships.syllable-lyrics 里取 Ttml / TtmlLocalizations）。
    // 这里按同样的职责边界只做「取出 ttml 字符串」这一步，
    // **比的是 TtmlParser 本身**，不含 Apple 信封解析。
    String appleTtml() => (jsonDecode(_fixture('AppleSyllableDemo.txt'))
            as Map<String, dynamic>)['data'][0]['attributes']['ttml'] as String;

    test('AppleSyllableDemo 与上游逐行一致（69 行 / 单 agent 对齐 / 背景人声子行）',
        () {
      final data = TtmlParser.parse(appleTtml());
      _expectSameAsGolden(_describe(data), 'AppleSyllableDemo');

      expect(data.file!.type, LyricsTypes.ttml);
      // 上游 TtmlParser.cs:158/227 全部是逐字行 → SyllableSynced
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      // TtmlParser.cs:277-282 iTunesMetadata/@leadingSilence 进 Attributes
      final info = data.file!.additionalInfo as GeneralAdditionalInfo;
      expect(info.attributes!.map((a) => '${a.key}=${a.value}').toList(),
          ['leadingSilence=0.300']);
      // TtmlParser.cs:284-290 songwriters → Writers
      expect(data.writers, ['Ryan Tedder']);
      // TtmlParser.cs:311-317 body/@dur = 4:17.286 → 257286ms
      expect(data.trackMetadata!.durationMs, 257286);

      final lines = data.lines!;
      expect(lines.length, 69);
      expect(lines.whereType<SyllableLineInfo>().length, 69);
      expect(lines.whereType<TextLineInfo>().length, 0);
      // TtmlParser.cs:48-55：只有一个 agent → 不是 duet → 一律 Left
      expect(lines.every((l) => l.lyricsAlignment == LyricsAlignment.left), isTrue);

      final first = lines.first as SyllableLineInfo;
      expect(first.text, "Lately I've been, I've been losing sleep");
      expect(first.startTime, 358);
      expect(first.endTime, 4933);
      expect(first.syllables.length, 7);

      final last = lines.last as SyllableLineInfo;
      expect(last.text, "Sink in the river, the lessons I've learned");
      expect(last.startTime, 251830);
      expect(last.endTime, 253793);
      expect(last.syllables.length, 8);

      // TtmlParser.cs:182-189 role="x-bg" 的 span 走 bgSyllables → SubLine
      final withSub = lines.where((l) => l.subLine != null).toList();
      expect(withSub.length, 4);
      for (final l in withSub) {
        final sub = l.subLine! as SyllableLineInfo;
        // TtmlParser.cs:186-187 子行沿用主行对齐
        expect(sub.lyricsAlignment, LyricsAlignment.left);
        expect(sub.syllables, isNotEmpty);
        // 子行不在主行文本里（TtmlParser.cs:152-159 main/bg 分开收集）
        expect(l.text.contains(sub.text), isFalse);
      }
      // 本样本没有 itunes:translation 节点 → 没有任何行被升级成 Full*LineInfo
      expect(lines.whereType<FullLineInfoMixin>().length, 0);
    });

    test('空串/非法 XML 直接返回空壳（TtmlParser.cs:108-119）', () {
      final empty = TtmlParser.parse('   ');
      expect(empty.lines, isEmpty);
      expect(empty.file!.type, LyricsTypes.ttml);

      // TtmlParser.cs:111-119 XDocument.Parse 抛异常 → catch 后原样返回
      final broken = TtmlParser.parse('<tt><p begin="0.1s">x');
      expect(broken.lines, isEmpty);
    });

    // AppleSyllableDemo 里没有 itunes:translation 节点，所以 translations /
    // FullSyllableLineInfo 这条路径 golden 覆盖不到，这里按上游源码逐条手推。
    test('subtitle 翻译：主行拆括号 → translations，背景段给 subLine', () {
      const ttml = '''
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xml:lang="en">
<head><metadata><ttm:agent type="person" xml:id="v1"/></metadata></head>
<body dur="0:10.000"><div begin="0.000" end="10.000">
<p begin="1.000" end="2.000" itunes:key="L1"><span begin="1.000" end="1.500">Hel</span><span begin="1.500" end="2.000">lo </span></p>
<p begin="3.000" end="4.000" itunes:key="L2"><span begin="3.000" end="3.400">Wor</span><span ttm:role="x-bg" begin="3.400" end="4.000">ld</span></p>
</div></body>
<itunes:translation type="subtitle" xml:lang="en"><itunes:text for="L1">Hallo (world)</itunes:text><itunes:text for="L2">Foo (Bar)</itunes:text></itunes:translation>
</tt>''';

      final data = TtmlParser.parse(ttml);
      // TtmlParser.cs:192-220：只有 itunes:key 命中 translations 的行才会被升级
      final lines = data.lines!;
      expect(lines.length, 2);

      // L1 没有 x-bg 子行 → SplitSubtitleByParentheses(:835-852) 取出的括号段
      // 没有去处（:755-768 bgDict 为 null），主行只剩括号外的内容
      final l1 = lines[0];
      expect(l1, isA<FullSyllableLineInfo>()); // :774 line as FullSyllableLineInfo ?? new ...
      expect(l1.text, 'Hello ');
      expect(l1.lyricsAlignment, LyricsAlignment.left);
      // translations / pronunciation 只在 IFullLineInfo 上有（上游 TtmlParser.cs:774
      // 那里就是 `line as FullSyllableLineInfo ?? new ...`），LineInfo 上没有。
      final full1 = l1 as FullLineInfoMixin;
      expect(full1.translations, {'en': 'Hallo'});
      expect(l1.subLine, isNull);
      expect(full1.pronunciation, isNull);

      // L2 有 x-bg 子行 → 括号段进 subLine 的 translations，主行只留主文本
      final l2 = lines[1];
      expect(l2, isA<FullSyllableLineInfo>());
      expect(l2.text, 'Wor');
      expect(l2.startTime, 3000);
      expect(l2.endTime, 3400);
      expect((l2 as FullLineInfoMixin).translations, {'en': 'Foo'});
      // :796-823 子行同样被升级成 FullSyllableLineInfo 并拿到括号内的译文
      final sub = l2.subLine!;
      expect(sub, isA<FullSyllableLineInfo>());
      expect(sub.text, 'ld');
      expect(sub.lyricsAlignment, LyricsAlignment.left);
      expect((sub as FullLineInfoMixin).translations, {'en': 'Bar'});
    });
  });

  group('SpotifyParser', () {
    test('SpotifyDemo 与上游逐行一致（25 行 / LineSynced / 无 syllables 时按 endTime 分叉）',
        () {
      final data = SpotifyParser.parse(_fixture('SpotifyDemo.txt'))!;
      _expectSameAsGolden(_describe(data), 'SpotifyDemo');

      expect(data.file!.type, LyricsTypes.spotify);
      expect(data.file!.syncTypes, SyncTypes.lineSynced);
      // 上游 SpotifyParser.cs:15-19 只建 File/Lines，**不建** TrackMetadata
      expect(data.trackMetadata, isNull);

      final lines = data.lines!;
      expect(lines.length, 25);
      expect(lines.every((l) => l is TextLineInfo), isTrue);
      expect(lines.first.text, "Today I'm not myself");
      expect(lines.first.startTime, 50500);
      // SpotifyParser.cs:74-81：EndTime == 0 → new LineInfo(words, startTime)，endTime 留 null
      expect(lines.first.endTime, isNull);
      // 末行是空词 + 只有 startTimeMs
      expect(lines.last.text, '');
      expect(lines.last.startTime, 262840);
      expect(lines.last.endTime, isNull);
    });

    test('SpotifySyllableDemo 与上游逐行一致（129 行 / SyllableSynced / 按 numChars 切词）',
        () {
      final data = SpotifyParser.parse(_fixture('SpotifySyllableDemo.txt'))!;
      _expectSameAsGolden(_describe(data), 'SpotifySyllableDemo');

      expect(data.file!.type, LyricsTypes.spotify);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      expect(data.trackMetadata, isNull);

      final lines = data.lines!.cast<SyllableLineInfo>();
      expect(lines.length, 129);
      final first = lines.first;
      expect(first.text, "The club isn't the best place");
      expect(first.startTime, 9595);
      expect(first.endTime, 11101);
      // SpotifyParser.cs:67-69：words 按 syllable.numChars 顺序切片
      expect(first.syllables.map((s) => s.text).toList(),
          ['The ', 'club ', "isn't ", 'the ', 'best ', 'place']);
      expect(first.syllables.map((s) => s.startTime).toList(),
          [9595, 9784, 10104, 10434, 10652, 10875]);
      // 末行 syllables 有一个空词（numChars=0）
      expect(lines.last.syllables.length, 1);
      expect(lines.last.syllables.single.text, '');
    });

    test('SpotifyUnsyncedDemo 与上游逐行一致（27 行 / Unsynced / 无时间戳）', () {
      final data = SpotifyParser.parse(_fixture('SpotifyUnsyncedDemo.txt'))!;
      _expectSameAsGolden(_describe(data), 'SpotifyUnsyncedDemo');

      expect(data.file!.type, LyricsTypes.spotify);
      expect(data.file!.syncTypes, SyncTypes.unsynced);

      final lines = data.lines!;
      expect(lines.length, 27);
      expect(lines.every((l) => l is TextLineInfo), isTrue);
      // SpotifyParser.cs:46-54 UNSYNCED 分支只 new LineInfo(words)，不碰时间
      expect(lines.every((l) => l.startTime == null && l.endTime == null), isTrue);
      expect(lines.first.text, "Six on the second hand to New Year's resolutions");
      expect(lines.last.text, 'Straight in a straight line, running back to you');
    });

    test('顶层没有 lyrics 字段时返回 null（SpotifyParser.cs:12/31）', () {
      expect(SpotifyParser.parse('{"colors":{}}'), isNull);
    });
  });

  group('MusixmatchParser', () {
    test('MusixmatchDemo 与上游逐行一致（28 行 / SyllableSynced / ts+o 定位逐字）', () {
      final data = MusixmatchParser.parse(_fixture('MusixmatchDemo.txt'))!;
      _expectSameAsGolden(_describe(data), 'MusixmatchDemo');

      expect(data.file!.type, LyricsTypes.musixmatch);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      // MusixmatchParser.cs:64-69 richsync 分支会 new TrackMetadata()（字段全空）
      expect(data.trackMetadata, isNotNull);
      expect(data.trackMetadata!.durationMs, isNull);

      final lines = data.lines!.cast<SyllableLineInfo>();
      expect(lines.length, 28);
      final first = lines.first;
      expect(first.text, 'When, when we came home');
      expect(first.startTime, 7780);
      expect(first.endTime, 12304);
      // MusixmatchParser.cs:51-56：start = ts*1000，音节起止 = 本词 o 与**下一个词** o
      expect(first.syllables.length, 9);
      expect(first.syllables.map((s) => s.text).toList(),
          ['When,', ' ', 'when', ' ', 'we', ' ', 'came', ' ', 'home']);
      expect(first.syllables.last.startTime, 11634);
      // 末个音节的 endTime 取的是行尾 te*1000（MusixmatchParser.cs:54）
      expect(first.syllables.last.endTime, first.endTime);

      final last = lines.last;
      expect(last.text, "If this love is pain, then honey let's love tonight");
      expect(last.startTime, 185770);
      expect(last.endTime, 190858);
      expect(last.syllables.length, 19);
      expect(data.lines!.whereType<FullLineInfoMixin>().length, 0);
    });

    test('没有 macro_calls / 三条分支都不命中时返回 null（MusixmatchParser.cs:19/136）', () {
      expect(MusixmatchParser.parse('{}'), isNull);
      expect(
        MusixmatchParser.parse('{"message":{"body":{"macro_calls":{}}}}'),
        isNull,
      );
    });
  });

  group('Decrypter (QRC)', () {
    test('QrcEncrypted 解出 QrcDemo 原文（TripleDES + zlib + BOM）', () {
      final encrypted = _fixture('QrcEncrypted.txt').trim();
      final expected = _fixture('QrcPlainExpected.txt');
      final decrypted = qrc_decrypter.Decrypter.decryptLyrics(encrypted);
      expect(decrypted, expected);
      // 解出来的就是能直接喂给 QrcParser 的纯文本
      expect(QrcParser.parse(decrypted!).lines!.length, 39);
    });

    test('hexStringToByteArray 大小写不敏感（int.parse radix 16）', () {
      expect(
        qrc_decrypter.Decrypter.hexStringToByteArray('0A1b'),
        [0x0A, 0x1B],
      );
    });

    test('XmlUtils 修复非法 & 与引号，并解析出 DOM', () {
      // 裸 & 会被替换成 &amp;
      final doc = XmlUtils.create('<root><a x="1">Tom & Jerry</a></root>');
      expect(doc.rootElement.name.local, 'root');
      expect(doc.findAllElements('a').single.innerText, 'Tom & Jerry');

      // 属性值里嵌引号（ReplaceQuot 的用途）
      final fixed = XmlUtils.replaceQuot('<a b="he said "hi" ok"/>');
      expect(fixed.contains('&quot;'), isTrue);

      // RemoveIllegalContent：`<a="b" />` 这种等号在标签名和引号之间的非法属性会被移除
      expect(XmlUtils.removeIllegalContent('<root><a="b" /></root>'), '<root></root>');
      // 合法属性保持不动
      expect(
        XmlUtils.removeIllegalContent('<root><a b="c" /></root>'),
        '<root><a b="c" /></root>',
      );
    });

    test('XmlUtils.recursionFindElement 递归收集节点', () {
      final doc = XmlUtils.create(
        '<QrcInfos><LyricInfo><Lyric_1 LyricContent="x"/></LyricInfo></QrcInfos>',
      );
      final res = <String, XmlNode>{};
      XmlUtils.recursionFindElement(
        doc.rootElement,
        {'LyricInfo': 'lyricInfo', 'Lyric_1': 'lyric1'},
        res,
      );
      expect(res.keys.toSet(), {'lyricInfo', 'lyric1'});
      expect((res['lyric1'] as XmlElement).getAttribute('LyricContent'), 'x');
    });
  });

  group('Decrypter (KRC)', () {
    test('KrcToken 解出 KrcDemo 原文（base64 + XOR + zlib + 去首字符）', () {
      final token = _fixture('KrcToken.txt').trim();
      final expected = _fixture('KrcPlainExpected.txt');
      final decrypted = krc_decrypter.Decrypter.decryptLyrics(token);
      expect(decrypted, expected);
      expect(KrcParser.parse(decrypted!).lines!.length, 98);
    });
  });

  group('Decrypter models', () {
    test('KugouLyricsResponse / KugouTranslation 按 JSON 字段名取值', () {
      final response = KugouLyricsResponse.fromJson(
        jsonDecode('{"content":"abc","info":"i","_source":"s","status":1,'
            '"contenttype":2,"error_code":0,"fmt":"krc"}') as Map<String, dynamic>,
      );
      expect(response.content, 'abc');
      expect(response.info, 'i');
      expect(response.source, 's');
      expect(response.status, 1);
      expect(response.contentType, 2);
      expect(response.errorCode, 0);
      expect(response.format, 'krc');

      final translation = KugouTranslation.fromJson(
        jsonDecode(
          '{"content":[{"language":0,"type":1,"lyricContent":[["a","b"],null]}],"version":1}',
        ) as Map<String, dynamic>,
      );
      expect(translation.version, 1);
      expect(translation.content!.single.type, 1);
      expect(translation.content!.single.lyricContent![0], ['a', 'b']);
      expect(translation.content!.single.lyricContent![1], isNull);
    });
  });
}
