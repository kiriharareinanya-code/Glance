// Ported from Lyricify.Lyrics.Helper/Searchers/QQMusicSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//
//
library;

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
      final result = await Providers.qqMusicApi
          .search(searchString, qq.SearchTypeEnum.songId);
      final results = result?.req1?.data?.body?.song?.list;
      if (results == null) return null;
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
