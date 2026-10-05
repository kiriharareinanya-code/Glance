/// 回归测试：用户实拍《他不懂》《阳光下的星星》只有开头两行（作词/作曲），
/// 后面整片空白。根因有两条，都在这里钉住。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';
import 'package:vectra/lyrics/searchers/isearcher.dart';

/// 《阳光下的星星》真实时长。
TrackMultiArtistMetadata _track(int durationMs) {
  final t = TrackMultiArtistMetadata()
    ..title = '阳光下的星星'
    ..artists = ['金海心']
    ..durationMs = durationMs;
  return t;
}

class _R implements ISearchResult {
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
  @override
  MatchType? matchType;
  @override
  String get artist => artists.join(', ');
  @override
  String get albumArtist => (albumArtists ?? <String>[]).join(', ');
  @override
  ISearcher get searcher => throw UnimplementedError();
  @override
  void setMatchType(MatchType? m) => matchType = m;
  _R(this.title, this.artists, this.album, this.albumArtists, this.durationMs);
}

void main() {
  group('空行占比判据（对应 _hasRealLyrics 的规则）', () {
    // 这是 engine_sources.dart 里 _hasRealLyrics 的判定：非空行 * 2 >= 总行数。
    bool hasReal(List<LineInfo>? lines) {
      if (lines == null || lines.isEmpty) return false;
      return lines.where((l) => l.text.trim().isNotEmpty).length * 2 >=
          lines.length;
    }

    test('用户实拍的那种数据：38 行里 36 行空 → 判为不可用', () {
      final lines = <LineInfo>[
        TextLineInfo('作词: 代岳东/周振霆', 0),
        TextLineInfo('作曲: 唐湘智', 1000),
        for (var i = 0; i < 36; i++) TextLineInfo('', 19530 + i * 3000),
      ];
      expect(hasReal(lines), isFalse,
          reason: '这就是让用户只看到两行制作名单的那份数据');
    });

    test('正常歌词（个别空行是间奏）→ 判为可用', () {
      final lines = <LineInfo>[
        for (var i = 0; i < 40; i++)
          i == 20 ? TextLineInfo('', 60000) : TextLineInfo('第$i句', i * 3000),
      ];
      expect(hasReal(lines), isTrue);
    });

    test('全都有词的正常 YRC（实测 38/38）→ 可用', () {
      final lines = <LineInfo>[
        TextLineInfo('作词: 某', 0),
        for (var i = 0; i < 37; i++) TextLineInfo('第$i句', (i + 1) * 5000),
      ];
      expect(lines.length, 38);
      expect(hasReal(lines), isTrue);
    });

    test('一半空一半有 → 恰好判为可用（边界取 >=）', () {
      final lines = <LineInfo>[
        TextLineInfo('有', 0),
        TextLineInfo('', 1000),
      ];
      expect(hasReal(lines), isTrue);
    });

    test('null / 空列表 → 不可用', () {
      expect(hasReal(null), isFalse);
      expect(hasReal(<LineInfo>[]), isFalse);
    });
  });

  group('时长否决闸：修「时长差 75 秒却判 perfect」', () {
    test('复现原 bug：标题歌手全对、时长差 36% → 必须 NoMatch', () {
      final r = _R('阳光下的星星', ['金海心'], '', null, 283514);
      // 真值 207814ms，差 75.7 秒 = 36.4%
      expect(
        CompareHelper.compareTrack(_track(207814), r),
        MatchType.noMatch,
        reason: '原实现归一化会把时长分稀释掉，14 分经归一后 21.2 > 21 判成 perfect，'
            '于是歌词被取走——但行时间戳在 4 分钟之后，歌只有 3:52',
      );
    });

    test('长 intro / 现场版的正常差异（20~40 秒）→ 不受影响', () {
      for (final d in [227814, 247814]) {
        expect(
          CompareHelper.compareTrack(_track(207814), _R('阳光下的星星', ['金海心'], '', null, d)),
          isNot(MatchType.noMatch),
          reason: '差 ${(d - 207814) ~/ 1000} 秒属正常版本差异，不该被否',
        );
      }
    });
  });
}
