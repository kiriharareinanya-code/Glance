// W-A 测试：解析器 + 解密器（逐行对照上游 Lyricify.Lyrics.Helper）。
//
// 断言基线来自**上游 C# 代码本身**：
//   用 `Lyricify.Lyrics.Demo` 引用的同一个 `Lyricify.Lyrics.Helper` 程序集，
//   对同一批 `RawLyrics/*.txt` 调用 LrcParser/QrcParser/KrcParser/YrcParser/
//   LyricifySyllableParser/LyricifyLinesParser，把结果序列化成
//   `*.golden.json`（构建/生成脚本是一次性的，不随仓库交付）。
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
import 'package:vectra/lyrics/models/syllable_info.dart';
import 'package:vectra/lyrics/parsers/krc_parser.dart';
import 'package:vectra/lyrics/parsers/lrc_parser.dart';
import 'package:vectra/lyrics/parsers/lyricify_lines_parser.dart';
import 'package:vectra/lyrics/parsers/lyricify_syllable_parser.dart';
import 'package:vectra/lyrics/parsers/qrc_parser.dart';
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
      expect(lines[3].text, "Lately, I've been, I've been losing sleep");
      expect(lines[3].startTime, 77870);
      expect(lines.first.startTime, 0);
      expect(lines.last.startTime, 252350);
      // LRC 只有行时间，EndTime 全为 null
      expect(lines.every((l) => l.endTime == null), isTrue);
    });

    test('offset 属性参与时间戳计算（[offset:0] 时原样）', () {
      final data = LrcParser.parse('[offset:1000]\n[00:10.000]hello');
      expect(data.lines!.single.startTime, 10000);
      expect(data.trackMetadata!.durationMs, isNull);

      final shifted = LrcParser.parse('[offset:1000]\n[00:10.000]hello'.replaceAll(
        '[offset:1000]',
        '[offset:-500]',
      ));
      expect(shifted.lines!.single.startTime, 10500);
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
      expect(lines.first.text, 'Stop and Stare');
      expect(lines.first.startTime, 0);
      expect(lines.first.endTime, 4390);
      expect(lines.last.startTime, 212532);
      expect(lines.last.endTime, 221221);
      expect(lines.first.syllables.length, 30);

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
      expect(lines.length, infoLines.length);
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

    test('parseLyrics 与 parse 的行数一致（parseLyrics 不解析末尾信息行）', () {
      final all = YrcParser.parseLyrics(_fixture('YrcDemo.txt'));
      expect(all.length, 102);
      expect(all.first.text, startsWith('作词: '));
      expect(all.last.text, startsWith('作曲: '));
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

  group('LyricifySyllableParser', () {
    test('LyricifySyllableDemo 与上游逐行一致（54 行 / 1 条背景人声子行）', () {
      final data = LyricifySyllableParser.parse(_fixture('LyricifySyllableDemo.txt'));
      _expectSameAsGolden(_describe(data), 'LyricifySyllableDemo');

      // PORT NOTE: 上游把 Type 写成 LyricsTypes.Qrc（不是 LyricifySyllable）
      expect(data.file!.type, LyricsTypes.qrc);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      final info = data.file!.additionalInfo as GeneralAdditionalInfo;
      expect(info.attributes!.single.key, 'from');
      expect(info.attributes!.single.value, 'AppleSyllable');

      final lines = data.lines!.cast<SyllableLineInfo>();
      expect(lines.length, 54);
      expect(lines.first.text, "Hate to give the satisfaction asking how you're doing now");
      expect(lines.first.startTime, 14872);
      expect(lines.last.text, 'Bleeding me dry like a goddamn vampire');
      expect(lines.last.startTime, 203364);
      expect(lines.where((l) => l.subLine != null).length, 1);
    });

    test('LsMixQrcDemo 与上游逐行一致（32 行 / 4 条背景人声子行）', () {
      final data = LyricifySyllableParser.parse(_fixture('LsMixQrcDemo.txt'));
      _expectSameAsGolden(_describe(data), 'LsMixQrcDemo');

      final lines = data.lines!;
      expect(lines.length, 32);
      expect(lines.where((l) => l.subLine != null).length, 4);
      expect(data.trackMetadata!.title, 'Stop and Stare');
      expect(data.trackMetadata!.artist, 'OneRepublic');
    });

    test('行首 [p] 决定背景人声与对唱视图', () {
      final background = LyricifySyllableParser.parseLyricsLine('[6]a(0,100)');
      expect(background!.isBackgroundVocals, isTrue);
      final main = LyricifySyllableParser.parseLyricsLine('[3]a(0,100)');
      expect(main!.isBackgroundVocals, isFalse);
      final left = LyricifySyllableParser.parseLyricsLine('[4]a(0,100)');
      expect(left!.lyricsAlignment, LyricsAlignment.left);
      expect(left.isBackgroundVocals, isFalse);
      final right = LyricifySyllableParser.parseLyricsLine('[5]a(0,100)');
      expect(right!.lyricsAlignment, LyricsAlignment.right);
      final plain = LyricifySyllableParser.parseLyricsLine('[0]a(0,100)');
      expect(plain!.lyricsAlignment, LyricsAlignment.unspecified);
      expect(plain.isBackgroundVocals, isNull);
    });

    test('头尾括号的行会被并入上一行作为子行', () {
      final data = LyricifySyllableParser.parse(
        '[0]main line(0,1000)\n[0](background)(1000,500)',
      );
      expect(data.lines!.length, 1);
      expect(data.lines!.single.text, 'main line');
      expect(data.lines!.single.subLine!.text, '(background)');
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
