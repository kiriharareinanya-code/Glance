// Ported from Lyricify.Lyrics.Helper/Providers/Web/Netease/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

import 'dart:convert';
import 'dart:math';

import '../../../helpers/general/string_helper.dart';
import '../../../json_utils.dart';
import '../../web/base_api.dart';
import 'eapi_helper.dart';
import 'response.dart';

enum SearchTypeEnum {
  songId,
  albumId,
  playlistId,
}

class Api extends BaseApi {
  @override
  String? get httpRefer => 'https://music.163.com/';

  @override
  String? get httpCookie => BaseApi.cookie;

  @override
  Map<String, String>? get additionalHeaders => null;

  // General
  static const String modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';
  static const String nonce = '0CoJUm6Qyw8W8jud';
  static const String pubkey = '010001';
  static const String vi = '0102030405060708';

  static final List<int> _viBytes = utf8.encode(vi);

  // use keygen in c#
  final String _secretKey;

  Api({String? secretKey}) : _secretKey = secretKey ?? createSecretKey(16);

  String get encSecKey => _encSecKeyValue ??= rsaEncode(_secretKey);
  String? _encSecKeyValue;

  Future<SearchResult?> search(String keyword, SearchTypeEnum searchType) async {
    final String type = switch (searchType) {
      SearchTypeEnum.songId => '1',
      SearchTypeEnum.albumId => '10',
      SearchTypeEnum.playlistId => '1000',
    };

    final url =
        'http://music.163.com/api/search/get/web?csrf_token=hlpretag=&hlposttag=&s=${Uri.encodeComponent(keyword)}&type=$type&offset=0&total=true&limit=20';

    final res = await getAsync(url);

    return decodeAs(res, SearchResult.fromJson);
  }

  Future<SearchResult?> searchNew(String keyword) async {
    const String url = 'https://interface.music.163.com/eapi/cloudsearch/pc';

    final data = <String, String>{
      's': keyword,
      'type': '1',
      'limit': '30',
      'offset': '0',
      'total': 'true',
    };

    final raw = await EapiHelper.postAsync(url, BaseApi.httpClient, data);

    final eapiResult = decodeAs(raw, EapiSearchResult.fromJson);
    if (eapiResult == null) return null;

    final list = <Song>[];
    for (final song in eapiResult.result.eapiSongs) {
      list.add(Song(
        album: song.album,
        alias: song.alias,
        artists: song.artists,
        duration: song.duration,
        id: song.id,
        name: song.name,
        privilege: song.privilege,
        publishTime: song.publishTime,
      ));
    }
    final resultData = SearchResultData(
      songs: list,
      songCount: eapiResult.result.songCount,
      albums: eapiResult.result.albums,
      albumCount: eapiResult.result.albumCount,
      playlists: eapiResult.result.playlists,
      playlistCount: eapiResult.result.playlistCount,
    );
    return SearchResult(
      needLogin: eapiResult.needLogin,
      result: resultData,
      code: eapiResult.code,
    );
  }

  // <summary>
  ///
  // </summary>
  // <param name="songId"></param>
  // <param name="bitrate"></param>
  // <exception cref="WebException"></exception>
  // <returns></returns>
  Future<Map<String, Datum>> getDatum(List<String> songId,
      {int bitrate = 999000}) async {
    final result = <String, Datum>{};

    final urls = await getSongsUrl(songId, bitrate: bitrate);
    if (urls?.code == 200) {
      for (final datum in urls!.data) {
        result[datum.id] = datum;
      }
    }

    return result;
  }

  // <summary>
  ///
  // </summary>
  // <param name="songIds"></param>
  // <exception cref="WebException"></exception>
  // <returns></returns>
  Future<Map<String, Song>> getSongs(List<String> songIds) async {
    final result = <String, Song>{};

    if (songIds.isEmpty) {
      return result;
    }

    final detailResult = await getDetail(songIds);
    if (detailResult == null || detailResult.code != 200) {
      return result;
    }

    for (final song in detailResult.songs) {
      result[song.id] = song;
    }

    return result;
  }

  // <summary>
  ///
  // </summary>
  // <param name="albumId"></param>
  // <returns></returns>
  // <exception cref="WebException"></exception>
  Future<AlbumResult?> getAlbum(String albumId) async {
    final url = 'https://music.163.com/weapi/v1/album/$albumId?csrf_token=';

    final data = <String, String>{
      'csrf_token': '',
    };

    final raw = await postRawAsync(url, prepare(jsonEncode(data)));

    return decodeAs(raw, AlbumResult.fromJson);
  }

  Future<PlaylistResult?> getPlaylist(String playlistId) async {
    const url = 'https://music.163.com/weapi/v6/playlist/detail?csrf_token=';

    final data = <String, String>{
      'csrf_token': '',
      'id': playlistId,
      'offset': '0',
      'total': 'true',
      'limit': '1000',
      'n': '1000',
    };

    final raw = await postRawAsync(url, prepare(jsonEncode(data)));

    return decodeAs(raw, PlaylistResult.fromJson);
  }

  // <summary>
  // </summary>
  // <exception cref="WebException"></exception>
  // <see cref="LyricResult"/></returns>
  Future<LyricResult?> getLyric(String songId) async {
    const url = 'https://music.163.com/weapi/song/lyric?csrf_token=';

    final data = <String, String>{
      'id': songId,
      'os': 'pc',
      'lv': '-1',
      'kv': '-1',
      'tv': '-1',
      'rv': '-1',
      'csrf_token': '',
    };

    final raw = await postRawAsync(url, prepare(jsonEncode(data)));

    return decodeAs(raw, LyricResult.fromJson);
  }

  // <summary>
  // </summary>
  // <exception cref="WebException"></exception>
  // <see cref="LyricResult"/></returns>
  Future<LyricResult?> getLyricNew(String songId) async {
    const url = 'https://interface3.music.163.com/eapi/song/lyric/v1';

    final data = <String, String>{
      'id': songId,
      'cp': 'false',
      'lv': '0',
      'kv': '0',
      'tv': '0',
      'rv': '0',
      'yv': '0',
      'ytv': '0',
      'yrv': '0',
      'csrf_token': '',
    };

    final raw = await EapiHelper.postAsync(url, BaseApi.httpClient, data);

    return decodeAs(raw, LyricResult.fromJson);
  }

  // <summary>
  ///
  // </summary>
  // <param name="songId"></param>
  // <param name="bitrate"></param>
  // <returns></returns>
  // <exception cref="WebException"></exception>
  Future<SongUrls?> getSongsUrl(List<String> songId, {int bitrate = 999000}) async {
    const url = 'https://music.163.com/weapi/song/enhance/player/url?csrf_token=';

    final data = <String, String>{
      'ids': '[${songId.join(',')}]',
      'br': bitrate.toString(),
      'csrf_token': '',
    };

    final raw = await postRawAsync(url, prepare(jsonEncode(data)));

    return decodeAs(raw, SongUrls.fromJson);
  }

  // <summary>
  // </summary>
  // <exception cref="WebException"></exception>
  // <returns></returns>
  Future<DetailResult?> getDetail(List<String> songIds) async {
    try {
      const url = 'https://music.163.com/weapi/v3/song/detail?csrf_token=';

      final songRequests = StringBuffer();
      for (final songId in songIds) {
        songRequests.write("{'id':'");
        songRequests.write(songId);
        songRequests.write("'}");
        songRequests.write(',');
      }

      final data = <String, String>{
        'c': '[${_removeLast(songRequests.toString())}]',
        'os': 'pc',
        'csrf_token': '',
      };

      final raw = await postRawAsync(url, prepare(jsonEncode(data)));

      return decodeAs(raw, DetailResult.fromJson);
    } catch (_) {
      return null;
    }
  }


  String prepare(String raw) {
    final data = <String, String>{
      'params': aesEncode(aesEncode(raw, nonce), _secretKey),
      'encSecKey': encSecKey,
    };
    return jsonEncode(data);
  }

  // encrypt mod
  static String rsaEncode(String text) {
    final srtext = StringHelper.reverse(text);
    final a = bcHexDec(
        _toHex(utf8.encode(srtext)));
    final b = bcHexDec(pubkey);
    final c = bcHexDec(modulus);
    var key = a.modPow(b, c).toRadixString(16);
    key = key.padLeft(256, '0');

    return key.length > 256 ? key.substring(key.length - 256, key.length) : key;
  }

  static BigInt bcHexDec(String hex) {
    var dec = BigInt.zero;
    final len = hex.length;

    for (var i = 0; i < len; i++) {
      dec += BigInt.from(int.parse(hex[i], radix: 16)) *
          BigInt.from(16).pow(len - i - 1);
    }

    return dec;
  }

  static String aesEncode(String secretData, [String secret = 'TA3YiYCfY2dDJQgg']) {
    final encrypted = EapiHelper.aesEncryptCbc(
        utf8.encode(secretData), utf8.encode(secret), _viBytes);

    return base64.encode(encrypted);
  }

  static String createSecretKey(int length) {
    const str = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final sb = StringBuffer();
    final rnd = Random();

    for (var i = 0; i < length; ++i) {
      sb.write(str[rnd.nextInt(str.length)]);
    }

    return sb.toString();
  }

  static String _removeLast(String value) =>
      value.isEmpty ? value : value.substring(0, value.length - 1);

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

