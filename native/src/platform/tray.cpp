#include "platform/tray.h"

#include <shellapi.h>

#include "platform/log.h"

namespace glance {
namespace {

constexpr const wchar_t kTooltipClass[] = L"GlanceNativeTray";

// 从 Flutter 版的资源目录逐级往上找 app_icon.ico
std::wstring FindIconPath() {
  wchar_t exe_path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return {};
  std::wstring dir(exe_path);
  const size_t slash = dir.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return {};
  dir.resize(slash);

  std::wstring base = dir;
  for (int level = 0; level < 6; ++level) {
    const std::wstring candidate = base + L"\\app_icon.ico";
    if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return candidate;
    }
    const std::wstring flutter_res =
        base + L"\\windows\\runner\\resources\\app_icon.ico";
    if (GetFileAttributesW(flutter_res.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return flutter_res;
    }
    base += L"\\..";
  }
  return {};
}

}  // namespace

bool Tray::Create(HWND hwnd, const std::wstring& tooltip) {
  if (hwnd == nullptr || created_) return false;
  hwnd_ = hwnd;

  // 图标：优先用项目自己的 ico（和 Flutter 版一致），拿不到就用系统默认
  const std::wstring icon_path = FindIconPath();
  if (!icon_path.empty()) {
    icon_ = static_cast<HICON>(LoadImageW(nullptr, icon_path.c_str(), IMAGE_ICON,
                                          GetSystemMetrics(SM_CXSMICON),
                                          GetSystemMetrics(SM_CYSMICON),
                                          LR_LOADFROMFILE));
  }
  if (icon_ == nullptr) icon_ = LoadIconW(nullptr, IDI_APPLICATION);

  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = 1;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kCallbackMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, tooltip.c_str(), _TRUNCATE);

  created_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  Log(L"[tray] created=%d icon=%s", created_ ? 1 : 0,
      icon_path.empty() ? L"(system)" : icon_path.c_str());
  return created_;
}

void Tray::Destroy() {
  if (!created_) return;
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = 1;
  Shell_NotifyIconW(NIM_DELETE, &data);
  created_ = false;
  if (icon_ != nullptr) {
    DestroyIcon(icon_);
    icon_ = nullptr;
  }
}

int Tray::ShowMenu(bool tiles_visible) {
  if (!created_) return 0;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return 0;
  AppendMenuW(menu, MF_STRING, kTrayToggleTiles,
              tiles_visible ? L"隐藏磁贴" : L"显示磁贴");
  AppendMenuW(menu, MF_STRING, kTrayReload, L"重载布局");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExit, L"退出 Glance");

  POINT cursor = {};
  GetCursorPos(&cursor);
  // 菜单要能"点别处自动关"，必须先让本线程成为前台——这是 TrackPopupMenu
  // 的经典要求，少了它会留下一个关不掉的菜单。
  SetForegroundWindow(hwnd_);
  const int command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY, cursor.x, cursor.y, 0, hwnd_, nullptr);
  DestroyMenu(menu);
  return command;
}

}  // namespace glance
