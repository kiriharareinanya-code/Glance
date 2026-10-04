// W-C: helpers/general 单测（StringHelper 全量 + ChineseHelper 交叉验证）。
//
// 上游对照：Lyricify.Lyrics.Helper/Helpers/General/StringHelper.cs
// （Apache-2.0, WXRIW/Lyricify-Lyrics-Helper, commit 53a2f81）。
// 每个期望值都写成 "上游行为如此" 的注释；`computeTextSame` 的期望值是按上游
// LCS/DP 算法手算的（`Math.Round(LCS / max(len) * 100, 2)`）——注意 .NET 的
// `Math.Round` 默认是 **ToEven（银行家舍入）**，不是 half-up，实现里已按 ToEven 写。
//
// 注意几处"反直觉但上游如此"的行为，已单独标注：
//   - `IsEmoji('')` → false（上游收 char，空串不可表示；最近的 '\0' 也匹配不上表）；
//   - `OptimizeCJK` 收尾只做一次 `.Replace("  ", " ")`，不循环；
//   - `ContainsEmoji` 不读 `full` 参数；
//   - `GetMillisecondsFromString('1:30')` → 60000（两段式无点号时不累加"秒"）；
//   - `GetMillisecondsFromString('1:02:03')` → 3720000（三段式无点号时"秒"被丢弃）。
import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/helpers/general/chinese_helper.dart';
import 'package:vectra/lyrics/helpers/general/string_helper.dart';

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
      // 区分大小写：'Hello' vs 'hello' → 公共子序列 "ello"（e,l,l,o），LCS = 4，4/5 = 80
      // 上游 StringHelper.cs:60-73 是标准 LCS DP（字符相同则 dp[x+1,y+1] = dp[x,y] + 1），
      // 第 74 行 `Math.Round(dp[lenX, lenY] / Math.Max(lenX, lenY) * 100, 2)`。
      // 'e' 在两串里相同，所以 LCS 是 4 而不是 3。
      expect(StringHelper.computeTextSame('Hello', 'hello', true), 80);
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
      // '12:345.006' → 12*60000 + 345*1000 + 6 = 1065006。
      // 上游 StringHelper.cs:200-211 的两段分支：第 207 行在 times[1] 含 '.' 时把
      // 拆分出的 [_times[0], _times[1]] 整段累加（345*1000 + 6 = 345006），
      // 第 210 行再累加 `int.Parse(times[0]) * 1000 * 60`（12*60000 = 720000）。
      // 毫秒位不补零：'006' → 6，不是 006 毫秒位的 6ms，而是直接加 6。
      expect(StringHelper.getMillisecondsFromString('12:345.006'), 1065006);
      // 2 段且第 2 段无点号：上游不累加秒数（只取分钟 × 60000）
      expect(StringHelper.getMillisecondsFromString('1:30'), 60000);
      expect(StringHelper.getMillisecondsFromString('0:00'), 0);
    });

    test('时:分:秒(.毫秒)', () {
      expect(StringHelper.getMillisecondsFromString('1:00:00'), 3600000);
      // 1h + 2min = 3720000，"03" 这 3 秒被上游丢弃。
      // 上游 StringHelper.cs:212-224 的三段分支里，第 214 行 `if (times[2].Contains('.'))`
      // 才把 times[2] 拆点累加；纯 "03" 不含点号 → 既不加 3000 也不加 4，
      // 只剩第 222-223 行的 2*60000 + 1*3600000。
      expect(StringHelper.getMillisecondsFromString('1:02:03'), 3720000);
      expect(StringHelper.getMillisecondsFromString('1:02:03.004'), 3723004);
      expect(StringHelper.getMillisecondsFromString('01:02:03.004'), 3723004);
      expect(StringHelper.getMillisecondsFromString('0:00:00.000'), 0);
    });

    test('解析失败返回 null（上游 catch { }）', () {
      expect(StringHelper.getMillisecondsFromString('abc'), isNull);
      expect(StringHelper.getMillisecondsFromString('12:ab'), 720000);
      // 12:ab → 720000，不是 null：上游 StringHelper.cs:202 只在 times[1] 含 '.' 时
      // 才 Parse 它，"ab" 从头到尾没被解析，不抛异常；
      // 只有第 210 行 int.Parse(times[0]) * 1000 * 60 = 12*60000 生效。
      expect(StringHelper.getMillisecondsFromString('1:2:x'), 3720000);
      // 1:2:x → 3720000，不是 null：三段分支同理（StringHelper.cs:214 只在含 '.' 时
      // 才碰 times[2]），"x" 不会被 Parse；累加 1*3600000 + 2*60000。
      expect(StringHelper.getMillisecondsFromString(''), isNull);
      expect(StringHelper.getMillisecondsFromString(null), isNull);
      // 3 段（超过两段）无法解析
      expect(StringHelper.getMillisecondsFromString('1.2.3'), isNull);
      // 前后空白：C# int.Parse 会 Trim 后成功，见下面两条断言
      expect(StringHelper.getMillisecondsFromString(' 12'), 12);
      // 上面这条的依据：上游 StringHelper.cs:193 是裸的 int.Parse(time)，默认
      // NumberStyles.Integer = AllowLeadingWhite | AllowTrailingWhite | AllowLeadingSign，
      // 首尾空白会被吃掉 → 解析成功返回 12（不是 null）。
      // 越界输入则抛 OverflowException，同样被第 228 行 catch { } 吞成 null：
      expect(StringHelper.getMillisecondsFromString('99999999999'), isNull);
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
      // 'a' + U+1F600（UTF-16 = D83D DE00）→ 按代码单元整体反转 = DE00 D83D 61。
      // 上游 StringHelper.cs:292-300：`str.ToCharArray()` + `Array.Reverse(arr)`，
      // char[] 的元素就是 UTF-16 代码单元，不做代理对感知的分组。
      expect(StringHelper.reverse('a😀'), '\uDE00\uD83Da');
    });

    test('remove：移除全部出现', () {
      expect(StringHelper.remove('a-b-c', '-'), 'abc');
      expect(StringHelper.remove('abc', 'x'), 'abc');
      expect(StringHelper.remove('abc', ''), 'abc'); // C# Replace(s, "") 原样
      expect(StringHelper.remove('', 'x'), '');
    });
  });

  group('StringHelper.computeTextSame 舍入 = .NET 的 ToEven', () {
    // 期望值**不是手推的**，是本机 CLR 实跑 Math.Round(x, 2) 的输出
    // （.NET 默认 MidpointRounding.ToEven）。
    //
    // ratio = LCS / max(len) * 100。这里刻意让 **max(len) 是 2 的幂**：
    // LCS/n 是二进制精确值，再乘 100（= 4*25）仍然是精确值，于是 ratio 恰好等于
    // 那些"正好 .5"的十进制数，不会因为浮点尾数落在临界点上而测不出舍入方向。
    // 之前用 n = 20000 那种除不尽的长度，ratio 实际是 12.3549999…，
    // 根本走不到 tie 分支，测了个寂寞。
    double ratioFor(int lcs, int n) =>
        StringHelper.computeTextSame('a' * lcs, 'a' * n, true);

    test('正好 .5 时取偶（ToEven），不是 half-up', () {
      // ratio = LCS*100/32：LCS=1 → 3.125。.NET 给 3.12（2 是偶）；half-up 会给 3.13
      expect(ratioFor(1, 32), 3.12);
      // LCS=3 → 9.375，保留部分 "9.37" 最低位 7 是奇数 → 进位 ⇒ 9.38
      expect(ratioFor(3, 32), 9.38);
      // LCS=10,n=64 → 15.625，保留部分 "15.62" 最低位 2 是偶数 → **不进位** ⇒ 15.62
      // （half-up 会给 15.63，这一条就是专门区分两者的）
      expect(ratioFor(10, 64), 15.62);
      // 同一个 tie 值从另一条 LCS/长度比走过来，结果必须一致
      expect(ratioFor(6, 64), 9.38);
    });

    test('第三位不是 5 时按普通四舍五入', () {
      // LCS*100/64 = LCS*1.5625
      expect(ratioFor(1, 64), 1.56); // 第三位 2 → 舍
      expect(ratioFor(5, 64), 7.81); // 7.8125，第三位 2 → 舍
      expect(ratioFor(9, 64), 14.06); // 14.0625，第三位 2 → 舍
      // 不足两位小数时不需要舍入
      expect(ratioFor(1, 16), 6.25);
    });

    test('边界', () {
      expect(StringHelper.computeTextSame('', '', true), 0);
      expect(StringHelper.computeTextSame('abc', '', true), 0);
      expect(ratioFor(4, 4), 100);
      expect(ratioFor(0, 4), 0);
    });
  });

  group('StringHelper.removeControlChars', () {
    test('移除 C0 / DEL 控制字符', () {
      expect(StringHelper.removeControlChars('a\u0001b'), 'ab');
      expect(StringHelper.removeControlChars('a\u007Fb'), 'ab');
      expect(StringHelper.removeControlChars('a\u0000b\u001Fc'), 'abc');
      // \t \n \r 也在 C0 区间里，.NET 的 char.IsControl 对它们返回 true，
      // 所以上游 StringHelper.cs:330 的 RemoveControlChars("a\nb\tc\rd") 就是 "abcd"——
      // 换行被吃掉。看着反直觉，但这是上游行为，照抄。
      expect(StringHelper.removeControlChars('a\nb\tc\rd'), 'abcd');
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
      // 全角逗号 '，'(U+FF0C) 同样在 symbolRegex 里（StringHelper.cs:402 的字符类尾部是
      // "。”’、？"），所以第 439 行的 !isSymbol 不成立 → 标点旁不加空格。
      expect(StringHelper.optimizeCJK('你好，world'), '你好，world');
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
      // 上游 StringHelper.cs:543 的签名是 IsEmoji(char character, bool full = true)，
      // char 是 16 位值类型，不存在"空串"这种输入；最接近的合法入参是 '\0'，
      // ToString() 得到 "\0"。EmojiPattern（StringHelper.cs:530）里每个分支
      // 都至少含 1 个可见 emoji 字符，没有可空分支 → 匹配结果为 false。
      expect(StringHelper.isEmoji(''), isFalse);
      expect(StringHelper.isEmoji('\u0000'), isFalse);
    });

    test('isEmoji(full=false)：上游的快速区间分支', () {
      // 快速分支的区间
      expect(StringHelper.isEmoji('☀', false), isTrue); // U+2600 区间
      expect(StringHelper.isEmoji('⭕', false), isTrue); // U+2B55
      expect(StringHelper.isEmoji('★', false), isTrue); // ★ U+2605 落在 0x2600-0x26FF
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
}
