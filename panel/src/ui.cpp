#include "ui.h"

#include <winrt/Windows.UI.ViewManagement.h>

#include "text.h"

namespace ui {
namespace {

Theme g_theme;

bool AppsUseLightTheme() {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER,
                      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\"
                      L"Personalize",
                      0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD value = 1;
  DWORD size = sizeof(value);
  DWORD type = 0;
  const bool ok =
      ::RegQueryValueExW(key, L"AppsUseLightTheme", nullptr, &type,
                         reinterpret_cast<LPBYTE>(&value), &size) == ERROR_SUCCESS;
  ::RegCloseKey(key);
  return ok && value != 0;
}

}  // namespace

Theme DetectAndApplyTheme() {
  const bool dark = !AppsUseLightTheme();
  g_theme.dark = dark;
  if (dark) {
    g_theme = Theme{};
  } else {
    g_theme.window_bg = 0xF3F3F3;
    g_theme.card_bg = 0xFFFFFF;
    g_theme.card_hover = 0xF5F5F5;
    g_theme.stroke = 0xE0E0E0;
    g_theme.text = 0x1A1A1A;
    g_theme.text_dim = 0x5D5D5D;
    g_theme.text_faint = 0x8A8A8A;
    g_theme.accent = 0x005FB8;
    g_theme.danger = 0xC42B1C;
  }

  // 取系统主题色当强调色（拿不到就用上面那套默认）
  try {
    winrt::Windows::UI::ViewManagement::UISettings settings;
    const auto accent =
        settings.GetColorValue(winrt::Windows::UI::ViewManagement::UIColorType::
                                   Accent);
    g_theme.accent =
        (static_cast<uint32_t>(accent.R) << 16) |
        (static_cast<uint32_t>(accent.G) << 8) | accent.B;
  } catch (...) {
  }

  mux::Application::Current().RequestedTheme(
      dark ? mux::ApplicationTheme::Dark : mux::ApplicationTheme::Light);
  return g_theme;
}

const Theme& theme() { return g_theme; }

muxc::Border Card(mux::UIElement child) {
  muxc::Border border;
  border.Background(Brush(g_theme.card_bg));
  border.BorderBrush(Brush(g_theme.stroke));
  border.BorderThickness(mux::ThicknessHelper::FromUniformLength(1));
  border.CornerRadius(mux::CornerRadiusHelper::FromUniformRadius(8));
  border.Padding(mux::ThicknessHelper::FromLengths(16, 12, 16, 12));
  border.Child(child);
  border.HorizontalAlignment(mux::HorizontalAlignment::Stretch);
  return border;
}

muxc::Grid SettingRow(const winrt::hstring& title, const winrt::hstring& desc,
                      mux::FrameworkElement control) {
  muxc::Grid grid;
  grid.ColumnDefinitions().Append(muxc::ColumnDefinition{});
  auto auto_col = muxc::ColumnDefinition{};
  auto_col.Width(mux::GridLengthHelper::FromValueAndType(
      0, mux::GridUnitType::Auto));
  grid.ColumnDefinitions().Append(auto_col);
  grid.Padding(mux::ThicknessHelper::FromLengths(0, 6, 0, 6));
  grid.ColumnSpacing(12);

  muxc::StackPanel left;
  left.Spacing(2);
  left.VerticalAlignment(mux::VerticalAlignment::Center);
  left.Children().Append(Label(title));
  if (!desc.empty()) left.Children().Append(Dim(desc));
  muxc::Grid::SetColumn(left, 0);
  grid.Children().Append(left);

  control.VerticalAlignment(mux::VerticalAlignment::Center);
  muxc::Grid::SetColumn(control, 1);
  grid.Children().Append(control);
  return grid;
}

muxc::FontIcon Glyph(const wchar_t* code, double size) {
  muxc::FontIcon icon;
  icon.Glyph(code);
  icon.FontSize(size);
  return icon;
}

}  // namespace ui
