#include "core/date_util.h"

namespace glance {

int64_t DaysFromCivil(int year, int month, int day) {
  year -= month <= 2 ? 1 : 0;
  const int64_t era = (year >= 0 ? year : year - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(year - era * 400);
  const unsigned doy =
      (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + static_cast<unsigned>(day) - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + static_cast<int64_t>(doe) - 719468;
}

void CivilFromDays(int64_t days, int* year, int* month, int* day) {
  days += 719468;
  const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
  const unsigned doe = static_cast<unsigned>(days - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  const int64_t y = static_cast<int64_t>(yoe) + era * 400;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  const unsigned d = doy - (153 * mp + 2) / 5 + 1;
  const unsigned m = mp + (mp < 10 ? 3 : -9);

  *year = static_cast<int>(y + (m <= 2 ? 1 : 0));
  *month = static_cast<int>(m);
  *day = static_cast<int>(d);
}

int WeekdayFromDays(int64_t days) {
  // 1970-01-01 是周四（4）。负数取模要先加够倍数。
  int64_t weekday = (days + 4) % 7;
  if (weekday < 0) weekday += 7;
  return static_cast<int>(weekday);
}

}  // namespace glance
