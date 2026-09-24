// 天气图标：按小米天气代码的语义名画矢量图形。
//
// Flutter 版用的是 Material 图标字体；原生版没有图标字体（也不该为此引一个），
// 用几何形状拼——太阳是圆加射线、云是三个圆叠一个底、雨是云加斜线。
// 颜色跟语义走（与 Flutter 版 weather.dart 的 _iconColor 一致）：
//   sun #FFD79A / cloud #B8C4D9 / fog #C7CFD9
//   rain #7CC7FF / snow #DCEEFA / storm #B79CFF
#ifndef GLANCE_NATIVE_CARDS_WEATHER_ICON_H_
#define GLANCE_NATIVE_CARDS_WEATHER_ICON_H_

#include <string>

#include "render/renderer.h"

namespace glance {

// 小米天气代码 → 语义图标名（sun / cloud / fog / rain / snow / sleet / storm）
// 与 weather.dart 的 _code 表一致。
const wchar_t* IconKindForCode(int code);
// 代码 → 中文描述（晴 / 多云 / 阵雨…）
const wchar_t* DescriptionForCode(int code);
// 图标名 → 颜色（语义色）
Color ColorForIconKind(const wchar_t* kind);

// 以 (cx, cy) 为中心、边长约 size 绘制图标。
void DrawWeatherIcon(Renderer& renderer, const wchar_t* kind, float cx, float cy,
                     float size, const Color& color);

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_WEATHER_ICON_H_
