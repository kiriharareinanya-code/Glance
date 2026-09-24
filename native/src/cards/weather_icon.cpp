#include "cards/weather_icon.h"

#include <cmath>
#include <cstddef>
#include <string>

namespace glance {
namespace {

struct CodeEntry {
  int code;
  const wchar_t* desc;
  const wchar_t* icon;
};

// 小米天气代码表（与 weather.dart 的 _code 表逐条对应）
constexpr CodeEntry kCodes[] = {
    {0, L"晴", L"sun"},          {1, L"多云", L"cloud"},
    {2, L"阴", L"cloud"},        {3, L"阵雨", L"rain"},
    {4, L"雷阵雨", L"storm"},    {5, L"雷阵雨伴冰雹", L"storm"},
    {6, L"雨夹雪", L"sleet"},    {7, L"小雨", L"rain"},
    {8, L"中雨", L"rain"},       {9, L"大雨", L"rain"},
    {10, L"暴雨", L"rain"},      {11, L"大暴雨", L"rain"},
    {12, L"特大暴雨", L"rain"},  {13, L"阵雪", L"snow"},
    {14, L"小雪", L"snow"},      {15, L"中雪", L"snow"},
    {16, L"大雪", L"snow"},      {17, L"暴雪", L"snow"},
    {18, L"雾", L"fog"},         {19, L"冻雨", L"rain"},
    {20, L"沙尘暴", L"fog"},     {21, L"小雨-中雨", L"rain"},
    {22, L"中雨-大雨", L"rain"}, {23, L"大雨-暴雨", L"rain"},
    {24, L"暴雨-大暴雨", L"rain"},
    {25, L"大暴雨-特大暴雨", L"rain"},
    {26, L"小雪-中雪", L"snow"}, {27, L"中雪-大雪", L"snow"},
    {28, L"大雪-暴雪", L"snow"}, {29, L"浮尘", L"fog"},
    {30, L"扬沙", L"fog"},       {31, L"强沙尘暴", L"fog"},
    {32, L"飑", L"storm"},       {33, L"龙卷风", L"storm"},
    {34, L"高吹雪", L"snow"},    {35, L"轻雾", L"fog"},
    {53, L"霾", L"fog"},         {99, L"未知", L"cloud"},
};

const CodeEntry& Lookup(int code) {
  for (const CodeEntry& entry : kCodes) {
    if (entry.code == code) return entry;
  }
  return kCodes[std::size(kCodes) - 1];  // 99 未知
}

// 云：三个圆 + 一个底矩形拼出下缘平直的轮廓
void DrawCloud(Renderer& r, float cx, float cy, float size, const Color& color) {
  const float s = size;
  r.FillCircle(cx - 0.21f * s, cy + 0.03f * s, 0.17f * s, color);
  r.FillCircle(cx + 0.22f * s, cy + 0.05f * s, 0.15f * s, color);
  r.FillCircle(cx + 0.01f * s, cy - 0.08f * s, 0.23f * s, color);
  r.FillRect(D2D1::RectF(cx - 0.23f * s, cy + 0.03f * s, cx + 0.24f * s,
                         cy + 0.19f * s),
             color);
}

void DrawSun(Renderer& r, float cx, float cy, float size, const Color& color) {
  const float s = size;
  r.FillCircle(cx, cy, 0.24f * s, color);
  // 八条射线
  for (int i = 0; i < 8; ++i) {
    const float angle = 3.14159265f * 2.0f * static_cast<float>(i) / 8.0f;
    const float cos_a = std::cos(angle);
    const float sin_a = std::sin(angle);
    r.DrawLine(cx + cos_a * 0.34f * s, cy + sin_a * 0.34f * s,
               cx + cos_a * 0.5f * s, cy + sin_a * 0.5f * s, 0.07f * s, color);
  }
}

void DrawRainDrops(Renderer& r, float cx, float cy, float size, const Color& color,
                   bool sleet) {
  const float s = size;
  for (int i = -1; i <= 1; ++i) {
    const float x = cx + static_cast<float>(i) * 0.17f * s;
    r.DrawLine(x + 0.05f * s, cy + 0.24f * s, x - 0.03f * s, cy + 0.44f * s,
               0.07f * s, color);
    if (sleet) {
      r.FillCircle(x + 0.06f * s, cy + 0.34f * s, 0.035f * s, color);
    }
  }
}

void DrawSnowFlakes(Renderer& r, float cx, float cy, float size, const Color& color) {
  const float s = size;
  const float arm = 0.11f * s;
  for (int i = -1; i <= 1; ++i) {
    const float x = cx + static_cast<float>(i) * 0.17f * s;
    const float y = cy + 0.34f * s;
    r.DrawLine(x - arm, y, x + arm, y, 0.06f * s, color);
    r.DrawLine(x, y - arm, x, y + arm, 0.06f * s, color);
  }
}

void DrawStormBolt(Renderer& r, float cx, float cy, float size, const Color& color) {
  const float s = size;
  const D2D1_POINT_2F bolt[] = {
      D2D1::Point2F(cx - 0.05f * s, cy + 0.20f * s),
      D2D1::Point2F(cx + 0.12f * s, cy + 0.20f * s),
      D2D1::Point2F(cx + 0.01f * s, cy + 0.36f * s),
      D2D1::Point2F(cx + 0.14f * s, cy + 0.36f * s),
      D2D1::Point2F(cx - 0.10f * s, cy + 0.62f * s),
      D2D1::Point2F(cx - 0.01f * s, cy + 0.42f * s),
      D2D1::Point2F(cx - 0.13f * s, cy + 0.42f * s),
  };
  r.FillPolygon(bolt, static_cast<int>(std::size(bolt)), color);
}

void DrawFogLines(Renderer& r, float cx, float cy, float size, const Color& color) {
  const float s = size;
  const float widths[3] = {0.42f, 0.34f, 0.46f};
  for (int i = 0; i < 3; ++i) {
    const float y = cy + (static_cast<float>(i) - 1.0f) * 0.17f * s;
    r.DrawLine(cx - widths[i] * s * 0.5f, y, cx + widths[i] * s * 0.5f, y,
               0.08f * s, color);
  }
}

}  // namespace

const wchar_t* IconKindForCode(int code) { return Lookup(code).icon; }
const wchar_t* DescriptionForCode(int code) { return Lookup(code).desc; }

Color ColorForIconKind(const wchar_t* kind) {
  const std::wstring k = kind != nullptr ? kind : L"cloud";
  if (k == L"sun") return Color::Hex(0xFFD79A);
  if (k == L"fog") return Color::Hex(0xC7CFD9);
  if (k == L"rain") return Color::Hex(0x7CC7FF);
  if (k == L"snow") return Color::Hex(0xDCEEFA);
  if (k == L"sleet") return Color::Hex(0xDCEEFA);
  if (k == L"storm") return Color::Hex(0xB79CFF);
  return Color::Hex(0xB8C4D9);  // cloud
}

void DrawWeatherIcon(Renderer& renderer, const wchar_t* kind, float cx, float cy,
                     float size, const Color& color) {
  const std::wstring k = kind != nullptr ? kind : L"cloud";
  if (k == L"sun") {
    DrawSun(renderer, cx, cy, size, color);
  } else if (k == L"fog") {
    DrawFogLines(renderer, cx, cy, size, color);
  } else if (k == L"rain") {
    DrawCloud(renderer, cx, cy - 0.12f * size, size * 0.86f, color);
    DrawRainDrops(renderer, cx, cy, size, color, false);
  } else if (k == L"sleet") {
    DrawCloud(renderer, cx, cy - 0.12f * size, size * 0.86f, color);
    DrawRainDrops(renderer, cx, cy, size, color, true);
  } else if (k == L"snow") {
    DrawCloud(renderer, cx, cy - 0.14f * size, size * 0.86f, color);
    DrawSnowFlakes(renderer, cx, cy, size, color);
  } else if (k == L"storm") {
    DrawCloud(renderer, cx, cy - 0.16f * size, size * 0.86f, color);
    DrawStormBolt(renderer, cx, cy, size, color);
  } else {
    DrawCloud(renderer, cx, cy, size, color);
  }
}

}  // namespace glance
