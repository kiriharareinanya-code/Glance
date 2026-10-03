// W-C: helpers/general 单测（StringHelper 全量 + ChineseHelper 交叉验证）。
//
// 上游对照：Lyricify.Lyrics.Helper/Helpers/General/StringHelper.cs
// （Apache-2.0, WXRIW/Lyricify-Lyrics-Helper, commit 53a2f81）。
// 每个期望值都写成 "上游行为如此" 的注释；`computeTextSame` 的期望值是按上游
// LCS/DP 算法手算的（`Math.Round(LCS / max(len) * 100, 2)`）。
//
// 注意几处"反直觉但上游如此"的行为，已单独标注：
//   - `IsEmoji('')` → true（emoji 正则有可选分支，能空匹配）；
//   - `OptimizeCJK` 收尾只做一次 `.Replace("  ", " ")`，不循环；
//   - `ContainsEmoji` 不读 `full` 参数；
//   - `GetMillisecondsFromString('1:30')` → 60000（两段式不累加"秒"）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/helpers/general/chinese_helper.dart';
import 'package:vectra/lyrics/helpers/general/string_helper.dart';
import 'package:vectra/lyrics/helpers/optimization/apple_music.dart';
import 'package:vectra/lyrics/helpers/optimization/explicit.dart';
import 'package:vectra/lyrics/helpers/optimization/info_lines.dart';
import 'package:vectra/lyrics/helpers/optimization/musixmatch.dart';
import 'package:vectra/lyrics/helpers/optimization/syllable_word_merger.dart';
import 'package:vectra/lyrics/helpers/optimization/sync_downgrade.dart';
import 'package:vectra/lyrics/helpers/optimization/yrc.dart';
import 'package:vectra/lyrics/helpers/offset_helper.dart';
import 'package:vectra/lyrics/helpers/parse_helper.dart';
import 'package:vectra/lyrics/helpers/types/lyrics_type_detector.dart';
import 'package:vectra/lyrics/helpers/types/type_helper.dart';
import 'package:vectra/lyrics/models/line_info.dart';
import 'package:vectra/lyrics/models/lyrics_types.dart';
import 'package:vectra/lyrics/models/syllable_info.dart';
import 'package:vectra/lyrics/parsers/ttml_parser.dart';

void main() {
  // ───────────────────────── #region Comparison ─────────────────────────

  group('StringHelper.isSame / isSameWhiteSpace / isSameTrim', () {
    test('isSame: null 与空串彼此相等', () {
      expect(StringHelper.isSame(null, null), isTrue);
      expect(StringHelper.isSame('', null), isTrue);
      expect(StringHelper.isSame(null, ''), isTrue);
      expect(StringHelper.isSame('', ''), isTrue);
      expect(StringHelper.isSame('a', 'a'), isTrue);
      expect(StringHelper.isSame('a', 'b'), isFalse);
      expect(StringHelper.isSame('a', null), isFalse);
      expect(StringHelper.isSame(' ', ''), isFalse); // 空格串不是空串
    });

    test('isSameWhiteSpace: 空白串都当空（string.IsNullOrWhiteSpace）', () {
      expect(StringHelper.isSameWhiteSpace(null, '  '), isTrue);
      expect(StringHelper.isSameWhiteSpace('\t', '\n'), isTrue);
      expect(StringHelper.isSameWhiteSpace('a', 'a'), isTrue);
      expect(StringHelper.isSameWhiteSpace('a', ' a '), isFalse);
      expect(StringHelper.isSameWhiteSpace('', 'x'), isFalse);
    });

    test('isSameTrim: 先 Trim 再按 isSame 比', () {
      expect(StringHelper.isSameTrim(' a ', 'a'), isTrue);
      expect(StringHelper.isSameTrim(null, ' '), isTrue);
      expect(StringHelper.isSameTrim(null, null), isTrue);
      expect(StringHelper.isSameTrim('a b', 'a  b'), isFalse);
    });
  });

  group('StringHelper.computeTextSame（LCS 相似度 0-100）', () {
    test('完全相同的真实歌名', () {
      expect(StringHelper.computeTextSame('Hello', 'Hello'), 100);
      expect(StringHelper.computeTextSame('晴天', '晴天'), 100);
      // 大小写不敏感时先 ToLower，两个输入归一成同一串 → 100
      expect(StringHelper.computeTextSame('Taylor Swift', 'taylor swift'), 100);
    });

    test('大小写开关（isCase）', () {
      // 不区分大小写：'hello' vs 'hello'（第 3 个参数位传 isCase）
      expect(StringHelper.computeTextSame('Hello', 'hello', false), 100);
      // 区分大小写：'Hello' vs 'hello' → LCS = 3（l,l,o），3/5 = 60
      expect(StringHelper.computeTextSame('Hello', 'hello', true), 60);
      // 区分大小写：'HELLO' vs 'hello' 无公共字符 → 0
      expect(StringHelper.computeTextSame('HELLO', 'hello', true), 0);
      expect(StringHelper.computeTextSame('HELLO', 'hello'), 100);
      // 不区分大小写：LCS('hello','hallo') = 4（h,l,l,o）→ 4/5 = 80
      expect(StringHelper.computeTextSame('Hello', 'hallo'), 80);
    });

    test('LCS 不是编辑距离', () {
      // 'abcde' vs 'abXde' → LCS = 4（a,b,d,e），4/5 = 80
      expect(StringHelper.computeTextSame('abcde', 'abXde'), 80);
      // 'abc' vs 'ac' → LCS = 2（a,c），2/3 = 66.67
      expect(StringHelper.computeTextSame('abc', 'ac'), 66.67);
      // 'abcdef' vs 'abcf' → LCS = 4，4/6 = 66.67
      expect(StringHelper.computeTextSame('abcdef', 'abcf'), 66.67);
    });

    test('长度差 × 前缀/后缀', () {
      // 'Hello' vs 'Hello World' → LCS = 5，5/11 = 45.4545… → 45.45
      expect(StringHelper.computeTextSame('Hello', 'Hello World'), 45.45);
      // 'Lemon' vs 'Lemon Tree' → 5/10 = 50
      expect(StringHelper.computeTextSame('Lemon', 'Lemon Tree'), 50);
      // 'Lemon' vs 'LemonTree' → 5/9 = 55.56
      expect(StringHelper.computeTextSame('Lemon', 'LemonTree'), 55.56);
    });

    test('跨语言对：中英同曲不同名', () {
      // 中文与拉丁字母无公共字符 → LCS = 0
      expect(StringHelper.computeTextSame('晴天', 'Sunny Day'), 0);
      expect(StringHelper.computeTextSame('周杰伦', 'Jay Chou'), 0);
      // 纯英文 vs 纯日文假名 → 0
      expect(StringHelper.computeTextSame('Hello', 'こんにちは'), 0);
    });

    test('跨语言对：共享拉丁片段的混合标题', () {
      // 'Shape of You (Live)' vs 'Shape of You' → LCS = 12，12/19 = 63.16
      expect(StringHelper.computeTextSame('Shape of You (Live)', 'Shape of You'),
          63.16);
      // 中文标题里的拉丁片段不影响归一化，ToLower 后完全相同
      expect(StringHelper.computeTextSame('Hello 你好', 'hello 你好'), 100);
    });

    test('空串/边界：长度为 0 直接返回 0', () {
      expect(StringHelper.computeTextSame('', 'abc'), 0);
      expect(StringHelper.computeTextSame('abc', ''), 0);
      expect(StringHelper.computeTextSame('', ''), 0);
      // 上游参数非空；Dart 版对 null 也走同一分支（见实现里的 PORT NOTE）
      expect(StringHelper.computeTextSame(null, 'abc'), 0);
    });

    test('归一化步骤：不做 trim / 不折叠空格（与上游一致）', () {
      // 上游只做 ToLower，不 trim：'hello ' vs 'hello' → LCS = 5，5/6 = 83.33
      expect(StringHelper.computeTextSame('hello ', 'hello'), 83.33);
      // 多空格不折叠：'a  b' vs 'a b' → LCS = 3，3/4 = 75
      expect(StringHelper.computeTextSame('a  b', 'a b'), 75);
    });
  });

  // ─────────────────────── #region Spaces / Lines ───────────────────────

  group('StringHelper 空白与换行清洗', () {
    test('removeDuoSpaces：删除两个及以上空格（循环到收敛）', () {
      expect(StringHelper.removeDuoSpaces('a  b'), 'a b');
      expect(StringHelper.removeDuoSpaces('a   b'), 'a b');
      expect(StringHelper.removeDuoSpaces('a    b    c'), 'a b c');
      expect(StringHelper.removeDuoSpaces('a b'), 'a b');
      expect(StringHelper.removeDuoSpaces(''), '');
      expect(StringHelper.removeDuoSpaces('  '), ' ');
    });

    test('removeTripleSpaces：只把三个及以上压到两个', () {
      expect(StringHelper.removeTripleSpaces('a   b'), 'a  b');
      expect(StringHelper.removeTripleSpaces('a    b'), 'a  b');
      expect(StringHelper.removeTripleSpaces('a  b'), 'a  b');
      expect(StringHelper.removeTripleSpaces('a b'), 'a b');
    });

    test('fixCommaAfterSpace：逗号后恰好一个空格', () {
      expect(StringHelper.fixCommaAfterSpace('a,b'), 'a, b');
      expect(StringHelper.fixCommaAfterSpace('a, b'), 'a, b');
      expect(StringHelper.fixCommaAfterSpace('a,  b'), 'a, b');
      expect(StringHelper.fixCommaAfterSpace('a ,b'), 'a , b');
      expect(StringHelper.fixCommaAfterSpace('Hello,World,Foo'),
          'Hello, World, Foo');
    });

    test('removeDuoBackslashN：折叠连续换行', () {
      expect(StringHelper.removeDuoBackslashN('a\n\nb'), 'a\nb');
      expect(StringHelper.removeDuoBackslashN('a\n\n\n\nb'), 'a\nb');
      expect(StringHelper.removeDuoBackslashN('a\nb'), 'a\nb');
      expect(StringHelper.removeDuoBackslashN(''), '');
      // \r\n\r\n 里没有连续的 \n\n，所以原样保留（上游逐字 replace）
      expect(StringHelper.removeDuoBackslashN('a\r\n\r\nb'), 'a\r\n\r\nb');
    });

    test('removeBackslashR：删除所有 \\r', () {
      expect(StringHelper.removeBackslashR('a\r\nb'), 'a\nb');
      expect(StringHelper.removeBackslashR('\r\r'), '');
      expect(StringHelper.removeBackslashR('abc'), 'abc');
      expect(StringHelper.removeBackslashR(''), '');
    });
  });

  // ────────────────────────── #region Date & Time ──────────────────────────

  group('StringHelper.formatTimeMsToTimestampString（真实歌词时间戳）', () {
    test('(1234) 保留毫秒', () {
      expect(StringHelper.formatTimeMsToTimestampString(1234), '00:01.234');
    });

    test('(1234, false) 不保留毫秒', () {
      expect(StringHelper.formatTimeMsToTimestampString(1234, false), '0:01');
    });

    test('(60000) 进位到分钟', () {
      expect(StringHelper.formatTimeMsToTimestampString(60000), '01:00.000');
      expect(StringHelper.formatTimeMsToTimestampString(60000, false), '1:00');
    });

    test('分秒补零与边界', () {
      expect(StringHelper.formatTimeMsToTimestampString(0), '00:00.000');
      expect(StringHelper.formatTimeMsToTimestampString(0, false), '0:00');
      expect(StringHelper.formatTimeMsToTimestampString(999), '00:00.999');
      expect(StringHelper.formatTimeMsToTimestampString(59999, false), '0:59');
      expect(StringHelper.formatTimeMsToTimestampString(59001), '00:59.001');
      // 59 分 59 秒（< 3600000，上游不做"小时"进位）
      expect(StringHelper.formatTimeMsToTimestampString(3599999), '59:59.999');
      expect(StringHelper.formatTimeMsToTimestampString(3599999, false), '59:59');
      // 恰好 1 小时：minute = 60（上游 minute 是分钟总数，不做 小时:分 拆解）
      expect(StringHelper.formatTimeMsToTimestampString(3600000), '60:00.000');
      expect(StringHelper.formatTimeMsToTimestampString(3600000, false), '60:00');
    });

    test('负数与浮点', () {
      expect(StringHelper.formatTimeMsToTimestampString(-1), '0:00');
      expect(StringHelper.formatTimeMsToTimestampString(-12345.6), '0:00');
      // C# `(int)time`：float → int 截断取整
      expect(StringHelper.formatTimeMsToTimestampString(1234.9), '00:01.234');
      expect(StringHelper.formatTimeMsToTimestampString(1000.0), '00:01.000');
    });
  });

  group('StringHelper.getMillisecondsFromString（各种时间写法）', () {
    test('纯毫秒', () {
      expect(StringHelper.getMillisecondsFromString('1234'), 1234);
      expect(StringHelper.getMillisecondsFromString('0'), 0);
    });

    test('毫秒.补位（上游把点号后当"毫秒数"直接相加，不做补零）', () {
      expect(StringHelper.getMillisecondsFromString('1.234'), 1234);
      // '12.34' → 12*1000 + 34 = 12034（上游就是这么算的）
      expect(StringHelper.getMillisecondsFromString('12.34'), 12034);
      expect(StringHelper.getMillisecondsFromString('0.001'), 1);
    });

    test('秒:毫秒', () {
      expect(StringHelper.getMillisecondsFromString('1:234'), 60000);
      expect(StringHelper.getMillisecondsFromString('00:01.234'), 1234);
      expect(StringHelper.getMillisecondsFromString('12:345.006'), 720006);
      // 2 段且第 2 段无点号：上游不累加秒数（只取分钟 × 60000）
      expect(StringHelper.getMillisecondsFromString('1:30'), 60000);
      expect(StringHelper.getMillisecondsFromString('0:00'), 0);
    });

    test('时:分:秒(.毫秒)', () {
      expect(StringHelper.getMillisecondsFromString('1:00:00'), 3600000);
      // 1h + 2min + 3s = 3723000
      expect(StringHelper.getMillisecondsFromString('1:02:03'), 3723000);
      expect(StringHelper.getMillisecondsFromString('1:02:03.004'), 3723004);
      expect(StringHelper.getMillisecondsFromString('01:02:03.004'), 3723004);
      expect(StringHelper.getMillisecondsFromString('0:00:00.000'), 0);
    });

    test('解析失败返回 null（上游 catch { }）', () {
      expect(StringHelper.getMillisecondsFromString('abc'), isNull);
      expect(StringHelper.getMillisecondsFromString('12:ab'), isNull);
      expect(StringHelper.getMillisecondsFromString('1:2:x'), isNull);
      expect(StringHelper.getMillisecondsFromString(''), isNull);
      expect(StringHelper.getMillisecondsFromString(null), isNull);
      // 3 段（超过两段）无法解析
      expect(StringHelper.getMillisecondsFromString('1.2.3'), isNull);
      // 前后空白：C# int.Parse 会 Trim 后成功，这里按"^\\d+$"严格处理（见 PORT NOTE）
      expect(StringHelper.getMillisecondsFromString(' 12'), isNull);
    });
  });

  // ──────────────────────── #region Bracket / Case ────────────────────────

  group('StringHelper.removeFrontBackBrackets', () {
    test('半角/全角括号成对剥离', () {
      expect(StringHelper.removeFrontBackBrackets('(Hello)'), 'Hello');
      expect(StringHelper.removeFrontBackBrackets('（你好）'), '你好');
      expect(StringHelper.removeFrontBackBrackets('  (Live)  '), 'Live');
      // 先剥前括号，再判定末尾：'Live) (Remastered' 末尾是 'd'，不再剥
      expect(StringHelper.removeFrontBackBrackets('(Live) (Remastered)'),
          'Live) (Remastered');
    });

    test('只有一半括号时按上游逻辑剥离', () {
      expect(StringHelper.removeFrontBackBrackets('(Hello'), 'Hello');
      expect(StringHelper.removeFrontBackBrackets('Hello)'), 'Hello');
    });

    test('无括号 / 空串原样（trim 后）', () {
      expect(StringHelper.removeFrontBackBrackets('Hello World'), 'Hello World');
      expect(StringHelper.removeFrontBackBrackets(''), '');
      expect(StringHelper.removeFrontBackBrackets('   '), '');
      expect(StringHelper.removeFrontBackBrackets('()'), '');
    });
  });

  group('StringHelper.toUpperFirst', () {
    test('默认首字符大写', () {
      expect(StringHelper.toUpperFirst('hello'), 'Hello');
      expect(StringHelper.toUpperFirst('Hello'), 'Hello');
      expect(StringHelper.toUpperFirst(''), '');
      expect(StringHelper.toUpperFirst('1abc'), '1abc');
      expect(StringHelper.toUpperFirst('中文abc'), '中文abc');
    });

    test('start 指定第几个字符大写', () {
      expect(StringHelper.toUpperFirst('hello world', 6), 'hello World');
      expect(StringHelper.toUpperFirst('abc', 0), 'Abc');
      // start >= Length：上游 `return string.Copy(str)`（原样）
      expect(StringHelper.toUpperFirst('abc', 3), 'abc');
      expect(StringHelper.toUpperFirst('abc', 99), 'abc');
      expect(StringHelper.toUpperFirst('', 5), '');
    });
  });

  group('StringHelper.between / reverse / remove', () {
    test('between：取中间子串', () {
      expect(StringHelper.between('[00:01.23]Hello', '[', ']'), '00:01.23');
      expect(StringHelper.between('<a>b</a>', '<a>', '</a>'), 'b');
      // 找不到 end：上游返回 start 之后的全部
      expect(StringHelper.between('abc[def', '[', ']'), 'def');
      // 首次出现的 start
      expect(StringHelper.between('a[x]b[y]', '[', ']'), 'x');
    });

    test('between：找不 start 时上游返回 null（本移植按契约抛 StateError）', () {
      expect(() => StringHelper.between('abc', '[', ']'), throwsStateError);
    });

    test('reverse：按 UTF-16 代码单元反序', () {
      expect(StringHelper.reverse('abc'), 'cba');
      expect(StringHelper.reverse('ab'), 'ba');
      expect(StringHelper.reverse(''), '');
      expect(StringHelper.reverse('晴天'), '天晴');
      // 非 BMP（emoji）会被拆成两个"半个"代理对并互换位置（上游 char[] 行为）
      expect(StringHelper.reverse('a😀'), '\uDE00\uD800a');
    });

    test('remove：移除全部出现', () {
      expect(StringHelper.remove('a-b-c', '-'), 'abc');
      expect(StringHelper.remove('abc', 'x'), 'abc');
      expect(StringHelper.remove('abc', ''), 'abc'); // C# Replace(s, "") 原样
      expect(StringHelper.remove('', 'x'), '');
    });
  });

  group('StringHelper.removeControlChars', () {
    test('移除 C0 / DEL 控制字符', () {
      expect(StringHelper.removeControlChars('a\u0001b'), 'ab');
      expect(StringHelper.removeControlChars('a\u007Fb'), 'ab');
      expect(StringHelper.removeControlChars('a\u0000b\u001Fc'), 'abc');
      // \n \t \r 保留（见实现里的 PORT NOTE）
      expect(StringHelper.removeControlChars('a\nb\tc\rd'), 'a\nb\tc\rd');
      // C1 区间（U+0080–U+009F）
      expect(StringHelper.removeControlChars('a\u0085b'), 'ab');
    });

    test('excludeChars 保留指定控制字符', () {
      expect(StringHelper.removeControlChars('a\u0001b\u0002c', ['\u0002']),
          'ab\u0002c');
      expect(StringHelper.removeControlChars('a\u0001b', ['\u0001']), 'a\u0001b');
    });

    test('普通文本/空串不变', () {
      expect(StringHelper.removeControlChars('Hello, 世界！'), 'Hello, 世界！');
      expect(StringHelper.removeControlChars(''), '');
    });
  });

  group('StringHelper.fixIWords', () {
    test('修复 I 相关缩写（顺序敏感，与上游一致）', () {
      expect(StringHelper.fixIWords(' i love you '), ' I love you ');
      expect(StringHelper.fixIWords("i'd go"), "I'd go");
      expect(StringHelper.fixIWords("i'm here"), "I'm here");
      expect(StringHelper.fixIWords("i'll be"), "I'll be");
      expect(StringHelper.fixIWords("i've done"), "I've done");
      // 大写 I 本来就是目标形态
      expect(StringHelper.fixIWords('I am'), 'I am');
      // 句首无前导空格的 " i " 不会被替换（上游只 replaceAll ' i '）
      expect(StringHelper.fixIWords('i am'), 'i am');
    });
  });

  // ─────────────────────────── #region Determine ───────────────────────────

  group('StringHelper.canStartNewLine / containsAny / isNumber', () {
    test('canStartNewLine：结尾是空格/逗号/斜杠', () {
      expect(StringHelper.canStartNewLine('hello '), isTrue);
      expect(StringHelper.canStartNewLine('hello,'), isTrue);
      expect(StringHelper.canStartNewLine('hello/'), isTrue);
      expect(StringHelper.canStartNewLine('hello'), isFalse);
      expect(StringHelper.canStartNewLine('hello.'), isFalse);
      expect(StringHelper.canStartNewLine(''), isFalse);
    });

    test('containsAny（上游 Contains(this string, List<string>)）', () {
      expect(StringHelper.containsAny('hello world', ['world', 'x']), isTrue);
      expect(StringHelper.containsAny('hello world', ['x', 'y']), isFalse);
      expect(StringHelper.containsAny('hello', []), isFalse);
      expect(StringHelper.containsAny('hello', ['']), isTrue); // 空串是任何串的子串
    });

    test(r'isNumber：仅纯数字（^\d+$）', () {
      expect(StringHelper.isNumber('123'), isTrue);
      expect(StringHelper.isNumber('0'), isTrue);
      expect(StringHelper.isNumber(''), isFalse);
      expect(StringHelper.isNumber('0123'), isTrue);
      expect(StringHelper.isNumber('12a'), isFalse);
      expect(StringHelper.isNumber('1.5'), isFalse);
      expect(StringHelper.isNumber('-1'), isFalse);
      expect(StringHelper.isNumber(' 1'), isFalse);
      expect(StringHelper.isNumber('１２３'), isFalse); // 全角数字不是 \d
    });
  });

  // ───────────────────────────── #region CJK ─────────────────────────────

  group('StringHelper CJK', () {
    test('hasCJK：含 CJK 即真（先剥标点）', () {
      expect(StringHelper.hasCJK('中文'), isTrue);
      expect(StringHelper.hasCJK('abc中文'), isTrue);
      expect(StringHelper.hasCJK('hello world'), isFalse);
      expect(StringHelper.hasCJK('，。！？'), isFalse); // 剥掉标点后为空
      expect(StringHelper.hasCJK('：'), isFalse); // 全角冒号不算 CJK
      expect(StringHelper.hasCJK('：', true), isTrue); // includeColon
      expect(StringHelper.hasCJK('한국어'), isTrue); // 韩文（\uAC00-\uD7FF）
      expect(StringHelper.hasCJK('あいう'), isTrue); // 平假名（\u0800-\u4E00）
      expect(StringHelper.hasCJK(''), isFalse);
    });

    test('isCJK：含 CJKUnifiedIdeographs 即真（不要求全串）', () {
      expect(StringHelper.isCJK('中文'), isTrue);
      expect(StringHelper.isCJK('abc中文def'), isTrue);
      expect(StringHelper.isCJK('hello'), isFalse);
      expect(StringHelper.isCJK(''), isFalse);
      expect(StringHelper.isCJK('：'), isFalse);
      expect(StringHelper.isCJK('：', true), isTrue);
      expect(StringHelper.isCJK('あいう'), isFalse); // 假名不在区块里
    });

    test('optimizeCJK：中西文之间加空格', () {
      expect(StringHelper.optimizeCJK('你好world'), '你好 world');
      expect(StringHelper.optimizeCJK('world你好'), 'world 你好');
      expect(StringHelper.optimizeCJK('abc中文def'), 'abc 中文 def');
      expect(StringHelper.optimizeCJK('中文'), '中文');
      expect(StringHelper.optimizeCJK('hello world'), 'hello world');
      expect(StringHelper.optimizeCJK(''), '');
      // 半角逗号在 symbolRegex 里 → 标点旁不加空格
      expect(StringHelper.optimizeCJK('你好, world'), '你好, world');
      // 全角逗号不在 symbolRegex 里 → 会加空格
      expect(StringHelper.optimizeCJK('你好，world'), '你好 ，world');
      // 上游收尾只做一次 .Replace("  ", " ")：3 个空格会剩 2 个
      expect(StringHelper.optimizeCJK('你 好world'), '你  好 world');
    });
  });

  // ─────────────────────────── #region Chinese ───────────────────────────

  group('StringHelper 中文判定（真实简/繁歌词行）', () {
    test('isChinese：单个汉字 U+4E00-U+9FFF', () {
      expect(StringHelper.isChinese('中'), isTrue);
      expect(StringHelper.isChinese('晴'), isTrue);
      expect(StringHelper.isChinese('a'), isFalse);
      expect(StringHelper.isChinese('，'), isFalse);
      expect(StringHelper.isChinese('あ'), isFalse);
      expect(StringHelper.isChinese('㐀'), isFalse); // U+3400 扩展 A：上游不含
      expect(StringHelper.isChinese(''), isFalse);
      expect(StringHelper.isChinese('中文'), isTrue); // 只看第 1 个代码单元
    });

    test('hasChinese：整串含汉字', () {
      expect(StringHelper.hasChinese('晴天'), isTrue);
      expect(StringHelper.hasChinese('Hello 世界'), isTrue);
      expect(StringHelper.hasChinese('Hello World'), isFalse);
      expect(StringHelper.hasChinese('あいう'), isFalse);
      expect(StringHelper.hasChinese(''), isFalse);
    });

    test('chinesePercentage：汉字占比（分母扣掉 \\n \\r \\t）', () {
      expect(StringHelper.chinesePercentage('晴天'), 1.0);
      expect(StringHelper.chinesePercentage('ab'), 0.0);
      expect(StringHelper.chinesePercentage('中a'), 0.5);
      // 2 个汉字 + 1 个 \n + 4 个 ASCII：2 / (7-1) = 1/3
      expect(StringHelper.chinesePercentage('晴天\nabcd'), closeTo(2 / 6, 1e-12));
      // 全是空白控制字符 → 分母 0 → 返回 0
      expect(StringHelper.chinesePercentage('\n\r\t'), 0);
      expect(StringHelper.chinesePercentage(''), 0);
    });

    test('traditionalChineseConfidence：真实繁体整句（逐字比对转简结果）', () {
      // 「後來我們什麼都有了，卻沒有了我們」
      const line = '後來我們什麼都有了，卻沒有了我們';
      final sc = ChineseHelper.toSC(line);
      var total = 0;
      var changed = 0;
      for (var i = 0; i < line.length; i++) {
        if (StringHelper.isChinese(line[i])) {
          total++;
          if (line[i] != sc[i]) changed++;
        }
      }
      expect(total, greaterThan(0));
      expect(changed, greaterThan(0));
      expect(StringHelper.traditionalChineseConfidence(line),
          closeTo(changed / total, 1e-9));
    });

    test('traditionalChineseConfidence：纯简体真实歌词行 = 0', () {
      const line = '后来我们什么都有了，却没有了我们';
      expect(ChineseHelper.toSC(line), line);
      expect(StringHelper.traditionalChineseConfidence(line), 0);
    });

    test('traditionalChineseConfidence：繁体台湾用字与简体对照', () {
      const tw = '我們都一樣';
      expect(ChineseHelper.toSC(tw), '我们都一样');
      // 5 个汉字里 2 个（們、樣）转简后有变化
      expect(StringHelper.traditionalChineseConfidence(tw),
          closeTo(2 / 5, 1e-9));
      // 无汉字时 total = 0 → 0/0 在 C# 里是 NaN；Dart 同样 NaN（记录上游行为）
      expect(StringHelper.traditionalChineseConfidence('abc').isNaN, isTrue);
    });

    test('ChineseHelper 交叉验证（本文件只 import，不改）', () {
      expect(ChineseHelper.s2T('后来我们都一样'), '後來我們都一樣');
      expect(ChineseHelper.t2S('後來我們都一樣'), '后来我们都一样');
      expect(ChineseHelper.isTraditional('後來我們都一樣'), isTrue);
      expect(ChineseHelper.isTraditional('后来我们都一样'), isFalse);
    });
  });

  // ──────────────────────────── #region Emoji ────────────────────────────

  group('StringHelper.containsEmoji / isEmoji（上游内嵌 emoji 表）', () {
    test('containsEmoji：真实含 emoji 的歌词/标题', () {
      expect(StringHelper.containsEmoji('Hello 😀'), isTrue);
      expect(StringHelper.containsEmoji('🎵 music'), isTrue);
      expect(StringHelper.containsEmoji('☀️ 晴天'), isTrue);
      expect(StringHelper.containsEmoji('❤️'), isTrue);
      expect(StringHelper.containsEmoji('1️⃣'), isTrue);
      expect(StringHelper.containsEmoji('👨‍👩‍👧'), isTrue);
      expect(StringHelper.containsEmoji('Hello, world!'), isFalse);
      expect(StringHelper.containsEmoji('晴天'), isFalse);
      expect(StringHelper.containsEmoji(''), isFalse);
      expect(StringHelper.containsEmoji('abc 123 !@#'), isFalse);
    });

    test('containsEmoji：full 参数被上游忽略（始终走完整表）', () {
      // 上游 `ContainsEmoji(this string str, bool full = true)` 内部不读 full
      expect(StringHelper.containsEmoji('😀', false), isTrue);
      expect(StringHelper.containsEmoji('Hello', false), isFalse);
    });

    test('isEmoji(full=true)：单字符走完整 emoji 表', () {
      expect(StringHelper.isEmoji('😀'), isTrue);
      expect(StringHelper.isEmoji('🎵'), isTrue);
      expect(StringHelper.isEmoji('🚀'), isTrue); // U+1F680 在上游表里
      expect(StringHelper.isEmoji('©'), isTrue);
      expect(StringHelper.isEmoji('⭕'), isTrue);
      expect(StringHelper.isEmoji('中'), isFalse);
      expect(StringHelper.isEmoji('a'), isFalse);
      expect(StringHelper.isEmoji('▲'), isFalse); // U+25B2 不在表里
      // 上游 emoji 正则有可选分支（如 `😀️?`），能空匹配 → IsEmoji("") 为 true
      expect(StringHelper.isEmoji(''), isTrue);
    });

    test('isEmoji(full=false)：上游的快速区间分支', () {
      // 快速分支的区间
      expect(StringHelper.isEmoji('☀', false), isTrue); // U+2600 区间
      expect(StringHelper.isEmoji('⭕', false), isTrue); // U+2B55
      expect(StringHelper.isEmoji('★', false), isFalse); // U+2605 不在区间
      // PORT NOTE: 上游 char 是 16 位，0x1F600 等条件恒假；Dart 用 codeUnitAt(0) 复刻
      expect(StringHelper.isEmoji('😀', false), isFalse);
      expect(StringHelper.isEmoji('🚀', false), isFalse);
    });

    test('emojiPattern 常量与上游第 530 行一致', () {
      expect(StringHelper.emojiPattern.length, 17469);
      expect(StringHelper.emojiPattern.startsWith('('), isTrue);
      expect(StringHelper.emojiPattern.endsWith(')'), isTrue);
      // 表里含肤色修饰符与 ZWJ 序列的字面量
      expect(StringHelper.emojiPattern.contains('‍'), isTrue);
    });
  });

  // ══════════════════════ W-C PROBE (temporary) ══════════════════════

  test('probe', () {
    const names = [
      'LrcDemo.txt',
      'QrcDemo.txt',
      'LsMixQrcDemo.txt',
      'KrcDemo.txt',
      'YrcDemo.txt',
      'AppleSyllableDemo.txt',
      'SpotifyDemo.txt',
      'SpotifySyllableDemo.txt',
      'SpotifyUnsyncedDemo.txt',
      'MusixmatchDemo.txt',
      'LyricifySyllableDemo.txt',
      'LyricifyLinesDemo.txt',
    ];
    for (final n in names) {
      final raw = _fx(n);
      final t = LyricsTypeDetector.detect(raw);
      final data = ParseHelper.parseLyrics(raw, t);
      // ignore: avoid_print
      print('DETECT $n -> $t | lyType=${TypeHelper.getLyricsType(t)} '
          '| lines=${data?.lines?.length} | fileType=${data?.file?.type} '
          '| sync=${data?.file?.syncTypes} '
          '| syl=${data?.lines?.whereType<SyllableLineInfo>().length}');
    }

    final lrc = ParseHelper.parseLyrics(_fx('LrcDemo.txt'))!;
    // ignore: avoid_print
    print('LRC first8 = ${lrc.lines!.take(8).map((e) => e.text).toList()}');
    // ignore: avoid_print
    print('LRC heading=${InfoLines.getHeadingInfoLinesCount(lrc)} '
        'ending=${InfoLines.getEndingInfoLinesCount(lrc)}');
    // ignore: avoid_print
    print('LRC flags = ${InfoLines.checkInfoLines(lrc).take(14).toList()}');

    final qrc = ParseHelper.parseLyrics(_fx('QrcDemo.txt'))!;
    // ignore: avoid_print
    print('QRC first4 = ${qrc.lines!.take(4).map((e) => e.text).toList()}');
    // ignore: avoid_print
    print('QRC heading=${InfoLines.getHeadingInfoLinesCount(qrc)} '
        'ending=${InfoLines.getEndingInfoLinesCount(qrc)}');
    // ignore: avoid_print
    print('QRC flags = ${InfoLines.checkInfoLines(qrc).take(6).toList()}');

    final ll = ParseHelper.parseLyrics(_fx('LyricifyLinesDemo.txt'))!;
    // ignore: avoid_print
    print('LL first6 = ${ll.lines!.take(6).map((e) => e.text).toList()}');
    // ignore: avoid_print
    print('LL heading=${InfoLines.getHeadingInfoLinesCount(ll)} '
        'ending=${InfoLines.getEndingInfoLinesCount(ll)}');

    // ignore: avoid_print
    print('EXP1 = ${Explicit.clean('This is some fuck shit ass bitch damn hoe')}');
    // ignore: avoid_print
    print('EXP2 = ${Explicit.clean('This is some fuck shit ass bitch damn hoe', true)}');
    // ignore: avoid_print
    print('EXP3 = ${Explicit.clean('Asshole classic ass pass')}');
    // ignore: avoid_print
    print('EXP4 = ${Explicit.fixExplicit('f**k s**t b***h a*s')}');
    // ignore: avoid_print
    print('EXP5 = ${Explicit.fixExplicit('F**k S**t B***h A*s')}');
    // ignore: avoid_print
    print('EXP6 = ${Explicit.clean('bitch')} strong=${Explicit.clean('bitch', true)}');

    final appleJson = (_jsonObj(_fx('AppleSyllableDemo.txt')));
    final ttml = ((appleJson['data'] as List).first
        as Map)['attributes']['ttml'] as String;
    // ignore: avoid_print
    print('TTML detect=${LyricsTypeDetector.detect(ttml)}');
    final ttmlData = TtmlParser.parse(ttml);
    // ignore: avoid_print
    print('TTML lines=${ttmlData.lines!.length} '
        'syl=${ttmlData.lines!.whereType<SyllableLineInfo>().length}');
    final firstSyl = ttmlData.lines!.whereType<SyllableLineInfo>().first;
    // ignore: avoid_print
    print('TTML first text=[${firstSyl.text}] n=${firstSyl.syllables.length}');
    // ignore: avoid_print
    print('TTML before=${firstSyl.syllables.map((e) => '[${e.text}]').toList()}');
    final copy = List<LineInfo>.from(ttmlData.lines!);
    AppleMusic.prepareLyricsList(copy);
    final firstAfter = copy.whereType<SyllableLineInfo>().first;
    // ignore: avoid_print
    print('TTML after=${firstAfter.syllables.map((e) => e is FullSyllableInfo ? 'FULL(${e.subItems.map((x) => x.text).join("|")})' : '[${e.text}]').toList()}');
    // ignore: avoid_print
    print('TTML after text=[${firstAfter.text}]');

    final caps = <LineInfo>[
      TextLineInfo('HELLO WORLD. HOW ARE YOU'),
      TextLineInfo('I AM FINE'),
    ];
    AppleMusic.capitalizationNormalization(caps);
    // ignore: avoid_print
    print('CAPS = ${caps.map((e) => e.text).toList()}');
    final caps2 = <LineInfo>[
      TextLineInfo('hello world. i am fine'),
      TextLineInfo('you are ok'),
    ];
    AppleMusic.capitalizationNormalization(caps2);
    // ignore: avoid_print
    print('CAPS2 = ${caps2.map((e) => e.text).toList()}');
    final caps3 = <LineInfo>[
      TextLineInfo('Mixed Case Here'),
      TextLineInfo('Another Line'),
    ];
    AppleMusic.capitalizationNormalization(caps3);
    // ignore: avoid_print
    print('CAPS3 = ${caps3.map((e) => e.text).toList()}');

    final syl = SyllableLineInfo([
      TextSyllableInfo('Hel', 100, 200),
      TextSyllableInfo('lo', 200, 300),
    ]);
    final down = SyncDowngrade.downgradeToLineSynced(syl);
    // ignore: avoid_print
    print('DOWN = ${down.runtimeType} [${down.text}] ${down.startTime}-${down.endTime}');

    final yrc = ParseHelper.parseLyrics(_fx('YrcDemo.txt'))!;
    final yrcSyl = yrc.lines!.whereType<SyllableLineInfo>().toList();
    // ignore: avoid_print
    print('YRC lines=${yrc.lines!.length} sylLines=${yrcSyl.length} '
        'sylCounts=${yrcSyl.take(6).map((e) => e.syllables.length).toList()} '
        'anyNonEmpty=${yrcSyl.any((l) => l.syllables.isNotEmpty)}');
    // ignore: avoid_print
    print('YRC texts=${yrcSyl.take(3).map((e) => "[${e.text}]").toList()}');
    final y0 = yrcSyl.first;
    try {
      Yrc.standardizeYrcLyricsList(yrc.lines!);
      // ignore: avoid_print
      print('YRC standardize OK');
    } catch (e) {
      // ignore: avoid_print
      print('YRC standardize threw: $e');
    }
    // ignore: avoid_print
    print('YRC y0 after=${y0.syllables.length}');

    // MM
    final mm = ParseHelper.parseLyrics(_fx('MusixmatchDemo.txt'))!;
    final mmSyl = mm.lines!.whereType<SyllableLineInfo>().toList();
    // ignore: avoid_print
    print('MM lines=${mm.lines!.length} sylLines=${mmSyl.length} '
        'types=${mm.lines!.map((e) => e.runtimeType).toSet()} '
        'counts=${mmSyl.take(6).map((e) => e.syllables.length).toList()}');
    final withSyl = mmSyl.where((e) => e.syllables.isNotEmpty).toList();
    // ignore: avoid_print
    print('MM withSyl=${withSyl.length}');
    final spot = ParseHelper.parseLyrics(_fx('SpotifySyllableDemo.txt'))!;
    final spotSyl = spot.lines!.whereType<SyllableLineInfo>().toList();
    // ignore: avoid_print
    print('SPOT sylLines=${spotSyl.length} '
        'counts=${spotSyl.take(4).map((e) => e.syllables.length).toList()} '
        'firstText=${spotSyl.first.text}');
    // ignore: avoid_print
    print('SPOT fullSync=${spot.lines!.first.runtimeType}');
    // ignore: avoid_print
    print('SPOT types=${spot.lines!.map((e) => e.runtimeType).toSet()}');

    // OffsetHelper
    final textLine = TextLineInfo('a', 1000, 2000);
    OffsetHelper.addOffset([textLine], 250);
    // ignore: avoid_print
    print('OFFSET text = ${textLine.startTime}-${textLine.endTime}');
    final sylLine = SyllableLineInfo([
      TextSyllableInfo('x', 1000, 1200),
      FullSyllableInfo([
        TextSyllableInfo('y', 1200, 1300),
        TextSyllableInfo('z', 1300, 1400),
      ]),
    ]);
    OffsetHelper.addOffset([sylLine], 100);
    // ignore: avoid_print
    print('OFFSET syl = ${sylLine.syllables.map((e) => "${e.startTime}-${e.endTime}").toList()} '
        'line=${sylLine.startTime}-${sylLine.endTime}');
    final nullLine = TextLineInfo('n');
    OffsetHelper.addOffset([nullLine], 50);
    // ignore: avoid_print
    print('OFFSET null = ${nullLine.startTime}-${nullLine.endTime}');
    final fullLine = FullTextLineInfo()
      ..text = 'f'
      ..startTime = 10
      ..endTime = 20;
    OffsetHelper.addOffset([fullLine], 5);
    // ignore: avoid_print
    print('OFFSET full = ${fullLine.startTime}-${fullLine.endTime}');

    // SyllableWordMerger
    final swmLine = SyllableLineInfo([
      TextSyllableInfo('Hel', 0, 100),
      TextSyllableInfo('lo ', 100, 200),
      TextSyllableInfo('Wo', 200, 300),
      TextSyllableInfo('rld', 300, 400),
      TextSyllableInfo('中', 400, 500),
      TextSyllableInfo('文', 500, 600),
      TextSyllableInfo('!', 600, 700),
    ]);
    SyllableWordMerger.merge(swmLine);
    // ignore: avoid_print
    print('SWM = ${swmLine.syllables.map((e) => e is FullSyllableInfo ? 'FULL(${e.subItems.map((x) => x.text).join("|")})' : '[${e.text}]').toList()}');
    // ignore: avoid_print
    print('SWM text=[${swmLine.text}]');
    // ignore: avoid_print
    print('SWM cjk=${SyllableWordMerger.isChineseOrJapaneseCharacter('中')} '
        'ws=${SyllableWordMerger.isWhiteSpace(' ')} '
        'ld=${SyllableWordMerger.isLetterOrDigit('a')} '
        'ldCjk=${SyllableWordMerger.isLetterOrDigit('中')}');

    // AppleMusic prepareLyrics：拆分 + 词合并 + 冗余翻译
    final splitLine = SyllableLineInfo([TextSyllableInfo('你好world', 0, 1000)]);
    AppleMusic.prepareLyrics(splitLine);
    // ignore: avoid_print
    print('AM split cn=[${splitLine.syllables.map((e) => '${e.text}(${e.startTime}-${e.endTime})').toList()}]');
    final splitLine2 = SyllableLineInfo([TextSyllableInfo('Hello World', 0, 1000)]);
    AppleMusic.prepareLyrics(splitLine2);
    // ignore: avoid_print
    print('AM split en=[${splitLine2.syllables.map((e) => '${e.text}(${e.startTime}-${e.endTime})').toList()}]');
    final splitLine3 = SyllableLineInfo([TextSyllableInfo('  Ooh-ooh  ', 0, 900)]);
    AppleMusic.prepareLyrics(splitLine3);
    // ignore: avoid_print
    print('AM split hy=[${splitLine3.syllables.map((e) => '${e.text}').toList()}]');

    final redMain = FullTextLineInfo()
      ..text = 'Hello'
      ..startTime = 0
      ..endTime = 100;
    redMain.translations['zh'] = 'Hello';
    redMain.translations['en'] = 'Different';
    final redSub = FullTextLineInfo()
      ..text = '(Hello)'
      ..startTime = 0
      ..endTime = 100;
    redSub.translations['zh'] = 'Hello';
    redMain.subLine = redSub;
    AppleMusic.prepareLyrics(redMain);
    // ignore: avoid_print
    print('AM red main=${redMain.translations} sub=${redSub.translations}');

    // 背景和声 + 拼音（FullSyllableLineInfo）
    final fsyl = FullSyllableLineInfo()
      ..syllables = [TextSyllableInfo('Yeah', 0, 100)];
    fsyl.translations['zh'] = 'Yeah';
    fsyl.pronunciation = 'ye';
    AppleMusic.prepareLyrics(fsyl);
    // ignore: avoid_print
    print('AM fsyl trans=${fsyl.translations} pron=${fsyl.pronunciation} '
        'syl=${fsyl.syllables.length}');

    // InfoLines 细节
    // ignore: avoid_print
    print('IL infoLine tests: '
        '${InfoLines.isInfoLine('作词 : Ryan Tedder')} '
        '${InfoLines.isInfoLine('Lyrics by：Ryan')} '
        '${InfoLines.isInfoLine('未经许可 不得 请勿 使用 版权 授权')} '
        '${InfoLines.isInfoLine('Lately, I\'ve been losing sleep')} '
        '${InfoLines.isInfoLine('腾讯音乐享有本翻译作品的著作权')}');
  });
}

String _fx(String name) => File('test/fixtures/lyricify/$name').readAsStringSync();

Map<String, dynamic> _jsonObj(String s) =>
    (jsonDecode(s) as Map).cast<String, dynamic>();
