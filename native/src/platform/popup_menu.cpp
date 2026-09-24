#include "platform/popup_menu.h"

namespace glance {
namespace {

constexpr const wchar_t kMenuHostClass[] = L"GlanceNativeMenuHost";

// 隐藏宿主窗口：只为承接前台归属和接收菜单消息，不显示任何东西。
// 进程内共用一个即可（菜单是串行的，不存在并发弹出）。
HWND MenuHostWindow() {
  static HWND host = nullptr;
  if (host != nullptr) return host;

  static bool registered = false;
  if (!registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = kMenuHostClass;
    if (!RegisterClassExW(&wc)) return nullptr;
    registered = true;
  }
  host = CreateWindowExW(0, kMenuHostClass, L"", WS_POPUP, 0, 0, 0, 0, nullptr,
                         nullptr, GetModuleHandle(nullptr), nullptr);
  return host;
}

}  // namespace

int ShowPopupMenu(int screen_x, int screen_y, const std::vector<MenuItem>& items) {
  HWND host = MenuHostWindow();
  if (host == nullptr || items.empty()) return 0;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return 0;

  for (const MenuItem& item : items) {
    if (item.separator) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    UINT flags = MF_STRING;
    if (item.checked) flags |= MF_CHECKED;
    AppendMenuW(menu, flags, static_cast<UINT_PTR>(item.id), item.label.c_str());
  }

  // 前台归属给隐藏宿主窗口（不是磁贴层），菜单才能点别处自动关
  SetForegroundWindow(host);
  const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, screen_x,
                                     screen_y, 0, host, nullptr);
  PostMessageW(host, WM_NULL, 0, 0);  // 官方 workaround：防菜单"粘"住
  DestroyMenu(menu);
  return command;
}

}  // namespace glance
