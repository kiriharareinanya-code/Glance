// W-F 的离线测试：Searcher 搜索编排（三段式降级搜索字符串）+ 匹配打分。
//
// 只依赖 lib/lyrics 内部符号（不联网、不碰 provider DTO）：
//   - CompareHelper / MatchType（打分与档位）
//   - Searcher 抽象类（三段式降级搜索 + 排序 + 短路）
//   - ISearchResult（用测试内的假实现构造搜索结果）
// 每一个断言都直接对应上游 C# 的行为（见每个 test 的注释）。
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

/// 测试用的假搜索结果（对应上游任意一个 `XxxSearchResult`）。
class FakeSearchResult implements ISearchResult {
  FakeSearchResult({
    required this.title,
    required this.artists,
    required this.album,
    this.albumArtists,
    this.durationMs,
  });

  @override
  ISearcher get searcher => throw UnimplementedError();

  @override
  final String title;

  @override
  final List<String> artists;

  // ISearchResult.dart:16 的默认实现，这里照抄（`implements` 不会继承默认实现）。
  @override
  String get artist => artists.join(', ');

  @override
  final String album;

  @override
  final List<String>? albumArtists;

  // ISearchResult.dart:23 的默认实现。
  @override
  String get albumArtist => (albumArtists ?? <String>[]).join(', ');

  @override
  final int? durationMs;

  MatchType? _matchType;

  @override
  MatchType? get matchType => _matchType;

  @override
  void setMatchType(MatchType? matchType) => _matchType = matchType;
}

/// 记录收到的 searchString 序列，并返回被植入的结果序列（按调用次序）。
class RecordingSearcher extends Searcher {
  RecordingSearcher({this.responses = const []});

  /// 第 n 次调用 [searchForResults] 返回 `responses[n]`（越界返回空列表）。
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

/// 返回固定结果列表，用来测排序。
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
    // 上游 CompareHelper.cs:63-73 的 `enum MatchType` 显式赋值。
    test('value 与 C# 声明一致', () {
      expect(MatchType.perfect.value, 100);
      expect(MatchType.veryHigh.value, 99);
      expect(MatchType.high.value, 95);
      expect(MatchType.prettyHigh.value, 90);
      expect(MatchType.medium.value, 70);
      expect(MatchType.low.value, 30);
      expect(MatchType.veryLow.value, 10);
      expect(MatchType.noMatch.value, -1);
    });

    // 上游 CompareHelper.cs:76-82 的 `MatchTypeComparer.Compare` 就是枚举值升序。
    test('MatchTypeComparer 按 value 升序比较', () {
      const comparer = MatchTypeComparer();
      expect(comparer.compare(MatchType.noMatch, MatchType.perfect), -1);
      expect(comparer.compare(MatchType.perfect, MatchType.noMatch), 1);
      expect(comparer.compare(MatchType.high, MatchType.high), 0);
    });
  });

  group('CompareHelper.compareTrack 打分', () {
    // 上游 CompareHelper.cs:24-58：全命中 7 + 7 + 7*0.4 + 7*0.2 + 7 = 25.2，
    // fullScore / availableScore 归一系数为 25.2 / 25.2 = 1，25.2 > 21 → Perfect。
    test('全部字段命中 → Perfect', () {
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

    // 上游 CompareHelper.cs:26-45：只有专辑对不上。
    //   名称 7 + 艺人 7 + 专辑 High(5)*0.4 + 专辑艺人缺省 0 + 时长 7 = 23；
    //   availableScore = 14 + 2.8 + 7 = 23.8（专辑艺人匹配为 null，不参与分配），
    //   归一后 23 * 25.2 / 23.8 = 24.35，仍 > 21 → Perfect（CompareHelper.cs:49）。
    test('艺人完全相同但专辑不同（时长相同）→ 仍有档位且高于 NoMatch', () {
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
      expect(match, MatchType.perfect);
    });

    test('单艺人 vs 双艺人列表（含 feat.）→ 艺人档位 High', () {
      // 上游 ArtistMatch.cs:38 `count == 1 && list1.Count == 1 && list2.Count == 2` → High
      expect(
        CompareHelper.compareArtist(['artist'], ['artist', 'other']),
        ArtistMatchType.high,
      );
    });

    // ---- 时长否决闸（上游没有，为修用户实拍问题加的）----
    //
    // 用户实拍《阳光下的星星》（真 207.8s）只看到开头几行，日志显示
    // 「命中：时长差 75.7s 匹配 prettyHigh 共 45 行」。原因见
    // `CompareHelper.compareTrackMultiArtist` 里的说明：时长分被归一化稀释，
    // 标题 7 + 歌手 7 就够判 Perfect/prettyHigh，门槛是 medium，于是照样取词。
    // 后果是歌词时间戳全在 4 分钟之后，而歌只有 3:52。
    test('时长差极大但标题歌手全对 → 直接 NoMatch（不能只看标题）', () {
      final track = multiTrack(
        title: '阳光下的星星',
        artists: ['金海心'],
        durationMs: 207814,
      );
      // 时长差 36% / 39%：同名不同曲（现场版、剪辑版）。
      for (final wrong in [283514, 126714, 130000]) {
        final result = FakeSearchResult(
          title: '阳光下的星星',
          artists: ['金海心'],
          album: '',
          albumArtists: null,
          durationMs: wrong,
        );
        expect(
          CompareHelper.compareTrack(track, result),
          MatchType.noMatch,
          reason: '候选时长 $wrong 与真值 207814 差太多，不该进候选池',
        );
      }
    });

    test('时长在正常版本差异范围内 → 不受否决闸影响', () {
      final track = multiTrack(
        title: '阳光下的星星',
        artists: ['金海心'],
        durationMs: 207814,
      );
      // +9.6% / +19.2%：加长 intro、现场版都属正常，仍该进候选池。
      for (final ok in [227814, 247814]) {
        final result = FakeSearchResult(
          title: '阳光下的星星',
          artists: ['金海心'],
          album: '',
          albumArtists: null,
          durationMs: ok,
        );
        expect(
          CompareHelper.compareTrack(track, result),
          isNot(MatchType.noMatch),
          reason: '候选时长 $ok 只差 20~40 秒，是正常的版本差异，不该被否',
        );
      }
    });

    test('阈值用相对比例：长歌差同样秒数占比小，不该被否', () {
      // 8 分钟的歌差 40 秒 = 8%，远小于 25%。
      final track = multiTrack(
        title: 'Long',
        artists: ['A'],
        durationMs: 480000,
      );
      final result = FakeSearchResult(
        title: 'Long',
        artists: ['A'],
        album: '',
        albumArtists: null,
        durationMs: 520000,
      );
      expect(CompareHelper.compareTrack(track, result), isNot(MatchType.noMatch));
    });

    test('时长缺失（null）时不启用否决闸', () {
      // 很多源不返回时长，这时候只能靠标题歌手判断，不能因为拿不到时长
      // 就把候选全否掉——那会导致"所有源都没有歌词"。
      final track = multiTrack(
        title: 'Song',
        artists: ['Artist'],
        durationMs: 207814,
      );
      final result = FakeSearchResult(
        title: 'Song',
        artists: ['Artist'],
        album: '',
        albumArtists: null,
        durationMs: null,
      );
      expect(CompareHelper.compareTrack(track, result), isNot(MatchType.noMatch));
    });

    test('艺人跨文字（简繁）→ toSC 后命中 → Perfect', () {
      // ArtistMatch 里先 `ToLowerInvariant().ToSC(true)`（上游 ArtistMatch.cs:22-25），
      // 所以简繁应视为同一个。
      expect(
        CompareHelper.compareArtist(['周杰倫'], ['周杰伦']),
        ArtistMatchType.perfect,
      );
    });

    test('多艺人列表：两个都命中 → Perfect；只命中一个 → 不是 Perfect', () {
      // 上游 ArtistMatch.cs:32-33：`count == list1.Count && list1.Count == list2.Count` → Perfect
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['b', 'a']),
        ArtistMatchType.perfect,
      );
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['a', 'c']),
        isNot(ArtistMatchType.perfect),
      );
    });

    test('各种群星/多人列表分支（逐条对应上游比较顺序）', () {
      // 上游 ArtistMatch.cs:35 `count + 1 >= list1.Count && list1.Count >= 2` → VeryHigh
      expect(
        CompareHelper.compareArtist(['a', 'b'], ['a']),
        ArtistMatchType.veryHigh,
      );
      // 上游 ArtistMatch.cs:41 `list1.Count > 5 && (list2[0].Contains("Various")
      // || list2[0].Contains("群星"))` → VeryHigh。
      // 注意 list2 在 ArtistMatch.cs:24-25 已经被 `ToLowerInvariant().ToSC(true)`
      // 转成小写，而 C# 的 `string.Contains` 是**区分大小写**的序数比较，
      // 所以 `"Various Artists"` 里的 `Contains("Various")` 永远不成立，
      // 这条输入在上游同样是 NoMatch（下面的 `群星` 才真的命中该分支）。
      expect(
        CompareHelper.compareArtist(
            ['a', 'b', 'c', 'd', 'e', 'f'], ['Various Artists']),
        ArtistMatchType.noMatch,
      );
      // 上游 ArtistMatch.cs:41 的另一半：中文 `群星` 不受 ToLowerInvariant 影响。
      expect(
        CompareHelper.compareArtist(['a', 'b', 'c', 'd', 'e', 'f'], ['群星']),
        ArtistMatchType.veryHigh,
      );
      // 上游 ArtistMatch.cs:38 `count == 1 && list1.Count == 1 && list2.Count == 2` → High
      expect(
        CompareHelper.compareArtist(['artist name'], ['artist', 'x']),
        ArtistMatchType.high,
      );
      // 上游 ArtistMatch.cs:47 `list1.Count == 1 && list2.Count > 1 &&
      // list1[0].StartsWith(list2[0])` → High。
      // 它排在 ArtistMatch.cs:56（`count == 1 && list1.Count == 1 &&
      // list2.Count >= 3` → Medium）之前，所以 ['artist'] vs ['artist','x','y']
      // 命中的是 High，而不是 Medium。
      expect(
        CompareHelper.compareArtist(['artist'], ['artist', 'x', 'y']),
        ArtistMatchType.high,
      );
      // 上游 ArtistMatch.cs:56 的 Medium 分支：需要 list2[0] 既不是 list1[0] 的前缀、
      // 也不是它的子串，ArtistMatch.cs:47/50/53 才不会被抢先命中。
      expect(
        CompareHelper.compareArtist(['xyz'], ['a', 'b', 'xyz']),
        ArtistMatchType.medium,
      );
      // 上游 ArtistMatch.cs:35 `count + 1 >= list1.Count`（3 >= 3）对
      // ['a','b','c'] vs ['a','b'] 已经成立，所以先落到 VeryHigh，
      // 而不是 ArtistMatch.cs:59 `count >= 2` 的 Low。
      expect(
        CompareHelper.compareArtist(['a', 'b', 'c'], ['a', 'b']),
        ArtistMatchType.veryHigh,
      );
      // 上游 ArtistMatch.cs:59 `count >= 2` → Low：list1 有 5 个时 count + 1 = 3 < 5，
      // 上面几条分支都不成立，才轮得到这里。
      expect(
        CompareHelper.compareArtist(['a', 'b', 'c', 'd', 'e'], ['a', 'b']),
        ArtistMatchType.low,
      );
      // 完全不相关 → NoMatch（上游 ArtistMatch.cs:62）
      expect(
        CompareHelper.compareArtist(['aaa'], ['zzz']),
        ArtistMatchType.noMatch,
      );
      // 全空白列表 → null（上游 ArtistMatch.cs:19
      // `if (list1.Count == 0 || list2.Count == 0) return null`）
      expect(CompareHelper.compareArtist(['', '  '], ['a']), isNull);
      expect(CompareHelper.compareArtist(null, ['a']), isNull);
    });
  });

  group('CompareHelper.compareDuration 边界（0/300/700/1500/3500ms）', () {
    // 上游 DurationMatch.cs:13：任一为 null 或 0 就返回 null
    test('null / 0 不参与评分', () {
      expect(CompareHelper.compareDuration(null, 1000), isNull);
      expect(CompareHelper.compareDuration(1000, null), isNull);
      expect(CompareHelper.compareDuration(0, 1000), isNull);
      expect(CompareHelper.compareDuration(1000, 0), isNull);
    });

    // 上游 DurationMatch.cs:17 `0 => Perfect`
    test('差 0 → Perfect', () {
      expect(
          CompareHelper.compareDuration(1000, 1000), DurationMatchType.perfect);
    });

    // 上游 DurationMatch.cs:18-19 `< 300 => VeryHigh`，300 掉到下一档 High
    test('差 ≤ 299 → VeryHigh；差 300 → High', () {
      expect(CompareHelper.compareDuration(1000, 1299),
          DurationMatchType.veryHigh);
      expect(
          CompareHelper.compareDuration(1000, 1300), DurationMatchType.high);
    });

    // 上游 DurationMatch.cs:19-20 `< 700 => High`，700 掉到 Medium
    test('差 ≤ 699 → High；差 700 → Medium', () {
      expect(
          CompareHelper.compareDuration(1000, 1699), DurationMatchType.high);
      expect(
          CompareHelper.compareDuration(1000, 1700), DurationMatchType.medium);
    });

    // 上游 DurationMatch.cs:20-21 `< 1500 => Medium`，1500 掉到 Low
    test('差 ≤ 1499 → Medium；差 1500 → Low', () {
      expect(
          CompareHelper.compareDuration(1000, 2499),
          DurationMatchType.medium);
      expect(CompareHelper.compareDuration(1000, 2500), DurationMatchType.low);
    });

    // 上游 DurationMatch.cs:21-22 `< 3500 => Low`，3500 掉到 NoMatch
    test('差 ≤ 3499 → Low；差 3500 → NoMatch', () {
      expect(CompareHelper.compareDuration(1000, 4499), DurationMatchType.low);
      expect(
          CompareHelper.compareDuration(1000, 4500), DurationMatchType.noMatch);
    });

    // 上游 CompareHelper.cs:26-45：700ms 偏差在 DurationMatch.cs:19 落到 Medium(4)，
    // 总分 7 + 7 + 7*0.4 + 7*0.2 + 4 = 22.2；五个字段都有值，
    // availableScore = fullScore = 25.2，归一系数 1；22.2 > 21 → Perfect
    // （CompareHelper.cs:49）。分数确实被拉低了（25.2 → 22.2），但档位还在 Perfect。
    test('时长不同会拉低总分（同艺人同名，700ms 偏差 → 总分 22.2，仍是 Perfect）',
        () {
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
      expect(match, MatchType.perfect);
    });
  });

  group('CompareHelper.compareName 档位（ComputeTextSame + 特殊后缀）', () {
    // 上游 NameMatch.cs:38 `if (name1 == name2) return Perfect`
    test('完全一致 → Perfect', () {
      expect(CompareHelper.compareName('Song', 'Song'), NameMatchType.perfect);
    });

    // 上游 NameMatch.cs:15 `IsNullOrWhiteSpace` → null
    test('空串 → null（上游 IsNullOrWhiteSpace）', () {
      expect(CompareHelper.compareName(null, 'Song'), isNull);
      expect(CompareHelper.compareName('Song', '  '), isNull);
    });

    // 上游 NameMatch.cs:25-28 把 '（' '）' '[' ']' 统一成 '(' ')'，:30-32 再吃掉括号前的空格
    test('全角括号/方括号规范化后一致 → Perfect', () {
      expect(CompareHelper.compareName('Song（Deluxe）', 'Song (Deluxe)'),
          NameMatchType.perfect);
      expect(
          CompareHelper.compareName('Song [Live]', 'Song (Live)'),
          NameMatchType.perfect);
    });

    // 上游 NameMatch.cs:43-45 的比较式是 `(...Replace(" - ", " (").Trim() + ")")`
    // 再去掉空格："Song - Live" 变成 "Song(Live)"，"Song (Live)" 变成
    // "Song(Live))"，多出一个右括号所以并不相等，落不到 VeryHigh。
    // 最后 NameMatch.cs:113 的 `ComputeTextSame > 68`（8/11 = 72.7）→ Medium。
    test('" - " 与 " ()" 等价写法 → Medium', () {
      expect(CompareHelper.compareName('Song - Live', 'Song (Live)'),
          NameMatchType.medium);
      // 上游 NameMatch.cs:43-45 真正能命中的写法：右侧不带收尾括号，
      // 两边补完 ")" 之后去空格结果相同 → VeryHigh。
      expect(CompareHelper.compareName('Song - Live', 'Song(Live'),
          NameMatchType.veryHigh);
    });

    // 上游 NameMatch.cs:38 的相等判断在 :40-41 的 `acoustic version` → `acoustic`
    // 归一**之前**，所以这一组到 :43 才命中 VeryHigh，而不是 Perfect。
    test('acoustic version 归一 → VeryHigh', () {
      expect(CompareHelper.compareName('Song Acoustic Version', 'Song Acoustic'),
          NameMatchType.veryHigh);
    });

    // 上游 NameMatch.cs:85-90 的 SpecialCompare（单边存在 + 前缀一致）→ VeryHigh
    test('special 后缀（deluxe 等）单边存在 → VeryHigh', () {
      expect(CompareHelper.compareName('Song', 'Song (Deluxe)'),
          NameMatchType.veryHigh);
      expect(CompareHelper.compareName('Song', 'Song (feat. X)'),
          NameMatchType.veryHigh);
    });

    // 上游 NameMatch.cs:94-95 的 SingleSpecialCompare（双边都有且前缀一致）→ High；
    // 但单边的 explicit 在 :86 就被 SpecialCompare 判成 VeryHigh 了。
    test('双边 special（feat / explicit）→ High；单边 explicit → VeryHigh', () {
      expect(
        CompareHelper.compareName('Song (feat. X)', 'Song (feat. Y)'),
        NameMatchType.high,
      );
      expect(
        CompareHelper.compareName('Song (feat. X)', 'Song (feat. X) (explicit)'),
        NameMatchType.veryHigh,
      );
    });

    // 上游 NameMatch.cs:97（BracketsCompare）+ :76-83 → Medium
    test('只差括号内容且括号前一致 → Medium', () {
      expect(CompareHelper.compareName('Song', 'Song (Live)'),
          NameMatchType.medium);
    });

    // 上游 NameMatch.cs:106 `count / name1.Length >= 0.8 && name1.Length >= 4` → High
    test('同长度 80% 相同（>= 4 字）→ High（异体字分支）', () {
      // 长度 5，逐字符相同 4 个 → 0.8
      expect(CompareHelper.compareName('abcde', 'abcdX'), NameMatchType.high);
    });

    // 上游 NameMatch.cs:107 `>= 0.5 && name1.Length >= 2 && <= 3` → High
    test('同长度 50%~80%（2~3 字）→ High', () {
      expect(CompareHelper.compareName('abc', 'abX'), NameMatchType.high);
    });

    // 上游 NameMatch.cs:111-116：ComputeTextSame 全部不达标 → NoMatch
    test('完全不同 → NoMatch', () {
      expect(CompareHelper.compareName('abcdef', 'zzzzzz'),
          NameMatchType.noMatch);
    });

    // 上游 NameMatch.cs:124-135 / ArtistMatch.cs:70-81 / DurationMatch.cs:31-42
    test('GetMatchScore 合并语义（null → 0）', () {
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
    // 上游 Searcher.cs:59-93 的 do-while：`while (++level < 3)` 让 level 只取到 1、2，
    // 所以一次 track 最多发两次搜索（switch 里的 `_ => string.Empty` 是死代码）。
    test('无结果时依次降级（含 (feat. / - feat. 截断）', () async {
      final searcher = RecordingSearcher();
      final track = multiTrack(
        title: 'Song - feat. X (feat. Y)',
        artists: ['A', 'B'],
        album: 'Album',
      );

      await searcher.searchForResultsByTrack(track);

      expect(searcher.received, [
        // level 1（初始串）：Searcher.cs:59 是整串 `.Replace(" - ", " ")`，
        // 所以标题里的 " - " 已经被换成空格。
        'Song feat. X (feat. Y) A B Album',
        // level 1 的降级串：Title 先截 "(feat." → "Song - feat. X"；
        // 再截 " - feat." → "Song"，加上艺人 →
        'Song A B',
      ]);
    });

    // 上游 Searcher.cs:75-91：非 fullSearch 且已有结果时直接 break
    test('有结果且非完整搜索时：只搜一次（短路）', () async {
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

    // 上游 Searcher.cs:75-87：fullSearch 时即使已有结果也继续降级，
    // 但同样受 `while (++level < 3)` 限制，只有 level 1 / level 2 两轮。
    test('fullSearch = true 时：即使有结果也继续降级', () async {
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

      expect(searcher.received, ['Song A Album', 'Song A']);
      // 两段结果全部累加
      expect(results.length, 2);
      expect(found.length, 1);
    });

    // 上游 Searcher.cs:59 与 :79 都把 null 字段插值成空串：
    //   初始串 = "Song A " → trim 后 "Song A"；
    //   降级串 = "Song A " → trim 后 "Song A"，两者相同 → Searcher.cs:83-86 直接 break。
    test('降级串与上一段相同则 break（不重复搜索）', () async {
      final searcher = RecordingSearcher();
      await searcher.searchForResultsByTrack(
          multiTrack(title: 'Song', artists: ['A']));
      expect(searcher.received, ['Song A']);
    });

    // 上游 Searcher.cs:59：$"{null} {null} {null}" 插值出的是 "  "，Trim 之后是空串；
    // 降级串同样是空串，于是 Searcher.cs:83-86 立刻 break，只搜一次。
    test('title/artist 都为 null 时的字符串行为（上游 string 插值产生空串）',
        () async {
      final searcher = RecordingSearcher();
      await searcher.searchForResultsByTrack(multiTrack());
      expect(searcher.received, ['']);
    });

    // 上游 Searcher.cs:19-32 的无 minimumMatch 重载：空结果时再跑一次 fullSearch。
    test('searchForResult 默认重载：无结果时回退完整搜索并返回首个', () async {
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

    // 上游 Searcher.cs:34-50：首条结果的 MatchType 低于 minimumMatch 时重跑 fullSearch，
    // 仍不达标就返回 null。
    test('searchForResult → minimumMatch：低于要求时回退完整搜索', () async {
      // 第一次返回一个低分结果（艺人不同 → 分数低于 Medium），
      // 触发完整搜索；第二轮给出 Perfect 结果。
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

    test('searchForResult → minimumMatch：始终不达标则返回 null', () async {
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

      // 完整搜索结果里仍未达标 → null（上游 Searcher.cs:46-49）
      expect(result, isNull);
    });
  });

  group('排序稳定性（MatchType 降序）', () {
    // 上游 Searcher.cs:95-100：先给每条结果打分，再按 MatchType 降序排序。
    test('结果按 MatchType 从高到低排序', () async {
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
      // 三条样本必须真的分出高下：艺人 ['A','B','C'] 对 ['A'] 在上游
      // ArtistMatch.cs:47 只拿到 High(5)，专辑再对不上就只剩
      // 7 + 5 + 7 = 19 分（availableScore 23.8，按 CompareHelper.cs:45 归一为
      // 19 * 25.2 / 23.8 = 20.12 → VeryHigh），才排在 perfect（25.2 → Perfect）之后。
      final medium = FakeSearchResult(
        title: 'Song',
        artists: ['A', 'B', 'C'],
        album: 'Other Album',
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

    test('同分结果保持输入顺序（List.sort 稳定）', () async {
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
    // 上游 SearchersHelper.cs:14-68 的三个映射与 Searchers.cs:8-16 的枚举一一对应。
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

    // 上游 SearchersHelper.cs:57-68：八个 Searcher 都不是就返回 null
    test('未知实例 → null', () {
      expect(SearchersHelper.getSearchers(RecordingSearcher()), isNull);
    });
  });
}