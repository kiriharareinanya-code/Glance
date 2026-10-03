// Lyricify 歌词引擎的真实接口端到端校验脚本（Vectra 侧工具，非上游文件）。
//
// 用法（在项目根目录）：
//   dart run tool/lyricify_live_check.dart "歌名" "歌手" [时长秒] [来源]
//
// 例：
//   dart run tool/lyricify_live_check.dart "黄金数" "いよわ" 188 netease
//   dart run tool/lyricify_live_check.dart "Counting Stars" "OneRepublic" 258 auto
//
// 它会：走一遍 LyricsEngine（多源搜索 → 匹配打分 → 取词 → 解析 → 优化），
// 打印命中来源、匹配档位、同步类型（逐字/逐行）、行数、翻译/罗马音覆盖，
// 以及逐字歌词的音节抽样——用来确认真实网络下这套移植是通的。
//
// 走的是 `DirectLyricsHttpClient`（package:http 直连），不经宿主日志/超时，
// 因此【只用于开发机验证】，不影响应用内的实现（应用内由 lyrics_bridge.dart
// 注入走 WidgetContext 的客户端）。
//
// 许可：本文件是 Vectra 自己的工具，不是上游代码，但用到 lib/lyrics 里的
// Apache-2.0 移植产物（见 lib/lyrics/NOTICE）。
library;

import 'dart:io';

import 'package:vectra/lyrics/engine.dart';
import 'package:vectra/lyrics/lyrics_log.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/lyricify_live_check.dart "歌名" "歌手" '
        '[时长秒] [来源]');
    exitCode = 2;
    return;
  }

  final title = args[0];
  final artist = args[1];
  final durationSec = args.length > 2 ? int.tryParse(args[2]) ?? 0 : 0;
  final source = args.length > 3 ? args[3] : 'auto';

  // 把库内日志接到控制台（应用里这一步由 lyrics_bridge.dart 接到 Log）。
  lyricsLogFn = (message, {bool warn = false}) {
    stdout.writeln('${warn ? '[WARN]' : '[INFO]'} $message');
  };

  stdout.writeln('=== Lyricify 引擎实网校验 ===');
  stdout.writeln('曲目: $title / $artist / ${durationSec}s  来源偏好: $source');
  stdout.writeln('');

  final sw = Stopwatch()..start();
  final outcome = await LyricsEngine().fetch(
    title: title,
    artist: artist,
    durationMs: durationSec > 0 ? durationSec * 1000 : null,
    sourcePreference: source,
    stripInfoLines: true,
    minimumMatch: MatchType.low,
  );
  sw.stop();

  if (outcome == null) {
    stdout.writeln('结果: 没找到（各源都没匹配上）  ${sw.elapsedMilliseconds}ms');
    exitCode = 1;
    return;
  }

  final lines = outcome.lines;
  final withTrans = lines.where((l) => _transOf(l).isNotEmpty).length;
  final withRoma = lines.where((l) => _romaOf(l).isNotEmpty).length;
  final syllableLines = lines.whereType<SyllableLineInfo>().length;
  final syllables =
      lines.whereType<SyllableLineInfo>().fold<int>(0, (n, l) => n + l.syllables.length);

  stdout.writeln('');
  stdout.writeln('结果: 命中  ${sw.elapsedMilliseconds}ms');
  stdout.writeln('  来源      : ${outcome.sourceName} (${outcome.source.name})');
  stdout.writeln('  匹配档位  : ${outcome.matchType.name}'
      ' (${outcome.matchType.value})');
  stdout.writeln('  命中的曲目: ${outcome.searchResult.title} / '
      '${outcome.searchResult.artist}'
      '${outcome.searchResult.durationMs != null ? " / ${outcome.searchResult.durationMs! / 1000}s" : ""}');
  stdout.writeln('  格式/同步 : ${lyricsTypeDisplayName(outcome.data.file?.type ?? LyricsTypes.unknown)}'
      ' / ${outcome.syncTypes.name}');
  stdout.writeln('  行数      : ${lines.length}');
  stdout.writeln('  带翻译行  : $withTrans');
  stdout.writeln('  带罗马音行: $withRoma');
  stdout.writeln('  逐字行    : $syllableLines（共 $syllables 个音节）');
  stdout.writeln('');

  stdout.writeln('--- 前 8 行 ---');
  for (final line in lines.take(8)) {
    final t = _fmt(line.startTime);
    final trans = _transOf(line);
    final isSyl = line is SyllableLineInfo && line.syllables.isNotEmpty;
    stdout.writeln('[$t] ${line.text}${isSyl ? "   ⟨逐字 ${line.syllables.length}⟩" : ""}'
        '${trans.isNotEmpty ? "\n        译文: $trans" : ""}');
  }

  final firstSyllableLine = lines.whereType<SyllableLineInfo>().firstOrNull;
  if (firstSyllableLine != null) {
    stdout.writeln('');
    stdout.writeln('--- 逐字抽样（第 1 个逐字行的前 8 个音节）---');
    for (final s in firstSyllableLine.syllables.take(8)) {
      stdout.writeln('  ${_fmt(s.startTime)} → ${_fmt(s.endTime)}  '
          '(${s.endTime - s.startTime}ms)  「${s.text}」');
    }
  }

  stdout.writeln('');
  stdout.writeln('=== 校验通过 ===');
}

String _transOf(LineInfo line) {
  if (line is! FullLineInfoMixin) return '';
  return line.chineseTranslation ??
      line.translations.values.firstWhere((v) => v.isNotEmpty,
          orElse: () => '');
}

String _romaOf(LineInfo line) {
  if (line is! FullLineInfoMixin) return '';
  return line.pronunciation ?? '';
}

String _fmt(int? ms) {
  if (ms == null) return '--:--';
  final total = ms ~/ 1000;
  final m = total ~/ 60;
  final s = total % 60;
  final cs = (ms % 1000) ~/ 10;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      '.${cs.toString().padLeft(2, '0')}';
}
