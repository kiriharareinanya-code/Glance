/// 农历换算与二十四节气。适用 1900-2100。
///
/// 从 assets/plugins/calendar/lunar.js 逐行移植：
/// - lunarInfo 每年一个数：低 4 位是闰月月份（0 表示无闰月），
///   第 4..16 位从高到低表示每个月是大月(30)还是小月(29)，
///   第 16 位表示闰月是大月还是小月。
/// - 节气用"通用寿星公式"的简化版：以 1900-01-06 02:05 为基准，
///   加上回归年长度乘以年差，再加该节气的分钟偏移。
library;

class LunarDate {
  const LunarDate({
    required this.y,
    required this.m,
    required this.d,
    required this.isLeap,
    required this.dayText,
    required this.monthText,
  });
  final int y;
  final int m;
  final int d;
  final bool isLeap;
  final String dayText;
  final String monthText;
}

class Lunar {
  static const List<int> _lunarInfo = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
    0x09ad0, 0x055d2, 0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540,
    0x0d6a0, 0x0ada2, 0x095b0, 0x14977, 0x04970, 0x0a4b0, 0x0b4b5, 0x06a50,
    0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, 0x06566, 0x0d4a0,
    0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
    0x0a950, 0x0b557, 0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573,
    0x052b0, 0x0a9a8, 0x0e950, 0x06aa0, 0x0aea6, 0x0ab50, 0x04b60, 0x0aae4,
    0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, 0x096d0, 0x04dd5,
    0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
    0x0ab60, 0x09570, 0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58,
    0x055c0, 0x0ab60, 0x096d5, 0x092e0, 0x0c960, 0x0d954, 0x0d4a0, 0x0da50,
    0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, 0x0a950, 0x0b4a0,
    0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
    0x0ea65, 0x0d530, 0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0,
    0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, 0x0b5a0, 0x056d0, 0x055b2, 0x049b0,
    0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0, 0x14b63, 0x09370,
    0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
    0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0,
    0x0a6d0, 0x055d4, 0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50,
    0x055a0, 0x0aba4, 0x0a5b0, 0x052b0, 0x0b273, 0x06930, 0x07337, 0x06aa0,
    0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160, 0x0e968, 0x0d520,
    0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0, 0x0d150, 0x0f252,
    0x0d520,
  ];

  static int _yearDays(int y) {
    var sum = 348; // 12 个月 * 29 天
    for (var i = 0x8000; i > 0x8; i >>= 1) {
      sum += (_lunarInfo[y - 1900] & i) != 0 ? 1 : 0;
    }
    return sum + _leapDays(y);
  }

  static int _leapMonth(int y) => _lunarInfo[y - 1900] & 0xf;

  static int _leapDays(int y) {
    if (_leapMonth(y) != 0) {
      return (_lunarInfo[y - 1900] & 0x10000) != 0 ? 30 : 29;
    }
    return 0;
  }

  /// 农历 y 年 m 月的天数（不含闰月）
  static int _monthDays(int y, int m) =>
      (_lunarInfo[y - 1900] & (0x10000 >> m)) != 0 ? 30 : 29;

  static const _cnDay = ['初', '十', '廿', '三'];
  static const _cnNum = ['日', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  static const _cnMonth = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];

  static String _dayName(int d) {
    if (d == 10) return '初十';
    if (d == 20) return '二十';
    if (d == 30) return '三十';
    return _cnDay[d ~/ 10] + _cnNum[d % 10];
  }

  static String _monthName(int m, bool isLeap) =>
      '${isLeap ? '闰' : ''}${_cnMonth[m - 1]}月';

  /// 公历 -> 农历。与 1900-01-31（农历 1900 年正月初一）求天数差。
  static LunarDate? fromSolar(int year, int month, int day) {
    final base = DateTime.utc(1900, 1, 31);
    var offset =
        (DateTime.utc(year, month, day).difference(base).inDays);
    if (offset < 0) return null;

    var y = 1900;
    var temp = 0;
    for (; y < 2101 && offset > 0; y++) {
      temp = _yearDays(y);
      offset -= temp;
    }
    if (offset < 0) {
      offset += temp;
      y--;
    }

    final leap = _leapMonth(y);
    var isLeap = false;
    var m = 1;
    for (; m < 13 && offset > 0; m++) {
      if (leap > 0 && m == leap + 1 && !isLeap) {
        m--;
        isLeap = true;
        temp = _leapDays(y);
      } else {
        temp = _monthDays(y, m);
      }
      if (isLeap && m == leap + 1) isLeap = false;
      offset -= temp;
    }
    if (offset == 0 && leap > 0 && m == leap + 1) {
      if (isLeap) {
        isLeap = false;
      } else {
        isLeap = true;
        m--;
      }
    }
    if (offset < 0) {
      offset += temp;
      m--;
    }

    final d = offset + 1;
    return LunarDate(
      y: y,
      m: m,
      d: d,
      isLeap: isLeap,
      dayText: _dayName(d),
      monthText: _monthName(m, isLeap),
    );
  }

  // 24 节气：相对 1900-01-06 02:05 的分钟偏移
  static const List<int> _termMinutes = [
    0, 21208, 42467, 63836, 85337, 107014, 128867, 150921, 173149, 195551,
    218072, 240693, 263343, 285989, 308563, 331033, 353350, 375494, 397447,
    419210, 440795, 462224, 483532, 504758,
  ];
  static const List<String> termNames = [
    '小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
    '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑',
    '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
  ];

  /// 返回某年第 n 个节气所在的日（1-31）
  static int termDay(int year, int n) {
    final ms = 31556925974.7 * (year - 1900) + _termMinutes[n] * 60000;
    final d = DateTime.fromMillisecondsSinceEpoch(
        DateTime.utc(1900, 1, 6, 2, 5).millisecondsSinceEpoch + ms.round(),
        isUtc: true);
    return d.day;
  }

  /// 公历某天若是节气则返回名字，否则 null
  static String? termOf(int year, int month, int day) {
    final a = (month - 1) * 2;
    final b = a + 1;
    if (termDay(year, a) == day) return termNames[a];
    if (termDay(year, b) == day) return termNames[b];
    return null;
  }

  // 公历固定日期的节日
  static const Map<String, String> _solarFest = {
    '1-1': '元旦', '2-14': '情人节', '3-8': '妇女节', '3-12': '植树节',
    '4-1': '愚人节', '5-1': '劳动节', '5-4': '青年节', '6-1': '儿童节',
    '7-1': '建党节', '8-1': '建军节', '9-10': '教师节', '10-1': '国庆节',
    '12-24': '平安夜', '12-25': '圣诞节',
  };
  // 农历固定日期的节日
  static const Map<String, String> _lunarFest = {
    '1-1': '春节', '1-15': '元宵', '2-2': '龙抬头', '5-5': '端午',
    '7-7': '七夕', '7-15': '中元', '8-15': '中秋', '9-9': '重阳',
    '12-8': '腊八', '12-23': '小年',
  };
  // 法定节假日（用于标红），其余只是民俗节日
  static const Set<String> _statutory = {
    '元旦', '春节', '清明', '劳动节', '端午', '中秋', '国庆节',
  };

  /// 节日：{name, statutory} 或 null
  static ({String name, bool statutory})? festivalOf(
      int year, int month, int day, LunarDate? lunar) {
    final s = _solarFest['$month-$day'];
    if (s != null) return (name: s, statutory: _statutory.contains(s));
    if (lunar != null && !lunar.isLeap) {
      final l = _lunarFest['${lunar.m}-${lunar.d}'];
      if (l != null) return (name: l, statutory: _statutory.contains(l));
      // 除夕：农历腊月的最后一天
      if (lunar.m == 12 && lunar.d == _monthDays(lunar.y, 12)) {
        return (name: '除夕', statutory: true);
      }
    }
    return null;
  }

  // 干支纪年
  static const _gan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
  static const _zhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
  static const _zodiac = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];

  static String ganzhi(int lunarYear) {
    var i = (lunarYear - 4) % 60;
    if (i < 0) i += 60;
    return _gan[i % 10] + _zhi[i % 12];
  }

  static String zodiac(int lunarYear) {
    var i = (lunarYear - 4) % 12;
    if (i < 0) i += 12;
    return _zodiac[i];
  }

  /// 从某天往后找最近的节气，返回 {name, days}
  static ({String name, int days})? nextTerm(int year, int month, int day) {
    for (var i = 1; i <= 40; i++) {
      final d = DateTime(year, month, day + i);
      final t = termOf(d.year, d.month, d.day);
      if (t != null) return (name: t, days: i);
    }
    return null;
  }
}
