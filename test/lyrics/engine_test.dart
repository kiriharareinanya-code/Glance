/// 歌词引擎（Lyricify 编排层）的离线测试。
///
/// 用假的 [LyricsSourceBridge] + 真的解析器，验证编排行为本身：
///   - 来源顺序（auto 顺序、以及设置里选源时把该源提前）
///   - 匹配门槛过滤（低于门槛的候选不取词）
///   - 候选按分数从高到低逐个尝试
///   - 语言偏好（中/英）与"全不符时返回兜底候选"
///   - 信息行裁剪（stripInfoLines）与"裁空就不裁"
///   - 单源失败/抛异常不影响后续来源
///   - **逐字格式（YRC）在管线出口降级成纯文本行**（砍掉逐字功能后新增）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/engine.dart';
import 'package:vectra/lyrics/engine_sources.dart';
import 'package:vectra/lyrics/helpers/parse_helper.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';
import 'package:vectra/lyrics/searchers/isearcher.dart';
import 'package:vectra/lyrics/searchers/searchers.dart';
import 'package:vectra/widgets/lyrics_view.dart';

/// 一个可控的假 Searcher：返回预先排好序（或故意乱序）的候选列表。
class _FakeSearcher implements ISearcher {
  _FakeSearcher(this._results, {this.throwOnSearch = false});

  final List<ISearchResult> _results;
  final bool throwOnSearch;

  /// 记录收到的搜索字符串（验证引擎不会自己拼搜索串，交给 Searcher）
  final List<String> seen = <String>[];

  @override
  String get name => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  Searchers get searcherType => Searchers.netease;

  @override
  Future<ISearchResult?> searchForResult(TrackMetadata track,
          [MatchType? minimumMatch]) async =>
      _results.isEmpty ? null : _results.first;

  @override
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]) async {
    seen.add('${track.title}|${track.artist}');
    if (throwOnSearch) throw StateError('搜索炸了');
    return _results;
  }

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async =>
      _results;
}

/// 假搜索结果。
class _FakeResult implements ISearchResult {
  _FakeResult(this.title, this.artists, this.durationMs, this._matchType);

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final int? durationMs;

  final MatchType _matchType;

  @override
  String get album => '';

  @override
  List<String>? get albumArtists => null;

  // ISearchResult 给了这两个的默认实现，但 implements 不继承默认实现，
  // 必须显式写出来。
  @override
  String get artist => artists.join(', ');

  @override
  String get albumArtist => (albumArtists ?? const <String>[]).join(', ');

  @override
  ISearcher get searcher => _FakeSearcher(const []);

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) {}
}

/// 假 bridge：按 title 查表返回歌词，或返回 null / 抛异常。
class _FakeBridge implements LyricsSourceBridge {
  _FakeBridge({
    required this.searcherType,
    required this.displayName,
    required this.searcher,
    this.lyricsByTitle = const {},
    this.failingTitles = const {},
    this.throwTitles = const {},
    this.rawType,
  });

  @override
  final Searchers searcherType;

  @override
  final String displayName;

  @override
  final ISearcher searcher;

  /// title → 歌词原文
  final Map<String, String> lyricsByTitle;

  /// 这些 title 返回 null（拿不到歌词）
  final Set<String> failingTitles;

  /// 这些 title 抛异常
  final Set<String> throwTitles;

  /// 按哪种格式解析 [lyricsByTitle] 里的原文。null = 交给类型检测。
  ///
  /// 逐字格式（YRC/KRC/QRC/TTML）必须显式指定：它们的原文长得跟 LRC
  /// 完全不像，自动检测在合成的短样本上未必认得出来。
  final LyricsRawTypes? rawType;

  /// 被取过词的 title 顺序
  final List<String> fetched = <String>[];

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    fetched.add(result.title);
    if (throwTitles.contains(result.title)) throw StateError('取词炸了');
    if (failingTitles.contains(result.title)) return null;
    final raw = lyricsByTitle[result.title];
    if (raw == null) return null;
    return ParseHelper.parseLyrics(raw, rawType);
  }
}

/// 逐字格式的 YRC 原文（每行若干音节，音节带起止时间）。
///
/// 抄自真实网易云 YRC：`[行起点,行终点](音节起点,音节时长,0)文本`。
/// 解析出来的行是 `SyllableLineInfo`，行文本和行时间**全靠音节累积**——
/// 所以砍掉逐字功能后，这些行必须先被降级成纯文本行才对。
const _yrcSyllable = '''
[0,2000](0,500,0)你(500,500,0)好(1000,500,0)世(1500,500,0)界
[2000,4000](2000,1000,0)第二行歌词
[4000,6000](4000,1000,0)第三行歌词
[6000,8000](6000,1000,0)第四行歌词
''';


const _lrcZh = '''
[ti:测试]
[ar:某人]
[00:01.00]第一句中文歌词
[00:03.00]第二句中文歌词
[00:05.00]第三句中文歌词
[00:07.00]第四句中文歌词
''';

const _lrcEn = '''
[00:01.00]the first english line
[00:03.00]the second english line
[00:05.00]the third english line
[00:07.00]the fourth english line
''';

/// 带制作名单头部的 LRC（验证 InfoLines 裁剪）
const _lrcWithCredits = '''
[00:01.00]作词 : 某人
[00:02.00]作曲 : 某人
[00:03.00]第一句
[00:04.00]第二句
[00:05.00]第三句
[00:06.00]第四句
[00:07.00]第五句
''';

void main() {
  LyricsEngine engineWith(List<LyricsSourceBridge> bridges) =>
      LyricsEngine(bridges: bridges);

  test('auto：按来源顺序找，第一个命中的就返回', () async {
    final b1 = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'歌': _lrcZh},
    );
    final b2 = _FakeBridge(
      searcherType: Searchers.qqMusic,
      displayName: 'QQ',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'歌': _lrcEn},
    );

    final out = await engineWith([b1, b2]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out, isNotNull);
    expect(out!.source, Searchers.netease);
    expect(out.sourceName, 'Netease');
    expect(b2.fetched, isEmpty, reason: '第一个源命中后不该再问第二个源');
    expect(out.lines.length, 4);
  });

  test('设置里选源时，该源被提到最前，其余仍按默认顺序跟随', () async {
    final netease = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher(const []),
    );
    final qq = _FakeBridge(
      searcherType: Searchers.qqMusic,
      displayName: 'QQ',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'歌': _lrcZh},
    );

    final out = await engineWith([netease, qq]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
      sourcePreference: 'qq',
    );

    expect(out?.source, Searchers.qqMusic);
  });

  test('匹配门槛：低于门槛的候选一个都不取词', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('别的歌', ['别人'], 8000, MatchType.noMatch),
      ]),
      lyricsByTitle: {'别的歌': _lrcZh},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out, isNull);
    expect(bridge.fetched, isEmpty);
  });

  test('候选逐个尝试：前一个取不到就换下一个（按分数从高到低）', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('首选', ['某人'], 8000, MatchType.perfect),
        _FakeResult('次选', ['某人'], 8000, MatchType.high),
      ]),
      lyricsByTitle: {'次选': _lrcZh},
      failingTitles: {'首选'},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out?.searchResult.title, '次选');
    expect(bridge.fetched, ['首选', '次选']);
  });

  test('语言偏好：中文偏好会跳过英文歌词，返回中文候选', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('英文版', ['某人'], 8000, MatchType.perfect),
        _FakeResult('中文版', ['某人'], 8000, MatchType.high),
      ]),
      lyricsByTitle: {'英文版': _lrcEn, '中文版': _lrcZh},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
      preferLang: 'zh',
    );

    expect(out?.searchResult.title, '中文版');
    expect(bridge.fetched, ['英文版', '中文版']);
  });

  test('语言偏好：全都不符时返回兜底候选（不要没歌词）', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('英文版', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'英文版': _lrcEn},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
      preferLang: 'zh',
    );

    expect(out, isNotNull);
    expect(out!.searchResult.title, '英文版');
  });


  test('信息行：stripInfoLines=false 时原样保留', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'歌': _lrcWithCredits},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
      stripInfoLines: false,
    );

    expect(out!.lines.any((l) => l.text.contains('作词')), isTrue);
  });

  test('单源失败（抛异常）不影响后续来源', () async {
    final broken = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher(const [], throwOnSearch: true),
    );
    final ok = _FakeBridge(
      searcherType: Searchers.kugou,
      displayName: 'Kugou',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      lyricsByTitle: {'歌': _lrcZh},
    );

    final out = await engineWith([broken, ok]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out?.source, Searchers.kugou);
  });

  test('取词抛异常也不影响同一个源的下一个候选', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('炸的', ['某人'], 8000, MatchType.perfect),
        _FakeResult('好的', ['某人'], 8000, MatchType.high),
      ]),
      lyricsByTitle: {'好的': _lrcZh},
      throwTitles: {'炸的'},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out?.searchResult.title, '好的');
  });

  test('全都不行返回 null（宁可没找到，也不贴错词）', () async {
    final bridge = _FakeBridge(
      searcherType: Searchers.netease,
      displayName: 'Netease',
      searcher: _FakeSearcher([
        _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
      ]),
      failingTitles: {'歌'},
    );

    final out = await engineWith([bridge]).fetch(
      title: '歌',
      artist: '某人',
      durationMs: 8000,
    );

    expect(out, isNull);
  });

  group('逐字格式降级（砍掉逐字后新增）', () {
    // 这一组锁的是"砍逐字"这件事在数据侧的收口：YRC/KRC/QRC/TTML 仍要
    // 解析（行文本和行时间是从音节累积来的），但**出引擎时必须已经是纯
    // 文本行**。以前渲染层靠 `isSyllable` 分支画卡拉OK擦除，现在那个分支
    // 没了——漏掉降级的后果不是报错，而是歌词变成音节碎片拼的怪字符串，
    // 或者行时间变成 0（音节行降级前 startTime/endTime 依赖 refreshProperties
    // 被正确调用过），所以必须在管线出口就钉住。

    test('YRC 进、纯文本行出：文本与行时间都从音节累积而来', () async {
      final bridge = _FakeBridge(
        searcherType: Searchers.netease,
        displayName: 'Netease',
        searcher: _FakeSearcher([
          _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
        ]),
        lyricsByTitle: {'歌': _yrcSyllable},
        rawType: LyricsRawTypes.yrc,
      );

      final out = await engineWith([bridge]).fetch(
        title: '歌',
        artist: '某人',
        durationMs: 8000,
      );

      expect(out, isNotNull);
      final lines = out!.data.lines!;
      // 一行都不能是音节行了。
      expect(lines.whereType<SyllableLineInfo>(), isEmpty,
          reason: '出引擎时必须已降级；漏掉的话渲染层会拿到音节行');
      // 文本是**音节拼起来的完整句子**，不是碎片。
      expect(lines.first.text, '你好世界');
      // 行时间来自「第一个音节的起点 ~ 最后一个音节的终点」。
      expect(lines.first.startTime, 0);
      expect(lines.first.endTime, 2000);
      expect(lines[1].text, '第二行歌词');
      expect(lines[1].startTime, 2000);
      // 行终点取**最后一个音节的终点**（= 音节起点 + 音节时长），不是
      // YRC 行头里的第二个数。行头 `[2000,4000]` 的 4000 是"这行到什么时候
      // 完"，而音节表 `(2000,1000,0)` 自己算出的终点是 3000——两者不等，
      // 上游取的确实是后者（`SyncDowngrade.cs` 用 `syllables.Last().EndTime`）。
      expect(lines[1].endTime, 3000);
      // 同步类型不许再自称逐字（否则缓存里的 sync 字段会撒谎）。
      expect(out.data.file!.syncTypes, SyncTypes.lineSynced);
    });

    test('降级是幂等的：已经是文本行时原样通过（LRC 不受影响）', () async {
      final bridge = _FakeBridge(
        searcherType: Searchers.netease,
        displayName: 'Netease',
        searcher: _FakeSearcher([
          _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
        ]),
        lyricsByTitle: {'歌': _lrcZh},
        rawType: LyricsRawTypes.lrc,
      );

      final out = await engineWith([bridge]).fetch(
        title: '歌',
        artist: '某人',
        durationMs: 8000,
      );

      expect(out, isNotNull);
      final lines = out!.data.lines!;
      expect(lines.first.text, '第一句中文歌词');
      expect(lines.first.startTime, 1000);
      // LRC 格式本身没有行终点，所以 endTime 是 null。降级必须**原样放过**
      // 文本行（幂等），不能顺手补一个 0 或别的值——那会让
      // `LyricsLine.progressAt` 的零长行分支被误触发。
      expect(lines.first.endTime, isNull);
      expect(out.data.file!.syncTypes, SyncTypes.lineSynced);
    });

    test('降级后仍能正常转成渲染模型（不留音节概念）', () async {
      final bridge = _FakeBridge(
        searcherType: Searchers.netease,
        displayName: 'Netease',
        searcher: _FakeSearcher([
          _FakeResult('歌', ['某人'], 8000, MatchType.perfect),
        ]),
        lyricsByTitle: {'歌': _yrcSyllable},
        rawType: LyricsRawTypes.yrc,
      );

      final out = await engineWith([bridge]).fetch(
        title: '歌',
        artist: '某人',
        durationMs: 8000,
      );

      final view = LyricsView.fromData(out!.data, sourceName: 'Netease');
      expect(view.lines.first.text, '你好世界');
      expect(view.lines.first.start, 0);
      expect(view.lines.first.end, 2000);
      expect(view.indexAt(0), 0);
      expect(view.indexAt(2500), 1);
    });
  });
}
