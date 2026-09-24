// 时钟圆体的定位与族名。
//
// 注意：字体**不是**在这里加载的。曾经用 GDI 的 AddFontResourceExW 试过——
// 它返回 added=2、看起来成功，但 DirectWrite 完全看不到，
// CreateTextFormat 照旧回退系统字体。加载走 Renderer::LoadPrivateFontFile
// （DWrite FontSet 路线），这里只负责"文件在哪"和"字体叫什么"。
#ifndef GLANCE_NATIVE_PLATFORM_PRIVATE_FONTS_H_
#define GLANCE_NATIVE_PLATFORM_PRIVATE_FONTS_H_

#include <string>

namespace glance {

// 该字体内部的族名（ttf name 表里的值）。不是 pubspec 侧那个
// TsukushiBMaru 别名——DWrite 只认内部名。
inline constexpr const wchar_t kClockFontFamily[] = L"筑紫A丸W圆";

// 从 exe 所在目录逐级向上找 assets/fonts/tsukushi_b_maru.ttf。
// 开发时 exe 在 native\build\Release（往上三级是仓库根），打包后
// assets 会放在 exe 旁边。找不到返回空串。
std::wstring FindClockFontPath();

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_PRIVATE_FONTS_H_
