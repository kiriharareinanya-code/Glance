/// 最小隔离：直接调各 provider，不经过 engine，定位是哪一层坏。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/providers/web/netease/api.dart' show SearchTypeEnum;
import 'package:vectra/lyrics/providers/web/providers.dart';
import 'package:vectra/lyrics/searchers/helpers/compare_helper.dart';
import 'package:vectra/lyrics/searchers/netease_search_result.dart';
import 'package:vectra/lyrics/models/track_metadata.dart';

void main() {
  test('网易云旧接口 search()', () async {
    try {
      final r = await Providers.neteaseApi.search('昔涟 张韶涵', SearchTypeEnum.songId);
      // ignore: avoid_print
      print('[netease.search] code=${r?.code} songs=${r?.result?.songs?.length}');
      for (final s in (r?.result?.songs ?? const []).take(3)) {
        // ignore: avoid_print
        print('    ${s.name} / ${s.artists?.map((a) => a.name).join('/')} / ${s.duration}');
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[netease.search] 抛异常: $e');
      // ignore: avoid_print
      print(st.toString().split('\n').take(6).join('\n'));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('网易云新接口 searchNew()', () async {
    try {
      final r = await Providers.neteaseApi.searchNew('昔涟 张韶涵');
      // ignore: avoid_print
      print('[netease.searchNew] code=${r?.code} songs=${r?.result?.songs?.length}');
      for (final s in (r?.result?.songs ?? const []).take(3)) {
        // ignore: avoid_print
        print('    ${s.name} / ${s.duration}');
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('[netease.searchNew] 抛异常: $e');
      // ignore: avoid_print
      print(st.toString().split('\n').take(6).join('\n'));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('逐层拆解 compareTrack 的递归', () async {
    final track = TrackMultiArtistMetadata()
      ..title = 'Ripples of Past Reverie - Chinese Ver.'
      ..artist = 'HOYO-MiX'
      ..durationMs = 186671;
    // ignore: avoid_print
    print('[A] getTrackMultiArtistMetadata 入口');
    final m = TrackMultiArtistMetadata.getTrackMultiArtistMetadata(track);
    // ignore: avoid_print
    print('[B] 拿到 multi: title=${m.title} artists=${m.artists}');

    final r = await Providers.neteaseApi.searchNew('昔涟 张韶涵');
    final song = r!.result.songs!.first;
    // ignore: avoid_print
    print('[C] 拿到 song: ${song.name} / ${song.artists?.map((a) => a.name).join('/')}');

    final sr = NeteaseSearchResult.fromSong(song);
    // ignore: avoid_print
    print('[D] 转成 SearchResult: title=${sr.title} artists=${sr.artists}');

    // ignore: avoid_print
    print('[E] 逐个读字段…');
    // ignore: avoid_print
    print('   sr.artist      = ${sr.artist}');
    // ignore: avoid_print
    print('   sr.albumArtists= ${sr.albumArtists}');
    // ignore: avoid_print
    print('   sr.album       = ${sr.album}');
    // ignore: avoid_print
    print('   sr.durationMs  = ${sr.durationMs}');
    // ignore: avoid_print
    print('[F] compareName(track.title, sr.title)…');
    // ignore: avoid_print
    print('   → ${CompareHelper.compareName(track.title, sr.title)}');
    // ignore: avoid_print
    print('[G] compareArtist(m.artists, sr.artists)…');
    // ignore: avoid_print
    print('   → ${CompareHelper.compareArtist(m.artists, sr.artists)}');
    // ignore: avoid_print
    print('[H] compareDuration(…)');
    // ignore: avoid_print
    print('   → ${CompareHelper.compareDuration(m.durationMs, sr.durationMs)}');
    // ignore: avoid_print
    print('[I] 完整 compareTrack…');
    // ignore: avoid_print
    print('   → ${CompareHelper.compareTrack(track, sr)}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('打印每个候选的分数排名', () async {
    final track = TrackMultiArtistMetadata()
      ..title = 'Ripples of Past Reverie - Chinese Ver.'
      ..artist = 'HOYO-MiX'
      ..durationMs = 186671;
    final r = await Providers.neteaseApi.searchNew('昔涟 张韶涵 HOYO-MiX');
    final rows = <String, MatchType>{};
    for (final s in r!.result.songs!) {
      final sr = NeteaseSearchResult.fromSong(s);
      rows['${sr.title} / ${sr.artists?.join("/")} / ${sr.durationMs}ms'] =
          CompareHelper.compareTrack(track, sr);
    }
    final sorted = rows.entries.toList()
      ..sort((a, b) => b.value.index.compareTo(a.value.index));
    for (final e in sorted.take(8)) {
      // ignore: avoid_print
      print('  ${e.value.name.padRight(10)} ${e.key}');
    }
    // 单独看《昔涟》的 album 字段有没有值
    for (final s in r!.result.songs!) {
      final sr = NeteaseSearchResult.fromSong(s);
      if (sr.title == '昔涟') {
        // ignore: avoid_print
        print('  《昔涟》album = "${sr.album}"');
      }
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('酷狗 searchSong()', () async {
    try {
      final r = await Providers.kugouApi.getSearchSong('昔涟');
      // ignore: avoid_print
      print('[kugou.search] status=${r?.status} songs=${r?.data?.info?.length}');
    } catch (e, st) {
      // ignore: avoid_print
      print('[kugou.search] 抛异常: $e');
      // ignore: avoid_print
      print(st.toString().split('\n').take(6).join('\n'));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
