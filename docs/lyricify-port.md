# Lyricify 歌词逻辑全量移植（规格 + 进度）

本文件是移植工作的**唯一契约**：所有参与移植的人/agent 都按这里的目录、命名、
接口约定写代码，不得自行发明结构。

## 0. 来源与许可

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/WXRIW/Lyricify-Lyrics-Helper |
| 固定提交 | `53a2f81d3b92b279e1996a27e1de8598cf283a2d`（2026-09-28） |
| 许可证 | **Apache License 2.0** |
| 本地参考副本 | `C:\Users\81157\Documents\deepseek-harness\default-workspace\refs\Lyricify-Lyrics-Helper` |
| 上游规模 | 110 个 `.cs`，16004 行 |

**许可义务（必须遵守）**：
1. 源文件保留 `lib/lyrics/LICENSE`（Apache-2.0 全文，已拷贝）。
2. 每个移植文件顶部写一行出处注释：
   `// Ported from Lyricify.Lyrics.Helper/<相对路径>.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)`
3. 我们对代码做过翻译（C# → Dart）与少量适配，必须在 `lib/lyrics/NOTICE` 里声明"已修改"。
4. 不得删除上游版权头（C# 源文件本身没有逐文件版权头，故以 LICENSE + NOTICE 覆盖）。

## 1. 目标

Glance（本仓库 `Vectra`）现有歌词链路是手写的：只有 LRC、只有网易云/酷狗/LRCLIB、
只有逐行高亮。本次把 Lyricify 的歌词逻辑**全量**移植进来：

- 全部歌词格式解析：LRC / QRC / KRC / YRC / TTML(Apple) / Spotify JSON / Musixmatch JSON /
  Lyricify Syllable / Lyricify Lines
- 全部生成器（反向导出）：同上一套
- 解密器：QQ 音乐的 QRC（DES + XML）、酷狗 KRC（zlib + XML）
- 通用助手：字符串比对、简繁转换、类型识别、偏移、歌词优化（背景和声、显式内容、制作名单、逐字合并、同步降级）
- 全部在线来源：网易云 / QQ 音乐 / 酷狗 / LRCLIB / Musixmatch / SodaMusic(汽水) / Apple Music / Spotify
- 搜索与匹配打分：Searcher 体系 + Artist/Name/Duration 三路匹配 + 艺人名中文化表

最终接线：`lib/lyrics/engine.dart` 暴露一个 `fetchLyrics(...)`，`lib/widgets/builtin/lyrics.dart`
只调用它，替换掉原来的 `_searchLyrics` / `_neteaseAttempt` / `_kugouAttempt` / `_lrclib*`。

## 2. 目录结构（谁写哪个文件）

命名空间 `Lyricify.Lyrics.*` → Dart 目录 `lib/lyrics/**`。**目录名用 snake_case，类名保持 PascalCase。**

```
lib/lyrics/
  LICENSE                     [宿主] Apache-2.0 全文
  NOTICE                      [宿主] 出处 + 已修改声明
  lyrics_log.dart             [宿主] 可替换日志出口
  http/
    lyrics_http.dart          [宿主] HTTP 抽象（唯一网络出口）
  json_utils.dart             [宿主] JSON 取值助手（替代 Newtonsoft 的动态取值）
  models/                     [宿主]
    lyrics_types.dart         LyricsTypes, LyricsRawTypes, SyncTypes
    line_info.dart            LineInfo(抽象), TextLineInfo, SyllableLineInfo,
                              FullLineInfoMixin, FullTextLineInfo, FullSyllableLineInfo, LyricsAlignment
    syllable_info.dart        SyllableInfo(抽象), TextSyllableInfo, FullSyllableInfo, SyllableHelper
    lyrics_data.dart          LyricsData
    file_info.dart            FileInfo
    additional_file_info.dart IAdditionalFileInfo, GeneralAdditionalInfo, KrcAdditionalInfo, SpotifyAdditionalInfo
    track_metadata.dart       TrackMetadata, TrackMultiArtistMetadata, SpotifyTrackMetadata
  helpers/
    general/
      string_helper.dart          [W-C]
      math_helper.dart            [W-C]
      chinese_helper.dart         [W-C]
      chinese_converter_tables.dart [W-C] 上游 CHSWord/CHTWord 原文抄录（4804 对）
    types/
      lyrics_type_detector.dart   [W-C]
      type_helper.dart            [W-C]
    optimization/
      apple_music.dart, explicit.dart, info_lines.dart, musixmatch.dart,
      syllable_word_merger.dart, sync_downgrade.dart, yrc.dart   [W-C]
    parse_helper.dart             [W-C]
    offset_helper.dart            [W-C]
    generator_helper.dart         [W-B]
    search_helper.dart            [W-F]
    provider_helper.dart          [W-F]
  parsers/
    attributes_helper.dart, lrc_parser.dart, krc_parser.dart, qrc_parser.dart,
    yrc_parser.dart, lyricify_syllable_parser.dart, lyricify_lines_parser.dart   [W-A]
    ttml_parser.dart, spotify_parser.dart, musixmatch_parser.dart               [W-B]
    models/{spotify.dart, musixmatch.dart, yrc.dart}                            [W-B]
  generators/
    lrc_generator.dart, krc_generator.dart, qrc_generator.dart,
    yrc_generator.dart, lyricify_syllable_generator.dart,
    lyricify_lines_generator.dart                                               [W-B]
  decrypters/
    krc/{decrypter.dart, helper.dart, model.dart}                               [W-A]
    qrc/{decrypter.dart, des_helper.dart, helper.dart, model.dart, xml_utils.dart} [W-A]
  providers/
    i_provider.dart, i_provider_result.dart, provider.dart,
    kugou_provider_result.dart, netease_provider_result.dart,
    qqmusic_provider_result.dart                                                [W-F]
    web/
      base_api.dart, proxy.dart, providers.dart                                 [宿主]
      netease/{api.dart, eapi_helper.dart, response.dart}                       [W-D]
      qqmusic/{api.dart, response.dart}                                         [W-D]
      kugou/{api.dart, response.dart}                                           [W-D]
      lrclib/{api.dart, response.dart}                                          [W-D]
      musixmatch/{api.dart, api_options.dart, response.dart}                    [W-E]
      spotify/{api.dart, models.dart}                                           [W-E]
      applemusic/{api.dart, response.dart}                                      [W-E]
      sodamusic/{api.dart, response.dart}                                       [W-E]
  searchers/
    searchers.dart, isearcher.dart, isearch_result.dart, searcher.dart,
    searcher_helper.dart, searchers_helper.dart                                 [W-F]
    netease_searcher.dart, netease_search_result.dart,
    qqmusic_searcher.dart, qqmusic_search_result.dart,
    kugou_searcher.dart, kugou_search_result.dart,
    lrclib_searcher.dart, lrclib_search_result.dart,
    musixmatch_searcher.dart, musixmatch_search_result.dart,
    sodamusic_searcher.dart, sodamusic_search_result.dart,
    applemusic_searcher.dart, applemusic_search_result.dart,
    spotify_searcher.dart, spotify_search_result.dart                           [W-F]
    helpers/
      artist_helper.dart, compare_helper.dart                                   [W-F]
      match_helpers/{artist_match.dart, name_match.dart, duration_match.dart}   [W-F]
  engine.dart                 [宿主] 对外门面：fetchLyrics / parseAny / 缓存模型
```

测试：

```
test/fixtures/lyricify/*.txt        [宿主] 从上游 Lyricify.Lyrics.Demo/RawLyrics 拷来的真实样本
test/lyrics/parsers_test.dart       [W-A]
test/lyrics/generators_test.dart    [W-B]
test/lyrics/helpers_test.dart       [W-C]
test/lyrics/providers_test.dart     [W-D/W-E]（离线：解析内置 JSON/XML 样本）
test/lyrics/searchers_test.dart     [W-F]
```

## 3. 契约（宿主已写好，直接用，别改）

### 3.1 models

C# 的接口/默认实现映射到 Dart 的抽象类 + mixin：

| C# | Dart | 说明 |
|---|---|---|
| `ILineInfo` | `LineInfo`（抽象类） | 带 `duration`/`startTimeWithSubLine`/`fullText` 等派生 getter |
| `LineInfo` | `TextLineInfo extends LineInfo` | 可写字段 `text`/`startTime`/`endTime` |
| `SyllableLineInfo` | `SyllableLineInfo extends LineInfo` | 同名字段 `syllables` |
| `IFullLineInfo` | `mixin FullLineInfoMixin on LineInfo` | `translations` / `pronunciation` |
| `FullLineInfo` | `FullTextLineInfo extends TextLineInfo with FullLineInfoMixin` | |
| `FullSyllableLineInfo` | `FullSyllableLineInfo extends SyllableLineInfo with FullLineInfoMixin` | |
| `ISyllableInfo` | `SyllableInfo`（抽象类） | |
| `SyllableInfo` | `TextSyllableInfo extends SyllableInfo` | 叶子音节 |
| `FullSyllableInfo` | `FullSyllableInfo extends SyllableInfo` | `subItems` |
| `LyricsAlignment` | `enum LyricsAlignment { unspecified, left, right }` | |
| `SyncTypes` | `enum SyncTypes { unknown, syllableSynced, lineSynced, mixedSynced, unsynced }` | |
| `LyricsTypes` / `LyricsRawTypes` | 同名 enum（Dart 小驼峰成员） | 全部成员保留 |

**枚举成员命名**：Dart 风格 `unknown` / `lyricifySyllable` / `qrcFull` / `appleJson` …，
不要用 C# 的 `PascalCase`。

### 3.2 HTTP（唯一网络出口）

```dart
abstract class LyricsHttpClient {
  Future<LyricsHttpResponse> send({
    required String method,            // 'GET' | 'POST'
    required Uri url,
    Map<String, String>? headers,
    String? body,                      // POST 体（表单已编码或 JSON 字符串）
    Duration timeout,                  // 默认 15s
  });
}

class LyricsHttpResponse {
  final int statusCode;
  final String body;                   // UTF-8 解码后的文本
  bool get ok => statusCode >= 200 && statusCode < 300;
}
```

- 全局默认实例：`BaseApi.httpClient`（`lib/lyrics/providers/web/base_api.dart`）。
  在 Glance 里由 `engine.dart` 注入走宿主 `ctx` 的实现（带日志/超时/代理）。
- 测试与命令行里用 `DirectLyricsHttpClient`（`package:http`）。
- **禁止**在 `lib/lyrics/**` 里直接用 `package:http`/`dart:io` 发请求——一律走 `LyricsHttpClient`。

### 3.3 JSON

不再有 Newtonsoft。用 `lib/lyrics/json_utils.dart`：

```dart
Map<String, dynamic> asObj(dynamic v);          // 不是 Map 就返回 {}
List<dynamic> asArr(dynamic v);                 // 不是 List 就返回 []
String asStr(dynamic v, [String def = '']);
int asInt(dynamic v, [int def = 0]);
int? asIntOrNull(dynamic v);
double asDouble(dynamic v, [double def = 0]);
bool asBool(dynamic v, [bool def = false]);
dynamic jget(dynamic root, String path);        // 'a.b[2].c' 形式取值
String jencode(Object? o);                      // jsonEncode 包装
T? decodeAs<T>(String body, T Function(Map<String, dynamic>) fromJson);
```

C# 里的 `token["a"]?["b"]` → `jget(token, 'a.b')`，`JsonConvert.DeserializeObject<T>(s)` →
`T.fromJson(asObj(jsonDecode(s)))`。DTO 类统一：`factory X.fromJson(Map<String, dynamic> j)`。

### 3.4 日志

```dart
// lyrics_log.dart
typedef LyricsLogFn = void Function(String message, {bool warn});
void lyricsLog(String message, {bool warn = false});
```
默认实现是空实现（纯库）；Glance 在启动时注入转发到 `core/logger.dart` 的 `Log`。

### 3.5 BaseApi

`lib/lyrics/providers/web/base_api.dart` 提供 C# `BaseApi` 的等价物：

```dart
abstract class BaseApi {
  static LyricsHttpClient httpClient = DirectLyricsHttpClient();
  static const String userAgent = '...';      // 与上游逐字一致
  static const String cookie = '...';         // 与上游逐字一致

  String? get httpUserAgent => userAgent;
  String? get httpCookie => null;
  String? get httpRefer;                      // 抽象
  Map<String, String>? get additionalHeaders; // 抽象

  Future<String> getAsync(String url);
  Future<String> postFormAsync(String url, Map<String, String> paramDict);
  Future<String> postJsonAsync(String url, Object? param);
  Future<String> postRawAsync(String url, String param);
  Future<String> postJsonObjectAsync(String url, Map<String, Object?> paramDict);
}
```
子类（各源 `Api`）只实现 `httpRefer` / `additionalHeaders`，其余照抄 C# 调用点。

### 3.6 W-C 必须提供的静态 API（其他模块依赖它们，名字不许改）

C# 的扩展方法 `str.Foo(x)` 在 Dart 里统一写成静态方法 `StringHelper.foo(str, x)`。

```dart
// helpers/general/math_helper.dart
class MathHelper {
  static int? min(int? val1, int? val2);
  static int? max(int? val1, int? val2);
  static num greaterThanZero(num x);
  static num greaterThan(num x, num minValue);
  static bool isBetween(num x, num a, num b, {bool containEdge = true});
}

// helpers/general/string_helper.dart（全量移植，下面这些名字被别的模块直接调用）
class StringHelper {
  static bool isSame(String? str1, String? str2);
  static bool isSameWhiteSpace(String? str1, String? str2);
  static bool isSameTrim(String? str1, String? str2);
  static double computeTextSame(String? textX, String? textY, [bool isCase = false]);
  static String removeDuoSpaces(String str);
  static String removeTripleSpaces(String str);
  static String fixCommaAfterSpace(String str);
  static String removeDuoBackslashN(String str);
  static String removeBackslashR(String str);
  static String formatTimeMsToTimestampString(num time, [bool millisecond = true]);
  static int? getMillisecondsFromString(String? time);
  static String toUpperFirst(String str, [int start = 0]);
  static String between(String str, String start, String end);
  static String reverse(String str);
  static String remove(String str, String substring);
  static String removeControlChars(String value, [List<String> excludeChars = const []]);
  static String fixIWords(String str);
  static String removeFrontBackBrackets(String str);
  static bool canStartNewLine(String str);
  static bool containsAny(String str, List<String> list);   // PORT NOTE: 上游叫 Contains，与 Dart 内建同名
  static bool isNumber(String str);
  static bool hasCJK(String str, [bool includeColon = false]);
  static bool isCJK(String str, [bool includeColon = false]);
  static String optimizeCJK(String str);
  static bool isChinese(String ch);                          // 上游参数是 char
  static bool hasChinese(String str);
  static double chinesePercentage(String text);
  static double traditionalChineseConfidence(String text);
  static bool isEmoji(String character, [bool full = true]);
  static bool containsEmoji(String str, [bool full = true]);
}
```

`chinese_helper.dart` 提供 `ChineseHelper.s2T` / `t2S` / `toTC` / `toSC` / `isTraditional`（上游成员全保留），
底层是上游自带的 `CHSWord`/`CHTWord` 字表（`chinese_converter_tables.dart`）。

### 3.7 各源 Provider 的类名与导入（避免 Dart 无命名空间导致的撞名）

C# 里 8 个源各自有 `namespace ...Providers.Web.Netease { public class Api }` 之类，
**类名全是 `Api`**。Dart 没有命名空间，所以：

1. 每个 `api.dart` 里仍然写 `class Api extends BaseApi`（与上游逐字对应）。
2. 使用方**必须带前缀导入**，作为"命名空间"：
   ```dart
   import '../providers/web/netease/api.dart' as ne;
   import '../providers/web/qqmusic/api.dart' as qq;
   import '../providers/web/kugou/api.dart' as kg;
   import '../providers/web/lrclib/api.dart' as lrclib;
   import '../providers/web/musixmatch/api.dart' as mx;
   import '../providers/web/spotify/api.dart' as sp;
   import '../providers/web/applemusic/api.dart' as am;
   import '../providers/web/sodamusic/api.dart' as soda;
   ```
   于是 C# 的 `Providers.NeteaseApi.Search(...)` → Dart 的 `Providers.neteaseApi.search(...)`，
   类型写作 `ne.Api`、`qq.Api`。
3. `response.dart` / `models.dart` 里的 DTO **保留上游类名**（`Song`、`Artist`、`Album`…），
   同理只在前缀导入下使用。
4. **嵌套类型**：Dart 不支持嵌套类/枚举，C# 的 `Api.SearchTypeEnum` →
   同文件顶层 `enum SearchTypeEnum`（加 `// PORT NOTE: 上游是 Api 的嵌套枚举`）。
   同理 `RequestCaptchaException`（Musixmatch）放同文件顶层。
5. 上游的重载方法（`Search(string, SearchTypeEnum)` 与 `Search(...)` 等）在 Dart 里
   合并为带可选参数的一个方法，或按语义分名（如 `search` / `searchNew`），
   名字必须在文件里说明，**W-F 按这个名字用**。
6. 方法名统一规则：C# `XxxAsync` → Dart `xxxAsync`；C# 同步 `Xxx` → Dart `xxx`。


## 4. C# → Dart 移植规则

1. **逐行保真**。阈值、正则、常量、顺序、注释里的中文说明全部保留。**不要"顺手优化"**。
   行为差异只在无法直译时出现，且必须在文件里用 `// PORT NOTE:` 说明。
2. `string`/`int?` → `String`/`int?`；`List<T>` → `List<T>`；`Dictionary<K,V>` → `Map<K,V>`。
3. C# 扩展方法 `x.Foo(y)` → Dart 扩展 `extension XExt on X { ... }` 或静态方法
   `StringHelper.foo(x, y)`。**优先静态方法**，扩展只在上游就是扩展方法且调用点很多时用，
   并在 spec 里说明。
4. `async Task<T>` → `Future<T>`；`Task` → `Future<void>`；`await` 语义一致。
5. C# 的 `out` 参数 → Dart 的返回记录（record）或 `(bool ok, T? value)`；
   例如 `TryParseRawType` → `LyricsRawTypes? tryParseRawType(String? name)`。
6. 属性 → getter；只读集合字段保留 `final List<T>`（可变则 `final List<T> x = []`）。
7. `enum` 的数值不再依赖（Dart enum 无隐式 int）；若有序列化需求，显式写 `index`/`name` 映射。
8. 空安全：C# 的可空引用 → Dart `?`。**不要**用 `!` 硬解包不确定的值，按 C# 判空逻辑走。
9. `Regex` → `RegExp`；C# `RegexOptions.Compiled|Multiline` 等 → `multiLine: true` 等。
10. `StringBuilder` → `StringBuffer`；`sb.AppendLine(x)` → `sb.writeln(x)`。
11. C# 字符串插值 `$"{a}{b}"` → Dart `'$a$b'`。
12. `System.Text.Json`/Newtonsoft 的属性名映射：JSON 字段名一律以**上游代码里出现的名字**为准
    （`[JsonProperty("xxx")]` 有就用它）。Dart DTO 用 `fromJson` 手工映射。
13. XML（TTML/QRC-full/KRC）：用 `package:xml`（已在依赖树里，`xml: ^7.0.1`）。
    `XDocument` → `XmlDocument.parse`，`XNamespace` → `XmlNamespace`，需要显式命名空间匹配。
14. 压缩（KRC）：`System.IO.Compression` → `dart:io` 的 `ZLibDecoder` / `RawZLibFilter`。
15. DES/TripleDES（QRC）：**手写移植 `DESHelper.cs`**（230 行），不引第三方加密库，
    保证与上游逐位一致。
16. 文件级：一个 C# 文件 → 一个 Dart 文件（同名 snake_case）。
    一个 C# 文件里有多个类 → 全部放进同一个 Dart 文件（Dart 允许）。
17. 每个 Dart 文件顶部：出处注释 + `library;`（需要时）+ 注释保留中文原文。
18. `lib/lyrics/**` **不得 import Flutter**（`package:flutter/*`）。只用 `dart:core|async|convert|math|io|typed_data`
    和 `package:http`、`package:xml`。这样 `flutter test` 与将来的纯 Dart 复用都不受限。

## 5. 验收（每个 worker 自己先过一遍）

```powershell
$env:Path="$env:Path;C:\src\flutter\bin"
cd C:\Users\81157\Documents\work\Vectra
flutter analyze lib\lyrics\<你负责的子目录>   # 自己负责的目录必须 0 error
flutter test test\lyrics\<你的测试文件>       # 必须全绿
```

**注意**：`lib/lyrics` 是 6 个 worker 并行写的。别人的目录里符号还不存在属于**预期**
（例如 providers 还没写时 searcher 会报未定义），所以 analyze 只跑**自己的子目录**，
不要为了消灭跨目录报错去创建别人负责的文件。宿主负责最后统一 integration。

要求：
- `flutter analyze` 在你负责的目录下 **0 error 0 warning**（info 级 lint 也尽量清掉）。
- 每个 worker 至少给出**基于真实样本**的测试：解析类用 `test/fixtures/lyricify/*.txt`
  （上游 Demo 的真实歌词），断言行数 / 首末时间戳 / 逐字音节数 / 翻译条数等硬指标。
- 测试失败不许靠改测试糊过去；要么修实现，要么在测试里写清"上游行为如此"的依据。

## 6. 已知的环境适配点（必须记录，不许偷偷改行为）

| # | 上游 | 我们 | 原因 |
|---|---|---|---|
| 1 | `Microsoft.International.Converters...ChineseConverter` | 改用**上游同文件** `ChineseConverter` 的 `CHSWord`/`CHTWord` 两张硬编码字表（逐字节抄录，4804 对） | .NET 专有库，Dart 无；用上游自带数据反而更保真 |
| 2 | `HttpClient` 静态实例 + 系统代理 | `LyricsHttpClient` 抽象 + 宿主注入 | 桌面应用要统一日志/超时/代理 |
| 3 | Newtonsoft 动态 JSON | `json_utils.dart` 手写取值 | 依赖体积 |
| 4 | `System.Xml.Linq` | `package:xml` | 同上 |
| 5 | `DeflateStream` | `dart:io` ZLibDecoder | 同上 |
| 6 | `RegexOptions.Compiled` | 无对应（Dart 无此概念） | 语义等价 |

以上 6 条已写进 `lib/lyrics/NOTICE`。

## 7. 全量覆盖核对（怎么证明"抄全了"）

上游 `Lyricify.Lyrics.Helper` 共 **110 个 `.cs`**（不含 `obj/` 生成物）。
用脚本把每个上游路径按"目录/文件名 → snake_case"映射后逐个 `Test-Path`，结论是
**110/110 都有对应 Dart 文件**；脚本报出的 ~32 条"missing"全部是**命名风格差异**，
不是缺文件，逐条对账如下：

| 上游 | 我们的 | 说明 |
|---|---|---|
| `Decrypter/**` | `decrypters/**` | 目录改复数 |
| `Searchers/AppleMusicSearcher.cs` | `searchers/applemusic_searcher.dart` | 不加下划线（`AppleMusic` 视作一个词） |
| `Searchers/QQMusicSearcher.cs` | `searchers/qqmusic_searcher.dart` | 同上 |
| `Providers/QQMusicProviderResult.cs` | `providers/qqmusic_provider_result.dart` | 同上 |
| `Providers/Web/MusixMatch/**` | `providers/web/musixmatch/**` | 上游目录拼写特殊 |
| `Helpers/TypeHelper.cs` | `helpers/types/type_helper.dart` | 与类型识别放一起（唯一一处刻意的目录调整） |
| `Helpers/Types/LyricsTypes.cs` | 并入 `helpers/types/lyrics_type_detector.dart` | 上游那 10 个一行转发方法已合并 |
| `Models/ILineInfo.cs` + `Models/LineInfo.cs` | `models/line_info.dart` | 接口 + 实现同文件 |
| `Models/ISyllableInfo.cs` + `Models/SyllableInfo.cs` | `models/syllable_info.dart` | 同上 |
| `Models/SyncTypes.cs` + `Models/LyricsTypes.cs` | `models/lyrics_types.dart` | 同目录枚举合并 |
| `Models/ITrackMetadata.cs` + `Models/TrackMetadata.cs` | `models/track_metadata.dart` | 同上 |
| `Providers/Web/BaseApi.cs` 的 `JsonUtils` | `json_utils.dart` | 独立成文件 |

### 7.1 验收脚本（不要靠人肉数）

上面这张表是人写的，会烂。真正把关的是 `tool/` 下这几个脚本，它们对着
**本地固定的上游副本**跑，改完代码跑一遍就知道有没有抄漏：

| 脚本 | 回答的问题 | 判定 |
|---|---|---|
| `pwsh -File tool\verify_port.ps1` | 一条龙：完整性 → 契约 → 成员保真 → analyze → 全量测试 | 任一关不过返回非 0 |
| `python tool\check_contracts.py` | 第 0/3.6/4.18 节的硬约定：出处注释、不许 import Flutter、关键方法没被改名、LICENSE/NOTICE 在 | 任一不合规返回非 0 |
| `dotnet run --project tool/upstream_goldengen -- test/fixtures/lyricify _out` | **用真正的上游 C# 重新生成全部黄金样本**，逐字节比对 | 有差异即失败 |
| `python tool\port_audit.py` | 上游 110 个 `.cs` 是否都有对应 Dart 文件；哪个文件**抄薄了**（行数比 < 0.55） | 缺文件即失败 |
| `python tool\member_audit.py` | 有没有**抄漏某个方法/字段**（按成员名比对，行数对比看不出来） | 输出疑似缺失清单 |
| `python tool\gen_artist_pairs.py --apply` | 从上游重新生成 `ArtistHelper` 的 2077 条艺人表 | 人工核对过条数 |
| `python tool\restore_doc_comments.py --apply` | 把上游被剥掉的 `///` 中文注释按成员名写回去（**已跑过**；改动与删行必须合成一趟倒序应用，用行号分别记录会错位） | 对不上名字的一律不动 |
| `dart run tool\lyricify_live_check.dart "歌名" "歌手" 时长秒 来源` | 真实网络下引擎是否真的选出歌词 | 需要联网 |

`port_audit.py` 当前输出：上游 14514 行 → 我们 17632 行，**110/110 有对应实现**。

### 7.2 黄金样本：全部 12 份都由上游 C# 生成

`test/fixtures/lyricify/*.golden.json` 是判定"行为是否与上游一致"的 ground truth。
它们**不是**手写的，也不是 Dart 端自己生成的（自己证明自己等于没证明）——
`tool/upstream_goldengen/` 是一个 .NET 控制台程序，直接 ProjectReference
`refs/Lyricify-Lyrics-Helper` 的上游工程，用**上游的解析器**跑 fixture 再序列化。

```powershell
dotnet run --project tool/upstream_goldengen -- test/fixtures/lyricify _out
# 然后逐字节比对 _out 与 test/fixtures/lyricify —— 当前是 12/12 完全一致
```

| fixture | 上游类型 | 行数 | golden |
|---|---|---|---|
| `LrcDemo` | Lrc | 100 | ✅ |
| `QrcDemo` | Qrc | 39 | ✅ |
| `KrcDemo` | Krc | 98 | ✅ |
| `YrcDemo` | Yrc | 102 | ✅ |
| `LyricifySyllableDemo` | LyricifySyllable | 54 | ✅ |
| `LsMixQrcDemo` | LyricifySyllable | 32 | ✅ |
| `LyricifyLinesDemo` | LyricifyLines | 53 | ✅ |
| `AppleSyllableDemo` | Ttml | 69 | ✅ 本轮补 |
| `SpotifyDemo` | Spotify（行同步） | 25 | ✅ 本轮补 |
| `SpotifySyllableDemo` | Spotify（逐字） | 129 | ✅ 本轮补 |
| `SpotifyUnsyncedDemo` | Spotify（无同步） | 27 | ✅ 本轮补 |
| `MusixmatchDemo` | Musixmatch | 28 | ✅ 本轮补 |

本轮开工时只有前 7 份，**TTML / Spotify / Musixmatch 三个解析器从来没有跟上游输出
比对过**——而它们恰恰是最容易在 agent、背景人声、translations、pronunciation、
`FullSyllableInfo.subItems` 上出错的地方。补齐后这 12 份全部可复现。

注意 `AppleSyllableDemo` 的取法：它是 Apple 的 JSON **信封**
（`{"data":[{"type":"syllable-lyrics","attributes":{"ttml":"<tt .../>"}}]}`），
`ParseHelper.cs:33-45` 里**没有** `AppleJson` 分支（会返回 null），是
`Providers/Web/AppleMusic/Api.cs` 拆出 `data[].attributes.ttml` 之后再交给
`TtmlParser` 的——生成器照抄了这条路径。用 `LyricsRawTypes.Ttml` 直接喂整个信封
会解析出 0 行，那是类型选错，不是 bug。

**已知的误报**（`member_audit.py` 会报但其实是对的，不要去"修"）：
C# 接口 `ILineInfo` 按契约变成 Dart 抽象类 `LineInfo`；C# 嵌套 DTO 提升为顶层并带前缀
（`GetTokenResponse.TaskType` → `GetTokenTaskType`）；`_lock`/`HttpClient`/`CreateRequest`
按 3.2 契约换成 `LyricsHttpClient`；`JsonUtils` 移到 `json_utils.dart`；
`RegexOptions.Compiled` 无对应物（见第 6 节第 6 条）；`CHSWord`/`CHTWord` 移到
`chinese_converter_tables.dart` 并加了 `k` 前缀。

脚本本身已经把三类纯命名差异归一化掉了（比较前统一小写、去掉分隔符、放行单/复数），
所以剩下的报项基本都是**跨文件引用**而非漏抄：
`Searchers/Helpers/MatchHelpers/*.cs` 里的 `CompareHelper`、`GetMatchScore`
住在 `compare_helper.dart`，按文件比对自然看不见；
`switch` 是 C# 关键字（JSON 字段名）。**判定方式是逐个 grep 确认符号真的存在**，
不要看着清单就补代码。当前 26 个文件命中，全属此类。

## 8. 进度

- [x] 定位源码、固定上游提交、许可核查
- [x] 规格 + 契约（models / http / json / base_api / log / LICENSE / NOTICE）
- [x] W-A 解析器 + 解密器（LRC/KRC/QRC/YRC/Lyricify Syllable/Lyricify Lines + KRC/QRC 解密）
- [x] W-B TTML/Spotify/Musixmatch + 全部生成器
- [x] W-C 通用助手（StringHelper / MathHelper / ChineseHelper，含上游 CHSWord/CHTWord 原文 4804 对）
- [x] W-C2 类型识别 + ParseHelper/OffsetHelper + 全部优化助手
- [x] W-D 网易云/QQ/酷狗/LRCLIB（含 eapi AES-128-ECB + MD5，weapi/eapi 均按上游 `FormUrlEncodedContent` 发表单）
- [x] W-E Musixmatch/Spotify/AppleMusic/SodaMusic
- [x] W-F Searcher 体系 + Artist/Name/Duration 匹配 + SearchHelper/ProviderHelper
- [x] W-G ArtistHelper 艺人名表（2077 条，与上游逐条一致）
- [x] 宿主接线（context POST/自定义头、engine、engine_sources 各源 bridge、lyrics_view 渲染模型）
- [x] 歌词卡片接入（engine → lyrics_view → 逐字高亮，含滚轮浏览/点击定位）
- [x] 全量验证（analyze 干净 + 全部测试绿 + 真机真接口）
  - `flutter analyze lib test` → **No issues found**（0 error / 0 warning / 0 info）
  - `flutter test` → **329 全绿**
  - 12 份 golden 由上游 C# 重新生成后 **12/12 逐字节一致**
  - 实网：`lyricify_live_check.dart` 搜索 → 打分 → 取词 → 解析 → 渲染跑通

### 8.1 一次真实的翻车（留档，别再犯）

移植规模这么大，"写完了"不等于"对了"。本轮开工时的实际状态：

1. `lib/lyrics/searchers/helpers/artist_helper.dart` 的 2077 条艺人表是**空列表**——
   编译通过、单测通过，但功能等于没有。**行数对比能看出来**（0.02），成员名对比看不出来。
2. 提交 `61e9c7c` 把 5151 行端口测试（parsers/generators/helpers/providers/searchers/
   artist_helper）**删掉了**。删掉之后 `flutter test` 全绿，于是看起来"没问题"。
   恢复后跑一次：**51 个失败**——其中既有实现偏离上游，也有测试自己写错（对错要逐条
   回到上游 `.cs` 判定，见各 worker 的报告）。
3. `test/lyrics/searchers_test.dart` 写入时编码管道坏了，150 个 U+FFFD 把中文字符串
   截断，**文件根本编译不过**，而且因为它编译不过，同目录其他测试的错误也会被掩盖。
4. 上游的中文 `///` 注释在移植时被整体剥掉，只剩空的 `///`（69 个文件）。
5. **把注释写回去的脚本自己把代码删了。** `restore_doc_comments.py` 先按行号落"插入"、
   再按**落插入之前的行号**落"删空注释行"，两趟的行号已经错位，于是删掉了正确的代码行。
   表面症状是 118 个编译错误；**真正可怕的是其中两处编译得过**：
   - `Explicit._replaceAt` 少了 `replacement +` 一行 → 掩码词被**整个删掉**而不是替换掉；
   - `StringHelper.canStartNewLine` 少了 `return true;` → 恒返回 false。
   靠 `flutter analyze` 抓不到这两个（0 错误时它们照样能编译）。抓它们靠的是
   `git diff HEAD -- <文件> | grep '^-' | grep -v '^-\s*//'`——**逐行扫非注释的删除项**。

   修法：把"插入"和"删除"合并成同一趟 `(行号, 删行?, 替换文本)` 的倒序应用。

   连带教训：脚本改源码时，`ReadAllText` 失败会让 `$t` 变成 `$null`，
   随后的 `WriteAllText($p, $null, $enc)` 会**把文件写成 0 字节**，而
   `flutter analyze` 对空文件报的是 "No issues found"。本轮因此丢了
   `engine.dart` / `engine_sources.dart` / `lrc.dart` 三个文件，靠 `git checkout HEAD --` 找回。

### 8.2 实网跑出来的一个"不是 bug 的 bug"

`dart run tool/lyricify_live_check.dart 青花瓷 周杰伦 240 netease` 实网跑通
（搜索 → 打分 → 取词 → 解析 → 渲染，1.4s），但返回的是 **LRC / lineSynced，0 个音节**——
周杰伦的歌拿不到逐字。看着像 bug，逐行对回上游却是**完全一致**的：

- 上游 `Netease/Api.cs:225-246` `GetLyricNew` 的参数是 `yv:"0"`、`ytv:"0"`、`yrv:"0"`；
- 网易云 `/eapi/song/lyric/v1` 里 `yv` 就是"要不要返回 yrc 逐字"，传 `0` 即**关闭**；
- 上游自己的 doc comment（`Api.cs:219`）还写着「获得新版歌词结果（含逐字）」。

也就是说 Lyricify 自己关掉了逐字，我们照抄了，所以行为一致。上游要 `yv:"1"` 才有逐字。

**处置：保持不变。** 本移植的契约是"行为与上游一致"，不是"比上游好用"；擅自把 `yv`
改成 `1` 就是制造一处没有出处的偏差。真要逐字，走 LRCLIB 那条路（本仓库已经接了）。
记在这里，免得下次看到实网结果缺音节时，又以为是移植漏了东西而"顺手修一下"。

教训：**"编译通过"和"测试全绿"都不能证明移植正确**。判据必须是
"对着上游源码逐条核对"，而第 7.1 节的脚本就是为此存在的。测试失败时**删测试是最坏的选择**
——它把唯一的证伪手段拿掉了。

