// 回归测试：`SyllableLineInfo` 必须**复制**传入的音节 List。
//
// 这是一个已经真实发生过的 bug（用户实拍《他不懂》《阳光下的星星》只有开头
// 两行制作名单、其余全是 `·`），根因是三方叠加：
//
//   1. `SyllableLineInfo` 的构造函数**直接持有**传入 List 的引用；
//   2. YRC 解析器把复用的 `karaokeWordInfos` 直接传进去（不复制）；
//   3. 上游 `YrcParser.cs:196/326` 在建行之后立刻 `karaokeWordInfos.Clear()`。
//
// 三者叠加 → **所有已建好的行共享同一个 List，被连坐清空** →
// `text` 得空串、`startTime` 得 `null`（缓存里存成 `t=0`）。
//
// 之所以只有开头两行制作名单幸存：它们由另一条代码路径构造，
// 不走那个被 `Clear()` 的 List。
//
// 上游 C# 是靠 `LineInfo.cs:54-57` 的 `Syllables = syllables.ToList()` 免疫的，
// Dart 侧必须自己补上这层复制——参见 `line_info.dart` 里的 PORT NOTE。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/helpers/parse_helper.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/syllable_info.dart';

void main() {
  group('SyllableLineInfo 的引用隔离', () {
    test('建行之后源 List 被 Clear，行不受影响', () {
      // 模拟上游 `YrcParser` 的用法：同一个 List 复用给多行，建完就 Clear。
      final buf = <SyllableInfo>[
        TextSyllableInfo('他留给你是背影', 19530, 25440),
        TextSyllableInfo('关于爱情只字不提', 25440, 29790),
      ];
      final line = SyllableLineInfo(buf);

      // 上游 YrcParser.cs:196/326 的 `karaokeWordInfos.Clear()`
      buf.clear();

      // 这三条正是坏缓存里全部丢失的信息。
      expect(line.syllables, hasLength(2), reason: '行不应被源 List 连坐清空');
      expect(line.text, '他留给你是背影关于爱情只字不提');
      expect(line.startTime, 19530);
      expect(line.endTime, 29790);
    });

    test('多行共享同一个源 List 时互不干扰', () {
      final buf = <SyllableInfo>[];
      // a 在 buf 为空时就建好 —— 之后往 buf 里 add 对它**不应有任何影响**，
      // 这正是"建行那一刻的快照"语义（旧版持引用会被后续 add 悄悄改写）。
      final a = SyllableLineInfo(buf);
      buf.add(TextSyllableInfo('第一行', 0, 1000));
      final b = SyllableLineInfo(buf);
      buf.add(TextSyllableInfo('第二行', 1000, 2000));
      buf.clear();

      expect(a.text, isEmpty, reason: 'a 建行时 buf 为空，之后的变更不该回灌');
      expect(a.syllables, isEmpty);
      expect(b.text, '第一行', reason: 'b 建行时 buf 里只有第一行');
      expect(b.syllables, hasLength(1));
    });
  });

  group('YRC 解析端到端不产空行', () {
    test('逐字 YRC 解析后每行都有文本和时间', () {
      const yrc = '''
[0,3000](0,1000,0)作词(1000,1000,0): (2000,1000,0)代岳东
[19530,25440](19530,5910,0)他留给你的背影
[25440,29790](25440,4350,0)关于爱情只字不提
''';
      final data = ParseHelper.parseLyrics(yrc, LyricsRawTypes.yrc);
      final lines = data?.lines ?? const [];
      expect(lines, hasLength(3));
      expect(lines.map((l) => l.text), ['作词: 代岳东', '他留给你的背影', '关于爱情只字不提']);
      expect(lines[1].startTime, 19530);
      expect(lines[2].startTime, 25440);
    });

    test('整份歌词不含空文本行（用户实拍 bug 的直接判据）', () {
      const yrc = '''
[0,3000](0,1000,0)作词(1000,1000,0): (2000,1000,0)代岳东
[19530,25440](19530,5910,0)他留给你的背影
[25440,29790](25440,4350,0)关于爱情只字不提
[29790,33070](29790,3280,0)害你哭红了眼睛
''';
      final lines = ParseHelper.parseLyrics(yrc, LyricsRawTypes.yrc)?.lines ??
          const [];
      // 坏缓存的签名：行数对但大部分文本为空。
      expect(lines.where((l) => l.text.trim().isEmpty), isEmpty,
          reason: '解析结果不该含空文本行');
      expect(lines.every((l) => l.startTime != null), isTrue,
          reason: '每行都该有时间戳（被 Clear 会让 startTime 变 null）');
    });
  });
}
