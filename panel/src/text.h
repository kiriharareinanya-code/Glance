// 编码转换。协议走 UTF-8，Windows API 要 UTF-16，AF_UNIX 的路径要 ANSI。
#pragma once

#include <windows.h>

#include <string>
#include <string_view>

namespace panel {

inline std::wstring WideFromUtf8(std::string_view s) {
  if (s.empty()) return {};
  const int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(static_cast<size_t>(n), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n);
  return out;
}

inline std::string Utf8FromWide(std::wstring_view s) {
  if (s.empty()) return {};
  const int n = ::WideCharToMultiByte(CP_UTF8, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0,
                                      nullptr, nullptr);
  std::string out(static_cast<size_t>(n), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n, nullptr, nullptr);
  return out;
}

// AF_UNIX 的 sun_path 是 char[]，Windows 按系统 ANSI 代码页解释它
inline std::string AnsiFromWide(std::wstring_view s) {
  if (s.empty()) return {};
  const int n = ::WideCharToMultiByte(CP_ACP, 0, s.data(),
                                      static_cast<int>(s.size()), nullptr, 0,
                                      nullptr, nullptr);
  std::string out(static_cast<size_t>(n), '\0');
  ::WideCharToMultiByte(CP_ACP, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n, nullptr, nullptr);
  return out;
}

}  // namespace panel
