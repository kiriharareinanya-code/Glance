// Ported from Lyricify.Lyrics.Helper/Searchers/SearchersHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `SearchersHelper.xxx(...)`。
library;

import 'applemusic_searcher.dart';
import 'isearcher.dart';
import 'kugou_searcher.dart';
import 'lrclib_searcher.dart';
import 'musixmatch_searcher.dart';
import 'netease_searcher.dart';
import 'qqmusic_searcher.dart';
import 'searcher_helper.dart';
import 'searchers.dart';
import 'sodamusic_searcher.dart';
import 'spotify_searcher.dart';

class SearchersHelper {
  SearchersHelper._();

  static ISearcher getSearcher(Searchers searcher) {
    switch (searcher) {
      case Searchers.qqMusic:
        return SearcherHelper.qqMusicSearcher;
      case Searchers.netease:
        return SearcherHelper.neteaseSearcher;
      case Searchers.kugou:
        return SearcherHelper.kugouSearcher;
      case Searchers.musixmatch:
        return SearcherHelper.musixmatchSearcher;
      case Searchers.sodaMusic:
        return SearcherHelper.sodaMusicSearcher;
      case Searchers.appleMusic:
        return SearcherHelper.appleMusicSearcher;
      case Searchers.spotify:
        return SearcherHelper.spotifySearcher;
      case Searchers.lrclib:
        return SearcherHelper.lrclibSearcher;
    }
  }

  static ISearcher getNewSearcher(Searchers searcher) {
    switch (searcher) {
      case Searchers.qqMusic:
        return QQMusicSearcher();
      case Searchers.netease:
        return NeteaseSearcher();
      case Searchers.kugou:
        return KugouSearcher();
      case Searchers.musixmatch:
        return MusixmatchSearcher();
      case Searchers.sodaMusic:
        return SodaMusicSearcher();
      case Searchers.appleMusic:
        return AppleMusicSearcher();
      case Searchers.spotify:
        return SpotifySearcher();
      case Searchers.lrclib:
        return LRCLIBSearcher();
    }
  }

  static Searchers? getSearchers(ISearcher searcher) {
    if (searcher is QQMusicSearcher) return Searchers.qqMusic;
    if (searcher is NeteaseSearcher) return Searchers.netease;
    if (searcher is KugouSearcher) return Searchers.kugou;
    if (searcher is MusixmatchSearcher) return Searchers.musixmatch;
    if (searcher is SodaMusicSearcher) return Searchers.sodaMusic;
    if (searcher is AppleMusicSearcher) return Searchers.appleMusic;
    if (searcher is SpotifySearcher) return Searchers.spotify;
    if (searcher is LRCLIBSearcher) return Searchers.lrclib;
    return null;
  }
}
