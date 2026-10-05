///
///
library;

import 'helpers/optimization/info_lines.dart';
import 'helpers/optimization/sync_downgrade.dart';
import 'helpers/parse_helper.dart';
import 'helpers/types/type_helper.dart';
import 'lyrics_log.dart';
import 'models/line_info.dart';
import 'models/lyrics_data.dart';
import 'models/lyrics_types.dart';
import 'models/track_metadata.dart';
import 'searchers/helpers/compare_helper.dart';
import 'searchers/isearcher.dart';
import 'searchers/searchers.dart';
import 'engine_sources.dart';

class LyricsFetchOutcome {
  LyricsFetchOutcome({
    required this.data,
    required this.source,
    required this.sourceName,
    required this.matchType,
    required this.searchResult,
  });

  final LyricsData data;

  final Searchers source;

  final String sourceName;

  final MatchType matchType;

  final ISearchResult searchResult;

  SyncTypes get syncTypes => data.file?.syncTypes ?? SyncTypes.unknown;

  List<LineInfo> get lines => data.lines ?? const <LineInfo>[];
}

///
class LyricsEngine {
  LyricsEngine({
    this.bridges,
    this.defaultMinimumMatch = MatchType.medium,
  });

  final List<LyricsSourceBridge>? bridges;

  final MatchType defaultMinimumMatch;

  List<LyricsSourceBridge> get _bridges => bridges ?? defaultSourceBridges;

  ///
  ///   auto / netease / qq / kugou / lrclib / musixmatch / apple / spotify / soda
  List<LyricsSourceBridge> _orderedBridges(String preference) {
    final all = _bridges;
    final pref = preference.toLowerCase();
    Searchers? first;
    switch (pref) {
      case 'netease':
        first = Searchers.netease;
        break;
      case 'qq':
      case 'qqmusic':
        first = Searchers.qqMusic;
        break;
      case 'kugou':
        first = Searchers.kugou;
        break;
      case 'lrclib':
        first = Searchers.lrclib;
        break;
      case 'musixmatch':
        first = Searchers.musixmatch;
        break;
      case 'apple':
      case 'applemusic':
        first = Searchers.appleMusic;
        break;
      case 'spotify':
        first = Searchers.spotify;
        break;
      case 'soda':
      case 'sodamusic':
        first = Searchers.sodaMusic;
        break;
      default:
        first = null;
    }
    if (first == null) return all;
    final head = all.where((b) => b.searcherType == first).toList();
    final tail = all.where((b) => b.searcherType != first).toList();
    return [...head, ...tail];
  }

  ///
  Future<LyricsFetchOutcome?> fetch({
    required String title,
    String? artist,
    String? album,
    int? durationMs,
    String sourcePreference = 'auto',
    String preferLang = '',
    bool stripInfoLines = true,
    MatchType? minimumMatch,
  }) async {
    final track = TrackMultiArtistMetadata()
      ..title = title
      ..artist = artist
      ..album = album
      ..durationMs = durationMs;

    final minMatch = minimumMatch ?? defaultMinimumMatch;
    lyricsLog('搜索:「$title」/「${artist ?? ''}」/${durationMs ?? 0}ms '
        '（门槛 ${minMatch.name}）');

    for (final bridge in _orderedBridges(sourcePreference)) {
      final ISearcher searcher = bridge.searcher;

      List<ISearchResult> results;
      try {
        results = await searcher.searchForResultsByTrack(track);
      } catch (e) {
        final st = StackTrace.current;
        lyricsLog('${bridge.displayName} 搜索失败：$e', warn: true);
        lyricsLog('堆栈：$st', warn: true);
        continue;
      }
      if (results.isEmpty) {
        lyricsLog('${bridge.displayName} 无候选');
        continue;
      }

      final candidates =
          results.where((r) => (r.matchType?.value ?? -1) >= minMatch.value);
      if (candidates.isEmpty) {
        lyricsLog('${bridge.displayName} ${results.length} 个候选都没过门槛'
            '（最高 ${results.first.matchType?.name ?? '无'}）');
        continue;
      }

      LyricsFetchOutcome? fallback;
      for (final result in candidates) {
        LyricsData? data;
        try {
          data = await bridge.fetch(result, track);
        } catch (e) {
          lyricsLog('${bridge.displayName} 取词失败「${result.title}」：$e',
              warn: true);
          continue;
        }
        if (data == null) continue;
        // 判据和 bridge 层一致：**行数不为 0 不等于有词**。
        // 历史上出现过一份 38 行里 36 行文本为空的 YRC（模型层引用共享 bug
        // 留下的坏数据），只查 `isEmpty` 会让它当成命中返回，屏幕上只剩
        // 开头两行制作名单。空行占比过半就当这份数据不可用，换下一个候选。
        final fetched = data.lines ?? const <LineInfo>[];
        if (fetched.isEmpty || !hasRealLyrics(fetched)) continue;

        data = _optimize(data, stripInfoLines: stripInfoLines);

        final outcome = LyricsFetchOutcome(
          data: data,
          source: bridge.searcherType,
          sourceName: bridge.displayName,
          matchType: result.matchType ?? MatchType.noMatch,
          searchResult: result,
        );

        // 伴奏/纯音乐的"歌词"只有一行「纯音乐，请欣赏」，语言判定会把它
        // 当中文歌词放行。行数是最可靠的信号：真歌词至少有几十行。
        // 留 3 行给极短的口播/诗体歌词，低于这个数一律当没有歌词。
        final lineCount = data.lines?.length ?? 0;
        if (lineCount < 3) {
          lyricsLog('${bridge.displayName}「${result.title}」只有 $lineCount 行'
              '（伴奏/纯音乐），换下一个候选');
          continue;
        }

        if (preferLang == 'zh' || preferLang == 'en') {
          final got = _lyricLangOf(data);
          if (got != 'unknown' && got != preferLang) {
            lyricsLog('${bridge.displayName}「${result.title}」歌词语言是 $got，'
                '与偏好 $preferLang 不符，换下一个候选');
            fallback ??= outcome;
            continue;
          }
        }

        lyricsLog('命中：${bridge.displayName}「${result.title}」/'
            '「${result.artist}」'
            '${result.durationMs != null ? " 时长差 ${((result.durationMs! - (durationMs ?? result.durationMs!)) / 1000).toStringAsFixed(1)}s" : ""} '
            '匹配 ${result.matchType?.name} 共 ${data.lines?.length ?? 0} 行');
        return outcome;
      }

      if (fallback != null) {
        lyricsLog('${bridge.displayName} 语言偏好全不符，返回兜底候选');
        return fallback;
      }
      lyricsLog('${bridge.displayName} 候选都没取到可用歌词');
    }

    lyricsLog('没找到（各源都没匹配上）');
    return null;
  }

  LyricsData? parseAny(String raw) => ParseHelper.parseLyrics(raw);

  LyricsData? parseAs(String raw, LyricsRawTypes type) =>
      ParseHelper.parseLyrics(raw, type);

  ///
  LyricsData _optimize(LyricsData data, {required bool stripInfoLines}) {
    final initial = data.lines;
    if (initial == null || initial.isEmpty) return data;
    List<LineInfo> lines = initial;

    if (stripInfoLines) {
      try {
        final flags = InfoLines.checkInfoLines(data);
        final kept = <LineInfo>[];
        for (var i = 0; i < lines.length; i++) {
          if (i < flags.length && flags[i]) continue;
          kept.add(lines[i]);
        }
        if (kept.length >= 4) {
          data.lines = kept;
          lines = kept;
        }
      } catch (e) {
        lyricsLog('优化（信息行）失败：$e', warn: true);
      }
    }

    // **统一降级出口**（逐字功能下线后新增）。
    //
    // KRC/YRC/QRC/TTML 这几种逐字格式的 parser 会产出 `SyllableLineInfo`
    // ——因为它们的行文本和行时间是从音节累积出来的，解析阶段离不开它。
    // 但渲染层只认纯文本行（逐字擦除动画已下线），所以在这里一次性把
    // 音节行降级掉。放在 `_optimize` 末尾而不是逐个改 parser，是因为：
    // 改 parser 就得把"音节累积 → 拼文本"这套逻辑在 5 个文件里各抄一遍，
    // 而降级是 Lyricify 自带的、上游就有保证的行为（`SyncDowngrade.cs`）。
    //
    // 降级是**幂等**的：已经是 `TextLineInfo` 的行原样返回，所以
    // LRC 这类本来就没有音节的源不受影响。
    try {
      SyncDowngrade.downgradeToLineSyncedList(lines);
      // 降级后整份数据的同步类型不该再声称自己是逐字——否则日志和
      // `LyricsView.encode()` 写出去的 `sync` 字段会继续撒谎。
      if (data.file != null) data.file!.syncTypes = SyncTypes.lineSynced;
    } catch (e) {
      lyricsLog('优化（降级为文本行）失败：$e', warn: true);
    }

    return data;
  }

  ///
  static String _lyricLangOf(LyricsData data) {
    var zh = 0;
    var latin = 0;
    final lines = data.lines ?? const <LineInfo>[];
    for (final line in lines.take(40)) {
      for (final ch in line.text.split('')) {
        final c = ch.codeUnitAt(0);
        if (c >= 0x4E00 && c <= 0x9FFF) {
          zh++;
        } else if (c < 128) {
          latin++;
        }
      }
    }
    if (zh == 0 && latin == 0) return 'unknown';
    return zh * 4 >= latin ? 'zh' : 'en';
  }
}

String lyricsTypeDisplayName(LyricsTypes type) => switch (type) {
      LyricsTypes.lyricifyLines => 'Lyricify Lines',
      LyricsTypes.lrc => 'LRC',
      LyricsTypes.qrc => 'QRC',
      LyricsTypes.krc => 'KRC',
      LyricsTypes.yrc => 'YRC',
      LyricsTypes.ttml => 'TTML',
      LyricsTypes.spotify => 'Spotify',
      LyricsTypes.musixmatch => 'Musixmatch',
      LyricsTypes.unknown => 'Unknown',
    };

String lyricsRawTypeDisplayName(LyricsRawTypes type) =>
    TypeHelper.getDisplayName(type);
