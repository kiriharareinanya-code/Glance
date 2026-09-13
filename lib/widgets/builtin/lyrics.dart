/// 内置组件：歌词。
///
/// 从 assets/plugins/lyrics/index.js 逐行移植。数据分两路：
///   「正在放什么」来自 Windows 系统媒体控件（SMTC）；
///   「歌词」来自网络（网易云 / LRCLIB），解析与挑选在 lrc.dart。
///
/// 位置自己外推：native 每 250ms 采样一次 SMTC，播放中按流逝时间往前推，
/// 把采样间隔抹平；切歌/暂停/拖动时快照会纠正回来。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../catalog.dart';
import 'lrc.dart';

class LyricsWidget extends BuiltinController {
  LyricsWidget(super.ctx);

  late Map<String, Object?> _settings;
  late double _w;
  late double _h;

  late String _accent = '#7CC7FF';

  // ---- 界面尺寸：按卡片高度缩放 ----
  static const _pad = 12;
  static const _textBlock = 70;
  static const _artGap = 8;
  late double _artSize;
  late double _lyricSize;
  /// 每行固定高度。滚动模型下所有行等高，没有"当前行更高"这回事。
  late int _lineContext;
  late int _lyricLines;
  /// 当前行是否有译文（译文叠在正文下方，不撑高行）。
  bool _hasTrans = false;
  /// 歌词槽位总数 = 可见行数 + 2（滚动时上下各多铺一行，防止边缘露白）。
  /// handler 按这个数注册。
  late int _slotCount;

  static const _ctrlSide = 26;
  static const _ctrlMain = 34;
  static const _ctrlBox = 42;

  /// 歌词区上方（按钮 + 进度条 + 时间行 + 间隔）占用的固定高度。
  /// mount() 与 _visibleLines() 必须用同一个值，否则行数预算和实际渲染打架。
  static const _headerBlock = 88;

  // ---- 运行时状态 ----
  Map<String, Object?>? _media; // 最近一次「有歌在放」的 SMTC 快照
  List<LrcLine> _lyrics = [];
  String _lyricState = 'idle'; // idle | loading | ok | none
  String _trackKey = '';
  String _viewKey = 'idle';
  int _idleMs = 0;
  static const int _idleGrace = 3000;
  String _lastPaint = '';
  int _lastPos = 0;
  int _windowBase = 0;
  bool _dead = false;

  final List<String> _hLine = [];

  // ------------------------------------------------------------------
  // 事件处理器
  // ------------------------------------------------------------------

  void _registerHandlers() {
    _hPrev = ctx.on((_) => ctx.mediaControl('prev'));
    _hToggle = ctx.on((_) => ctx.mediaControl('toggle'));
    _hNext = ctx.on((_) => ctx.mediaControl('next'));
    _hSeek = ctx.on((p) {
      final media = _media;
      if (media == null || (media['duration'] as num? ?? 0) <= 0) return;
      _lastPos = 0; // 定位是大跳，先解除单调保护
      final dur = (media['duration'] as num).toInt();
      ctx.mediaControl('seek',
          posMs: ((num.tryParse('${p['value']}') ?? 0) * dur).round());
    });
    // 点某一行歌词跳到那一句。槽位数是可见行数 + 2（滚动时上下各多铺
    // 一行），handler 按上限备齐。
    _hLine.clear();
    for (var i = 0; i < _slotCount; i++) {
      final slot = i;
      _hLine.add(ctx.on((_) {
        // 槽位 slot 显示的是 _windowBase + slot - 1 号行（往上多铺了一行）
        final idx = _windowBase + slot - 1;
        if (idx >= 0 && idx < _lyrics.length) {
          _lastPos = 0;
          ctx.mediaControl('seek', posMs: _lyrics[idx].t);
        }
      }));
    }
  }

  // ------------------------------------------------------------------
  // 取歌词
  // ------------------------------------------------------------------

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
    if (_settings['credits'] == true) return arr;
    final out =
        arr.where((l) => !_creditRe.hasMatch(l.s)).map((e) => e).toList();
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
    if (_settings['trans'] == true && data['tlyric'] is Map) {
      final tl = data['tlyric'] as Map;
      return Lrc.merge(main, Lrc.parse('${tl['lyric'] ?? ''}'));
    }
    return main;
  }

  Future<List<LrcLine>?> _neteaseAttempt(
      String vTitle, String artist, int durMs, bool artistOnly) async {
    final query = artistOnly ? artist : '$vTitle $artist'.trim();
    if (query.isEmpty) return null;
    final songs = await _searchNeteaseSongs(query, artistOnly ? 30 : 10);
    if (songs == null) return null;
    final song = Lrc.pickSong(songs, vTitle, artist, durMs);
    if (song == null) return null;
    return _lyricsFromNeteaseSong(song);
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

  /// 完整搜索编排。来源优先级：auto = 网易云 → LRCLIB；手动选源时只跑
  /// 所选来源优先，但来源内部的变体/兜底序列保持完整。
  Future<List<LrcLine>?> _searchLyrics(String title, String artist, int durMs) {
    final variants = Lrc.titleVariants(title).take(3).toList();
    if (variants.isEmpty) return Future.value(null);
    final bare = variants.length > 1 ? variants[1] : variants[0];

    Future<List<LrcLine>?> neteaseBlock() {
      final list = <Future<List<LrcLine>?> Function()>[
        for (final v in variants)
          () => _neteaseAttempt(v, artist, durMs, false),
        // 兜底 1：只搜歌手（30 条候选里靠歌手+时长挑），专治歌名被
        // 翻译成另一门语言/罗马音对不上曲库的情况
        () => _neteaseAttempt(title, artist, durMs, true),
      ];
      return _trySeq(list, 0);
    }

    Future<List<LrcLine>?> lrclibBlock() {
      final list = <Future<List<LrcLine>?> Function()>[
        for (final v in variants) () => _lrclibGetAttempt(v, artist, durMs),
        // 兜底 2：LRCLIB 的模糊 search 接口
        () => _lrclibSearchAttempt(bare, artist, durMs),
      ];
      return _trySeq(list, 0);
    }

    final src = '${_settings['source'] ?? 'auto'}';
    if (src == 'lrclib') {
      return lrclibBlock().then((r) => r ?? neteaseBlock());
    }
    if (src == 'netease') {
      return neteaseBlock().then((r) => r ?? lrclibBlock());
    }
    return neteaseBlock().then((r) => r ?? lrclibBlock());
  }

  Future<void> _loadLyrics(
      String title, String artist, int durMs, String key) async {
    // 只在没有旧歌词时设 loading（首次加载），避免状态变化触发重绘闪白
    if (_lyrics.isEmpty) _lyricState = 'loading';
    // 缓存键 = 标题|歌手|时长秒，含时长（区分现场版/录音室版）
    final cached = await ctx.cacheGet(key);
    if (_trackKey != key) return; // 加载期间已经换歌了
    if (cached is List && cached.isNotEmpty) {
      _lyrics = [for (final e in cached.cast<Map>()) LrcLine.fromJson(e.cast<String, Object?>())];
      _lyricState = 'ok';
      _paint(true);
      return;
    }
    List<LrcLine>? arr;
    try {
      arr = await _searchLyrics(title, artist, durMs);
    } catch (_) {
      arr = null;
    }
    if (_trackKey != key) return;
    if (arr != null && arr.isNotEmpty) {
      _lyrics = arr;
      _lyricState = 'ok';
      ctx.cacheSet(key, [for (final l in arr) l.toJson()]);
    } else {
      _lyrics = [];
      _lyricState = 'none';
    }
    _paint(true);
  }

  /// 一次性清掉旧版留在键值存储里的歌词缓存（lru 记账时代的遗留）
  Future<void> _purgeLegacyCache() async {
    final lru = ctx.storageGet('lru');
    if (lru is! List || lru.isEmpty) return;
    for (final k in lru) {
      ctx.storageSet('$k', null);
    }
    ctx.storageSet('lru', null);
  }

  // ------------------------------------------------------------------
  // 采样与绘制
  // ------------------------------------------------------------------

  /// 播放中按流逝时间外推位置，把 250ms 的采样间隔抹平
  int _nowPos() {
    final media = _media;
    if (media == null || media['available'] != true) return 0;
    var p = (media['position'] as num?)?.toInt() ?? 0;
    if (media['status'] == 4) {
      // positionAge 是播放器上报位置到 native 采样之间的时间；
      // __localAt 是 Dart 收到快照到现在的本地流逝时间。
      p += (media['positionAge'] as num?)?.toInt() ?? 0;
      final localAt = media['__localAt'];
      if (localAt is int) p += DateTime.now().millisecondsSinceEpoch - localAt;
    }
    if (p < 0) p = 0;
    final duration = (media['duration'] as num?)?.toInt() ?? 0;
    if (duration > 0 && p > duration) p = duration;
    // 只压 2 秒以内的倒退——真正的拖动定位是大跳，必须放过去
    if (_lastPos > 0 && p < _lastPos && _lastPos - p < 2000) p = _lastPos;
    _lastPos = p;
    return p;
  }

  Future<void> _tick() async {
    final r = await ctx.mediaState();
    if (r['ok'] != true) return;
    if (_dead) return;
    final d = (r['data'] as Map?)?.cast<String, Object?>() ?? {};

    if (d['available'] == true && '${d['title'] ?? ''}'.isNotEmpty) {
      // 快照只在「确实有歌」时才生效：切歌间隙 available 会翻成 false
      d['__localAt'] = DateTime.now().millisecondsSinceEpoch;
      _media = d;
      _idleMs = 0;

      final key = '${d['title']}|${d['artist']}'
          '|${(((d['duration'] as num?) ?? 0) / 1000).round()}';
      if (key != _trackKey) {
        _trackKey = key;
        // 整卡内容版本只跟「哪首歌」走：切歌才整卡交叉淡入
        _viewKey = '${d['title']}|${d['artist'] ?? ''}';
        _lastPos = 0;
        _windowBase = 0;
        // 不清空旧歌词：保留到新歌词加载完成，避免空白闪屏
        _loadLyrics(
            '${d['title']}', '${d['artist'] ?? ''}', (d['duration'] as num?)?.toInt() ?? 0, key);
      }
    } else if (_idleMs < _idleGrace) {
      // 信号短暂丢失（切歌间隙/刷新元数据）：保持旧画面，不闪空
      _idleMs += 100;
    } else if (_media != null) {
      // 连续宽限期没有有效信号：认定停播，切回空态。歌词不清空。
      _media = null;
      _lyricState = 'idle';
    }
    _paint(false);
  }

  /// 只有可见内容真的变了才 render。指纹：当前行、秒数、播放状态、
  /// 进度条的像素位置（300px 条上 1px 以内的变化不值得重绘）。
  void _paint(bool force) {
    final pos = _nowPos();
    final idx = Lrc.indexAt(_lyrics, pos);
    final duration = (_media?['duration'] as num?)?.toInt() ?? 0;
    final barPx = _media != null && duration > 0
        ? (pos / duration * 300).round()
        : 0;
    final sig = [
      _media?['available'] == true ? 1 : 0,
      _trackKey,
      _lyricState,
      idx,
      barPx,
      pos ~/ 1000,
      _media?['status'] ?? -1,
    ].join('\u0001');
    if (!force && sig == _lastPaint) return;
    _lastPaint = sig;
    ctx.render(_view(pos, idx));
  }

  // ------------------------------------------------------------------
  // 视图
  // ------------------------------------------------------------------

  Map<String, Object?> _txt(String v, num size, String? color, num? opacity,
      [Map<String, Object?>? extra]) {
    final n = <String, Object?>{
      't': 'text',
      'v': v,
      'size': size,
      'color': ?color,
      'opacity': ?opacity,
    };
    if (extra != null) n.addAll(extra);
    return n;
  }

  Map<String, Object?> _iconBtn(
      String name, String handler, num size, bool enabled, int box) {
    final icon = {
      't': 'icon',
      'v': name,
      'size': size,
      'color': enabled ? '#FFFFFF' : '#7A7A7A'
    };
    final cell = {'t': 'box', 'w': box, 'h': box, 'center': true, 'child': icon};
    return enabled
        ? {'t': 'tap', 'id': handler, 'child': cell}
        : cell;
  }

  Map<String, Object?> _idleView() {
    return {
      // key 固定 'idle'：与播放视图不同，停播/开播切换时整卡交叉淡入
      'key': 'idle',
      't': 'box',
      'pad': _pad,
      'center': true,
      'child': {
        't': 'col',
        'gap': 8,
        'cross': 'center',
        'children': [
          {
            't': 'icon',
            'v': 'music',
            'size': 26,
            'color': '#FFFFFF',
            'opacity': 0.25
          },
          _txt('没有正在播放的音乐', 12, null, 0.45),
          _txt('支持 SMTC 的播放器都能读到（网易云 / QQ 音乐 / Spotify / 浏览器）',
              10, null, 0.25, {
            'align': 'center',
            'maxLines': 2
          }),
        ]
      }
    };
  }

  /// 按"当前行到底有没有译文"决定当前行高度。
  ///
  /// 滚动模型下**所有行等高**（不然滚动时行距会抖），所以译文改用叠字
  /// 压进同一行，不再撑高。这个方法现在只维护 `_hasTrans`（当前行有
  /// 无译文），供调试与将来需要区分时使用。
  void _syncLineHeights(int idx) {
    _hasTrans = _settings['trans'] == true &&
        idx >= 0 &&
        idx < _lyrics.length &&
        _lyrics[idx].tr.isNotEmpty;
  }

  /// 歌词区能放下几行（**一律按单行高度算**）。
  ///
  /// 滚动模型要求每行等高：如果当前行因为带译文而变高，滚动时行与行的
  /// 间距就会忽大忽小，看起来是"抖"而不是"滚"。所以译文改用**叠字**的
  /// 方式挤在同一行高度内（字号小一点），不再撑高行。
  int _visibleLines() {
    final avail = _h - _pad * 2 - _headerBlock;
    var n = (avail / _lineContext).floor();
    if (n < 1) n = 1;
    if (n > 18) n = 18;
    return n;
  }

  Map<String, Object?> _lyricArea(int idx) {
    _syncLineHeights(idx);
    final lines = _visibleLines();
    // 当前句放在可见区的偏上位置：上方约 1/3、下方 2/3
    final anchor = ((lines - 1) / 3).floor().clamp(0, lines - 1);
    // 当前行在"整段歌词"里的下标；idx<0（前奏）时锚在第一行
    final cur = idx < 0 ? 0 : idx;
    // 窗口起点：让 cur 落在 anchor 号槽位里
    var base = cur - anchor;
    if (base > _lyrics.length - lines) base = _lyrics.length - lines;
    if (base < 0) base = 0;
    _windowBase = base;

    // 滚动偏移：把 base 号行推到槽位 0。弹簧由 'slide' 节点负责，
    // 这里只给目标像素值（行高固定，所以就是简单的乘法）。
    final shift = -(base * _lineContext).toDouble();
    // 多铺两行：滑动过程中上下边缘不能露白
    final slots = lines + 2;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < slots; i++) {
      // 槽位 i 显示第 (base + i - 1) 行——往上多铺了一行。
      // handler 也是照这个映射注册的（见 _registerHandlers），两边必须一致。
      final li = base + i - 1;
      if (li < 0 || li >= _lyrics.length) {
        rows.add({'t': 'box', 'h': _lineContext});
        continue;
      }
      final line = _lyrics[li];
      final dist = (li - idx).abs();
      final isCurrent = dist == 0;
      // 焦点层级：越远越淡
      double op;
      num sz, wt;
      if (dist == 0) {
        op = 1;
        sz = _lyricSize + 2;
        wt = 700;
      } else if (dist == 1) {
        op = 0.55;
        sz = _lyricSize;
        wt = 400;
      } else if (dist == 2) {
        op = 0.32;
        sz = _lyricSize;
        wt = 400;
      } else {
        op = 0.14;
        sz = _lyricSize;
        wt = 400;
      }
      // "正在唱"的这一行带辉光。半径按字号配，光晕必须小于字间距。
      final glowMain = isCurrent
          ? <String, Object?>{'glow': _accent, 'glowSigma': 9}
          : <String, Object?>{};
      final body = _txt(line.s.isEmpty ? '·' : line.s, sz, null, op, {
        'maxLines': 1,
        'weight': wt,
        ...glowMain,
      });
      // 译文只在"正在唱"的这一行显示，且**不撑高行**——压成小字叠在
      // 正文下面一点点，整行仍占 _lineContext。滚动时行距才是一致的。
      final cell = (isCurrent && line.tr.isNotEmpty)
          ? {
              't': 'col',
              'gap': 0,
              'children': [
                body,
                _txt(line.tr, _lyricSize - 4, null, 0.7, {
                  'maxLines': 1,
                  'glow': _accent,
                  'glowSigma': 6,
                })
              ]
            }
          : body;
      // 每行钉死在同一高度预算内（滚动模型的前提）
      rows.add({
        't': 'tap',
        'id': _hLine[i],
        'child': {
          't': 'box',
          'h': _lineContext,
          'clip': true,
          'pad': [4, 0],
          'child': cell
        }
      });
    }
    // 外层的固定高度 + clip 很关键：滑动时内容会超出这块区域（往上平移
    // 会把顶部行推出边界、往下留出空白槽），不裁就会画到卡片外面去。
    return {
      't': 'box',
      'h': _lineContext * lines,
      'clip': true,
      'child': {
        't': 'slide',
        'v': shift,
        'child': {
          't': 'col',
          'gap': 0,
          'children': rows,
        }
      }
    };
  }

  Map<String, Object?> _lyricPlaceholder() {
    final msg = _lyricState == 'loading' ? '正在找歌词…' : '没找到这首歌的歌词';
    return {
      // 高度必须和真有歌词时一致，否则切歌时整块跳一下。
      // 滚动模型下每行等高，直接用 行高 × 可见行数。
      't': 'box',
      'center': true,
      'h': _lineContext * _visibleLines(),
      'child': _txt(msg, 12, null, 0.35)
    };
  }

  Map<String, Object?> _view(int pos, int idx) {
    final media = _media;
    if (media == null || media['available'] != true) return _idleView();

    final playing = media['status'] == 4;
    final dur = (media['duration'] as num?)?.toInt() ?? 0;

    final left = {
      't': 'col',
      'gap': 8,
      'cross': 'start',
      'children': [
        {
          't': 'image',
          'key': '${media['artKey'] ?? ''}',
          'w': _artSize,
          'h': _artSize,
          'radius': 10
        },
        {
          't': 'col',
          'gap': 1,
          'children': [
            _txt('${media['title'] ?? '未知曲目'}', 13, null, 0.95,
                {'maxLines': 1, 'weight': 600}),
            _txt('${media['artist'] ?? '未知艺术家'}', 11, null, 0.5,
                {'maxLines': 1}),
          ]
        }
      ]
    };

    final controls = {
      't': 'row',
      'gap': 10,
      'main': 'center',
      'cross': 'center',
      'children': [
        _iconBtn('prev', _hPrev, _ctrlSide, media['canPrev'] == true, _ctrlBox),
        _iconBtn(playing ? 'pause' : 'play', _hToggle, _ctrlMain,
            playing ? media['canPause'] == true : media['canPlay'] == true,
            _ctrlBox),
        _iconBtn('next', _hNext, _ctrlSide, media['canNext'] == true, _ctrlBox),
      ]
    };

    final bar = {
      't': 'col',
      'gap': 2,
      'children': [
        {
          't': 'slider',
          'id': _hSeek,
          'h': 3,
          'v': dur > 0 ? pos / dur : 0,
          'color': '#FFFFFF',
          'bg': '#FFFFFF33', // RRGGBBAA，alpha 在后
          // 播放器不支持定位时置灰
          'enabled': media['canSeek'] == true && dur > 0,
        },
        {
          't': 'row',
          'main': 'between',
          'children': [
            _txt(Lrc.fmt(pos), 9.5, null, 0.4, {'mono': true}),
            _txt(Lrc.fmt(dur), 9.5, null, 0.4, {'mono': true}),
          ]
        }
      ]
    };

    final right = {
      't': 'col',
      'gap': 6,
      'children': [
        controls,
        bar,
        // 换行/换词原地替换内容：不传 animKey（该动画已因闪白禁用）
        {
          't': 'flex',
          'f': 1,
          'child': _lyrics.isNotEmpty
              ? _lyricArea(idx)
              : _lyricPlaceholder()
        }
      ]
    };

    return {
      // key 挂「歌名|歌手」：切歌时整卡交叉淡入，不含时长（时长从 0 刷新
      // 到正常值不会触发第二次整卡过渡）
      'key': _viewKey,
      't': 'box',
      'pad': _pad,
      'child': {
        't': 'row',
        'gap': 14,
        'cross': 'start',
        'children': [
          {'t': 'box', 'w': _artSize, 'child': left},
          {'t': 'flex', 'f': 1, 'child': right},
        ]
      }
    };
  }

  // ---- 事件处理器 id（树里引用的）----
  late final String _hPrev;
  late final String _hToggle;
  late final String _hNext;
  late final String _hSeek;

  @override
  void mount() {
    _settings = Map<String, Object?>.from(ctx.settings);
    _w = ctx.size.width;
    _h = ctx.size.height;
    _accent = ctx.themeAccent ?? '#7CC7FF';

    // ---- 界面尺寸：按卡片高度缩放，小尺寸也不至于挤成一团 ----
    var artSize =
        min(_h - _pad * 2 - _textBlock - _artGap, (_w * 0.24).round());
    if (artSize < 52) artSize = 52;
    _artSize = artSize.toDouble();

    final lyricSize = _h >= 380
        ? 15.5
        : _h >= 260
            ? 14.0
            : 13.0;
    _lyricSize = lyricSize;
    // 行高：真机同款字体实测的单行/双语组合高度（三档字号与断点对应）。
    // +10 是行内 pad:[4,0] 的上下留白加一点容错。
    final lineMetrics = {
      13.0: (21, 37),
      14.0: (23, 41),
      15.5: (25, 45),
    };
    final metrics = lineMetrics[lyricSize] ?? (21, 37);
    // 滚动模型下每行等高，所以行高**只取单行值**。译文不再撑高行，
    // 而是压成小字叠在同一行里（见 _lyricArea 的 cell）。
    _lineContext = metrics.$1 + 10;

    // 行槽位：可见行数 + 2（滚动时上下各多铺一行）
    _lyricLines = _visibleLines();
    _slotCount = _lyricLines + 2;

    _registerHandlers();
    _lyrics = [];
    ctx.render(_idleView());
    _purgeLegacyCache();
    _tick();
    ctx.interval(_tick, 100);
  }

  @override
  void unmount() {
    _dead = true;
    super.unmount();
  }

  @override
  void onSettingsChange() {}

  // ------------------------------------------------------------------
  // 测试探针：让布局契约可被断言，而不是靠肉眼看截图
  // ------------------------------------------------------------------

  @visibleForTesting
  int get debugLineContext => _lineContext;

  @visibleForTesting
  int get debugVisibleLines => _visibleLines();

  @visibleForTesting
  int get debugSlotCount => _slotCount;

  @visibleForTesting
  int get debugWindowBase => _windowBase;

  @visibleForTesting
  bool get debugHasTrans => _hasTrans;

  @visibleForTesting
  void debugSetLyrics(List<LrcLine> lines) {
    _lyrics = lines;
    _lyricState = 'ok';
  }

  /// 直接渲染"有歌词"的那个分支，绕过 _media 空态检查。
  /// 测试关心的是歌词区布局，不是 SMTC 有没有歌。
  @visibleForTesting
  void debugPaint(int idx) {
    ctx.render({
      't': 'box',
      'pad': _pad,
      'child': _lyrics.isNotEmpty ? _lyricArea(idx) : _lyricPlaceholder(),
    });
  }
}
