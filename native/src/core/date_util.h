// 公历日期运算：日期 ↔ 天数（Howard Hinnant 的 days_from_civil 系列，1970-01-01 为 0）。
//
// lunar.cpp 用它算农历偏移，calendar_card.cpp 用它排月历格子。
// 不用 SYSTEMTIME/FileTime 是因为那套接口要处理时区与 1601 基准，
// 这里只需要"纯日期"的整数运算，这套算法没有时区坑、也没有闰年坑。
#ifndef GLANCE_NATIVE_CORE_DATE_UTIL_H_
#define GLANCE_NATIVE_CORE_DATE_UTIL_H_

#include <cstdint>

namespace glance {

// 公历 (y, m, d) → 天数（1970-01-01 为 0）
int64_t DaysFromCivil(int year, int month, int day);

// 天数 → 公历
void CivilFromDays(int64_t days, int* year, int* month, int* day);

// 星期：0 = 周日（与 GetLocalTime 的 wDayOfWeek 同序）
int WeekdayFromDays(int64_t days);

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_DATE_UTIL_H_
