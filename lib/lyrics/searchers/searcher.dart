// Ported from Lyricify.Lyrics.Helper/Searchers/Searcher.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//
library;

import '../models/track_metadata.dart';
import 'helpers/compare_helper.dart';
import 'isearcher.dart';
import 'searchers.dart';

abstract class Searcher implements ISearcher {
  @override
  String get name;

  @override
  String get displayName;

  @override
  Searchers get searcherType;

  @override
  Future<List<ISearchResult>?> searchForResults(String searchString);

  @override
  Future<ISearchResult?> searchForResult(TrackMetadata track,
      [MatchType? minimumMatch]) async {
    var search = await searchForResultsByTrack(track);

    if (minimumMatch != null) {
      if (search.isEmpty ||
          (search[0].matchType?.value ?? 0) < minimumMatch.value) {
        search = await searchForResultsByTrack(track, true);
      }

      if (search.isEmpty) return null;

      if ((search[0].matchType?.value ?? 0) >= minimumMatch.value) {
        return search[0];
      } else {
        return null;
      }
    }

    if (search.isEmpty) search = await searchForResultsByTrack(track, true);

    if (search.isEmpty) return null;

    return search[0];
  }

  @override
  Future<List<ISearchResult>> searchForResultsByTrack(TrackMetadata track,
      [bool fullSearch = false]) async {
    // PORT NOTE: 上游 Searcher.cs:59 是
    //   `$"{track.Title} {track.Artist?.Replace(", ", " ")} {track.Album}".Replace(" - ", " ").Trim()`
    // C# 的字符串插值遇到 null 字段得到的是**空串**（`"" + " " + ""` → Trim 后 `""`）；
    // Dart 的 `'${null}'` 会写出字面量 `"null"`，把搜索串污染成 `"Song A null"`。
    // 这里逐个补 `?? ''` 还原上游行为（level 1 / level 2 的插值见 :79 / :80）。
    var searchString =
        '${track.title ?? ''} ${track.artist?.replaceAll(', ', ' ') ?? ''} ${track.album ?? ''}'
            .replaceAll(' - ', ' ')
            .trim();
    final searchResults = <ISearchResult>[];

    var level = 1;
    do {
      final results = await searchForResults(searchString);
      if (results != null && results.isNotEmpty) {
        searchResults.addAll(results);
      }

      var newTitle = track.title;
      if (newTitle?.contains('(feat.') == true) {
        final title = newTitle!;
        newTitle = title.substring(0, title.indexOf('(feat.')).trim();
      }
      if (newTitle?.contains(' - feat.') == true) {
        final title = newTitle!;
        newTitle = title.substring(0, title.indexOf(' - feat.')).trim();
      }

      if (fullSearch || results == null || results.isEmpty) {
        final String newSearchString;
        switch (level) {
          case 1:
            newSearchString =
                '${newTitle ?? ''} ${track.artist?.replaceAll(', ', ' ') ?? ''}'
                    .replaceAll(' - ', ' ')
                    .trim();
            break;
          case 2:
            newSearchString =
                (newTitle ?? '').replaceAll(' - ', ' ').trim();
            break;
          default:
            newSearchString = '';
            break;
        }
        if (newSearchString != searchString) {
          searchString = newSearchString;
        } else {
          break;
        }
      } else {
        break;
      }
    } while (++level < 3);

    for (final result in searchResults) {
      result.setMatchType(CompareHelper.compareTrack(track, result));
    }

    searchResults.sort(
        (x, y) => MatchTypeComparer().compare(y.matchType!, x.matchType!));

    return searchResults;
  }
}
