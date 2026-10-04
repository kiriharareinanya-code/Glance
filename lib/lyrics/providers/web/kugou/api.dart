// Ported from Lyricify.Lyrics.Helper/Providers/Web/Kugou/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

import 'dart:convert';
import '../../../json_utils.dart';
import '../../web/base_api.dart';
import 'response.dart';

class Api extends BaseApi {
  @override
  String? get httpRefer => null;

  @override
  Map<String, String>? get additionalHeaders => null;

  Future<SearchSongResponse?> getSearchSong(String keywords) async {
    final response = await getResponseAsync(
        'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=${Uri.encodeComponent(keywords)}&page=1&pagesize=20&showtype=1');
    final resp = decodeAs(response.body, SearchSongResponse.fromJson);
    return resp;
  }

  Future<SearchLyricsResponse?> getSearchLyrics(
      {String? keywords, int? duration, String? hash}) async {
    var durationPara = '';
    if (duration != null) {
      durationPara = '&duration=$duration';
    }
    hash ??= '';
    final keywordPara =
        keywords == null ? '' : Uri.encodeComponent(keywords);
    final response = await getResponseAsync(
        'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=$keywordPara$durationPara&hash=$hash');
    final resp = decodeAs(response.body, SearchLyricsResponse.fromJson);
    return resp;
  }
  /// 下载 KRC 密文：先 search 拿到候选的 id/accessKey，再 download 取回加密体。
  /// 上游 Lyricify 的 Kugou 流程就是这个（search → download → 解密）。
  Future<String?> downloadKrc(String id, String accessKey) async {
    final text = await getAsync(
      'https://lyrics.kugou.com/download?ver=1&client=pc&fmt=krc&charset=utf8'
      '&id=$id&accesskey=${Uri.encodeQueryComponent(accessKey)}',
    );
    if (text.isEmpty) return null;
    // 返回体是 {"content":"<base64 KRC 密文>","fmt":...,"status":1}
    try {
      final j = jsonDecode(text);
      final content = '${(j as Map)['content'] ?? ''}';
      return content.isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

}
