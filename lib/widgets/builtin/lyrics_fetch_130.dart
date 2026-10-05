/// 130 版本的歌词选词逻辑（从 tag `0.2.0.130` 原样搬过来，独立成一个类）。
///
/// ## 为什么单独放一个文件，而不是整体回滚 lyrics.dart
///
/// `lyrics.dart` 在 130 之后经历过大量**与选词无关**的改动：卡片 UI、
/// 渲染管线、双驱动、砍逐字、封面缓存……整体回滚会把它们一起丢掉。
/// 这里只把「**取词**」这一段换回 130 的行为，其余一律不动——改错了也
/// 容易整个文件回退（删掉它、把 `_loadLyrics` 改回去即可）。
///
/// ## 与「8 源打分版」的差异（这就是要回滚掉的东西）
///
/// | | 130（本文件） | 8 源打分版 |
/// |---|---|---|
/// | 源 | **网易云 + LRCLIB** | 8 个源 |
/// | 选词 | `Lrc.pickSong` 在**本源候选里**挑最好 | 逐源、按分数从高到低**先到先得** |
/// | 针对歌名翻译 | **有专门兜底**（只搜歌手 / 模糊 search） | 无 |
///
/// 最后一行是关键。8 源版的失败模式在这里能看到：Netease 里一个
/// `medium(70)` 的**别的歌**只要排第一且有歌词，就会抢先返回，把 Apple
/// Music / LRCLIB 的 `perfect(100)` 挡在后面。130 版没有"跨源先到先得"，
/// 它在每个源内部用 `pickSong` 挑出最像的那一条，**拿不到就换下一个源**。
///
/// ## 性能上的取舍（要知道）
///
/// 130 版只用两个源 → **能搜到的歌变少**（QQ/Kugou/Musixmatch/Apple/
/// Spotify/Soda 独有的曲目会搜不到）。这是用户明确要求换回来的行为：
/// 宁可少几首，不要"显示了别人的歌词"。
library;

import '../../core/logger.dart';
import '../../lyrics/engine_sources.dart' show KugouBridge, QQMusicBridge;
import '../../lyrics/models/track_metadata.dart';
import '../../lyrics/searchers/kugou_search_result.dart';
import '../../lyrics/searchers/qqmusic_search_result.dart';
import '../../lyrics/searchers/searchers.dart';
import '../../lyrics/searchers/searchers_helper.dart';
import '../context.dart';
import 'lrc.dart';

class LyricsFetcher130 {
  LyricsFetcher130(this.ctx, this.settings);

  /// 宿主上下文：提供 httpGetJSON。
  final WidgetContext ctx;

  /// 组件设置（用到 `credits` / `trans` / `source` 三项）。
  final Map<String, Object?> settings;

  /// 取词入口。返回 null 表示各源都没匹配上。
  Future<List<LrcLine>?> fetch(String title, String artist, int durMs) =>
      _searchLyrics(title, artist, durMs);

  // 网易云是非官方接口，带上正常的 UA/Referer 降低被限流的概率。
  Map<String, Object?> get _neHeaders => {
        'headers': {
          'Referer': 'https://music.163.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        }
      };

  // 歌词开头的「作词 : X」名单。设置里可以关掉。
  static final _creditRe = RegExp(
      r'^\s*(作词|作曲|编曲|制作人|monitor|录音|混音|母带|和声|吉他|贝斯|鼓|键盘|弦乐|统筹|企划|出品|发行|监制|制作|营销|策划|录音室|Producer|Composer|Lyricist|Arranger|Mixing|Mastering)\s*[:：]',
      caseSensitive: false);

  List<LrcLine> _stripCredits(List<LrcLine> arr) {
    if (settings['credits'] == true) return arr;
    final out = arr.where((l) => !_creditRe.hasMatch(l.s)).toList();
    // 万一整首歌被当成名单滤空了，宁可原样显示也别显示空白
    return out.length >= 4 ? out : arr;
  }

  Future<List<Map<String, Object?>>?> _searchNeteaseSongs(
      String query, int limit) async {
    final q = Uri.encodeComponent(query.trim());
    final url =
        'https://music.163.com/api/search/get?s=$q&type=1&limit=$limit';
    final r = await ctx.httpGetJSON(url, headers: _neHeaders);
    if (r['ok'] != true) return null;
    final data = r['data'];
    if (data is! Map) return null;
    final result = data['result'];
    if (result is! Map) return null;
    final songs = (result['songs'] as List?)?.cast<Object?>() ?? const [];
    return songs.isNotEmpty
        ? [for (final s in songs) (s as Map).cast<String, Object?>()]
        : null;
  }

  Future<List<LrcLine>?> _lyricsFromNeteaseSong(
      Map<String, Object?> song) async {
    final lu = 'https://music.163.com/api/song/lyric'
        '?id=${song['id']}&lv=1&kv=1&tv=-1';
    final r = await ctx.httpGetJSON(lu, headers: _neHeaders);
    if (r['ok'] != true) return null;
    final data = r['data'];
    if (data is! Map || data['lrc'] is! Map) return null;
    final lrcMap = data['lrc'] as Map;
    final main = _stripCredits(Lrc.parse('${lrcMap['lyric'] ?? ''}'));
    if (main.isEmpty) return null;
    if (settings['trans'] == true && data['tlyric'] is Map) {
      final tl = data['tlyric'] as Map;
      return Lrc.merge(main, Lrc.parse('${tl['lyric'] ?? ''}'));
    }
    return main;
  }


  Future<List<LrcLine>?> _lrclibGetAttempt(
      String vTitle, String artist, int durMs) async {
    var u = 'https://lrclib.net/api/get'
        '?track_name=${Uri.encodeComponent(vTitle)}'
        '&artist_name=${Uri.encodeComponent(artist)}';
    if (durMs > 0) u += '&duration=${(durMs / 1000).round()}';
    final r = await ctx.httpGetJSON(u);
    if (r['ok'] != true) return null;
    final data = r['data'];
    if (data is! Map) return null;
    final synced = data['syncedLyrics'];
    if (synced == null || '$synced'.isEmpty) return null;
    final arr = _stripCredits(Lrc.parse('$synced'));
    return arr.isNotEmpty ? arr : null;
  }

  Future<List<LrcLine>?> _lrclibSearchAttempt(
      String vTitle, String artist, int durMs) async {
    final u = 'https://lrclib.net/api/search'
        '?track_name=${Uri.encodeComponent(vTitle)}'
        '&artist_name=${Uri.encodeComponent(artist)}';
    final r = await ctx.httpGetJSON(u);
    if (r['ok'] != true) return null;
    final data = r['data'];
    if (data is! List || data.isEmpty) return null;
    final songs = <Map<String, Object?>>[];
    for (var i = 0; i < data.length && i < 20; i++) {
      final it = data[i];
      if (it is! Map || it['syncedLyrics'] == null) continue;
      songs.add({
        'id': i,
        'name': '${it['trackName'] ?? ''}',
        'artists': [
          {'name': '${it['artistName'] ?? ''}'}
        ],
        'duration': it['duration'] ?? 0,
        '_synced': it['syncedLyrics'],
      });
    }
    final song = Lrc.pickSong(songs, vTitle, artist, durMs);
    if (song == null) return null;
    final arr = _stripCredits(Lrc.parse('${song['_synced']}'));
    return arr.isNotEmpty ? arr : null;
  }

  /// 顺序尝试一串 attempt，单个失败/为空自动滑到下一个
  Future<List<LrcLine>?> _trySeq(
      List<Future<List<LrcLine>?> Function()> attempts, int i) async {
    if (i >= attempts.length) return null;
    List<LrcLine>? r;
    try {
      r = await attempts[i]();
    } catch (_) {
      r = null;
    }
    if (r != null && r.isNotEmpty) return r;
    return _trySeq(attempts, i + 1);
  }

  /// 完整搜索编排：**汇总所有源的候选，最后统一挑一首**。
  ///
  /// ## 为什么是"综合"而不是"逐源先到先得"
  ///
  /// 8 源打分版是 `for (源) { for (候选按分数) { 第一个有词的就返回 } }`——
  /// 某个源里一条 medium 分的别首歌只要排第一且有词，就压过了别的源的
  /// perfect 候选（实测「Golden Number」被 Netease 一条 medium(70) 的
  /// 「Ozymandias」抢走）。
  ///
  /// 这里把顺序反过来：**先把各源的候选装进同一个池子，再让 [Lrc.pickSong]
  /// 一次挑出最像的那首**。分数是跨源可比的（歌手 60 / 时长 70 / 歌名 40），
  /// 所以"网易云的 medium"和"QQ 的 perfect"能公平比较，而不是谁先返回谁赢。
  ///
  /// ## 源与查询
  ///
  /// | 源 | 查询 | 为什么要这一路 |
  /// |---|---|---|
  /// | 网易云 | 「歌名 歌手」 | 常规；中文曲库最全 |
  /// | 网易云 | 只搜歌手 | 治歌名被翻译/罗马字化（130 原有兜底） |
  /// | QQ | 「歌名 歌手」 | 网易云搜不到时的主要补位 |
  /// | QQ | 只搜歌手 | 同上 |
  /// | 酷狗 | 「歌名 歌手」 | **QQ 被限流时的主力**（见下） |
  /// | 酷狗 | 只搜歌手 | 同上 |
  ///
  /// 三个源**并行**发，最多 6 路。
  ///
  /// **QQ 的坑**：它的搜索接口（`u.y.qq.com/cgi-bin/musicu.fcg`）在裸请求
  /// 下很容易被限流，而限流的表现是**HTTP 200 + code=0 + songs 为空**，
  /// 响应体只有 ~900 字节（正常 42KB）——从状态码和错误码上完全看不出问题。
  /// cookie 只能让它"看起来像浏览器"，限流本身是按 IP+频率的，治不了根。
  /// 所以**酷狗必须留着**：它走明文接口，实测稳定返回 40KB+，是 QQ 被掐时
  /// 的实际补位。QQ 返回空列表时 `QQMusicSearcher` 会打一条专门的告警。
  ///
  /// ## 取词仍然分源
  ///
  /// 挑中哪首就用哪个源的取词接口（网易云走 `_lyricsFromNeteaseSong`，
  /// QQ 走 `QQMusicBridge`）——搜索结果能统一，歌词格式却不能，硬合并
  /// 只会把两套解析逻辑搅在一起。
  Future<List<LrcLine>?> _searchLyrics(String title, String artist, int durMs) {
    // 排查"这首歌搜不到/搜错了"时，这条和下面的命中日志是唯一线索。
    Log.i('lyrics', '[综合] 搜索:「$title」/「$artist」/${durMs}ms');
    final variants = Lrc.titleVariants(title).take(2).toList();
    if (variants.isEmpty) return Future.value(null);

    final queries = <String>{
      // 歌名变体 + 歌手（去重后最多两个变体）
      for (final v in variants)
        if (artist.isNotEmpty) '$v $artist'.trim() else v.trim(),
      // 只搜歌手：查歌名被翻译成另一门语言/罗马音对不上曲库的情况
      if (artist.isNotEmpty) artist.trim(),
    };

    return _gatherAndPick(queries, title, artist, durMs).then((lines) async {
      if (lines != null) {
        Log.i('lyrics', '[综合] 命中 ${lines.length} 行');
        return lines;
      }
      // 兜底：LRCLIB（130 原有的第二路，曲库偏英文/日文罗马字，
      // 网易云和 QQ 都没有时常常能救回来）。
      final bare = variants.length > 1 ? variants[1] : variants[0];
      final fb = await _trySeq(<Future<List<LrcLine>?> Function()>[
        for (final v in variants) () => _lrclibGetAttempt(v, artist, durMs),
        () => _lrclibSearchAttempt(bare, artist, durMs),
      ], 0);
      Log.i('lyrics',
          fb == null ? '[综合] 没找到（各源都没匹配上）' : '[综合·LRCLIB] 命中 ${fb.length} 行');
      return fb;
    });
  }

  /// 把各源的候选汇总成一张表，挑出最像的那首，再用对应源取词。
  Future<List<LrcLine>?> _gatherAndPick(
      Set<String> queries, String title, String artist, int durMs) async {
    // 并行发：3 个源 × 2 种查法，最多 6 路。串行的话最坏要等 6 个网络往返。
    final batches = await Future.wait([
      for (final q in queries) _neteaseCandidates(q),
      for (final q in queries) _qqCandidates(q),
      for (final q in queries) _kugouCandidates(q),
    ]);

    // 去重（同一个源里可能被两种查询各命中一次）。
    final pool = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final batch in batches) {
      for (final c in batch) {
        final key = '${c['_source']}:${c['_key']}';
        if (seen.add(key)) pool.add(c);
      }
    }
    if (pool.isEmpty) return null;

    final best = Lrc.pickSong(pool, title, artist, durMs);
    if (best == null) return null;
    Log.i('lyrics', '[综合] 选中 [${best['_source']}] '
        '「${best['name']}」/「${best['_artistText']}」');
    return _lyricsOf(best, title, artist, durMs);
  }

  /// 按候选所属源取词。
  Future<List<LrcLine>?> _lyricsOf(
      Map<String, Object?> best, String title, String artist, int durMs) async {
    final src = best['_source'] as String;
    // QQ / 酷狗的歌词走各自现成的 bridge（里面已经处理了 KRC 解密、
    // 逐行降级、译文合并、空歌词判定），这里只把 LyricsData 转回 LrcLine。
    if (src == 'qq' || src == 'kugou') {
      final track = BasicTrackMetadata()
        ..title = title
        ..artist = artist
        ..durationMs = durMs > 0 ? durMs : null;
      final bridge = src == 'qq' ? QQMusicBridge() : KugouBridge();
      final data = await bridge.fetch(best['_raw'] as dynamic, track);
      final lines = data?.lines;
      if (lines == null || lines.isEmpty) return null;
      return [
        for (final l in lines)
          LrcLine(t: l.startTime ?? 0, s: l.text, tr: l.subLine?.text ?? ''),
      ];
    }
    // 网易云
    return _lyricsFromNeteaseSong(best);
  }

  /// 网易云候选，转成 `pickSong` 能吃的统一格式。
  Future<List<Map<String, Object?>>> _neteaseCandidates(String query) async {
    if (query.trim().isEmpty) return const [];
    final songs = await _searchNeteaseSongs(query, 30);
    if (songs == null) return const [];
    return [
      for (final s in songs)
        {
          ...s,
          '_source': 'netease',
          '_key': '${s['id']}',
          '_raw': s,
          '_artistText': [
            for (final a in (s['artists'] as List?) ?? const [])
              '${(a as Map)['name'] ?? ''}',
          ].join('/'),
        },
    ];
  }

  /// QQ 音乐候选，转成同一格式（`id`/`artists`/`duration` 与网易云对齐）。
  Future<List<Map<String, Object?>>> _qqCandidates(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final searcher = SearchersHelper.getSearcher(Searchers.qqMusic);
      final track = BasicTrackMetadata()..title = query;
      final results = await searcher.searchForResultsByTrack(track);
      return [
        for (final r in results)
          if (r is QQMusicSearchResult)
            {
              'id': r.id,
              'name': r.title,
              'artists': [
                for (final a in r.artists) {'name': a},
              ],
              'duration': r.durationMs ?? 0,
              '_source': 'qq',
              '_key': r.mid,
              '_raw': r,
              '_artistText': r.artists.join('/'),
            },
      ];
    } catch (e) {
      Log.w('lyrics', '[综合] QQ 搜索失败：$e');
      return const [];
    }
  }

  /// 酷狗候选，转成同一格式。
  ///
  /// 酷狗的价值在于它**没有 QQ 那种限流**（搜索接口是明文的
  /// `mobilecdn.kugou.com/api/v3/search/song`，实测稳定返回 40KB+），
  /// 而且中文曲库比网易云还全。QQ 被掐住时，酷狗是主要补位。
  Future<List<Map<String, Object?>>> _kugouCandidates(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final searcher = SearchersHelper.getSearcher(Searchers.kugou);
      final track = BasicTrackMetadata()..title = query;
      final results = await searcher.searchForResultsByTrack(track);
      return [
        for (final r in results)
          if (r is KugouSearchResult)
            {
              'id': r.hash,
              'name': r.title,
              'artists': [
                for (final a in r.artists) {'name': a},
              ],
              'duration': r.durationMs ?? 0,
              '_source': 'kugou',
              '_key': r.hash,
              '_raw': r,
              '_artistText': r.artists.join('/'),
            },
      ];
    } catch (e) {
      Log.w('lyrics', '[综合] 酷狗搜索失败：$e');
      return const [];
    }
  }
}
