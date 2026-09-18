// 面板的视觉基础：配色、字体、卡片容器、两列行。
//
// 目标观感：Win11 原生设置页那一套 —— 分组卡片、标题/说明两级文字、
// 右侧控件对齐、跟随系统深浅色与主题色。这里是**原生 WinUI3 控件**，
// 所以观感直接来自系统，不用像 Flutter 面板那样自己画一遍。
#pragma once

// C++/WinRT 的投射头要一个个显式引：少一个就会出现"必须首先定义此函数"
// 这类看着莫名其妙的报错（其实只是模板定义没被包含进来）。
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Windows.UI.h>

#include <cstdint>
#include <string>

namespace ui {

namespace mux = winrt::Microsoft::UI::Xaml;
namespace muxc = winrt::Microsoft::UI::Xaml::Controls;
namespace muxm = winrt::Microsoft::UI::Xaml::Media;

struct Theme {
  bool dark = true;
  uint32_t window_bg = 0x202020;
  uint32_t card_bg = 0x2B2B2B;
  uint32_t card_hover = 0x323232;
  uint32_t stroke = 0x3A3A3A;
  uint32_t text = 0xFFFFFF;
  uint32_t text_dim = 0xB0B0B0;
  uint32_t text_faint = 0x808080;
  uint32_t accent = 0x60CDFF;
  uint32_t danger = 0xFF6B6B;
};

// 读系统设置（深浅色 / 主题色），并把它固定到 Application::RequestedTheme，
// 这样我们的手写颜色和系统控件不会各说各话。
Theme DetectAndApplyTheme();

const Theme& theme();

inline muxm::SolidColorBrush Brush(uint32_t rgb, uint8_t alpha = 0xFF) {
  return muxm::SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(
      alpha, static_cast<uint8_t>((rgb >> 16) & 0xFF),
      static_cast<uint8_t>((rgb >> 8) & 0xFF),
      static_cast<uint8_t>(rgb & 0xFF)));
}

inline muxc::TextBlock Text(const winrt::hstring& value, double size,
                           uint32_t color) {
  muxc::TextBlock t;
  t.Text(value);
  t.FontSize(size);
  t.Foreground(Brush(color));
  t.TextWrapping(mux::TextWrapping::Wrap);
  return t;
}

inline muxc::TextBlock Label(const winrt::hstring& value) {
  return Text(value, 14, theme().text);
}

inline muxc::TextBlock Heading(const winrt::hstring& value) {
  auto t = Text(value, 20, theme().text);
  t.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
  return t;
}

inline muxc::TextBlock Dim(const winrt::hstring& value, double size = 12) {
  return Text(value, size, theme().text_dim);
}

// 分组卡片：Win11 设置页里那种圆角容器
muxc::Border Card(winrt::Microsoft::UI::Xaml::UIElement child);

// 一行设置项：左边标题+说明，右边控件
muxc::Grid SettingRow(const winrt::hstring& title, const winrt::hstring& desc,
                      winrt::Microsoft::UI::Xaml::FrameworkElement control);

muxc::FontIcon Glyph(const wchar_t* code, double size = 16);

}  // namespace ui
