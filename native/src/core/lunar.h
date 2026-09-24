// 农历换算与二十四节气（适用 1900-2100）。
//
// 从 Flutter 版 lib/widgets/builtin/lunar.dart 逐行移植（那又是从
// assets/plugins/calendar/lunar.js 移植的），算法与数据表一字不差——
// 两个版本算出来必须是同一天，否则日历对不上没法并排比对。
//
// lunarInfo 每年一个数：低 4 位是闰月月份（0 表示无闰月），第 4..16 位
// 从高到低表示每个月是大月(30)还是小月(29)，第 16 位表示闰月大小。
// 节气用"通用寿星公式"的简化版：以 1900-01-06 02:05(UTC) 为基准，
// 加上回归年长度乘年差，再加该节气的分钟偏移。
#ifndef GLANCE_NATIVE_CORE_LUNAR_H_
#define GLANCE_NATIVE_CORE_LUNAR_H_

#include <string>

namespace glance {

struct LunarDate {
  int year = 1900;
  int month = 1;
  int day = 1;
  bool is_leap = false;
  std::wstring day_text;    // 初一 / 十五 / 廿三
  std::wstring month_text;  // 正月 / 闰二月
};

// 公历 → 农历。超出 1900-2100 返回 false。
bool SolarToLunar(int year, int month, int day, LunarDate* out);

// 公历某天若是节气返回节气名（小寒/立春/清明…），否则返回空串。
std::wstring TermOf(int year, int month, int day);

struct Festival {
  std::wstring name;
  bool statutory = false;  // 法定节假日（标红）
};

// 节日：公历固定日 + 农历固定日 + 除夕。不是节日返回 false。
bool FestivalOf(int year, int month, int day, const LunarDate& lunar,
                Festival* out);

// 农历某月天数（不含闰月）；闰月天数用 LeapMonthDays。
int LunarMonthDays(int lunar_year, int month);

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_LUNAR_H_
