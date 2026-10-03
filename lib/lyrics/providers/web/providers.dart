/// Ported from Lyricify.Lyrics.Helper/Providers/Web/Providers.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'applemusic/api.dart' as am;
import 'kugou/api.dart' as kg;
import 'lrclib/api.dart' as lrclib;
import 'musixmatch/api.dart' as mx;
import 'netease/api.dart' as ne;
import 'qqmusic/api.dart' as qq;
import 'sodamusic/api.dart' as soda;
import 'spotify/api.dart' as sp;

class Providers {
  Providers._();

  static qq.Api? _qqMusicApi;

  static qq.Api get qqMusicApi => _qqMusicApi ??= qq.Api();

  static ne.Api? _neteaseApi;

  static ne.Api get neteaseApi => _neteaseApi ??= ne.Api();

  static kg.Api? _kugouApi;

  static kg.Api get kugouApi => _kugouApi ??= kg.Api();

  static mx.Api? _musixmatchApi;

  static mx.Api get musixmatchApi => _musixmatchApi ??= mx.Api();

  static soda.Api? _sodaMusicApi;

  static soda.Api get sodaMusicApi => _sodaMusicApi ??= soda.Api();

  static am.Api? _appleMusicApi;

  static am.Api get appleMusicApi => _appleMusicApi ??= am.Api();

  static sp.Api? _spotifyApi;

  static sp.Api get spotifyApi => _spotifyApi ??= sp.Api();

  static lrclib.Api? _lrclibApi;

  static lrclib.Api get lrclibApi => _lrclibApi ??= lrclib.Api();
}
