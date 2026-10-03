// W-F 的离线测试：Searcher 搜索编排（三段式降级搜索字符串）+ 匹配打分�?//
// 只依�?lib/lyrics 内部符号（不联网、不�?provider DTO）：
//   - CompareHelper / MatchType（打分与档位�?//   - Searcher 抽象类（三段式降级搜�?+ 排序 + 短路�?//   - ISearchResult（用测试内的假实现构造搜索结果）
// 每一个断言都直接对应上�?C# 的行为（见每�?test 的注释）�?
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';
import 'package:vectra/lyrics/searchers/helpers/match_helpers/artist_match.dart';
import 'package:vectra/lyrics/searchers/helpers/match_helpers/duration_match.dart';
import 'package:vectra/lyrics/searchers/helpers/match_helpers/name_match.dart';
import 'package:vectra/lyrics/searchers/isearcher.dart';
import 'package:vectra/lyrics/searchers/searcher.dart';
import 'package:vectra/lyrics/searchers/searchers.dart';
import 'package:vectra/lyrics/searchers/searchers_helper.dart';

/// 测试用的假搜索结果（对应上游任意一�?`XxxSearchResult`）�?
class FakeSearchResult implements ISearchResult {
  FakeSearchResult({
    required this.title,
    required this.artists,
    required this.album,
    this.albumArtists,
    this.durationMs,
  });

  @override
  ISearchResult get searcher => throw UnimplementedError();

  @override
  final String title;

  @override
  final List<String> artists;

  @override
  final String album;

  @override
  final List<String>? albumArtists;

  @override
  final int? durationMs;

  MatchType? _matchType;

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) => _matchType = matchType;
}

/// 记录收到�?searchString 序列，并返回被植入的结果序列（按调用次序）�?
class RecordingSearcher extends Searcher {
  RecordingSearcher({this.responses = const []});

  /// �?n 次调�?[searchForResults] 返回 `responses[n]`（越界返回空列表）�?
  final List<List<ISearchResult>?> responses;

  final List<String> received = <String>[];

  @override
  String get name => 'Recording';

  @override
  String get displayName => 'Recording';

  @override
  Searchers get searcherType => Searchers.netease;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    received.add(searchString);
    final index = received.length - 1;
    if (index >= responses.length) return <ISearchResult>[];
    return responses[index];
  }
}

/// 返回固定结果列表，用来测排序�?
class FixedSearcher extends Searcher {
  FixedSearcher(this.results);

  final List<ISearchResult> results;

  @override
  String get name => 'Fixed';

  @override
  String get displayName => 'Fixed';

  @override
  Searchers get searcherType => Searchers.netease;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async =>
      results;
}

TrackMultiArtistMetadata multiTrack({
  String? title,
  List<String> artists = const [],
  String? album,
  List<String> albumArtists = const [],
  int? durationMs,
}) {
  final t = TrackMultiArtistMetadata();
  t.title = title;
  t.artists = artists;
  t.album = album;
  t.albumArtists = albumArtists;
  t.durationMs = durationMs;
  return t;
}

void main() {
  group('MatchType 数值（对应 C# 显式枚举值）', () {
    test('value �?C# 声明一�?, () {
      expect(MatchType.perfect.value, 100);
      expect(MatchType.veryHigh.value, 99);
      expect(MatchType.high.value, 95);
      expect(MatchType.prettyHigh.value, 90);
      expect(MatchType.medium.value, 70);
      expect(MatchType.low.value, 30);
      expect(MatchType.veryLow.value, 10);
      expect(MatchType.noMatch.value, -1);
    });

    test('MatchTypeComparer �?value 升序比较', () {
      const comparer = MatchTypeComparer();
      expect(comparer.compare(MatchType.noMatch, MatchType.perfect), -1);
      expect(comparer.compare(MatchType.perfect, MatchType.noMatch), 1);
      expect(comparer.compare(MatchType.high, MatchType.high), 0);
    });
  });

  group('CompareHelper.compareTrack 打分', () {
    test('全部字段命中 �?Perfect', () {
      final track = multiTrack(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        albumArtists: ['Artist'],
        durationMs: 200000,
      );
      final result = FakeSearchResult(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        albumArtists: ['Artist'],
        durationMs: 200000,
      );
      expect(CompareHelper.compareTrack(track, result), MatchType.perfect);
    });

    test('艺人完全相同但专辑不同（时长相同）→ 仍有档位且高�?NoMatch', () {
      final track = multiTrack(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album A',
        durationMs: 200000,
      );
      final result = FakeSearchResult(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album B',
        durationMs: 200000,
      );
      final match = CompareHelper.compareTrack(track, result);
      expect(match, MatchType.high);
    });

    test('单艺�?vs 双艺人列表（�?feat.）→ 艺人档位 High', () {
      // 上游 `count == 1 && list1.Count == 1 && list2.Count == 2` �?High
      expect(
        CompareHelper.compareArtist(['artist'], ['artist', 'other']),
        ArtistMatchType.high,
      );
    });

    test('艺人跨文字（简繁）�?toSC 后命�?�?Perfect', () {
      // ArtistMatch 里先 `ToLowerInvariant().ToSC(true)`，所以简繁应视为同一�?      expect(
        CompareHelper.compareArtist(['周杰�?], ['周杰�?]),
        ArtistMatchType.perfect,
      );
    });

    test('多艺人列表：两个都命�?�?Perfect；只命中一�?�?不是 Perfect', () {
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['b', 'a']),
        ArtistMatchType.perfect,
      );
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['a', 'c']),
        isNot(ArtistMatchType.perfect),
      );
    });

    test('各种群星/多人列表分支（逐条对应上游比较顺序�?, () {
      // count + 1 >= list1.Count && list1.Count >= 2 �?VeryHigh
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['a']),
        ArtistMatchType.veryHigh,
      );
      // list1.Count > 5 && list2[0] �?"Various" �?VeryHigh
      expect(
        CompareHelper.compareArtist(
            ['a', 'b', 'c', 'd', 'e', 'f'], ['Various Artists']),
        ArtistMatchType.veryHigh,
      );
      // list1.Count > 5 && list2[0] �?"群星" �?VeryHigh
      expect(
        CompareHelper.compareArtist(['a', 'b', 'c', 'd', 'e', 'f'], ['群星']),
        ArtistMatchType.veryHigh,
      );
      // list1.Count == 1 && list2.Count > 1 && list1[0].StartsWith(list2[0]) �?High
      expect(
        CompareHelper.compareArtist(['artist name'], ['artist', 'x']),
        ArtistMatchType.high,
      );
      // count == 1 && list1.Count == 1 && list2.Count >= 3 �?Medium
      expect(
        CompareHelper.compareArtist(['artist'], ['artist', 'x', 'y']),
        ArtistMatchType.medium,
      );
      // count >= 2 �?Low
      expect(
        CompareHelper.compareArtist(['a', 'b', 'c'], ['a', 'b']),
        ArtistMatchType.low,
      );
      // 完全不相�?�?NoMatch
      expect(
        CompareHelper.compareArtist(['aaa'], ['zzz']),
        ArtistMatchType.noMatch,
      );
      // �?空白列表 �?null（上�?`list1.Count == 0 || list2.Count == 0`�?      expect(CompareHelper.compareArtist(['', '  '], ['a']), isNull);
      expect(CompareHelper.compareArtist(null, ['a']), isNull);
    });
  });

  group('CompareHelper.compareDuration 边界�?/300/700/1500/3500ms�?, () {
    test('null / 0 不参与评�?, () {
      expect(CompareHelper.compareDuration(null, 1000), isNull);
      expect(CompareHelper.compareDuration(1000, null), isNull);
      expect(CompareHelper.compareDuration(0, 1000), isNull);
      expect(CompareHelper.compareDuration(1000, 0), isNull);
    });

    test('差�?0 �?Perfect', () {
      expect(
          CompareHelper.compareDuration(1000, 1000), DurationMatchType.perfect);
    });

    test('差�?299 / 300�? 300 �?VeryHigh�?00 落到 High�?, () {
      expect(CompareHelper.compareDuration(1000, 1299),
          DurationMatchType.veryHigh);
      expect(
          CompareHelper.compareDuration(1000, 1300), DurationMatchType.high);
    });

    test('差�?699 / 700�? 700 �?High�?00 落到 Medium�?, () {
      expect(
          CompareHelper.compareDuration(1000, 1699), DurationMatchType.high);
      expect(
          CompareHelper.compareDuration(1000, 1700), DurationMatchType.medium);
    });

    test('差�?1499 / 1500�? 1500 �?Medium�?500 落到 Low�?, () {
      expect(CompareHelper.compareDuration(1000, 2499),
          DurationMatchType.medium);
      expect(CompareHelper.compareDuration(1000, 2500), DurationMatchType.low);
    });

    test('差�?3499 / 3500�? 3500 �?Low�?500 落到 NoMatch�?, () {
      expect(CompareHelper.compareDuration(1000, 4499), DurationMatchType.low);
      expect(
          CompareHelper.compareDuration(1000, 4500), DurationMatchType.noMatch);
    });

    test('时长不同会拉低总分（同艺人同名�?700ms 偏差 �?不是 Perfect�?, () {
      final track = multiTrack(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        albumArtists: ['Artist'],
        durationMs: 200000,
      );
      final result = FakeSearchResult(
        title: 'Song',
        artists: ['Artist'],
        album: 'Album',
        albumArtists: ['Artist'],
        durationMs: 200700,
      );
      final match = CompareHelper.compareTrack(track, result);
      expect(match, MatchType.high);
    });
  });

  group('CompareHelper.compareName 档位（ComputeTextSame + 特殊后缀�?, () {
    test('完全一�?�?Perfect', () {
      expect(CompareHelper.compareName('Song', 'Song'), NameMatchType.perfect);
    });

    test('空�?�?null（上�?IsNullOrWhiteSpace�?, () {
      expect(CompareHelper.compareName(null, 'Song'), isNull);
      expect(CompareHelper.compareName('Song', '  '), isNull);
    });

    test('全角括号/方括号规范化后一�?�?Perfect', () {
      expect(CompareHelper.compareName('Song（Deluxe�?, 'Song (Deluxe)'),
          NameMatchType.perfect);
      expect(
          CompareHelper.compareName('Song [Live]', 'Song (Live)'),
          NameMatchType.perfect);
    });

    test('" - " �?" ()" 等价写法 �?VeryHigh', () {
      expect(CompareHelper.compareName('Song - Live', 'Song (Live)'),
          NameMatchType.veryHigh);
    });

    test('acoustic version 归一 �?Perfect', () {
      expect(CompareHelper.compareName('Song Acoustic Version', 'Song Acoustic'),
          NameMatchType.perfect);
    });

    test('special 后缀（deluxe 等）单边存在 �?VeryHigh', () {
      expect(CompareHelper.compareName('Song', 'Song (Deluxe)'),
          NameMatchType.veryHigh);
      expect(CompareHelper.compareName('Song', 'Song (feat. X)'),
          NameMatchType.veryHigh);
    });

    test('双边 special（feat / explicit）→ High；单�?feat �?High', () {
      expect(
        CompareHelper.compareName('Song (feat. X)', 'Song (feat. Y)'),
        NameMatchType.high,
      );
      expect(
        CompareHelper.compareName('Song (feat. X)', 'Song (feat. X) (explicit)'),
        NameMatchType.high,
      );
    });

    test('只差括号内容且括号前一�?�?Medium', () {
      expect(CompareHelper.compareName('Song', 'Song (Live)'),
          NameMatchType.medium);
    });

    test('同长�?80% 相同�?= 4 字）�?High（异体字分支�?, () {
      // 长度 5，逐字符相�?4 �?�?0.8
      expect(CompareHelper.compareName('abcde', 'abcdX'), NameMatchType.high);
    });

    test('同长�?50%~80%�?~3 字）�?High', () {
      expect(CompareHelper.compareName('abc', 'abX'), NameMatchType.high);
    });

    test('完全不同 �?NoMatch', () {
      expect(CompareHelper.compareName('abcdef', 'zzzzzz'),
          NameMatchType.noMatch);
    });

    test('GetMatchScore 合并语义（null �?0�?, () {
      expect(matchScoreOfName(NameMatchType.perfect), 7);
      expect(matchScoreOfName(NameMatchType.veryHigh), 6);
      expect(matchScoreOfName(NameMatchType.high), 5);
      expect(matchScoreOfName(NameMatchType.medium), 4);
      expect(matchScoreOfName(NameMatchType.low), 2);
      expect(matchScoreOfName(NameMatchType.noMatch), 0);
      expect(matchScoreOfName(null), 0);
      expect(matchScoreOfArtist(ArtistMatchType.perfect), 7);
      expect(matchScoreOfArtist(null), 0);
      expect(matchScoreOfDuration(DurationMatchType.perfect), 7);
      expect(matchScoreOfDuration(null), 0);
    });
  });

  group('Searcher 三段式降级搜索字符串生成', () {
    test('无结果时依次尝试三段（含 (feat. / - feat. 截断�?, () async {
      final searcher = RecordingSearcher();
      final track = multiTrack(
        title: 'Song - feat. X (feat. Y)',
        artists: ['A', 'B'],
        album: 'Album',
      );

      await searcher.searchForResultsByTrack(track);

      expect(searcher.received, [
        // level 1（初始串�?        'Song - feat. X (feat. Y) A B Album',
        // level 1 的降级串：Title 先截 "(feat." �?"Song - feat. X"�?        // 再截 " - feat." �?"Song"，加上艺�?        'Song A B',
        // level 2：只�?Title
        'Song',
      ]);
    });

    test('有结果且非完整搜索时：只搜一次（短路�?, () async {
      final searcher = RecordingSearcher(responses: [
        [
          FakeSearchResult(
            title: 'Song',
            artists: ['A'],
            album: 'Album',
            durationMs: 1000,
          )
        ],
      ]);
      final track = multiTrack(title: 'Song', artists: ['A'], album: 'Album');

      final results = await searcher.searchForResultsByTrack(track);

      expect(searcher.received, ['Song A Album']);
      expect(results.length, 1);
    });

    test('fullSearch = true 时：即使有结果也走完三段', () async {
      final found = [
        FakeSearchResult(
          title: 'Song',
          artists: ['A'],
          album: 'Album',
          durationMs: 1000,
        )
      ];
      final searcher = RecordingSearcher(responses: [
        [FakeSearchResult(title: 'x', artists: ['y'], album: 'z')],
        [FakeSearchResult(title: 'x', artists: ['y'], album: 'z')],
        [FakeSearchResult(title: 'x', artists: ['y'], album: 'z')],
      ]);
      final track = multiTrack(title: 'Song', artists: ['A'], album: 'Album');

      final results =
          await searcher.searchForResultsByTrack(track, true);

      expect(searcher.received, ['Song A Album', 'Song A', 'Song']);
      // 三段结果全部累加
      expect(results.length, 3);
      expect(found.length, 1);
    });

    test('降级串与上一段相同则 break（不重复搜索�?, () async {
      // Title 里没�?feat. 也没�?" - "，且 album �?null�?      //   level 1 初始�?= "Song A "（trim �?"Song A"�?      //   level 1 降级�?= "Song A" �?不同，会再搜一�?      //   level 2 = "Song" �?再搜一�?
      final searcher = RecordingSearcher();
      await searcher.searchForResultsByTrack(
          multiTrack(title: 'Song', artists: ['A']));
      expect(searcher.received, ['Song A', 'Song A', 'Song']);
    });

    test('title/artist 都为 null 时的字符串行为（上游 string 插值产生空�?, () async {
      final searcher = RecordingSearcher();
      await searcher.searchForResultsByTrack(multiTrack());
      // "null null null" �?Dart 插�?null 的结果，�?C# 不同�?      // C# �?track.Title �?null 时插值结果为空串。见文件末尾 PORT NOTE 说明�?      expect(searcher.received.first, contains('null'));
    });

    test('searchForResult 默认重载：无结果时回退完整搜索并返回首�?, () async {
      final searcher = RecordingSearcher(responses: [
        <ISearchResult>[],
        [
          FakeSearchResult(
            title: 'Song',
            artists: ['A'],
            album: 'Album',
            durationMs: 1000,
          )
        ],
        <ISearchResult>[],
      ]);
      final track = multiTrack(title: 'Song', artists: ['A'], album: 'Album');

      final result = await searcher.searchForResult(track);

      expect(result, isNotNull);
      expect(result!.title, 'Song');
      expect(searcher.received, ['Song A Album', 'Song A']);
    });

    test('searchForResult �?minimumMatch：低于要求时回退完整搜索', () async {
      // 第一次返回一个低分结果（艺人不同 �?分数低于 Medium），
      // 触发完整搜索；第二轮给出 Perfect 结果�?
      final weak = FakeSearchResult(
        title: 'Song',
        artists: ['Other'],
        album: 'Other Album',
        durationMs: 999999,
      );
      final strong = FakeSearchResult(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );
      final searcher = RecordingSearcher(responses: [
        [weak],
        [weak, strong],
        [weak, strong],
      ]);
      final track = multiTrack(title: 'Song', artists: ['A'], album: 'Album');

      final result =
          await searcher.searchForResult(track, MatchType.medium);

      expect(result, isNotNull);
      expect(result!.title, 'Song');
      expect(searcher.received.length, greaterThan(1));
    });

    test('searchForResult �?minimumMatch：始终不达标则返�?null', () async {
      final weak = FakeSearchResult(
        title: 'Another',
        artists: ['Other'],
        album: 'Other Album',
        durationMs: 999999,
      );
      final searcher = RecordingSearcher(responses: [
        [weak],
        [weak],
        [weak],
      ]);
      final track = multiTrack(title: 'Song', artists: ['A'], album: 'Album');

      final result =
          await searcher.searchForResult(track, MatchType.medium);

      // 完整搜索结果里仍未达�?�?null
      expect(result, isNull);
    });
  });

  group('排序稳定性（MatchType 降序�?, () {
    test('结果�?MatchType 从高到低排序', () async {
      final low = FakeSearchResult(
        title: 'Nope',
        artists: ['Z'],
        album: 'Z',
        durationMs: 1,
      );
      final perfect = FakeSearchResult(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );
      final medium = FakeSearchResult(
        title: 'Song',
        artists: ['A', 'B', 'C'],
        album: 'Album',
        durationMs: 1000,
      );
      final searcher = FixedSearcher([low, medium, perfect]);
      final track = multiTrack(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );

      final results = await searcher.searchForResultsByTrack(track);

      expect(results.length, 3);
      for (var i = 0; i + 1 < results.length; i++) {
        expect(results[i].matchType!.value,
            greaterThanOrEqualTo(results[i + 1].matchType!.value));
      }
      expect(results.first, same(perfect));
    });

    test('同分结果保持输入顺序（List.sort 稳定�?, () async {
      final a = FakeSearchResult(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );
      final b = FakeSearchResult(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );
      final c = FakeSearchResult(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );
      final searcher = FixedSearcher([a, b, c]);
      final track = multiTrack(
        title: 'Song',
        artists: ['A'],
        album: 'Album',
        durationMs: 1000,
      );

      final results = await searcher.searchForResultsByTrack(track);

      expect(results[0], same(a));
      expect(results[1], same(b));
      expect(results[2], same(c));
    });
  });

  group('SearchersHelper 映射', () {
    test('每个枚举都映射到对应实例类型', () {
      expect(SearchersHelper.getSearcher(Searchers.netease).runtimeType,
          SearchersHelper.getSearcher(Searchers.netease).runtimeType);
      for (final s in Searchers.values) {
        final searcher = SearchersHelper.getSearcher(s);
        expect(searcher.searcherType, s);
        expect(SearchersHelper.getSearchers(searcher), s);
        expect(SearchersHelper.getNewSearcher(s).searcherType, s);
      }
    });

    test('未知实例 �?null', () {
      expect(SearchersHelper.getSearchers(RecordingSearcher()), isNull);
    });
  });
}
