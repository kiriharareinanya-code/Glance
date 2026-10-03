// Ported from Lyricify.Lyrics.Helper/Providers/Web/Spotify/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../http/lyrics_http.dart';
import '../../../json_utils.dart';
import '../base_api.dart';
import 'models.dart';

class Api extends BaseApi {
  @override
  String? get httpRefer => 'https://open.spotify.com/';

  @override
  Map<String, String>? get additionalHeaders {
    final dict = <String, String>{
      'Accept': 'application/json',
      'App-Platform': 'WebPlayer',
      'Origin': 'https://open.spotify.com',
    };

    if (!_isNullOrWhiteSpace(_accessToken)) {
      dict['Authorization'] = 'Bearer $_accessToken';
    }

    return dict;
  }

  static const String tokenUrl = 'https://open.spotify.com/api/token';
  static const String searchUrl = 'https://api.spotify.com/v1/search';
  static const String pathfinderSearchUrl =
      'https://api-partner.spotify.com/pathfinder/v1/query';
  static const String serverTimeUrl =
      'https://open.spotify.com/api/server-time';

  static const List<String> secretKeyUrls = [
    'https://code.thetadev.de/ThetaDev/spotify-secrets/raw/branch/main/secrets/secretDict.json',
    'https://raw.githubusercontent.com/Thereallo1026/spotify-secrets/refs/heads/main/secrets/secretDict.json',
    'https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json',
  ];

  static const String bundledSecretJson =
      '{"59":[123,105,79,70,110,59,52,125,60,49,80,70,89,75,80,86,63,53,123,37,117,49,52,93,77,62,47,86,48,104,68,72],"60":[79,109,69,123,90,65,46,74,94,34,58,48,70,71,92,85,122,63,91,64,87,87],"61":[44,55,47,42,70,40,34,114,76,74,50,111,120,97,75,76,94,102,43,69,49,120,118,80,64,78]}';

  static const String spotifyUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const List<String> pathfinderSearchHashes = [
    '0dff51c99e552b992377a2a6f40d213dc42b62db86ca0bcf16cf3934aec1aae6',
    '75bbf6bfcfdf85b8fc828417bfad92b7cd66bf7f556d85670f4da8292373ebec',
  ];

  static String _spDc = '';
  static String _accessToken = '';
  static int _accessTokenExpirationTimestampMs = 0;

  void setSpDc(String? spDc) {
    _spDc = normalizeSpDc(spDc);
  }

  String getSpDc() => _spDc;

  static String normalizeSpDc(String? spDc) {
    var value = spDc?.trim() ?? '';

    String? cookieValue;
    for (final part in value.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase().startsWith('sp_dc=')) {
        cookieValue = trimmed;
        break;
      }
    }

    if (cookieValue != null) {
      value = cookieValue.substring('sp_dc='.length).trim();
    }

    return value.trim().replaceAll(RegExp(r'^"+|"+$'), '');
  }

  void setAccessToken(String? token, [int expirationTimestampMs = 0]) {
    _accessToken = token?.trim() ?? '';
    _accessTokenExpirationTimestampMs = expirationTimestampMs;
  }

  String getAccessToken() => _accessToken;

  int getAccessTokenExpirationTimestampMs() =>
      _accessTokenExpirationTimestampMs;

  Future<List<SpotifyTrackCandidate>> searchTrackCandidates(
    String song,
    String artist, [
    int limit = 10,
  ]) async {
    await ensureAccessTokenAsync();

    final pathfinderCandidates =
        await searchTrackCandidatesViaPathfinder(song, artist, limit);
    if (pathfinderCandidates.isNotEmpty) {
      return pathfinderCandidates;
    }

    return searchTrackCandidatesViaWebApi(song, artist, limit);
  }

  Future<String> getLyrics(String trackId) async {
    final url = 'https://spclient.wg.spotify.com/color-lyrics/v2/track/$trackId'
        '?format=json&market=from_token';

    return getAuthorizedJsonAsync(url, (headers) {
      headers['User-Agent'] = spotifyUserAgent;
      headers['App-platform'] = 'WebPlayer';
      headers['Authorization'] = 'Bearer ${getAccessToken()}';
    });
  }

  Future<List<SpotifyTrackCandidate>> searchTrackCandidatesViaPathfinder(
      String song, String artist, int limit) async {
    final searchTerm = [song, artist]
        .where((t) => !_isNullOrWhiteSpace(t))
        .join(' ');
    if (_isNullOrWhiteSpace(searchTerm)) {
      return <SpotifyTrackCandidate>[];
    }

    for (final hash in pathfinderSearchHashes) {
      final variablesJson = jencode({
        'searchTerm': searchTerm,
        'offset': 0,
        'limit': limit,
        'numberOfTopResults': limit < 5 ? limit : 5,
      });
      final extensionsJson = jencode({
        'persistedQuery': {
          'version': 1,
          'sha256Hash': hash,
        },
      });

      final url = '$pathfinderSearchUrl'
          '?operationName=searchDesktop'
          '&variables=${_urlEncode(variablesJson)}'
          '&extensions=${_urlEncode(extensionsJson)}';

      var response = await _sendAsync(url, (headers) {
        headers['User-Agent'] = spotifyUserAgent;
        headers['Accept'] = 'application/json';
        headers['Authorization'] = 'Bearer ${getAccessToken()}';
      });

      var json = response.body;
      if (response.statusCode == 401 || response.statusCode == 403) {
        await refreshAccessTokenAsync();

        response = await _sendAsync(url, (headers) {
          headers['User-Agent'] = spotifyUserAgent;
          headers['Accept'] = 'application/json';
          headers['Authorization'] = 'Bearer ${getAccessToken()}';
        });

        json = response.body;
      }

      if (response.statusCode == 404 || response.statusCode == 400) {
        continue;
      }

      if (!response.ok) {
        throw LyricsHttpException('GET $url 失败',
            statusCode: response.statusCode);
      }

      final parsed = parsePathfinderTrackCandidates(json);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    return <SpotifyTrackCandidate>[];
  }

  Future<List<SpotifyTrackCandidate>> searchTrackCandidatesViaWebApi(
      String song, String artist, int limit) async {
    final keyword =
        [song, artist].where((t) => !_isNullOrWhiteSpace(t)).join(' ');
    final url = '$searchUrl'
        '?q=${_urlEncode(keyword)}'
        '&type=track&limit=$limit&market=from_token';

    final json = await getAuthorizedJsonAsync(url, (headers) {
      headers['User-Agent'] = spotifyUserAgent;
      headers['Authorization'] = 'Bearer ${getAccessToken()}';
    });

    final result = decodeAs(json, SearchResponse.fromJson);
    final items = result?.tracks?.items;
    if (items == null) return <SpotifyTrackCandidate>[];

    return items
        .map((t) => SpotifyTrackCandidate(
              id: t.id,
              title: t.name,
              artistName: (t.artists ?? <SearchArtistItem>[])
                  .map((a) => a.name)
                  .where((a) => !_isNullOrWhiteSpace(a))
                  .join(', '),
              albumName: t.album?.name ?? '',
              durationMs: t.durationMs,
            ))
        .where((t) => !_isNullOrWhiteSpace(t.id) && !_isNullOrWhiteSpace(t.title))
        .toList();
  }

  static List<SpotifyTrackCandidate> parsePathfinderTrackCandidates(String json) {
    try {
      final root = asObj(jsonDecode(json));
      final arrays = <List<dynamic>?>[
        _selectArray(root, 'data.searchV2.tracks.items'),
        _selectArray(root, 'data.search.tracks.items'),
      ];

      for (final array in arrays) {
        if (array == null || array.isEmpty) continue;

        final parsed = <SpotifyTrackCandidate>[];
        for (final item in array) {
          final candidate = parsePathfinderTrackCandidate(item);
          if (candidate != null) parsed.add(candidate);
        }

        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
    } catch (_) {
    }

    return <SpotifyTrackCandidate>[];
  }

  static SpotifyTrackCandidate? parsePathfinderTrackCandidate(dynamic raw) {
    final dataNode = _member(raw, 'data') ?? raw;
    final id = _valueString(dataNode, 'id') ?? spotifyIdFromUri(_valueString(dataNode, 'uri'));
    final title = _valueString(dataNode, 'name') ??
        _valueString(_member(dataNode, 'track'), 'name') ??
        '';
    final albumName = _valueString(_member(dataNode, 'albumOfTrack'), 'name') ??
        _valueString(_member(dataNode, 'album'), 'name') ??
        '';

    final artistItems = _selectArray(dataNode, 'artists.items') ??
        _selectArray(dataNode, 'track.artists.items') ??
        <dynamic>[];

    final artistNames = <String>[];
    for (final item in artistItems) {
      final name = _valueString(_member(item, 'profile'), 'name') ??
          _valueString(_member(item, 'data'), 'name') ??
          _valueString(_member(_member(item, 'data'), 'profile'), 'name') ??
          _valueString(item, 'name');
      if (name != null && !_isNullOrWhiteSpace(name)) {
        artistNames.add(name);
      }
    }

    if (_isNullOrWhiteSpace(id) || _isNullOrWhiteSpace(title)) {
      return null;
    }

    return SpotifyTrackCandidate(
      id: id!,
      title: title,
      artistName: artistNames.join(', '),
      albumName: albumName,
      durationMs: null,
    );
  }

  static String? spotifyIdFromUri(String? uri) {
    const prefix = 'spotify:track:';
    if (_isNullOrWhiteSpace(uri) || !uri!.startsWith(prefix)) {
      return null;
    }

    return uri.substring(prefix.length);
  }

  Future<String> getAuthorizedJsonAsync(
      String url, void Function(Map<String, String> headers) configureRequest) async {
    await ensureAccessTokenAsync();

    var response = await _sendAsync(url, configureRequest);
    if (response.ok) {
      return response.body;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await refreshAccessTokenAsync();

      response = await _sendAsync(url, configureRequest);
      if (response.ok) {
        return response.body;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError('Spotify access token is invalid or expired.');
      }
    }

    if (!response.ok) {
      throw LyricsHttpException('GET $url 失败', statusCode: response.statusCode);
    }
    return response.body;
  }

  static Future<LyricsHttpResponse> _sendAsync(
      String url, void Function(Map<String, String> headers) configureRequest) {
    final headers = <String, String>{};
    configureRequest(headers);
    return BaseApi.httpClient
        .send(method: 'GET', url: Uri.parse(url), headers: headers);
  }

  Future<void> ensureAccessTokenAsync() async {
    final spDc = _spDc;
    final accessToken = _accessToken;
    final expirationTimestampMs = _accessTokenExpirationTimestampMs;

    if (_isNullOrWhiteSpace(spDc)) {
      throw StateError('Spotify sp_dc is not configured.');
    }

    if (!_isNullOrWhiteSpace(accessToken) &&
        DateTime.now().toUtc().millisecondsSinceEpoch <
            expirationTimestampMs) {
      return;
    }

    await refreshAccessTokenAsync();
  }

  Future<void> refreshAccessTokenAsync() async {
    final spDc = _spDc;

    if (_isNullOrWhiteSpace(spDc)) {
      throw StateError('Spotify sp_dc is not configured.');
    }

    SpotifyTokenResponse payload;
    try {
      // Preserve the platform-selected handler and its existing session
      // for callers whose token exchange already works.
      payload = await requestAccessTokenAsync(spDc: spDc);
    } on StateError {
      // Android's native handler can overwrite the manual Cookie header
      // with server-time cookies. Retry authentication once with sp_dc
      // in the same cookie container as those server-issued cookies.
      //
      payload = await requestAccessTokenAsync(spDc: spDc);
    }

    _accessToken = payload.accessToken!;
    _accessTokenExpirationTimestampMs = payload.accessTokenExpirationTimestampMs;
  }

  Future<SpotifyTokenResponse> requestAccessTokenAsync({String? spDc}) async {
    var parameters = await buildTokenParametersAsync();
    var response = await sendTokenRequestAsync(parameters, spDc);
    if (response.statusCode == 400) {
      parameters = await buildTokenParametersAsync(useLegacyParameters: true);
      response = await sendTokenRequestAsync(parameters, spDc);
    }

    final text = response.body;

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw StateError('Spotify sp_dc is invalid.');
    }

    if (!response.ok) {
      throw LyricsHttpException(
        'Failed to refresh Spotify access token. HTTP ${response.statusCode}: ${previewText(text)}',
        statusCode: response.statusCode,
      );
    }

    final payload = decodeAs(text, SpotifyTokenResponse.fromJson);
    if (payload?.isAnonymous == true || _isNullOrWhiteSpace(payload?.accessToken)) {
      throw StateError('Spotify sp_dc is invalid.');
    }

    return payload!;
  }

  static Future<LyricsHttpResponse> sendTokenRequestAsync(
      List<MapEntry<String, String>> parameters, String? spDc) async {
    final query = parameters
        .map((t) => '${_urlEncode(t.key)}=${_urlEncode(t.value)}')
        .join('&');
    final headers = <String, String>{
      'User-Agent': spotifyUserAgent,
      'Accept': 'application/json',
      'App-Platform': 'WebPlayer',
      'Origin': 'https://open.spotify.com',
      'Referer': 'https://open.spotify.com/',
    };
    if (!_isNullOrWhiteSpace(spDc)) {
      headers['Cookie'] = 'sp_dc=$spDc';
    }
    return BaseApi.httpClient.send(
      method: 'GET',
      url: Uri.parse('$tokenUrl?$query'),
      headers: headers,
    );
  }

  Future<List<MapEntry<String, String>>> buildTokenParametersAsync(
      {bool useLegacyParameters = false}) async {
    final serverTimeResponse = await BaseApi.httpClient.send(
      method: 'GET',
      url: Uri.parse(serverTimeUrl),
    );
    if (!serverTimeResponse.ok) {
      throw LyricsHttpException('GET $serverTimeUrl 失败',
          statusCode: serverTimeResponse.statusCode);
    }
    final serverTimeText = serverTimeResponse.body;
    final serverTime = asIntOrNull(jget(asObj(jsonDecode(serverTimeText)), 'serverTime'));
    if (serverTime == null) {
      throw StateError('Spotify server time is invalid.');
    }

    final secret = await fetchLatestSecretAsync();
    final totp = generateTotp(serverTime, secret.secret);
    final parameters = <MapEntry<String, String>>[
      MapEntry('reason', useLegacyParameters ? 'transport' : 'init'),
      const MapEntry('productType', 'web-player'),
      MapEntry('totp', totp),
      MapEntry('totpVer', secret.version),
      MapEntry('totpServer', totp),
    ];

    if (useLegacyParameters) {
      parameters.add(MapEntry(
          'ts', (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString()));
    }

    return parameters;
  }

  ///
  Future<({String secret, String version})> fetchLatestSecretAsync() async {
    for (final secretKeyUrl in secretKeyUrls) {
      try {
        final response = await BaseApi.httpClient.send(
          method: 'GET',
          url: Uri.parse(secretKeyUrl),
        );
        if (!response.ok) {
          throw LyricsHttpException('GET $secretKeyUrl 失败',
              statusCode: response.statusCode);
        }
        final raw = response.body;
        final parsed = tryParseSecretPayload(raw);
        if (parsed != null) {
          return parsed;
        }
      } catch (_) {
      }
    }

    final fallback = tryParseSecretPayload(bundledSecretJson);
    if (fallback != null) {
      return fallback;
    }

    throw StateError('Spotify secret payload is invalid.');
  }

  static ({String secret, String version})? tryParseSecretPayload(String raw) {
    try {
      final json = asObj(jsonDecode(raw));
      final numericKeys = json.keys.where((k) => int.tryParse(k) != null).toList()
        ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));

      if (numericKeys.isEmpty) return null;
      final latestKey = numericKeys.first;
      final array = json[latestKey];
      if (array is! List) return null;

      final transformed = <String>[];
      for (var index = 0; index < array.length; index++) {
        final value = asInt(array[index]);
        transformed.add((value ^ ((index % 33) + 9)).toString());
      }

      return (secret: transformed.join(), version: latestKey);
    } catch (_) {
      return null;
    }
  }

  static String generateTotp(int serverTimeSeconds, String secret) {
    const period = 30;
    const digits = 6;

    final counter = serverTimeSeconds ~/ period;
    final counterBytes = _hostToNetworkOrder(counter);
    final hmac = Hmac(sha1, utf8.encode(secret));
    final hash = hmac.convert(counterBytes).bytes;

    final offset = hash[hash.length - 1] & 0x0f;
    final binary = ((hash[offset] & 0x7f) << 24) |
        (hash[offset + 1] << 16) |
        (hash[offset + 2] << 8) |
        hash[offset + 3];
    final code = binary % _pow10(digits);
    return code.toString().padLeft(digits, '0');
  }

  static int _pow10(int digits) {
    var result = 1;
    for (var i = 0; i < digits; i++) {
      result *= 10;
    }
    return result;
  }

  static List<int> _hostToNetworkOrder(int value) {
    final bytes = ByteData(8)..setInt64(0, value, Endian.big);
    return bytes.buffer.asUint8List().toList();
  }

  static String? previewText(String? text) {
    if (_isNullOrWhiteSpace(text)) return null;
    final trimmed = text!.trim();
    return trimmed.length <= 180 ? trimmed : trimmed.substring(0, 180);
  }

  ///
  static String _urlEncode(String value) => Uri.encodeQueryComponent(value);


  static dynamic _member(dynamic node, String name) {
    if (node is Map) return node[name];
    return null;
  }

  static String? _valueString(dynamic node, String name) {
    if (node == null) return null;
    final dynamic value = node is Map ? node[name] : null;
    if (value == null) return null;
    if (value is String) return value;
    return '$value';
  }

  static List<dynamic>? _selectArray(dynamic root, String path) {
    final value = jget(root, path);
    return value is List ? value : null;
  }

  static bool _isNullOrWhiteSpace(String? value) =>
      value == null || value.trim().isEmpty;
}
