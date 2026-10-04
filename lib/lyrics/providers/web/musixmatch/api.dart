// Ported from Lyricify.Lyrics.Helper/Providers/Web/MusixMatch/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../../http/lyrics_http.dart';
import '../../../json_utils.dart';
import '../base_api.dart';
import 'api_options.dart';
import 'response.dart';

class Api extends BaseApi {
  static const int requestRetryCount = 5;
  static const int resultRetryCount = 5;

  late final ApiOptions options;
  final _AsyncLock _requestLock = _AsyncLock();
  final _AsyncLock _tokenLock = _AsyncLock();
  DateTime lastRequestUtc = DateTime.fromMillisecondsSinceEpoch(0);
  String? userToken;

  @override
  String? get httpRefer => null;

  @override
  Map<String, String>? get additionalHeaders => null;

  @override
  String? get httpUserAgent => options.userAgent;

  @override
  String? get httpCookie => options.cookie;

  Api([void Function(ApiOptions)? configure]) {
    options = ApiOptions();
    configure?.call(options);
    _validateOptions(options);
  }

  void setUserToken(String token) {
    userToken = _isUsableToken(token) ? token : null;
  }

  String? getUserToken() {
    return userToken;
  }

  Future<GetTokenResponse?> getToken() async {
    final response = await requestTokenAsync();
    return response == null
        ? null
        : decodeAs(jencode(response), GetTokenResponse.fromJson);
  }

  Future<GetTrackResponse?> getTrack(String track, String artist,
      [int? duration]) async {
    final tracks = await searchTracksAsync(null, track, artist, duration);
    final result = tracks.isEmpty ? null : tracks.first;
    if (result == null) {
      return null;
    }

    return GetTrackResponse(
      message: GetTrackMessageContent(
        header: GetTrackHeader(
          statusCode: 200,
          executeTime: 0,
          confidence: 1000,
          mode: '',
          cached: 0,
          hint: '',
        ),
        body: GetTrackBody(
          track: result,
        ),
      ),
    );
  }

  Future<List<GetTrackTrack>> searchTracksAsync(
    String? keyword,
    String? track,
    String? artist,
    int? duration,
  ) async {
    final parameters = <String>[
      'page_size=10',
      'page=1',
      's_track_rating=desc',
    ];
    _addParameter(parameters, 'q', keyword);
    _addParameter(parameters, 'q_track', track);
    _addParameter(parameters, 'q_artist', artist);
    if (duration != null && duration > 0) {
      parameters.add('q_duration=$duration');
    }

    final request = 'track.search?${parameters.join('&')}';
    for (var attempt = 0; attempt < resultRetryCount; attempt++) {
      final response = await sendApiRequestAsync(request);
      final trackList = jget(getBody(response), 'track_list');
      if (trackList is List) {
        final results = <GetTrackTrack>[];
        for (final item in trackList) {
          final track = jget(item, 'track');
          if (track is Map) {
            results.add(GetTrackTrack.fromJson(asObj(track)));
          }
        }
        if (results.isNotEmpty &&
            _hasRelatedResult(results, keyword, track, artist)) {
          return results;
        }
      }

      if (attempt + 1 < resultRetryCount) {
        await _delayBeforeResultRetryAsync(attempt);
      }
    }

    return <GetTrackTrack>[];
  }

  Future<GetTrackTrack?> resolveTrackAsync(String identifier) async {
    final trackId = int.tryParse(identifier);
    if (trackId != null) {
      final response =
          await sendApiRequestAsync('track.get?track_id=$trackId');
      final trackNode = jget(getBody(response), 'track');
      var track =
          trackNode is Map ? GetTrackTrack.fromJson(asObj(trackNode)) : null;
      if (track?.trackId == trackId) {
        return track;
      }

      track = _getMatchedTrack(await _getLyricsResponseAsync(trackId));
      return track?.trackId == trackId ? track : null;
    }

    final vanity = normalizeVanity(identifier);
    final parts = _splitWithLimit(vanity, '/', 2);
    if (parts.length != 2) {
      return null;
    }

    final artist = decodeVanityPart(parts[0]);
    final title = decodeVanityPart(parts[1]);
    final results = await searchTracksAsync(null, title, artist, null);
    for (final result in results) {
      if (normalizeVanity(result.commontrackVanityId).toLowerCase() ==
          vanity.toLowerCase()) {
        return result;
      }
    }
    for (final result in results) {
      if (result.trackName.toLowerCase() == title.toLowerCase() &&
          result.artistName
              .split(RegExp(' feat. | & '))
              .where((value) => value.isNotEmpty)
              .any((value) => value.toLowerCase() == artist.toLowerCase())) {
        return result;
      }
    }
    return null;
  }

  Future<GetTrackResponse?> getFullLyrics(String track, String artist,
      [int? duration]) async {
    final response = await getFullLyricsRaw(track, artist, duration);
    return response == null
        ? null
        : decodeAs(response, GetTrackResponse.fromJson);
  }

  Future<String?> getFullLyricsRawById(String trackId,
      [String? expectedVanityId]) async {
    final id = int.tryParse(trackId);
    if (id == null) {
      return null;
    }

    for (var attempt = 0; attempt < resultRetryCount; attempt++) {
      final response = await _getLyricsResponseAsync(id);
      final matched = _getMatchedTrack(response);
      if (matched?.trackId == id &&
          (_isNullOrWhiteSpace(expectedVanityId) ||
              normalizeVanity(matched!.commontrackVanityId).toLowerCase() ==
                  normalizeVanity(expectedVanityId).toLowerCase())) {
        return jencode(response);
      }

      if (attempt + 1 < resultRetryCount) {
        await _delayBeforeResultRetryAsync(attempt);
      }
    }

    return null;
  }

  Future<String?> getFullLyricsRaw(String track, String artist,
      [int? duration]) async {
    final tracks = await searchTracksAsync(null, track, artist, duration);
    final result = tracks.isEmpty ? null : tracks.first;
    return result == null
        ? null
        : await getFullLyricsRawById(
            result.trackId.toString(), result.commontrackVanityId);
  }

  Future<GetTranslationsResponse?> getTranslations(String trackId,
      [String language = 'zh']) async {
    final response = await getTranslationsRaw(trackId, language);
    return response == null
        ? null
        : decodeAs(response, GetTranslationsResponse.fromJson);
  }

  Future<String?> getTranslationsRaw(String trackId, String language) async {
    final response = await sendApiRequestAsync(
        'crowd.track.translations.get?translation_fields_set=minimal'
        '&selected_language=${_escape(language)}'
        '&track_id=${_escape(trackId)}'
        '&comment_format=text&part=user');
    return response == null ? null : jencode(response);
  }

  Future<Map<String, dynamic>?> _getLyricsResponseAsync(int trackId) {
    return sendApiRequestAsync(
        'macro.subtitles.get?namespace=lyrics_richsynched'
        '&optional_calls=track.richsync'
        '&subtitle_format=lrc'
        '&track_id=$trackId'
        '&f_subtitle_length_max_deviation=40');
  }

  Future<Map<String, dynamic>?> sendApiRequestAsync(String request) async {
    Object? lastError;
    for (var attempt = 0; attempt < requestRetryCount; attempt++) {
      try {
        final token = await ensureUserTokenAsync();
        final separator = request.contains('?') ? '&' : '?';
        final url = '${options.apiBaseUrl}'
            '$request$separator'
            'usertoken=${_escape(token)}'
            '&format=json'
            '&app_id=${_escape(options.appId)}'
            '&t=${_escape(options.requestIdFactory())}';
        final response = await getResponseAsync(url);
        if (_isNullOrWhiteSpace(response.body)) {
          throw LyricsHttpException(
              'Musixmatch returned HTTP ${response.statusCode}.',
              statusCode: response.statusCode);
        }

        final json = asObj(jsonDecode(response.body));
        final header = jget(json, 'message.header');
        final statusCode = asIntOrNull(jget(header, 'status_code'));
        final hint = asStr(jget(header, 'hint'));
        if (statusCode == 404) {
          return json;
        }
        if (!response.ok) {
          throw LyricsHttpException(
              'Musixmatch returned HTTP ${response.statusCode}.',
              statusCode: response.statusCode);
        }
        if (statusCode == 200) {
          return json;
        }

        if (statusCode == 401 && hint.toLowerCase() == 'renew') {
          _invalidateToken();
        } else if (statusCode == 401 && hint.toLowerCase() == 'captcha') {
          throw const RequestCaptchaException();
        }
        lastError = LyricsHttpException(
            'Musixmatch returned API status ${statusCode?.toString() ?? 'unknown'}'
            '${_isNullOrWhiteSpace(hint) ? '.' : ' ($hint).'}');
      } on RequestCaptchaException {
        rethrow;
      } catch (ex) {
        lastError = ex;
      }

      if (attempt + 1 < requestRetryCount) {
        await _delayBeforeRequestRetryAsync(attempt);
      }
    }

    throw LyricsHttpException(
      'Musixmatch request failed after all retries.',
      statusCode: lastError is LyricsHttpException
          ? lastError.statusCode
          : null,
    );
  }

  Future<String> ensureUserTokenAsync() async {
    if (_isUsableToken(userToken)) {
      return userToken!;
    }

    await _tokenLock.acquire();
    try {
      if (_isUsableToken(userToken)) {
        return userToken!;
      }

      final response = await requestTokenAsync();
      final token = asStr(jget(response, 'message.body.user_token'));
      if (_isUsableToken(token)) {
        userToken = token;
        return token;
      }

      throw StateError('Musixmatch token request failed.');
    } finally {
      _tokenLock.release();
    }
  }

  Future<Map<String, dynamic>?> requestTokenAsync() async {
    final url = '${options.apiBaseUrl}'
        'token.get?user_language=en'
        '&app_id=${_escape(options.appId)}'
        '&t=${_escape(options.requestIdFactory())}';
    final response = await getResponseAsync(url);
    if (!response.ok) {
      throw LyricsHttpException(
          'Musixmatch returned HTTP ${response.statusCode}.',
          statusCode: response.statusCode);
    }
    if (_isNullOrWhiteSpace(response.body)) {
      return null;
    }

    final json = asObj(jsonDecode(response.body));
    final header = jget(json, 'message.header');
    final statusCode = asIntOrNull(jget(header, 'status_code'));
    final hint = asStr(jget(header, 'hint'));
    if (statusCode == 401 && hint.toLowerCase() == 'captcha') {
      throw const RequestCaptchaException();
    }
    if (statusCode != 200) {
      throw LyricsHttpException(
          'Musixmatch returned API status ${statusCode?.toString() ?? 'unknown'}'
          '${_isNullOrWhiteSpace(hint) ? '.' : ' ($hint).'}');
    }
    return json;
  }

  ///
  @override
  Future<LyricsHttpResponse> getResponseAsync(String url) async {
    await _requestLock.acquire();
    try {
      final elapsed = DateTime.now().toUtc().difference(lastRequestUtc);
      if (elapsed < const Duration(milliseconds: 250)) {
        await Future<void>.delayed(
            const Duration(milliseconds: 250) - elapsed);
      }

      final headers = <String, String>{};
      if (!_isNullOrWhiteSpace(options.userAgent)) {
        headers['User-Agent'] = options.userAgent!;
      }
      if (!_isNullOrWhiteSpace(options.cookie)) {
        headers['Cookie'] = options.cookie!;
      }

      final response = await BaseApi.httpClient.send(
        method: 'GET',
        url: Uri.parse(url),
        headers: headers,
        timeout: options.timeout,
      );
      lastRequestUtc = DateTime.now().toUtc();
      return response;
    } finally {
      _requestLock.release();
    }
  }

  // PORT NOTE: 上游 `GetMatchedTrack`（`MusixMatch/Api.cs:469-476`）用的是字面量索引
  // `calls?["matcher.track.get"]`——这个 key 自身带点号，不能用按 '.' 拆路径的
  // `jget`，否则永远取不到（会去找 macro_calls.matcher.track.get.message…）。
  static GetTrackTrack? _getMatchedTrack(Map<String, dynamic>? response) {
    final calls = jget(getBody(response), 'macro_calls');
    final matcher = calls is Map ? calls['matcher.track.get'] : null;
    final message = matcher is Map ? matcher['message'] : null;
    final body = message is Map ? message['body'] : null;
    final track = body is Map ? body['track'] : null;
    return track is Map ? GetTrackTrack.fromJson(asObj(track)) : null;
  }

  static Map<String, dynamic>? getBody(Map<String, dynamic>? response) {
    final body = response == null ? null : response['message'];
    if (body is! Map) return null;
    final inner = body['body'];
    return inner is Map ? inner.cast<String, dynamic>() : null;
  }

  static bool _isUsableToken(String? token) {
    return !_isNullOrWhiteSpace(token) &&
        token != 'null' &&
        token!.split('').any((character) => character != '0');
  }

  void _invalidateToken() {
    userToken = null;
  }

  static Future<void> _delayBeforeRequestRetryAsync(int attempt) {
    final delay = math.min(500 * (1 << attempt), 2000);
    return Future<void>.delayed(Duration(milliseconds: delay));
  }

  static Future<void> _delayBeforeResultRetryAsync(int attempt) {
    return Future<void>.delayed(
        Duration(milliseconds: math.min(200 * (attempt + 1), 800)));
  }

  static void _validateOptions(ApiOptions options) {
    if (_isNullOrWhiteSpace(options.apiBaseUrl)) {
      throw ArgumentError('Musixmatch API base URL is required.');
    }
    if (!options.apiBaseUrl.endsWith('/')) {
      options.apiBaseUrl += '/';
    }
    if (_isNullOrWhiteSpace(options.appId)) {
      throw ArgumentError('Musixmatch app ID is required.');
    }
    if (options.timeout <= Duration.zero) {
      throw ArgumentError.value(options.timeout, 'timeout',
          'Musixmatch request timeout must be greater than zero.');
    }
  }

  static void _addParameter(
      List<String> parameters, String name, String? value) {
    if (!_isNullOrWhiteSpace(value)) {
      parameters.add('$name=${_escape(value!)}');
    }
  }

  static String normalizeVanity(String? value) {
    return _unescape(value ?? '').trim().replaceAll(RegExp(r'^/+|/+$'), '');
  }

  static String decodeVanityPart(String value) {
    return _unescape(value).replaceAll('-', ' ').trim();
  }

  static bool _hasRelatedResult(
    List<GetTrackTrack> results,
    String? keyword,
    String? title,
    String? artist,
  ) {
    final keywordTokens = _tokenize(keyword);
    final titleTokens = _tokenize(title);
    final artistTokens = _tokenize(artist);
    if (keywordTokens.isEmpty && titleTokens.isEmpty && artistTokens.isEmpty) {
      return true;
    }

    for (final result in results) {
      final actualTitle = result.trackName.toLowerCase();
      final actualArtists = result.artistName.toLowerCase();
      if (titleTokens.isNotEmpty &&
          !titleTokens.every(actualTitle.contains)) {
        continue;
      }
      if (artistTokens.isNotEmpty &&
          !artistTokens.any(actualArtists.contains)) {
        continue;
      }

      if (keywordTokens.isEmpty) {
        return true;
      }
      final actual = '$actualTitle $actualArtists';
      final requiredMatches =
          math.max(1, (keywordTokens.length * 0.6).ceil());
      if (keywordTokens.where(actual.contains).length >= requiredMatches) {
        return true;
      }
    }

    return false;
  }

  static List<String> tokenize(String? value) => _tokenize(value);

  static List<String> _tokenize(String? value) {
    return (value ?? '')
        .toLowerCase()
        .split(RegExp(r'[ _\-/,\.\(\)\[\]&]'))
        .where((token) => token.length > 1)
        .toList();
  }

  static String _escape(String value) => Uri.encodeQueryComponent(value);

  static String _unescape(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static List<String> _splitWithLimit(String value, String separator, int count) {
    final result = <String>[];
    var rest = value;
    while (result.length < count - 1) {
      final index = rest.indexOf(separator);
      if (index < 0) break;
      result.add(rest.substring(0, index));
      rest = rest.substring(index + separator.length);
    }
    result.add(rest);
    return result;
  }

  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;
}

class _AsyncLock {
  final List<Completer<void>> _queue = [];
  bool _locked = false;

  Future<void> acquire() {
    if (!_locked) {
      _locked = true;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _queue.add(completer);
    return completer.future;
  }

  void release() {
    if (_queue.isEmpty) {
      _locked = false;
      return;
    }
    final next = _queue.removeAt(0);
    next.complete();
  }
}

/// `RequestCaptchaException([String? requestUrl, String? response])`，
class RequestCaptchaException implements Exception {
  const RequestCaptchaException([this.requestUrl, this.response, this.cause]);

  static const String defaultMessage = 'Hit 401 error with Captcha hint.';

  final String? requestUrl;

  final String? response;

  final Object? cause;

  @override
  String toString() => 'RequestCaptchaException: $defaultMessage';
}
