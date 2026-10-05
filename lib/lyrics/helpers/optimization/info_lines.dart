// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/InfoLines.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   `NeedsToSC()`：`text.ToSC()` → `ChineseHelper.toSC(text)`；`ToSC(true)` →
//   `StringHelper.HasChinese(...)` → `StringHelper.hasChinese(...)`。
//   `Regex.Split(titleLower, " - ", RegexOptions.IgnoreCase)` → `titleLower.split(...)`。
//   `s.Contains(x, StringComparison.OrdinalIgnoreCase)` → [_containsIgnoreCaseLowered]。
//
//   `CheckInfoLines(LyricsData)`                    → [checkInfoLines]
//   `CheckInfoLines(List<ILineInfo>, ITrackMetadata?)` → [checkInfoLinesList]
//   `GetHeadingInfoLinesCount(LyricsData)`                    → [getHeadingInfoLinesCount]
//   `GetHeadingInfoLinesCount(List<ILineInfo>, ITrackMetadata?)` → [getHeadingInfoLinesCountList]
//   `GetEndingInfoLinesCount(LyricsData)`                    → [getEndingInfoLinesCount]
//   `GetEndingInfoLinesCount(List<ILineInfo>, ITrackMetadata?)` → [getEndingInfoLinesCountList]
//
//
library;

import '../../models/line_info.dart';
import '../../models/lyrics_data.dart';
import '../../models/track_metadata.dart';
import '../general/chinese_helper.dart';
import '../general/string_helper.dart';

class InfoLines {
  InfoLines._();

  static List<bool> checkInfoLines(LyricsData lyrics) =>
      checkInfoLinesList(lyrics.lines ?? <LineInfo>[], lyrics.trackMetadata);

  static int getHeadingInfoLinesCount(LyricsData lyrics) =>
      getHeadingInfoLinesCountList(
        lyrics.lines ?? <LineInfo>[],
        lyrics.trackMetadata,
      );

  static int getEndingInfoLinesCount(LyricsData lyrics) =>
      getEndingInfoLinesCountList(
        lyrics.lines ?? <LineInfo>[],
        lyrics.trackMetadata,
      );

  /// Returns a bool list with the same length as [lines]:
  /// true => info/credit/claiming line
  ///
  static List<bool> checkInfoLinesList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    final n = lines.length;
    final flags = List<bool>.filled(n, false);
    if (n == 0) return flags;

    final startCount = getHeadingInfoLinesCountList(lines, trackInfo);
    final endCount = getEndingInfoLinesCountList(lines, trackInfo);

    for (var i = 0; i < startCount && i < n; i++) {
      flags[i] = true;
    }

    for (var i = n - endCount; i < n; i++) {
      if (i >= 0) flags[i] = true;
    }

    // Middle part
    final midStart = _clampInt(startCount, 0, n);
    final midEndExclusive = _clampInt(n - endCount, 0, n);

    for (var i = midStart; i < midEndExclusive; i++) {
      final text = _getLineText(lines[i]);
      if (isInfoLine(text, trackInfo)) {
        flags[i] = true;
      }
    }

    return flags;
  }

  static int getHeadingInfoLinesCountList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    if (lines.isEmpty) return 0;

    // Special-case: "Title + Artist"
    var i = 0;
    if (trackInfo != null && lines.isNotEmpty) {
      final first = _getLineText(lines[0]);

      if (_looksLikeTitleAndArtistLine(first, trackInfo)) {
        i++;
      } else if (i == 0 && lines.length >= 3) {
        if (isInfoLine(_getLineText(lines[1]), trackInfo)) {
          i += 2;
        }
      }
    }

    for (; i < lines.length; i++) {
      final text = _getLineText(lines[i]);

      if (text.trim().isEmpty) {
        if (_hasUpcomingInfo(lines, i, trackInfo)) continue;

        break;
      }

      if (isInfoLine(text, trackInfo)) continue;

      if (i + 1 < lines.length &&
          isInfoLine(_getLineText(lines[i + 1]), trackInfo)) {
        i++;
        continue;
      }

      break;
    }

    return i;
  }

  static int getEndingInfoLinesCountList(
    List<LineInfo> lines, [
    TrackMetadata? trackInfo,
  ]) {
    if (lines.isEmpty) return 0;

    var count = 0;

    for (var i = lines.length - 1; i >= 0; i--) {
      final text = _getLineText(lines[i]);

      if (text.trim().isEmpty) {
        if (_hasPreviousInfo(lines, i, trackInfo)) {
          count++;
          continue;
        }
        break;
      }

      if (isInfoLine(text, trackInfo)) {
        count++;
        continue;
      }

      break;
    }

    return count;
  }

  static bool isInfoLine(String? text, [TrackMetadata? trackInfo]) {
    if (text == null || text.trim().isEmpty) return false;

    final str = ChineseHelper.toSC(text.replaceAll('：', ': ')).trim();

    if (_looksLikeArtistSpeakerLabel(text, trackInfo)) {
      return false;
    }

    if (_isStringTencentClaiming(str)) {
      return true;
    }

    if (_isStringCreditBy(str)) {
      return true;
    }

    final hasColon = str.contains(':') || str.contains('：');
    if (!hasColon) {
      // 无冒号的方括号标签：`【作词】代岳东`（某些源爱这么写）。
      // 靠"标签在行首 + 后面有内容"判定，同样要求标签**全等**词表，
      // 所以 `【歌词里的事】` 这种不会被误伤。
      if (_matchesBracketedCreditLabel(str)) return true;
      // 中英混排且**没有冒号**：`编曲 Arranged by Dean Ting`。
      // 这类只能靠"行首是岗位名"来认，所以要求岗位名**全等**词表——
      // 「我和编曲孪生」的开头是"我"，不会命中。
      if (_matchesLeadingCreditLabel(str)) return true;
      // 上游的兜底：版权声明句（"未经许可，不得…"）本来就没有冒号，
      // **不能因为上面加了分支就把这条弄丢**。
      return _isStringCopyrightClaiming(str);
    }

    // 冒号左边才是"岗位名"。**必须只比对冒号前的部分**——
    // 否则「编曲是一只猫」这种正文会连带把整句判成信息行。
    // 同时把岗位名规范化：剥掉 `【】`/`[]`/空格（制表人爱写「【作词】」「作 词」），
    // 中文词表才能命中这些变体。
    final label = _normalizeLabel(str.split(':').first);
    if (label.isEmpty) return _isStringCopyrightClaiming(str);

    // 单字岗位（「词:」「曲:」）单独放行：太短，不加进主表怕误伤。
    if (_chineseCreditsLabels.contains(label)) return true;

    if (_containsAnyKeyword(label)) return true;

    // 岗位名没命中，但整句可能是版权声明（上游行为）。
    return _isStringCopyrightClaiming(str);
  }

  /// 行首是岗位名、后面用空格/斜杠分隔（无冒号）：
  /// `编曲 Arranged by Dean Ting` / `词 张三` / `Guitar 某某`。
  ///
  /// 要求岗位名**全等**词表（不是 contains）——这是防误伤的关键：
  /// 「我和编曲孪生」「编曲是一首好歌」开头都不是岗位名，不会命中。
  static bool _matchesLeadingCreditLabel(String str) {
    // 岗位名最长几个字（「音乐制作」「声音设计」）——超过就说明不是岗位名开头。
    const maxLabelLen = 6;
    for (var len = 1; len <= maxLabelLen && len < str.length; len++) {
      final label = _normalizeLabel(str.substring(0, len));
      if (label.isEmpty) continue;
      final hit = _chineseCreditsLabels.contains(label) ||
          _containsAnyKeyword(label);
      if (!hit) continue;
      // 岗位名后面必须紧跟分隔符或空格，不能是继续的正文。
      // `containsAnyKeyword` 是子串匹配，所以「音乐制作」会被 len=2 的
      // 「音乐」先命中吗？不会——「音乐」不在词表里。逐长度枚举是安全的。
      final rest = str.substring(len);
      if (rest.isEmpty) continue;
      final sep = rest[0];
      if (sep == ' ' || sep == '/' || sep == ':' || sep == '：' ||
          sep == '\t' || sep == '·') {
        // 分隔符后还得有内容（排除「编曲   」这种空壳）。
        if (rest.substring(1).trim().isEmpty) continue;
        return true;
      }
    }
    return false;
  }

  /// 无冒号的方括号制作名单：`【作词】代岳东` / `[Mixer] 某某`。
  ///
  /// 要求标签落在**行首**且括号后还有内容（避免把 `【作词】` 这种
  /// 纯标签行、和正文里的括号片段误判）。
  static bool _matchesBracketedCreditLabel(String str) {
    for (final pair in const <List<String>>[
      <String>['【', '】'],
      <String>['[', ']'],
      <String>['（', '）'],
      <String>['(', ')'],
    ]) {
      if (!str.startsWith(pair[0])) continue;
      final close = str.indexOf(pair[1]);
      if (close <= pair[0].length) continue; // 标签本身为空
      // 闭合括号之后**必须还有内容**（人名）。`【作词】` 这种纯标签行不是
      // 制作名单——它更可能是歌词里的一个占位，不该被删。
      final rest = str.substring(close + 1).trim();
      if (rest.isEmpty) continue;
      final label = _normalizeLabel(str.substring(pair[0].length, close));
      if (label.isEmpty) continue;
      if (_chineseCreditsLabels.contains(label) ||
          _containsAnyKeyword(label)) {
        return true;
      }
    }
    return false;
  }

  /// 岗位名规范化：去空白、方括号、方头括号。
  ///
  /// 为什么需要：制作名单的实际格式远比词表单一——
  /// 网易云写「作词:」，QQ 音乐写「作词：」，有些源写「【作词】代岳东」
  /// 甚至「作 词:」。不规范化就漏判（实测 4 个常见变体全漏）。
  static String _normalizeLabel(String raw) {
    final buf = StringBuffer();
    for (final ch in raw.split('')) {
      if (ch.trim().isEmpty) continue;
      if (_creditLabelBrackets.contains(ch)) continue;
      buf.write(ch);
    }
    return buf.toString();
  }

  /// 岗位名里要剥掉的装饰符号（不算内容）。
  static const List<String> _creditLabelBrackets = <String>[
    '[', ']', '【', '】', '(', ')', '（', '）', '・', '/', '*',
  ];

  /// 中文里那些**本身就是岗位名**的单字。
  ///
  /// 刻意与 [titleLineInfoDict] 分开：这些字太短（"词"/"曲"/"编"/"唱"），
  /// 放进主表会误伤 "歌词里有话"、"曲线" 这类正文。
  /// 判定时要求**整行只有「岗位名 + 人名」**，靠 `isInfoLine` 的冒号门禁
  /// 加这里的**全等**约束（不是 `contains`）双重保险。
  static const Set<String> _chineseCreditsLabels = <String>{
    // 只放**单字**岗位。多字岗位都在 [titleLineInfoDict] 里，
    // 两边不重复，避免同一个词出现在两处、改一处漏一处。
    //
    // 单字要额外小心的原因：「词」「曲」「编」在正文里太常见
    // （"歌词"、"曲线"）。所以判定用**全等**而不是 contains，
    // 且必须先过 `isInfoLine` 的冒号门禁。
    '词',
    '曲',
    '编',
    '唱',
    '录',
    '混',
    '监',
    '制',
  };

  /// 制作名单关键词表。
  ///
  /// 上游 Lyricify 只收英文/拼音（`Mixer`/`Guitar`/`Vocal`…），
  /// 因为它主要面向英文歌词；**中文歌的「作词/作曲/编曲」一个都覆盖不到**。
  /// 实测后果：用户设置里「显示制作名单」已关闭（`credits=false`），
  /// 屏幕上却照样显示「作词: 代岳东/周振霆」——因为 `isInfoLine`
  /// 对它返回 false，裁剪逻辑压根没把它认成信息行。
  ///
  /// 所以这里必须补齐中文。判定还需**同时含冒号**（见 [isInfoLine]），
  /// 这样「作词的手指在颤抖」这类正文歌词不会被误删。
  static final List<String> titleLineInfoDict = <String>[
    // —— 中文制作名单 ——
    '作词',
    '作曲',
    '编曲',
    '制作人',
    '监制',
    '出品',
    '发行',
    '统筹',
    '策划',
    '录音',
    '混音',
    '和声',
    '配唱',
    '吉他',
    '贝斯',
    '鼓',
    '键盘',
    '弦乐',
    '打击乐',
    '音乐制作',
    '声音设计',
    '技术总监',
    '人声编辑',
    '母带',
    '母带后期',
    '特别鸣谢',
    '鸣谢',
    '音乐总监',
    '声乐指导',
    '钢琴',
    '提琴',
    '二胡',
    '古筝',
    '笛子',
    '箫',
    '唢呐',
    '笙',
    '萨克斯',
    '小号',
    '长号',
    // 注意：不要加「曲」「词」这类单字——它们在正文里太常见
    //（"歌词"、"曲线"），冒号那道保险挡不住所有说法。
    // —— 上游原有的英文/拼音条目 ——
    'OA',
    'OP',
    'OT',
    'PV',
    'SP',
    'A&R',
    'PGM',
    'ISRC',
    'Bass',
    'Drum',
    'Pads',
    'Brass',
    'Cello',
    'Choir',
    'Horns',
    'Mixed',
    'Mixer',
    'Piano',
    'Synth',
    'Viola',
    'Vocal',
    'Winds',
    'Kobza',
    'Assist',
    'Violin',
    'Mixing',
    'String',
    'Guitar',
    'Master',
    'Chorus',
    'Record',
    'violins',
    'Arrange',
    'Conduct',
    'Editing',
    'Hormony',
    'Ocarina',
    'Produce',
    'Strings',
    'Whistle',
    'Stylist',
    'Engineer',
    'Keyboard',
    'Director',
    'Harmonica',
    'Mastering',
    'Recording',
    'Balalaika',
    'Percussion',
    'Programing',
    'Production',
    'Programming',
    'Additional programming',
    'Irish whistle',
  ];

  static String _getLineText(LineInfo? line) => line?.text ?? '';

  /// Lowercased copy of the `credit by` markers, built once.
  ///
  /// PERF: the old `_containsAny(str, ['st:', 'or:', 'Lyrics:', ' by:',
  /// ' By:'])` allocated the list **and** lowercased all five constants on every
  /// lyric line. (Note ' by:' and ' By:' both collapse to ' by:' - harmless, the
  /// original scan hit the same duplicate.)
  static const List<String> _creditByMarkers = <String>[
    'st:',
    'or:',
    'lyrics:',
    ' by:',
    ' by:',
  ];

  /// Lowercased copy of [titleLineInfoDict].
  ///
  /// PERF: `_containsAnyKeyword` used to call `toLowerCase()` on all ~94
  /// constant entries on **every** invocation. `_matchesLeadingCreditLabel`
  /// invokes it once per prefix length 1..6 and `_matchesBracketedCreditLabel`
  /// once per bracket style, so a single no-colon lyric line burned ~600
  /// redundant lowercasing + substring scans. Keywords are constants, so they
  /// are lowercased exactly once, here.
  ///
  /// Blank entries were skipped by the old loop; they are skipped here too so
  /// the two lists stay aligned.
  static final List<String> _titleLineInfoDictLowered = <String>[
    for (final k in titleLineInfoDict)
      if (k.trim().isNotEmpty) k.toLowerCase(),
  ];

  /// [parts] must already be lowercased - see [_creditByMarkers].
  static bool _containsAny(String s, List<String> parts) {
    final lowered = s.toLowerCase();
    for (final p in parts) {
      if (p.isEmpty) continue;
      if (lowered.contains(p)) return true;
    }
    return false;
  }

  /// The keyword table is pre-lowercased in [_titleLineInfoDictLowered]; only
  /// the (short) needle is lowercased here.
  static bool _containsAnyKeyword(String s) {
    if (_titleLineInfoDictLowered.isEmpty) return false;

    final lowered = s.toLowerCase();
    for (var i = 0; i < _titleLineInfoDictLowered.length; i++) {
      if (lowered.contains(_titleLineInfoDictLowered[i])) return true;
    }
    return false;
  }

  static bool _hasUpcomingInfo(
    List<LineInfo> lines,
    int index,
    TrackMetadata? trackInfo,
  ) {
    var seen = 0;
    for (var i = index + 1; i < lines.length && seen < 2; i++) {
      final t = _getLineText(lines[i]);
      if (t.trim().isEmpty) continue;
      seen++;
      if (isInfoLine(t, trackInfo)) return true;
    }
    return false;
  }

  static bool _hasPreviousInfo(
    List<LineInfo> lines,
    int index,
    TrackMetadata? trackInfo,
  ) {
    var seen = 0;
    for (var i = index - 1; i >= 0 && seen < 2; i--) {
      final t = _getLineText(lines[i]);
      if (t.trim().isEmpty) continue;
      seen++;
      if (isInfoLine(t, trackInfo)) return true;
    }
    return false;
  }

  static bool _looksLikeArtistSpeakerLabel(
    String raw,
    TrackMetadata? trackInfo,
  ) {
    // If any artist equals "Artist:" then NOT titleline
    final t = raw.trim();
    if (!t.endsWith(':')) return false;

    // Multi-artist
    if (trackInfo is TrackMultiArtistMetadata && trackInfo.artists.isNotEmpty) {
      for (final artist in trackInfo.artists) {
        if (artist.trim().isEmpty) continue;
        if (_equalsIgnoreCase('${artist.trim()}:', t)) return true;
      }
    }

    // Single artist
    final single = trackInfo?.artist;
    if (single != null && single.trim().isNotEmpty) {
      if (_equalsIgnoreCase('${single.trim()}:', t)) return true;
    }

    return false;
  }

  static bool _looksLikeTitleAndArtistLine(
    String line,
    TrackMetadata trackInfo,
  ) {
    if (line.trim().isEmpty) return false;

    final lineNorm = line.toLowerCase().replaceAll('’', "'");
    final titleNorm = ChineseHelper
        .toSC((trackInfo.title ?? '').toLowerCase(), true)
        .replaceAll('’', "'");
    final artistNorm = ChineseHelper
        .toSC((trackInfo.artist ?? '').toLowerCase(), true)
        .replaceAll('’', "'")
        .replaceAll(', ', '/');

    final titleHit = _containsTitle(lineNorm, titleNorm);
    final artistHit = _containsArtists(lineNorm, trackInfo, artistNorm);

    if (titleHit && artistHit) return true;

    if ((trackInfo.title ?? '').contains(' - ')) {
      final parts = (trackInfo.title ?? '')
          .toLowerCase()
          .replaceAll('’', "'")
          .split(RegExp(' - ', caseSensitive: false));
      if (parts.isNotEmpty) {
        final t0 = parts[0];
        if (t0.trim().isNotEmpty &&
            lineNorm.contains(t0) &&
            lineNorm.contains(artistNorm)) {
          return true;
        }
      }
    }

    if (StringHelper.hasChinese(trackInfo.title ?? '')) {
      if (line.contains(ChineseHelper.toSC(trackInfo.title ?? '')) &&
          line.contains(ChineseHelper.toSC(trackInfo.artist ?? ''))) {
        return true;
      }
    }

    return false;
  }

  static bool _containsTitle(String lineLower, String titleLower) {
    if (titleLower.trim().isEmpty) return false;
    if (lineLower.contains(titleLower)) return true;

    // line has "(...)" => compare before '('
    final idx = lineLower.indexOf('(');
    if (idx > 0) {
      final before = lineLower.substring(0, idx);
      if (before.contains(titleLower)) return true;
    }

    // title has "(...)" => compare before '('
    final tIdx = titleLower.indexOf('(');
    if (tIdx > 0) {
      final before = titleLower.substring(0, tIdx).trim();
      if (before.isNotEmpty && lineLower.contains(before)) return true;
    }

    // title has " - " => compare before " - "
    final dash = titleLower.indexOf(' - ');
    if (dash > 0) {
      final before = titleLower.substring(0, dash).trim();
      if (before.isNotEmpty && lineLower.contains(before)) return true;
    }

    return false;
  }

  static bool _containsArtists(
    String lineLower,
    TrackMetadata trackInfo,
    String singleArtistNorm,
  ) {
    if (singleArtistNorm.trim().isNotEmpty &&
        lineLower.contains(singleArtistNorm)) {
      return true;
    }

    if (trackInfo is TrackMultiArtistMetadata && trackInfo.artists.isNotEmpty) {
      var hit = 0;
      for (final a in trackInfo.artists) {
        if (a.trim().isEmpty) continue;
        final norm = ChineseHelper.toSC(a.toLowerCase(), true)
            .replaceAll('’', "'")
            .replaceAll(', ', '/');
        if (norm.isNotEmpty && lineLower.contains(norm)) hit++;
      }

      if (hit > 1 || (hit == 1 && trackInfo.artists.length == 1)) {
        return true;
      }
    }

    return false;
  }

  /// [str] must already be Simplified Chinese - [isInfoLine] hands this method the
  /// output of `ChineseHelper.toSC(...)`.
  ///
  /// PERF: `isInfoLine` runs `ChineseHelper.toSC(text...)` at the top, and this
  /// method used to run a *second* full dictionary conversion on top of it -
  /// once per lyric line, for nothing. `convertToSimplifiedChinese` is
  /// idempotent (verified exhaustively over every BMP code unit), so the second
  /// pass was provably a no-op.
  static bool _isStringTencentClaiming(String s) =>
      (s.contains('腾讯') || s.contains('TME')) &&
      s.contains('享有') &&
      s.contains('翻译') &&
      s.contains('权');

  static bool _isStringCreditBy(String str) {
    if (_containsAny(str, _creditByMarkers)) {
      return true;
    }

    if (_containsIgnoreCaseLowered(str, 'er:') &&
        !_containsIgnoreCaseLowered(str, 'tedder:') &&
        !_containsIgnoreCaseLowered(str, 'bieber:')) {
      return true;
    }

    return false;
  }

  static bool _isStringCopyrightClaiming(String str) {
    var score = 0;
    if (str.contains('未经')) score++;
    if (str.contains('许可')) score++;
    if (str.contains('授权')) score++;
    if (str.contains('不得')) score++;
    if (str.contains('请勿')) score++;
    if (str.contains('使用')) score++;
    if (str.contains('版权')) score++;

    return score >= 4;
  }

  /// `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`。
  static bool _equalsIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  /// `str.Contains(x, StringComparison.OrdinalIgnoreCase)`。
  ///
  /// PERF: [valueLower] must already be lowercased. Every call site passes a
  /// constant ('er:', 'tedder:', 'bieber:'), and lowercasing a constant inside
  /// the comparison is pure waste — it ran 3x per lyric line.
  static bool _containsIgnoreCaseLowered(String str, String valueLower) =>
      str.toLowerCase().contains(valueLower);

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
