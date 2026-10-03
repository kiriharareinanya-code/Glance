// Ported from Lyricify.Lyrics.Helper/Providers/Web/SodaMusic/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'dart:math' as math;

import '../../../http/lyrics_http.dart';
import '../../../json_utils.dart';
import '../base_api.dart';
import 'response.dart';

class Api extends BaseApi {
  @override
  String? get httpRefer => 'https://api.qishui.com/';

  @override
  Map<String, String>? get additionalHeaders => null;

  @override
  String? get httpUserAgent => userAgent;

  @override
  String? get httpCookie => null;

  static const String userAgent = 'LunaPC/2.1.0(12292405)';

  static const String searchUserAgent =
      'com.luna.music/100198030 (Linux; U; Android 15; zh_CN_#Hans; ABR-AL80; Build/V417IR;tt-ok/3.12.13.19)';

  static const String webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static final math.Random _random = math.Random();

  static String Function() clockMsFactory =
      () => DateTime.now().toUtc().millisecondsSinceEpoch.toString();

  static final String searchDeviceId = _generateClientId();

  static final String searchInstallId = _generateClientId();

  Future<SearchResult?> search(String keyword) async {
    final query = <String, String>{
      'device_platform': 'android',
      'os': 'android',
      'ssmix': 'a',
      'cdid': '46556f98-1720-4248-83da-62b74b60b46a',
      'channel': 'xiaomi_8478_64',
      'aid': '386088',
      'app_name': 'luna',
      'version_code': '100198030',
      'version_name': '19.8.0',
      'manifest_version_code': '100198030',
      'update_version_code': '100198030',
      'resolution': '1080*1920',
      'dpi': '480',
      'device_type': 'ABR-AL80',
      'device_brand': 'HUAWEI',
      'language': 'zh',
      'os_api': '35',
      'os_version': '15',
      'ac': 'wifi',
      'device_model': 'ABR-AL80',
      'tz_name': 'Asia/Shanghai',
      'tz_offset': '28800',
      'package': 'com.luna.music',
      'sim_region': 'cn',
      'iid': searchInstallId,
      'device_id': searchDeviceId,
      '_rticket': clockMsFactory(),
      'q': keyword,
      'cursor': '0',
      'count': '20',
    };

    final res = await _sodaGet(
      buildUrl('search/track', query),
      <String, String>{'Accept': '*/*', 'User-Agent': searchUserAgent},
    );

    if (res.isEmpty) {
      return null;
    }

    return decodeAs(res, SearchResult.fromJson);
  }

  Future<TrackDetailResult?> getDetail(String id) async {
    try {
      final query = <String, String>{
        'track_id': id,
        'device_platform': 'web',
      };

      final resp = await _sodaGet(
        buildH5Url('seo_track', query),
        <String, String>{
          'Accept': 'application/json',
          'User-Agent': webUserAgent,
        },
      );

      final result = decodeAs(resp, TrackDetailResult.fromJson);

      final seoTrack = result?.seoTrack;
      if (seoTrack != null && result != null) {
        result.track ??= seoTrack.track;
        result.trackPlayer ??= seoTrack.trackPlayer;
      }

      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sodaGet(
    String url,
    Map<String, String> headers,
  ) async {
    final res = await BaseApi.httpClient
        .send(method: 'GET', url: Uri.parse(url), headers: headers);
    if (!res.ok) {
      throw LyricsHttpException('GET $url 失败', statusCode: res.statusCode);
    }
    return res.body;
  }

  static String buildUrl(String path, Map<String, String> query) {
    final queryString = query.entries
        .map((pair) => '${_escape(pair.key)}=${_escape(pair.value)}')
        .join('&');
    return 'https://api.qishui.com/luna/$path?$queryString';
  }

  static String buildH5Url(String path, Map<String, String> query) {
    final queryString = query.entries
        .map((pair) => '${_escape(pair.key)}=${_escape(pair.value)}')
        .join('&');
    return 'https://beta-luna.douyin.com/luna/h5/$path?$queryString';
  }

  static String _escape(String value) => Uri.encodeQueryComponent(value);

  static String _generateClientId() {
    return (_random.nextInt(90000000) + 10000000).toString() +
        (_random.nextInt(90000000) + 10000000).toString();
  }
}
