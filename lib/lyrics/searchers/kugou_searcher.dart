// Ported from Lyricify.Lyrics.Helper/Searchers/KugouSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// 上游 KugouSearcher.cs:23 用 `if (track.Group is { Count: > 0 } group)` 展开子曲目；
// Dart 侧 `Song.group` 是非空 List，`is { Count: > 0 }` 的判空部分恒成立，
// 所以这里只保留 `isNotEmpty`（等价，不改行为）。
library;

import '../providers/web/providers.dart';
import 'isearcher.dart';
import 'kugou_search_result.dart';
import 'searcher.dart';
import 'searchers.dart';

class KugouSearcher extends Searcher {
  @override
  String get name => 'Kugou';

  @override
  String get displayName => 'Kugou Music';

  @override
  Searchers get searcherType => Searchers.kugou;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    final search = <ISearchResult>[];

    try {
      final result = await Providers.kugouApi.getSearchSong(searchString);
      final results = result?.data?.info;
      if (results == null) return null;
      for (final track in results) {
        search.add(KugouSearchResult.fromSong(track));
        final group = track.group;
        if (group.isNotEmpty) {
          for (final subTrack in group) {
            search.add(KugouSearchResult.fromSong(subTrack));
          }
        }
      }
    } catch (_) {
      return null;
    }

    return search;
  }
}
