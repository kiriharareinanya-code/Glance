/// 渲染层的歌词模型（`lib/widgets/lyrics_view.dart`）。
///
/// 把数据层的 `LineInfo` 收敛成渲染层唯一认识的形状：每行一段纯文本 +
/// 行起止时间 + 译文。`lib/widgets/builtin/lyrics.dart` 只画这个，不再碰
/// 数据层的类型。
library;

import 'dart:convert';

import '../lyrics/models/line_info.dart';
import '../lyrics/models/lyrics_data.dart';
import '../lyrics/models/lyrics_types.dart';

/// 渲染层的行模型。
///
/// **逐字（卡拉OK擦除）已下线**：原先这里有 [LyricsSyllable] 音节列表和
/// `sungCharsF`/`charsSungAt` 两个推进函数。它们整个删掉了——数据侧
/// （`lib/lyrics/`）仍会解析 KRC/YRC 的音节时间，但那是为了从逐字格式里
/// 取出正确的行文本和行时间，管线末端由 `SyncDowngrade` 统一降级成纯文本行
/// （见 `LyricsEngine._optimize`），到这里已经没有音节概念了。
class LyricsLine {
  LyricsLine({
    required this.start,
    required this.end,
    required this.text,
    this.trans = '',
    this.roma = '',
    this.subText = '',
    this.alignment = LyricsAlignment.unspecified,
  });

  final int start;

  final int end;

  final String text;

  final String trans;

  final String roma;

  final String subText;

  final LyricsAlignment alignment;

  /// 这一行在 [posMs] 时刻的播放进度（0~1）。
  ///
  /// 只有行级时间，没有音节，所以是**线性**的：行开始为 0，行结束为 1。
  /// 逐字功能下线后 UI 不再消费这个值，保留是因为它是"某时刻这行唱到
  /// 百分之几"这条语义唯一的实现，将来要做行内进度（例如进度条联动）会用到。
  double progressAt(int posMs) {
    if (end <= start) return posMs >= start ? 1 : 0;
    return ((posMs - start) / (end - start)).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
        't': start,
        'e': end,
        's': text,
        if (trans.isNotEmpty) 'tr': trans,
        if (roma.isNotEmpty) 'ro': roma,
        if (subText.isNotEmpty) 'sub': subText,
        if (alignment != LyricsAlignment.unspecified) 'al': alignment.name,
      };

  static LyricsLine fromJson(Map<String, Object?> j) => LyricsLine(
        start: (j['t'] as num?)?.toInt() ?? 0,
        end: (j['e'] as num?)?.toInt() ?? 0,
        text: '${j['s'] ?? ''}',
        trans: '${j['tr'] ?? ''}',
        roma: '${j['ro'] ?? ''}',
        subText: '${j['sub'] ?? ''}',
        alignment: switch ('${j['al'] ?? ''}') {
          'left' => LyricsAlignment.left,
          'right' => LyricsAlignment.right,
          _ => LyricsAlignment.unspecified,
        },
      );
}

class LyricsView {
  LyricsView({
    required this.lines,
    required this.type,
    required this.syncTypes,
    this.sourceName = '',
    this.rawType = LyricsRawTypes.unknown,
  }) : hasTranslation = lines.any((l) => l.trans.isNotEmpty);

  final List<LyricsLine> lines;

  /// 这份歌词里**有没有任何一行带译文**。
  ///
  /// 行数据构造之后不再变（渲染只读它），所以构造时扫一遍存下结果。
  /// 原来是每次读都现扫一遍的 O(n) getter，而它挂在歌词卡的 build 路径上
  /// （见 LyricsWidget 的 `_songHasTrans`）——一行几百的歌词每帧白扫几百次。
  final bool hasTranslation;

  final LyricsTypes type;

  final SyncTypes syncTypes;

  final String sourceName;

  final LyricsRawTypes rawType;

  bool get isEmpty => lines.isEmpty;

  /// [posMs] 时刻正在播的是第几行；还没进第一行返回 -1。
  ///
  /// 走二分是因为渲染每帧都要问一次（要拿当前行算滚动锚点），行数上百时
  /// 线性扫会白烧 CPU。
  int indexAt(int posMs) {
    if (lines.isEmpty) return -1;
    if (posMs < lines.first.start) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= posMs) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  List<Map<String, Object?>> toJson() =>
      [for (final l in lines) l.toJson()];

  String encode() => jsonEncode({
        'type': type.name,
        'sync': syncTypes.name,
        'raw': rawType.name,
        'src': sourceName,
        'v': toJson(),
      });

  static LyricsView? decode(Object? cached) {
    try {
      if (cached is List) {
        return LyricsView(
          lines: [
            for (final e in cached)
              LyricsLine.fromJson((e as Map).cast<String, Object?>()),
          ],
          type: LyricsTypes.lrc,
          syncTypes: SyncTypes.lineSynced,
        );
      }
      if (cached is String && cached.isNotEmpty) {
        final j = jsonDecode(cached);
        if (j is! Map) return null;
        return LyricsView(
          lines: [
            for (final e in (j['v'] as List? ?? const <Object?>[]))
              LyricsLine.fromJson((e as Map).cast<String, Object?>()),
          ],
          type: _typeOf('${j['type'] ?? ''}'),
          syncTypes: _syncOf('${j['sync'] ?? ''}'),
          rawType: _rawOf('${j['raw'] ?? ''}'),
          sourceName: '${j['src'] ?? ''}',
        );
      }
      if (cached is Map) {
        return LyricsView(
          lines: [
            for (final e in (cached['v'] as List? ?? const <Object?>[]))
              LyricsLine.fromJson((e as Map).cast<String, Object?>()),
          ],
          type: _typeOf('${cached['type'] ?? ''}'),
          syncTypes: _syncOf('${cached['sync'] ?? ''}'),
          rawType: _rawOf('${cached['raw'] ?? ''}'),
          sourceName: '${cached['src'] ?? ''}',
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static LyricsTypes _typeOf(String name) => LyricsTypes.values.firstWhere(
        (t) => t.name == name,
        orElse: () => LyricsTypes.unknown,
      );

  static SyncTypes _syncOf(String name) => SyncTypes.values.firstWhere(
        (t) => t.name == name,
        orElse: () => SyncTypes.unknown,
      );

  static LyricsRawTypes _rawOf(String name) => LyricsRawTypes.values.firstWhere(
        (t) => t.name == name,
        orElse: () => LyricsRawTypes.unknown,
      );

  /// 数据层 → 渲染层。译文按 [wantTranslation] 决定要不要带（设置里
  /// 「显示翻译」关掉时传 false，省掉每行拼字符串的开销）。
  ///
  /// 行按起点排序后再交出去：各源解析出来的行顺序不保证单调（QRC/YRC 会
  /// 夹信息行），而 [indexAt] 的二分要求有序。
  static LyricsView fromData(
    LyricsData data, {
    String sourceName = '',
    bool wantTranslation = true,
  }) {
    final out = <LyricsLine>[];
    for (final line in data.lines ?? const <LineInfo>[]) {
      final mixin = line is FullLineInfoMixin ? line : null;

      var trans = '';
      if (wantTranslation && mixin != null) {
        trans = mixin.chineseTranslation ??
            mixin.translations.values.firstWhere(
              (v) => v.isNotEmpty,
              orElse: () => '',
            );
      }

      out.add(LyricsLine(
        start: line.startTime ?? 0,
        end: line.endTime ?? 0,
        text: line.text,
        trans: trans,
        roma: wantTranslation ? (mixin?.pronunciation ?? '') : '',
        subText: line.subLine?.text ?? '',
        alignment: line.lyricsAlignment,
      ));
    }

    out.sort((a, b) => a.start - b.start);

    return LyricsView(
      lines: out,
      type: data.file?.type ?? LyricsTypes.unknown,
      syncTypes: data.file?.syncTypes ?? SyncTypes.unknown,
      sourceName: sourceName,
      rawType: _rawOfFromType(data.file?.type ?? LyricsTypes.unknown),
    );
  }

  /// 直接从「起点 + 文本」三元组建渲染模型，不经过数据层。
  ///
  /// 只给调试/预览图用（[LyricsView] 的 `end` 全是 0，所以
  /// [LyricsLine.progressAt] 走的是"到点就满"那一档）。
  static LyricsView fromSimpleLines(
    List<({int start, String text, String trans})> lines, {
    String sourceName = '',
  }) {
    return LyricsView(
      lines: [
        for (final l in lines)
          LyricsLine(start: l.start, end: 0, text: l.text, trans: l.trans),
      ],
      type: LyricsTypes.lrc,
      syncTypes: SyncTypes.lineSynced,
      sourceName: sourceName,
      rawType: LyricsRawTypes.lrc,
    );
  }

  static LyricsRawTypes _rawOfFromType(LyricsTypes t) => switch (t) {
        LyricsTypes.lyricifyLines => LyricsRawTypes.lyricifyLines,
        LyricsTypes.lrc => LyricsRawTypes.lrc,
        LyricsTypes.qrc => LyricsRawTypes.qrc,
        LyricsTypes.krc => LyricsRawTypes.krc,
        LyricsTypes.yrc => LyricsRawTypes.yrc,
        LyricsTypes.ttml => LyricsRawTypes.ttml,
        LyricsTypes.spotify => LyricsRawTypes.spotify,
        LyricsTypes.musixmatch => LyricsRawTypes.musixmatch,
        LyricsTypes.unknown => LyricsRawTypes.unknown,
      };
}
