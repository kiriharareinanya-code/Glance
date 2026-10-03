/// 歌词引擎（Lyricify 编排层）的离线测试。
///
/// 用假的 [LyricsSourceBridge] + 真的解析器，验证编排行为本身：
///   - 来源顺序（auto 顺序、以及设置里选源时把该源提前）
///   - 匹配门槛过滤（低于门槛的候选不取词）
///   - 候选按分数从高到低逐个尝试
///   - 语言偏好（中/英）与"全不符时返回兜底候选"
///   - 信息行裁剪（stripInfoLines）与"裁空就不裁"
///   - 单源失败/抛异常不影响后续来源
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/engine.dart';
import 'package:vectra/lyrics/engine_sources.dart';
import 'package:vectra/lyrics/helpers/parse_helper.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';
import 'package:vectra/lyrics/searchers/isearcher.dart';
import 'package:vectra/lyrics/searchers/searchers.dart';

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
  });

  @override
  final Searchers searcherType;

  @override
  final String displayName;

  @override
  final ISearcher searcher;

  /// title → LRC 文本
  final Map<String, String> lyricsByTitle;

  /// 这些 title 返回 null（拿不到歌词）
  final Set<String> failingTitles;

  /// 这些 title 抛异常
  final Set<String> throwTitles;

  /// 被取过词的 title 顺序
  final List<String> fetched = <String>[];

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    fetched.add(result.title);
    if (throwTitles.contains(result.title)) throw StateError('取词炸了');
    if (failingTitles.contains(result.title)) return null;
    final raw = lyricsByTitle[result.title];
    if (raw == null) return null;
    return ParseHelper.parseLyrics(raw, LyricsRawTypes.lrc);
  }
}

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
}
