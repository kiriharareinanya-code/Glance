// Ported from Lyricify.Lyrics.Helper/Searchers/QQMusicSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//
//
library;

import '../lyrics_log.dart';
import '../providers/web/providers.dart';
import '../providers/web/qqmusic/api.dart' as qq;
import 'isearcher.dart';
import 'qqmusic_search_result.dart';
import 'searcher.dart';
import 'searchers.dart';

class QQMusicSearcher extends Searcher {
  @override
  String get name => 'QQ Music';

  @override
  String get displayName => 'QQ Music';

  @override
  Searchers get searcherType => Searchers.qqMusic;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    final search = <ISearchResult>[];

    try {
      // 先确保带上游客 cookie：裸请求很容易被 QQ 限流，表现为
      // "返回 200 但 songs 为空、body 只有 ~900 字节"（见 Api.ensureVisitorCookie）。
      await qq.Api.ensureVisitorCookie();
      final result = await Providers.qqMusicApi
          .search(searchString, qq.SearchTypeEnum.songId);
      final results = result?.req1?.data?.body?.song?.list;
      if (results == null) {
        return null;
      }
      // 返回 200、`code` 也是 0，但歌曲列表为空 —— 这几乎总是**被限流**，
      // 不是"这个关键词没有结果"。不单独记一条的话，日志里只会看到
      // "QQ Music 无候选"，和真的没搜到混在一起，完全没法区分。
      // （实测裸请求第一次能拿到 15 首，连发几次后就变成 0 首。）
      if (results.isEmpty) {
        lyricsLog('QQ 音乐返回空列表 —— 大概率被限流（code=0 但 songs=0）',
            warn: true);
      }
      for (final track in results) {
        search.add(QQMusicSearchResult.fromSong(track as dynamic));
        final group = track.group;
        if (group.isNotEmpty) {
          for (final subTrack in group) {
            search.add(QQMusicSearchResult.fromSong(subTrack as dynamic));
          }
        }
      }
    } catch (_) {
      return null;
    }

    return search;
  }
}
