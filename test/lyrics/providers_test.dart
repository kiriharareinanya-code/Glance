// 网易云 / QQ 音乐 / 酷狗 / LRCLIB 四个在线源的**离线**验收测试。
//
// 覆盖两块：
//   1) 请求构造：URL / 方法 / 请求体（中文关键词的百分号编码、QQ 的 jsonp 与 g_tk、
//      网易云 eapi 的加密 params 能不能解回原文）；
//   2) 响应 DTO：`fromJson` 在**真实样本 JSON** 上取到的字段值（歌名/歌手/时长/歌词/id）。
//
// 网络出口用假的 `LyricsHttpClient`（记录请求 + 返回内置样本），**不发真实请求**。
// 样本来源：2026-09 用 pwsh `Invoke-WebRequest` 实抓的响应（
// `music.163.com/api/search/get/web`、`u.y.qq.com/cgi-bin/musicu.fcg`、
// `c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg`、`c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg`、
// `mobilecdn.kugou.com/api/v3/search/song`、`lyrics.kugou.com/search`、`lrclib.net/api/search`），
// 字段值原样保留，只把用不到的大字段裁掉。
//
// eapi / weapi 的加密用**离线黄金向量**对齐 .NET：向量由 PowerShell 调
// `System.Security.Cryptography.Aes`(ECB/CBC + PKCS7) / `MD5` / `BigInteger.ModPow`
// 独立算出（等价于上游 C# 的实现），写在下面几个 `const` 里。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/http/lyrics_http.dart';
import 'package:vectra/lyrics/providers/web/base_api.dart';
import 'package:vectra/lyrics/providers/web/kugou/api.dart' as kg;
import 'package:vectra/lyrics/providers/web/kugou/response.dart' as kgresp;
import 'package:vectra/lyrics/providers/web/lrclib/api.dart' as lrclib;
import 'package:vectra/lyrics/providers/web/lrclib/response.dart' as lrclibresp;
import 'package:vectra/lyrics/providers/web/netease/api.dart' as ne;
import 'package:vectra/lyrics/providers/web/netease/eapi_helper.dart';
import 'package:vectra/lyrics/providers/web/qqmusic/api.dart' as qq;
import 'package:vectra/lyrics/providers/web/qqmusic/response.dart' as qqresp;

// ---------------------------------------------------------------------------
// 假 HTTP 客户端
// ---------------------------------------------------------------------------

class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  @override
  String toString() => '$method $url body=${body ?? ''}';
}

class FakeLyricsHttpClient implements LyricsHttpClient {
  FakeLyricsHttpClient(this.handler, {this.statusCode = 200});

  /// 根据请求给出响应体。
  final String Function(RecordedRequest request) handler;

  final int statusCode;

  final List<RecordedRequest> requests = <RecordedRequest>[];

  RecordedRequest get last => requests.last;

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
    );
    requests.add(request);
    return LyricsHttpResponse(statusCode: statusCode, body: handler(request));
  }
}

/// 表单体 → Map（复刻 `application/x-www-form-urlencoded` 的解码）。
Map<String, String> parseForm(String body) => Uri.splitQueryString(body);

/// weapi 的请求体是 `{"params":"...","encSecKey":"..."}`（上游
/// `PostAsync(url, string)` → `StringContent(param, Encoding.UTF8, "application/json")`）。
String weapiParamsOf(String body) =>
    (jsonDecode(body) as Map<String, dynamic>)['params'] as String;

/// weapi：`params` 是两次 base64（AES-CBC(secret) 包 AES-CBC(nonce) 包原文）。
String decodeWeapiParams(String params) =>
    utf8.decode(base64.decode(utf8.decode(base64.decode(params))));

// ---------------------------------------------------------------------------
// 真实样本
// ---------------------------------------------------------------------------

/// 网易云 `api/search/get/web`（实抓，原样）。
const String neSearchJson = r'''
{"result":{"songs":[{"album":{"publishTime":1751990400000,"size":1,"artist":{"img1v1Url":"http://p1.music.126.net/6y-UleORITEDbvrOLV0Q8A==/5639395138885805.jpg","musicSize":0,"albumSize":0,"img1v1":0,"name":"","alias":[],"id":0,"picId":0},"copyrightId":1416729,"name":"夜曲","id":278269102,"picId":109951171458803146,"mark":0,"status":1},"fee":1,"duration":233956,"rtype":0,"ftype":0,"artists":[{"img1v1Url":"http://p1.music.126.net/6y-UleORITEDbvrOLV0Q8A==/5639395138885805.jpg","musicSize":0,"albumSize":0,"img1v1":0,"name":"Xai小爱","alias":[],"id":98459986,"picId":0}],"copyrightId":1416729,"mvid":0,"name":"夜曲","alias":[],"id":2725685941,"mark":17179877376,"status":0}],"songCount":333},"code":200,"trp":{}}
''';

/// 网易云 eapi 响应形状（字段名取自线上 eapi 响应：`ar`/`alia`/`al`/`dt` + `result`/`code`）。
const String neEapiSearchJson = r'''
{"needLogin":false,"code":200,"result":{"songs":[{"name":"晴天","id":186016,"publishTime":1147104000000,"ar":[{"id":6452,"name":"周杰伦","tns":[],"alias":[]}],"alia":["Sunny Day"],"al":{"id":186014,"name":"叶惠美","picUrl":"https://p1.music.126.net/x.jpg","tns":[],"pic":1099511659},"dt":269590,"privilege":{"id":186016,"fee":0,"payed":0,"st":0,"pl":320000,"dl":320000,"sp":7,"cp":1,"subp":1,"cs":false,"maxbr":999000,"fl":320000,"toast":false,"flag":0}}],"songCount":1},"trp":{}}
''';

/// 网易云 `weapi/song/lyric`（实抓字段名；`yrc` 是逐字）。
const String neLyricJson = r'''
{"sgc":false,"sfy":false,"qfy":false,"nolyric":false,"uncollected":false,"lrc":{"version":54,"lyric":"[00:00.00] 作词 : 周杰伦\n[00:01.00]晴天 - 周杰伦"},"tlyric":{"version":0,"lyric":""},"romalrc":{"version":0,"lyric":""},"yrc":{"version":11,"lyric":"[0,1000](0,300,0)晴"},"ytlrc":{"version":0,"lyric":""},"yromalrc":{"version":0,"lyric":""},"code":200}
''';

/// QQ 音乐 `musicu.fcg` 搜索（实抓；歌曲字段原样，裁掉了 file/lyric 等大字段）。
///
/// `list[0]` 是外层曲目（id 260678），`grp` 是它的同版本曲目（实抓里有两个）。
const String qqSearchJson = r'''
{"code":0,"ts":1791040217535,"start_ts":1791040217266,"traceid":"4d6c2b5b206e8893","req_1":{"code":0,"data":{"code":0,"ver":0,"meta":{"curpage":1,"nextpage":2,"perpage":15,"query":"富士山下","sum":1939},"body":{"song":{"list":[
{"id":260678,"mid":"003aAPj81VWrbL","name":"富士山下","title":"富士山下","subtitle":"","interval":259,"time_public":"2007-01-25","language":1,"genre":0,"isonly":0,"index_cd":0,"index_album":5,"label":"0","singer":[{"id":143,"mid":"003Nz2So3XXYek","name":"陈奕迅","pmid":"","title":"陈奕迅","type":0}],"album":{"id":22276,"mid":"004Z85XP1c25b7","name":"What's Going On...?","pmid":"004Z85XP1c25b7_5","subtitle":"","time_public":"","title":"What's Going On...?"},"ksong":{"id":3162194,"mid":"003dcvFu2txVFl"},"grp":[
{"id":1249550,"mid":"003dtkNk26WhJD","name":"富士山下","title":"富士山下","subtitle":"《爱情呼叫转移》电影主题曲","interval":259,"time_public":"2019-12-23","language":1,"genre":0,"isonly":0,"index_cd":0,"index_album":5,"label":"0","singer":[{"id":143,"mid":"003Nz2So3XXYek","name":"陈奕迅"}],"album":{"id":51144,"mid":"003nMzes28P7wv","name":"What's Going On...? (Remastered 2019)","time_public":"","title":"What's Going On...? (Remastered 2019)"},"grp":[]}]}
]}}}}}
''';

/// QQ 音乐 `fcg_v8_album_info_cp.fcg`（实抓；list[0] 原样，裁掉了无关字段）。
const String qqAlbumJson = r'''
{"code":0,"subcode":0,"message":"succ","data":{"id":8220,"mid":"000MkMni19ClKG","name":"叶惠美","singername":"周杰伦","singermid":"0025NhlN2yWrP4","lan":"国语","aDate":"2003-07-31","total":11,"company":"杰威尔音乐有限公司","desc":"","list":[
{"albumdesc":"","albumid":8220,"albummid":"000MkMni19ClKG","albumname":"叶惠美","alertid":41,"belongCD":1,"cdIdx":0,"interval":342,"isonly":0,"label":"0","msgid":13,"rate":23,"singer":[{"id":4558,"mid":"0025NhlN2yWrP4","name":"周杰伦"}],"size128":5473371,"size320":13682683,"sizeape":0,"sizeflac":33950377,"sizeogg":7501924,"songid":97771,"songmid":"001n4C3p1yv0FU","songname":"以父之名","songorig":"以父之名","songtype":0,"strMediaMid":"002ExFMX2Jt6gv","stream":13,"switch":16897281,"type":0,"vid":"r00138f4quj"}]}}
''';

/// QQ 音乐歌词的**真实**前 10 行（由实抓响应里的 base64 解出）。
const String qqLrcHead = '[ti:晴天]\n'
    '[ar:周杰伦]\n'
    '[al:叶惠美]\n'
    '[by:]\n'
    '[offset:0]\n'
    '[00:00.00]晴天 - 周杰伦 (Jay Chou)\n'
    '[00:02.25]词：周杰伦\n'
    '[00:04.50]曲：周杰伦\n'
    '[00:06.75]编曲：周杰伦\n'
    '[00:09.00]制作人：周杰伦';

/// 实抓响应里那段 base64 的前 80 个字符（= 上面真实歌词的前 60 字节）。
const String qqLrcBase64Prefix =
    'W3RpOuaZtOWkqV0KW2FyOuWRqOadsOS8pl0KW2FsOuWPtuaDoOe+jl0KW2J5Ol0KW29mZnNldDowXQpb';

/// 酷狗 `mobilecdn.kugou.com/api/v3/search/song`（实抓，含 group）。
const String kgSearchSongJson = r'''
{"status":1,"errcode":0,"error":"","data":{"timestamp":1791040208,"total":480,"info":[{"hash":"16c8ab298231370293d16bcf9e5ff9b6","songname":"夜曲","album_name":"十一月的萧邦","songname_original":"夜曲","singername":"周杰伦","duration":226,"filename":"周杰伦 - 夜曲【网友热搜 : 肖邦的夜曲】","group":[{"hash":"f68ddc4048a40d82dd2594a294f4baf7","songname":"夜曲","album_name":"寂寞边境 月光爱人 情歌精选","songname_original":"夜曲","singername":"周杰伦","duration":226,"filename":"周杰伦 - 夜曲【网友热搜 : 肖邦的夜曲】","group":[]}]}]}}
''';

/// 酷狗 `lyrics.kugou.com/search`（实抓，2 个候选）。
const String kgSearchLyricsJson = r'''
{"status":200,"info":"OK","errcode":200,"errmsg":"OK","keyword":"夜曲","proposal":"649477717","has_complete_right":0,"ugc":0,"ugccount":0,"expire":7200,"candidates":[{"id":"649477717","product_from":"官方推荐歌词","accesskey":"802A097884D36A55192ABF0502A5C53C","can_score":false,"singer":"夜曲","song":"夜曲","duration":181000,"uid":"486953864","nickname":"热心用户","origiuid":"0","originame":"","transuid":"0","transname":"","sounduid":"0","soundname":"","language":"国语","krctype":2,"hitlayer":7,"hitcasemask":12,"adjust":0,"score":60,"contenttype":0,"content_format":1,"download_id":"649477717"},{"id":"649477711","accesskey":"ED22F4FAC2B6145B40499DFA4C68C53B","can_score":false,"singer":"夜曲","song":"夜曲","duration":181000,"language":"国语","krctype":2,"score":50,"content_format":1,"download_id":"649477711"}]}
''';

/// LRCLIB `/api/search` 的一条真实结果（`syncedLyrics` 只保留前两行）。
const String lrclibSearchJson = r'''
[{"id":36879197,"name":"夜曲","trackName":"夜曲","artistName":"周杰伦","albumName":"周傑倫2007世界巡回演唱會","duration":223.0,"instrumental":false,"hasWordSync":false,"plainLyrics":"一群嗜血的螞蟻 被腐肉所吸引 我面無表情 看孤獨的風景","syncedLyrics":"[00:24.63] 一群嗜血的螞蟻 被腐肉所吸引 我面無表情 看孤獨的風景\n[00:30.77] 失去妳 愛恨開始分明 失去妳 還有什麼事好關心"}]
''';

// ---------------------------------------------------------------------------
// eapi / weapi 黄金向量（由 .NET 独立算出，用于逐字节对齐）
// ---------------------------------------------------------------------------

/// `EapiHelper.EApi("https://interface3.music.163.com/eapi/song/lyric/v1", {...})`
/// 里那个固定 data 串对应的 params（AES-128-ECB + PKCS7，大写 hex）。
const String eapiGoldenParams =
    '04AE33D34A93FE3EC22DA8FA305D290AB337D0FE5F36D211DE0D338CC6AA89D0ACBBD9E916537A23C8CDD041F9433D121C74D20E42845AFF074D563E1FD95EB7759DAC206573304843CF051F1CB28CABEAA678329A53B1FB0700ECE0C8AB3D2D8B4B1D02C6029E69C8391D3843DD471C2FDE5E798EB694BF3B3CA98E02F3D545B2E2B98431183F815E83504D86C0C5F88666322D08DB15FD08AD3CA2092E21EBED90FCC66E7E01791876114DEC5B62D40167FCDF81D5146396A5B74B72D4F05D';

/// 上面那个固定 data 串（= `url-36cd479b6b5-{json}-36cd479b6b5-{md5lower}`）。
const String eapiGoldenData =
    '/api/song/lyric/v1-36cd479b6b5-{"id":"123","cp":"false","lv":"0","kv":"0","tv":"0","rv":"0","yv":"0","ytv":"0","yrv":"0","csrf_token":""}-36cd479b6b5-a662f24ddee8af868d2c6bcc52d287c3';

/// `Api.AESEncode('{"id":"123","os":"pc"}')`（CBC，IV 是 ASCII "0102030405060708"，PKCS7）。
const String aesCbcGolden = 'BznJt1bKgMwwEPUYGnNey/0cwz30DmXr9gGP5j4KR6U=';

/// `Api.AESEncode('{"csrf_token":""}')`。
const String aesCbcGolden2 = '3aDaLonxF5k4SQY7FM9HgsKnjHVqyNlEl3IDhOlL3xw=';

/// `Api.AESEncode('{"id":"123","os":"pc"}', NONCE)`。
const String aesCbcNonceGolden = 'R5SaZLtu/XNi9Nves/UN4rVmjDenGPiDUXqq/K0oIGg=';

/// `Api.prepare('{"csrf_token":""}')` 的 params（= 两次 AES-CBC 的 base64）。
const String prepareGolden2 =
    '68i8DF91+6gmLErs+lE6xvJ/lCISQEpKbgbcY4lwC13p6qeD+aNFc1nqj3WsXjyF';

/// `Api.prepare('{"id":"123","os":"pc"}')` 的 params。
const String prepareGolden =
    'iNdhVzVZTUA4EuUK7uq0CduEz+I7s+EXQVjVT5rY4jrEPs2Kbq2MFi3pKsaDG22s';

/// `Api.RSAEncode('abcdefghijklmnop')`（BigInteger.ModPow(010001, MODULUS)）。
const String rsaGolden =
    'd15a1683c992095d0c234c19966605c5c5964911268bbeda8cb8d08d834913e59d53b32358903a121b5fca784c1f5ae44951fd02524df58ecc98e52cc7cf8689b42c2e93ddf05b0592512d87f5960467e2f086c018849d76014d323500e30f13ef4cafbb0cf5a66731a3f1776c75ca35d0062dac70a3e33245afabcf47938487';

/// hex → bytes。
List<int> hexToBytes(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

void main() {
  late LyricsHttpClient originalClient;

  setUp(() {
    originalClient = BaseApi.httpClient;
  });

  tearDown(() {
    BaseApi.httpClient = originalClient;
  });

  // -------------------------------------------------------------------------
  group('网易云 eapi 加密（离线黄金向量，对齐 .NET）', () {
    test('EApi 的 params 与 .NET 逐字节一致（大写 hex）', () {
      final data = <String, String>{
        'id': '123',
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
      final result = EapiHelper.eApi(
          'https://interface3.music.163.com/eapi/song/lyric/v1', data);

      expect(result['params'], eapiGoldenParams);
      // 大写 hex：只含 0-9A-F，长度为偶数。
      expect(result['params']!.length.isEven, isTrue);
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(result['params']!), isTrue);
    });

    test('params 能解回原文（MD5 用小写 hex，分隔符 36cd479b6b5）', () {
      final data = <String, String>{
        'id': '123',
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
      final result = EapiHelper.eApi(
          'https://interface3.music.163.com/eapi/song/lyric/v1', data);

      final plain =
          utf8.decode(EapiHelper.decrypt(hexToBytes(result['params']!)));
      expect(plain, eapiGoldenData);
      // 摘要段必须是 `nobody{url}use{json}md5forencrypt` 的小写 MD5。
      final digest = plain.split('-36cd479b6b5-').last;
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(digest), isTrue);
    });

    test('url 替换：interface3/interface 的 /e 前缀换成 /', () {
      final plain = utf8.decode(EapiHelper.decrypt(hexToBytes(EapiHelper.eApi(
          'https://interface.music.163.com/eapi/cloudsearch/pc',
          <String, String>{})['params']!)));
      expect(plain, startsWith('/api/cloudsearch/pc-36cd479b6b5-'));
      // 摘要 = md5('nobody{url}use{json}md5forencrypt')，所以 'use' 只体现在摘要里；
      // 明文串本身只由 url / 分隔符 / json / 分隔符 / md5 组成。
      expect(plain,
          matches(RegExp(r'^/api/cloudsearch/pc-36cd479b6b5-\{\}-36cd479b6b5-[0-9a-f]{32}$')));
    });

    test('Api.AESEncode（weapi 用的 CBC）与 .NET 一致', () {
      expect(ne.Api.aesEncode('{"id":"123","os":"pc"}'), aesCbcGolden);
      expect(ne.Api.aesEncode('{"csrf_token":""}'), aesCbcGolden2);
      expect(ne.Api.aesEncode('{"id":"123","os":"pc"}', ne.Api.nonce),
          aesCbcNonceGolden);
      // params = base64(base64(raw, NONCE), secretKey)
      final inner = ne.Api.aesEncode('{"id":"123","os":"pc"}', ne.Api.nonce);
      expect(ne.Api.aesEncode(inner), prepareGolden);
    });

    test('Api.RSAEncode 与 .NET BigInteger.ModPow 一致（encSecKey 256 hex）', () {
      final api = ne.Api(secretKey: 'abcdefghijklmnop');
      expect(api.encSecKey, rsaGolden);
      expect(api.encSecKey.length, 256);
    });

    test('Api.prepare：params 是两次 AES-CBC 的 base64，encSecKey 是 256 hex', () {
      final api = ne.Api(secretKey: 'abcdefghijklmnop');
      final body = jsonDecode(api.prepare('{"csrf_token":""}')) as Map;
      expect(body['encSecKey'], rsaGolden);
      expect(body['params'], prepareGolden2);
      expect(api.prepare('{"id":"123","os":"pc"}'), contains(prepareGolden));
    });
  });

  // -------------------------------------------------------------------------
  group('网易云 Api', () {
    test('search：URL/方法/中文编码/请求头 + DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) => neSearchJson);
      BaseApi.httpClient = fake;

      final result = await ne.Api().search('夜曲', ne.SearchTypeEnum.songId);

      final req = fake.last;
      expect(req.method, 'GET');
      expect(req.url.host, 'music.163.com');
      expect(req.url.path, '/api/search/get/web');
      expect(req.url.query, contains('csrf_token=hlpretag='));
      expect(req.url.query, contains('hlposttag='));
      // 中文关键词 → UTF-8 百分号编码（与 C# Uri.EscapeDataString 一致）。
      expect(req.url.query, contains('s=%E5%A4%9C%E6%9B%B2'));
      expect(req.url.query, contains('type=1'));
      expect(req.url.query, contains('offset=0'));
      expect(req.url.query, contains('total=true'));
      expect(req.url.query, contains('limit=20'));
      expect(req.headers['Referer'], 'https://music.163.com/');
      expect(req.headers['Cookie'], contains('os=pc'));
      expect(req.headers['Cookie'], contains('appver=2.0.3.131777'));
      expect(req.headers['User-Agent'], contains('Chrome/63.0.3239.132'));

      expect(result, isNotNull);
      expect(result!.code, 200);
      expect(result.result.songCount, 333);
      final song = result.result.songs.single;
      expect(song.name, '夜曲');
      // 上游 `Id` 是 string，线上是数字 → 取成 '2725685941'
      expect(song.id, '2725685941');
      expect(song.duration, 233956);
      expect(song.artists!.single.name, 'Xai小爱');
      expect(song.artists!.single.id, 98459986);
      expect(song.album!.name, '夜曲');
      expect(song.album!.id, 278269102);
      // PORT NOTE: 线上 album 里是 `picId`，而上游 `Al` 只映射 id/name/picUrl/tns/pic
      // （没有 picId），所以 `pic` 取不到值 —— 与 Newtonsoft 行为一致，故为 0。
      expect(song.album!.pic, 0);
      expect(song.album!.tns, isEmpty);
    });

    test('search：失败时按上游语义抛异常（不吞）', () async {
      BaseApi.httpClient = FakeLyricsHttpClient((_) => 'boom', statusCode: 500);
      final api = ne.Api();
      await expectLater(
        api.search('夜曲', ne.SearchTypeEnum.songId),
        throwsA(isA<LyricsHttpException>()),
      );
    });

    test('searchNew：POST 表单 + eapi params 解回原文 + DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) => neEapiSearchJson);
      BaseApi.httpClient = fake;

      final result = await ne.Api(secretKey: 'abcdefghijklmnop').searchNew('夜曲');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://interface.music.163.com/eapi/cloudsearch/pc');
      expect(req.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(req.headers['Referer'], 'https://music.163.com/');

      final form = parseForm(req.body!);
      // 上游 `EApi` 只往请求体里放一个 params（header 是加密进去的）。
      expect(form.keys, contains('params'));
      expect(RegExp(r'^[0-9A-F]+$').hasMatch(form['params']!), isTrue);

      final plain = utf8.decode(EapiHelper.decrypt(hexToBytes(form['params']!)));
      // 上游 `EApi` 把 interface 的 /e 前缀换成 /，所以这里是 /api/cloudsearch/pc
      expect(plain, startsWith('/api/cloudsearch/pc-36cd479b6b5-'));
      expect(plain, contains('"s":"夜曲"'));
      expect(plain, contains('"type":"1"'));
      expect(plain, contains('"limit":"30"'));
      expect(plain, contains('"offset":"0"'));
      expect(plain, contains('"total":"true"'));
      expect(plain, contains('"header":'));
      // PORT NOTE: 上游 `data["header"] = JsonConvert.SerializeObject(header)`，而 data 是
      // Dictionary<string,string>，于是 header 被**二次编码**成 JSON 里的转义字符串
      // （`"header":"{\"__csrf\":\"\",...}"`）。这里断言转义后的形态。
      expect(plain, contains(r'\"appver\":\"8.0.0\"'));
      expect(plain, contains(r'\"resolution\":\"1920x1080\"'));
      expect(plain, contains(r'\"os\":\"android\"'));
      expect(plain, contains(r'\"versioncode\":\"140\"'));
      expect(plain, contains(r'\"__csrf\":\"\"'));
      expect(plain, contains(r'\"MUSIC_U\":\"\"'));
      expect(plain, contains(r'\"buildver\":\"'));
      expect(plain, contains(r'\"requestId\":\"'));
      // 摘要段自洽：nobody{url}use{json}md5forencrypt 的小写 MD5
      final separator = plain.indexOf('-36cd479b6b5-');
      final second = plain.indexOf('-36cd479b6b5-', separator + 1);
      expect(plain.substring(0, separator), '/api/cloudsearch/pc');
      final text = plain.substring(separator + 16, second);
      final digest = plain.substring(second + 16);
      expect(text, contains('"s":"夜曲"'));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(digest), isTrue);

      // Cookie 头是 header 的 k=v 拼接
      expect(req.headers['Cookie'], contains('MUSIC_U='));
      expect(req.headers['Cookie'], contains('appver=8.0.0'));
      expect(req.headers['Cookie'], contains('buildver='));
      expect(req.headers['Cookie'], contains('resolution=1920x1080'));
      expect(req.headers['User-Agent'], contains('HuaweiBrowser/10.0.3.311'));

      // DTO：EapiSong 的 [JsonProperty] 字段（ar/alia/al/dt）都要取到
      expect(result, isNotNull);
      expect(result!.code, 200);
      final song = result.result.songs.single;
      expect(song.name, '晴天');
      expect(song.id, '186016');
      expect(song.duration, 269590);
      expect(song.artists!.single.name, '周杰伦');
      expect(song.album!.name, '叶惠美');
      expect(song.privilege!.maxbr, 999000);
      expect(song.publishTime, 1147104000000);
      expect(result.result.songCount, 1);
      expect(result.needLogin, isFalse);
    });

    test('getLyricNew：eapi params 能解回 id，LyricResult 取到 yrc 逐字', () async {
      final fake = FakeLyricsHttpClient((_) => neLyricJson);
      BaseApi.httpClient = fake;

      final result = await ne.Api(secretKey: 'abcdefghijklmnop').getLyricNew('186016');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://interface3.music.163.com/eapi/song/lyric/v1');
      final form = parseForm(req.body!);
      final plain = utf8.decode(EapiHelper.decrypt(hexToBytes(form['params']!)));
      expect(plain, startsWith('/api/song/lyric/v1-36cd479b6b5-'));
      expect(plain, contains('"id":"186016"'));
      expect(plain, contains('"cp":"false"'));
      expect(plain, contains('"lv":"0"'));
      expect(plain, contains('"ytv":"0"'));
      expect(plain, contains('"yrv":"0"'));

      expect(result!.code, 200);
      expect(result.lrc!.lyric, contains('晴天 - 周杰伦'));
      expect(result.yrc!.lyric, contains('(0,300,0)晴'));
      expect(result.tlyric!.lyric, '');
      expect(result.romalrc!.version, 0);
      expect(result.sgc, isFalse);
    });

    test('getLyric：weapi 的 JSON 体里 params 是双层 base64、encSecKey 是 256 hex',
        () async {
      final fake = FakeLyricsHttpClient((_) => neLyricJson);
      BaseApi.httpClient = fake;

      final result = await ne.Api(secretKey: 'abcdefghijklmnop').getLyric('186016');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://music.163.com/weapi/song/lyric?csrf_token=');
      // 上游 `PostAsync(url, string)` 用 StringContent(..., "application/json")，
      // 所以体是 JSON（`{"params":...,"encSecKey":...}`）而不是表单。
      expect(req.headers['Content-Type'], 'application/json');
      final body = jsonDecode(req.body!) as Map<String, dynamic>;
      expect(body['encSecKey'], rsaGolden);
      expect(RegExp(r'^[0-9a-f]{256}$').hasMatch(body['encSecKey'] as String), isTrue);
      expect(decodeWeapiParams(weapiParamsOf(req.body!)), contains('"id":"186016"'));
      expect(decodeWeapiParams(weapiParamsOf(req.body!)), contains('"lv":"-1"'));
      expect(decodeWeapiParams(weapiParamsOf(req.body!)), contains('"csrf_token":""'));
      expect(result!.lrc!.lyric, contains('晴天'));
    });

    test('getSongs/getAlbum/getPlaylist/getDatum 的 URL 与入参', () async {
      final fake = FakeLyricsHttpClient((req) {
        if (req.url.path.contains('song/detail')) {
          return '{"songs":[{"name":"夜曲","id":"1","duration":1000}],"privileges":[],"code":200}';
        }
        if (req.url.path.contains('player/url')) {
          return '{"data":[{"id":"1","url":"http://x/1.mp3","br":999000,"size":10,"code":200}],"code":200}';
        }
        if (req.url.path.contains('album')) {
          return '{"songs":[{"name":"夜曲","id":"1"}],"code":200,"album":{"name":"十一月的萧邦","id":2}}';
        }
        return '{"code":200,"playlist":{"id":"3","name":"歌单","tracks":[{"name":"夜曲","id":"1"}]},"privileges":[]}';
      });
      BaseApi.httpClient = fake;
      final api = ne.Api(secretKey: 'abcdefghijklmnop');

      final songs = await api.getSongs(['1', '2']);
      expect(songs['1']!.name, '夜曲');
      expect(decodeWeapiParams(weapiParamsOf(fake.last.body!)),
          contains('"c":"[{\'id\':\'1\'},{\'id\':\'2\'}]"'));
      expect(fake.last.url.path, '/weapi/v3/song/detail');

      final album = await api.getAlbum('278269102');
      expect(album!.album!.name, '十一月的萧邦');
      expect(fake.last.url.path, '/weapi/v1/album/278269102');

      final playlist = await api.getPlaylist('123');
      expect(playlist!.playlist!.name, '歌单');
      expect(playlist.playlist!.tracks.single.name, '夜曲');
      expect(fake.last.url.path, '/weapi/v6/playlist/detail');

      final datum = await api.getDatum(['1', '2']);
      final form = decodeWeapiParams(weapiParamsOf(fake.last.body!));
      expect(form, contains('"ids":"[1,2]"'));
      expect(form, contains('"br":"999000"'));
      expect(datum['1']!.url, 'http://x/1.mp3');

      // 空 id 列表：上游直接返回空字典，不发请求
      final before = fake.requests.length;
      expect(await api.getSongs([]), isEmpty);
      expect(fake.requests.length, before);
    });
  });

  // -------------------------------------------------------------------------
  group('QQ 音乐 Api', () {
    test('search：URL/JSON 体/中文关键词 + DTO 取值（含 grp 同版本）', () async {
      final fake = FakeLyricsHttpClient((_) => qqSearchJson);
      BaseApi.httpClient = fake;

      final result = await qq.Api().search('富士山下', qq.SearchTypeEnum.songId);

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://u.y.qq.com/cgi-bin/musicu.fcg');
      expect(req.headers['Content-Type'], 'application/json');
      expect(req.headers['Referer'], 'https://c.y.qq.com/');

      // 中文关键词按 UTF-8 原样放进 JSON（与 C# JsonConvert 一致，不做 \u 转义）
      expect(req.body, contains('"query":"富士山下"'));
      final body = jsonDecode(req.body!) as Map<String, dynamic>;
      final req1 = body['req_1'] as Map<String, dynamic>;
      final param = req1['param'] as Map<String, dynamic>;
      expect(req1['method'], 'DoSearchForQQMusicDesktop');
      expect(req1['module'], 'music.search.SearchCgiService');
      expect(param['num_per_page'], '20');
      expect(param['page_num'], '1');
      expect(param['search_type'], 0);

      expect(result, isNotNull);
      expect(result!.code, 0);
      expect(result.req1!.code, 0);
      expect(result.req1!.data!.ver, 0);
      expect(result.req1!.data!.meta!.query, '富士山下');
      expect(result.req1!.data!.meta!.sum, 1939);
      expect(result.ts, 1791040217535);
      expect(result.startTs, 1791040217266);
      expect(result.traceid, '4d6c2b5b206e8893');

      final song = result.req1!.data!.body!.song!.list.single;
      expect(song.name, '富士山下');
      expect(song.title, '富士山下');
      expect(song.mid, '003aAPj81VWrbL');
      expect(song.id, '260678');
      expect(song.interval, 259); // 秒
      expect(song.timePublic, '2007-01-25');
      expect(song.singer.single.name, '陈奕迅');
      expect(song.singer.single.mid, '003Nz2So3XXYek');
      expect(song.album!.name, "What's Going On...?");
      expect(song.album!.mid, '004Z85XP1c25b7');
      // PORT NOTE: 上游 QQ 的 `Song` 没有 ksong/label/index_* 字段，只映射
      // album/id/interval/mid/name/desc/singer/title/subtitle/time_public/grp/language/genre。
      expect(song.language, 1);
      expect(song.genre, 0);

      // grp（同版本曲目）
      final group = song.group.single;
      expect(group.id, '1249550');
      expect(group.mid, '003dtkNk26WhJD');
      expect(group.interval, 259);
      expect(group.timePublic, '2019-12-23');
      expect(group.subtitle, '《爱情呼叫转移》电影主题曲');
      expect(group.album!.name, "What's Going On...? (Remastered 2019)");
      expect(group.group, isEmpty);
    });

    test('searchAlternative：老接口的字符串 JSON 体', () async {
      final fake = FakeLyricsHttpClient((_) =>
          '{"code":0,"music.search.SearchCgiService":{"data":{"body":{"song":{"list":[{"id":"1","mid":"m","name":"n","interval":1,"singer":[],"album":{"id":1,"mid":"a","name":"al","title":"al","subtitle":"","time_public":"","pmid":""},"grp":[],"language":0,"genre":0,"desc":"","title":"n","subtitle":"","time_public":""}]}}}}}');
      BaseApi.httpClient = fake;

      final result = await qq.Api().searchAlternative('夜曲');
      expect(fake.last.url.toString(), 'https://u.y.qq.com/cgi-bin/musicu.fcg');
      expect(fake.last.headers['Content-Type'], 'application/json');
      expect(fake.last.body, contains('"music.search.SearchCgiService"'));
      expect(fake.last.body, contains('"query": "夜曲"'));
      expect(result!.search!.data!.body!.song!.list.single.name, 'n');
    });

    test('getAlbumSongList：JSON 体与 URL 参数 + DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) =>
          '{"code":0,"ts":1,"start_ts":2,"traceId":"t","albumSonglist":{"code":0,"data":{"albumMid":"000MkMni19ClKG","totalNum":11,"songList":[{"songInfo":{"id":1,"mid":"m","name":"以父之名","title":"以父之名","singer":[],"album":{"id":1,"mid":"a","name":"叶惠美"},"interval":342,"isOnly":0,"index_cd":0,"index_album":1,"time_public":"2003-07-31","status":0,"fnote":0,"label":0,"url":"","bpm":0,"version":0,"trace":"","data_type":0,"modify_stamp":0,"pingpong":"","aid":0,"ppurl":"","tid":0,"ov":0,"sa":0,"es":"","vs":[],"vi":[],"k_tag":""},"listenCount":5,"uploadTime":"2003-07-31","isThemeSong":0,"teamStr":""}],"classicList":[],"sort":0,"albumTips":"","index":0,"scheduleStatus":0,"curBegin":0,"cdNewStyle":0,"cdNameMap":{}}}}');
      BaseApi.httpClient = fake;

      final list = await qq.Api().getAlbumSongList('000MkMni19ClKG');
      expect(fake.last.url.query, contains('g_tk=5381'));
      expect(fake.last.url.query, contains('format=json'));
      expect(fake.last.url.query, contains('inCharset=utf8'));
      final body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      final albumSonglist = body['albumSonglist'] as Map<String, dynamic>;
      expect((albumSonglist['param'] as Map)['albumMid'], '000MkMni19ClKG');
      expect((albumSonglist['param'] as Map)['albumID'], 0);
      expect((albumSonglist['param'] as Map)['begin'], 0);
      expect((albumSonglist['param'] as Map)['num'], 1000);
      expect((albumSonglist['param'] as Map)['order'], 2);
      expect((body['comm'] as Map)['ct'], 24);
      expect((body['comm'] as Map)['cv'], 10000);

      expect(list!.albumSonglist!.code, 0);
      expect(list.albumSonglist!.data!.totalNum, 11);
      expect(list.startTs, 2);
      final item = list.albumSonglist!.data!.songList.single;
      expect(item.songInfo!.name, '以父之名');
      expect(item.songInfo!.interval, 342);
      expect(item.songInfo!.indexCd, 0);
      expect(item.songInfo!.timePublic, '2003-07-31');
      expect(item.songInfo!.album!.name, '叶惠美');
      expect(item.listenCount, 5);
    });

    test('getToplist：period 透传 + 日期型榜单的 yyyy-MM-dd 格式', () async {
      final fake = FakeLyricsHttpClient((_) => '{"code":0}');
      BaseApi.httpClient = fake;

      await qq.Api().getToplist(id: 4, page: 2, pageSize: 50, period: '2026-09-28');
      var body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      var param = (body['detail'] as Map)['param'] as Map;
      expect(param['topId'], 4);
      expect(param['offset'], 50);
      expect(param['num'], 50);
      expect(param['period'], '2026-09-28');
      expect((body['detail'] as Map)['module'], 'musicToplist.ToplistInfoServer');

      await qq.Api().getToplist(id: 26);
      body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      param = (body['detail'] as Map)['param'] as Map;
      expect(param['period'], matches(RegExp(r'^\d{4}-\d{1,2}$')));

      await qq.Api().getToplist(id: 4);
      body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      param = (body['detail'] as Map)['param'] as Map;
      expect(param['period'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('getAlbum：表单 body + DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) => qqAlbumJson);
      BaseApi.httpClient = fake;

      final result = await qq.Api().getAlbum('000MkMni19ClKG');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg');
      expect(req.headers['Content-Type'], 'application/x-www-form-urlencoded');
      expect(req.body, 'albummid=000MkMni19ClKG');

      expect(result!.code, 0);
      expect(result.message, 'succ');
      expect(result.data!.name, '叶惠美');
      expect(result.data!.mid, '000MkMni19ClKG');
      expect(result.data!.singername, '周杰伦');
      expect(result.data!.aDate, '2003-07-31');
      expect(result.data!.lan, '国语');
      expect(result.data!.total, 11);
      expect(result.data!.company, '杰威尔音乐有限公司');

      final song = result.data!.list.single;
      expect(song.songname, '以父之名');
      expect(song.songmid, '001n4C3p1yv0FU');
      expect(song.songid, 97771);
      // PORT NOTE: 上游 `AlbumInfo.AlbumSong` 只映射 singer/songid/songmid/songname，
      // 线上 list 里的 interval 等字段没有对应属性（照上游保留）。
      expect(song.singer.single.name, '周杰伦');
      expect(song.singer.single.mid, '0025NhlN2yWrP4');
    });

    test('getLyric：jsonp 剥离 + base64 解码成真实 LRC', () async {
      final b64 = base64.encode(utf8.encode(qqLrcHead));
      // 内置 LRC 与实抓响应的 base64 前缀一致（前 60 字节逐字节相同）
      expect(
        qqLrcHead.startsWith(utf8.decode(base64.decode(qqLrcBase64Prefix))),
        isTrue,
      );

      final fake = FakeLyricsHttpClient((_) =>
          'MusicJsonCallback_lrc({"retcode":0,"code":0,"subcode":0,"lyric":"$b64","trans":""})');
      BaseApi.httpClient = fake;

      final result = await qq.Api().getLyric('0039MnYb0qxYhV');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg');
      final form = parseForm(req.body!);
      expect(form['songmid'], '0039MnYb0qxYhV');
      expect(form['g_tk'], '5381'); // QQ 的 sign 参数
      expect(form['callback'], 'MusicJsonCallback_lrc');
      expect(form['jsonpCallback'], 'MusicJsonCallback_lrc');
      expect(form['format'], 'jsonp');
      expect(form['inCharset'], 'utf8');
      expect(form['outCharset'], 'utf8');
      expect(form['platform'], 'yqq');
      expect(form['loginUin'], '0');
      expect(form['hostUin'], '0');
      expect(form['needNewCode'], '0');
      expect(form['notice'], '0');
      // pcachetime 是毫秒时间戳（本地时间轴）
      expect(RegExp(r'^\d{12,}$').hasMatch(form['pcachetime']!), isTrue);

      expect(result!.code, 0);
      // Decode() 把 base64 解成 UTF-8 的 LRC 原文
      expect(result.lyric, qqLrcHead);
      expect(result.lyric, startsWith('[ti:晴天]'));
      expect(result.lyric, contains('[00:02.25]词：周杰伦'));
    });

    test('getLyric：响应没带 callback 前缀时返回 null', () async {
      BaseApi.httpClient = FakeLyricsHttpClient((_) => '{"code":0}');
      expect(await qq.Api().getLyric('0039MnYb0qxYhV'), isNull);
    });

    test('getSong：数字 id 用 songid，mid 用 songmid', () async {
      final fake = FakeLyricsHttpClient((_) =>
          'getOneSongInfoCallback({"code":0,"data":[{"id":"97771","mid":"001n4C3p1yv0FU","name":"以父之名","interval":342,"singer":[{"name":"周杰伦","mid":"0025NhlN2yWrP4"}],"album":{"name":"叶惠美","mid":"000MkMni19ClKG"}}]})');
      BaseApi.httpClient = fake;
      final api = qq.Api();

      final byId = await api.getSong('97771');
      expect(parseForm(fake.last.body!).keys, contains('songid'));
      expect(parseForm(fake.last.body!)['songid'], '97771');
      expect(parseForm(fake.last.body!).containsKey('songmid'), isFalse);
      expect(fake.last.url.path, '/v8/fcg-bin/fcg_play_single_song.fcg');
      expect(byId!.code, 0);
      expect(byId.data.single.id, '97771');
      expect(byId.data.single.name, '以父之名');
      expect(byId.data.single.interval, 342);
      expect(byId.data.single.singer.single.name, '周杰伦');
      expect(byId.data.single.album!.name, '叶惠美');
      expect(byId.isIllegal(), isFalse);

      final byMid = await api.getSong('001n4C3p1yv0FU');
      expect(parseForm(fake.last.body!).keys, contains('songmid'));
      expect(parseForm(fake.last.body!).containsKey('songid'), isFalse);
      expect(byMid!.data.single.mid, '001n4C3p1yv0FU');
    });

    test('getLyricsAsync：XML 解出 content/contentts（非 hex 时按上游走 LRC 兜底）',
        () async {
      const trans = '[00:00.00]Sunny Day - Jay Chou';
      final xml = '<?xml version="1.0" encoding="utf-8"?>\n'
          '<root>\n'
          '<!--这是被剥掉的注释-->\n'
          '<content>$qqLrcHead</content>\n'
          '<contentts>$trans</contentts>\n'
          '</root>';
      final fake = FakeLyricsHttpClient((_) => xml);
      BaseApi.httpClient = fake;

      final result = await qq.Api().getLyricsAsync('97771');

      final req = fake.last;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg');
      final form = parseForm(req.body!);
      expect(form['version'], '15');
      expect(form['miniversion'], '82');
      expect(form['lrctype'], '4');
      expect(form['musicid'], '97771');

      expect(result, isNotNull);
      expect(result!.lyrics, qqLrcHead);
      expect(result.trans, trans);
    });

    test('getLyricsAsync：XML 里没有可用内容时返回 null', () async {
      BaseApi.httpClient =
          FakeLyricsHttpClient((_) => '<?xml version="1.0"?><root></root>');
      expect(await qq.Api().getLyricsAsync('97771'), isNull);
    });

    test('getSongLink：guid 是 10 位数字，正文含 req/req_0/comm', () async {
      final fake = FakeLyricsHttpClient((_) =>
          '{"code":0,"req":{"code":0,"data":{"sip":["http://isure.stream.qqmusic.qq.com/"]}},"req_0":{"code":0,"data":{"midurlinfo":[{"songmid":"003aAPj81VWrbL","purl":"M500003aAPj81VWrbL.mp3"}]}}}');
      BaseApi.httpClient = fake;

      final link = await qq.Api().getSongLink('003aAPj81VWrbL');
      expect(link, 'http://isure.stream.qqmusic.qq.com/M500003aAPj81VWrbL.mp3');
      final body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      final guid = ((body['req'] as Map)['param'] as Map)['guid'] as String;
      expect(RegExp(r'^\d{10}$').hasMatch(guid), isTrue);
      expect((body['req_0'] as Map)['method'], 'CgiGetVkey');
      expect(((body['req_0'] as Map)['param'] as Map)['songmid'], ['003aAPj81VWrbL']);
      expect((body['comm'] as Map)['ct'], 24);
      expect((body['comm'] as Map)['uin'], 0);
    });

    test('getPlaylist/getSingerSongs 的 URL 与参数', () async {
      final fake = FakeLyricsHttpClient((_) => '{"code":0}');
      BaseApi.httpClient = fake;
      final api = qq.Api();

      await api.getPlaylist('123');
      var form = parseForm(fake.last.body!);
      expect(fake.last.url.path, '/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg');
      expect(form['disstid'], '123');
      expect(form['onlysong'], '0');
      expect(form['new_format'], '1');
      expect(form['format'], 'json');

      await api.getSingerSongs('0025NhlN2yWrP4', page: 2, pageSize: 10);
      final body = jsonDecode(fake.last.body!) as Map<String, dynamic>;
      final param = (body['singer'] as Map)['param'] as Map;
      expect((body['singer'] as Map)['method'], 'get_singer_detail_info');
      expect(param['singermid'], '0025NhlN2yWrP4');
      expect(param['sin'], 10);
      expect(param['num'], 10);
      expect(param['sort'], 5);
    });

    test('DTO：QQ LyricResult.Decode 与 SongResult.IsIllegal 直测', () {
      final lyric = qqresp.LyricResult.fromJson(<String, dynamic>{
        'code': 0,
        'lyric': base64.encode(utf8.encode(qqLrcHead)),
        'trans': base64.encode(utf8.encode('[00:00.00]t')),
      });
      expect(lyric.decode().lyric, qqLrcHead);
      expect(lyric.trans, '[00:00.00]t');

      final illegal = qqresp.SongResult.fromJson(<String, dynamic>{
        'code': 1,
        'data': <dynamic>[],
      });
      expect(illegal.isIllegal(), isTrue);
      expect(illegal.data, isEmpty);

      final ok = qqresp.SongResult.fromJson(<String, dynamic>{
        'code': 0,
        'data': [
          {'id': '1'}
        ],
      });
      expect(ok.isIllegal(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('酷狗 Api', () {
    test('getSearchSong：URL/DTO（含 group 同歌曲版本）', () async {
      final fake = FakeLyricsHttpClient((_) => kgSearchSongJson);
      BaseApi.httpClient = fake;

      final result = await kg.Api().getSearchSong('夜曲');

      final req = fake.last;
      expect(req.method, 'GET');
      expect(req.url.toString(),
          'http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=%E5%A4%9C%E6%9B%B2&page=1&pagesize=20&showtype=1');
      // 酷狗没有 Referer
      expect(req.headers.containsKey('Referer'), isFalse);
      expect(req.headers['User-Agent'], contains('Chrome/63.0.3239.132'));

      expect(result!.status, 1);
      expect(result.error, '');
      expect(result.errorCode, 0);
      expect(result.data!.timestamp, 1791040208);
      expect(result.data!.total, 480);

      final item = result.data!.info.single;
      expect(item.hash, '16c8ab298231370293d16bcf9e5ff9b6');
      expect(item.songName, '夜曲');
      expect(item.singerName, '周杰伦');
      expect(item.albumName, '十一月的萧邦');
      expect(item.songNameOriginal, '夜曲');
      expect(item.duration, 226); // 秒
      expect(item.filename, '周杰伦 - 夜曲【网友热搜 : 肖邦的夜曲】');

      final group = item.group.single;
      expect(group.hash, 'f68ddc4048a40d82dd2594a294f4baf7');
      expect(group.albumName, '寂寞边境 月光爱人 情歌精选');
      expect(group.group, isEmpty);
    });

    test('getSearchLyrics：具名可选参数 + URL/DTO', () async {
      final fake = FakeLyricsHttpClient((_) => kgSearchLyricsJson);
      BaseApi.httpClient = fake;

      final result = await kg.Api().getSearchLyrics(
        keywords: '夜曲',
        duration: 226000,
        hash: 'AABBCC',
      );

      final req = fake.last;
      expect(req.method, 'GET');
      expect(req.url.toString(),
          'https://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=%E5%A4%9C%E6%9B%B2&duration=226000&hash=AABBCC');

      expect(result!.status, 200);
      expect(result.errorCode, 200);
      expect(result.errorMessage, 'OK');
      expect(result.info, 'OK');
      expect(result.proposal, '649477717');
      expect(result.hasCompleteRight, 0);
      expect(result.ugc, 0);
      expect(result.ugcCount, 0);
      expect(result.expire, 7200);
      // PORT NOTE：上游属性名拼错成 `Keywork`，这里按线上字段名 keyword 取。
      expect(result.keyword, '夜曲');

      expect(result.candidates.length, 2);
      final first = result.candidates.first;
      expect(first.id, '649477717');
      expect(first.accessKey, '802A097884D36A55192ABF0502A5C53C');
      expect(first.song, '夜曲');
      expect(first.singer, '夜曲');
      expect(first.duration, 181000);
      expect(first.productFrom, '官方推荐歌词');
      expect(first.canScore, isFalse);
      expect(first.language, '国语');
      expect(first.krcType, 2);
      expect(first.contentFormat, 1);
      expect(first.score, 60);
      expect(first.nickname, '热心用户');
      expect(first.hitlayer, 7);
      // 上游属性 TransId 对应线上 download_id
      expect(first.transId, '649477717');

      final second = result.candidates[1];
      expect(second.id, '649477711');
      expect(second.accessKey, 'ED22F4FAC2B6145B40499DFA4C68C53B');
      expect(second.score, 50);
    });

    test('getSearchLyrics：不传可选参数时 keyword=/hash= 为空', () async {
      final fake = FakeLyricsHttpClient((_) => '{"status":200,"candidates":[]}');
      BaseApi.httpClient = fake;

      final result = await kg.Api().getSearchLyrics();
      expect(fake.last.url.query, 'ver=1&man=yes&client=pc&keyword=&hash=');
      expect(result!.candidates, isEmpty);
      expect(result.keyword, '');
    });

    test('getSearchSong：响应不是 JSON 时返回 null（不抛）', () async {
      BaseApi.httpClient = FakeLyricsHttpClient((_) => '<html>404</html>');
      expect(await kg.Api().getSearchSong('夜曲'), isNull);
    });

    test('DTO 别名：InfoItem 就是 DataItemInfoItem（Searcher 侧按上游名字用）', () {
      final item = kgresp.InfoItem.fromJson(<String, dynamic>{
        'hash': 'h',
        'songname': 'n',
        'singername': 's',
        'duration': 1,
      });
      expect(item, isA<kgresp.DataItemInfoItem>());
      expect(item.hash, 'h');
      expect(item.songName, 'n');
      expect(item.group, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('LRCLIB Api', () {
    test('search：URL（中文编码 + UA）+ DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) => lrclibSearchJson);
      BaseApi.httpClient = fake;

      final result = await lrclib.Api().search('夜曲', '周杰伦');

      final req = fake.last;
      expect(req.method, 'GET');
      expect(req.url.toString(),
          'https://lrclib.net/api/search?track_name=%E5%A4%9C%E6%9B%B2&artist_name=%E5%91%A8%E6%9D%B0%E4%BC%A6');
      // LRCLIB 的 UA 必须带上（上游逐字）
      expect(req.headers['User-Agent'],
          'Lyricify-Lyrics-Helper (https://github.com/WXRIW/Lyricify-Lyrics-Helper)');
      expect(req.headers.containsKey('Referer'), isFalse);

      expect(result, isNotNull);
      final item = result!.single;
      expect(item.id, 36879197);
      expect(item.name, '夜曲');
      expect(item.trackName, '夜曲');
      expect(item.artistName, '周杰伦');
      expect(item.albumName, '周傑倫2007世界巡回演唱會');
      expect(item.duration, 223.0);
      expect(item.instrumental, isFalse);
      expect(item.syncedLyrics, contains('[00:24.63] 一群嗜血的螞蟻'));
      expect(item.plainLyrics, contains('一群嗜血的螞蟻'));
    });

    test('search：albumName / duration 可选参数追加到 URL', () async {
      final fake = FakeLyricsHttpClient((_) => '[]');
      BaseApi.httpClient = fake;

      await lrclib.Api().search('夜曲', '周杰伦', '叶惠美', 223.0);
      expect(fake.last.url.query, contains('album_name=%E5%8F%B6%E6%83%A0%E7%BE%8E'));
      expect(fake.last.url.query, contains('duration=223.0'));
    });

    test('search：只给曲目名时没有 artist_name/album_name/duration', () async {
      final fake = FakeLyricsHttpClient((_) => '[]');
      BaseApi.httpClient = fake;

      await lrclib.Api().search('夜曲');
      expect(fake.last.url.query, 'track_name=%E5%A4%9C%E6%9B%B2');
    });

    test('get：URL + GetLyricResult 取值（syncedLyrics/plainLyrics/id）', () async {
      final fake = FakeLyricsHttpClient((_) =>
          '{"id":36879197,"name":"夜曲","trackName":"夜曲","artistName":"周杰伦","albumName":"十一月的萧邦","duration":223.0,"instrumental":false,"plainLyrics":"一群嗜血的螞蟻","syncedLyrics":"[00:24.63] 一群嗜血的螞蟻\\n[00:30.77] 失去妳"}');
      BaseApi.httpClient = fake;

      final result = await lrclib.Api().get('夜曲', '周杰伦');

      expect(fake.last.method, 'GET');
      expect(fake.last.url.toString(),
          'https://lrclib.net/api/get?track_name=%E5%A4%9C%E6%9B%B2&artist_name=%E5%91%A8%E6%9D%B0%E4%BC%A6');
      expect(result, isNotNull);
      expect(result!.id, 36879197);
      expect(result.trackName, '夜曲');
      expect(result.artistName, '周杰伦');
      expect(result.duration, 223.0);
      expect(result.syncedLyrics, startsWith('[00:24.63] 一群嗜血的螞蟻'));
      expect(result.syncedLyrics, contains('\n[00:30.77] 失去妳'));
      expect(result.plainLyrics, '一群嗜血的螞蟻');
    });

    test('get：albumName/duration 追加；响应缺 syncedLyrics 时为 null', () async {
      final fake = FakeLyricsHttpClient(
          (_) => '{"id":1,"trackName":"t","artistName":"a","plainLyrics":"p"}');
      BaseApi.httpClient = fake;

      final result = await lrclib.Api().get('夜曲', '周杰伦', '叶惠美', 223.0);
      expect(fake.last.url.query, contains('album_name=%E5%8F%B6%E6%83%A0%E7%BE%8E'));
      expect(fake.last.url.query, contains('duration=223.0'));
      expect(result!.id, 1);
      expect(result.syncedLyrics, isNull);
      expect(result.plainLyrics, 'p');
    });

    test('getById：URL 是 /get/{id} + DTO 取值', () async {
      final fake = FakeLyricsHttpClient((_) =>
          '{"id":36879197,"trackName":"夜曲","artistName":"周杰伦","syncedLyrics":"[00:24.63] x"}');
      BaseApi.httpClient = fake;

      final result = await lrclib.Api().getById(36879197);
      expect(fake.last.url.toString(), 'https://lrclib.net/api/get/36879197');
      expect(result!.id, 36879197);
      expect(result.syncedLyrics, '[00:24.63] x');
    });

    test('search/get/getById：出错时按上游语义返回 null（不抛）', () async {
      BaseApi.httpClient = FakeLyricsHttpClient((_) => 'not found', statusCode: 404);
      final api = lrclib.Api();
      expect(await api.search('夜曲'), isNull);
      expect(await api.get('夜曲', '周杰伦'), isNull);
      expect(await api.getById(1), isNull);
    });

    test('GetLyricResult/SearchResultItem 是各自独立的 DTO（都保留上游类名）', () {
      final a = lrclibresp.SearchResultItem.fromJson(<String, dynamic>{'id': 1});
      final b = lrclibresp.GetLyricResult.fromJson(<String, dynamic>{'id': 2});
      expect(a.id, 1);
      expect(b.id, 2);
      expect(a.duration, 0.0);
      expect(b.instrumental, isFalse);
      expect(a.syncedLyrics, isNull);
    });
  });
}
