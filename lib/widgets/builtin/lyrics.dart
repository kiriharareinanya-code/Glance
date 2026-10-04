/// 内置组件：歌词。
///
/// 数据分两路：
///   「正在放什么」来自 Windows 系统媒体控件（SMTC）；
///   「歌词」来自 `lib/lyrics/**`（Lyricify 歌词逻辑的移植，纯 Dart）——
///   经由 `lib/widgets/lyrics_bridge.dart` 接上宿主的网络/日志，取词统一走
///   `LyricsEngine.fetch()`：多源顺序、匹配打分门槛、语言偏好过滤、信息行
///   裁剪、逐字词合并都在引擎里，本文件**不再自己搜歌、自己拼 LRC**。
///
/// 引擎返回的 `LyricsData` 由 `lib/widgets/lyrics_view.dart` 的
/// [LyricsView]/[LyricsLine] 转成渲染模型（含逐字音节），本文件只负责画：
///   - 当前行用 `LyricsLine.sungCharsF(pos)` 做**逐字（卡拉OK）高亮**——
///     连续量，配 [ShaderMask] 的横向渐变遮罩擦出平滑推进的边界；
///   - 没有逐字数据时退化成原来的整行高亮，行为与旧版一致。
///
/// 位置自己外推：native 每 250ms 采样一次 SMTC，播放中按流逝时间往前推，
/// 把采样间隔抹平；切歌/暂停/拖动时快照会纠正回来。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../lyrics/engine.dart';
import '../catalog.dart';
import '../images.dart' show WidgetImages;
import '../kit.dart'
    show PluginSlider, TapFeedback, iconDataFor, nodeColor, nodeGlow;
import '../lyrics_bridge.dart' show installLyricsHost;
import '../lyrics_view.dart' show LyricsLine, LyricsView;
import '../morph_icons.dart' show MorphableIcon;
import '../node_anim.dart'
    show NodeAnimatedColor, kNodeAnimCurve, kNodeAnimDuration;
import '../spring_transition.dart' show SpringSlide;
import 'lrc.dart';

class LyricsWidget extends BuiltinController {
  LyricsWidget(super.ctx);

  late Map<String, Object?> _settings;
  late double _w;
  late double _h;

  late String _accent = '#7CC7FF';

  // ---- 界面尺寸：按卡片高度缩放 ----
  static const double _pad = 12;
  static const _textBlock = 70;
  static const double _artGap = 8;
  late double _artSize;
  late double _lyricSize;

  /// 窄卡片模式：宽度不足以横排「封面 + 歌词」时切到上下堆叠，并收紧
  /// 各处的固定尺寸。由 mount() 按 ctx.size.width 判定（见那里的注释）。
  bool _narrow = false;
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
  /// 这首歌是否**存在**译文（渲染模型里任一行有译文即算）。决定行高取单行
  /// 还是双语。
  ///
  /// 直接问 `_view`（"这首歌到底有没有译文"是渲染模型的属性），不再自己
  /// 遍历行数组统计。`_settings['trans']` 也要与进来：缓存可能是开着翻译时
  /// 写下的，用户关掉翻译后不该继续按双语留高（那正是"上方空一大片"的旧问题）。
  bool get _songHasTrans =>
      _settings['trans'] == true && (_view?.hasTranslation ?? false);
  /// 当前行是否有译文（用于辉光/调试）。
  bool _hasTrans = false;

  static const _ctrlSide = 26;
  static const _ctrlMain = 34;
  static const _ctrlBox = 42;

  // ---- 运行时状态 ----
  Map<String, Object?>? _media; // 最近一次「有歌在放」的 SMTC 快照
  /// 歌词渲染模型（引擎取词结果 / 缓存解析结果）。null = 还没有歌词。
  ///
  /// 命中判断、行文本、译文、逐字进度全部走它，卡片自己不再持有
  /// `List<LrcLine>`。
  LyricsView? _view;
  String _lyricState = 'idle'; // idle | loading | ok | none
  String _trackKey = '';

  /// **当前显示的这份歌词**是按哪个 key 取到的。
  ///
  /// 要分清两件长得一样但性质完全不同的事（用户实拍截图指出来的）：
  ///   - SMTC 标题在「XXX - Chinese Ver.」和「XXX (Honkai Star Rail)」之间
  ///     **跳变**——同一首歌、两个 key，第二次搜索失败不该把已显示的歌词清掉；
  ///   - 真的**换了另一首没歌词的曲子**（纯音乐等）——这时必须清掉，
  ///     否则屏幕上一直挂着上一首歌的词，内容和声音完全对不上。
  /// 光看"这次搜索失败"区分不了，只能问"新 key 和显示中的这份是不是同一首"。
  String _lyricKey = '';
  String _viewKey = 'idle';
  int _idleMs = 0;
  static const int _idleGrace = 3000;

  /// 上一帧 [_tick] 的本地时刻，用来在两次 tick 之间量**真实**流逝时间。
  /// 不能写死 tick 周期：native 采样偶尔慢一拍，累加常量会把宽限期算短。
  int _idleAtMs = 0;
  String _lastPaint = '';
  int _lastPos = 0;

  /// 当前歌词行（还没有歌词时是空列表，取用一律安全）。
  List<LyricsLine> get _lines => _view?.lines ?? const <LyricsLine>[];
  /// 当前渲染的歌词列表**窗口顶端**在整首歌里的行号（0 基）。
  int _windowBase = 0;
  bool _dead = false;

  /// 用户用滚轮手动浏览的偏移量，单位「行」。
  ///
  /// 自动跟随时为 0（窗口锚在当前行）。滚轮往下滚为正——窗口整体下移，
  /// 让人能读后面的歌词；往回滚为负。超过 [_browseHoldMs] 没有新的滚轮
  /// 事件就自动回 0，重新跟着歌走。
  int _browseOffset = 0;
  int _browseAtMs = 0;
  static const int _browseHoldMs = 4000;
  /// 每次滚轮滚动几行：Windows 上 wheel delta 一格是 ±120，所以 60 ≈ 两行。
  static const double _wheelPerLine = 60;
  /// 滚轮的小数余额。触控板/高精度鼠标每次只给几像素，直接 round 会整段
  /// 抹成 0（表现为"推了没反应"），所以把不足一行 remainder 存下来，
  /// 跟下一次累加。
  double _wheelAccum = 0;

  /// 上一帧的「跟随位置」窗口顶端行号，和它能走到的下界（歌尾）。
  ///
  /// 浏览偏移是**相对跟随位置**的增量，夹取必须知道这两个数；它们由
  /// [_lyricArea] 每帧算出并回填（渲染的地方才知道可见行数与锚点）。
  int _browseBase = 0;
  int _browseMax = 0;

  // ------------------------------------------------------------------
  // 交互（原生通道：点击直接闭包调 ctx.mediaControl，不再经 id 事件表）
  // ------------------------------------------------------------------

  void _prev() => ctx.mediaControl('prev');
  void _toggle() => ctx.mediaControl('toggle');
  void _next() => ctx.mediaControl('next');

  /// 进度条定位。dur 无效时忽略（与旧 handler 的守门一致）。
  void _seekFraction(num fraction) {
    final media = _media;
    if (media == null || (media['duration'] as num? ?? 0) <= 0) return;
    _lastPos = 0; // 定位是大跳，先解除单调保护
    final dur = (media['duration'] as num).toInt();
    ctx.mediaControl('seek', posMs: (fraction * dur).round());
  }

  /// 点某一行歌词：跳到那一句，并**立刻高亮那一行**。
  ///
  /// 清 `_browseOffset` 是关键，不清就会「点了没反应」：浏览期间
  /// `browsing` 为真，高亮逻辑刻意不给任何行高亮（整列统一 0.82），
  /// 而窗口也停在浏览位置。于是播放位置虽然跳了，画面却纹丝不动，
  /// 用户完全看不出点击生效了。点击的语义就是"我要跳到这句唱"，
  /// 所以必须同时回到跟随状态，让那一行马上成为「正在唱」的行。
  void _seekTo(int lineIndex) {
    final lines = _lines;
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final target = lines[lineIndex].start;
    // 退出浏览：窗口回到跟随位置，这一行会在下一帧成为高亮行。
    _browseOffset = 0;
    _wheelAccum = 0;
    // 乐观接管播放位置：高亮与窗口**同帧**就跳过去，不等 250ms 的采样。
    _seekOptimistic = target;
    _seekOptAtMs = DateTime.now().millisecondsSinceEpoch;
    // 注意不再把 _lastPos 清 0：那道"2 秒内倒退保护"会误吃掉真实采样
    // 回来的位置（点在后面的行时，真实值短暂比目标小），表现为"点了又弹回去"。
    ctx.mediaControl('seek', posMs: target);
    _paint(true);
  }

  // ------------------------------------------------------------------
  // 取歌词
  // ------------------------------------------------------------------

  /// 载入歌词：缓存优先（命中就不联网）→ 引擎取词 → 回写缓存。
  ///
  /// [key] = 「标题|歌手|时长秒」（含时长，区分现场版/录音室版），也是缓存键。
  Future<void> _loadLyrics(
      String title, String artist, int durMs, String key) async {
    // 只在没有旧歌词时设 loading（首次加载），避免状态变化触发重绘闪白
    if (_lines.isEmpty) _lyricState = 'loading';

    // 缓存里存的是 LyricsView.encode() 出来的字符串（旧版裸 LrcLine 数组
    // 也读得懂，decode 里有兼容分支）。
    final cached = LyricsView.decode(await ctx.cacheGet(key));
    if (_trackKey != key) return; // 加载期间已经换歌了
    if (cached != null && cached.lines.isNotEmpty) {
      _view = cached;
      _lyricState = 'ok';
      _lyricKey = key;
      _paint(true);
      return;
    }

    LyricsView? fetched;
    try {
      // 取词全权交给 Lyricify 移植过来的引擎：来源顺序、匹配打分门槛、语言
      // 偏好过滤、信息行裁剪、逐字词合并都在 fetch() 里，卡片不再自己拼。
      final outcome = await LyricsEngine().fetch(
        title: title,
        // 歌手/时长取不到就传 null（旧代码用空串/0 表示"没有"，引擎按 null 判）
        artist: artist.isEmpty ? null : artist,
        durationMs: durMs > 0 ? durMs : null,
        sourcePreference: '${_settings['source'] ?? 'auto'}',
        // 语言要求：标题里的标记（Chinese Ver. 之类）优先；没写就用用户偏好。
        // 默认中文优先——用户是中文用户，英文原文反正还挂着官方翻译，而
        // "曲库里藏着中演唱版"的情况只有偏好启动了才找得到。英文歌不会受
        // 影响：全不符时引擎会回退到兜底候选。
        preferLang: Lrc.wantedLyricLang(title) ??
            switch ('${_settings['preferLang'] ?? 'zh'}') {
              'zh' => 'zh',
              'en' => 'en',
              _ => '',
            },
        // 设置里的「显示制作名单」开着（credits == true）就不裁信息行
        stripInfoLines: _settings['credits'] != true,
      );
      if (outcome != null) {
        fetched = LyricsView.fromData(
          outcome.data,
          sourceName: outcome.sourceName,
          wantTranslation: _settings['trans'] == true,
        );
      }
    } catch (_) {
      fetched = null;
    }
    if (_trackKey != key) return;

    if (fetched != null && fetched.lines.isNotEmpty) {
      _view = fetched;
      _lyricState = 'ok';
      _lyricKey = key;
      // 存字符串：渲染模型自带格式/同步类型/来源/逐字音节，能无损还原
      ctx.cacheSet(key, fetched.encode());
    } else if (_isSameSong(_lyricKey, key)) {
      // **同一首歌**的另一个 key 搜索失败（SMTC 标题在「XXX - Chinese Ver.」
      // 和「XXX (Honkai Star Rail)」之间跳变，同一次切歌会以两个 key 各触发
      // 一次搜索）。保留已显示的歌词，不然用户看到的就是歌词凭空消失。
    } else {
      // **换了另一首**，而这首没有歌词（纯音乐、冷门歌、源都没覆盖）。
      // 必须清掉：屏幕上留着上一首歌的词，歌词和声音完全对不上，比"没歌词"
      // 糟糕得多（用户实拍截图指出来的 bug）。顺带把浏览偏移也清零——
      // 偏移是按行号算的，换歌后行号毫无意义。
      _view = null;
      _lyricState = 'none';
      _lyricKey = '';
      _browseOffset = 0;
    }
    _paint(true);
  }

  /// [a] 和 [b] 是不是同一首歌的两个 key。
  ///
  /// key 格式是 `标题|歌手|时长秒`。判据是**时长**：同一首歌的时长不会变，
  /// 而不同歌撞上完全相同整数秒时长的概率极低（真要撞了，歌词多半也差不多，
  /// 保留错的代价小于清掉对的）。
  ///
  /// 标题**故意不比**：标题正是会跳变的那部分（"Chinese Ver." 后缀、
  /// 副标题、罗马音注记都在变），拿它判会把这两种情况混成一团。
  /// 时长缺失（0 或解析不出）时按"不同歌"处理——宁可显示"没找到"，
  /// 也不显示上一首的词。
  static bool _isSameSong(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final sa = a.split('|');
    final sb = b.split('|');
    if (sa.length < 3 || sb.length < 3) return false;
    final da = int.tryParse(sa[2]);
    final db = int.tryParse(sb[2]);
    if (da == null || db == null || da <= 0 || db <= 0) return false;
    return (da - db).abs() <= 1;
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

  /// **乐观跳转**：点击歌词后立刻假定播放位置已经到 [posMs]。
  ///
  /// 为什么需要：seek 是"发命令给播放器→播放器跳→下一次 SMTC 采样回来"
  /// 的一条异步链，中间最多要等 250ms（native 的采样周期）。用户点了某行
  /// 却要等四分之一秒才看到高亮跳过去，手感是"没点上"。
  /// 所以点完立刻把位置改写成目标值，让高亮和窗口同帧就位；
  /// 真实采样回来后（[_seekPending] 变回 null）自动交棒。
  int? _seekOptimistic;

  /// 乐观跳转的**起点时刻**，用来在等采样期间继续往前走（歌还在放），
  /// 同时也是超时判据：距起点超过 [_seekOptimisticGiveUpMs] 就放弃，
  /// 交回真实采样——有些播放器不支持 seek（SMTC 明确允许拒绝），
  /// 那就得老老实实停在原地，不能一直播一个假位置。
  int _seekOptAtMs = 0;

  static const int _seekOptimisticGiveUpMs = 700;

  /// 取播放位置：乐观值优先，否则用真实采样（含外推与单调保护）。
  int _nowPos() {
    final opt = _seekOptimistic;
    if (opt != null) {
      final waited = DateTime.now().millisecondsSinceEpoch - _seekOptAtMs;
      if (waited > _seekOptimisticGiveUpMs) {
        // 播放器大概拒绝了 seek（或它不回报位置）：放弃乐观值。
        _seekOptimistic = null;
      } else {
        // 歌还在放，等采样期间也要往前走，否则高亮会"卡住不动"。
        final media = _media;
        final playing = media != null && media['status'] == 4;
        return playing ? opt + waited : opt;
      }
    }
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
    if (_dead) return;
    // 记下这一帧的时刻：_idleMs 要按真实流逝时间累加（见字段注释）。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // 浏览超时回到跟随要在任何早退之前做：mediaState() 失败时下面会直接
    // return，否则用户会永远卡在浏览位置（停手了也不跟回去）。
    if (_browseOffset != 0 && _browseExpired()) _paint(true);
    final r = await ctx.mediaState();
    if (_dead) return;
    // 上一次 await 期间可能又来了一帧：那一帧会自己记 _idleAtMs，
    // 这里不能拿自己这一帧的起点去减（会算成负数）。用"只前进"的写法。
    if (_idleAtMs == 0) _idleAtMs = nowMs;
    if (r['ok'] != true) {
      _idleAtMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    final d = (r['data'] as Map?)?.cast<String, Object?>() ?? {};

    if (d['available'] == true && '${d['title'] ?? ''}'.isNotEmpty) {
      // 快照只在「确实有歌」时才生效：切歌间隙 available 会翻成 false
      d['__localAt'] = DateTime.now().millisecondsSinceEpoch;
      _media = d;
      _idleMs = 0;
      // 宽限期归零的同时把计时基准也拨到现在，否则下一帧算流逝时间
      // 会把"归零前那段空白"也算进去。
      _idleAtMs = d['__localAt'] as int;

      // 真实采样回来了 → 乐观位置交棒。
      // 判据是「真实值已经追上（或越过）目标」：这时画面该由真实值接管，
      // 两者衔接上看不出跳变。目标还差得远说明 seek 没生效
      //（播放器不支持/拒绝），由 [_nowPos] 的超时兜底放弃。
      final opt = _seekOptimistic;
      if (opt != null) {
        final real = (d['position'] as num?)?.toInt() ?? 0;
        if ((real - opt).abs() < 1500) {
          _seekOptimistic = null;
          _lastPos = 0; // 交棒后重新建立单调基准
        }
      }

      final key = '${d['title']}|${d['artist']}'
          '|${(((d['duration'] as num?) ?? 0) / 1000).round()}';
      if (key != _trackKey) {
        _trackKey = key;
        // 整卡内容版本只跟「哪首歌」走：切歌才整卡交叉淡入
        _viewKey = '${d['title']}|${d['artist'] ?? ''}';
        _lastPos = 0;
        _windowBase = 0;
        _browseOffset = 0;
        _seekOptimistic = null; // 换歌了，别把上一首的乐观位置带过来
        // 不清空旧歌词：保留到新歌词加载完成，避免空白闪屏
        _loadLyrics(
            '${d['title']}', '${d['artist'] ?? ''}', (d['duration'] as num?)?.toInt() ?? 0, key);
      }
    } else if (_idleMs < _idleGrace) {
      // 信号短暂丢失（切歌间隙/刷新元数据）：保持旧画面，不闪空。
      // 累加的是**真实流逝时间**而不是写死 100：tick 周期从 100 改到 60
      // 之后，写死会让 3 秒的空闲宽限期实际只撑 1.8 秒。
      _idleMs += DateTime.now().millisecondsSinceEpoch - _idleAtMs;
    } else if (_media != null) {
      // 连续宽限期没有有效信号：认定停播，切回空态。歌词不清空。
      _media = null;
      _lyricState = 'idle';
    }
    _paint(false);
  }

  /// 只有可见内容真的变了才 render。指纹：当前行、秒数、播放状态、
  /// 进度条的像素位置（300px 条上 1px 以内的变化不值得重绘）。
  ///
  /// 逐字高亮比"秒"更细：同一秒里已唱字符数就可能变（`LyricsLine.sungCharsF`），
  /// 所以当前行是逐字行时把已唱字符数也进指纹。**只对逐字行加**——普通 LRC
  /// 行的 charsSungAt 是整行进度的折算值，每帧都在变，塞进指纹等于每 100ms
  /// 白重绘一次；而它渲染出来只是整行高亮，本来就不需要更细的重绘。
  /// （也不要直接把 pos 塞进指纹：那是每帧都变。）
  ///
  /// 逐字行这里用**量化到 1/8 字**的浮点而不是整数：逐字动画的边界是连续
  /// 推过去的，只认整数的话每 100ms 才跳一格，看着是"一顿一顿"而不是在动。
  /// 1/8 字 ≈ 一个字宽的 12%，肉眼看不出台阶，但比整数细得多。
  /// （不用完整浮点：那样连未唱部分亚像素抖动都会触发重绘，白烧 CPU。）
  void _paint(bool force) {
    // 浏览超时自动回到跟随。这里每帧都进来，等价于定时器，还不用管生命周期
    if (_browseOffset != 0 && _browseExpired()) force = true;
    final pos = _nowPos();
    final idx = _view?.indexAt(pos) ?? -1;
    final lines = _lines;
    final cur = idx >= 0 && idx < lines.length ? lines[idx] : null;
    final sung = cur != null && cur.isSyllable
        ? (cur.sungCharsF(pos) * 8).round()
        : -1;
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
      sung,
      _media?['status'] ?? -1,
      _browseOffset, // 滚轮浏览位置变了要重绘（否则被节流吃掉）
    ].join('\u0001');
    if (!force && sig == _lastPaint) return;
    _lastPaint = sig;
    ctx.renderWidget(_root(pos, idx));
  }

  // ------------------------------------------------------------------
  // 视图（原生通道：直接产出 Flutter Widget，不再经 JSON 树 / NodeView）
  // ------------------------------------------------------------------

  /// 解析 #RGB / #RRGGBB / #RRGGBBAA（8 位时 alpha 在后，与 node.dart 一致）。
  TextStyle _monoStyle(Color fg) => TextStyle(
        fontSize: 9.5,
        color: fg.withValues(alpha: 0.4),
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _idleView(Color fg) {
    // JSON 版的 box center → 整卡内容居中
    return Padding(
      padding: const EdgeInsets.all(_pad),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MorphableIcon(
              name: 'music',
              size: 26,
              color: Colors.white.withValues(alpha: 0.25),
              animate: false,
              fallback: iconDataFor('music'),
            ),
            const SizedBox(height: 8),
            Text('没有正在播放的音乐',
                style:
                    TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.45))),
            const SizedBox(height: 8),
            Text(
              '支持 SMTC 的播放器都能读到（网易云 / QQ 音乐 / Spotify / 浏览器）',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.25)),
            ),
          ],
        ),
      ),
    );
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
  ///
  /// 译文从哪来：`LyricsView.fromData(..., wantTranslation: ...)` 已经把
  /// 关掉翻译的情况滤掉了，所以「这行有没有译文」就是 `line.trans.isNotEmpty`；
  /// [_songHasTrans] 同样只看渲染模型里到底有没有译文。两边都再与
  /// 「显示翻译」开关取一次与：缓存可能是在开着翻译时写下的，设置关掉后
  /// 不该继续按双语留高（那就会退回上面说的那个空白问题）。
  void _syncLineHeights(int idx) {
    final lines = _lines;
    _hasTrans = _settings['trans'] == true &&
        idx >= 0 &&
        idx < lines.length &&
        lines[idx].trans.isNotEmpty;
    _lineContext = _songHasTrans ? _lineBilingual : _lineSingle;
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

  /// 歌词列表区（列表式滚动 + 弹簧换句，原生 Widget 版）。
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
  ///
  /// [pos] 是当前播放位置（毫秒），只用于当前行的**逐字**高亮
  /// （`LyricsLine.charsSungAt`）——非逐字行一个像素都不受影响。
  /// 滚轮浏览歌词。返回 true 表示消费掉了这次滚轮。
  ///
  /// 放在 PointerSignalResolver 里而不是 Scrollable：歌词列不是列表，是
  /// 按当前行算位置的整列，用 Scrollable 会和"自动跟随当前行"打架。
  /// 浏览期间（[_browseOffset] != 0）窗口锚点被接管；停止滚动
  /// [_browseHoldMs] 之后自动回到跟随模式，不会把人丢在歌词中间不管。
  bool _onWheel(PointerSignalEvent e) {
    if (_lines.isEmpty) return false;
    final dy = e is PointerScrollEvent ? e.scrollDelta.dy : 0.0;
    if (dy == 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 长时间没滚了 → 视为新的浏览会话，从当前自动位置起算
    if (now - _browseAtMs > _browseHoldMs) {
      _browseOffset = 0;
      _wheelAccum = 0;
    }
    _browseAtMs = now;
    // 往下滚（dy > 0）看**后面**的歌词 → 窗口整体下移 → 偏移加。
    // （原来这里写的是 -dy，方向反了：往下滚会去看上一句。）
    // 触控板/高精度鼠标一格只有几像素，先累加小数，满一行才真正挪，
    // 否则每次 round 都归零，表现为"推了没反应"。
    _wheelAccum += dy / _wheelPerLine;
    // 容差 1e-9：纯小数累加会停在 0.9999999999999999 这种值上，永远差一
    // 丝够不到 1，truncate 永远给 0 —— 表现就是"触控板推了一路没反应"。
    // 差这么点本来就该算一行，加个容差把它抹平。
    final delta = (_wheelAccum + 1e-9).truncate();
    if (delta == 0) return true;
    _wheelAccum -= delta;
    _browseOffset += delta;
    _clampBrowseOffset();
    _paint(true);
    return true;
  }

  /// 把浏览偏移限制在「窗口顶端能走到的范围」内。
  ///
  /// 范围是**相对跟随位置**的 `[-跟随top, 歌尾top - 跟随top]`，不是
  /// `[0, 总行数-可见行数]`：往回滚要能一路滚到歌头（偏移为负），
  /// 往后滚要能滚到歌尾。之前夹成 `[0, …]` 的后果是**永远滚不回上一句**，
  /// 只能单向往后翻——这正是这个功能最初要解决的事。
  void _clampBrowseOffset() {
    final lo = -_browseBase;
    final hi = _browseMax - _browseBase;
    if (hi <= lo) {
      // 整首歌一屏装得下，没有浏览空间
      _browseOffset = 0;
      return;
    }
    if (_browseOffset > hi) _browseOffset = hi;
    if (_browseOffset < lo) _browseOffset = lo;
  }

  /// 浏览是否已超时（超时后回到自动跟随）。
  bool _browseExpired() {
    if (_browseOffset == 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _browseAtMs <= _browseHoldMs) return false;
    _browseOffset = 0;
    return true;
  }

  Widget _lyricArea(int pos, int idx, Color fg) {
    _syncLineHeights(idx);
    final arr = _lines;
    final lh = _lineContext;
    // 取景框高度 = 外层 Expanded 实际给到的可用高度。
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
    final base = cur - anchor;
    // 窗口下界：不能越过"最后一行落在最后一个可见行"的位置。到底之后
    // 就**冻结**——内容不再滚动，当前行在框内下移。
    final maxTop = arr.length - lines;
    // 跟随位置先自己夹一次（这是"不浏览时"窗口该在的地方）。
    var top = base;
    if (maxTop >= 0 && top > maxTop) top = maxTop;
    if (top < 0) top = 0;
    // 回填给滚轮夹取用：浏览偏移是相对**跟随位置**的增量，得知道跟随
    // 位置和它能走到的两端（歌头 0 / 歌尾 maxTop）。
    _browseBase = top;
    _browseMax = maxTop < top ? top : maxTop;
    // 用户在滚轮浏览：整列从跟随位置整体下移，可以往下看后面的歌词，
    // 也可以往回滚看前面的。停止滚动 [_browseHoldMs] 后 _browseOffset
    // 归零，自动回到"跟着歌走"。
    if (_browseOffset != 0) {
      _clampBrowseOffset();
      top = _browseBase + _browseOffset;
      if (top > _browseMax) top = _browseMax;
      if (top < 0) top = 0;
    }
    _windowBase = top;

    // 高亮只有一个含义：**这行正在唱**。所以高亮对象永远是播放位置，
    // 滚轮浏览期间不给任何行高亮——用户明确要求过（高亮是"正在唱"的信号，
    // 拿来标记"你正在看哪一行"会把这个信号毁掉：看别的歌的词时一堆行在闪，
    // 分不清哪句是真在唱）。浏览时改成**整列均匀可读**。
    final browsing = _browseOffset != 0;
    final singing = cur;
    // 浏览时视口里可能**根本没有**正在唱的那行（滚到别处去了），
    // 这时全部行一个档位，不制造假的焦点。
    final singingVisible = singing >= top && singing < top + bodyRows;

    // 数组**从 0 铺到窗口底部**（+ 上下余量），下标 i 即真实行号。
    // 上限收到总行数：末尾时不再往后铺空行。
    final lastNeeded = top + bodyRows + preRoll + 1;
    final rowCount = lastNeeded > arr.length ? arr.length : lastNeeded;
    final rows = <Widget>[];
    for (var i = 0; i < rowCount; i++) {
      final li = i;
      final line = arr[li];
      final dist = (li - singing).abs();
      // 正在唱的那一行。浏览时只有它真的落在视口里才算。
      final isSinging = li == singing && (!browsing || singingVisible);
      // 焦点层级：越远越淡。**浏览时整列同一档**——按 dist 分层是为了
      // 跟随时把注意力收到当前句上；浏览时用户要的是"平铺的歌词列表"，
      // 分层只会让窗口外那几行被压到 0.14，读都读不了。
      double op;
      num sz, wt;
      if (browsing) {
        op = 0.82;
        sz = _lyricSize;
        wt = 400;
      } else if (dist == 0) {
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
      // 辉光标的是"正在唱"的那一行，和高亮是同一个含义，同一套规则。
      final glow = isSinging
          ? nodeGlow(nodeColor(_accent), 9)
          : const <Shadow>[];
      final style = TextStyle(
        fontSize: sz.toDouble(),
        fontWeight: wt == 700 ? FontWeight.w700 : FontWeight.w400,
        color: fg.withValues(alpha: op),
        shadows: glow,
      );
      final text = line.text;
      final Widget body;
      // 逐字（卡拉OK）高亮只在**跟随时**、且确实是正在唱的那行才做。
      // 浏览别的句子时按播放位置切已唱/未唱是误导——看着像"这句唱到一半"。
      if (isSinging && !browsing && line.isSyllable && text.isNotEmpty) {
        // 逐字行：已唱的部分亮、未唱的部分暗，且只在这一行上做。
        body = _syllableBody(text, line.sungCharsF(pos), style);
      } else {
        // 没有逐字数据（普通 LRC）**或不是当前行**：整行一个颜色，
        // 与改造前逐像素一致——逐字高亮不会让旧行为退化。
        body = Text(
          text.isEmpty ? '·' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      }
      // 正在唱的那行有译文 → 正文 + 译文叠两行**垂直居中**地放进这一行的
      // 高度预算里。整首歌的行高（_lineContext）在 _syncLineHeights 里
      // 已经按"有没有译文"选好，所以这里正文 + 译文一定放得下。
      //
      // 其余行**不显示译文**，但行高仍是双语的——单行正文用 center
      // 居中，视觉上落在行中间，换句时不会有"忽然跳高"的抖动。
      // 浏览时也走这一条：译文跟着"正在唱"走，不跟着"你在看哪行"走。
      final Widget cell;
      if (isSinging && line.trans.isNotEmpty) {
        cell = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            const SizedBox(height: 1),
            Text(
              line.trans,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _lyricSize - 3,
                color: fg.withValues(alpha: 0.7),
                shadows: nodeGlow(nodeColor(_accent), 6),
              ),
            ),
          ],
        );
      } else {
        cell = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          // JSON 协议里 col 的 cross 默认是 start——漏了这行文字会被
          // 水平居中，各行左边缘错开（真实渲染测试抓到的）。
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [body],
        );
      }
      // 每行钉死在同一高度预算内（滚动模型的前提）。宽度撑满取景框，
      // 让整行（不只文字部分）可点。
      rows.add(TapFeedback(
        animate: ctx.animate,
        onTap: () => _seekTo(i),
        child: SizedBox(
          height: lh.toDouble(),
          width: double.infinity,
          child: Padding(
            // 不裁切：行高已按"有没有译文"选好，正文+译文放得下；
            // 裁切反而会在字体行高略有出入时把文字裁掉一两像素。
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: cell,
          ),
        ),
      ));
    }
    // 取景框高度 = 实际可用高度（外层 Expanded 给多少就用多少），
    // ClipRect 裁掉滑动时探出边缘的行。
    //
    // 内层行堆总高 = rowCount × 行高 ≥ 取景框高 + 1 行，所以不会露白；
    // 多出来的部分被裁掉，正是取景框该干的事。OverflowBox 放开高度约束
    // （行堆天然比取景框高），宽度由外面的 SizedBox 收紧。
    //
    // 偏移 = -(top × 行高)：**绝对滚动量**，随换句单调增长 → 弹簧有东西
    // 可动（这正是"弹簧效果"的来源）；末尾 top 冻结 → 偏移不变，内容
    // 确实没动，当前行在框内下移。
    return SizedBox(
      height: viewport,
      width: double.infinity,
      child: Stack(
        children: [
          ClipRect(
            child: OverflowBox(
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.topCenter,
              child: SpringSlide(
                offset: -(top * lh).toDouble(),
                // 浏览期间关掉弹簧：弹簧是给"自动跟随换句"用的，让人看到
                // 句子平滑滚过去。滚轮是**直接操控**，每格都要立刻到位——
                // 套上弹簧会变成"手还在滚、内容还在追"的橡皮筋延迟感，
                // 而且连滚时弹簧不断被重定向，几乎永远到不了目标位置。
                animate: ctx.animate && !browsing,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows,
                ),
              ),
            ),
          ),
          // 浏览提示：脱离"跟随当前行"时给一条细提示，停手 4 秒后自动消失
          if (_browseOffset != 0)
            Positioned(
              right: 2,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '浏览中 · 停手自动跟随',
                    style: TextStyle(
                      fontSize: 9,
                      color: fg.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 逐字（卡拉OK）高亮：已唱到 [sung] 个字符（**带小数**，见
  /// [LyricsLine.sungCharsF]），后面的压暗。
  ///
  /// 做法是**两个 `Text` 叠在一起**：
  ///   - 底层：整行都用暗色（未唱部分）；
  ///   - 上层：整行亮色（带辉光），再用 [ShaderMask] 按已唱进度做**横向
  ///     渐变遮罩**——亮的部分露出来，暗的部分被遮掉。
  ///
  /// 关键点是**边界能落在字的中间**：上层画的是完整的一行，遮罩只管
  /// "露到哪"，所以推进是连续的，不会一个字一个字地跳。羽化宽度取一个
  /// 字号左右，太窄看成硬边（还是跳），太宽糊成一片看不出走到哪。
  ///
  /// 为什么不按字符数 `ClipRect` 裁宽度：比例字体下"第 n 个字符"的
  /// 边界不在宽度的 n/total 处，会切进字里（这就是之前用两层 `Text`
  /// 叠加而不用裁切的原因）。这里要拿到像素坐标，就用 [TextPainter]
  /// 量一次每个字符的左边界。
  ///
  /// 为什么不用单个 `Text.rich` 分段染色：那样整行得由一个 Text 画，
  /// 没法让"亮的部分带辉光、暗的部分不带"——辉光是跟着已唱范围走的。
  ///
  /// 没有逐字数据的行根本不会走到这里（见 [_lyricArea]），所以旧行为不变。
  Widget _syllableBody(String text, double sung, TextStyle bright) {
    final dim = bright.copyWith(
      color: bright.color?.withValues(alpha: 0.28),
      shadows: const <Shadow>[],
    );
    // 两头都贴边时不用遮罩：0 会有一个"起笔处微微发亮"的残影，
    // 整行唱完时遮罩的羽化也会在末尾啃掉一点字。直接走无遮罩的两层。
    if (sung <= 0) {
      return Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: dim);
    }
    if (sung >= text.length) {
      return Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: bright);
    }
    return LayoutBuilder(
      builder: (context, cons) {
        final m = _syllableMetrics(text, bright, cons.maxWidth);
        // 已唱边界落在像素上的位置：在第 k 个字内部按 frac 线性插值。
        final k = sung.floor().clamp(0, text.length - 1);
        final frac = sung - k;
        final x0 = m.xs[k];
        final edge = x0 + (m.xs[k + 1] - x0) * frac;
        final w = m.width <= 0 ? 1.0 : m.width;
        final t = (edge / w).clamp(0.0, 1.0);
        // 羽化宽度 ≈ 一个字号。LinearGradient 要求 stops 非降序且落在
        // [0,1]，两端 clamp 之后天然满足（t-f ≤ t+f，单调 clamp 保序）。
        final f = ((bright.fontSize ?? 14) * 0.9 / w).clamp(0.0, 1.0);
        return Stack(
          // 辉光会画到文字盒子外，Stack 默认 Clip.hardEdge 会把它切掉
          clipBehavior: Clip.none,
          children: [
            Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
            ShaderMask(
              // dstIn：遮罩的 alpha 就是亮部的"不透明度"。
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                colors: const [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: [0.0, (t - f).clamp(0.0, 1.0), (t + f).clamp(0.0, 1.0), 1.0],
              ).createShader(r),
              child: Text.rich(
                TextSpan(text: text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bright,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 逐字高亮要的排版度量：[xs] 是每个字符**左边界**的 x 像素（长度
  /// `text.length + 1`），[width] 是整行排版宽度。
  ///
  /// 量一次缓存住：同一首歌里同一行的文字 / 字号 / 可用宽度都是不变的，
  /// 每帧变的只有播放位置。缓存在单槽 [_syllableMetric] 里——同时只有
  /// "正在唱的那一行"需要逐字动画，不会互相挤掉。
  ///
  /// 必须带 `maxWidth` 量：否则量出的是自然宽度，而实际渲染会被卡片宽度
  /// 截断成省略号，两者的坐标会错位，擦除边界会飘。
  ({List<double> xs, double width}) _syllableMetrics(
      String text, TextStyle style, double maxWidth) {
    final key = '$text|${style.fontSize}|${style.fontWeight}|'
        '${style.height}|${style.letterSpacing}|$maxWidth';
    final hit = _syllableMetric;
    if (hit != null && key == _syllableMetricKey) return hit;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final xs = <double>[
      for (var i = 0; i <= text.length; i++)
        tp.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx,
    ];
    final m = (xs: xs, width: tp.width);
    tp.dispose();
    _syllableMetricKey = key;
    _syllableMetric = m;
    return m;
  }

  ({List<double> xs, double width})? _syllableMetric;
  String _syllableMetricKey = '';

  Widget _lyricPlaceholder(Color fg) {
    final msg = _lyricState == 'loading' ? '正在找歌词…' : '没找到这首歌的歌词';
    return SizedBox(
      // 高度必须和真有歌词时一致（取景框高度），否则切歌时整块跳一下。
      height: _availHeight(),
      width: double.infinity,
      child: Center(
        child: Text(msg,
            style:
                TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.35))),
      ),
    );
  }

  /// 根入口：解析环境前景色（等价 NodeView 的 fg 下传），再按根 key
  /// （_viewKey，歌名|歌手）做整卡交叉淡入——与 NodeView 根节点的处理
  /// 同参数。字体红线：这里不给任何 Text 指定 fontFamily，全部继承
  /// 卡片环境的全局字体。
  Widget _root(int pos, int idx) {
    return Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
      final content = DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 13, decoration: TextDecoration.none),
        child: _content(pos, idx, fg),
      );
      if (!ctx.animate) return content;
      return AnimatedSwitcher(
        duration: kNodeAnimDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_viewKey), child: content),
      );
    });
  }

  /// 整卡内容（封面 + 控件 + 歌词区）。
  ///
  /// 名字不叫 `_view`：那已经是「渲染模型字段」的名字（`LyricsView? _view`），
  /// 同名的成员方法会和字段冲突。
  Widget _content(int pos, int idx, Color fg) {
    final media = _media;
    if (media == null || media['available'] != true) return _idleView(fg);

    final playing = media['status'] == 4;
    final dur = (media['duration'] as num?)?.toInt() ?? 0;

    final left = SizedBox(
      width: _artSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover('${media['artKey'] ?? ''}', fg),
          const SizedBox(height: _artGap),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${media['title'] ?? '未知曲目'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: fg.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '${media['artist'] ?? '未知艺术家'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ],
      ),
    );

    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconBtn('prev', _prev, _ctrlSide, media['canPrev'] == true, _ctrlBox),
        const SizedBox(width: 10),
        _iconBtn(
            playing ? 'pause' : 'play',
            _toggle,
            _ctrlMain,
            playing ? media['canPause'] == true : media['canPlay'] == true,
            _ctrlBox),
        const SizedBox(width: 10),
        _iconBtn('next', _next, _ctrlSide, media['canNext'] == true, _ctrlBox),
      ],
    );

    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PluginSlider(
          value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
          height: 3,
          color: Colors.white,
          background: const Color(0x33FFFFFF), // RRGGBBAA，alpha 在后
          // 播放器不支持定位时置灰
          enabled: media['canSeek'] == true && dur > 0,
          onChanged: _seekFraction,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Lrc.fmt(pos), style: _monoStyle(fg)),
            Text(Lrc.fmt(dur), style: _monoStyle(fg)),
          ],
        ),
      ],
    );

    // 撑满卡片高度，让 Expanded 有确定的高度预算（歌词区吃掉剩余部分）。
    final right = SizedBox(
      height: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          controls,
          const SizedBox(height: 6),
          bar,
          const SizedBox(height: 6),
          Expanded(
            // Listener(behavior: opaque) 而不是 Scrollable：歌词列是按当前
            // 行算位置的整列，滚轮只用来「往回看/往后看」，滚动位置由
            // _browseOffset 接管，停手 4 秒自动回到跟随当前行。
            child: _lines.isNotEmpty
                ? Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _onWheel,
                    child: _lyricArea(pos, idx, fg),
                  )
                : _lyricPlaceholder(fg),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(_pad),
      // 宽卡片：封面在左、歌词在右（横向并排）。
      // 窄卡片：改成上下堆叠——封面 + 曲目信息在上，控件与歌词在下。
      // 这是"容器宽度不足时像手机端那样从上到下依次堆叠"的直接落点：
      // 硬并排的话封面会吃掉大半宽度，右侧歌词只剩一条缝。
      child: _narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 窄模式下封面横过来放：封面 + 曲目文字一行，省地方
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: _artSize,
                      height: _artSize,
                      child: _cover('${media['artKey'] ?? ''}', fg),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${media['title'] ?? '未知曲目'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: fg.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${media['artist'] ?? '未知艺术家'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: fg.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: right),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(width: 14),
                Expanded(child: right),
              ],
            ),
    );
  }

  /// 封面：监听图片缓存版本号（解码完成时这一帧早就画过了，不重建就
  /// 永远是占位图），换歌时占位图 → 封面交叉淡入。
  Widget _cover(String key, Color fg) {
    return ValueListenableBuilder<int>(
      valueListenable: WidgetImages.revision,
      builder: (context, _, _) {
        final img = key.isEmpty ? null : WidgetImages.get(key);
        final Widget raw = img == null
            ? Container(
                width: _artSize,
                height: _artSize,
                color: const Color(0x14FFFFFF),
                alignment: Alignment.center,
                child: Icon(Icons.music_note_rounded,
                    size: _artSize * 0.32,
                    color: fg.withValues(alpha: 0.25)),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: RawImage(
                  image: img,
                  width: _artSize,
                  height: _artSize,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              );
        if (!ctx.animate) return raw;
        return AnimatedSwitcher(
          duration: kNodeAnimDuration,
          switchInCurve: kNodeAnimCurve,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (c, anim) =>
              FadeTransition(opacity: anim, child: c),
          child: KeyedSubtree(key: ValueKey(key), child: raw),
        );
      },
    );
  }

  Widget _iconBtn(
      String name, VoidCallback onTap, num size, bool enabled, num box) {
    final icon = NodeAnimatedColor(
      color: enabled ? Colors.white : const Color(0xFF7A7A7A),
      animate: ctx.animate,
      builder: (context, color) => MorphableIcon(
        name: name,
        size: size.toDouble(),
        color: color,
        animate: ctx.animate,
        fallback: iconDataFor(name),
      ),
    );
    final cell = SizedBox(
      width: box.toDouble(),
      height: box.toDouble(),
      child: Center(child: icon),
    );
    if (!enabled) return cell;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TapFeedback(animate: ctx.animate, onTap: onTap, child: cell),
    );
  }

  @override
  void mount() {
    _measure();
    _view = null;
    // 把歌词模块的网络/日志接到宿主（15s 超时、组件卸载自动取消、统一日志），
    // 一次即可；引擎里的各源 Api 都走这唯一的 httpClient 出口。
    installLyricsHost(ctx);
    ctx.renderWidget(_root(0, -1));
    _purgeLegacyCache();
    _tick();
    // 60ms 而不是 100ms：逐字动画的边界每个 tick 推 1/8 字，单字 500ms
    // 的歌里 100ms 只有 4 格，看着是"一顿一顿"而不是在动。60ms ≈ 16fps，
    // 够把连续推进抹平，又不至于把 native 采样压力翻倍（_tick 里每次都
    // await 一次 mediaState，那是跨进程调用）。真正的位置精度不靠这个
    // tick——[_nowPos] 每次都按本地流逝时间外推，所以采样间隔和位置
    // 精度是解耦的。
    ctx.interval(_tick, 60);
  }

  /// 按卡片尺寸算出所有界面度量（封面大小、字号、行高、窄卡判定）。
  ///
  /// 从 [mount] 里拆出来单独一个方法：这些量是**纯计算**的，谁先算都行。
  /// 之前只有 mount 会算，于是 [debugBuildFull]（不调 mount 的测试钩子）
  /// 构建出来的树里 `_artSize` 还是 `late` 未初始化，一 build 就炸——
  /// 测试根本进不到滚轮那一步，只能靠肉眼验证。拆开之后测试钩子自己
  /// 调一次，渲染路径和真机完全一致。
  void _measure() {
    _settings = Map<String, Object?>.from(ctx.settings);
    _w = ctx.size.width;
    _h = ctx.size.height;
    _accent = ctx.themeAccent ?? '#7CC7FF';

    // ---- 界面尺寸：按卡片高度缩放，小尺寸也不至于挤成一团 ----
    var artSize =
        min(_h - _pad * 2 - _textBlock - _artGap, (_w * 0.24).round());
    if (artSize < 52) artSize = 52;
    // 窄卡片（宽度不够横排）时把封面再收一档，并让封面列整体缩到 40%：
    // 否则「封面 + 14px 间隔 + 播放控件」这一横排会顶穿卡片。
    _narrow = _w < 300;
    if (_narrow) {
      artSize = min(artSize, 68);
      if (artSize < 44) artSize = 44;
    }
    _artSize = artSize.toDouble();

    final lyricSize =
        _h >= 380 ? 15.5 : (_h >= 260 ? 14.0 : 13.0);
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
    // 实际行高在 _lyricArea 里按「这首歌有没有译文」现算，
    // 这里先给单行值，保证 mount 阶段的行数预算有意义。
    _lineContext = _lineSingle;
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
  int get debugWindowBase => _windowBase;

  /// 第 [i] 句是否**完整落在取景框内**（也就是真的点得到）。
  ///
  /// 测试需要这个判定，但**不该自己从渲染树反推**：歌词区外层套了
  /// `ClipRect`，行堆又用 `OverflowBox` 放开高度，于是有一批行坐标还在
  /// 台面范围内、却被裁掉一截——tap 落在框外，表现为"点了没反应"。
  /// 从渲染树猜框高也会算错（行高是行间距，框高是整块区域，差一个量级）。
  /// 组件自己知道 [_windowBase]、行高和框高，直接算最可靠。
  @visibleForTesting
  bool debugLineFullyVisible(int i) {
    if (i < 0 || i >= _lines.length) return false;
    final rel = i - _windowBase;
    final rows = _availHeight() ~/ _lineContext;
    return rel >= 0 && rel < rows;
  }

  @visibleForTesting
  bool get debugHasTrans => _hasTrans;

  /// 滚轮浏览偏移（行）。0 = 正在自动跟随当前行。
  @visibleForTesting
  int get debugBrowseOffset => _browseOffset;

  /// 组件真正的重绘通道（`ctx.widget`），测试要监听它才能看到重绘结果。
  ///
  /// [_paint] 是写进这个 notifier 来重绘的，桌面宿主用
  /// `ValueListenableBuilder` 监听（见 `builtin_card_body.dart`）。测试如果
  /// 直接 pump 一棵静态树，重绘就进了没人监听的 notifier，看起来像"没反应"。
  @visibleForTesting
  ValueListenable<Widget?> get debugWidgetChannel => ctx.widget;

  /// 构建完整播放视图并**写进 ctx.widget**（走真实重绘通道）。
  ///
  /// 和 [debugBuildFull] 的区别：那个只是"返回一棵 Widget 给你自己 pump"，
  /// 适合截图；这个把 Widget 推进 notifier，之后 `_paint` 的重绘才能被看到。
  @visibleForTesting
  void debugPublishFull(int idx,
      {String title = '测试曲目', String artist = '测试歌手'}) {
    ctx.renderWidget(debugBuildFull(idx, title: title, artist: artist));
  }

  /// 滚轮浏览能走到的偏移范围 `[最小, 最大]`（相对跟随位置，可为负）。
  @visibleForTesting
  List<int> get debugBrowseRange => <int>[-_browseBase, _browseMax - _browseBase];

  /// 模拟一次滚轮。[dy] 用 Windows 的原始刻度：一格 = ±120。
  @visibleForTesting
  void debugWheel(double dy) {
    _onWheel(PointerScrollEvent(
        scrollDelta: Offset(0, dy), viewId: 0));
  }

  /// 滚轮小数余额（测试触控板细粒度滚动是否真的在累积）。
  @visibleForTesting
  double get debugWheelAccum => _wheelAccum;

  /// 推进"停手 [_browseHoldMs] 之后"的状态：让浏览过期回到跟随。
  @visibleForTesting
  void debugExpireBrowse() {
    _browseAtMs = 0;
    _paint(true);
  }

  /// 塞一段演示歌词（预览图生成 / 布局测试用）。
  ///
  /// 签名保持 `List<LrcLine>` 不变（`test/gen_previews_test.dart` 在用），
  /// 内部转成渲染模型：这些行没有逐字数据，所以画出来就是整行高亮。
  @visibleForTesting
  void debugSetLyrics(List<LrcLine> lines) {
    _view = LyricsView.fromSimpleLines([
      for (final l in lines) (start: l.t, text: l.s, trans: l.tr),
    ]);
    _lyricState = 'ok';
  }

  /// 当前歌词状态（idle | loading | ok | none）——测试断言"没歌词时确实
  /// 切到了 none"用。
  @visibleForTesting
  String get debugLyricState => _lyricState;

  /// 当前显示的歌词是按哪个 key 取到的（见 [_lyricKey]）。
  @visibleForTesting
  String get debugLyricKey => _lyricKey;

  /// 模拟"新曲目搜不到歌词"时的判定：按 [_isSameSong] 的规则决定是保留
  /// 旧歌词还是清空，返回是否保留。
  ///
  /// 单独暴露是为了能**直接测判据本身**——真去跑一次网络搜索既慢又不稳定
  /// （源时好时坏），而这里出错的代价是"屏幕上挂着上一首歌的词"。
  @visibleForTesting
  bool debugWouldKeepOnMiss(String newKey) =>
      _lyricKey.isNotEmpty && _isSameSong(_lyricKey, newKey);

  /// 设定"当前显示的歌词来自哪个 key"（[_lyricKey]），配合
  /// [debugWouldKeepOnMiss] 覆盖切歌的各种组合。
  @visibleForTesting
  void debugSetLyricKey(String key) => _lyricKey = key;

  /// 测试钩子：构建**完整的播放视图**（含封面/控制条/进度条/歌词区），
  /// 直接返回 Widget——测试自己 pump，完全不经过 ctx 通道。
  ///
  /// 相比旧的 debugPaintFull（往 ctx.render 里塞 JSON 树）少了一整类坑：
  /// 不再依赖"宿主监听 tree 重建"，快照反模式无从发生。
  ///
  /// 与真实渲染的差别只有两处，都是测试环境所必需的：
  ///   1. `_dead = true` 掐掉 _tick：测试里没有 native，定时采样会把
  ///      `_media` 清成 null，视图就退回 idle（曾因此量到 idle 的几何）。
  ///   2. `_media` 用假快照顶上，绕过 SMTC 空态检查。
  ///
  /// 只渲染歌词区（不带头部）的旧 debugPaint 已删：没有头部的树量出来
  /// 的坐标不反映真实布局（曾因此误判），统一用完整视图。
  @visibleForTesting
  Widget debugBuildFull(int idx,
      {String title = '测试曲目', String artist = '测试歌手'}) {
    // 尺寸度量必须自己算一遍：这些量原本只在 mount 里算，而这个钩子
    // 故意不调 mount（mount 会起定时采样、装网络宿主）。
    _measure();
    _dead = true;
    _media = {
      'available': true,
      'title': title,
      'artist': artist,
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
    return _root(idx * 1000, idx);
  }
}
