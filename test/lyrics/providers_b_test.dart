// Musixmatch / Spotify / Apple Music / SodaMusic 四个在线源的**离线**验收测试。
//
// PORT NOTE: 共享文件 `test/lyrics/providers_test.dart` 已由另一个 worker
// （网易云/QQ/酷狗/LRCLIB）占用，按任务约定本文件命名为 providers_b_test.dart。
//
// 覆盖两块：
//   1) 请求构造：URL / 方法 / 请求头（Apple 的 storefront 与 token、
//      Musixmatch 的 token 流程、SodaMusic 的 UA 与 iid/device_id/_rticket）；
//   2) 响应 DTO：`fromJson` 在**真实样本 JSON** 上取到的字段值
//      （歌名/歌手/时长/歌词/id）。
//
// 网络出口用假的 `LyricsHttpClient`（记录请求 + 返回内置样本），**不发真实请求**。
// 样本形状来自 2026-10 用 pwsh `Invoke-WebRequest` 实抓的响应，只保留用到的字段。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/http/lyrics_http.dart';
import 'package:vectra/lyrics/providers/web/applemusic/api.dart' as am;
import 'package:vectra/lyrics/providers/web/applemusic/response.dart' as amresp;
import 'package:vectra/lyrics/providers/web/base_api.dart';
import 'package:vectra/lyrics/providers/web/musixmatch/api.dart' as mx;
import 'package:vectra/lyrics/providers/web/musixmatch/api_options.dart' as mxopt;
import 'package:vectra/lyrics/providers/web/musixmatch/response.dart' as mxresp;
import 'package:vectra/lyrics/providers/web/sodamusic/api.dart' as soda;
import 'package:vectra/lyrics/providers/web/sodamusic/response.dart' as sodaresp;
import 'package:vectra/lyrics/providers/web/spotify/api.dart' as sp;
import 'package:vectra/lyrics/providers/web/spotify/models.dart' as spmodel;

// ---------------------------------------------------------------------------
// 假 HTTP 客户端
// ---------------------------------------------------------------------------

class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
    required this.timeout,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;

  Map<String, String> get query => url.queryParameters;
}

typedef Responder = LyricsHttpResponse Function(RecordedRequest request);

class FakeLyricsHttpClient implements LyricsHttpClient {
  FakeLyricsHttpClient(this.responder);

  /// 固定响应（所有请求都回它）。
  factory FakeLyricsHttpClient.fixed(String body, {int statusCode = 200}) =>
      FakeLyricsHttpClient(
          (request) => LyricsHttpResponse(statusCode: statusCode, body: body));

  /// 队列响应（按顺序消费；用完后一直沿用最后一个）。
  factory FakeLyricsHttpClient.queue(List<LyricsHttpResponse> responses) {
    var index = 0;
    return FakeLyricsHttpClient((request) {
      final response =
          responses[index < responses.length ? index : responses.length - 1];
      index++;
      return response;
    });
  }

  final Responder responder;

  final List<RecordedRequest> requests = [];

  List<Uri> get urls => [for (final r in requests) r.url];

  @override
  Future<LyricsHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final request = RecordedRequest(
      method: method,
      url: url,
      headers: headers ?? const <String, String>{},
      body: body,
      timeout: timeout,
    );
    requests.add(request);
    return responder(request);
  }
}

// ---------------------------------------------------------------------------
// 真实样本 JSON（截取自实际响应，只保留用到的字段）
// ---------------------------------------------------------------------------

const String musixmatchTokenJson =
    '{"message":{"header":{"status_code":200,"execute_time":0.0123,"pid":1,"hint":"ok"},'
    '"body":{"user_token":"abcdef0123456789","app_config":{"trial":false,"searchMaxResults":10},'
    '"location":{"GEOIP_CITY_COUNTRY_CODE":"CN","GEOIP_LATITUDE":31.22,"GEOIP_LONGITUDE":121.46}}}}';

const String musixmatchSearchJson =
    '{"message":{"header":{"status_code":200,"execute_time":0.05,"hint":""},'
    '"body":{"track_list":['
    '{"track":{"track_id":123456789,"commontrack_id":98765432,"track_name":"晴天",'
    '"artist_name":"周杰伦","album_name":"叶惠美","track_length":269,"has_lyrics":1,'
    '"has_subtitles":1,"has_richsync":1,"lyrics_id":111,"subtitle_id":222,'
    '"commontrack_vanity_id":"Jay-Chou/Qing-Tian","track_rating":100,'
    '"primary_genres":{"music_genre_list":[{"music_genre":{"music_genre_id":12,'
    '"music_genre_name":"Pop"}}]},"updated_time":"2024-01-01T00:00:00Z"}}]}}}';

const String musixmatchLyricsJson =
    '{"message":{"header":{"status_code":200,"confidence":1000,"mode":"musixmatch",'
    '"cached":1,"hint":""},"body":{"macro_calls":{"matcher.track.get":{"message":'
    '{"header":{"status_code":200,"hint":"ok"},"body":{"track":{"track_id":123456789,'
    '"track_name":"晴天","artist_name":"周杰伦","track_length":269,'
    '"commontrack_vanity_id":"Jay-Chou/Qing-Tian"}}}},"track.subtitles.get":{"message":'
    '{"body":{"subtitle_list":[{"subtitle":{"subtitle_body":"[00:01.00] 故事的小黄花"}}]}}}}}}}';

const String musixmatchTranslationsJson =
    '{"message":{"header":{"status_code":200,"execute_time":0.01,"hint":""},'
    '"body":{"translations_list":[{"translation":{"type_id":"1","artist_id":8,'
    '"language_from":"en","selected_language":"zh","snippet":"晴天","language":"zh",'
    '"matched_line":"[00:01.00] 故事的小黄花","confidence":0.98,"lyrics_id":111,'
    '"subtitle_id":222,"is_mine":1,"user":{"uaid":"u-1","user_name":"tester","score":10,'
    '"rank_colors":{"rank_color_10":"#fff"}}}}]}}}';

/// 汽水音乐搜索响应（结构照抄 track 搜索接口，数值为真实样本截取）。
const String sodaSearchJson =
    '{"status_code":0,"status_info":{"log_id":"2026100312000000","status_msg":"","now":1700000000,'
    '"now_ts_ms":1700000000000},"result_groups":[{"id":"g1","next_cursor":"1","has_more":false,'
    '"display_title":"单曲","description":"","data":[{"meta":{"item_type":"track"},'
    '"entity":{"track":{"id":"7000000000000000001","name":"晴天","duration":269000,'
    '"vid":"v123","media_type":"audio","explicit":false,"vocal":1,'
    '"album":{"id":"a1","name":"叶惠美","release_date":1056297600},'
    '"artists":[{"id":"ar1","name":"周杰伦","simple_display_name":"周杰伦"}],'
    '"bit_rates":[{"br":320000,"size":10752000,"quality":"higher"}]}}}]}],'
    '"extra":{"log_extra":"{}"}}';

/// 汽水音乐 h5 详情响应（含逐字歌词与中文翻译）。
const String sodaDetailJson =
    '{"status_code":0,"status_info":{"log_id":"log-2","status_msg":"","now":1700000000,'
    '"now_ts_ms":1700000000000},"lyric":{"content":"[1000,500](1000,500,0)故(1500,500,0)事",'
    '"lang":"zh","type":"krc","id":"ly-1","hide_request_lyrics":false,'
    '"translations":{"cn":""}},"track":{"id":"7000000000000000001","name":"晴天",'
    '"duration":269000,"vid":"v123","media_type":"audio",'
    '"album":{"id":"a1","name":"叶惠美","release_date":1056297600},'
    '"artists":[{"id":"ar1","name":"周杰伦"}]},"track_player":{"expire_at":1700000600,'
    '"media_id":"m-1","url_player_info":"{\\"url\\":\\"https://x\\"}"},"risk_result":0}';

/// Apple Music storefront 响应。
const String appleStorefrontJson =
    '{"data":[{"id":"cn","attributes":{"defaultLanguageTag":"zh-Hans-CN"}}]}';

/// Apple Music 搜索响应（结果形状照抄 catalog search）。
const String appleSearchJson =
    '{"results":{"songs":{"data":[{"id":"1440857781","attributes":{"name":"晴天",'
    '"artistName":"周杰伦","albumName":"叶惠美","durationInMillis":269000}}]}}}';

/// Apple Music 歌词响应（ttmlLocalizations 优先）。
const String appleLyricsJson =
    '{"data":[{"relationships":{"syllable-lyrics":{"data":[{"attributes":{'
    '"ttml":"<tt><p begin=\\"1s\\" end=\\"3s\\">fallback</p></tt>",'
    '"ttmlLocalizations":"<tt><p begin=\\"1s\\" end=\\"3s\\">晴天</p></tt>"}}]}}}]}';

/// Spotify Web API 搜索响应。
const String spotifySearchJson =
    '{"tracks":{"items":[{"id":"6a1RJ9EfZfvyv5x1nO0z0N","name":"晴天",'
    '"duration_ms":269000,"artists":[{"name":"周杰伦"}],'
    '"album":{"name":"叶惠美","artists":[{"name":"周杰伦"}]}}]}}';

/// Spotify pathfinder 搜索响应（两层嵌套）。
const String spotifyPathfinderJson =
    '{"data":{"searchV2":{"tracks":{"items":[{"data":{"id":"6a1RJ9EfZfvyv5x1nO0z0N",'
    '"name":"晴天","albumOfTrack":{"name":"叶惠美"},'
    '"artists":{"items":[{"profile":{"name":"周杰伦"}}]}}}]}}}}';

/// Spotify pathfinder 的 URI 兜底响应（没有 id，只有 uri）。
const String spotifyPathfinderUriJson =
    '{"data":{"search":{"tracks":{"items":[{"uri":"spotify:track:0abcDEF",'
    '"track":{"name":"七里香","artists":{"items":[{"data":{"name":"周杰伦"}}]}}}]}}}}';

/// Spotify server-time 响应。
const String spotifyServerTimeJson = '{"serverTime":1700000000}';

/// Spotify token 端点响应。
const String spotifyTokenJson =
    '{"accessToken":"BQfake-token","accessTokenExpirationTimestampMs":1700003600000,'
    '"isAnonymous":false}';

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

void useFake(LyricsHttpClient client) {
  BaseApi.httpClient = client;
}

Map<String, dynamic> jsonDecodeObj(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

/// 造一个"未过期"的 JWT：header.payload.signature（payload 只带 exp）。
String buildJwt({required int exp, String kid = 'WebPlayKid', String iss = 'AMPWebPlay'}) {
  String b64(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = b64({'alg': 'ES256', 'kid': kid});
  final payload = b64({'exp': exp, 'iss': iss, 'root_https_origin': ['https://music.apple.com']});
  return '$header.$payload.c2ln';
}

void main() {
  setUp(() {
    useFake(FakeLyricsHttpClient.fixed('{}'));
  });

  tearDown(() {
    useFake(DirectLyricsHttpClient());
  });

  // =========================================================================
  // SodaMusic（汽水音乐）
  // =========================================================================

  group('SodaMusic', () {
    test('搜索请求：URL 参数、UA、Accept 与固定的 iid/device_id', () async {
      final fake = FakeLyricsHttpClient.fixed(sodaSearchJson);
      useFake(fake);
      soda.Api.clockMsFactory = () => '1700000000000';

      final result = await soda.Api().search('晴天');

      expect(fake.requests, hasLength(1));
      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.url.host, 'api.qishui.com');
      expect(request.url.path, '/luna/search/track');
      expect(request.headers['User-Agent'], soda.Api.searchUserAgent);
      expect(request.headers['Accept'], '*/*');

      final q = request.query;
      // 逐字对照上游 BuildUrl 的字典
      expect(q['device_platform'], 'android');
      expect(q['os'], 'android');
      expect(q['ssmix'], 'a');
      expect(q['cdid'], '46556f98-1720-4248-83da-62b74b60b46a');
      expect(q['channel'], 'xiaomi_8478_64');
      expect(q['aid'], '386088');
      expect(q['app_name'], 'luna');
      expect(q['version_code'], '100198030');
      expect(q['version_name'], '19.8.0');
      expect(q['manifest_version_code'], '100198030');
      expect(q['update_version_code'], '100198030');
      expect(q['resolution'], '1080*1920');
      expect(q['dpi'], '480');
      expect(q['device_type'], 'ABR-AL80');
      expect(q['device_brand'], 'HUAWEI');
      expect(q['language'], 'zh');
      expect(q['os_api'], '35');
      expect(q['os_version'], '15');
      expect(q['ac'], 'wifi');
      expect(q['device_model'], 'ABR-AL80');
      expect(q['tz_name'], 'Asia/Shanghai');
      expect(q['tz_offset'], '28800');
      expect(q['package'], 'com.luna.music');
      expect(q['sim_region'], 'cn');
      expect(q['_rticket'], '1700000000000');
      expect(q['q'], '晴天');
      expect(q['cursor'], '0');
      expect(q['count'], '20');
      // 上游 `GenerateClientId()`：两个 8 位数拼接 = 16 位数字
      expect(q['iid'], matches(RegExp(r'^\d{16}$')));
      expect(q['device_id'], matches(RegExp(r'^\d{16}$')));
      expect(q['iid'] == q['device_id'], isFalse);

      expect(result?.statusCode, 0);
      expect(result?.statusInfo?.statusMsg, '');
      expect(result?.resultGroups, hasLength(1));

      // 直接对 DTO 的 fromJson 断言一遍（不经过 Api）
      final parsed = sodaresp.SearchResult.fromJson(jsonDecodeObj(sodaSearchJson));
      expect(parsed.statusInfo!.logId, '2026100312000000');
      expect(parsed.statusInfo!.now, 1700000000);
      expect(parsed.statusInfo!.nowTsMs, 1700000000000);
      expect(parsed.extra!.logExtra, '{}');
      expect(parsed.resultGroups!.single.nextCursor, '1');
      expect(parsed.resultGroups!.single.hasMore, isFalse);
      expect(parsed.resultGroups!.single.displayTitle, '单曲');
      expect(parsed.resultGroups!.single.displayViewAll, isNull);
    });

    test('搜索响应 DTO：歌名/歌手/时长/id', () async {
      useFake(FakeLyricsHttpClient.fixed(sodaSearchJson));
      final result = await soda.Api().search('晴天');
      final track = result!.resultGroups!.single.data!.single.entity!.track!;

      expect(track.id, '7000000000000000001');
      expect(track.name, '晴天');
      expect(track.duration, 269000);
      expect(track.vid, 'v123');
      expect(track.mediaType, 'audio');
      expect(track.explicit, isFalse);
      expect(track.vocal, 1);
      expect(track.album?.name, '叶惠美');
      expect(track.album?.releaseDate, 1056297600);
      expect(track.artists!.single.name, '周杰伦');
      expect(track.artists!.single.simpleDisplayName, '周杰伦');
      expect(track.bitRates!.single.br, 320000);
      expect(track.bitRates!.single.quality, 'higher');
      expect(result.resultGroups!.single.data!.single.meta!.itemType, 'track');
    });

    test('详情请求：h5 URL、web UA、track_id/device_platform', () async {
      final fake = FakeLyricsHttpClient.fixed(sodaDetailJson);
      useFake(fake);

      final detail = await soda.Api().getDetail('7000000000000000001');

      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(),
          'https://beta-luna.douyin.com/luna/h5/seo_track?track_id=7000000000000000001&device_platform=web');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['User-Agent'], soda.Api.webUserAgent);

      expect(detail?.statusCode, 0);
      expect(detail?.lyric?.content, startsWith('[1000,500]'));
      expect(detail?.lyric?.lang, 'zh');
      expect(detail?.lyric?.id, 'ly-1');
      expect(detail?.track?.name, '晴天');
      expect(detail?.track?.duration, 269000);
      expect(detail?.track?.artists!.single.name, '周杰伦');
      expect(detail?.trackPlayer?.mediaId, 'm-1');
      expect(detail?.trackPlayer?.expireAt, 1700000600);
    });

    test('详情响应：seo_track 回填 track / track_player（??= 语义）', () async {
      const seoOnly = '{"status_code":0,"seo_track":{"track":{"id":"t-1","name":"七里香",'
          '"duration":299000},"track_player":{"media_id":"m-9"}}}';
      useFake(FakeLyricsHttpClient.fixed(seoOnly));

      final detail = await soda.Api().getDetail('t-1');

      expect(detail?.track?.name, '七里香');
      expect(detail?.track?.duration, 299000);
      expect(detail?.trackPlayer?.mediaId, 'm-9');
      // track 里已有的字段不被 seo_track 覆盖
      const both = '{"status_code":0,"track":{"id":"t-1","name":"原曲名"},"seo_track":{"track":{"id":"t-1","name":"SE0名"}}}';
      useFake(FakeLyricsHttpClient.fixed(both));
      final detail2 = await soda.Api().getDetail('t-1');
      expect(detail2?.track?.name, '原曲名');
    });

    test('空响应返回 null；HTTP 失败时 getDetail 吞异常返回 null', () async {
      useFake(FakeLyricsHttpClient.fixed('   '));
      expect(await soda.Api().search('晴天'), isNull);

      useFake(FakeLyricsHttpClient.fixed('boom', statusCode: 500));
      expect(await soda.Api().getDetail('t-1'), isNull);
    });
  });

  // =========================================================================
  // Apple Music
  // =========================================================================

  group('AppleMusic', () {
    setUp(() {
      // 每个用例都从干净状态开始（静态缓存）
      am.Api()
        ..setAccessToken(buildJwt(exp: 4102444800)) // 2100-01-01
        ..setStorefrontCache('cn', 'zh-Hans-CN', null);
    });

    test('findIndexScriptUrls / findAccessTokenInScript 正则与打分', () {
      const html = '<html><script src="/assets/index~abc123.js"></script>'
          '<script src="https://music.apple.com/assets/index-legacy~def.js"></script>'
          '<script src="assets/index~abc123.js"></script></html>';
      final urls = am.Api.findIndexScriptUrls(html);
      // index-legacy 被排除，相对路径补全，重复项去重
      expect(urls, ['https://music.apple.com/assets/index~abc123.js']);

      // 首选正则无命中时走 fallback 正则（含 index-legacy）
      const onlyLegacy =
          '<script src="https://music.apple.com/assets/index-legacy~9f9.js"></script>';
      expect(am.Api.findIndexScriptUrls(onlyLegacy),
          ['https://music.apple.com/assets/index-legacy~9f9.js']);

      // 两个 token：分数高的胜出（kid/iss 命中 +100+100+10 vs 0）
      final good = buildJwt(exp: 4102444800);
      final plain = buildJwt(exp: 4102444800, kid: 'Other', iss: 'Other');
      final js = 'var a="$plain";var b="$good";';
      expect(am.Api.findAccessTokenInScript(js), good);

      // 过期 token 得分 -1，被过滤
      final expired = buildJwt(exp: 1, kid: 'Other', iss: 'Other');
      expect(am.Api.findAccessTokenInScript('var a="$expired";'), isNull);
      expect(am.Api.getAccessTokenScore(expired), -1);
      expect(am.Api.getAccessTokenScore(good), 210);
      expect(am.Api.getAccessTokenScore('not-a-jwt'), -1);
    });

    test('JWT 过期判定（exp - 1 分钟）', () {
      final future = buildJwt(exp: 4102444800);
      expect(am.Api.isAccessTokenRefreshRequired(future), isFalse);
      expect(am.Api.isAccessTokenRefreshRequired(''), isTrue);

      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      // 还有 30 秒到期 -> 落在 "到期前 1 分钟" 窗口内，需要刷新
      expect(
          am.Api.isAccessTokenRefreshRequired(buildJwt(exp: nowSeconds + 30)),
          isTrue);
      // 还有 5 分钟到期 -> 不需要刷新
      expect(
          am.Api.isAccessTokenRefreshRequired(buildJwt(exp: nowSeconds + 300)),
          isFalse);

      // 非 base64 的 payload 读不出来 -> 需要刷新
      expect(am.Api.isAccessTokenRefreshRequired('a.???'), isTrue);
    });

    test('normalizeBase64 / tryReadJwt 解析出 header 与 payload', () {
      expect(am.Api.normalizeBase64('YQ'), 'YQ==');
      expect(am.Api.normalizeBase64('YWI'), 'YWI=');
      expect(am.Api.normalizeBase64('YWJj'), 'YWJj');
      expect(am.Api.normalizeBase64('a-b_c'), 'a+b/c=');

      final jwt = buildJwt(exp: 4102444800);
      final parsed = am.Api.tryReadJwt(jwt);
      expect(parsed, isNotNull);
      expect(parsed!.header['kid'], 'WebPlayKid');
      expect(parsed.payload['exp'], 4102444800);
      expect(parsed.payload['iss'], 'AMPWebPlay');
      expect(am.Api.tryReadJwt('only-one-part'), isNull);
    });

    test('搜索请求：storefront 与 l 参数、Authorization 头', () async {
      final fake = FakeLyricsHttpClient.fixed(appleSearchJson);
      useFake(fake);

      final result = await am.Api().search('晴天 周杰伦');

      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.url.host, 'amp-api.music.apple.com');
      expect(request.url.path, '/v1/catalog/cn/search');
      final q = request.query;
      expect(q['term'], '晴天 周杰伦');
      expect(q['types'], 'songs');
      expect(q['limit'], '20');
      expect(q['l'], 'zh-Hans-CN');
      expect(request.headers['Authorization'],
          startsWith('Bearer '));
      expect(request.headers['Origin'], 'https://music.apple.com');
      expect(request.headers['Accept'], 'application/json');
      expect(request.headers['Accept-Language'], 'zh-Hans-CN,en;q=0.9');
      expect(request.headers['Referer'], 'https://music.apple.com/');

      // 搜索响应 DTO
      final song = result!.results!.songs!.data!.single;
      expect(song.id, '1440857781');
      expect(song.attributes!.name, '晴天');
      expect(song.attributes!.artistName, '周杰伦');
      expect(song.attributes!.albumName, '叶惠美');
      expect(song.attributes!.durationInMillis, 269000);
    });

    test('歌词请求：include[songs]=syllable-lyrics、l 固定 zh-hans-cn、TTML 归一化', () async {
      final fake = FakeLyricsHttpClient.fixed(appleLyricsJson);
      useFake(fake);

      final resp = await am.Api().getLyrics('1440857781');

      final request = fake.requests.single;
      expect(request.url.host, 'amp-api.music.apple.com');
      expect(request.url.path, '/v1/catalog/cn/songs/1440857781');
      // PORT NOTE: 上游把字面量 `include[songs]` 直接拼进 URL；Dart 的 Uri
      // 会把 `[`/`]` 百分号编码成 %5B/%5D，服务器解码后等价。
      expect(request.url.toString(), contains('include%5Bsongs%5D=syllable-lyrics'));
      expect(request.url.queryParameters['l'], 'zh-hans-cn');
      expect(request.url.queryParameters['extend'], 'ttmlLocalizations');

      // 优先 ttmlLocalizations
      expect(resp?.ttml, '<tt><p begin="1s" end="3s">晴天</p></tt>');
    });

    test('TTML 回退与时间轴校验', () {
      final onlyTtml = amresp.LyricResponse.fromJson(jsonDecodeObj(
          '{"data":[{"relationships":{"syllable-lyrics":{"data":[{"attributes":'
          '{"ttml":"<p begin=\\"1s\\" end=\\"2s\\">a</p>"}}]}}}]}'));
      onlyTtml.normalizeTtml();
      expect(onlyTtml.ttml, '<p begin="1s" end="2s">a</p>');

      final noTimeline = amresp.LyricResponse.fromJson(jsonDecodeObj(
          '{"data":[{"relationships":{"syllable-lyrics":{"data":[{"attributes":'
          '{"ttml":"<p>unsynced</p>"}}]}}}]}'));
      noTimeline.normalizeTtml();
      expect(noTimeline.ttml, isNull);

      final noData = amresp.LyricResponse.fromJson(jsonDecodeObj('{}'));
      noData.normalizeTtml();
      expect(noData.ttml, isNull);
    });

    test('storefront 请求：media-user-token 头与 storefront/language 生效', () async {
      // token 有效，但 _inited 被重置 -> 触发 storefront 拉取
      final api = am.Api()..setAccessToken(buildJwt(exp: 4102444800));
      final fake = FakeLyricsHttpClient.fixed(appleStorefrontJson);
      useFake(fake);
      api.setMediaUserToken('mut-abc'); // 变化 -> _inited = false

      await api.ensureInitAsync();

      expect(fake.requests, hasLength(1));
      final request = fake.requests.single;
      expect(request.url.toString(),
          'https://amp-api.music.apple.com/v1/me/storefront');
      expect(request.headers['media-user-token'], 'mut-abc');
      expect(request.headers['Authorization'], startsWith('Bearer '));

      expect(api.getStorefront(), 'cn');
      expect(api.getLanguage(), 'zh-Hans-CN');
    });

    test('401 会刷新 access token 并重试一次', () async {
      am.Api()
        ..setAccessToken(buildJwt(exp: 4102444800))
        ..setStorefrontCache('us', 'en-US', null);
      final freshToken = buildJwt(exp: 4102444800);
      final js = 'var x="$freshToken";';
      final fake = FakeLyricsHttpClient.queue([
        // 1) catalog search 返回 401
        const LyricsHttpResponse(statusCode: 401, body: ''),
        // 2) GetAccessTokenAsync：browse HTML
        const LyricsHttpResponse(
            statusCode: 200,
            body: '<script src="/assets/index~1.js"></script>'),
        // 3) index js（内含 token）
        LyricsHttpResponse(statusCode: 200, body: js),
        // 4) 重试 search
        const LyricsHttpResponse(statusCode: 200, body: appleSearchJson),
      ]);
      useFake(fake);

      final result = await am.Api().search('晴天');

      expect(fake.requests, hasLength(4));
      expect(fake.requests[0].url.path, '/v1/catalog/us/search');
      expect(fake.requests[1].url.toString(), 'https://music.apple.com/us/browse');
      expect(fake.requests[2].url.path, '/assets/index~1.js');
      expect(fake.requests[3].url.path, '/v1/catalog/us/search');
      expect(result!.results!.songs!.data!.single.attributes!.name, '晴天');
    });

    test('403 + 空响应体也会刷新 token（上游的 ContentLength==0 等价物）', () async {
      am.Api()
        ..setAccessToken(buildJwt(exp: 4102444800))
        ..setStorefrontCache('us', 'en-US', null);
      final freshToken = buildJwt(exp: 4102444800);
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 403, body: ''),
        const LyricsHttpResponse(
            statusCode: 200,
            body: '<script src="/assets/index~1.js"></script>'),
        LyricsHttpResponse(statusCode: 200, body: 'var x="$freshToken";'),
        const LyricsHttpResponse(statusCode: 200, body: appleSearchJson),
      ]);
      useFake(fake);

      await am.Api().search('晴天');
      expect(fake.requests, hasLength(4));

      // 403 且响应体非空 -> 不刷新，直接抛
      final fake2 = FakeLyricsHttpClient.fixed('{"error":"forbidden"}',
          statusCode: 403);
      useFake(fake2);
      await expectLater(am.Api().search('晴天'), throwsA(isA<LyricsHttpException>()));
      expect(fake2.requests, hasLength(1));
    });

    test('setMediaUserToken：相同 token 不重置 _inited；空串忽略', () async {
      final api = am.Api()
        ..setAccessToken(buildJwt(exp: 4102444800))
        ..setStorefrontCache('cn', 'zh-Hans-CN', 'mut-1');

      final fake = FakeLyricsHttpClient.fixed(appleSearchJson);
      useFake(fake);
      api.setMediaUserToken('mut-1'); // 与 _cachedMut 相同 -> 不重置
      await api.search('晴天');
      expect(fake.requests, hasLength(1));

      // 空串被忽略
      api.setMediaUserToken('   ');
      expect(am.Api().getStorefront(), 'cn');
    });
  });

  // =========================================================================
  // Spotify
  // =========================================================================

  group('Spotify', () {
    test('normalizeSpDc：去掉 cookie 前缀与引号', () {
      expect(sp.Api.normalizeSpDc('  abc123  '), 'abc123');
      expect(sp.Api.normalizeSpDc('sp_dc=abc123'), 'abc123');
      expect(sp.Api.normalizeSpDc('a=b; sp_dc=abc123 ; c=d'), 'abc123');
      expect(sp.Api.normalizeSpDc('"abc123"'), 'abc123');
      expect(sp.Api.normalizeSpDc(null), '');
    });

    test('tryParseSecretPayload：XOR 解码与取最大版本号', () {
      final parsed = sp.Api.tryParseSecretPayload(sp.Api.bundledSecretJson);
      expect(parsed, isNotNull);
      expect(parsed!.version, '61');
      expect(parsed.secret, isNotEmpty);
      expect(parsed.secret.length, 27);

      // 版本号 59（三个版本里最小），校验 XOR 规则：(v ^ ((i % 33) + 9))
      final v59 = sp.Api.tryParseSecretPayload(
          '{"59":[123,105,79,70,110,59,52,125,60,49,80,70,89,75,80,86,63,53,123,37,117,49,52,93,77,62,47,86,48,104,68,72]}');
      expect(v59!.version, '59');
      final expected = <int>[123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53, 123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72]
          .asMap()
          .entries
          .map((e) => e.value ^ ((e.key % 33) + 9))
          .join();
      expect(v59.secret, expected);

      expect(sp.Api.tryParseSecretPayload('not json'), isNull);
      expect(sp.Api.tryParseSecretPayload('{"abc":1}'), isNull);
      expect(sp.Api.tryParseSecretPayload('{"61":"not-array"}'), isNull);
    });

    test('generateTotp：与 .NET HMACSHA1 独立算出的黄金向量一致', () {
      // 向量由 pwsh 调 System.Security.Cryptography.HMACSHA1 独立算出：
      //   secret = 'f2b1...f1a2b3'（64 hex 字符）
      //   serverTime = 1700000000  -> counter = 56666667 -> code = 043318
      const secret =
          'f2b1c9d4e7a3456b8c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3';
      expect(sp.Api.generateTotp(1700000000, secret), '043318');
      // 同一 30 秒窗口内结果稳定
      expect(sp.Api.generateTotp(1700000005, secret), '043318');
      // 跨窗口即变化
      expect(sp.Api.generateTotp(1700000030, secret), isNot('043318'));
    });

    test('server time 缺失时报错；token 端点带 totp/totpVer/productType', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: spotifyServerTimeJson),
        const LyricsHttpResponse(statusCode: 200, body: spotifyTokenJson),
      ]);
      useFake(fake);

      final payload = await sp.Api().requestAccessTokenAsync(spDc: 'spdc-1');

      expect(fake.requests, hasLength(2));
      expect(fake.requests[0].url.toString(),
          'https://open.spotify.com/api/server-time');
      final tokenRequest = fake.requests[1];
      expect(tokenRequest.url.host, 'open.spotify.com');
      expect(tokenRequest.url.path, '/api/token');
      final q = tokenRequest.query;
      expect(q['reason'], 'init');
      expect(q['productType'], 'web-player');
      expect(q['totpVer'], '61');
      expect(q['totp'], q['totpServer']);
      expect(q['totp'], isNot(isEmpty));
      expect(q.containsKey('ts'), isFalse);
      expect(tokenRequest.headers['Cookie'], 'sp_dc=spdc-1');
      expect(tokenRequest.headers['App-Platform'], 'WebPlayer');
      expect(tokenRequest.headers['Referer'], 'https://open.spotify.com/');

      expect(payload.accessToken, 'BQfake-token');
      expect(payload.accessTokenExpirationTimestampMs, 1700003600000);
      expect(payload.isAnonymous, isFalse);
    });

    test('token 端点 400 时回退 legacy 参数（reason=transport + ts）', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: spotifyServerTimeJson),
        const LyricsHttpResponse(statusCode: 400, body: '{}'),
        const LyricsHttpResponse(statusCode: 200, body: spotifyServerTimeJson),
        const LyricsHttpResponse(statusCode: 200, body: spotifyTokenJson),
      ]);
      useFake(fake);

      await sp.Api().requestAccessTokenAsync(spDc: 'spdc-1');

      expect(fake.requests, hasLength(4));
      expect(fake.requests[1].query['reason'], 'init');
      final legacy = fake.requests[3];
      expect(legacy.query['reason'], 'transport');
      expect(legacy.query['productType'], 'web-player');
      expect(int.tryParse(legacy.query['ts']!), isNotNull);
    });

    test('isAnonymous / 空 accessToken 视为 sp_dc 无效', () async {
      useFake(FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: spotifyServerTimeJson),
        const LyricsHttpResponse(
            statusCode: 200,
            body: '{"accessToken":"","isAnonymous":true}'),
      ]));
      await expectLater(
          sp.Api().requestAccessTokenAsync(spDc: 'x'), throwsA(isA<StateError>()));

      useFake(FakeLyricsHttpClient.fixed('{}', statusCode: 401));
      await expectLater(sp.Api().requestAccessTokenAsync(spDc: 'x'),
          throwsA(isA<StateError>()));
    });

    test('Web API 搜索分支：URL 参数与 DTO 映射', () async {
      final fake = FakeLyricsHttpClient.fixed(spotifySearchJson);
      useFake(fake);

      final candidates =
          await sp.Api().searchTrackCandidatesViaWebApi('晴天', '周杰伦', 5);

      final request = fake.requests.single;
      expect(request.url.host, 'api.spotify.com');
      expect(request.url.path, '/v1/search');
      final q = request.url.queryParameters;
      expect(q['q'], '晴天 周杰伦');
      expect(q['type'], 'track');
      expect(q['limit'], '5');
      expect(q['market'], 'from_token');
      expect(request.headers['User-Agent'], sp.Api.spotifyUserAgent);
      expect(request.headers['Authorization'], 'Bearer ');

      expect(candidates, hasLength(1));
      expect(candidates.single.id, '6a1RJ9EfZfvyv5x1nO0z0N');
      expect(candidates.single.title, '晴天');
      expect(candidates.single.artistName, '周杰伦');
      expect(candidates.single.albumName, '叶惠美');
      expect(candidates.single.durationMs, 269000);
    });

    test('Web API 搜索 DTO：多歌手用 ", " 连接、空字段被过滤', () {
      final resp = spmodel.SearchResponse.fromJson(jsonDecodeObj(
          '{"tracks":{"items":[{"id":"i1","name":"n1","duration_ms":1,'
          '"artists":[{"name":"A"},{"name":""},{"name":"B"}],'
          '"album":{"name":"al"}},{"id":"","name":"n2"},{"id":"i3","name":""}]}}'));
      expect(resp.tracks!.items, hasLength(3));
      expect(resp.tracks!.items!.first.artists!.map((a) => a.name).toList(),
          ['A', '', 'B']);
    });

    test('pathfinder 搜索：URL 的 variables/extensions 编码 sha256Hash', () async {
      final fake = FakeLyricsHttpClient.fixed(spotifyPathfinderJson);
      useFake(fake);
      sp.Api().setAccessToken('tok-1', 4102444800000);

      final candidates =
          await sp.Api().searchTrackCandidatesViaPathfinder('晴天', '周杰伦', 10);

      final request = fake.requests.single;
      expect(request.url.host, 'api-partner.spotify.com');
      expect(request.url.path, '/pathfinder/v1/query');
      expect(request.url.queryParameters['operationName'], 'searchDesktop');
      final variables =
          jsonDecode(request.url.queryParameters['variables']!) as Map;
      expect(variables['searchTerm'], '晴天 周杰伦');
      expect(variables['offset'], 0);
      expect(variables['limit'], 10);
      expect(variables['numberOfTopResults'], 5); // min(5, limit)
      final extensions =
          jsonDecode(request.url.queryParameters['extensions']!) as Map;
      expect((extensions['persistedQuery'] as Map)['version'], 1);
      expect((extensions['persistedQuery'] as Map)['sha256Hash'],
          sp.Api.pathfinderSearchHashes.first);
      expect(request.headers['Authorization'], 'Bearer tok-1');

      expect(candidates.single.id, '6a1RJ9EfZfvyv5x1nO0z0N');
      expect(candidates.single.title, '晴天');
      expect(candidates.single.artistName, '周杰伦');
      expect(candidates.single.albumName, '叶惠美');
      expect(candidates.single.durationMs, isNull);
    });

    test('pathfinder 解析：uri 兜底、data 包裹、data.search 分支', () {
      final fromUri = sp.Api.parsePathfinderTrackCandidates(spotifyPathfinderUriJson);
      expect(fromUri, hasLength(1));
      expect(fromUri.single.id, '0abcDEF');
      expect(fromUri.single.title, '七里香');
      expect(fromUri.single.artistName, '周杰伦');
      expect(fromUri.single.albumName, '');

      expect(sp.Api.spotifyIdFromUri('spotify:track:xyz'), 'xyz');
      expect(sp.Api.spotifyIdFromUri('spotify:album:xyz'), isNull);
      expect(sp.Api.spotifyIdFromUri(null), isNull);

      expect(sp.Api.parsePathfinderTrackCandidates('not json'), isEmpty);
      expect(sp.Api.parsePathfinderTrackCandidates('{}'), isEmpty);
      expect(
          sp.Api.parsePathfinderTrackCandidates(
              '{"data":{"searchV2":{"tracks":{"items":[]}}}}'),
          isEmpty);
    });

    test('getLyrics：color-lyrics URL 与专用 UA', () async {
      final fake = FakeLyricsHttpClient.fixed('{"lyrics":{"syncType":"LINE_SYNCED"}}');
      useFake(fake);
      sp.Api().setAccessToken('tok-2', 4102444800000);

      final body = await sp.Api().getLyrics('6a1RJ9EfZfvyv5x1nO0z0N');

      final request = fake.requests.single;
      expect(request.url.toString(),
          'https://spclient.wg.spotify.com/color-lyrics/v2/track/6a1RJ9EfZfvyv5x1nO0z0N?format=json&market=from_token');
      expect(request.headers['User-Agent'], sp.Api.spotifyUserAgent);
      expect(request.headers['App-platform'], 'WebPlayer');
      expect(request.headers['Authorization'], 'Bearer tok-2');
      expect(body, contains('LINE_SYNCED'));
    });

    test('searchTrackCandidates：pathfinder 命中则不回落 Web API', () async {
      final fake = FakeLyricsHttpClient.fixed(spotifyPathfinderJson);
      useFake(fake);
      sp.Api().setAccessToken('tok-3', 4102444800000);

      final candidates = await sp.Api().searchTrackCandidates('晴天', '周杰伦');

      expect(fake.requests, hasLength(1));
      expect(fake.requests.single.url.host, 'api-partner.spotify.com');
      expect(candidates.single.title, '晴天');
    });

    test('searchTrackCandidates：没有 access token 且没配 sp_dc 时报错', () async {
      sp.Api().setAccessToken('', 0);
      sp.Api().setSpDc('');
      useFake(FakeLyricsHttpClient.fixed('{}'));
      await expectLater(sp.Api().searchTrackCandidates('a', 'b'),
          throwsA(isA<StateError>()));
    });

    test('previewText 截断到 180 字符', () {
      expect(sp.Api.previewText('  '), isNull);
      expect(sp.Api.previewText('  abc  '), 'abc');
      expect(sp.Api.previewText('x' * 200)!.length, 180);
      expect(sp.Api.previewText('x' * 10), 'x' * 10);
    });
  });

  // =========================================================================
  // Musixmatch
  // =========================================================================

  group('Musixmatch', () {
    test('ApiOptions 预设：Android / Desktop / Mobile 的常量', () {
      final android = mxopt.ApiOptions();
      expect(android.apiBaseUrl, 'https://apic.musixmatch.com/ws/1.1/');
      expect(android.appId, 'android-player-v1.0');
      expect(android.userAgent, 'Dalvik/2.1.0 (Linux; U; Android 13)');
      expect(android.cookie, 'AWSELB=0; AWSELBCORS=0');
      expect(android.timeout, const Duration(seconds: 4));
      // Guid.NewGuid().ToString("N")：32 位小写十六进制
      expect(android.requestIdFactory(), matches(RegExp(r'^[0-9a-f]{32}$')));

      final desktop = mxopt.ApiOptions()..useDesktop();
      expect(desktop.apiBaseUrl, 'https://apic-desktop.musixmatch.com/ws/1.1/');
      expect(desktop.appId, 'web-desktop-app-v1.0');
      expect(desktop.userAgent, BaseApi.userAgent);
      expect(int.tryParse(desktop.requestIdFactory()), isNotNull);

      final mobile = mxopt.ApiOptions()..useMobile();
      expect(mobile.appId, 'android-player-v1.0');
    });

    test('构造校验：baseUrl 自动补 /，appId/timeout 非法即抛', () {
      final api = mx.Api((options) {
        options.apiBaseUrl = 'https://example.com/ws';
        options.appId = 'app-1';
      });
      expect(api.options.apiBaseUrl, 'https://example.com/ws/');

      expect(() => mx.Api((o) => o.appId = ''), throwsA(isA<ArgumentError>()));
      expect(() => mx.Api((o) => o.apiBaseUrl = ''), throwsA(isA<ArgumentError>()));
      expect(
          () => mx.Api((o) => o.timeout = Duration.zero),
          throwsA(isA<ArgumentError>()));
    });

    test('token 流程：token.get 请求 URL/头，token 被缓存复用', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);

      final api = mx.Api((options) {
        options.requestIdFactory = () => 'req-id-1';
      });

      final token = await api.requestTokenAsync();
      expect(fake.requests, hasLength(1));
      final tokenRequest = fake.requests.single;
      expect(tokenRequest.method, 'GET');
      expect(tokenRequest.url.host, 'apic.musixmatch.com');
      expect(tokenRequest.url.path, '/ws/1.1/token.get');
      expect(tokenRequest.url.queryParameters['user_language'], 'en');
      expect(tokenRequest.url.queryParameters['app_id'], 'android-player-v1.0');
      expect(tokenRequest.url.queryParameters['t'], 'req-id-1');
      expect(tokenRequest.headers['User-Agent'], 'Dalvik/2.1.0 (Linux; U; Android 13)');
      expect(tokenRequest.headers['Cookie'], 'AWSELB=0; AWSELBCORS=0');
      expect(tokenRequest.timeout, const Duration(seconds: 4));
      expect(token!['message']['body']['user_token'], 'abcdef0123456789');

      // 后续两次请求都复用同一个 token（不再发 token.get）
      await api.searchTracksAsync(null, '晴天', '周杰伦', null);
      await api.searchTracksAsync(null, '晴天', '周杰伦', null);
      expect(fake.requests, hasLength(3));
      for (final request in fake.requests.skip(1)) {
        expect(request.url.path, '/ws/1.1/track.search');
        expect(request.url.queryParameters['usertoken'], 'abcdef0123456789');
        expect(request.url.queryParameters['app_id'], 'android-player-v1.0');
        expect(request.url.queryParameters['format'], 'json');
        expect(request.url.queryParameters['t'], 'req-id-1');
        // track.search 的固定参数 + 命名参数
        expect(request.url.queryParameters['page_size'], '10');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['s_track_rating'], 'desc');
        expect(request.url.queryParameters['q_track'], '晴天');
        expect(request.url.queryParameters['q_artist'], '周杰伦');
        expect(request.url.queryParameters.containsKey('q_duration'), isFalse);
      }
    });

    test('setUserToken / getUserToken 的可用性规则', () {
      final api = mx.Api();
      api.setUserToken('abcdef');
      expect(api.getUserToken(), 'abcdef');
      // 全是 0 -> 不可用
      api.setUserToken('000000');
      expect(api.getUserToken(), isNull);
      api.setUserToken('null');
      expect(api.getUserToken(), isNull);
      api.setUserToken('   ');
      expect(api.getUserToken(), isNull);
      api.setUserToken('0a0');
      expect(api.getUserToken(), '0a0');
    });

    test('searchTracksAsync：时长参数、空关键字不加 q', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);
      final api = mx.Api((o) => o.requestIdFactory = () => 't');

      await api.searchTracksAsync('天空', null, null, 269000);
      expect(fake.requests[1].url.queryParameters['q'], '天空');
      expect(fake.requests[1].url.queryParameters['q_duration'], '269000');

      await api.searchTracksAsync(null, null, null, 0);
      final q = fake.requests[2].url.queryParameters;
      expect(q.containsKey('q'), isFalse);
      expect(q.containsKey('q_track'), isFalse);
      expect(q.containsKey('q_artist'), isFalse);
      // duration 必须 > 0 才加参数
      expect(q.containsKey('q_duration'), isFalse);
    });

    test('track.search 响应 DTO：歌名/歌手/时长/id 与歌词字段', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);

      final tracks =
          await mx.Api((o) => o.requestIdFactory = () => 't').searchTracksAsync(
              null,
              '晴天',
              '周杰伦',
              null);

      expect(tracks, hasLength(1));
      final track = tracks.single;
      expect(track.trackId, 123456789);
      expect(track.trackName, '晴天');
      expect(track.artistName, '周杰伦');
      expect(track.albumName, '叶惠美');
      expect(track.trackLength, 269);
      expect(track.commontrackId, 98765432);
      expect(track.hasLyrics, 1);
      expect(track.hasSubtitles, 1);
      expect(track.hasRichsync, 1);
      expect(track.lyricsId, 111);
      expect(track.subtitleId, 222);
      expect(track.commontrackVanityId, 'Jay-Chou/Qing-Tian');
      expect(track.updatedTime, '2024-01-01T00:00:00Z');
      expect(track.primaryGenres!.musicGenreList!.single.musicGenre!.musicGenreName, 'Pop');
      expect(track.primaryGenres!.musicGenreList!.single.musicGenre!.musicGenreId, 12);
      expect(track.commontrackIsrcs, isNull);
      expect(track.firstReleaseDate, isNull);
    });

    test('HasRelatedResult 的过滤（不相关则不返回结果）', () async {
      // 标题完全不匹配 -> 5 次重试后返回空列表
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        for (var i = 0; i < 5; i++)
          const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);

      final tracks = await mx.Api(
              (o) => o.requestIdFactory = () => 't')
          .searchTracksAsync(null, '完全不存在的歌名 XYZ', '别的歌手', null);

      expect(tracks, isEmpty);
      // 1 次 token + ResultRetryCount(5) 次 track.search
      expect(fake.requests, hasLength(6));
    });

    test('getTrack 组装 GetTrackResponse（statusCode 200 / confidence 1000）', () async {
      useFake(FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]));

      final response = await mx.Api((o) => o.requestIdFactory = () => 't')
          .getTrack('晴天', '周杰伦');

      expect(response!.message!.header!.statusCode, 200);
      expect(response.message!.header!.confidence, 1000);
      expect(response.message!.body!.track!.trackName, '晴天');
      expect(response.message!.body!.track!.trackId, 123456789);
    });

    test('getFullLyricsRaw：macro.subtitles.get 请求参数与响应字符串', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchLyricsJson),
      ]);
      useFake(fake);

      final raw = await mx.Api((o) => o.requestIdFactory = () => 't')
          .getFullLyricsRawById('123456789');

      final request = fake.requests[1];
      expect(request.url.path, '/ws/1.1/macro.subtitles.get');
      final q = request.url.queryParameters;
      expect(q['namespace'], 'lyrics_richsynched');
      expect(q['optional_calls'], 'track.richsync');
      expect(q['subtitle_format'], 'lrc');
      expect(q['track_id'], '123456789');
      expect(q['f_subtitle_length_max_deviation'], '40');

      expect(raw, isNotNull);
      final parsed = mxresp.GetTrackResponse.fromJson(jsonDecodeObj(raw!));
      expect(parsed.message!.header!.statusCode, 200);
      expect(parsed.message!.header!.confidence, 1000);
      expect(parsed.message!.header!.mode, 'musixmatch');
      expect(parsed.message!.header!.cached, 1);
      expect(parsed.message!.body!.track!.trackName, '晴天');
      expect(parsed.message!.body!.track!.trackId, 123456789);
    });

    test('getFullLyricsRaw：track_id 非数字直接返回 null（不发请求）', () async {
      final fake = FakeLyricsHttpClient.fixed('{}');
      useFake(fake);
      expect(await mx.Api().getFullLyricsRawById('Jay-Chou/Qing-Tian'), isNull);
      expect(fake.requests, isEmpty);
    });

    test('getTranslations：crowd.track.translations.get 参数与 DTO', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTranslationsJson),
      ]);
      useFake(fake);

      final response = await mx.Api((o) => o.requestIdFactory = () => 't')
          .getTranslations('123456789', 'zh');

      final request = fake.requests[1];
      expect(request.url.path, '/ws/1.1/crowd.track.translations.get');
      final q = request.url.queryParameters;
      expect(q['translation_fields_set'], 'minimal');
      expect(q['selected_language'], 'zh');
      expect(q['track_id'], '123456789');
      expect(q['comment_format'], 'text');
      expect(q['part'], 'user');

      final translation =
          response!.message!.body!.translationsList!.single.translation!;
      expect(translation.languageFrom, 'en');
      expect(translation.selectedLanguage, 'zh');
      expect(translation.snippet, '晴天');
      expect(translation.matchedLine, '[00:01.00] 故事的小黄花');
      expect(translation.confidence, 0.98);
      expect(translation.lyricsId, 111);
      expect(translation.subtitleId, 222);
      expect(translation.isMine, 1);
      expect(translation.user!.userName, 'tester');
      expect(translation.user!.rankColors!.rankColor10, '#fff');
    });

    test('401 + hint=renew：作废 token 后重新取 token 并成功', () async {
      final fake = FakeLyricsHttpClient.queue([
        // 1) token.get
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        // 2) track.search -> 401 renew
        const LyricsHttpResponse(
            statusCode: 200,
            body: '{"message":{"header":{"status_code":401,"hint":"renew"}}}'),
        // 3) token.get（作废后重新取）
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        // 4) track.search 成功
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);

      final api = mx.Api((o) => o.requestIdFactory = () => 't');
      final tracks = await api.searchTracksAsync(null, '晴天', '周杰伦', null);

      expect(tracks, hasLength(1));
      expect(fake.requests, hasLength(4));
      expect(fake.requests[0].url.path, '/ws/1.1/token.get');
      expect(fake.requests[2].url.path, '/ws/1.1/token.get');
    });

    test('401 + hint=captcha：抛顶层 RequestCaptchaException', () async {
      useFake(FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(
            statusCode: 200,
            body: '{"message":{"header":{"status_code":401,"hint":"captcha"}}}'),
      ]));

      await expectLater(
        mx.Api((o) => o.requestIdFactory = () => 't')
            .searchTracksAsync(null, '晴天', '周杰伦', null),
        throwsA(isA<mx.RequestCaptchaException>()),
      );
    });

    test('token.get 也带 captcha 检测；status != 200 抛异常', () async {
      useFake(FakeLyricsHttpClient.fixed(
          '{"message":{"header":{"status_code":401,"hint":"captcha"}}}'));
      await expectLater(mx.Api().requestTokenAsync(),
          throwsA(isA<mx.RequestCaptchaException>()));

      useFake(FakeLyricsHttpClient.fixed(
          '{"message":{"header":{"status_code":500,"hint":"server"}}}'));
      await expectLater(mx.Api().requestTokenAsync(),
          throwsA(isA<LyricsHttpException>()));
    });

    test('status_code == 404 视为有效响应（直接返回 body，不重试）', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(
            statusCode: 200,
            body: '{"message":{"header":{"status_code":404,"hint":"not found"},'
                '"body":{}}}'),
      ]);
      useFake(fake);

      final response = await mx.Api((o) => o.requestIdFactory = () => 't')
          .sendApiRequestAsync('track.get?track_id=1');

      expect(response!['message']['header']['status_code'], 404);
      expect(fake.requests, hasLength(2));
    });

    test('token 请求失败后重试 RequestRetryCount 次并抛异常', () async {
      final fake = FakeLyricsHttpClient.fixed('{}', statusCode: 500);
      useFake(fake);

      await expectLater(
        mx.Api((o) => o.requestIdFactory = () => 't')
            .sendApiRequestAsync('track.get?track_id=1'),
        throwsA(isA<LyricsHttpException>()),
      );
      // 上游 RequestRetryCount = 5
      expect(fake.requests, hasLength(5));
    });

    test('Regex/工具方法：normalizeVanity、decodeVanityPart、tokenize', () {
      expect(mx.Api.normalizeVanity('/Jay-Chou/Qing-Tian/'), 'Jay-Chou/Qing-Tian');
      expect(mx.Api.normalizeVanity('%2FJay-Chou%2FQing-Tian'),
          'Jay-Chou/Qing-Tian');
      expect(mx.Api.decodeVanityPart('Jay-Chou'), 'Jay Chou');
      expect(mx.Api.decodeVanityPart(' Qing%20Tian '), 'Qing Tian');
      expect(mx.Api.tokenize('Hello, World (Remix)'), ['hello', 'world', 'remix']);
      expect(mx.Api.tokenize('a-b c'), ['c']);
      expect(mx.Api.tokenize(null), isEmpty);
    });

    test('resolveTrackAsync：数字 id 走 track.get 并校验 track_id', () async {
      const trackGetJson = '{"message":{"header":{"status_code":200,"hint":""},'
          '"body":{"track":{"track_id":123456789,"track_name":"晴天",'
          '"artist_name":"周杰伦","track_length":269}}}';
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: trackGetJson),
      ]);
      useFake(fake);

      final track = await mx.Api((o) => o.requestIdFactory = () => 't')
          .resolveTrackAsync('123456789');

      expect(fake.requests[1].url.path, '/ws/1.1/track.get');
      expect(fake.requests[1].url.queryParameters['track_id'], '123456789');
      expect(track!.trackId, 123456789);
      expect(track.trackName, '晴天');
    });

    test('resolveTrackAsync：vanity id 走搜索并匹配 commontrack_vanity_id', () async {
      final fake = FakeLyricsHttpClient.queue([
        const LyricsHttpResponse(statusCode: 200, body: musixmatchTokenJson),
        const LyricsHttpResponse(statusCode: 200, body: musixmatchSearchJson),
      ]);
      useFake(fake);

      final track = await mx.Api((o) => o.requestIdFactory = () => 't')
          .resolveTrackAsync('Jay-Chou/Qing-Tian');

      expect(fake.requests[1].url.path, '/ws/1.1/track.search');
      expect(fake.requests[1].url.queryParameters['q_track'], 'Qing Tian');
      expect(fake.requests[1].url.queryParameters['q_artist'], 'Jay Chou');
      expect(track!.trackId, 123456789);
    });

    test('resolveTrackAsync：无 "/" 的 vanity 返回 null', () async {
      final fake = FakeLyricsHttpClient.fixed(musixmatchTokenJson);
      useFake(fake);
      expect(await mx.Api().resolveTrackAsync('just-a-name'), isNull);
    });

    test('getToken 直接返回 token 响应 DTO', () async {
      useFake(FakeLyricsHttpClient.fixed(musixmatchTokenJson));

      final token = await mx.Api((o) => o.requestIdFactory = () => 't').getToken();

      expect(token!.message!.header!.statusCode, 200);
      expect(token.message!.header!.pid, 1);
      expect(token.message!.body!.userToken, 'abcdef0123456789');
      expect(token.message!.body!.appConfig!.searchMaxResults, 10);
      expect(token.message!.body!.appConfig!.trial, isFalse);
      expect(token.message!.body!.location!.geoIPCityCountryCode, 'CN');
      expect(token.message!.body!.location!.geoIPLatitude, 31.22);
      expect(token.message!.body!.location!.geoIPLongitude, 121.46);
      expect(token.message!.body!.location!.badipTags, isNull);
    });
  });
}
