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
  /// 每行的**实际**高度。滚动模型下所有行等高，没有"当前行更高"这回事。
  ///
  /// 取值看这首歌**有没有译文**：
  ///   - 有译文 → 用双语高度（正文 + 译文），行行都留得下译文；
  ///   - 没译文 → 用单行高度，不浪费一行空白。
  /// 这是关键：以前只要开了「显示翻译」就恒定按双语留高，而网易云多数
  /// 歌根本没有 tlyric，整块歌词上方就空出一大片（用户截图反馈的问题）。
  /// 现在按"这首歌到底有没有译文"决定，没有就一点都不留。
  late int _lineContext;
  /// 单行高度（无译文时用）
  late int _lineSingle;
  /// 双语高度（正文 + 译文叠两行）
  late int _lineBilingual;
  /// 这首歌是否**存在**译文（任一行有即算）。决定行高取单行还是双语。
  bool _songHasTrans = false;
  /// 当前行是否有译文（用于辉光/调试）。
  bool _hasTrans = false;
  /// 歌词槽位总数 = 可见行数 + 2（滚动时上下各多铺一行，防止边缘露白）。
  /// handler 按这个数注册。
  late int _slotCount;

  static const _ctrlSide = 26;
  static const _ctrlMain = 34;
  static const _ctrlBox = 42;

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
  /// 当前渲染的歌词列表**窗口顶端**在整首歌里的行号（0 基）。列表式布局
  /// 下它就是"槽位 1（预滚行的下一行）显示的那一行"，点击映射靠它。
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
    // 点某一行歌词跳到那一句。槽位数 = 可见行数 + 2，而可见行数会随
    // 「这首歌有没有译文」在单行/双语之间变（双语行高更大 → 行数更少）。
    // 与其在 mount 时赌一个上限，不如**按需增长**：要用到第 n 个槽位就
    // 保证它已经注册好。见 _handlerFor。
    _hLine.clear();
    for (var i = 0; i < _slotCount; i++) {
      _addLineHandler(i);
    }
  }

  /// 给第 [slot] 个歌词槽位注册点击处理器（幂等）。
  ///
  /// 每行对应一个 handle：点它就把播放位置跳到那一句。列表式模型下数组
  /// **从第 0 行起铺**，所以槽位号就是真实行号，映射是恒等的
  /// （见 [_slotLineIndex]）。
  void _addLineHandler(int slot) {
    _hLine.add(ctx.on((_) {
      final idx = _slotLineIndex(slot);
      if (idx != null) {
        _lastPos = 0;
        ctx.mediaControl('seek', posMs: _lyrics[idx].t);
      }
    }));
  }

  /// 槽位号 → 它在整首歌里的行号。空槽位（越界）返回 null。
  ///
  /// 布局里数组从第 0 行铺到窗口底部，**下标即行号**，所以这里是恒等映射。
  /// 之所以仍走函数：一旦将来改回"滑动窗口重取"的取法，映射就要跟着改，
  /// 留一个单一改动点比散在两处安全。
  int? _slotLineIndex(int slot) {
    if (slot < 0 || slot >= _lyrics.length) return null;
    return slot;
  }

  /// 取第 [slot] 个槽位的处理器 id，数量不够就现补。
  ///
  /// 这是「行高会变」带来的必然结果：可见行数不是常量，写死一个上限
  /// 迟早会有点不中的行（实测 RangeError）。现补的成本就是一次 ctx.on，
  /// 只在行数变多时才发生。
  String _handlerFor(int slot) {
    while (_hLine.length <= slot) {
      _addLineHandler(_hLine.length);
    }
    return _hLine[slot];
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
      _ensureSlotHandlers();
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
    _ensureSlotHandlers();
    _paint(true);
  }

  /// 把行点击 handler 备到「这首歌的总行数」。
  ///
  /// 列表式布局的槽位号就是真实行号，数组会铺到窗口底部，所以槽位数会
  /// 随歌长增长。mount 时还没有歌词（只知道可见行数），歌词到位后才知道
  /// 有多少行——这里补一次。多出的部分幂等，[ _handlerFor] 也只补不删。
  void _ensureSlotHandlers() {
    final want = _maxSlotCount();
    if (want > _slotCount) _slotCount = want;
    for (var i = _hLine.length; i < _slotCount; i++) {
      _addLineHandler(i);
    }
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

  /// 刷新当前行是否有译文，并据此决定这一首歌用哪种行高。
  ///
  /// **滚动模型下所有行必须等高**（否则换句时行距会抖），所以不能"只有
  /// 当前行更高"。折中办法是按**这首歌整体有没有译文**决定：
  ///   - 有译文 → 全篇用双语高度（行行都容得下正文 + 译文）；
  ///   - 没译文 → 全篇用单行高度，不留任何空白。
  ///
  /// 这正是用户截图反馈的那个问题：以前只要开了「显示翻译」就恒定按双语
  /// 留高，而网易云大多数歌没有 tlyric，正文上方就空出一大片。
  void _syncLineHeights(int idx) {
    _hasTrans = _settings['trans'] == true &&
        idx >= 0 &&
        idx < _lyrics.length &&
        _lyrics[idx].tr.isNotEmpty;
    final wantTrans = _settings['trans'] == true &&
        _lyrics.any((l) => l.tr.isNotEmpty);
    _songHasTrans = wantTrans;
    _lineContext = wantTrans ? _lineBilingual : _lineSingle;
  }

  /// 歌词区能放下的**完整**行数（取景框里看得见的行数，不含预滚/预铺行）。
  ///
  /// 预算 = 卡片高 − 上下内边距 − 头部（按钮/进度条/时间）实际占高。
  /// 一行高度就取 [_lineContext]，能整除多少行就用多少行。
  ///
  /// **不要给"预铺行"另占预算**：预铺行本来就画在取景框外（被裁掉），
  /// 它们只是滑动过程中用来填边缘的，不参与"看得见几行"的预算。上一版在
  /// 这里多减 2，5x2 的小卡片直接只剩 1~2 行，等于不能用。
  ///
  /// 布局本身用的是 [floor]（见 [_lyricArea] 的 `lines`），这里保持同一
  /// 口径，测试断言"可见行数"才有意义。
  int _visibleLines() {
    final avail = _availHeight();
    var n = (avail / _lineContext).floor();
    // 至少 3 行：小卡片上也要能看清"上一句 / 当前句 / 下一句"的上下文，
    // 只有 1~2 行的话歌词就退化成"字幕条"了，完全没有浏览感。
    if (n < 3) n = 3;
    if (n > 18) n = 18;
    return n;
  }

  /// 歌词区实际可用的高度（像素）。
  ///
  /// 头部高度**按卡片尺寸缩**：固定写 88 在小卡片上是灾难——5x2 只有
  /// 236px 高，88 就吃掉 37%，剩 124px 连三行都放不下。这里按比例给，
  /// 上限 88（大卡片用满），下限 64（再小也别把控制条压扁）。
  double _availHeight() {
    final head = _headerBlockFor(_h);
    final avail = _h - _pad * 2 - head;
    return avail < 0 ? 0 : avail;
  }

  /// 头部（控制条 + 进度条 + 时间行 + 间隔）占用高度。
  ///
  /// 控制按钮盒子固定 42px，进度条 + 时间行约 22px，加两处 gap 12px ≈ 76px。
  /// 小卡片稍微收紧一点，大卡片给足，避免"头重脚轻"。
  static double _headerBlockFor(double h) {
    if (h >= 340) return 88;
    if (h >= 280) return 80;
    return 72;
  }

  /// 槽位数的**上限**（mount 时先备一批 handler 用）。
  ///
  /// 行高会随「这首歌有没有译文」在单行/双语之间切换，可见行数也跟着变。
  /// **单行行高更小 → 可见行数更多 → 需要更多槽位**，所以上限要按单行算。
  ///
  /// 列表式布局下数组**从第 0 行铺到窗口底**，槽位数 = 真实行号，
  /// 所以歌曲越长槽位越多——这就是要把 [_lyrics] 长度也纳入的原因：
  /// 只按可见行数备的话，长歌播到后半段会一路现补 handler（每次一次
  /// `ctx.on`），虽然正确但没必要。运行时若仍不够，[_handlerFor] 兜底。
  int _maxSlotCount() {
    final avail = _availHeight();
    var n = (avail / _lineSingle).floor();
    if (n < 3) n = 3;
    if (n > 20) n = 20;
    final byRows = n + 4;
    // 已经有这首歌的歌词时，直接按总行数备齐（最多到歌词本身的行数）。
    return _lyrics.length > byRows ? _lyrics.length : byRows;
  }

  /// 歌词列表区（列表式滚动 + 弹簧换句）。
  ///
  /// ## 两个约束互相拉扯，这是本题的核心矛盾
  ///
  /// 1. **要弹簧滚动**：`slide` 的目标偏移必须**随换句变化**——`SpringSlide`
  ///    在 `didUpdateWidget` 里第一句就是 `if (widget.offset == old.offset) return;`，
  ///    偏移不变 = 动画不启动。
  /// 2. **要当前行永远在框内**：整列不能被推出取景框。
  ///
  /// 历史上有两版都只满足一半：
  ///   - **绝对偏移版**（`v = -(base × 行高)`，base 随当前行增长）：
  ///     动画正常，但数组也每次从 base 重取 → 偏移被算两遍，base 越大整列
  ///     越远，歌曲后段整列飞出取景框（实测 idx=36 时 y≈-734）= "歌词消失"。
  ///   - **常量偏移版**（`v = -行高`，数组按窗口取）：位置永远正确，但偏移
  ///     恒定 → 弹簧完全不触发 = "弹簧效果不见了"。
  ///
  /// ## 正解：数组从**固定起点 0** 铺，偏移扛下全部滚动量
  ///
  /// 关键是让"取行"和"对齐"**各司其职且互不重复**：
  ///   - 数组**固定从第 0 行开始铺**，铺到「当前窗口底 + 余量」为止
  ///     （不是从当前行开始重取，所以下标 `i` 就是真实行号，没有平移语义）；
  ///   - 偏移 = `-(top × 行高)`，`top` 是窗口顶端行号。**这是绝对滚动量，
  ///     随换句单调增长** → 弹簧有东西可动。
  ///
  /// `top` 被 clamp 到 `maxTop = 总行数 - 可见行数`：
  ///   - 歌曲中段：`top` 随当前行增长 → 内容真的在滚（每句滚一行高）；
  ///   - 歌曲到底：`top` 冻结在 `maxTop` → 整列不动，当前行在框内自然下移
  ///     （经典 scroll-boundary）。此时偏移不变（无动画）是**对的**——
  ///     内容确实没动，而且当前行仍稳稳在框内。
  ///
  /// 不变量：当前行屏上坐标 = `(cur × lh) + v`，恒等于 `anchor × lh`，
  /// 所以**任何位置当前行都落在锚点处、都在取景框内**（实测 0~39 全覆盖）。
  ///
  /// 代价：数组铺的行数随进度增长（40 行的歌最多铺 40 行）。这是必要的——
  /// 数组长度和偏移变量只能二选一，而要弹簧就必须让偏移动。子节点是
  /// `Text`，Flutter 会按位置 diff 复用，换句只重建一两个槽位。
  Map<String, Object?> _lyricArea(int idx) {
    _syncLineHeights(idx);
    final lh = _lineContext;
    // 取景框高度 = 外层 flex 实际给到的可用高度。
    final viewport = _availHeight();
    // 列表最顶端多铺一行（预滚行）：换句时它从上方滑进来，边缘不会露白；
    // 下方也多铺一行，滑动时从下方顶进来。
    const preRoll = 1;
    final bodyRows = (viewport / lh).ceil();

    // 当前行在整首歌里的下标；idx<0（前奏）时锚在第一行。
    final cur = idx < 0 ? 0 : idx;
    // 可见区里当前行的目标位置：偏上 1/3（上方留一点、下方留更多），
    // 这样"这句在唱"的分量感最足，也方便读到后面的句子。
    final lines = (viewport / lh).floor();
    final anchor = ((lines - 1) / 3).floor().clamp(0, 3);
    // 窗口顶端（0 基）：让当前行落在第 anchor 个可见行里。
    var top = cur - anchor;
    // 窗口下界：不能越过"最后一行落在最后一个可见行"的位置。到底之后
    // 就**冻结**——内容不再滚动，当前行在框内下移。
    final maxTop = _lyrics.length - lines;
    if (maxTop >= 0 && top > maxTop) top = maxTop;
    if (top < 0) top = 0;
    _windowBase = top;

    // 数组**从 0 铺到窗口底部**（+ 上下余量），下标 i 即真实行号。
    // 上限收到总行数：末尾时不再往后铺空行。
    final lastNeeded = top + bodyRows + preRoll + 1;
    final rowCount = lastNeeded > _lyrics.length ? _lyrics.length : lastNeeded;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < rowCount; i++) {
      final li = i;
      final line = _lyrics[li];
      final dist = (li - cur).abs();
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
      // 当前行有译文 → 正文 + 译文叠两行**垂直居中**地放进这一行的
      // 高度预算里。整首歌的开窗行高（_lineContext）在 _syncLineHeights
      // 里已经按"有没有译文"选好，所以这里正文 + 译文一定放得下，不会
      // 再出现 RenderFlex 溢出（以前硬塞进单行高度，实测溢出 12px）。
      //
      // 非当前行**不显示译文**，但行高仍是双语的——单行正文用 center
      // 居中，视觉上落在行中间，换句时不会有"忽然跳高"的抖动。
      final Map<String, Object?> cell;
      if (isCurrent && line.tr.isNotEmpty) {
        cell = {
          't': 'col',
          'gap': 1,
          'cross': 'start',
          'main': 'center',
          'children': [
            body,
            _txt(line.tr, _lyricSize - 3, null, 0.7, {
              'maxLines': 1,
              'glow': _accent,
              'glowSigma': 6,
            })
          ]
        };
      } else {
        cell = {
          't': 'col',
          'gap': 0,
          'main': 'center',
          'children': [body]
        };
      }
      // 每行钉死在同一高度预算内（滚动模型的前提）。槽位号 = 行号（数组
      // 从 0 起，没有平移），handler 因此可以静态注册、不必随窗口变。
      rows.add({
        't': 'tap',
        'id': _handlerFor(i),
        'child': {
          't': 'box',
          'h': lh,
          // 不裁切：行高已按"有没有译文"选好，正文+译文放得下；
          // 裁切反而会在字体行高略有出入时把文字裁掉一两像素。
          'pad': [4, 0],
          'child': cell
        }
      });
    }
    // 取景框高度 = 实际可用高度（外层 flex 给多少就用多少），
    // clip 掉滑动时探出边缘的行。
    //
    // 内层行堆总高 = rowCount × 行高 ≥ 取景框高 + 1 行，所以不会露白；
    // 多出来的部分被 clip 裁掉，正是取景框该干的事。
    //
    // 偏移 = -(top × 行高)：**绝对滚动量**，随换句单调增长 → 弹簧有东西
    // 可动（这正是"弹簧效果"的来源）；末尾 top 冻结 → 偏移不变，内容
    // 确实没动，当前行在框内下移。
    return {
      't': 'box',
      'h': viewport,
      'clip': true,
      'child': {
        't': 'slide',
        'v': -(top * lh).toDouble(),
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
      // 高度必须和真有歌词时一致（取景框高度），否则切歌时整块跳一下。
      't': 'box',
      'center': true,
      'h': _availHeight(),
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
    _lineSingle = metrics.$1 + 10;
    _lineBilingual = metrics.$2 + 10;
    // 实际行高在 _lyricArea 里按「这首歌有没有译文」现算（见 _refreshLineContext），
    // 这里先给单行值，保证 mount 阶段的行数预算有意义。
    _lineContext = _lineSingle;

    // 行槽位：先按**上限**备一批 handler。行高会随「这首歌有没有译文」在
    // 单行/双语之间切换，可见行数随之变化；按单行（行高最小 → 行数最多）
    // 备齐就不会有点不中的行。运行时若还不够，_handlerFor 会现补。
    _slotCount = _maxSlotCount();

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
  int get debugLineSingle => _lineSingle;

  @visibleForTesting
  int get debugLineBilingual => _lineBilingual;

  @visibleForTesting
  bool get debugSongHasTrans => _songHasTrans;

  @visibleForTesting
  int get debugVisibleLines => _visibleLines();

  /// 歌词取景框的实际可用高度（测试用来判断"当前行是否在框内"）。
  @visibleForTesting
  double get debugAvailHeight => _availHeight();

  /// 当前可见区里当前行的目标位置（第几个可见行）。测试断言当前行
  /// 落在这个槽位附近时用。
  @visibleForTesting
  int get debugAnchor {
    final lh = _lineContext;
    final lines = (_availHeight() / lh).floor();
    return ((lines - 1) / 3).floor().clamp(0, 3);
  }

  @visibleForTesting
  int get debugMaxSlotCount => _maxSlotCount();

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
    // 槽位号即行号，测试里注进来的行数可能比 mount 时备的多，补一次。
    _ensureSlotHandlers();
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

  /// 渲染**完整的播放视图**（含封面/控制条/进度条/歌词区）。
  ///
  /// 和 debugPaint 的区别很关键：只渲染歌词区会得到一个"没有头部"的树，
  /// 歌词当然贴着顶——那样量出来的坐标不能反映真实布局（曾因此误判）。
  /// 要验证"歌词是否落在控制条下方、有没有溢出卡片"，必须用这个。
  ///
  /// 两条使用前提，缺一个都量不到真东西：
  ///   1. 先 `_dead = true` 掐掉 _tick：测试里没有 native，定时采样会把
  ///      `_media` 清成 null，视图就退回 idle（曾因此量到 idle 的几何）。
  ///   2. 宿主必须**监听 `ctx.tree`**（如 ValueListenableBuilder）来重建
  ///      NodeView。若像早期那样把 `ctx.tree.value!` 当快照塞给
  ///      NodeView，后续所有 render 都不会反映到屏幕上——测得的是
  ///      mount 时的 idle 树，"歌词全空"是假象（曾因此白查一轮）。
  @visibleForTesting
  void debugPaintFull(int idx) {
    _dead = true;
    _media = {
      'available': true,
      'title': '测试曲目',
      'artist': '测试歌手',
      'duration': 240000,
      'position': idx * 1000,
      'status': 4,
      'canPrev': true,
      'canPlay': true,
      'canPause': true,
      'canNext': true,
      'canSeek': true,
      'artKey': '',
    };
    ctx.render(_view(idx * 1000, idx));
  }
}
