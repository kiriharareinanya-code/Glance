/// 歌词**渲染模型**的单元测试（`lib/widgets/lyrics_view.dart`）。
///
/// 重点是逐字（卡拉OK）高亮真正依赖的两个量：
///   - `LyricsLine.sungCharsF(pos)`：这一行**已唱到第几个字（带小数）**，
///     UI 用它画连续推进的擦除遮罩；
///   - `LyricsLine.progressAt(pos)`：整行线性进度，也是没有逐字数据时的兜底。
///
/// 以及那条不能退化的链条：**没有逐字数据时 `sungCharsF` 必须等于
/// 整行进度 × 字数**——歌词卡里的普通 LRC 行正是靠它保持"整行高亮"
/// 的旧行为。
///
/// **为什么必须是浮点**：旧实现对每个音节取整，于是单字音节在整个发音
/// 区间里都算 0 字已唱，要到唱完那一帧才 +1，每个字整整晚一个音节
/// 才亮，累积起来就是用户说的"逐字歌词慢半拍"。这里的断言把"字在
/// 音节中点就该亮一半"钉住，防止有人改回取整。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/models/file_info.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/syllable_info.dart';
import 'package:vectra/widgets/lyrics_view.dart';

/// 一行逐字歌词（4 个单字音节，每个 500ms，共 2000ms）。
FullSyllableLineInfo _zhLine() {
  final line = FullSyllableLineInfo()
    ..syllables = <SyllableInfo>[
      TextSyllableInfo('你', 0, 500),
      TextSyllableInfo('好', 500, 1000),
      TextSyllableInfo('世', 1000, 1500),
      TextSyllableInfo('界', 1500, 2000),
    ];
  line.refreshProperties();
  line.chineseTranslation = 'hello world';
  return line;
}

/// 一行**普通** LRC（没有逐字数据，只有整行时间）。
FullTextLineInfo _plainLine() {
  final line = FullTextLineInfo()
    ..text = 'plain line' // 10 个字符
    ..startTime = 2000
    ..endTime = 4000;
  return line;
}

LyricsView _view({bool wantTranslation = true}) {
  final data = LyricsData()
    ..file = (FileInfo()
      ..type = LyricsTypes.qrc
      ..syncTypes = SyncTypes.syllableSynced)
    ..lines = <LineInfo>[_zhLine(), _plainLine()];
  return LyricsView.fromData(data,
      sourceName: '测试源', wantTranslation: wantTranslation);
}

void main() {
  group('sungCharsF：逐字行按音节起点连续推进（带小数）', () {
    test('单字音节：字在**开始发声**那一刻就点亮，并在音节内平滑推进', () {
      final line = _view().lines.first;
      expect(line.text, '你好世界');
      expect(line.isSyllable, isTrue);

      expect(line.sungCharsF(-100), 0); // 还没开始
      expect(line.sungCharsF(0), 0); // 第一个字刚开口
      // 关键回归：旧实现用 floor()，整个 500ms 都返回 0，要到唱完那一帧
      // 才跳到 1 —— 每个字整整晚一个音节，就是"慢半拍"的成因。
      expect(line.sungCharsF(250), closeTo(0.5, 1e-9)); // 第一个字唱到一半
      expect(line.sungCharsF(499), closeTo(499 / 500, 1e-9));
      expect(line.sungCharsF(500), closeTo(1.0, 1e-9)); // 第一个字唱完
      expect(line.sungCharsF(750), closeTo(1.5, 1e-9)); // 第二个字唱到一半
      expect(line.sungCharsF(1000), closeTo(2.0, 1e-9));
      expect(line.sungCharsF(1999), closeTo(3 + 499 / 500, 1e-9));
      expect(line.sungCharsF(2000), 4.0); // 整行唱完
      expect(line.sungCharsF(999999), 4.0);
    });

    test('推进是单调的：位置往前走，已唱字符数绝不回退', () {
      // 动画逐帧取这个值画擦除边界，回退会表现为"高亮往回跳"。
      final line = _view().lines.first;
      var prev = -1.0;
      for (var pos = -200; pos <= 2400; pos += 7) {
        final n = line.sungCharsF(pos);
        expect(n, greaterThanOrEqualTo(prev), reason: 'pos=$pos 时回退了');
        expect(n, inInclusiveRange(0, 4));
        prev = n;
      }
    });

    test('多字音节（词）：按音节内部比例折算，字内也连续', () {
      final line = FullSyllableLineInfo()
        ..syllables = <SyllableInfo>[
          TextSyllableInfo('Hello', 0, 1000),
          TextSyllableInfo(' world', 1000, 2000),
        ];
      line.refreshProperties();
      final data = LyricsData()..lines = <LineInfo>[line];
      final l = LyricsView.fromData(data).lines.first;

      expect(l.text, 'Hello world');
      expect(l.sungCharsF(500), closeTo(2.5, 1e-9)); // 5 个字符唱了一半
      expect(l.sungCharsF(1000), closeTo(5.0, 1e-9)); // 第一个词唱完
      expect(l.sungCharsF(1500), closeTo(8.0, 1e-9)); // 5 + 6×0.5
      expect(l.sungCharsF(2000), 11.0);
    });

    test('leadMs 提前量：把高亮整体前移，吸收歌词源与人声的时间偏差', () {
      final line = _view().lines.first;
      // 提前 250ms：250ms 这一帧画出来的，是"没提前时 0ms"的状态。
      // 第一个字在 0ms 刚开口，所以提前后这里仍是 0。
      expect(line.sungCharsF(250, leadMs: 250), line.sungCharsF(0));
      expect(line.sungCharsF(750, leadMs: 250), line.sungCharsF(500));
      // 提前量确实把进度整体前移：`leadMs` 内部算的是 `posMs - leadMs`，
      // 也就是"这一帧画的是没提前时更早那一刻的状态"。所以同一时刻下
      // 提前后的值**更小**（这里 1.0 < 1.5），而不是更大。
      // 等价的说法是：没提前时要到 750ms 才出现的进度，提前后 500ms 就出现了。
      expect(line.sungCharsF(750, leadMs: 250),
          lessThan(line.sungCharsF(750, leadMs: 0)));
      expect(line.sungCharsF(750, leadMs: 250),
          line.sungCharsF(500, leadMs: 0));
      // 提前量不能把两端撑破。
      expect(line.sungCharsF(0, leadMs: 9999), 0);
      expect(line.sungCharsF(999999, leadMs: 9999), 4.0);
      // 默认 0 = 完全相信歌词源标的时间。
      expect(line.sungCharsF(250), line.sungCharsF(250, leadMs: 0));
    });
  });

  group('charsSungAt：整数版与 sungCharsF 一致', () {
    test('charsSungAt == sungCharsF.floor()', () {
      final line = _view().lines.first;
      for (var pos = -100; pos <= 2200; pos += 13) {
        expect(line.charsSungAt(pos), line.sungCharsF(pos).floor(),
            reason: 'pos=$pos 的整数版必须等于浮点版取整');
      }
    });

    test('多字音节（词）：按音节内部比例折算已唱的字数', () {
      final line = FullSyllableLineInfo()
        ..syllables = <SyllableInfo>[
          TextSyllableInfo('Hello', 0, 1000),
          TextSyllableInfo(' world', 1000, 2000),
        ];
      line.refreshProperties();
      final data = LyricsData()..lines = <LineInfo>[line];
      final l = LyricsView.fromData(data).lines.first;

      expect(l.charsSungAt(500), 2); // 5 个字符唱了一半
      expect(l.charsSungAt(1000), 5); // 第一个词唱完
      expect(l.charsSungAt(1500), 8); // 5 + 6×0.5
      expect(l.charsSungAt(2000), 11);
    });
  });

  group('progressAt：整行进度的兜底', () {
    test('逐字行的进度等于"已唱音节时长 / 整行时长"', () {
      final line = _view().lines.first;
      expect(line.progressAt(0), 0);
      expect(line.progressAt(250), closeTo(0.125, 1e-9));
      expect(line.progressAt(500), closeTo(0.25, 1e-9));
      expect(line.progressAt(1000), closeTo(0.5, 1e-9));
      expect(line.progressAt(2000), 1.0);
      expect(line.progressAt(999999), 1.0);
      expect(line.progressAt(-500), 0);
    });

    test('普通行按时间线性，超出两端各自夹住', () {
      final line = _view().lines[1];
      expect(line.isSyllable, isFalse);
      expect(line.progressAt(1500), 0);
      expect(line.progressAt(2000), 0);
      expect(line.progressAt(3000), closeTo(0.5, 1e-9));
      expect(line.progressAt(4000), 1.0);
      expect(line.progressAt(9000), 1.0);
    });
  });

  group('没有逐字数据时退化（旧行为不能变）', () {
    test('sungCharsF == 字数 × 整行进度（连续，不再取整）', () {
      final line = _view().lines[1];
      for (final pos in [1500, 2000, 2500, 3000, 3500, 4000, 5000]) {
        final p = line.progressAt(pos);
        expect(line.sungCharsF(pos), closeTo(line.text.length * p, 1e-9),
            reason: 'pos=$pos 的退化折算必须与整行进度一致');
      }
      // 具体取值：10 个字符的整行
      expect(line.sungCharsF(2000), 0);
      expect(line.sungCharsF(3000), closeTo(5.0, 1e-9));
      expect(line.sungCharsF(4000), closeTo(10.0, 1e-9));
    });

    test('charsSungAt == floor(字数 × 整行进度)', () {
      final line = _view().lines[1];
      for (final pos in [1500, 2000, 2500, 3000, 3500, 4000, 5000]) {
        final p = line.progressAt(pos);
        expect(line.charsSungAt(pos), (line.text.length * p).floor(),
            reason: 'pos=$pos 的退化折算必须与整行进度一致');
      }
      // 具体取值：10 个字符的整行
      expect(line.charsSungAt(2000), 0);
      expect(line.charsSungAt(3000), 5);
      expect(line.charsSungAt(4000), 10);
    });

    test('fromSimpleLines（调试/预览图路径）没有逐字数据，整行一到位就全亮', () {
      final v = LyricsView.fromSimpleLines(const [
        (start: 0, text: '第一句', trans: ''),
        (start: 7000, text: '第二句', trans: '译二'),
      ]);
      expect(v.hasSyllables, isFalse);
      expect(v.hasTranslation, isTrue);
      expect(v.lines.first.charsSungAt(0), 3); // 整行高亮 = 全部字符
      expect(v.lines[1].charsSungAt(6999), 0);
      expect(v.lines[1].charsSungAt(7000), 3);
      expect(v.lines[1].trans, '译二');
    });
  });

  group('翻译开关与缓存往返', () {
    test('wantTranslation=false 丢掉译文，hasTranslation 跟着变', () {
      expect(_view(wantTranslation: true).hasTranslation, isTrue);
      final off = _view(wantTranslation: false);
      expect(off.hasTranslation, isFalse);
      expect(off.lines.first.trans, isEmpty);
    });

    test('encode/decode 往返保留逐字音节与来源', () {
      final v = _view();
      final back = LyricsView.decode(v.encode());
      expect(back, isNotNull);
      expect(back!.sourceName, '测试源');
      expect(back.type, LyricsTypes.qrc);
      expect(back.syncTypes, SyncTypes.syllableSynced);
      expect(back.hasSyllables, isTrue);
      expect(back.hasTranslation, isTrue);
      expect(back.lines.length, 2);
      expect(back.lines.first.text, '你好世界');
      expect(back.lines.first.syllables.length, 4);
      expect(back.lines.first.syllables[1].text, '好');
      expect(back.lines.first.charsSungAt(1000), 2);
      expect(back.indexAt(2500), 1);
    });

    test('旧版裸数组缓存也能读（元素是 {t,s,tr}）', () {
      final back = LyricsView.decode(<Object?>[
        <String, Object?>{'t': 0, 's': '旧缓存', 'tr': 'old cache'},
      ]);
      expect(back, isNotNull);
      expect(back!.lines.single.text, '旧缓存');
      expect(back.hasSyllables, isFalse); // 旧缓存没有逐字 → 走整行高亮
      expect(back.hasTranslation, isTrue);
    });
  });

  group('indexAt：当前行定位', () {
    test('前奏返回 -1，之后二分命中', () {
      final v = _view();
      expect(v.indexAt(-1), -1);
      expect(v.indexAt(0), 0);
      expect(v.indexAt(1999), 0);
      expect(v.indexAt(2000), 1);
      expect(v.indexAt(999999), 1);
    });

    test('空渲染模型返回 -1', () {
      expect(LyricsView.fromSimpleLines(const []).indexAt(1234), -1);
    });
  });
}
