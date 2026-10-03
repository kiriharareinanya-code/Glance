// Ported from Lyricify.Lyrics.Helper/Searchers/SearcherHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import 'applemusic_searcher.dart';
import 'kugou_searcher.dart';
import 'lrclib_searcher.dart';
import 'musixmatch_searcher.dart';
import 'netease_searcher.dart';
import 'qqmusic_searcher.dart';
import 'sodamusic_searcher.dart';
import 'spotify_searcher.dart';

class SearcherHelper {
  SearcherHelper._();

  static QQMusicSearcher? _qqMusicSearcher;

  static QQMusicSearcher get qqMusicSearcher =>
      _qqMusicSearcher ??= QQMusicSearcher();

  static NeteaseSearcher? _neteaseSearcher;

  static NeteaseSearcher get neteaseSearcher =>
      _neteaseSearcher ??= NeteaseSearcher();

  static KugouSearcher? _kugouSearcher;

  static KugouSearcher get kugouSearcher => _kugouSearcher ??= KugouSearcher();

  static MusixmatchSearcher? _musixmatchSearcher;

  static MusixmatchSearcher get musixmatchSearcher =>
      _musixmatchSearcher ??= MusixmatchSearcher();

  static SodaMusicSearcher? _sodaMusicSearcher;

  static SodaMusicSearcher get sodaMusicSearcher =>
      _sodaMusicSearcher ??= SodaMusicSearcher();

  static AppleMusicSearcher? _appleMusicSearcher;

  static AppleMusicSearcher get appleMusicSearcher =>
      _appleMusicSearcher ??= AppleMusicSearcher();

  static SpotifySearcher? _spotifySearcher;

  static SpotifySearcher get spotifySearcher =>
      _spotifySearcher ??= SpotifySearcher();

  static LRCLIBSearcher? _lrclibSearcher;

  static LRCLIBSearcher get lrclibSearcher =>
      _lrclibSearcher ??= LRCLIBSearcher();
}
