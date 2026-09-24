#include "cards/calendar_card.h"

#include <windows.h>

#include <algorithm>

#include "core/date_util.h"

namespace glance {
namespace {

// 配色与 Flutter 版 calendar.dart 完全一致
const Color kAccent = Color::Hex(0x29B6F6);   // 今天的圆底
const Color kHoliday = Color::Hex(0xFF8A6B);  // 法定节假日 / 周末
const Color kTerm = Color::Hex(0x8FD6A0);     // 节气
const Color kOnAccent = Color::Hex(0x0B1116); // 圆底上的字
const Color kMarkedBg = Color::Hex(0xFFFFFF, 0.094f);  // 节日/节气的淡圆底

constexpr float kHeaderSize = 17.0f;  // 逻辑像素
constexpr float kWeekSize = 13.0f;
constexpr float kDateSize = 17.0f;
constexpr float kSubSize = 11.0f;

}  // namespace

CalendarCard::CalendarCard(bool show_lunar, bool show_festival, bool monday_first)
    : show_lunar_(show_lunar),
      show_festival_(show_festival),
      monday_first_(monday_first) {
  Update();
}

bool CalendarCard::Update() {
  SYSTEMTIME now = {};
  GetLocalTime(&now);
  // 跨过午夜才需要重画（今天的高亮要挪过去）
  if (now.wYear == today_year_ && now.wMonth == today_month_ &&
      now.wDay == today_day_) {
    return false;
  }
  today_year_ = now.wYear;
  today_month_ = now.wMonth;
  today_day_ = now.wDay;
  // 视图默认回到"今天所在的月"（翻月交互做出来之后只在首次生效）
  if (view_year_ == 0) {
    view_year_ = now.wYear;
    view_month_ = now.wMonth;
  }
  return true;
}

void CalendarCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  renderer.FillCardBackground(rect, theme.card_radius * s, theme.card_bg,
                              theme.CardTintAlpha());

  const float pad_x = 18.0f * s;
  const float pad_y = 16.0f * s;
  const float left = rect.left + pad_x;
  const float right = rect.right - pad_x;
  float cursor = rect.top + pad_y;

  // ---- 头部：年月 ----
  TextStyle head_style;
  head_style.size = kHeaderSize * s;
  head_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
  head_style.family = L"Microsoft YaHei UI";
  head_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  const float header_h = 26.0f * s;
  const std::wstring title =
      std::to_wstring(view_year_) + L"年" + std::to_wstring(view_month_) + L"月";
  renderer.DrawText(title, renderer.TextFormat(head_style),
                    D2D1::RectF(left, cursor, right, cursor + header_h), theme.fg);
  cursor += header_h + 10.0f * s;

  // ---- 周标题 ----
  static const wchar_t* kMondayFirst[7] = {L"一", L"二", L"三", L"四",
                                           L"五", L"六", L"日"};
  static const wchar_t* kSundayFirst[7] = {L"日", L"一", L"二", L"三",
                                           L"四", L"五", L"六"};
  const wchar_t* const* heads = monday_first_ ? kMondayFirst : kSundayFirst;
  const int weekend_a = monday_first_ ? 5 : 0;
  const int weekend_b = monday_first_ ? 6 : 6;

  TextStyle week_style;
  week_style.size = kWeekSize * s;
  week_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
  week_style.family = L"Microsoft YaHei UI";
  week_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  week_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  const float week_h = 20.0f * s;
  const float col_w = (right - left) / 7.0f;
  for (int col = 0; col < 7; ++col) {
    const float cx = left + col_w * (static_cast<float>(col) + 0.5f);
    const bool weekend = (col == weekend_a || col == weekend_b);
    renderer.DrawText(heads[col], renderer.TextFormat(week_style),
                      D2D1::RectF(cx - col_w * 0.5f, cursor, cx + col_w * 0.5f,
                                  cursor + week_h),
                      theme.fg.WithAlpha(weekend ? 0.8f : 0.62f));
  }
  cursor += week_h + 4.0f * s;

  // ---- 42 格（固定 6 行，换月不跳变）----
  const float grid_h = rect.bottom - pad_y - cursor;
  if (grid_h <= 0 || col_w <= 0) return;
  const float row_h = grid_h / 6.0f;
  const float cell = std::min(col_w, row_h);
  const float circle_r = cell * 0.5f;

  // 本月 1 号是周几 → 前面要补几格（周一起始时把周日挪到末尾）
  const int64_t first_days = DaysFromCivil(view_year_, view_month_, 1);
  const int start_dow = WeekdayFromDays(first_days);  // 0=周日
  const int lead = monday_first_ ? (start_dow + 6) % 7 : start_dow;

  TextStyle date_style;
  date_style.size = kDateSize * s;
  date_style.weight = DWRITE_FONT_WEIGHT_BOLD;
  date_style.family = L"Microsoft YaHei UI";
  date_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  date_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  TextStyle sub_style;
  sub_style.size = kSubSize * s;
  sub_style.family = L"Microsoft YaHei UI";
  sub_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  sub_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  for (int i = 0; i < 42; ++i) {
    int y = 0, m = 0, d = 0;
    CivilFromDays(first_days - lead + i, &y, &m, &d);

    const int col = i % 7;
    const int row = i / 7;
    const float cx = left + col_w * (static_cast<float>(col) + 0.5f);
    const float cy = cursor + row_h * (static_cast<float>(row) + 0.5f);

    const bool in_month = (m == view_month_);
    const bool is_today = (y == today_year_ && m == today_month_ && d == today_day_);
    const bool weekend = (col == weekend_a || col == weekend_b);

    LunarDate lunar;
    const bool has_lunar = SolarToLunar(y, m, d, &lunar);
    const std::wstring term = TermOf(y, m, d);
    Festival fest;
    const bool has_fest = has_lunar && FestivalOf(y, m, d, lunar, &fest);

    // 小字优先级：节日 > 节气 > 初一显示月名 > 农历日
    std::wstring sub;
    Color sub_color = theme.fg;
    bool sub_colored = false;
    if (show_festival_ && has_fest) {
      sub = fest.name;
      if (fest.statutory) {
        sub_color = kHoliday;
        sub_colored = true;
      }
    } else if (show_festival_ && !term.empty()) {
      sub = term;
      sub_color = kTerm;
      sub_colored = true;
    } else if (show_lunar_ && has_lunar) {
      sub = lunar.day == 1 ? lunar.month_text : lunar.day_text;
    }

    const bool marked =
        !is_today && in_month && show_festival_ && (has_fest || !term.empty());
    const bool statutory = show_festival_ && has_fest && fest.statutory;

    // 圆底：今天实心强调色；节日/节气给一层淡底，让它从一片数字里跳出来
    if (is_today) {
      renderer.FillCircle(cx, cy, circle_r, kAccent);
    } else if (marked) {
      renderer.FillCircle(cx, cy, circle_r, kMarkedBg);
    }

    Color day_color = theme.fg;
    float day_alpha = 1.0f;
    if (is_today) {
      day_color = kOnAccent;
    } else if (!in_month) {
      day_alpha = 0.4f;  // 非本月弱化但保持可辨认
    } else if (weekend || statutory) {
      day_color = kHoliday;
    }

    const float half = cell * 0.5f;
    renderer.DrawText(std::to_wstring(d), renderer.TextFormat(date_style),
                      D2D1::RectF(cx - half, cy - half * 0.92f, cx + half,
                                  cy + half * 0.18f),
                      day_color.WithAlpha(day_alpha));

    if (!sub.empty()) {
      Color color = theme.fg.WithAlpha(in_month ? 0.72f : 0.32f);
      if (is_today) color = kOnAccent.WithAlpha(0.9f);
      else if (sub_colored) color = sub_color;
      renderer.DrawText(sub, renderer.TextFormat(sub_style),
                        D2D1::RectF(cx - half, cy + half * 0.10f, cx + half,
                                    cy + half * 0.95f),
                        color);
    }
  }
}

}  // namespace glance
