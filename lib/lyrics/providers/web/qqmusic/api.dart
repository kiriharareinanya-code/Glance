// Ported from Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
///
///
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:xml/xml.dart';

import '../../../decrypters/qrc/decrypter.dart';
import '../../../decrypters/qrc/model.dart';
import '../../../decrypters/qrc/xml_utils.dart';
import '../../../helpers/general/string_helper.dart';
import '../../../helpers/types/type_helper.dart';
import '../../../json_utils.dart';
import '../../../models/lyrics_types.dart';
import '../../web/base_api.dart';
import 'response.dart' as resp;

enum SearchTypeEnum {
  songId,
  albumId,
  playlistId,
}

class Api extends BaseApi {
  /// 当前使用的 cookie。未抓到时用 [_fallbackCookie]。
  static String? _cookie;

  /// 兜底 cookie：站点常见的游客追踪字段，值本身不敏感，
  /// 目的是让请求**不是一次裸请求**。`uin`/`qm_keyst` 留空 = 游客态。
  static const String _fallbackCookie =
      'pgv_pvid=0; ts_uid=0; uin=; qqmusic_key=; qm_keyst=';

  /// 首次搜索前抓一次真实游客 cookie（访问 y.qq.com 的 Set-Cookie）。
  ///
  /// 抓不到就退回 [_fallbackCookie] —— 有它比没有强，但不能指望它
  /// 完全绕开限流：实测限流是**按 IP 和频率**来的，cookie 只是让请求
  /// 看起来更"正常"，无法从根本上提高配额。
  static Future<void> ensureVisitorCookie() async {
    if (_cookie != null) return;
    _cookie = _fallbackCookie;
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('https://y.qq.com/'));
      req.headers.set('User-Agent', BaseApi.userAgent);
      final res = await req.close();
      final jar = <String>[
        for (final c in res.cookies) '${c.name}=${c.value}',
      ];
      await res.drain<void>();
      client.close(force: true);
      if (jar.isNotEmpty) {
        _cookie = '${jar.join('; ')}; uin=; qqmusic_key=; qm_keyst=';
      }
    } catch (_) {
      // 抓不到就用兜底，不阻断搜索。
    }
  }
  @override
  String? get httpRefer => 'https://c.y.qq.com/';

  @override
  Map<String, String>? get additionalHeaders => null;

  /// 带上一份「游客 cookie」。
  ///
  /// 为什么需要：QQ 的搜索接口在**完全裸请求**下很容易被限流——实测同一个
  /// 请求，第一次返回 42969 字节（15 首歌），连续几次之后就只剩 **900 字节
  /// 且 songs 为空**（`code` 仍是 0，所以从状态码上看不出问题，只有体积
  /// 反常）。带上 cookie 后请求看起来"像一个已经访问过站点的浏览器"，
  /// 配额明显更宽。
  ///
  /// 这里不需要登录态：`uin`/`qm_keyst` 留空即可，起作用的是那两个
  /// 由站点在首次访问时下发的追踪 cookie（下面的 `ensureVisitorCookie`
  /// 会去抓真实值，抓不到就用这份兜底常量）。
  @override
  String? get httpCookie => _cookie;

  static final DateTime _dtFrom = DateTime(1970, 1, 1, 8, 0, 0, 0);

  // PORT NOTE: 上游 `VerbatimXmlMappingDict`（`QQMusic/Api.cs:17-23`）——之前这里
  // 是空字典，导致 `GetLyricsAsync` 永远取不到 content/contentts 而返回 null。
  static final Map<String, String> verbatimXmlMappingDict = {
    'content': 'orig', // 原文
    'contentts': 'ts', // 译文
    'contentroma': 'roma', // 罗马音
    'Lyric_1': 'lyric', // 解压后的内容
  };

  Future<resp.MusicFcgApiResult?> search(
      String keyword, SearchTypeEnum searchType) async {
    final type = switch (searchType) {
      SearchTypeEnum.songId => 0,
      SearchTypeEnum.albumId => 2,
      SearchTypeEnum.playlistId => 3,
    };
    final data = <String, Object?>{
      'req_1': <String, Object?>{
        'method': 'DoSearchForQQMusicDesktop',
        'module': 'music.search.SearchCgiService',
        'param': <String, Object?>{
          'num_per_page': '20',
          'page_num': '1',
          'query': keyword,
          'search_type': type,
        },
      },
    };

    final raw =
        await postJsonObjectAsync('https://u.y.qq.com/cgi-bin/musicu.fcg', data);

    return decodeAs(raw, resp.MusicFcgApiResult.fromJson);
  }

  Future<resp.MusicFcgApiAlternativeResult?> searchAlternative(
      String keyword) async {
    final data =
        '{"music.search.SearchCgiService": {"method": "DoSearchForQQMusicDesktop","module": "music.search.SearchCgiService","param": {"num_per_page": 10,"page_num": 1,"query": "$keyword","search_type": 0}}}';

    final raw =
        await postRawAsync('https://u.y.qq.com/cgi-bin/musicu.fcg', data);

    return decodeAs(raw, resp.MusicFcgApiAlternativeResult.fromJson);
  }

  Future<resp.AlbumResult?> getAlbum(String albumMid) async {
    final data = <String, String>{
      'albummid': albumMid,
    };

    final raw = await postFormAsync(
        'https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg', data);

    return decodeAs(raw, resp.AlbumResult.fromJson);
  }

  Future<resp.AlbumSongListResult?> getAlbumSongList(String mid,
      {int page = 1, int pageSize = 1000}) async {
    final data = <String, Object?>{
      'comm': <String, Object?>{
        'ct': 24,
        'cv': 10000,
      },
      'albumSonglist': <String, Object?>{
        'method': 'GetAlbumSongList',
        'param': <String, Object?>{
          'albumMid': mid,
          'albumID': 0,
          'begin': (page - 1) * pageSize,
          'num': pageSize,
          'order': 2,
        },
        'module': 'music.musichallAlbum.AlbumSongList',
      },
    };

    final raw = await postJsonAsync(
        'https://u.y.qq.com/cgi-bin/musicu.fcg?g_tk=5381&format=json&inCharset=utf8&outCharset=utf-8',
        data);

    return decodeAs(raw, resp.AlbumSongListResult.fromJson);
  }

  Future<resp.SingerSongResult?> getSingerSongs(String singerMid,
      {int page = 1, int pageSize = 20}) async {
    final data = <String, Object?>{
      'comm': <String, Object?>{
        'ct': 24,
        'cv': 0,
      },
      'singer': <String, Object?>{
        'method': 'get_singer_detail_info',
        'param': <String, Object?>{
          'sort': 5,
          'singermid': singerMid,
          'sin': (page - 1) * pageSize,
          'num': pageSize,
        },
        'module': 'music.web_singer_info_svr',
      },
    };

    final raw =
        await postJsonAsync('http://u.y.qq.com/cgi-bin/musicu.fcg', data);

    return decodeAs(raw, resp.SingerSongResult.fromJson);
  }

  Future<resp.ToplistResult?> getToplist(
      {int id = 4, int page = 1, int pageSize = 100, String? period}) async {
    final timeType = switch (id) {
      4 || 27 || 62 => 'yyyy-MM-dd',
      _ => 'yyyy-W',
    };
    final postPeriod = period ?? _formatDateTime(DateTime.now(), timeType);

    final data = <String, Object?>{
      'detail': <String, Object?>{
        'module': 'musicToplist.ToplistInfoServer',
        'method': 'GetDetail',
        'param': <String, Object?>{
          'topId': id,
          'offset': (page - 1) * pageSize,
          'num': pageSize,
          'period': postPeriod,
        },
      },
      'comm': <String, Object?>{
        'ct': 24,
        'cv': 0,
      },
    };

    final raw =
        await postJsonAsync('https://u.y.qq.com/cgi-bin/musicu.fcg', data);

    return decodeAs(raw, resp.ToplistResult.fromJson);
  }

  Future<resp.PlaylistResult?> getPlaylist(String playlistId) async {
    final data = <String, String>{
      'disstid': playlistId,
      'format': 'json',
      'outCharset': 'utf8',
      'type': '1',
      'json': '1',
      'utf8': '1',
      'onlysong': '0', // 返回歌曲明细
      'new_format': '1',
    };
    final raw = await postFormAsync(
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg', data);

    return decodeAs(raw, resp.PlaylistResult.fromJson);
  }

  // <summary>
  /// query music song
  // </summary>
  // <param name="id">query song by id, support songId and midId, eg: 001RaE0n4RrGX9 or 204422870</param>
  // <returns>music song</returns>
  Future<resp.SongResult?> getSong(String id) async {
    const callBack = 'getOneSongInfoCallback';

    final data = <String, String>{
      (StringHelper.isNumber(id) ? 'songid' : 'songmid'): id,
      'tpl': 'yqq_song_detail',
      'format': 'jsonp',
      'callback': callBack,
      'g_tk': '5381',
      'jsonpCallback': callBack,
      'loginUin': '0',
      'hostUin': '0',
      'outCharset': 'utf8',
      'notice': '0',
      'platform': 'yqq',
      'needNewCode': '0',
    };

    final raw = await postFormAsync(
        'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg', data);

    return decodeAs(_resolveRespJson(callBack, raw), resp.SongResult.fromJson);
  }

  Future<resp.LyricResult?> getLyric(String songMid) async {
    final currentMillis = DateTime.now().toLocal().millisecondsSinceEpoch -
        _dtFrom.millisecondsSinceEpoch;

    const callBack = 'MusicJsonCallback_lrc';

    final data = <String, String>{
      'callback': 'MusicJsonCallback_lrc',
      'pcachetime': currentMillis.toString(),
      'songmid': songMid,
      'g_tk': '5381',
      'jsonpCallback': callBack,
      'loginUin': '0',
      'hostUin': '0',
      'format': 'jsonp',
      'inCharset': 'utf8',
      'outCharset': 'utf8',
      'notice': '0',
      'platform': 'yqq',
      'needNewCode': '0',
    };

    final raw = await postFormAsync(
        'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg', data);

    final result =
        decodeAs(_resolveRespJson(callBack, raw), resp.LyricResult.fromJson);

    return result?.decode();
  }

  // <summary>
  // </summary>
  // <param name="id"></param>
  // <returns></returns>
  Future<QqLyricsResponse?> getLyricsAsync(String id) async {
    var text = await postFormAsync(
        'https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg',
        {
          'version': '15',
          'miniversion': '82',
          'lrctype': '4',
          'musicid': id,
        });

    text = text.replaceAll('<!--', '').replaceAll('-->', '');

    final dict = <String, XmlNode>{};

    XmlUtils.recursionFindElement(
        XmlUtils.create(text), verbatimXmlMappingDict, dict);

    final result = QqLyricsResponse('', '');

    for (final pair in dict.entries) {
      final value = pair.value.innerText;

      if (value.trim().isEmpty) {
        continue;
      }

      String decompressText;
      try {
        // PERF: 3DES is ~100-400 ms of pure Dart for a 20-80 kB payload, all
        // of it on the UI isolate. `decryptQrcLyrics` is top-level and pure, so
        // it ships to a worker isolate. `compute` forwards the thrown exception
        // verbatim (verified: FormatException / RangeError / ArgumentError all
        // survive the boundary), so the null/error handling below is unchanged.
        decompressText = await compute(decryptQrcLyrics, value) ?? '';
      } on FormatException {
        if (TypeHelper.isLyricsType(value, LyricsTypes.lrc)) {
          decompressText = value;
        } else {
          continue;
        }
      } catch (_) {
        continue;
      }

      var s = '';
      if (decompressText.contains('<?xml')) {
        final doc = XmlUtils.create(decompressText);

        final subDict = <String, XmlNode>{};

        XmlUtils.recursionFindElement(doc, verbatimXmlMappingDict, subDict);

        final d = subDict['lyric'];
        if (d is XmlElement) {
          s = d.getAttribute('LyricContent') ?? '';
        }
      } else {
        s = decompressText;
      }

      if (s.trim().isNotEmpty) {
        switch (pair.key) {
          case 'orig':
            result.lyrics = s;
            break;
          case 'ts':
            result.trans = s;
            break;
        }
      }
    }

    if (result.lyrics == '' && result.trans == '') {
      return null;
    }
    return result;
  }

  Future<String> getSongLink(String songMid) async {
    final guid = getGuid();

    final data = <String, Object?>{
      'req': <String, Object?>{
        'method': 'GetCdnDispatch',
        'module': 'CDN.SrfCdnDispatchServer',
        'param': <String, Object?>{
          'guid': guid,
          'calltype': '0',
          'userip': '',
        },
      },
      'req_0': <String, Object?>{
        'method': 'CgiGetVkey',
        'module': 'vkey.GetVkeyServer',
        'param': <String, Object?>{
          'guid': '8348972662',
          'songmid': [songMid],
          'songtype': [1],
          'uin': '0',
          'loginflag': 1,
          'platform': '20',
        },
      },
      'comm': <String, Object?>{
        'uin': 0,
        'format': 'json',
        'ct': 24,
        'cv': 0,
      },
    };

    final raw =
        await postJsonObjectAsync('https://u.y.qq.com/cgi-bin/musicu.fcg', data);

    final res = decodeAs(raw, resp.MusicFcgApiResult.fromJson);

    var link = '';
    if (res != null &&
        res.code == 0 &&
        res.req != null &&
        res.req!.code == 0 &&
        res.req0 != null &&
        res.req0!.code == 0) {
      link = res.req!.data!.sip[0] + res.req0!.data!.midurlinfo[0].purl;
    }

    return link;
  }

  static String _resolveRespJson(String callBackSign, String val) {
    if (!val.startsWith(callBackSign)) {
      return '';
    }

    final jsonStr = val.replaceAll('$callBackSign(', '');
    return _removeLast(jsonStr);
  }

  static String _removeLast(String value) =>
      value.isEmpty ? value : value.substring(0, value.length - 1);

  static String _formatDateTime(DateTime dt, String format) {
    if (format == 'yyyy-MM-dd') {
      return '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }
    return '${dt.year.toString().padLeft(4, '0')}-${_isoWeekNumber(dt)}';
  }

  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    return (thursday.difference(firstDayOfYear).inDays / 7).floor() + 1;
  }

  String getGuid() {
    final guid = StringBuffer();
    final r = Random();
    for (var i = 0; i < 10; i++) {
      guid.write(r.nextInt(10).toString());
    }

    return guid.toString();
  }
}
