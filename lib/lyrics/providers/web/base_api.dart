/// Ported from Lyricify.Lyrics.Helper/Providers/Web/BaseApi.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../http/lyrics_http.dart';
import '../../json_utils.dart';

abstract class BaseApi {
  static LyricsHttpClient httpClient = DirectLyricsHttpClient();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/63.0.3239.132 Safari/537.36';

  static const String cookie =
      'os=pc;osver=Microsoft-Windows-10-Professional-build-16299.125-64bit;appver=2.0.3.131777;channel=netease;__remember_me=true';

  String? get httpUserAgent => userAgent;

  String? get httpCookie => null;

  String? get httpRefer;

  Map<String, String>? get additionalHeaders;

  Map<String, String> _headers({String? contentType}) {
    final headers = <String, String>{};
    final ua = httpUserAgent;
    if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
    final refer = httpRefer;
    if (refer != null && refer.isNotEmpty) headers['Referer'] = refer;
    final cookieValue = httpCookie;
    if (cookieValue != null && cookieValue.isNotEmpty) {
      headers['Cookie'] = cookieValue;
    }
    final extra = additionalHeaders;
    if (extra != null) headers.addAll(extra);
    if (contentType != null) headers['Content-Type'] = contentType;
    return headers;
  }

  Future<LyricsHttpResponse> getResponseAsync(String url) =>
      BaseApi.httpClient
          .send(method: 'GET', url: Uri.parse(url), headers: _headers());

  Future<String> getAsync(String url) async {
    final res = await getResponseAsync(url);
    if (!res.ok) {
      throw LyricsHttpException('GET $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }

  Future<String> postFormAsync(String url, Map<String, String> paramDict) async {
    final res = await BaseApi.httpClient.send(
      method: 'POST',
      url: Uri.parse(url),
      headers: _headers(contentType: 'application/x-www-form-urlencoded'),
      body: Uri(queryParameters: paramDict).query,
    );
    if (!res.ok) {
      throw LyricsHttpException('POST $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }

  Future<String> postJsonAsync(String url, Object? param) async {
    final res = await BaseApi.httpClient.send(
      method: 'POST',
      url: Uri.parse(url),
      headers: _headers(contentType: 'application/json'),
      body: jencode(param),
    );
    if (!res.ok) {
      throw LyricsHttpException('POST $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }

  Future<String> postJsonObjectAsync(
      String url, Map<String, Object?> paramDict) async {
    final res = await BaseApi.httpClient.send(
      method: 'POST',
      url: Uri.parse(url),
      headers: _headers(contentType: 'application/json'),
      body: jencode(paramDict),
    );
    if (!res.ok) {
      throw LyricsHttpException('POST $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }

  Future<String> postRawAsync(String url, String param) async {
    final res = await BaseApi.httpClient.send(
      method: 'POST',
      url: Uri.parse(url),
      headers: _headers(contentType: 'application/json'),
      body: param,
    );
    if (!res.ok) {
      throw LyricsHttpException('POST $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }
}
