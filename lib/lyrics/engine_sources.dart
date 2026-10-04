///
///
library;

import 'decrypters/krc/decrypter.dart' as krc;
import 'helpers/parse_helper.dart';
import 'helpers/types/type_helper.dart';
import 'json_utils.dart';
import 'lyrics_log.dart';
import 'models/line_info.dart';
import 'models/lyrics_data.dart';
import 'models/lyrics_types.dart';
import 'models/track_metadata.dart';
import 'providers/web/providers.dart';
import 'searchers/applemusic_search_result.dart';
import 'searchers/isearcher.dart';
import 'searchers/kugou_search_result.dart';
import 'searchers/lrclib_search_result.dart';
import 'searchers/musixmatch_search_result.dart';
import 'searchers/netease_search_result.dart';
import 'searchers/qqmusic_search_result.dart';
import 'searchers/searchers.dart';
import 'searchers/searchers_helper.dart';
import 'searchers/sodamusic_search_result.dart';
import 'searchers/spotify_search_result.dart';

abstract class LyricsSourceBridge {
  Searchers get searcherType;

  String get displayName;

  ///
  ISearcher get searcher => SearchersHelper.getSearcher(searcherType);

  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track);
}

///
final List<LyricsSourceBridge> defaultSourceBridges = <LyricsSourceBridge>[
  NeteaseBridge(),
  QQMusicBridge(),
  KugouBridge(),
  LRCLibBridge(),
  MusixmatchBridge(),
  SodaMusicBridge(),
  AppleMusicBridge(),
  SpotifyBridge(),
];

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

///
void _mergeLines(List<LineInfo> main, List<LineInfo> secondary,
    {bool asRoma = false}) {
  if (main.isEmpty || secondary.isEmpty) return;

  final map = <int, String>{};
  for (final l in secondary) {
    final t = l.startTime;
    final text = l.text;
    if (t == null || text.isEmpty) continue;
    map[t] = text;
  }
  if (map.isEmpty) return;

  for (final l in main) {
    final t = l.startTime;
    if (t == null) continue;
    final v = map[t];
    if (v == null || v.isEmpty) continue;
    if (l is! FullLineInfoMixin) continue;
    if (asRoma) {
      l.pronunciation = v;
    } else {
      l.translations['zh'] = v;
    }
  }
}

LyricsData? _parseAuto(String text, LyricsRawTypes fallback) {
  final detected = TypeHelper.getLyricsTypes(text);
  final type = detected == LyricsRawTypes.unknown ? fallback : detected;
  if (type == LyricsRawTypes.unknown) return null;
  return ParseHelper.parseLyrics(text, type);
}

List<LineInfo> _parseSecondary(String text, LyricsRawTypes fallback) {
  if (text.trim().isEmpty) return const <LineInfo>[];
  final data = _parseAuto(text, fallback);
  return data?.lines ?? const <LineInfo>[];
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

///
class NeteaseBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.netease;

  @override
  String get displayName => 'Netease Cloud Music';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! NeteaseSearchResult) return null;
    final id = result.id;
    if (id.isEmpty) return null;

    dynamic lyric; // ne.LyricResult
    try {
      lyric = await Providers.neteaseApi.getLyricNew(id);
    } catch (e) {
      lyricsLog('网易云 eapi 取词失败，回退 weapi：$e', warn: true);
    }
    lyric ??= await Providers.neteaseApi.getLyric(id);
    if (lyric == null) return null;

    final yrcText = asStr(lyric.yrc?.lyric);
    if (yrcText.trim().isNotEmpty) {
      final data = ParseHelper.parseLyrics(yrcText, LyricsRawTypes.yrc);
      final lines = data?.lines;
      if (lines != null && lines.isNotEmpty) {
        _mergeLines(lines, _parseSecondary(asStr(lyric.ytlrc?.lyric), LyricsRawTypes.yrc));
        _mergeLines(
            lines, _parseSecondary(asStr(lyric.yromalrc?.lyric), LyricsRawTypes.yrc),
            asRoma: true);
        lyricsLog('网易云 命中逐字 YRC ${lines.length} 行');
        return data;
      }
    }

    final lrcText = asStr(lyric.lrc?.lyric);
    if (lrcText.trim().isEmpty) return null;
    final data = ParseHelper.parseLyrics(lrcText, LyricsRawTypes.lrc);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    _mergeLines(lines, _parseSecondary(asStr(lyric.tlyric?.lyric), LyricsRawTypes.lrc));
    _mergeLines(lines, _parseSecondary(asStr(lyric.romalrc?.lyric), LyricsRawTypes.lrc),
        asRoma: true);
    return data;
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

class QQMusicBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.qqMusic;

  @override
  String get displayName => 'QQ Music';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! QQMusicSearchResult) return null;

    String main = '';
    String trans = '';
    try {
      final r = await Providers.qqMusicApi.getLyricsAsync(result.id);
      main = r?.lyrics ?? '';
      trans = r?.trans ?? '';
    } catch (e) {
      lyricsLog('QQ 音乐 lyric_download 失败：$e', warn: true);
    }

    if (main.trim().isEmpty) {
      try {
        final r = await Providers.qqMusicApi.getLyric(result.mid);
        main = r?.lyric ?? '';
        if (trans.isEmpty) trans = r?.trans ?? '';
      } catch (e) {
        lyricsLog('QQ 音乐老接口也失败：$e', warn: true);
      }
    }
    if (main.trim().isEmpty) return null;

    final data = _parseAuto(main, LyricsRawTypes.lrc);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    _mergeLines(lines, _parseSecondary(trans, LyricsRawTypes.qrc));
    return data;
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

///
class KugouBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.kugou;

  @override
  String get displayName => 'Kugou';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! KugouSearchResult) return null;

    final candidates = await Providers.kugouApi.getSearchLyrics(
      keywords: result.title,
      duration: result.durationMs,
      hash: result.hash,
    );
    final list = candidates?.candidates;
    if (list == null || list.isEmpty) return null;

    for (final c in list.take(5)) {
      final id = c.id;
      final key = c.accessKey;
      if (id == null || id.isEmpty || key == null || key.isEmpty) continue;
      try {
        final raw = await Providers.kugouApi.downloadKrc(id, key);
        if (raw == null || raw.isEmpty) continue;
        final text = krc.Decrypter.decryptLyrics(raw);
        if (text == null || text.trim().isEmpty) continue;
        final data = ParseHelper.parseLyrics(text, LyricsRawTypes.krc);
        final lines = data?.lines;
        if (lines == null || lines.isEmpty) continue;
        lyricsLog('酷狗 命中 KRC ${lines.length} 行（候选 ${c.song ?? ''}）');
        return data;
      } catch (e) {
        lyricsLog('酷狗候选「${c.song ?? ''}」取词失败：$e', warn: true);
        continue;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// LRCLIB
// ---------------------------------------------------------------------------

class LRCLibBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.lrclib;

  @override
  String get displayName => 'LRCLIB';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! LRCLIBSearchResult) return null;

    final r = await Providers.lrclibApi.get(
      result.title,
      result.artist,
      result.album.isEmpty ? null : result.album,
      result.durationMs == null ? null : result.durationMs! / 1000,
    );
    if (r == null) return null;

    final synced = r.syncedLyrics ?? '';
    if (synced.trim().isEmpty) return null;
    final data = ParseHelper.parseLyrics(synced, LyricsRawTypes.lrc);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    return data;
  }
}

// ---------------------------------------------------------------------------
// Musixmatch
// ---------------------------------------------------------------------------

class MusixmatchBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.musixmatch;

  @override
  String get displayName => 'Musixmatch';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! MusixmatchSearchResult) return null;

    final raw = await Providers.musixmatchApi
        .getFullLyricsRawById('${result.id}', result.vanityId);
    if (raw == null || raw.trim().isEmpty) return null;
    final data = ParseHelper.parseLyrics(raw, LyricsRawTypes.musixmatch);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    return data;
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------

class SodaMusicBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.sodaMusic;

  @override
  String get displayName => 'Soda Music';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! SodaMusicSearchResult) return null;
    if (result.id.isEmpty) return null;

    final detail = await Providers.sodaMusicApi.getDetail(result.id);
    final content = detail?.lyric?.content ?? '';
    if (content.trim().isEmpty) return null;

    final data = _parseAuto(content, LyricsRawTypes.lrc);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;

    final trans = '';
    if (trans.trim().isNotEmpty) {
      _mergeLines(lines, _parseSecondary(trans, LyricsRawTypes.lrc));
    }
    return data;
  }
}

// ---------------------------------------------------------------------------
// Apple Music
// ---------------------------------------------------------------------------

class AppleMusicBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.appleMusic;

  @override
  String get displayName => 'Apple Music';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! AppleMusicSearchResult) return null;
    if (result.id.isEmpty) return null;

    final resp = await Providers.appleMusicApi.getLyrics(result.id);
    final ttml = resp?.ttml ?? '';
    if (ttml.trim().isEmpty) return null;
    final data = ParseHelper.parseLyrics(ttml, LyricsRawTypes.ttml);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    return data;
  }
}

// ---------------------------------------------------------------------------
// Spotify
// ---------------------------------------------------------------------------

class SpotifyBridge extends LyricsSourceBridge {
  @override
  Searchers get searcherType => Searchers.spotify;

  @override
  String get displayName => 'Spotify';

  @override
  Future<LyricsData?> fetch(ISearchResult result, TrackMetadata track) async {
    if (result is! SpotifySearchResult) return null;
    if (result.id.isEmpty) return null;

    final raw = await Providers.spotifyApi.getLyrics(result.id);
    if (raw.trim().isEmpty) return null;
    final data = ParseHelper.parseLyrics(raw, LyricsRawTypes.spotify);
    final lines = data?.lines;
    if (lines == null || lines.isEmpty) return null;
    return data;
  }
}
