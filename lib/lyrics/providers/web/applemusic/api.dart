// Ported from Lyricify.Lyrics.Helper/Providers/Web/AppleMusic/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
/// Apple Music API (amp-api.music.apple.com)
///
library;

import 'dart:convert';

import '../../../http/lyrics_http.dart';
import '../../../json_utils.dart';
import '../base_api.dart';
import 'response.dart';

class Api extends BaseApi {
  @override
  String? get httpRefer => 'https://music.apple.com/';

  @override
  Map<String, String>? get additionalHeaders {
    ensureInitSync(); // 只做轻量检查；真正网络初始化在 EnsureInitAsync
    final dict = <String, String>{
      'Origin': 'https://music.apple.com',
      'Accept': 'application/json',
    };

    if (!_isNullOrWhiteSpace(_accessToken)) {
      dict['Authorization'] = 'Bearer $_accessToken';
    }

    if (!_isNullOrWhiteSpace(_acceptLanguage)) {
      dict['Accept-Language'] = _acceptLanguage!;
    }

    if (!_isNullOrWhiteSpace(_mediaUserToken)) {
      dict['media-user-token'] = _mediaUserToken!;
    }

    return dict;
  }

  static bool _inited = false;
  static String _accessToken = '';

  static String _storefront = 'us';
  static String _language = 'en-US';
  static String? _acceptLanguage = 'en-US,en;q=0.9';

  static String? _mediaUserToken;
  static String? _cachedMut;

  void setMediaUserToken(String token) {
    if (_isNullOrWhiteSpace(token)) return;

    if (token.trim() == _mediaUserToken) {
      return;
    }

    _mediaUserToken = token.trim();
    _inited = false; // token 变化，下一次请求会刷新 storefront/language
  }

  void setAccessToken(String? token) {
    _accessToken = token?.trim() ?? '';
  }

  String getAccessToken() => _accessToken;

  void setStorefrontCache(String storefront,
      [String? language, String? mediaUserToken]) {
    if (_isNullOrWhiteSpace(storefront)) return;

    _storefront = storefront.trim();
    _language = _isNullOrWhiteSpace(language) ? 'en-US' : language!.trim();
    _acceptLanguage = '$_language,en;q=0.9';
    _cachedMut =
        _isNullOrWhiteSpace(mediaUserToken) ? null : mediaUserToken!.trim();
    _inited = true;
  }

  String getStorefront() => _storefront;

  String getLanguage() => _language;

  static void ensureInitSync() {
    if (_isNullOrWhiteSpace(_storefront)) _storefront = 'us';
    if (_isNullOrWhiteSpace(_language)) _language = 'en-US';
    if (_isNullOrWhiteSpace(_acceptLanguage)) {
      _acceptLanguage = '$_language,en;q=0.9';
    }
  }

  Future<void> ensureInitAsync() async {
    final mut = _mediaUserToken;
    final accessToken = _accessToken;
    final needRefreshAccessToken = isAccessTokenRefreshRequired(accessToken);
    final needInit = !_inited ||
        needRefreshAccessToken ||
        !(_cachedMut == mut);

    if (!needInit) return;

    if (needRefreshAccessToken) {
      await refreshAccessTokenAsync();
    }

    if (!_isNullOrWhiteSpace(mut)) {
      try {
        await fetchStorefrontAsync(mut!);
      } catch (_) {
        _storefront = 'us';
        _language = 'en-US';
        _acceptLanguage = '$_language,en;q=0.9';
      }
    } else {
      _storefront = 'us';
      _language = 'en-US';
      _acceptLanguage = '$_language,en;q=0.9';
    }

    _cachedMut = mut;
    _inited = true;
  }

  Future<void> refreshAccessTokenAsync() async {
    final accessToken = await getAccessTokenAsync();
    _accessToken = accessToken;
  }

  void clearAccessToken() {
    _accessToken = '';
  }

  static bool isAccessTokenRefreshRequired(String? accessToken) {
    if (_isNullOrWhiteSpace(accessToken)) return true;
    final parsed = _tryReadJwt(accessToken!);
    if (parsed == null) return true;
    return _isJwtRefreshRequired(parsed.payload);
  }

  static String normalizeBase64(String value) {
    value = value.replaceAll('-', '+').replaceAll('_', '/');
    return value.padRight(value.length + (4 - value.length % 4) % 4, '=');
  }

  static ({Map<String, dynamic> header, Map<String, dynamic> payload})?
      tryReadJwt(String token) => _tryReadJwt(token);

  static ({Map<String, dynamic> header, Map<String, dynamic> payload})?
      _tryReadJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;

      final headerJson = utf8.decode(
          base64.decode(normalizeBase64(parts[0])),
          allowMalformed: true);
      final payloadJson = utf8.decode(
          base64.decode(normalizeBase64(parts[1])),
          allowMalformed: true);

      return (
        header: asObj(jsonDecode(headerJson)),
        payload: asObj(jsonDecode(payloadJson)),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isJwtRefreshRequired(Map<String, dynamic> payload) {
    final exp = asIntOrNull(payload['exp']);
    if (exp == null) return true;
    final expTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    return !DateTime.now().toUtc().isBefore(expTime.subtract(
      const Duration(minutes: 1),
    ));
  }

  ///
  /// 上游 `ShouldRefreshAccessToken`（`AppleMusic/Api.cs:250-259`）：
  /// 401 一律刷新；403 只有在 `ContentType.MediaType == "application/octet-stream"`
  /// 且 `ContentLength.GetValueOrDefault() == 0`（响应没带 Content-Length 也算 0）时才刷新。
  static bool shouldRefreshAccessToken(LyricsHttpResponse response) {
    if (response.statusCode == 401) return true;
    if (response.statusCode != 403) return false;

    final mediaType = (response.contentType ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    return mediaType == 'application/octet-stream' &&
        (response.contentLength ?? 0) == 0;
  }

  Future<String> getAsyncWithAccessTokenRetry(String url,
      {bool allowRetry = true}) async {
    var response = await _getResponseAsync(url);
    if (response.ok) {
      return response.body;
    }

    if (allowRetry && shouldRefreshAccessToken(response)) {
      clearAccessToken();
      await refreshAccessTokenAsync();

      response = await _getResponseAsync(url);
      if (response.ok) {
        return response.body;
      }
    }

    throw LyricsHttpException('GET $url 失败', statusCode: response.statusCode);
  }

  Future<LyricsHttpResponse> _getResponseAsync(String url) =>
      BaseApi.httpClient.send(
        method: 'GET',
        url: Uri.parse(url),
        headers: _instanceHeaders(),
      );

  Map<String, String> _instanceHeaders() {
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
    return headers;
  }

  Future<String> getAccessTokenAsync() async {
    final html = await getAsync('https://music.apple.com/us/browse');
    final jsUrls = findIndexScriptUrls(html);
    if (jsUrls.isEmpty) {
      throw Exception('AppleMusic: Failed to find index*.js');
    }

    for (final jsUrl in jsUrls) {
      final js = await getAsync(jsUrl);
      final token = findAccessTokenInScript(js);
      if (!_isNullOrWhiteSpace(token)) return token!;
    }

    throw Exception('AppleMusic: Failed to find access token');
  }

  static final RegExp _indexScriptUrlRegex = RegExp(
    r'(?<url>(?:https://music\.apple\.com)?/?assets/index(?!-legacy)[^'
    "'"
    r'<>\s]*?\.js)',
    caseSensitive: false,
  );

  static final RegExp _indexScriptUrlFallbackRegex = RegExp(
    r'(?<url>(?:https://music\.apple\.com)?/?assets/index[^'
    "'"
    r'<>\s]*?\.js)',
    caseSensitive: false,
  );

  static final RegExp _accessTokenRegex =
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');

  static List<String> findIndexScriptUrls(String html) {
    var urls = _matchNamedUrl(html, _indexScriptUrlRegex)
        .map(normalizeAppleMusicAssetUrl)
        .where((x) => !_isNullOrWhiteSpace(x))
        .toList();
    urls = _distinctCaseInsensitive(urls);

    if (urls.isNotEmpty) return urls;

    var fallback = _matchNamedUrl(html, _indexScriptUrlFallbackRegex)
        .map(normalizeAppleMusicAssetUrl)
        .where((x) => !_isNullOrWhiteSpace(x))
        .toList();
    return _distinctCaseInsensitive(fallback);
  }

  static List<String> _matchNamedUrl(String input, RegExp regex) => [
        for (final m in regex.allMatches(input))
          if (m.groupCount >= 1) m.group(1) ?? ''
      ];

  static List<String> _distinctCaseInsensitive(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    return result;
  }

  static String normalizeAppleMusicAssetUrl(String url) {
    url = (url).trim();
    if (url.toLowerCase().startsWith('https://')) return url;
    if (url.startsWith('/')) return 'https://music.apple.com$url';
    return 'https://music.apple.com/$url';
  }

  static String? findAccessTokenInScript(String js) {
    final tokens = <String>[];
    for (final m in _accessTokenRegex.allMatches(js)) {
      if (!tokens.contains(m.group(0)!)) tokens.add(m.group(0)!);
    }

    final scored = <({String token, int score})>[
      for (final token in tokens)
        (token: token, score: getAccessTokenScore(token))
    ]..retainWhere((x) => x.score >= 0);

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.isEmpty ? null : scored.first.token;
  }

  static int getAccessTokenScore(String token) {
    final parsed = _tryReadJwt(token);
    if (parsed == null || _isJwtRefreshRequired(parsed.payload)) return -1;

    var score = 0;
    final kid = asStr(parsed.header['kid']);
    final issuer = asStr(parsed.payload['iss']);

    if (kid.toLowerCase() == 'webplaykid') score += 100;
    if (issuer.toLowerCase() == 'ampwebplay') score += 100;
    if (parsed.payload['root_https_origin'] != null) score += 10;

    return score;
  }

  Future<void> fetchStorefrontAsync(String mediaUserToken) async {
    _mediaUserToken = mediaUserToken;

    final json = await getAsyncWithAccessTokenRetry(
        'https://amp-api.music.apple.com/v1/me/storefront');
    final resp = decodeAs(json, StorefrontResponse.fromJson);

    final data = resp?.data;
    if (data == null || data.isEmpty) {
      throw Exception('AppleMusic: storefront data empty');
    }

    var storefront = data[0].id;
    var language = data[0].attributes?.defaultLanguageTag;

    if (_isNullOrWhiteSpace(storefront)) {
      throw Exception('AppleMusic: invalid storefront');
    }
    if (_isNullOrWhiteSpace(language)) language = 'en-US';

    _storefront = storefront;
    _language = language!;
    _acceptLanguage = '$_language,en;q=0.9';
  }

  Future<SearchResponse?> search(String keyword, [int limit = 20]) async {
    await ensureInitAsync();

    final storefront = _storefront;
    final language = _language;

    final url = 'https://amp-api.music.apple.com/v1/catalog/$storefront/search'
        '?term=${_escape(keyword)}&types=songs&limit=$limit'
        '&l=${_escape(language)}';

    final json = await getAsyncWithAccessTokenRetry(url);
    return decodeAs(json, SearchResponse.fromJson);
  }

  Future<LyricResponse?> getLyrics(String songId) async {
    await ensureInitAsync();

    final storefront = _storefront;

    //var url =
    //    $"https://amp-api.music.apple.com/v1/catalog/{storefront}/songs/{songId}" +
    //    $"?include[songs]=syllable-lyrics&l={WebUtility.UrlEncode(language)}&extend=ttmlLocalizations";

    final url = 'https://amp-api.music.apple.com/v1/catalog/$storefront/songs/'
        '$songId'
        '?include[songs]=syllable-lyrics&l=${_escape('zh-hans-cn')}'
        '&extend=ttmlLocalizations';

    final json = await getAsyncWithAccessTokenRetry(url);
    final resp = decodeAs(json, LyricResponse.fromJson);

    resp?.normalizeTtml();
    return resp;
  }

  static String _escape(String value) => Uri.encodeQueryComponent(value);

  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;
}
