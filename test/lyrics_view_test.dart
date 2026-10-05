/// 歌词**渲染模型**的单元测试（`lib/widgets/lyrics_view.dart`）。
///
/// 逐字（卡拉OK）已下线，所以这里不再有 `sungCharsF`/`charsSungAt`。
/// 剩下的职责只有三块：
///   - [LyricsLine.progressAt]：某时刻这行唱到百分之几；
///   - 翻译开关（[LyricsView.hasTranslation]）与来源/格式元数据的传递；
///   - 缓存往返（[LyricsView.encode] / [LyricsView.decode]）和
///     [LyricsView.indexAt] 的当前行定位。
///
/// 顺带钉住一条不能退化的事实：**渲染层拿到的行一定是纯文本行**。数据侧
/// （`lib/lyrics/`）对 KRC/YRC 这类逐字格式仍会解析出音节，但管线末端由
/// `SyncDowngrade` 统一降级（见 `LyricsEngine._optimize`）——万一哪天把
/// 降级漏掉，`fromData` 会把音节行原样放进 `LyricsLine.text`，歌词就变成
/// 音节碎片拼的奇怪字符串。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/models/file_info.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_data.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/widgets/lyrics_view.dart';

/// 一行**纯文本**歌词（带译文），行时间 0~2000。
FullTextLineInfo _zhLine() {
  return FullTextLineInfo()
    ..text = '你好世界'
    ..startTime = 0
    ..endTime = 2000
    ..chineseTranslation = 'hello world';
}

/// 一行**普通** LRC 行，只有行时间没有译文。
FullTextLineInfo _plainLine() {
  return FullTextLineInfo()
    ..text = 'plain line' // 10 个字符
    ..startTime = 2000
    ..endTime = 4000;
}

LyricsView _view({bool wantTranslation = true}) {
  final data = LyricsData()
    ..file = (FileInfo()
      ..type = LyricsTypes.qrc
      ..syncTypes = SyncTypes.lineSynced)
    ..lines = <LineInfo>[_zhLine(), _plainLine()];
  return LyricsView.fromData(data,
      sourceName: '测试源', wantTranslation: wantTranslation);
}

void main() {
  group('progressAt：行内进度', () {
    test('按行时间线性插值，两端各自夹住', () {
      final line = _view().lines.first;
      expect(line.progressAt(-500), 0); // 还没开始
      expect(line.progressAt(0), 0);
      expect(line.progressAt(250), closeTo(0.125, 1e-9));
      expect(line.progressAt(500), closeTo(0.25, 1e-9));
      expect(line.progressAt(1000), closeTo(0.5, 1e-9));
      expect(line.progressAt(2000), 1.0);
      expect(line.progressAt(999999), 1.0); // 行结束后不许继续涨
    });

    test('零长行（end <= start）退化成"到点就满"', () {
      // fromSimpleLines 造出来的行 end 全是 0，就走这一档。
      // 分母不能是 0，所以必须先判再算。
      final v = LyricsView.fromSimpleLines(const [
        (start: 0, text: '第一句', trans: ''),
        (start: 7000, text: '第二句', trans: '译二'),
      ]);
      expect(v.lines.first.progressAt(-1), 0);
      expect(v.lines.first.progressAt(0), 1.0);
      expect(v.lines[1].progressAt(6999), 0);
      expect(v.lines[1].progressAt(7000), 1.0);
    });
  });

  group('翻译开关', () {
    test('wantTranslation=false 丢掉译文，hasTranslation 跟着变', () {
      expect(_view(wantTranslation: true).hasTranslation, isTrue);
      final off = _view(wantTranslation: false);
      expect(off.hasTranslation, isFalse);
      expect(off.lines.first.trans, isEmpty);
    });

    test('fromSimpleLines（调试/预览图路径）也认译文', () {
      final v = LyricsView.fromSimpleLines(const [
        (start: 0, text: '第一句', trans: ''),
        (start: 7000, text: '第二句', trans: '译二'),
      ]);
      expect(v.hasTranslation, isTrue);
      expect(v.lines.first.trans, isEmpty);
      expect(v.lines[1].trans, '译二');
    });
  });

  group('缓存往返', () {
    test('encode/decode 保留行数据与来源元信息', () {
      final v = _view();
      final back = LyricsView.decode(v.encode());
      expect(back, isNotNull);
      expect(back!.sourceName, '测试源');
      expect(back.type, LyricsTypes.qrc);
      expect(back.syncTypes, SyncTypes.lineSynced);
      expect(back.hasTranslation, isTrue);
      expect(back.lines.length, 2);
      expect(back.lines.first.text, '你好世界');
      expect(back.lines.first.trans, 'hello world');
      expect(back.lines.first.start, 0);
      expect(back.lines.first.end, 2000);
      expect(back.indexAt(2500), 1);
    });

    test('写出去的 JSON 里没有音节字段', () {
      // 逐字数据彻底下线，缓存不该再留下 `sy` 的位置——留着就等于
      // 下次读回来时又以为有逐字可用。
      final v = _view();
      final json = v.encode();
      expect(json, isNot(contains('"sy"')));
      // 逐行的键也只剩 t/e/s/tr 这一组。
      expect(json, contains('"t":0'));
      expect(json, contains('"e":2000'));
      expect(json, contains('"s":"你好世界"'));
    });

    test('旧版裸数组缓存也能读（元素是 {t,s,tr}）', () {
      final back = LyricsView.decode(<Object?>[
        <String, Object?>{'t': 0, 's': '旧缓存', 'tr': 'old cache'},
      ]);
      expect(back, isNotNull);
      expect(back!.lines.single.text, '旧缓存');
      expect(back.lines.single.trans, 'old cache');
      expect(back.hasTranslation, isTrue);
      // 裸数组没有信封，格式/来源只能按默认值填。
      expect(back.type, LyricsTypes.lrc);
      expect(back.syncTypes, SyncTypes.lineSynced);
    });

    test('缓存里有遗留的 sy 字段时，无视它而不是崩', () {
      // 老版本写下的缓存里可能有 sy。decode 必须能读这种行——它没读 sy，
      // 未知键直接忽略，所以行为跟普通行一样。
      final back = LyricsView.decode({
        'type': 'qrc',
        'sync': 'lineSynced',
        'v': [
          {
            't': 0,
            'e': 2000,
            's': '你好世界',
            'sy': [
              {'s': '你', 'a': 0, 'b': 500},
            ],
          },
        ],
      });
      expect(back, isNotNull);
      expect(back!.lines.single.text, '你好世界');
      expect(back.lines.single.progressAt(1000), closeTo(0.5, 1e-9));
    });

    test('decode 遇到垃圾输入返回 null 而不是抛', () {
      expect(LyricsView.decode(null), isNull);
      expect(LyricsView.decode(''), isNull);
      expect(LyricsView.decode(42), isNull);
      expect(LyricsView.decode('不是 json'), isNull);
      expect(LyricsView.decode('[1, 2, 3]'), isNull); // 元素不是 Map
    });
  });

  group('fromData：音节行必须已被降级', () {
    test('渲染层只出纯文本行，不留音节概念', () {
      // 数据侧对 KRC/YRC 仍会解析出 SyllableLineInfo（行文本要从音节
      // 累积而来），但 _optimize 末端会 SyncDowngrade 掉。这里直接拿一个
      // 没降级的音节行进 fromData，钉住"渲染层不认音节"这件事本身。
      final data = LyricsData()
        ..file = (FileInfo()
          ..type = LyricsTypes.krc
          ..syncTypes = SyncTypes.syllableSynced)
        ..lines = <LineInfo>[_plainLine()];
      final v = LyricsView.fromData(data);
      expect(v.lines.single.text, 'plain line');
      // 格式元信息照实传（渲染层不解释它，只是缓存往返要靠它）。
      expect(v.type, LyricsTypes.krc);
      expect(v.rawType.name, 'krc');
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
