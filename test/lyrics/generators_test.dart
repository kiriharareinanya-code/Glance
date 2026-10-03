// W-B 测试：TTML / Spotify / Musixmatch 解析 + 全部歌词生成器。
//
// 样本来自上游 Lyricify.Lyrics.Demo/RawLyrics（已拷到 test/fixtures/lyricify/）。
// 生成器的断言分两类：
//   1) 对上游格式的逐字断言（时间戳、逐字括号、行尾、空行插入）；
//   2) 「解析 → 生成 → 再解析 → 再生成」往返一致性（第一次生成的字符串是基线，
//      第二次生成必须逐字节相同，保证生成器是可重入/无损的）。
//
// 生成器的换行：上游 `StringBuilder.AppendLine()` 写 `Environment.NewLine`
// （Windows 上 `\r\n`），所以断言里统一用 `\r\n`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/generators/krc_generator.dart';
import 'package:vectra/lyrics/generators/lrc_generator.dart';
import 'package:vectra/lyrics/generators/lyricify_lines_generator.dart';
import 'package:vectra/lyrics/generators/lyricify_syllable_generator.dart';
import 'package:vectra/lyrics/generators/qrc_generator.dart';
import 'package:vectra/lyrics/generators/yrc_generator.dart';
import 'package:vectra/lyrics/helpers/generator_helper.dart';
import 'package:vectra/lyrics/json_utils.dart';
import 'package:vectra/lyrics/models/additional_file_info.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/syllable_info.dart';
import 'package:vectra/lyrics/parsers/lyricify_lines_parser.dart';
import 'package:vectra/lyrics/parsers/lyricify_syllable_parser.dart';
import 'package:vectra/lyrics/parsers/musixmatch_parser.dart';
import 'package:vectra/lyrics/parsers/spotify_parser.dart';
import 'package:vectra/lyrics/parsers/ttml_parser.dart';

/// 读取 `test/fixtures/lyricify/<name>`。
String fixture(String name) {
  final file = File('test/fixtures/lyricify/$name');
  expect(file.existsSync(), isTrue, reason: '缺少样本 ${file.path}');
  return file.readAsStringSync();
}

/// Apple Music 接口响应里的 TTML 正文（`data[0].attributes.ttml`）。
String appleTtml(String rawJson) {
  final json = jsonDecode(rawJson);
  final ttml = asStr(jget(json, 'data[0].attributes.ttml'));
  expect(ttml, isNotEmpty, reason: 'Apple 样本里应能取到 data[0].attributes.ttml');
  return ttml;
}

List<SyllableInfo> syllablesOf(LineInfo line) {
  expect(line, isA<SyllableLineInfo>(),
      reason: '这一行应当是逐字行，实际 ${line.runtimeType}');
  return (line as SyllableLineInfo).syllables;
}

void main() {
  // =========================================================================
  // TTML（Apple Music）
  // =========================================================================
  group('TtmlParser', () {
    late LyricsData data;

    setUpAll(() {
      data = TtmlParser.parse(appleTtml(fixture('AppleSyllableDemo.txt')));
    });

    test('行数 / 同步类型 / 文件类型', () {
      expect(data.file!.type, LyricsTypes.ttml);
      // 样本里 69 个 <p>，每个都有逐字 <span>，所以整体是逐字同步。
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      expect(data.lines!.length, 69);
    });

    test('首行：逐字文本、音节数、起止时间', () {
      final first = data.lines!.first;
      expect(first.text, "Lately I've been, I've been losing sleep");
      expect(first.startTime, 358);
      expect(first.endTime, 4933);
      final syllables = syllablesOf(first);
      expect(syllables.length, 7);
      expect(syllables.first.text, 'Lately ');
      expect(syllables.first.startTime, 358);
      expect(syllables.first.endTime, 1694);
      expect(syllables.last.text, 'sleep');
      expect(syllables.last.startTime, 3747);
      expect(syllables.last.endTime, 4933);
    });

    test('末行：时间戳来自最后一个音节', () {
      final last = data.lines!.last;
      expect(last.startTime, 251830);
      expect(last.endTime, 253793);
    });

    test('背景和声进入 subLine，并保留括号内文本', () {
      // 样本里 L18 / L22 / L37 / L54 这四行带 <span ttm:role="x-bg">(Hey!)</span>
      final backgrounds = data.lines!.where((l) => l.subLine != null).toList();
      expect(backgrounds.length, 4);
      for (final line in backgrounds) {
        expect(line.subLine!.text, '(Hey!)');
        expect(line.subLine!.startTime, isNotNull);
        expect(line.subLine!.endTime, isNotNull);
      }
      final first18 = data.lines![17];
      expect(first18.subLine!.startTime, 81430);
      expect(first18.subLine!.endTime, 81635);
      expect(syllablesOf(first18).length, 7);
    });

    test('单演唱者（非对唱）时对齐是 left', () {
      expect(data.lines!.every((l) => l.lyricsAlignment == LyricsAlignment.left),
          isTrue);
    });

    test('元数据：词曲作者 / leadingSilence / 时长 / 语言', () {
      expect(data.writers, ['Ryan Tedder']);
      final info = data.file!.additionalInfo as GeneralAdditionalInfo;
      expect(info.attributes!.map((e) => e.key), contains('leadingSilence'));
      expect(
          info.attributes!.firstWhere((e) => e.key == 'leadingSilence').value,
          '0.300');
      // <body dur="4:17.286">
      expect(data.trackMetadata!.durationMs, 257286);
      expect(data.trackMetadata!.language, ['en']);
    });

    test('总音节数 = 523 个带 begin 的 span + 4 个背景 span 的字节拆分', () {
      var syllables = 0;
      var background = 0;
      for (final line in data.lines!) {
        syllables += syllablesOf(line).length;
        final sub = line.subLine;
        if (sub != null) background += syllablesOf(sub).length;
      }
      // 523 个 timed span 里有 4 个是 x-bg 容器内的，所以正文 519 + 背景 4。
      expect(syllables, 519);
      expect(background, 4);
    });

    test('空输入与非法 XML 都返回带 File 信息的空数据', () {
      final empty = TtmlParser.parse('');
      expect(empty.lines, isEmpty);
      expect(empty.file!.type, LyricsTypes.ttml);
      expect(empty.file!.syncTypes, SyncTypes.syllableSynced);

      final broken = TtmlParser.parse('<tt><p>oops');
      expect(broken.lines, isEmpty);
    });
  });

  // =========================================================================
  // Spotify
  // =========================================================================
  group('SpotifyParser', () {
    test('LINE_SYNCED：逐行 + 追加信息', () {
      final data = SpotifyParser.parse(fixture('SpotifyDemo.txt'))!;
      expect(data.file!.type, LyricsTypes.spotify);
      expect(data.file!.syncTypes, SyncTypes.lineSynced);
      final lines = data.lines!;
      expect(lines.length, 25);
      expect(lines.first.text, "Today I'm not myself");
      expect(lines.first.startTime, 50500);
      // "endTimeMs":"0" → 只传 startTime
      expect(lines.first.endTime, isNull);
      expect(data.file!.additionalInfo, isA<SpotifyAdditionalInfo>());
      final info = data.file!.additionalInfo as SpotifyAdditionalInfo;
      expect(info.provider, 'MusixMatch');
      expect(info.providerLyricsId, '11912324');
      expect(info.providerDisplayName, 'Musixmatch');
      expect(info.lyricsLanguage, 'en');
    });

    test('SYLLABLE_SYNCED：按 numChars 切词', () {
      final data = SpotifyParser.parse(fixture('SpotifySyllableDemo.txt'))!;
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      expect(data.lines!.length, 129);
      final first = data.lines!.first;
      expect(first.text, "The club isn't the best place");
      // 逐字行的开始/结束时间由 SyllableLineInfo 从首尾音节推导
      expect(first.startTime, 9595);
      expect(first.endTime, 11101);
      final syllables = syllablesOf(first);
      expect(syllables.length, 6);
      expect(syllables.first.text, 'The ');
      expect(syllables.first.startTime, 9595);
      expect(syllables.first.endTime, 9776);
      expect(syllables[1].text, 'club ');
      expect(syllables[1].startTime, 9784);
      expect(syllables[1].endTime, 10056);
      expect(syllables.last.text, 'place');
      expect(syllables.last.startTime, 10875);
      expect(syllables.last.endTime, 11101);
    });

    test('UNSYNCED：只有文本，无时间', () {
      final data = SpotifyParser.parse(fixture('SpotifyUnsyncedDemo.txt'))!;
      expect(data.file!.syncTypes, SyncTypes.unsynced);
      final lines = data.lines!;
      expect(lines.length, 27);
      expect(lines.first.text,
          "Six on the second hand to New Year's resolutions");
      expect(lines.first.startTime, isNull);
      expect(lines.every((l) => l is TextLineInfo), isTrue);
    });

    test('非法 JSON 返回 null', () {
      expect(SpotifyParser.parse('not json'), isNull);
      expect(SpotifyParser.parse('{}'), isNull);
    });
  });

  // =========================================================================
  // Musixmatch
  // =========================================================================
  group('MusixmatchParser', () {
    test('richsync 分支：逐字 + 语言（含上游拼写笔误字段）', () {
      final data = MusixmatchParser.parse(fixture('MusixmatchDemo.txt'))!;
      expect(data.file!.type, LyricsTypes.musixmatch);
      expect(data.file!.syncTypes, SyncTypes.syllableSynced);
      expect(data.lines!.length, 28);

      final first = data.lines!.first;
      expect(first.startTime, 7780);
      expect(first.endTime, 12304);
      final syllables = syllablesOf(first);
      expect(syllables.length, 9);
      expect(syllables.first.text, 'When,');
      expect(syllables.first.startTime, 7780);
      expect(syllables.first.endTime, 9618);
      expect(syllables.last.text, 'home');
      expect(syllables.last.startTime, 11634);
      // 最后一个音节的结束时间取整行的 TimeEnd
      expect(syllables.last.endTime, 12304);

      // 上游字段名是 richssync_language（笔误），样本里正是这个名字
      expect(data.trackMetadata!.language, ['en']);
    });

    test('ignoreSyllable=true 时退到 track.subtitles.get（LRC 逐行）', () {
      final data =
          MusixmatchParser.parse(fixture('MusixmatchDemo.txt'), true)!;
      expect(data.file!.syncTypes, SyncTypes.lineSynced);
      final lines = data.lines!;
      expect(lines.length, 30);
      expect(lines.first.text, 'When, when we came home');
      expect(lines.first.startTime, 7780);
      // 上游 LrcParser.ParseLyrics 对 "[03:10.86] " 这种空文本行也会产出 LineInfo
      expect(lines.last.text, '');
      expect(lines.last.startTime, 190860);
      expect(lines.every((l) => l is TextLineInfo), isTrue);
      expect(data.trackMetadata!.language, ['en']);
    });

    test('没有 macro_calls / 非法 JSON 返回 null', () {
      expect(MusixmatchParser.parse('{}'), isNull);
      expect(MusixmatchParser.parse('not json'), isNull);
    });
  });

  // =========================================================================
  // Lyricify Syllable 生成器
  // =========================================================================
  group('LyricifySyllableGenerator', () {
    late LyricsData parsed;
    late String generated;

    setUpAll(() {
      parsed =
          LyricifySyllableParser.parse(fixture('LyricifySyllableDemo.txt'));
      generated = LyricifySyllableGenerator.generate(parsed);
    });

    test('逐字断言：属性头、逐字括号、行尾 CRLF', () {
      final lines = generated.split('\r\n');
      expect(lines.first,
          '[4]Hate (14872,393)to (15265,190)give (15455,262)the (15717,113)satisfaction (15830,833)asking (16663,422)how (17085,250)you\'re (17335,173)doing (17508,363)now(17871,553)');
      expect(lines[1],
          "[4]How's (18424,327)the (18751,185)castle (18936,470)built (19406,238)off (19644,205)people (19849,466)you (20315,209)pretend (20524,506)to (21030,124)care (21154,239)about(21393,439)");
      // 样本 54 行歌词（其中一行的文本自带上游合并进来的换行，视觉上是 2 行）
      // + 结尾 split 产生的空串
      expect(lines.length, 56);
      expect(generated, endsWith('\r\n'));
      expect(generated.contains('\n\n'), isFalse);
    });

    test('往返一致：再解析 → 再生成逐字节相同', () {
      final again =
          LyricifySyllableGenerator.generate(LyricifySyllableParser.parse(generated));
      expect(again, generated);
    });

    test('对齐标记：默认 3，left 4 / right 5，子行 6/7/8', () {
      final data = LyricsData();
      final main = SyllableLineInfo([TextSyllableInfo('a', 0, 100)])
        ..lyricsAlignment = LyricsAlignment.right;
      final sub = SyllableLineInfo([TextSyllableInfo('b', 100, 200)])
        ..lyricsAlignment = LyricsAlignment.left;
      main.subLine = sub;
      data.lines = [main];
      expect(LyricifySyllableGenerator.generate(data), '[5]a(0,100)\r\n[7]b(100,100)\r\n');

      final plain = LyricsData();
      plain.lines = [SyllableLineInfo([TextSyllableInfo('c', 0, 5)])];
      expect(LyricifySyllableGenerator.generate(plain), '[3]c(0,5)\r\n');
    });

    test('空数据返回空串', () {
      final empty = LyricsData();
      expect(LyricifySyllableGenerator.generate(empty), '');
      empty.lines = <LineInfo>[];
      expect(LyricifySyllableGenerator.generate(empty), '');
    });

    test('非逐字行被跳过（上游只处理 SyllableLineInfo）', () {
      final data = LyricsData();
      data.lines = [TextLineInfo('plain', 1, 2)];
      expect(LyricifySyllableGenerator.generate(data), '');
    });
  });

  // =========================================================================
  // Lyricify Lines 生成器
  // =========================================================================
  group('LyricifyLinesGenerator', () {
    late LyricsData parsed;

    setUpAll(() {
      parsed = LyricifyLinesParser.parse(fixture('LyricifyLinesDemo.txt'));
    });

    test('逐字断言：[start,end]text + CRLF', () {
      final generated = LyricifyLinesGenerator.generate(parsed);
      final lines = generated.split('\r\n');
      expect(lines.first,
          '[5841,8298]Fever dream high in the quiet of the night');
      expect(lines[1],
          "[8298,11511]You know that I caught it (Oh yeah, you're right, I want it)");
      expect(generated, endsWith('\r\n'));
      expect(generated.endsWith('\r\n\r\n'), isFalse);
    });

    test('往返一致', () {
      final generated = LyricifyLinesGenerator.generate(parsed);
      final again =
          LyricifyLinesGenerator.generate(LyricifyLinesParser.parse(generated));
      expect(again, generated);
    });

    test('子行：InMainLine 用括号并取并集时间，InDiffLine 各行一条', () {
      final data = LyricsData();
      final main = TextLineInfo('main', 1000, 2000);
      final sub = TextLineInfo('bg', 1500, 2500);
      main.subLine = sub;
      data.lines = [main];

      expect(LyricifyLinesGenerator.generate(data, SubLinesOutputType.inMainLine),
          '[1000,2500]main (bg)\r\n');
      expect(LyricifyLinesGenerator.generate(data, SubLinesOutputType.inDiffLine),
          '[1000,2000]main\r\n[1500,2500]bg\r\n');
    });
  });

  // =========================================================================
  // LRC 生成器
  // =========================================================================
  group('LrcGenerator', () {
    test('逐字断言：时间戳格式 [mm:ss.xxx]、无毫秒时补 0、CRLF', () {
      final data = LyricsData();
      data.lines = [
        TextLineInfo('hello', 65000, 68000),
        TextLineInfo('world', 70000),
      ];
      final out = LrcGenerator.generate(data, EndTimeOutputType.none);
      expect(out, '[01:05.000]hello\r\n[01:10.000]world\r\n');
    });

    test('时间戳按上游 FormatTimeMsToTimestampString：分位不补零到 2 位以上', () {
      final data = LyricsData();
      data.lines = [
        TextLineInfo('a', 0),
        TextLineInfo('b', 999),
        TextLineInfo('c', 59780),
        TextLineInfo('d', 3600000),
      ];
      final out = LrcGenerator.generate(data, EndTimeOutputType.none);
      expect(out.split('\r\n').sublist(0, 4),
          ['[00:00.000]a', '[00:00.999]b', '[00:59.780]c', '[60:00.000]d']);
    });

    test('EndTimeOutputType.huge：行尾空行只在行末时间为 0 或间距 > 5s 时输出', () {
      final data = LyricsData();
      data.lines = [
        TextLineInfo('a', 0, 1000),
        TextLineInfo('b', 2000, 3000),
        TextLineInfo('c', 20000, 21000),
        TextLineInfo('d', 22000, 23000),
      ];
      expect(LrcGenerator.generate(data, EndTimeOutputType.huge),
          '[00:00.000]a\r\n[00:02.000]b\r\n[00:03.000]\r\n[00:20.000]c\r\n[00:22.000]d\r\n[00:23.000]\r\n');
      // 说明：a(1000) → b(2000) 间距 1000 → 不补；
      //       b(3000) → c(20000) 间距 17000 > 5000 → 补空行（输出在 b 之后）；
      //       c(21000) → d(22000) 间距 1000 → 不补；
      //       d 是最后一行（index + 1 >= Count）→ 补空行。
    });

    test('EndTimeOutputType.all：所有非零行末时间都补空行', () {
      final data = LyricsData();
      data.lines = [
        TextLineInfo('a', 0, 1000),
        TextLineInfo('b', 2000),
      ];
      expect(LrcGenerator.generate(data, EndTimeOutputType.all),
          '[00:00.000]a\r\n[00:01.000]\r\n[00:02.000]b\r\n');
    });

    test('子行：InMainLine 用 fullText（括号），InDiffLine 各占一行', () {
      final data = LyricsData();
      final main = TextLineInfo('main', 1000, 2000);
      main.subLine = TextLineInfo('bg', 1500, 2500);
      data.lines = [main];

      expect(
          LrcGenerator.generate(
              data, EndTimeOutputType.none, SubLinesOutputType.inMainLine),
          '[00:01.000]main (bg)\r\n');
      expect(
          LrcGenerator.generate(
              data, EndTimeOutputType.none, SubLinesOutputType.inDiffLine),
          '[00:01.000]main\r\n[00:01.500]bg\r\n');
    });

    test('子行在主行之前时括号写在前面（fullText 的上游行为）', () {
      final data = LyricsData();
      final main = TextLineInfo('main', 2000, 3000);
      main.subLine = TextLineInfo('bg', 1000, 2500);
      data.lines = [main];
      expect(
          LrcGenerator.generate(
              data, EndTimeOutputType.none, SubLinesOutputType.inMainLine),
          '[00:01.000](bg) main\r\n');
    });

    test('空数据 / 空列表返回空串', () {
      expect(LrcGenerator.generate(LyricsData()), '');
      final data = LyricsData();
      data.lines = <LineInfo>[];
      expect(LrcGenerator.generate(data), '');
    });

    test('真实样本：逐字歌词生成 LRC 时首行时间戳正确', () {
      final parsed =
          LyricifySyllableParser.parse(fixture('LyricifySyllableDemo.txt'));
      final out = LrcGenerator.generate(parsed, EndTimeOutputType.none);
      expect(out.split('\r\n').first,
          "[00:14.872]Hate to give the satisfaction asking how you're doing now");
      expect(out.split('\r\n').length, 55);
    });
  });

  // =========================================================================
  // QRC / KRC / YRC 生成器
  // =========================================================================
  group('QrcGenerator', () {
    test('逐字断言：text(start,duration)', () {
      final data = LyricsData();
      data.lines = [
        SyllableLineInfo([
          TextSyllableInfo('你', 1000, 1200),
          TextSyllableInfo('好', 1200, 1500),
        ]),
      ];
      expect(QrcGenerator.generate(data), '[1000,500]你(1000,200)好(1200,300)\r\n');
    });

    test('往返一致（逐字歌词 → QRC → 逐字解析 → QRC）', () {
      final parsed =
          LyricifySyllableParser.parse(fixture('LyricifySyllableDemo.txt'));
      final qrc = QrcGenerator.generate(parsed);
      final again = QrcGenerator.generate(roundTripSyllables(qrc));
      final a = qrc.split('\r\n');
      final b = again.split('\r\n');
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i], a[i], reason: '第 $i 行往返不一致');
      }
    });
  });

  group('KrcGenerator', () {
    test('逐字断言：行 [start,duration] + <offset,duration,0>text', () {
      final data = LyricsData();
      data.lines = [
        SyllableLineInfo([
          TextSyllableInfo('你', 1000, 1200),
          TextSyllableInfo('好', 1200, 1500),
        ]),
      ];
      expect(KrcGenerator.generate(data), '[1000,500]<0,200,0>你<200,300,0>好\r\n');
    });

    test('子行也输出为独立一行', () {
      final data = LyricsData();
      final main = SyllableLineInfo([TextSyllableInfo('a', 0, 100)]);
      main.subLine = SyllableLineInfo([TextSyllableInfo('b', 100, 300)]);
      data.lines = [main];
      expect(KrcGenerator.generate(data), '[0,100]<0,100,0>a\r\n[100,200]<0,200,0>b\r\n');
    });
  });

  group('YrcGenerator', () {
    test('逐字断言：(start,duration,0)text', () {
      final data = LyricsData();
      data.lines = [
        SyllableLineInfo([
          TextSyllableInfo('你', 1000, 1200),
          TextSyllableInfo('好', 1200, 1500),
        ]),
      ];
      expect(YrcGenerator.generate(data), '[1000,500](1000,200,0)你(1200,300,0)好\r\n');
    });

    test('逐行同步歌词生成 YRC 是空串（上游只处理 SyllableLineInfo）', () {
      final data = LyricsData();
      data.lines = [TextLineInfo('a', 0, 100)];
      expect(YrcGenerator.generate(data), '');
    });
  });

  // =========================================================================
  // GenerateHelper
  // =========================================================================
  group('GenerateHelper', () {
    test('按类型分发', () {
      final parsed =
          LyricifySyllableParser.parse(fixture('LyricifySyllableDemo.txt'));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.lyricifySyllable),
          LyricifySyllableGenerator.generate(parsed));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.lyricifyLines),
          LyricifyLinesGenerator.generate(parsed));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.lrc),
          LrcGenerator.generate(parsed));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.qrc),
          QrcGenerator.generate(parsed));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.krc),
          KrcGenerator.generate(parsed));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.yrc),
          YrcGenerator.generate(parsed));
    });

    test('未支持的类型返回 null，空结果也返回 null', () {
      final parsed =
          LyricifySyllableParser.parse(fixture('LyricifySyllableDemo.txt'));
      expect(GenerateHelper.generateString(parsed, LyricsTypes.ttml), isNull);
      expect(GenerateHelper.generateString(parsed, LyricsTypes.spotify), isNull);
      expect(GenerateHelper.generateString(parsed, LyricsTypes.musixmatch), isNull);
      // 全逐行的数据生成 QRC/KRC/YRC 都是空串 → null
      final lineOnly = LyricsData();
      lineOnly.lines = [TextLineInfo('a', 0, 1)];
      expect(GenerateHelper.generateString(lineOnly, LyricsTypes.qrc), isNull);
      expect(GenerateHelper.generateString(lineOnly, LyricsTypes.krc), isNull);
    });
  });
}

/// 把 QRC 文本按上游 QrcParser 的语义（`text(start,duration)` + 行头 `[start,duration]`）
/// 还原成 SyllableLineInfo 列表，用于生成器往返一致性测试。
LyricsData roundTripSyllables(String qrc) {
  final data = LyricsData();
  final lines = <LineInfo>[];
  for (final raw in qrc.split('\r\n')) {
    if (raw.isEmpty) continue;
    final header = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(raw);
    if (header == null) continue;
    final body = raw.substring(header.end);
    final syllables = <SyllableInfo>[];
    // 音节文本本身可能含 '('（样本里就有 "(How"），所以用非贪婪匹配停在
    // 第一个后面紧跟 "<数字>,<数字>)" 的那个 '('。
    for (final m
        in RegExp(r'([^()]*?)\((\d+),(\d+)\)').allMatches(body)) {
      final text = m.group(1)!;
      final start = int.parse(m.group(2)!);
      final duration = int.parse(m.group(3)!);
      syllables.add(TextSyllableInfo(text, start, start + duration));
    }
    lines.add(SyllableLineInfo(syllables));
  }
  data.lines = lines;
  return data;
}
