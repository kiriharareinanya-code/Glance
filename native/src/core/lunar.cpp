#include "core/lunar.h"

#include <cmath>
#include <map>
#include <string>

#include "core/date_util.h"

namespace glance {
namespace {

// 1900-2100 每年一条（与 lunar.dart 的 _lunarInfo 完全一致）
constexpr int kLunarInfo[] = {
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
};
constexpr int kLunarInfoCount = sizeof(kLunarInfo) / sizeof(kLunarInfo[0]);

int LeapMonth(int y) { return kLunarInfo[y - 1900] & 0xf; }

int LeapDays(int y) {
  if (LeapMonth(y) == 0) return 0;
  return (kLunarInfo[y - 1900] & 0x10000) != 0 ? 30 : 29;
}

int YearDays(int y) {
  int sum = 348;  // 12 个月 × 29 天
  for (int i = 0x8000; i > 0x8; i >>= 1) {
    if ((kLunarInfo[y - 1900] & i) != 0) ++sum;
  }
  return sum + LeapDays(y);
}

const wchar_t* kCnDay[] = {L"初", L"十", L"廿", L"三"};
const wchar_t* kCnNum[] = {L"日", L"一", L"二", L"三", L"四",
                           L"五", L"六", L"七", L"八", L"九", L"十"};
const wchar_t* kCnMonth[] = {L"正", L"二", L"三", L"四", L"五", L"六",
                             L"七", L"八", L"九", L"十", L"冬", L"腊"};

std::wstring DayName(int d) {
  if (d == 10) return L"初十";
  if (d == 20) return L"二十";
  if (d == 30) return L"三十";
  return std::wstring(kCnDay[d / 10]) + kCnNum[d % 10];
}

std::wstring MonthName(int m, bool is_leap) {
  std::wstring text;
  if (is_leap) text += L"闰";
  text += kCnMonth[m - 1];
  text += L"月";
  return text;
}

// ---- 公历日期运算在 core/date_util.h（两边共用）----

// 1900-01-31 是农历 1900 年正月初一
const int64_t kLunarEpochDays = DaysFromCivil(1900, 1, 31);

// 24 节气相对 1900-01-06 02:05 的分钟偏移
constexpr int kTermMinutes[] = {
    0,     21208, 42467, 63836, 85337, 107014, 128867, 150921, 173149, 195551,
    218072, 240693, 263343, 285989, 308563, 331033, 353350, 375494, 397447,
    419210, 440795, 462224, 483532, 504758,
};

}  // namespace

int LunarMonthDays(int lunar_year, int month) {
  if (lunar_year < 1900 || lunar_year > 2100) return 29;
  return (kLunarInfo[lunar_year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29;
}

bool SolarToLunar(int year, int month, int day, LunarDate* out) {
  if (year < 1900 || year > 2100 || out == nullptr) return false;

  int64_t offset = DaysFromCivil(year, month, day) - kLunarEpochDays;
  if (offset < 0) return false;

  int y = 1900;
  int temp = 0;
  for (; y < 2101 && offset > 0; ++y) {
    temp = YearDays(y);
    offset -= temp;
  }
  if (offset < 0) {
    offset += temp;
    --y;
  }

  const int leap = LeapMonth(y);
  bool is_leap = false;
  int m = 1;
  for (; m < 13 && offset > 0; ++m) {
    if (leap > 0 && m == leap + 1 && !is_leap) {
      --m;
      is_leap = true;
      temp = LeapDays(y);
    } else {
      temp = LunarMonthDays(y, m);
    }
    if (is_leap && m == leap + 1) is_leap = false;
    offset -= temp;
  }
  if (offset == 0 && leap > 0 && m == leap + 1) {
    if (is_leap) {
      is_leap = false;
    } else {
      is_leap = true;
      --m;
    }
  }
  if (offset < 0) {
    offset += temp;
    --m;
  }

  const int d = static_cast<int>(offset) + 1;
  out->year = y;
  out->month = m;
  out->day = d;
  out->is_leap = is_leap;
  out->day_text = DayName(d);
  out->month_text = MonthName(m, is_leap);
  return true;
}

std::wstring TermOf(int year, int month, int day) {
  static const wchar_t* kNames[] = {
      L"小寒", L"大寒", L"立春", L"雨水", L"惊蛰", L"春分", L"清明", L"谷雨",
      L"立夏", L"小满", L"芒种", L"夏至", L"小暑", L"大暑", L"立秋", L"处暑",
      L"白露", L"秋分", L"寒露", L"霜降", L"立冬", L"小雪", L"大雪", L"冬至",
  };
  if (year < 1900 || year > 2100) return {};

  // 基准：1900-01-06 02:05 UTC。与 Dart 版一致（那边也是 UTC 取 .day）。
  const int64_t base_seconds =
      DaysFromCivil(1900, 1, 6) * 86400 + 2 * 3600 + 5 * 60;

  const int index_a = (month - 1) * 2;
  for (int k = 0; k < 2; ++k) {
    const int n = index_a + k;
    const double minutes =
        31556925974.7 * (year - 1900) / 60000.0 + kTermMinutes[n];
    const int64_t total_seconds =
        base_seconds + static_cast<int64_t>(std::llround(minutes * 60.0));
    int ty = 0, tm = 0, td = 0;
    CivilFromDays(total_seconds / 86400, &ty, &tm, &td);
    if (ty == year && tm == month && td == day) return kNames[n];
  }
  return {};
}

bool FestivalOf(int year, int month, int day, const LunarDate& lunar,
                Festival* out) {
  if (out == nullptr) return false;
  static const std::map<std::string, const wchar_t*> kSolar = {
      {"1-1", L"元旦"},   {"2-14", L"情人节"}, {"3-8", L"妇女节"},
      {"3-12", L"植树节"}, {"4-1", L"愚人节"},  {"5-1", L"劳动节"},
      {"5-4", L"青年节"},  {"6-1", L"儿童节"},  {"7-1", L"建党节"},
      {"8-1", L"建军节"},  {"9-10", L"教师节"}, {"10-1", L"国庆节"},
      {"12-24", L"平安夜"}, {"12-25", L"圣诞节"},
  };
  static const std::map<std::string, const wchar_t*> kLunar = {
      {"1-1", L"春节"},   {"1-15", L"元宵"},  {"2-2", L"龙抬头"},
      {"5-5", L"端午"},   {"7-7", L"七夕"},   {"7-15", L"中元"},
      {"8-15", L"中秋"},  {"9-9", L"重阳"},   {"12-8", L"腊八"},
      {"12-23", L"小年"},
  };
  const auto is_statutory = [](const std::wstring& name) {
    return name == L"元旦" || name == L"春节" || name == L"清明" ||
           name == L"劳动节" || name == L"端午" || name == L"中秋" ||
           name == L"国庆节";
  };

  const std::string solar_key =
      std::to_string(month) + "-" + std::to_string(day);
  if (const auto it = kSolar.find(solar_key); it != kSolar.end()) {
    out->name = it->second;
    out->statutory = is_statutory(out->name);
    return true;
  }

  if (!lunar.is_leap) {
    const std::string lunar_key =
        std::to_string(lunar.month) + "-" + std::to_string(lunar.day);
    if (const auto it = kLunar.find(lunar_key); it != kLunar.end()) {
      out->name = it->second;
      out->statutory = is_statutory(out->name);
      return true;
    }
    // 除夕：腊月最后一天
    if (lunar.month == 12 && lunar.day == LunarMonthDays(lunar.year, 12)) {
      out->name = L"除夕";
      out->statutory = true;
      return true;
    }
  }
  return false;
}

}  // namespace glance
