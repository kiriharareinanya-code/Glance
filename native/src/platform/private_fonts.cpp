#include "platform/private_fonts.h"

#include <windows.h>

namespace glance {
namespace {

// 仓库里的固定位置（相对仓库根）。
constexpr const wchar_t kFontRelativePath[] = L"assets\\fonts\\tsukushi_b_maru.ttf";

}  // namespace

std::wstring FindClockFontPath() {
  wchar_t exe_path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return {};

  std::wstring dir(exe_path);
  const size_t slash = dir.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return {};
  dir.resize(slash);

  // 逐级向上找：exe 同级 → 上一级 → …… 最多五级。
  // 写死相对层级容易数错（第一版写成四级，字体就静悄悄没加载上）。
  std::wstring candidate = dir;
  for (int level = 0; level < 5; ++level) {
    const std::wstring path = candidate + L"\\" + kFontRelativePath;
    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return path;
    }
    candidate += L"\\..";
  }
  return {};
}

}  // namespace glance
