///
///
library;

import 'dart:convert';

import '../lyrics/models/line_info.dart';
import '../lyrics/models/lyrics_data.dart';
import '../lyrics/models/lyrics_types.dart';

class LyricsSyllable {
  const LyricsSyllable({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;

  final int start;

  final int end;

  int get duration => end - start;

  Map<String, Object?> toJson() => {'s': text, 'a': start, 'b': end};

  static LyricsSyllable fromJson(Map<String, Object?> j) => LyricsSyllable(
        text: '${j['s'] ?? ''}',
        start: (j['a'] as num?)?.toInt() ?? 0,
        end: (j['b'] as num?)?.toInt() ?? 0,
      );
}

class LyricsLine {
  LyricsLine({
    required this.start,
    required this.end,
    required this.text,
    this.trans = '',
    this.roma = '',
    this.subText = '',
    this.alignment = LyricsAlignment.unspecified,
    List<LyricsSyllable>? syllables,
  }) : syllables = syllables ?? const <LyricsSyllable>[];

  final int start;

  final int end;

  final String text;

  final String trans;

  final String roma;

  final String subText;

  final LyricsAlignment alignment;

  final List<LyricsSyllable> syllables;

  bool get isSyllable => syllables.isNotEmpty;

  double progressAt(int posMs) {
    if (syllables.isNotEmpty) {
      final total = end > start ? end - start : 0;
      if (total <= 0) return 0;
      var done = 0;
      for (final s in syllables) {
        if (posMs >= s.end) {
          done += s.end - s.start;
        } else if (posMs > s.start) {
          done += posMs - s.start;
          break;
        } else {
          break;
        }
      }
      return (done / total).clamp(0.0, 1.0);
    }
    if (end <= start) return posMs >= start ? 1 : 0;
    return ((posMs - start) / (end - start)).clamp(0.0, 1.0);
  }

  /// 逐字（卡拉OK）高亮推进到第几个字——**带小数**。
  ///
  /// 返回 0 ~ [text.length] 的浮点：整数部分是完全唱完的字数，小数部分
  /// 是**正在唱的那个字内部**唱到了百分之几。UI 拿它画"已唱变亮"，
  /// 所以边界能落在字的中间，一路平滑推过去。
  ///
  /// 判定基准是音节的 **start**（开始发声）而不是 end：音节的 start~end
  /// 就是这个字实际发声的区间，在区间内按比例推进即可。**这里不做
  /// 取整**——取整会把整个音节压成"最后那一帧才 +1"，字整整晚一个音节
  /// 才亮，行越多偏得越多（这就是之前逐字歌词"慢半拍"的成因）。
  ///
  /// [leadMs] 是**提前量**（毫秒），用来吸收歌词源时间戳与实际人声的
  /// 偏差：各家标的时间点略有出入，而人眼察觉"这个字亮了"的阈值在
  /// 亮度中段，滞后一点点就会被读成"慢了半拍"。默认 0 = 完全相信
  /// 歌词源标的时间。
  double sungCharsF(int posMs, {int leadMs = 0}) {
    final p = posMs - leadMs;
    if (syllables.isEmpty) {
      return text.length * progressAt(p);
    }
    var n = 0.0;
    for (final s in syllables) {
      if (p < s.start) break;
      final span = s.end - s.start;
      final ratio = span <= 0 ? 1.0 : ((p - s.start) / span).clamp(0.0, 1.0);
      n += s.text.length * ratio;
      if (ratio < 1.0) break; // 还在这个字里，后面的字没开始
    }
    return n.clamp(0.0, text.length.toDouble());
  }

  /// 已唱到的**整数字符**数（UI 只切整行颜色时用；要平滑推进用
  /// [sungCharsF]）。等价于 `sungCharsF(pos).floor()`。
  int charsSungAt(int posMs) => sungCharsF(posMs).floor();

  Map<String, Object?> toJson() => {
        't': start,
        'e': end,
        's': text,
        if (trans.isNotEmpty) 'tr': trans,
        if (roma.isNotEmpty) 'ro': roma,
        if (subText.isNotEmpty) 'sub': subText,
        if (alignment != LyricsAlignment.unspecified) 'al': alignment.name,
        if (syllables.isNotEmpty) 'sy': [for (final s in syllables) s.toJson()],
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
        syllables: [
          for (final e in (j['sy'] as List?) ?? const <Object?>[])
            LyricsSyllable.fromJson((e as Map).cast<String, Object?>()),
        ],
      );
}

class LyricsView {
  LyricsView({
    required this.lines,
    required this.type,
    required this.syncTypes,
    this.sourceName = '',
    this.rawType = LyricsRawTypes.unknown,
  });

  final List<LyricsLine> lines;

  final LyricsTypes type;

  final SyncTypes syncTypes;

  final String sourceName;

  final LyricsRawTypes rawType;

  bool get isEmpty => lines.isEmpty;

  bool get hasTranslation => lines.any((l) => l.trans.isNotEmpty);

  bool get hasSyllables => lines.any((l) => l.isSyllable);

  ///
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

  ///
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

      final syllables = <LyricsSyllable>[];
      if (line is SyllableLineInfo) {
        for (final s in line.syllables) {
          if (s.text.isEmpty) continue;
          syllables.add(LyricsSyllable(
              text: s.text, start: s.startTime, end: s.endTime));
        }
      }

      out.add(LyricsLine(
        start: line.startTime ?? 0,
        end: line.endTime ?? 0,
        text: line.text,
        trans: trans,
        roma: wantTranslation ? (mixin?.pronunciation ?? '') : '',
        subText: line.subLine?.text ?? '',
        alignment: line.lyricsAlignment,
        syllables: syllables,
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

  ///
  ///
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
        LyricsTypes.lyricifySyllable => LyricsRawTypes.lyricifySyllable,
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
