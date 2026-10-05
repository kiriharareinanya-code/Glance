// 回归测试：中文制作名单（作词/作曲/编曲…）必须被 `InfoLines` 识别并裁掉。
//
// 这是一个真实 bug：用户在设置里已经关掉「显示制作名单」
// （`cards[i].settings.credits = false`），屏幕上却照样显示
// 「作词: 代岳东/周振霆 / 作曲: 唐湘智」。
//
// 根因：`InfoLines.titleLineInfoDict` 是从上游 Lyricify 照搬的，
// 里面**一条中文都没有**（全是 `Mixer`/`Guitar`/`Vocal` 这类英文/拼音）——
// 上游主要面向英文歌词。于是 `isInfoLine('作词: 代岳东/周振霆')` 返回
// false，裁剪逻辑压根没把它认成信息行。
//
// 另外两个坑也是实测踩出来的：
//   - 判定必须**只看冒号前的岗位名**，否则「编曲是一只猫」这类正文会被误删。
//   - 岗位名要规范化（剥空格/方括号），否则 `【作词】`/`作 词:` 漏判。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/helpers/optimization/info_lines.dart';
import 'package:vectra/lyrics/helpers/parse_helper.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';

void main() {
  group('中文制作名单能被识别', () {
    const credits = <String>[
      '作词: 代岳东/周振霆',
      '作曲: 唐湘智',
      '编曲: 郭一凡',
      '制作人: 荒井十一',
      '监制: 张杰',
      '和声: 某某',
      '混音: 李游',
      '录音: 王五',
      '吉他: 徐楠',
      '贝斯: 可可',
      '键盘: 骆亚新',
      '弦乐: 第一爱乐乐团',
      '母带: 某某',
      '特别鸣谢: 所有人',
      '出品: 腾讯音乐',
      '统筹: 某某',
      // 英文/拼音（上游原有能力，不能被改坏）
      'OP: x',
      'SP: x',
      'Producer: x',
      'Mixer: x',
      // 格式变体（实测这些很容易漏）
      '作 词: 代岳东',
      '词：代岳东',
      '曲: 唐湘智',
      '编曲 : 郭一凡',
      '【作词】代岳东',
      '[Mixer] 某某',
      // 中英混排、无冒号（实测漏网的真实格式）
      '编曲 Arranged by Dean Ting',
      '词 张三',
      'Guitar 某某',
    ];

    for (final t in credits) {
      test('「$t」', () => expect(InfoLines.isInfoLine(t, null), isTrue));
    }
  });

  group('正文歌词不能被误判成制作名单', () {
    const lyrics = <String>[
      '他不懂你的心假装冷静',
      '歌词里有话想对你说',       // 含「词」
      '这是一条弯曲的曲线',       // 含「曲」
      '编曲wolves在奔跑',          // 无冒号
      '我和编曲孪生',               // 含「编曲」但开头不是岗位名
      '编曲是一首好歌',             // 同上
      '你唱得真好听',
      '【作词】',                  // 纯标签、后面没人名
      '【歌词里的故事】',          // 正文里的括号
      '我放弃了我的 chords',
      '',
      '   ',
    ];

    for (final t in lyrics) {
      test('「$t」', () => expect(InfoLines.isInfoLine(t, null), isFalse));
    }
  });

  group('端到端：裁剪后只剩正文', () {
    test('网易云风格的 YRC（开头 JSON 制作名单 + 逐字正文）', () {
      // 真实结构：网易云 YRC 开头几行是 JSON 制作名单，之后是逐字行。
      const yrc = '''
{"t":0,"c":[{"tx":"作词: "},{"tx":"代岳东"},{"tx":"/"},{"tx":"周振霆"}]}
{"t":1000,"c":[{"tx":"作曲: "},{"tx":"唐湘智"}]}
{"t":2000,"c":[{"tx":"编曲: "},{"tx":"郭一凡"}]}
{"t":3000,"c":[{"tx":"制作人: "},{"tx":"荒井十一"}]}
[19160,24320](19160,2000,0)他留给(21160,1400,0)你的背影
[25150,28790](25150,1800,0)关于爱情只字不提
[29790,33070](29790,1600,0)害你哭红了眼睛
''';
      final data = ParseHelper.parseLyrics(yrc, LyricsRawTypes.yrc)!;
      final lines = data.lines ?? const <LineInfo>[];
      expect(lines, hasLength(7), reason: '解析应得 7 行（4 名单 + 3 正文）');

      // 复刻 LyricsEngine._optimize 里 stripInfoLines 的裁剪逻辑
      final flags = InfoLines.checkInfoLines(data);
      final kept = <LineInfo>[];
      for (var i = 0; i < lines.length; i++) {
        if (i < flags.length && flags[i]) continue;
        kept.add(lines[i]);
      }

      expect(kept, hasLength(3), reason: '4 行制作名单应被裁掉');
      expect(kept.map((l) => l.text),
          ['他留给你的背影', '关于爱情只字不提', '害你哭红了眼睛']);
      // 时间戳必须保持原值——裁剪只该删行，不该改动剩下行的时间。
      expect(kept.first.startTime, 19160);
      expect(kept.last.startTime, 29790);
    });

    test('纯 LRC 的开头制作名单同样被裁', () {
      const lrc = '''
[00:00.00]作词: 代岳东/周振霆
[00:01.00]作曲: 唐湘智
[00:02.00]编曲: 郭一凡
[00:19.16]他留给你的背影
[00:25.15]关于爱情只字不提
''';
      final data = ParseHelper.parseLyrics(lrc, LyricsRawTypes.lrc)!;
      final lines = data.lines ?? const <LineInfo>[];
      final flags = InfoLines.checkInfoLines(data);
      final kept = <LineInfo>[];
      for (var i = 0; i < lines.length; i++) {
        if (i < flags.length && flags[i]) continue;
        kept.add(lines[i]);
      }
      expect(kept, hasLength(2));
      expect(kept.first.text, '他留给你的背影');
    });
  });

  group('上游英文能力不被改坏', () {
    test('版权声明仍能识别', () {
      // `_isStringCopyrightClaiming` 要 4 个词才命中（未经/许可/授权/不得/
      // 请勿/使用/版权），所以这句话得凑够 4 个。
      expect(
        InfoLines.isInfoLine(
          '未经许可，不得翻唱、复制、发行、使用',
          null,
        ),
        isTrue,
      );
      // 只有 2 个词不够——这是防误伤的下限。
      expect(
        InfoLines.isInfoLine('未经授权，请使用', null),
        isFalse,
      );
    });

    test('歌手说话标签（Artist:）不算制作名单', () {
      // 歌词里 "张杰:" 是歌手在说话，要保留
      expect(InfoLines.isInfoLine('张杰: 我一直在等你', null), isFalse);
    });
  });
}
