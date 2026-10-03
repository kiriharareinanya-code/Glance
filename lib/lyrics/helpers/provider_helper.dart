// Ported from Lyricify.Lyrics.Helper/Helpers/ProviderHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `neteaseApi` / `qqMusicApi` / `kugouApi` / `lrclibApi` / `musixmatchApi` /
// `qqMusicApi` / `neteaseApi` / `kugouApi` / `musixmatchApi` / `sodaMusicApi` /
library;

import '../providers/web/applemusic/api.dart' as am;
import '../providers/web/kugou/api.dart' as kg;
import '../providers/web/lrclib/api.dart' as lrclib;
import '../providers/web/musixmatch/api.dart' as mx;
import '../providers/web/netease/api.dart' as ne;
import '../providers/web/providers.dart';
import '../providers/web/qqmusic/api.dart' as qq;
import '../providers/web/sodamusic/api.dart' as soda;
import '../providers/web/spotify/api.dart' as sp;

class ProviderHelper {
  ProviderHelper._();

  static qq.Api get qqMusicApi => Providers.qqMusicApi;

  static ne.Api get neteaseApi => Providers.neteaseApi;

  static kg.Api get kugouApi => Providers.kugouApi;

  static mx.Api get musixmatchApi => Providers.musixmatchApi;

  static soda.Api get sodaMusicApi => Providers.sodaMusicApi;

  static am.Api get appleMusicApi => Providers.appleMusicApi;

  static sp.Api get spotifyApi => Providers.spotifyApi;

  static lrclib.Api get lrclibApi => Providers.lrclibApi;
}
