// Ported from Lyricify.Lyrics.Helper/Searchers/SodaMusicSearcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   `result?.ResultGroups?.Where(g => g?.Data != null).SelectMany(g => g.Data)`
// `result?.resultGroups?.expand((g) => g.data)`。
// → `resultData.meta?.itemType != 'track' || resultData.entity?.track == null`。
library;

import '../providers/web/providers.dart';
import 'isearcher.dart';
import 'searcher.dart';
import 'searchers.dart';
import 'sodamusic_search_result.dart';

class SodaMusicSearcher extends Searcher {
  @override
  String get name => 'SodaMusic';

  @override
  String get displayName => 'Soda Music';

  @override
  Searchers get searcherType => Searchers.sodaMusic;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString) async {
    final search = <ISearchResult>[];

    try {
      final result = await Providers.sodaMusicApi.search(searchString);
      final groups = result?.resultGroups;
      if (groups == null || groups.isEmpty) return search;
      final items = <dynamic>[];
      for (final g in groups) {
        items.addAll(g.data ?? const []);
      }
      if (items.isEmpty) return search;

      for (final resultData in items) {
        if (resultData.meta?.itemType != 'track' ||
            resultData.entity?.track == null) {
          continue;
        }
        search.add(SodaMusicSearchResult.fromResultGroupItem(resultData));
      }
    } catch (_) {
      return null;
    }

    return search;
  }
}
