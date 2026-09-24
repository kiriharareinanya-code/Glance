#include "cards/clock_card.h"

#include <windows.h>

#include "platform/private_fonts.h"

namespace glance {

bool ClockCard::Update() {
  SYSTEMTIME now = {};
  GetLocalTime(&now);
  if (now.wHour == last_hour_ && now.wMinute == last_minute_) return false;
  last_hour_ = now.wHour;
  last_minute_ = now.wMinute;

  wchar_t buffer[64] = {};
  swprintf_s(buffer, L"%02d:%02d", now.wHour, now.wMinute);
  time_text_ = buffer;

  // 顺序按 GetLocalTime 的约定：wDayOfWeek 0 = 周日
  static const wchar_t* kWeekdays[] = {L"周日", L"周一", L"周二", L"周三",
                                       L"周四", L"周五", L"周六"};
  swprintf_s(buffer, L"%d月%d日 %s", now.wMonth, now.wDay,
             kWeekdays[now.wDayOfWeek % 7]);
  date_text_ = buffer;

  return true;
}

void ClockCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  const float height = rect.bottom - rect.top;

  renderer.FillRoundRect(rect, theme.card_radius * s, theme.card_bg);

  // 时间：卡片上部的大字。字号按逻辑 58px 定，乘 DPI 缩放。
  // 圆体只有英数，族名必须精确到内部名（见 private_fonts.h），
  // 并且要走私有字体集合——系统字体集合里没有它。
  TextStyle time_style;
  time_style.size = 58.0f * s;
  time_style.weight = DWRITE_FONT_WEIGHT_BOLD;
  time_style.family = kClockFontFamily;
  time_style.use_private_font = true;
  time_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  time_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  const D2D1_RECT_F time_rect =
      D2D1::RectF(rect.left, rect.top + height * 0.16f, rect.right,
                  rect.top + height * 0.62f);
  renderer.DrawText(time_text_, renderer.TextFormat(time_style), time_rect,
                    theme.fg);

  // 日期：中文用雅黑，圆体只有英数，混排会缺字。
  TextStyle date_style;
  date_style.size = 14.0f * s;
  date_style.family = L"Microsoft YaHei UI";
  date_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  date_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  const D2D1_RECT_F date_rect =
      D2D1::RectF(rect.left, rect.top + height * 0.62f, rect.right,
                  rect.top + height * 0.62f + 30.0f * s);
  renderer.DrawText(date_text_, renderer.TextFormat(date_style), date_rect,
                    theme.fg_muted);
}

}  // namespace glance
