// Ported from Lyricify.Lyrics.Helper/Helpers/General/StringHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// 与上游的适配点（每条都是 C# 语义在 Dart 里无法逐字直译的地方）：
//   1. `ComputeTextSame`：C# 形参是 `string`（非空），`textX.Length` 遇 null 会抛 NRE；
//      移植契约（docs/lyricify-port.md 3.6）的签名是 `String?`，这里对 null 直接返回 0
//      （见方法内的 PORT NOTE）。
//   2. `Between`：C# 找不到 start 时 `return null`（StringHelper.cs:283）；
//      移植契约要求返回非空 `String`，所以本移植抛 StateError（见方法内的 PORT NOTE）。
//   3. `Reverse` / `RemoveControlChars` / `ToUpperFirst` / `RemoveFrontBackBrackets` /
//      `RemoveDuoBackslashN` / `RemoveBackslashR` / `Remove` 里的 `if (str == null) return null`
//      在移植侧形参已是非空 `String`，改写成 `str == ''` 提前返回，行为等价。
//   4. `IsEmoji` / `IsChinese` 的上游形参是 `char`（单字符值类型），移植侧用 `String`
//      并按第 1 个 UTF-16 代码单元复刻；空串按"没有代码单元"处理（见方法内的 PORT NOTE）。
//   5. `GetMillisecondsFromString` 里的 `int.Parse` 用 C# `NumberStyles.Integer` 语义复刻：
//      允许首尾空白 + 可选前导符号 + 十进制数字，溢出抛异常并被上游的 `catch { }` 吞成 null。
//   6. `IsSameWhiteSpace`：C# `string.IsNullOrWhiteSpace` → Dart `str.trim().isEmpty`。
library;

import 'chinese_helper.dart';

class StringHelper {
  // #region Comparison

  static bool isSame(String? str1, String? str2) {
    if (str1 == str2) return true;
    if ((str1 == null || str1.isEmpty) && (str2 == null || str2.isEmpty)) {
      return true;
    }
    return false;
  }

  static bool isSameWhiteSpace(String? str1, String? str2) {
    if (str1 == str2) return true;
    if ((str1 == null || str1.trim().isEmpty) &&
        (str2 == null || str2.trim().isEmpty)) {
      return true;
    }
    return false;
  }

  static bool isSameTrim(String? str1, String? str2) {
    str1 = (str1 ?? '').trim();
    str2 = (str2 ?? '').trim();
    if (str1 == str2) return true;
    if (str1.isEmpty && str2.isEmpty) return true;
    return false;
  }

  /// 计算文本相似度函数 (适用于短文本)
  /// @param isCase 是否区分大小写
  /// @returns 0-100
  static double computeTextSame(
    String? textX,
    String? textY, [
    bool isCase = false,
  ]) {
    // PORT NOTE: 上游 StringHelper.cs:50 是 `textX.Length <= 0 || textY.Length <= 0`，
    // 形参是非空 `string`，传 null 会在这一行抛 NullReferenceException；
    // Dart 契约 3.6 的形参是 `String?`，这里把 null 当成长度 0 处理（返回 0）。
    if (textX == null || textY == null) return 0;
    if (textX.isEmpty || textY.isEmpty) return 0;
    if (!isCase) {
      textX = textX.toLowerCase();
      textY = textY.toLowerCase();
    }
    final n = textX.length > textY.length ? textX.length : textY.length;
    final dp = List<int>.filled((n + 1) * (n + 1), 0);
    int at(int x, int y) => dp[x * (n + 1) + y];
    void set(int x, int y, int v) => dp[x * (n + 1) + y] = v;
    for (var x = 0; x < textX.length; x++) {
      for (var y = 0; y < textY.length; y++) {
        if (textX[x] == textY[y]) {
          set(x + 1, y + 1, at(x, y) + 1);
        } else {
          set(
            x + 1,
            y + 1,
            at(x, y + 1) > at(x + 1, y) ? at(x, y + 1) : at(x + 1, y),
          );
        }
      }
    }
    final ratio = at(textX.length, textY.length) / n * 100;
    // PORT NOTE（舍入）: 上游 StringHelper.cs:74 是 `Math.Round(ratio, 2)`，而 .NET 的
    // Math.Round 默认 MidpointRounding.ToEven（银行家舍入）——正好 .5 时取偶。
    // Dart 的 toStringAsFixed 是 half-up，正好 .5 时进位。所以这里必须自己实现 ToEven，
    // 否则 ratio 落在 x.xx5 这类边界上会和上游差 0.01。
    return _roundToEven(ratio, 2);
  }

  /// C# `Math.Round(value, digits)`（默认 `MidpointRounding.ToEven`，银行家舍入）。
  ///
  /// 两个常见写法都会和 .NET 对不上：
  /// 1. `value.toStringAsFixed(digits)` 是 half-up。`.NET` 给 `3.125 → 3.12`（ToEven
  ///    取偶），half-up 给 `3.13`。差别只在正好 .5 时出现。
  /// 2. 先 `value * 10^digits` 再取整是在**二进制**上放大，非 tie 值也会错：
  ///    `2.675 * 100 = 267.49999999999997` → `2.67`，而 .NET 给 `2.68`。
  ///
  /// .NET 的做法是取**最短往返十进制表示**，在它上面做 half-to-even。所以这里全程
  /// 用字符串处理十进制（`Decimal` 在 `dart:core` 里没有，也不为这点事引新依赖），
  /// 最后一步才 parse 回 double。负数取绝对值算完再取符号，保证 ± 对称。
  static double _roundToEven(double value, int digits) {
    if (!value.isFinite) return value;
    final negative = value < 0;
    final abs = negative ? -value : value;

    var text = abs.toString(); // 最短往返表示
    if (text.contains('e') || text.contains('E')) {
      text = abs.toStringAsFixed(digits + 2); // 指数形式先落成普通小数
    }

    final dot = text.indexOf('.');
    var head = dot < 0 ? text : text.substring(0, dot);
    var tail = dot < 0 ? '' : text.substring(dot + 1);

    if (tail.length > digits) {
      final keep = tail.substring(0, digits);
      final rest = tail.substring(digits);
      final first = rest.codeUnitAt(0) - 0x30;

      var bump = 0;
      if (first > 5) {
        bump = 1;
      } else if (first == 5) {
        // rest 剩下的位是不是全 0？全 0 才是"正好 .5"
        var restIsZero = true;
        for (var k = 1; k < rest.length; k++) {
          if (rest.codeUnitAt(k) != 0x30) {
            restIsZero = false;
            break;
          }
        }
        if (!restIsZero) {
          bump = 1; // 大于 .5
        } else {
          // 正好 .5：ToEven 看保留部分的最低位，奇数才进位
          final lowest = digits == 0 ? 0 : keep.codeUnitAt(digits - 1) - 0x30;
          bump = lowest % 2 == 1 ? 1 : 0;
        }
      }

      if (bump == 1) {
        final chars = keep.split('');
        var i = chars.length - 1;
        while (i >= 0) {
          final v = chars[i].codeUnitAt(0) - 0x30 + 1;
          if (v == 10) {
            chars[i] = '0';
            i--;
          } else {
            chars[i] = String.fromCharCode(v + 0x30);
            break;
          }
        }
        if (i < 0) head = _incrementDecimal(head);
        tail = chars.join();
      } else {
        tail = keep;
      }
    }

    tail = tail.padRight(digits, '0');
    final result = double.parse('$head.$tail');
    return negative ? -result : result;
  }

  /// 十进制整数字符串 +1（"99" → "100"，"7" → "8"）。
  static String _incrementDecimal(String digits) {
    final chars = digits.split('');
    var i = chars.length - 1;
    while (i >= 0) {
      final v = chars[i].codeUnitAt(0) - 0x30 + 1;
      if (v == 10) {
        chars[i] = '0';
        i--;
      } else {
        chars[i] = String.fromCharCode(v + 0x30);
        return chars.join();
      }
    }
    return '1${chars.join()}';
  }

  // #endregion

  // #region Conversion & Process

  // #region Spaces

  static String removeDuoSpaces(String str) {
    while (str.contains('  ')) {
      str = str.replaceAll('  ', ' ');
    }
    return str;
  }

  static String removeTripleSpaces(String str) {
    while (str.contains('   ')) {
      str = str.replaceAll('   ', '  ');
    }
    return str;
  }

  static String fixCommaAfterSpace(String str) {
    str = str.replaceAll(',', ', ');
    return removeDuoSpaces(str);
  }

  // #endregion

  // #region Lines

  static String removeDuoBackslashN(String str) {
    if (str == '') return str;
    while (str.contains('\n\n')) {
      str = str.replaceAll('\n\n', '\n');
    }
    return str;
  }

  static String removeBackslashR(String str) {
    if (str == '') return str;
    str = str.replaceAll('\r', '');
    return str;
  }

  // #endregion

  // #region Date & Time

  /// 将毫秒数转换为时间戳字符串
  /// @param time 毫秒数
  /// @param millisecond 字符串中是否保留毫秒位
  /// @returns 时间戳字符串
  static String formatTimeMsToTimestampString(
    num time, [
    bool millisecond = true,
  ]) {
    if (time < 0) {
      return '0:00';
    }
    final intTime = time.toInt();
    final second = intTime ~/ 1000;
    var minute = 0;
    var secondRemainder = second;
    if (second >= 60) {
      minute = second ~/ 60;
      secondRemainder = second % 60;
    }
    final ms = intTime % 1000;
    return millisecond
        ? '${_d(minute, 2)}:${_d(secondRemainder, 2)}.${_d(ms, 3)}'
        : '${_d(minute, 1)}:${_d(secondRemainder, 2)}';
  }

  static int? getMillisecondsFromString(String? time) {
    // PORT NOTE: 上游 StringHelper.cs:181 直接 `time.Contains(':')`，传 null 会抛
    // NullReferenceException，被第 228 行的 `catch { }` 吞掉后第 229 行 `return null`；
    // Dart 不能对 null 调成员方法，这里显式短路成 null，结果与上游一致。
    if (time == null) return null;
    try {
      if (!time.contains(':')) {
        if (time.contains('.')) {
          final times = time.split('.');
          if (times.length == 2) {
            return _mp(times[0]) * 1000 + _mp(times[1]);
          }
        } else {
          return _mp(time);
        }
      } else {
        var timeTotal = 0;
        final times = time.split(':');
        if (times.length == 2) {
          if (times[1].contains('.')) {
            final subTimes = times[1].split('.');
            if (subTimes.length == 2) {
              timeTotal += _mp(subTimes[0]) * 1000 + _mp(subTimes[1]);
            }
          }
          timeTotal += _mp(times[0]) * 1000 * 60;
        } else if (times.length == 3) {
          if (times[2].contains('.')) {
            final subTimes = times[2].split('.');
            if (subTimes.length == 2) {
              timeTotal += _mp(subTimes[0]) * 1000 + _mp(subTimes[1]);
            }
          }
          timeTotal += _mp(times[1]) * 1000 * 60;
          timeTotal += _mp(times[0]) * 1000 * 60 * 60;
        }
        return timeTotal;
      }
    } on FormatException catch (_) {
      // 上游 StringHelper.cs:227-229 是空的 `catch { }`，吞掉一切异常后 `return null`
    }
    return null;
  }

  // #endregion

  // #region Case

  /// 字符串首字母大写
  static String toUpperFirst(String str, [int start = 0]) {
    if (str == '') return str;
    if (start >= str.length) return str;
    return str.substring(0, start) +
        str[start].toUpperCase() +
        str.substring(start + 1);
  }

  // #endregion

  /// 获取夹在两个字符串中间的字符串
  static String between(String str, String start, String end) {
    final startIndex = str.indexOf(start);
    if (startIndex != -1) {
      var result = str.substring(startIndex + start.length);
      final endIndex = result.indexOf(end);
      if (endIndex != -1) {
        result = result.substring(0, endIndex);
      }
      return result;
    } else {
      // PORT NOTE: 上游 StringHelper.cs:282-284 找不到 start 时 `return null`；
      // 契约 3.6 规定 Dart 侧返回非空 `String`，无法表达 null，
      // 这里抛 StateError 作为等价信号（调用点都是"必然命中"的解析场景）。
      throw StateError('StringHelper.between: start "$start" not found');
    }
  }

  /// 字符串反序
  static String reverse(String str) {
    if (str == '') return str;
    final sb = StringBuffer();
    for (var i = str.length - 1; i >= 0; i--) {
      sb.writeCharCode(str.codeUnitAt(i));
    }
    return sb.toString();
  }

  static String remove(String str, String substring) {
    if (str == '') return str;
    return str.replaceAll(substring, '');
  }

  /// 移除字符串中的控制字符
  /// @param excludeChars 不移除的控制字符
  /// @exception
  static String removeControlChars(
    String value, [
    List<String> excludeChars = const [],
  ]) {
    final excluded = excludeChars;
    final sb = StringBuffer();
    // PORT NOTE: C# `value.Where(c => !char.IsControl(c) || excludeChars2.Contains(c))`
    for (var i = 0; i < value.length; i++) {
      final cu = value.codeUnitAt(i);
      if (!_isControl(cu) || excluded.contains(value[i])) {
        sb.write(value[i]);
      }
    }
    return sb.toString();
  }

  static String fixIWords(String str) {
    str = str
        .replaceAll(' i ', ' I ')
        .replaceAll("i'd ", "I'd ")
        .replaceAll("i'm", "I'm")
        .replaceAll("i'll", "I'll")
        .replaceAll("i've", "I've");
    return str;
  }

  static String removeFrontBackBrackets(String str) {
    if (str == '') return str;
    str = str.trim();
    if (str.isEmpty) return str;
    if (str[0] == '(' || str[0] == '（') str = str.substring(1);
    if (str.isEmpty) return str;
    if (str[str.length - 1] == ')' || str[str.length - 1] == '）') {
      str = str.substring(0, str.length - 1);
    }
    return str.trim();
  }

  // #endregion

  // #region Determine

  static bool canStartNewLine(String str) {
    if (str.endsWith(' ') || str.endsWith(',') || str.endsWith('/')) {
      return true;
    }
    return false;
  }

  ///
  static bool containsAny(String str, List<String> list) {
    for (final item in list) {
      if (str.contains(item)) return true;
    }
    return false;
  }

  static bool isNumber(String str) {
    return RegExp(r'^\d+$').hasMatch(str);
  }

  // #endregion

  // #region CJK

  static bool hasCJK(String str, [bool includeColon = false]) {
    if (includeColon && str.contains('：')) return true;
    str = str.replaceAll(_symbolRegex, '');
    for (var i = 0; i < str.length; i++) {
      final cu = str.codeUnitAt(i);
      if (_isCJKUnifiedIdeographs(cu)) return true;
    }
    if (str.isEmpty) return false;
    final first = str.codeUnitAt(0);
    if (first >= 0x0800 && first <= 0x4E00) return true;
    if (first >= 0x4E00 && first <= 0x9FA5) return true;
    if (first >= 0xAC00 && first <= 0xD7FF) return true;
    return false;
  }

  static bool isCJK(String str, [bool includeColon = false]) {
    if (includeColon && str == '：') return true;
    for (var i = 0; i < str.length; i++) {
      if (_isCJKUnifiedIdeographs(str.codeUnitAt(i))) return true;
    }
    return false;
  }

  static String optimizeCJK(String str) {
    final text = StringBuffer();

    var isCJKPrev = false;
    var isSymbolPrev = false;
    for (var i = 0; i < str.length; i++) {
      final ch = str[i];
      final chStr = ch;

      final isSymbol = _symbolRegex.hasMatch(chStr);
      final isCJK = _isCJKUnifiedIdeographs(ch.codeUnitAt(0));

      // Use spaces to separate non-CJK words.
      if (isCJK != isCJKPrev && !isSymbol && !isSymbolPrev) {
        text.write(' ');
      }

      text.write(ch);
      isCJKPrev = isCJK;
      isSymbolPrev = isSymbol;
    }
    return text.toString().replaceAll('  ', ' ').trim();
  }

  // #endregion

  // #region Chinese

  /// 判断字符是否为单个汉字
  static bool isChinese(String ch) {
    if (ch.isEmpty) return false;
    final cu = ch.codeUnitAt(0);
    return cu >= 0x4E00 && cu <= 0x9FFF;
  }

  static bool hasChinese(String str) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(str);
  }

  /// 字符串中中文占百分比
  /// @returns 0-1
  static double chinesePercentage(String text) {
    var count = 0;
    var spareCount = 0;
    for (var i = 0; i < text.length; i++) {
      if (isChinese(text[i])) {
        count++;
      } else if (text[i] == '\n' || text[i] == '\r' || text[i] == '\t') {
        spareCount++;
      }
    }
    return text.length - spareCount > 0
        ? count / (text.length - spareCount)
        : 0;
  }

  /// 是否是繁体中文文本的信心
  /// @returns 信心百分比
  static double traditionalChineseConfidence(String text) {
    var n = 0;
    var total = 0;
    final sc = ChineseHelper.toSC(text);
    for (var i = 0; i < text.length; i++) {
      if (isChinese(text[i])) {
        total++;
        if (text[i] != sc[i]) {
          n++;
        }
      }
    }
    // 上游是 `return (double)n / total;`——C# 的强制转换。Dart 的 `/` 对 int
    // 本来就返回 double，直接除即可（`(double)n` 在 Dart 里 `double` 是个类型名，
    // 不是转型语法）。
    return n / total;
  }

  // #endregion
  // #region Emoji

  static const String emojiPattern =
      r'''(🏴󠁥󠁳󠁣󠁴󠁿|🏴󠁦󠁲󠁢󠁲󠁥󠁿|🏴󠁥󠁳󠁰󠁶󠁿|🏴󠁣󠁡󠁱󠁣󠁿|🏴󠁥󠁳󠁡󠁳󠁿|🏴️?‍🅰️?|🐱‍🏍|🐱‍👓|🐱‍🚀|🐱‍👤|🐱‍🐉|🐱‍💻|(👨|👩)(🏻|🏼|🏽|🏾|🏿)?(‍(👨|👩)(🏻|🏼|🏽|🏾|🏿)?)*(‍(👦|👧|👶)(🏻|🏼|🏽|🏾|🏿)?)+|👩(🏻|🏼|🏽|🏾|🏿)‍❤️?‍💋‍👨(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)‍❤️?‍💋‍👨(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤️?‍💋‍👩(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤‍💋‍👨(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)‍❤‍💋‍👨(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤‍💋‍👩(🏻|🏼|🏽|🏾|🏿)|🧑(🏻|🏼|🏽|🏾|🏿)‍🤝‍🧑(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤️?‍👨(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)‍❤️?‍👨(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤️?‍👩(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤‍👨(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)‍❤‍👨(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)‍❤‍👩(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)‍(🦰|🦱|🦳|🦲)|👩(🏻|🏼|🏽|🏾|🏿)‍(🦰|🦱|🦳|🦲)|🧑(🏻|🏼|🏽|🏾|🏿)‍(🦰|🦱|🦳|🦲)|🧔(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧔(🏻|🏼|🏽|🏾|🏿)‍♀️?|👱(🏻|🏼|🏽|🏾|🏿)‍♀️?|👱(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙍(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙍(🏻|🏼|🏽|🏾|🏿)‍♀️?|🙎(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙎(🏻|🏼|🏽|🏾|🏿)‍♀️?|🙅(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙅(🏻|🏼|🏽|🏾|🏿)‍♀️?|🙆(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙆(🏻|🏼|🏽|🏾|🏿)‍♀️?|💁(🏻|🏼|🏽|🏾|🏿)‍♂️?|💁(🏻|🏼|🏽|🏾|🏿)‍♀️?|🙋(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙋(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧏(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧏(🏻|🏼|🏽|🏾|🏿)‍♀️?|🙇(🏻|🏼|🏽|🏾|🏿)‍♂️?|🙇(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤦(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤦(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤷(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤷(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧑(🏻|🏼|🏽|🏾|🏿)‍⚕️?|👨(🏻|🏼|🏽|🏾|🏿)‍⚕️?|👩(🏻|🏼|🏽|🏾|🏿)‍⚕️?|🧑(🏻|🏼|🏽|🏾|🏿)‍🎓|👨(🏻|🏼|🏽|🏾|🏿)‍🎓|👩(🏻|🏼|🏽|🏾|🏿)‍🎓|🧑(🏻|🏼|🏽|🏾|🏿)‍🏫|👨(🏻|🏼|🏽|🏾|🏿)‍🏫|👩(🏻|🏼|🏽|🏾|🏿)‍🏫|🧑(🏻|🏼|🏽|🏾|🏿)‍⚖️?|👨(🏻|🏼|🏽|🏾|🏿)‍⚖️?|👩(🏻|🏼|🏽|🏾|🏿)‍⚖️?|🧑(🏻|🏼|🏽|🏾|🏿)‍🌾|👨(🏻|🏼|🏽|🏾|🏿)‍🌾|👩(🏻|🏼|🏽|🏾|🏿)‍🌾|🧑(🏻|🏼|🏽|🏾|🏿)‍🍳|👨(🏻|🏼|🏽|🏾|🏿)‍🍳|👩(🏻|🏼|🏽|🏾|🏿)‍🍳|🧑(🏻|🏼|🏽|🏾|🏿)‍🔧|👨(🏻|🏼|🏽|🏾|🏿)‍🔧|👩(🏻|🏼|🏽|🏾|🏿)‍🔧|🧑(🏻|🏼|🏽|🏾|🏿)‍🏭|👨(🏻|🏼|🏽|🏾|🏿)‍🏭|👩(🏻|🏼|🏽|🏾|🏿)‍🏭|🧑(🏻|🏼|🏽|🏾|🏿)‍💼|👨(🏻|🏼|🏽|🏾|🏿)‍💼|👩(🏻|🏼|🏽|🏾|🏿)‍💼|🧑(🏻|🏼|🏽|🏾|🏿)‍🔬|👨(🏻|🏼|🏽|🏾|🏿)‍🔬|👩(🏻|🏼|🏽|🏾|🏿)‍🔬|🧑(🏻|🏼|🏽|🏾|🏿)‍💻|👨(🏻|🏼|🏽|🏾|🏿)‍💻|👩(🏻|🏼|🏽|🏾|🏿)‍💻|🧑(🏻|🏼|🏽|🏾|🏿)‍🎤|👨(🏻|🏼|🏽|🏾|🏿)‍🎤|👩(🏻|🏼|🏽|🏾|🏿)‍🎤|🧑(🏻|🏼|🏽|🏾|🏿)‍🎨|👨(🏻|🏼|🏽|🏾|🏿)‍🎨|👩(🏻|🏼|🏽|🏾|🏿)‍🎨|🧑(🏻|🏼|🏽|🏾|🏿)‍✈️?|👨(🏻|🏼|🏽|🏾|🏿)‍✈️?|👩(🏻|🏼|🏽|🏾|🏿)‍✈️?|🧑(🏻|🏼|🏽|🏾|🏿)‍🚀|👨(🏻|🏼|🏽|🏾|🏿)‍🚀|👩(🏻|🏼|🏽|🏾|🏿)‍🚀|🧑(🏻|🏼|🏽|🏾|🏿)‍🚒|👨(🏻|🏼|🏽|🏾|🏿)‍🚒|👩(🏻|🏼|🏽|🏾|🏿)‍🚒|👮(🏻|🏼|🏽|🏾|🏿)‍♂️?|👮(🏻|🏼|🏽|🏾|🏿)‍♀️?|🕵(🏻|🏼|🏽|🏾|🏿)‍♂️?|🕵(🏻|🏼|🏽|🏾|🏿)‍♀️?|💂(🏻|🏼|🏽|🏾|🏿)‍♂️?|💂(🏻|🏼|🏽|🏾|🏿)‍♀️?|👷(🏻|🏼|🏽|🏾|🏿)‍♂️?|👷(🏻|🏼|🏽|🏾|🏿)‍♀️?|👳(🏻|🏼|🏽|🏾|🏿)‍♂️?|👳(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤵(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤵(🏻|🏼|🏽|🏾|🏿)‍♀️?|👰(🏻|🏼|🏽|🏾|🏿)‍♂️?|👰(🏻|🏼|🏽|🏾|🏿)‍♀️?|👩(🏻|🏼|🏽|🏾|🏿)‍🍼|👨(🏻|🏼|🏽|🏾|🏿)‍🍼|🧑(🏻|🏼|🏽|🏾|🏿)‍🍼|🧑(🏻|🏼|🏽|🏾|🏿)‍🎄|🦸(🏻|🏼|🏽|🏾|🏿)‍♂️?|🦸(🏻|🏼|🏽|🏾|🏿)‍♀️?|🦹(🏻|🏼|🏽|🏾|🏿)‍♂️?|🦹(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧙(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧙(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧚(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧚(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧛(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧛(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧜(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧜(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧝(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧝(🏻|🏼|🏽|🏾|🏿)‍♀️?|💆(🏻|🏼|🏽|🏾|🏿)‍♂️?|💆(🏻|🏼|🏽|🏾|🏿)‍♀️?|💇(🏻|🏼|🏽|🏾|🏿)‍♂️?|💇(🏻|🏼|🏽|🏾|🏿)‍♀️?|🚶(🏻|🏼|🏽|🏾|🏿)‍♂️?|🚶(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧍(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧍(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧎(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧎(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧑(🏻|🏼|🏽|🏾|🏿)‍🦯|👨(🏻|🏼|🏽|🏾|🏿)‍🦯|👩(🏻|🏼|🏽|🏾|🏿)‍🦯|🧑(🏻|🏼|🏽|🏾|🏿)‍🦼|👨(🏻|🏼|🏽|🏾|🏿)‍🦼|👩(🏻|🏼|🏽|🏾|🏿)‍🦼|🧑(🏻|🏼|🏽|🏾|🏿)‍🦽|👨(🏻|🏼|🏽|🏾|🏿)‍🦽|👩(🏻|🏼|🏽|🏾|🏿)‍🦽|🏃(🏻|🏼|🏽|🏾|🏿)‍♂️?|🏃(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧖(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧖(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧗(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧗(🏻|🏼|🏽|🏾|🏿)‍♀️?|🏌(🏻|🏼|🏽|🏾|🏿)‍♂️?|🏌(🏻|🏼|🏽|🏾|🏿)‍♀️?|🏄(🏻|🏼|🏽|🏾|🏿)‍♂️?|🏄(🏻|🏼|🏽|🏾|🏿)‍♀️?|🚣(🏻|🏼|🏽|🏾|🏿)‍♂️?|🚣(🏻|🏼|🏽|🏾|🏿)‍♀️?|🏊(🏻|🏼|🏽|🏾|🏿)‍♂️?|🏊(🏻|🏼|🏽|🏾|🏿)‍♀️?|🏋(🏻|🏼|🏽|🏾|🏿)‍♂️?|🏋(🏻|🏼|🏽|🏾|🏿)‍♀️?|🚴(🏻|🏼|🏽|🏾|🏿)‍♂️?|🚴(🏻|🏼|🏽|🏾|🏿)‍♀️?|🚵(🏻|🏼|🏽|🏾|🏿)‍♂️?|🚵(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤸(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤸(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤽(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤽(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤾(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤾(🏻|🏼|🏽|🏾|🏿)‍♀️?|🤹(🏻|🏼|🏽|🏾|🏿)‍♂️?|🤹(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧘(🏻|🏼|🏽|🏾|🏿)‍♂️?|🧘(🏻|🏼|🏽|🏾|🏿)‍♀️?|🧔(🏻|🏼|🏽|🏾|🏿)‍♂|🧔(🏻|🏼|🏽|🏾|🏿)‍♀|👱(🏻|🏼|🏽|🏾|🏿)‍♀|👱(🏻|🏼|🏽|🏾|🏿)‍♂|🙍(🏻|🏼|🏽|🏾|🏿)‍♂|🙍(🏻|🏼|🏽|🏾|🏿)‍♀|🙎(🏻|🏼|🏽|🏾|🏿)‍♂|🙎(🏻|🏼|🏽|🏾|🏿)‍♀|🙅(🏻|🏼|🏽|🏾|🏿)‍♂|🙅(🏻|🏼|🏽|🏾|🏿)‍♀|🙆(🏻|🏼|🏽|🏾|🏿)‍♂|🙆(🏻|🏼|🏽|🏾|🏿)‍♀|💁(🏻|🏼|🏽|🏾|🏿)‍♂|💁(🏻|🏼|🏽|🏾|🏿)‍♀|🙋(🏻|🏼|🏽|🏾|🏿)‍♂|🙋(🏻|🏼|🏽|🏾|🏿)‍♀|🧏(🏻|🏼|🏽|🏾|🏿)‍♂|🧏(🏻|🏼|🏽|🏾|🏿)‍♀|🙇(🏻|🏼|🏽|🏾|🏿)‍♂|🙇(🏻|🏼|🏽|🏾|🏿)‍♀|🤦(🏻|🏼|🏽|🏾|🏿)‍♂|🤦(🏻|🏼|🏽|🏾|🏿)‍♀|🤷(🏻|🏼|🏽|🏾|🏿)‍♂|🤷(🏻|🏼|🏽|🏾|🏿)‍♀|🧑(🏻|🏼|🏽|🏾|🏿)‍⚕|👨(🏻|🏼|🏽|🏾|🏿)‍⚕|👩(🏻|🏼|🏽|🏾|🏿)‍⚕|🧑(🏻|🏼|🏽|🏾|🏿)‍⚖|👨(🏻|🏼|🏽|🏾|🏿)‍⚖|👩(🏻|🏼|🏽|🏾|🏿)‍⚖|🧑(🏻|🏼|🏽|🏾|🏿)‍✈|👨(🏻|🏼|🏽|🏾|🏿)‍✈|👩(🏻|🏼|🏽|🏾|🏿)‍✈|👮(🏻|🏼|🏽|🏾|🏿)‍♂|👮(🏻|🏼|🏽|🏾|🏿)‍♀|🕵(🏻|🏼|🏽|🏾|🏿)‍♂|🕵(🏻|🏼|🏽|🏾|🏿)‍♀|💂(🏻|🏼|🏽|🏾|🏿)‍♂|💂(🏻|🏼|🏽|🏾|🏿)‍♀|👷(🏻|🏼|🏽|🏾|🏿)‍♂|👷(🏻|🏼|🏽|🏾|🏿)‍♀|👳(🏻|🏼|🏽|🏾|🏿)‍♂|👳(🏻|🏼|🏽|🏾|🏿)‍♀|🤵(🏻|🏼|🏽|🏾|🏿)‍♂|🤵(🏻|🏼|🏽|🏾|🏿)‍♀|👰(🏻|🏼|🏽|🏾|🏿)‍♂|👰(🏻|🏼|🏽|🏾|🏿)‍♀|🦸(🏻|🏼|🏽|🏾|🏿)‍♂|🦸(🏻|🏼|🏽|🏾|🏿)‍♀|🦹(🏻|🏼|🏽|🏾|🏿)‍♂|🦹(🏻|🏼|🏽|🏾|🏿)‍♀|🧙(🏻|🏼|🏽|🏾|🏿)‍♂|🧙(🏻|🏼|🏽|🏾|🏿)‍♀|🧚(🏻|🏼|🏽|🏾|🏿)‍♂|🧚(🏻|🏼|🏽|🏾|🏿)‍♀|🧛(🏻|🏼|🏽|🏾|🏿)‍♂|🧛(🏻|🏼|🏽|🏾|🏿)‍♀|🧜(🏻|🏼|🏽|🏾|🏿)‍♂|🧜(🏻|🏼|🏽|🏾|🏿)‍♀|🧝(🏻|🏼|🏽|🏾|🏿)‍♂|🧝(🏻|🏼|🏽|🏾|🏿)‍♀|💆(🏻|🏼|🏽|🏾|🏿)‍♂|💆(🏻|🏼|🏽|🏾|🏿)‍♀|💇(🏻|🏼|🏽|🏾|🏿)‍♂|💇(🏻|🏼|🏽|🏾|🏿)‍♀|🚶(🏻|🏼|🏽|🏾|🏿)‍♂|🚶(🏻|🏼|🏽|🏾|🏿)‍♀|🧍(🏻|🏼|🏽|🏾|🏿)‍♂|🧍(🏻|🏼|🏽|🏾|🏿)‍♀|🧎(🏻|🏼|🏽|🏾|🏿)‍♂|🧎(🏻|🏼|🏽|🏾|🏿)‍♀|🏃(🏻|🏼|🏽|🏾|🏿)‍♂|🏃(🏻|🏼|🏽|🏾|🏿)‍♀|🧖(🏻|🏼|🏽|🏾|🏿)‍♂|🧖(🏻|🏼|🏽|🏾|🏿)‍♀|🧗(🏻|🏼|🏽|🏾|🏿)‍♂|🧗(🏻|🏼|🏽|🏾|🏿)‍♀|🏌(🏻|🏼|🏽|🏾|🏿)‍♂|🏌(🏻|🏼|🏽|🏾|🏿)‍♀|🏄(🏻|🏼|🏽|🏾|🏿)‍♂|🏄(🏻|🏼|🏽|🏾|🏿)‍♀|🚣(🏻|🏼|🏽|🏾|🏿)‍♂|🚣(🏻|🏼|🏽|🏾|🏿)‍♀|🏊(🏻|🏼|🏽|🏾|🏿)‍♂|🏊(🏻|🏼|🏽|🏾|🏿)‍♀|⛹(🏻|🏼|🏽|🏾|🏿)‍♂️?|⛹(🏻|🏼|🏽|🏾|🏿)‍♀️?|🏋(🏻|🏼|🏽|🏾|🏿)‍♂|🏋(🏻|🏼|🏽|🏾|🏿)‍♀|🚴(🏻|🏼|🏽|🏾|🏿)‍♂|🚴(🏻|🏼|🏽|🏾|🏿)‍♀|🚵(🏻|🏼|🏽|🏾|🏿)‍♂|🚵(🏻|🏼|🏽|🏾|🏿)‍♀|🤸(🏻|🏼|🏽|🏾|🏿)‍♂|🤸(🏻|🏼|🏽|🏾|🏿)‍♀|🤽(🏻|🏼|🏽|🏾|🏿)‍♂|🤽(🏻|🏼|🏽|🏾|🏿)‍♀|🤾(🏻|🏼|🏽|🏾|🏿)‍♂|🤾(🏻|🏼|🏽|🏾|🏿)‍♀|🤹(🏻|🏼|🏽|🏾|🏿)‍♂|🤹(🏻|🏼|🏽|🏾|🏿)‍♀|🧘(🏻|🏼|🏽|🏾|🏿)‍♂|🧘(🏻|🏼|🏽|🏾|🏿)‍♀|⛹(🏻|🏼|🏽|🏾|🏿)‍♂|⛹(🏻|🏼|🏽|🏾|🏿)‍♀|👋(🏻|🏼|🏽|🏾|🏿)|🤚(🏻|🏼|🏽|🏾|🏿)|🖐(🏻|🏼|🏽|🏾|🏿)|🖖(🏻|🏼|🏽|🏾|🏿)|🫱(🏻|🏼|🏽|🏾|🏿)|🫲(🏻|🏼|🏽|🏾|🏿)|🫳(🏻|🏼|🏽|🏾|🏿)|🫴(🏻|🏼|🏽|🏾|🏿)|🫷(🏻|🏼|🏽|🏾|🏿)|🫸(🏻|🏼|🏽|🏾|🏿)|👌(🏻|🏼|🏽|🏾|🏿)|🤌(🏻|🏼|🏽|🏾|🏿)|🤏(🏻|🏼|🏽|🏾|🏿)|🤞(🏻|🏼|🏽|🏾|🏿)|🫰(🏻|🏼|🏽|🏾|🏿)|🤟(🏻|🏼|🏽|🏾|🏿)|🤘(🏻|🏼|🏽|🏾|🏿)|🤙(🏻|🏼|🏽|🏾|🏿)|👈(🏻|🏼|🏽|🏾|🏿)|👉(🏻|🏼|🏽|🏾|🏿)|👆(🏻|🏼|🏽|🏾|🏿)|🖕(🏻|🏼|🏽|🏾|🏿)|👇(🏻|🏼|🏽|🏾|🏿)|🫵(🏻|🏼|🏽|🏾|🏿)|👍(🏻|🏼|🏽|🏾|🏿)|👎(🏻|🏼|🏽|🏾|🏿)|👊(🏻|🏼|🏽|🏾|🏿)|🤛(🏻|🏼|🏽|🏾|🏿)|🤜(🏻|🏼|🏽|🏾|🏿)|👏(🏻|🏼|🏽|🏾|🏿)|🙌(🏻|🏼|🏽|🏾|🏿)|🫶(🏻|🏼|🏽|🏾|🏿)|👐(🏻|🏼|🏽|🏾|🏿)|🤲(🏻|🏼|🏽|🏾|🏿)|🤝(🏻|🏼|🏽|🏾|🏿)|🙏(🏻|🏼|🏽|🏾|🏿)|💅(🏻|🏼|🏽|🏾|🏿)|🤳(🏻|🏼|🏽|🏾|🏿)|💪(🏻|🏼|🏽|🏾|🏿)|🦵(🏻|🏼|🏽|🏾|🏿)|🦶(🏻|🏼|🏽|🏾|🏿)|👂(🏻|🏼|🏽|🏾|🏿)|🦻(🏻|🏼|🏽|🏾|🏿)|👃(🏻|🏼|🏽|🏾|🏿)|👶(🏻|🏼|🏽|🏾|🏿)|🧒(🏻|🏼|🏽|🏾|🏿)|👦(🏻|🏼|🏽|🏾|🏿)|👧(🏻|🏼|🏽|🏾|🏿)|🧑(🏻|🏼|🏽|🏾|🏿)|👱(🏻|🏼|🏽|🏾|🏿)|👨(🏻|🏼|🏽|🏾|🏿)|🧔(🏻|🏼|🏽|🏾|🏿)|👩(🏻|🏼|🏽|🏾|🏿)|🧓(🏻|🏼|🏽|🏾|🏿)|👴(🏻|🏼|🏽|🏾|🏿)|👵(🏻|🏼|🏽|🏾|🏿)|🙍(🏻|🏼|🏽|🏾|🏿)|🙎(🏻|🏼|🏽|🏾|🏿)|🙅(🏻|🏼|🏽|🏾|🏿)|🙆(🏻|🏼|🏽|🏾|🏿)|💁(🏻|🏼|🏽|🏾|🏿)|🙋(🏻|🏼|🏽|🏾|🏿)|🧏(🏻|🏼|🏽|🏾|🏿)|🙇(🏻|🏼|🏽|🏾|🏿)|🤦(🏻|🏼|🏽|🏾|🏿)|🤷(🏻|🏼|🏽|🏾|🏿)|👮(🏻|🏼|🏽|🏾|🏿)|🕵(🏻|🏼|🏽|🏾|🏿)|💂(🏻|🏼|🏽|🏾|🏿)|🥷(🏻|🏼|🏽|🏾|🏿)|👷(🏻|🏼|🏽|🏾|🏿)|🫅(🏻|🏼|🏽|🏾|🏿)|🤴(🏻|🏼|🏽|🏾|🏿)|👸(🏻|🏼|🏽|🏾|🏿)|👳(🏻|🏼|🏽|🏾|🏿)|👲(🏻|🏼|🏽|🏾|🏿)|🧕(🏻|🏼|🏽|🏾|🏿)|🤵(🏻|🏼|🏽|🏾|🏿)|👰(🏻|🏼|🏽|🏾|🏿)|🤰(🏻|🏼|🏽|🏾|🏿)|🫃(🏻|🏼|🏽|🏾|🏿)|🫄(🏻|🏼|🏽|🏾|🏿)|🤱(🏻|🏼|🏽|🏾|🏿)|👼(🏻|🏼|🏽|🏾|🏿)|🎅(🏻|🏼|🏽|🏾|🏿)|🤶(🏻|🏼|🏽|🏾|🏿)|🦸(🏻|🏼|🏽|🏾|🏿)|🦹(🏻|🏼|🏽|🏾|🏿)|🧙(🏻|🏼|🏽|🏾|🏿)|🧚(🏻|🏼|🏽|🏾|🏿)|🧛(🏻|🏼|🏽|🏾|🏿)|🧜(🏻|🏼|🏽|🏾|🏿)|🧝(🏻|🏼|🏽|🏾|🏿)|💆(🏻|🏼|🏽|🏾|🏿)|💇(🏻|🏼|🏽|🏾|🏿)|🚶(🏻|🏼|🏽|🏾|🏿)|🧍(🏻|🏼|🏽|🏾|🏿)|🧎(🏻|🏼|🏽|🏾|🏿)|🏃(🏻|🏼|🏽|🏾|🏿)|💃(🏻|🏼|🏽|🏾|🏿)|🕺(🏻|🏼|🏽|🏾|🏿)|🕴(🏻|🏼|🏽|🏾|🏿)|🧖(🏻|🏼|🏽|🏾|🏿)|🧗(🏻|🏼|🏽|🏾|🏿)|🏇(🏻|🏼|🏽|🏾|🏿)|🏂(🏻|🏼|🏽|🏾|🏿)|🏌(🏻|🏼|🏽|🏾|🏿)|🏄(🏻|🏼|🏽|🏾|🏿)|🚣(🏻|🏼|🏽|🏾|🏿)|🏊(🏻|🏼|🏽|🏾|🏿)|🏋(🏻|🏼|🏽|🏾|🏿)|🚴(🏻|🏼|🏽|🏾|🏿)|🚵(🏻|🏼|🏽|🏾|🏿)|🤸(🏻|🏼|🏽|🏾|🏿)|🤽(🏻|🏼|🏽|🏾|🏿)|🤾(🏻|🏼|🏽|🏾|🏿)|🤹(🏻|🏼|🏽|🏾|🏿)|🧘(🏻|🏼|🏽|🏾|🏿)|🛀(🏻|🏼|🏽|🏾|🏿)|🛌(🏻|🏼|🏽|🏾|🏿)|👭(🏻|🏼|🏽|🏾|🏿)|👫(🏻|🏼|🏽|🏾|🏿)|👬(🏻|🏼|🏽|🏾|🏿)|💏(🏻|🏼|🏽|🏾|🏿)|💑(🏻|🏼|🏽|🏾|🏿)|✋(🏻|🏼|🏽|🏾|🏿)|✌(🏻|🏼|🏽|🏾|🏿)|☝(🏻|🏼|🏽|🏾|🏿)|✊(🏻|🏼|🏽|🏾|🏿)|✍(🏻|🏼|🏽|🏾|🏿)|⛹(🏻|🏼|🏽|🏾|🏿)|👨‍(🦰|🦱|🦳|🦲)|👩‍(🦰|🦱|🦳|🦲)|🧑‍(🦰|🦱|🦳|🦲)|(🏻|🏼|🏽|🏾|🏿)|🏴󠁧󠁢󠁥󠁮󠁧󠁿|🏴󠁧󠁢󠁳󠁣󠁴󠁿|🏴󠁧󠁢󠁷󠁬󠁳󠁿|(🦰|🦱|🦳|🦲)|👩‍❤️?‍💋‍👨|👨‍❤️?‍💋‍👨|👩‍❤️?‍💋‍👩|👩‍❤‍💋‍👨|👨‍❤‍💋‍👨|👩‍❤‍💋‍👩|🧑‍🤝‍🧑|👩‍❤️?‍👨|👨‍❤️?‍👨|👩‍❤️?‍👩|👁️?‍🗨️?|👩‍❤‍👨|👨‍❤‍👨|👩‍❤‍👩|😶‍🌫️?|👁‍🗨️?|👁️?‍🗨|🕵️?‍♂️?|🕵️?‍♀️?|🏌️?‍♂️?|🏌️?‍♀️?|🏋️?‍♂️?|🏋️?‍♀️?|🏳️?‍🌈|🏳️?‍⚧️?|😶‍🌫|😮‍💨|😵‍💫|❤️?‍🔥|❤️?‍🩹|👁‍🗨|🧔‍♂️?|🧔‍♀️?|👱‍♀️?|👱‍♂️?|🙍‍♂️?|🙍‍♀️?|🙎‍♂️?|🙎‍♀️?|🙅‍♂️?|🙅‍♀️?|🙆‍♂️?|🙆‍♀️?|💁‍♂️?|💁‍♀️?|🙋‍♂️?|🙋‍♀️?|🧏‍♂️?|🧏‍♀️?|🙇‍♂️?|🙇‍♀️?|🤦‍♂️?|🤦‍♀️?|🤷‍♂️?|🤷‍♀️?|🧑‍⚕️?|👨‍⚕️?|👩‍⚕️?|🧑‍🎓|👨‍🎓|👩‍🎓|🧑‍🏫|👨‍🏫|👩‍🏫|🧑‍⚖️?|👨‍⚖️?|👩‍⚖️?|🧑‍🌾|👨‍🌾|👩‍🌾|🧑‍🍳|👨‍🍳|👩‍🍳|🧑‍🔧|👨‍🔧|👩‍🔧|🧑‍🏭|👨‍🏭|👩‍🏭|🧑‍💼|👨‍💼|👩‍💼|🧑‍🔬|👨‍🔬|👩‍🔬|🧑‍💻|👨‍💻|👩‍💻|🧑‍🎤|👨‍🎤|👩‍🎤|🧑‍🎨|👨‍🎨|👩‍🎨|🧑‍✈️?|👨‍✈️?|👩‍✈️?|🧑‍🚀|👨‍🚀|👩‍🚀|🧑‍🚒|👨‍🚒|👩‍🚒|👮‍♂️?|👮‍♀️?|🕵‍♂️?|🕵️?‍♂|🕵‍♀️?|🕵️?‍♀|💂‍♂️?|💂‍♀️?|👷‍♂️?|👷‍♀️?|👳‍♂️?|👳‍♀️?|🤵‍♂️?|🤵‍♀️?|👰‍♂️?|👰‍♀️?|👩‍🍼|👨‍🍼|🧑‍🍼|🧑‍🎄|🦸‍♂️?|🦸‍♀️?|🦹‍♂️?|🦹‍♀️?|🧙‍♂️?|🧙‍♀️?|🧚‍♂️?|🧚‍♀️?|🧛‍♂️?|🧛‍♀️?|🧜‍♂️?|🧜‍♀️?|🧝‍♂️?|🧝‍♀️?|🧞‍♂️?|🧞‍♀️?|🧟‍♂️?|🧟‍♀️?|💆‍♂️?|💆‍♀️?|💇‍♂️?|💇‍♀️?|🚶‍♂️?|🚶‍♀️?|🧍‍♂️?|🧍‍♀️?|🧎‍♂️?|🧎‍♀️?|🧑‍🦯|👨‍🦯|👩‍🦯|🧑‍🦼|👨‍🦼|👩‍🦼|🧑‍🦽|👨‍🦽|👩‍🦽|🏃‍♂️?|🏃‍♀️?|👯‍♂️?|👯‍♀️?|🧖‍♂️?|🧖‍♀️?|🧗‍♂️?|🧗‍♀️?|🏌‍♂️?|🏌️?‍♂|🏌‍♀️?|🏌️?‍♀|🏄‍♂️?|🏄‍♀️?|🚣‍♂️?|🚣‍♀️?|🏊‍♂️?|🏊‍♀️?|⛹️?‍♂️?|⛹️?‍♀️?|🏋‍♂️?|🏋️?‍♂|🏋‍♀️?|🏋️?‍♀|🚴‍♂️?|🚴‍♀️?|🚵‍♂️?|🚵‍♀️?|🤸‍♂️?|🤸‍♀️?|🤼‍♂️?|🤼‍♀️?|🤽‍♂️?|🤽‍♀️?|🤾‍♂️?|🤾‍♀️?|🤹‍♂️?|🤹‍♀️?|🧘‍♂️?|🧘‍♀️?|🐕‍🦺|🐻‍❄️?|🏳‍🌈|🏳‍⚧️?|🏳️?‍⚧|🏴‍☠️?|❤‍🔥|❤‍🩹|🧔‍♂|🧔‍♀|👱‍♀|👱‍♂|🙍‍♂|🙍‍♀|🙎‍♂|🙎‍♀|🙅‍♂|🙅‍♀|🙆‍♂|🙆‍♀|💁‍♂|💁‍♀|🙋‍♂|🙋‍♀|🧏‍♂|🧏‍♀|🙇‍♂|🙇‍♀|🤦‍♂|🤦‍♀|🤷‍♂|🤷‍♀|🧑‍⚕|👨‍⚕|👩‍⚕|🧑‍⚖|👨‍⚖|👩‍⚖|🧑‍✈|👨‍✈|👩‍✈|👮‍♂|👮‍♀|🕵‍♂|🕵‍♀|💂‍♂|💂‍♀|👷‍♂|👷‍♀|👳‍♂|👳‍♀|🤵‍♂|🤵‍♀|👰‍♂|👰‍♀|🦸‍♂|🦸‍♀|🦹‍♂|🦹‍♀|🧙‍♂|🧙‍♀|🧚‍♂|🧚‍♀|🧛‍♂|🧛‍♀|🧜‍♂|🧜‍♀|🧝‍♂|🧝‍♀|🧞‍♂|🧞‍♀|🧟‍♂|🧟‍♀|💆‍♂|💆‍♀|💇‍♂|💇‍♀|🚶‍♂|🚶‍♀|🧍‍♂|🧍‍♀|🧎‍♂|🧎‍♀|🏃‍♂|🏃‍♀|👯‍♂|👯‍♀|🧖‍♂|🧖‍♀|🧗‍♂|🧗‍♀|🏌‍♂|🏌‍♀|🏄‍♂|🏄‍♀|🚣‍♂|🚣‍♀|🏊‍♂|🏊‍♀|⛹‍♂️?|⛹️?‍♂|⛹‍♀️?|⛹️?‍♀|🏋‍♂|🏋‍♀|🚴‍♂|🚴‍♀|🚵‍♂|🚵‍♀|🤸‍♂|🤸‍♀|🤼‍♂|🤼‍♀|🤽‍♂|🤽‍♀|🤾‍♂|🤾‍♀|🤹‍♂|🤹‍♀|🧘‍♂|🧘‍♀|🐈‍⬛|🐻‍❄|🐦‍⬛|🏳‍⚧|🏴‍☠|🇦🇨|🇦🇩|🇦🇪|🇦🇫|🇦🇬|🇦🇮|🇦🇱|🇦🇲|🇦🇴|🇦🇶|🇦🇷|🇦🇸|🇦🇹|🇦🇺|🇦🇼|🇦🇽|🇦🇿|🇧🇦|🇧🇧|🇧🇩|🇧🇪|🇧🇫|🇧🇬|🇧🇭|🇧🇮|🇧🇯|🇧🇱|🇧🇲|🇧🇳|🇧🇴|🇧🇶|🇧🇷|🇧🇸|🇧🇹|🇧🇻|🇧🇼|🇧🇾|🇧🇿|🇨🇦|🇨🇨|🇨🇩|🇨🇫|🇨🇬|🇨🇭|🇨🇮|🇨🇰|🇨🇱|🇨🇲|🇨🇳|🇨🇴|🇨🇵|🇨🇷|🇨🇺|🇨🇻|🇨🇼|🇨🇽|🇨🇾|🇨🇿|🇩🇪|🇩🇬|🇩🇯|🇩🇰|🇩🇲|🇩🇴|🇩🇿|🇪🇦|🇪🇨|🇪🇪|🇪🇬|🇪🇭|🇪🇷|🇪🇸|🇪🇹|🇪🇺|🇫🇮|🇫🇯|🇫🇰|🇫🇲|🇫🇴|🇫🇷|🇬🇦|🇬🇧|🇬🇩|🇬🇪|🇬🇫|🇬🇬|🇬🇭|🇬🇮|🇬🇱|🇬🇲|🇬🇳|🇬🇵|🇬🇶|🇬🇷|🇬🇸|🇬🇹|🇬🇺|🇬🇼|🇬🇾|🇭🇰|🇭🇲|🇭🇳|🇭🇷|🇭🇹|🇭🇺|🇮🇨|🇮🇩|🇮🇪|🇮🇱|🇮🇲|🇮🇳|🇮🇴|🇮🇶|🇮🇷|🇮🇸|🇮🇹|🇯🇪|🇯🇲|🇯🇴|🇯🇵|🇰🇪|🇰🇬|🇰🇭|🇰🇮|🇰🇲|🇰🇳|🇰🇵|🇰🇷|🇰🇼|🇰🇾|🇰🇿|🇱🇦|🇱🇧|🇱🇨|🇱🇮|🇱🇰|🇱🇷|🇱🇸|🇱🇹|🇱🇺|🇱🇻|🇱🇾|🇲🇦|🇲🇨|🇲🇩|🇲🇪|🇲🇫|🇲🇬|🇲🇭|🇲🇰|🇲🇱|🇲🇲|🇲🇳|🇲🇴|🇲🇵|🇲🇶|🇲🇷|🇲🇸|🇲🇹|🇲🇺|🇲🇻|🇲🇼|🇲🇽|🇲🇾|🇲🇿|🇳🇦|🇳🇨|🇳🇪|🇳🇫|🇳🇬|🇳🇮|🇳🇱|🇳🇴|🇳🇵|🇳🇷|🇳🇺|🇳🇿|🇴🇲|🇵🇦|🇵🇪|🇵🇫|🇵🇬|🇵🇭|🇵🇰|🇵🇱|🇵🇲|🇵🇳|🇵🇷|🇵🇸|🇵🇹|🇵🇼|🇵🇾|🇶🇦|🇷🇪|🇷🇴|🇷🇸|🇷🇺|🇷🇼|🇸🇦|🇸🇧|🇸🇨|🇸🇩|🇸🇪|🇸🇬|🇸🇭|🇸🇮|🇸🇯|🇸🇰|🇸🇱|🇸🇲|🇸🇳|🇸🇴|🇸🇷|🇸🇸|🇸🇹|🇸🇻|🇸🇽|🇸🇾|🇸🇿|🇹🇦|🇹🇨|🇹🇩|🇹🇫|🇹🇬|🇹🇭|🇹🇯|🇹🇰|🇹🇱|🇹🇲|🇹🇳|🇹🇴|🇹🇷|🇹🇹|🇹🇻|🇹🇼|🇹🇿|🇺🇦|🇺🇬|🇺🇲|🇺🇳|🇺🇸|🇺🇾|🇺🇿|🇻🇦|🇻🇨|🇻🇪|🇻🇬|🇻🇮|🇻🇳|🇻🇺|🇼🇫|🇼🇸|🇽🇰|🇾🇪|🇾🇹|🇿🇦|🇿🇲|🇿🇼|🕳️?|🗨️?|🗯️?|🖐️?|👁️?|🕵️?|🕴️?|🏌️?|⛹‍♂|⛹‍♀|🏋️?|🗣️?|🐿️?|🕊️?|🕷️?|🕸️?|🏵️?|🌶️?|🍽️?|🗺️?|🏔️?|🏕️?|🏖️?|🏜️?|🏝️?|🏞️?|🏟️?|🏛️?|🏗️?|🏘️?|🏚️?|🏙️?|🏎️?|🏍️?|🛣️?|🛤️?|🛢️?|🛳️?|🛥️?|🛩️?|🛰️?|🛎️?|🕰️?|🌡️?|🌤️?|🌥️?|🌦️?|🌧️?|🌨️?|🌩️?|🌪️?|🌫️?|🌬️?|🎗️?|🎟️?|🎖️?|🕹️?|🖼️?|🕶️?|🛍️?|🎙️?|🎚️?|🎛️?|🖥️?|🖨️?|🖱️?|🖲️?|🎞️?|📽️?|🕯️?|🗞️?|🏷️?|🗳️?|🖋️?|🖊️?|🖌️?|🖍️?|🗂️?|🗒️?|🗓️?|🖇️?|🗃️?|🗄️?|🗑️?|🗝️?|🛠️?|🗡️?|🛡️?|🗜️?|🛏️?|🛋️?|🕉️?|#️?⃣|[*]️?⃣|0️?⃣|1️?⃣|2️?⃣|3️?⃣|4️?⃣|5️?⃣|6️?⃣|7️?⃣|8️?⃣|9️?⃣|🅰️?|🅱️?|🅾️?|🅿️?|🈂️?|🈷️?|🏳️?|😀|😃|😄|😁|😆|😅|🤣|😂|🙂|🙃|🫠|😉|😊|😇|🥰|😍|🤩|😘|😗|☺️?|😚|😙|🥲|😋|😛|😜|🤪|😝|🤑|🤗|🤭|🫢|🫣|🤫|🤔|🫡|🤐|🤨|😐|😑|😶|🫥|😏|😒|🙄|😬|🤥|🫨|😌|😔|😪|🤤|😴|😷|🤒|🤕|🤢|🤮|🤧|🥵|🥶|🥴|😵|🤯|🤠|🥳|🥸|😎|🤓|🧐|😕|🫤|😟|🙁|☹️?|😮|😯|😲|😳|🥺|🥹|😦|😧|😨|😰|😥|😢|😭|😱|😖|😣|😞|😓|😩|😫|🥱|😤|😡|😠|🤬|😈|👿|💀|☠️?|💩|🤡|👹|👺|👻|👽|👾|🤖|😺|😸|😹|😻|😼|😽|🙀|😿|😾|🙈|🙉|🙊|💌|💘|💝|💖|💗|💓|💞|💕|💟|❣️?|💔|❤️?|🩷|🧡|💛|💚|💙|🩵|💜|🤎|🖤|🩶|🤍|💋|💯|💢|💥|💫|💦|💨|🕳|💬|🗨|🗯|💭|💤|👋|🤚|🖐|🖖|🫱|🫲|🫳|🫴|🫷|🫸|👌|🤌|🤏|✌️?|🤞|🫰|🤟|🤘|🤙|👈|👉|👆|🖕|👇|☝️?|🫵|👍|👎|👊|🤛|🤜|👏|🙌|🫶|👐|🤲|🤝|🙏|✍️?|💅|🤳|💪|🦾|🦿|🦵|🦶|👂|🦻|👃|🧠|🫀|🫁|🦷|🦴|👀|👁|👅|👄|🫦|👶|🧒|👦|👧|🧑|👱|👨|🧔|👩|🧓|👴|👵|🙍|🙎|🙅|🙆|💁|🙋|🧏|🙇|🤦|🤷|👮|🕵|💂|🥷|👷|🫅|🤴|👸|👳|👲|🧕|🤵|👰|🤰|🫃|🫄|🤱|👼|🎅|🤶|🦸|🦹|🧙|🧚|🧛|🧜|🧝|🧞|🧟|🧌|💆|💇|🚶|🧍|🧎|🏃|💃|🕺|🕴|👯|🧖|🧗|🤺|🏇|⛷️?|🏂|🏌|🏄|🚣|🏊|⛹️?|🏋|🚴|🚵|🤸|🤼|🤽|🤾|🤹|🧘|🛀|🛌|👭|👫|👬|💏|💑|👪|🗣|👤|👥|🫂|👣|🐵|🐒|🦍|🦧|🐶|🐕|🦮|🐩|🐺|🦊|🦝|🐱|🐈|🦁|🐯|🐅|🐆|🐴|🫎|🫏|🐎|🦄|🦓|🦌|🦬|🐮|🐂|🐃|🐄|🐷|🐖|🐗|🐽|🐏|🐑|🐐|🐪|🐫|🦙|🦒|🐘|🦣|🦏|🦛|🐭|🐁|🐀|🐹|🐰|🐇|🐿|🦫|🦔|🦇|🐻|🐨|🐼|🦥|🦦|🦨|🦘|🦡|🐾|🦃|🐔|🐓|🐣|🐤|🐥|🐦|🐧|🕊|🦅|🦆|🦢|🦉|🦤|🪶|🦩|🦚|🦜|🪽|🪿|🐸|🐊|🐢|🦎|🐍|🐲|🐉|🦕|🦖|🐳|🐋|🐬|🦭|🐟|🐠|🐡|🦈|🐙|🐚|🪸|🪼|🐌|🦋|🐛|🐜|🐝|🪲|🐞|🦗|🪳|🕷|🕸|🦂|🦟|🪰|🪱|🦠|💐|🌸|💮|🪷|🏵|🌹|🥀|🌺|🌻|🌼|🌷|🪻|🌱|🪴|🌲|🌳|🌴|🌵|🌾|🌿|☘️?|🍀|🍁|🍂|🍃|🪹|🪺|🍄|🍇|🍈|🍉|🍊|🍋|🍌|🍍|🥭|🍎|🍏|🍐|🍑|🍒|🍓|🫐|🥝|🍅|🫒|🥥|🥑|🍆|🥔|🥕|🌽|🌶|🫑|🥒|🥬|🥦|🧄|🧅|🥜|🫘|🌰|🫚|🫛|🍞|🥐|🥖|🫓|🥨|🥯|🥞|🧇|🧀|🍖|🍗|🥩|🥓|🍔|🍟|🍕|🌭|🥪|🌮|🌯|🫔|🥙|🧆|🥚|🍳|🥘|🍲|🫕|🥣|🥗|🍿|🧈|🧂|🥫|🍱|🍘|🍙|🍚|🍛|🍜|🍝|🍠|🍢|🍣|🍤|🍥|🥮|🍡|🥟|🥠|🥡|🦀|🦞|🦐|🦑|🦪|🍦|🍧|🍨|🍩|🍪|🎂|🍰|🧁|🥧|🍫|🍬|🍭|🍮|🍯|🍼|🥛|🫖|🍵|🍶|🍾|🍷|🍸|🍹|🍺|🍻|🥂|🥃|🫗|🥤|🧋|🧃|🧉|🧊|🥢|🍽|🍴|🥄|🔪|🫙|🏺|🌍|🌎|🌏|🌐|🗺|🗾|🧭|🏔|⛰️?|🌋|🗻|🏕|🏖|🏜|🏝|🏞|🏟|🏛|🏗|🧱|🪨|🪵|🛖|🏘|🏚|🏠|🏡|🏢|🏣|🏤|🏥|🏦|🏨|🏩|🏪|🏫|🏬|🏭|🏯|🏰|💒|🗼|🗽|🕌|🛕|🕍|⛩️?|🕋|🌁|🌃|🏙|🌄|🌅|🌆|🌇|🌉|♨️?|🎠|🛝|🎡|🎢|💈|🎪|🚂|🚃|🚄|🚅|🚆|🚇|🚈|🚉|🚊|🚝|🚞|🚋|🚌|🚍|🚎|🚐|🚑|🚒|🚓|🚔|🚕|🚖|🚗|🚘|🚙|🛻|🚚|🚛|🚜|🏎|🏍|🛵|🦽|🦼|🛺|🚲|🛴|🛹|🛼|🚏|🛣|🛤|🛢|🛞|🚨|🚥|🚦|🛑|🚧|🛟|🛶|🚤|🛳|⛴️?|🛥|🚢|✈️?|🛩|🛫|🛬|🪂|💺|🚁|🚟|🚠|🚡|🛰|🚀|🛸|🛎|🧳|⏱️?|⏲️?|🕰|🕛|🕧|🕐|🕜|🕑|🕝|🕒|🕞|🕓|🕟|🕔|🕠|🕕|🕡|🕖|🕢|🕗|🕣|🕘|🕤|🕙|🕥|🕚|🕦|🌑|🌒|🌓|🌔|🌕|🌖|🌗|🌘|🌙|🌚|🌛|🌜|🌡|☀️?|🌝|🌞|🪐|🌟|🌠|🌌|☁️?|⛈️?|🌤|🌥|🌦|🌧|🌨|🌩|🌪|🌫|🌬|🌀|🌈|🌂|☂️?|⛱️?|❄️?|☃️?|☄️?|🔥|💧|🌊|🎃|🎄|🎆|🎇|🧨|🎈|🎉|🎊|🎋|🎍|🎎|🎏|🎐|🎑|🧧|🎀|🎁|🎗|🎟|🎫|🎖|🏆|🏅|🥇|🥈|🥉|🥎|🏀|🏐|🏈|🏉|🎾|🥏|🎳|🏏|🏑|🏒|🥍|🏓|🏸|🥊|🥋|🥅|⛸️?|🎣|🤿|🎽|🎿|🛷|🥌|🎯|🪀|🪁|🔫|🎱|🔮|🪄|🎮|🕹|🎰|🎲|🧩|🧸|🪅|🪩|🪆|♠️?|♥️?|♦️?|♣️?|♟️?|🃏|🀄|🎴|🎭|🖼|🎨|🧵|🪡|🧶|🪢|👓|🕶|🥽|🥼|🦺|👔|👕|👖|🧣|🧤|🧥|🧦|👗|👘|🥻|🩱|🩲|🩳|👙|👚|🪭|👛|👜|👝|🛍|🎒|🩴|👞|👟|🥾|🥿|👠|👡|🩰|👢|🪮|👑|👒|🎩|🎓|🧢|🪖|⛑️?|📿|💄|💍|💎|🔇|🔈|🔉|🔊|📢|📣|📯|🔔|🔕|🎼|🎵|🎶|🎙|🎚|🎛|🎤|🎧|📻|🎷|🪗|🎸|🎹|🎺|🎻|🪕|🥁|🪘|🪇|🪈|📱|📲|☎️?|📞|📟|📠|🔋|🪫|🔌|💻|🖥|🖨|⌨️?|🖱|🖲|💽|💾|💿|📀|🧮|🎥|🎞|📽|🎬|📺|📷|📸|📹|📼|🔍|🔎|🕯|💡|🔦|🏮|🪔|📔|📕|📖|📗|📘|📙|📚|📓|📒|📃|📜|📄|📰|🗞|📑|🔖|🏷|💰|🪙|💴|💵|💶|💷|💸|💳|🧾|💹|✉️?|📧|📨|📩|📤|📥|📦|📫|📪|📬|📭|📮|🗳|✏️?|✒️?|🖋|🖊|🖌|🖍|📝|💼|📁|📂|🗂|📅|📆|🗒|🗓|📇|📈|📉|📊|📋|📌|📍|📎|🖇|📏|📐|✂️?|🗃|🗄|🗑|🔒|🔓|🔏|🔐|🔑|🗝|🔨|🪓|⛏️?|⚒️?|🛠|🗡|⚔️?|💣|🪃|🏹|🛡|🪚|🔧|🪛|🔩|⚙️?|🗜|⚖️?|🦯|🔗|⛓️?|🪝|🧰|🧲|🪜|⚗️?|🧪|🧫|🧬|🔬|🔭|📡|💉|🩸|💊|🩹|🩼|🩺|🩻|🚪|🛗|🪞|🪟|🛏|🛋|🪑|🚽|🪠|🚿|🛁|🪤|🪒|🧴|🧷|🧹|🧺|🧻|🪣|🧼|🫧|🪥|🧽|🧯|🛒|🚬|⚰️?|🪦|⚱️?|🧿|🪬|🗿|🪧|🪪|🏧|🚮|🚰|🚹|🚺|🚻|🚼|🚾|🛂|🛃|🛄|🛅|⚠️?|🚸|🚫|🚳|🚭|🚯|🚱|🚷|📵|🔞|☢️?|☣️?|⬆️?|↗️?|➡️?|↘️?|⬇️?|↙️?|⬅️?|↖️?|↕️?|↔️?|↩️?|↪️?|⤴️?|⤵️?|🔃|🔄|🔙|🔚|🔛|🔜|🔝|🛐|⚛️?|🕉|✡️?|☸️?|☯️?|✝️?|☦️?|☪️?|☮️?|🕎|🔯|🪯|🔀|🔁|🔂|▶️?|⏭️?|⏯️?|◀️?|⏮️?|🔼|🔽|⏸️?|⏹️?|⏺️?|⏏️?|🎦|🔅|🔆|📶|🛜|📳|📴|♀️?|♂️?|⚧️?|✖️?|🟰|♾️?|‼️?|⁉️?|〰️?|💱|💲|⚕️?|♻️?|⚜️?|🔱|📛|🔰|☑️?|✔️?|〽️?|✳️?|✴️?|❇️?|©️?|®️?|™️?|#⃣|[*]⃣|0⃣|1⃣|2⃣|3⃣|4⃣|5⃣|6⃣|7⃣|8⃣|9⃣|🔟|🔠|🔡|🔢|🔣|🔤|🅰|🆎|🅱|🆑|🆒|🆓|ℹ️?|🆔|Ⓜ️?|🆕|🆖|🅾|🆗|🅿|🆘|🆙|🆚|🈁|🈂|🈷|🈶|🈯|🉐|🈹|🈚|🈲|🉑|🈸|🈴|🈳|㊗️?|㊙️?|🈺|🈵|🔴|🟠|🟡|🟢|🔵|🟣|🟤|🟥|🟧|🟨|🟩|🟦|🟪|🟫|◼️?|◻️?|▪️?|▫️?|🔶|🔷|🔸|🔹|🔺|🔻|💠|🔘|🔳|🔲|🏁|🚩|🎌|🏴|🏳|☺|☹|☠|❣|❤|✋|✌|☝|✊|✍|⛷|⛹|☘|☕|⛰|⛪|⛩|⛲|⛺|♨|⛽|⚓|⛵|⛴|✈|⌛|⏳|⌚|⏰|⏱|⏲|☀|⭐|☁|⛅|⛈|☂|☔|⛱|⚡|❄|☃|⛄|☄|✨|⚽|⚾|⛳|⛸|♠|♥|♦|♣|♟|⛑|☎|⌨|✉|✏|✒|✂|⛏|⚒|⚔|⚙|⚖|⛓|⚗|⚰|⚱|♿|⚠|⛔|☢|☣|⬆|↗|➡|↘|⬇|↙|⬅|↖|↕|↔|↩|↪|⤴|⤵|⚛|✡|☸|☯|✝|☦|☪|☮|♈|♉|♊|♋|♌|♍|♎|♏|♐|♑|♒|♓|⛎|▶|⏩|⏭|⏯|◀|⏪|⏮|⏫|⏬|⏸|⏹|⏺|⏏|♀|♂|⚧|✖|➕|➖|➗|♾|‼|⁉|❓|❔|❕|❗|〰|⚕|♻|⚜|⭕|✅|☑|✔|❌|❎|➰|➿|〽|✳|✴|❇|©|®|™|ℹ|Ⓜ|㊗|㊙|⚫|⚪|⬛|⬜|◼|◻|◾|◽|▪|▫)''';

  ///
  static final RegExp _emojiMatchOneRegex = RegExp(emojiPattern);

  ///
  static bool isEmoji(String character, [bool full = true]) {
    if (full) {
      // PORT NOTE: 上游 StringHelper.cs:543 的形参是 `char` 值类型，
      // `character.ToString()` 恒为长度 1 的串，不存在"空串"这种输入；
      // Dart 契约 3.6 用 `String` 承载，空串等价于"没有代码单元"→ 匹配不上 → false。
      return _emojiMatchOneRegex.hasMatch(character);
    }
    if (character.isEmpty) return false;
    // 上游 char 是 16 位，0x1F600 / 0x1F300 / 0x1F680 三个区间对非 BMP 字符恒假；
    // Dart 侧取第 1 个 UTF-16 代码单元（= 高位代理）复刻同一结果。
    final value = character.codeUnitAt(0);
    return (value >= 0x1F600 && value <= 0x1F64F) || // Emoticons
        (value >= 0x1F300 &&
            value <= 0x1F5FF) || // Misc Symbols and Pictographs
        (value >= 0x1F680 && value <= 0x1F6FF) || // Transport and Map Symbols
        (value >= 0x2600 && value <= 0x26FF) || // Misc Symbols
        (value >= 0x2700 && value <= 0x27BF) || // Dingbats
        (value == 0x2B50) || // Star emoji
        (value == 0x2B55); // Another star emoji
  }

  static bool containsEmoji(String str, [bool full = true]) {
    if (str.isEmpty) return false;

    // （`InitiateEmojiRegex(); return EmojiMatchOneRegex.IsMatch(str);`），
    return _emojiMatchOneRegex.hasMatch(str);
  }

  // #endregion
}

//   new Regex("[`~!@#$%^&*()+=|{}':;',\\[\\].<>/?~！@#￥%……&*（）——+|{}《》【】‘；：\"”“’。，、？]")
final RegExp _symbolRegex = RegExp(
  "[`~!@#\$%^&*()+=|{}':;',\\[\\].<>/?~！@#￥%……&*（）——+|{}《》【】‘；：\"”“’。，、？]",
);

/// C# `char.IsControl(char)`：C0（U+0000–U+001F）、DEL（U+007F）、C1（U+0080–U+009F）。
///
/// 注意 U+0009 (TAB) / U+000A (LF) / U+000D (CR) **落在 C0 里**，.NET 的
/// `char.IsControl` 对它们返回 true，所以上游 `StringHelper.cs:330` 的
/// `RemoveControlChars("a\nb")` 结果是 `"ab"`——换行会被吃掉。这看着反直觉，
/// 但它就是上游的行为，本移植照抄，不"顺手修正"。
///
/// （上游全仓库只有 `RemoveControlChars` 的定义那一处命中，没有任何调用方，
/// 所以这个行为不会影响解析/优化路径。）
bool _isControl(int cu) =>
    (cu >= 0x0000 && cu <= 0x001F) || (cu >= 0x007F && cu <= 0x009F);

///
/// C# `int.Parse(string)`（`NumberStyles.Integer` = AllowLeadingWhite | AllowTrailingWhite
/// | AllowLeadingSign）：允许首尾空白、可选前导 `+`/`-`、其余必须是十进制数字；
/// 超出 Int32 范围抛 OverflowException，`null`/空串抛 FormatException。
/// 上游 `GetMillisecondsFromString` 的 `catch { }`（StringHelper.cs:228）把两者都吞成 null。
int _mp(String part) {
  final m = RegExp(r'^([+-]?)([0-9]+)$').firstMatch(part.trim());
  if (m == null) {
    throw FormatException('int.Parse failed: "$part"');
  }
  final digits = int.parse(m.group(2)!);
  final sign = m.group(1) == '-' ? -1 : 1;
  final value = sign * digits;
  // PORT NOTE: Dart 的 int 是任意精度，上游 int.Parse 越界会抛 OverflowException；
  // 这里显式判 Int32 区间，让越界输入同样落到上游 `catch { }` → null 的结果。
  if (value > 2147483647 || value < -2147483648) {
    throw FormatException('int.Parse overflow: "$part"');
  }
  return value;
}

///
/// C# `\p{IsCJKUnifiedIdeographs}`（StringHelper.cs:404 / 415 / 426）。
bool _isCJKUnifiedIdeographs(int cu) => cu >= 0x4E00 && cu <= 0x9FFF;

///
/// C# `string.Format("{0:D2}", v)`。
String _d(int value, int digits) => value.toString().padLeft(digits, '0');
