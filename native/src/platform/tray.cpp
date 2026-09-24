#include "platform/tray.h"

#include <shellapi.h>

#include "platform/autostart.h"
#include "platform/log.h"

namespace glance {
namespace {

constexpr const wchar_t kTrayHostClass[] = L"GlanceNativeTrayHost";

}  // namespace

Tray::~Tray() { Destroy(); }

std::wstring Tray::FindIconPath() {
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

bool Tray::Create(const std::wstring& tooltip, CommandHandler handler) {
  if (created_) return false;
  handler_ = std::move(handler);

  // 宿主窗口类（只注册一次）
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &Tray::WndProcThunk;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = kTrayHostClass;
    if (!RegisterClassExW(&wc)) return false;
    class_registered = true;
  }

  // 不显示的宿主窗口：只收托盘回调消息、只当菜单宿主
  hwnd_ = CreateWindowExW(0, kTrayHostClass, L"", WS_POPUP, 0, 0, 0, 0, nullptr,
                          nullptr, GetModuleHandle(nullptr), this);
  if (hwnd_ == nullptr) return false;

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
  Log(L"[tray] created=%d host=0x%p icon=%s", created_ ? 1 : 0, hwnd_,
      icon_path.empty() ? L"(system)" : icon_path.c_str());
  if (!created_) Destroy();
  return created_;
}

void Tray::Destroy() {
  if (created_) {
    NOTIFYICONDATAW data = {};
    data.cbSize = sizeof(data);
    data.hWnd = hwnd_;
    data.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &data);
    created_ = false;
  }
  if (icon_ != nullptr) {
    DestroyIcon(icon_);
    icon_ = nullptr;
  }
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void Tray::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kTraySettings, L"设置…");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayToggleTiles,
              tiles_visible_ ? L"隐藏磁贴" : L"显示磁贴");
  AppendMenuW(menu, MF_STRING, kTrayReload, L"重载布局");
  AppendMenuW(menu, IsAutostartEnabled() ? MF_CHECKED : MF_UNCHECKED,
              kTrayAutostart, L"开机自启");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExit, L"退出 Glance");

  POINT cursor = {};
  GetCursorPos(&cursor);
  // 前台归属给**宿主窗口**（不是磁贴层）：菜单才能"点别处自动关"，
  // 同时不会把整块磁贴顶到前台。
  SetForegroundWindow(hwnd_);
  const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, cursor.x,
                                     cursor.y, 0, hwnd_, nullptr);
  // 官方 workaround：菜单关闭后补一条消息，避免菜单偶尔"粘"在屏幕上
  PostMessageW(hwnd_, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command != 0 && handler_) handler_(command);
}

LRESULT CALLBACK Tray::WndProcThunk(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
  Tray* self = nullptr;
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<Tray*>(cs->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<Tray*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self != nullptr) return self->HandleMessage(message, wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT Tray::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kCallbackMessage) {
    const UINT event = LOWORD(lparam);
    if (event == WM_RBUTTONUP || event == WM_CONTEXTMENU) {
      ShowMenu();
      return 0;
    }
    if (event == WM_LBUTTONUP) {
      // 左键直接切换显隐，不用点进菜单
      if (handler_) handler_(kTrayToggleTiles);
      return 0;
    }
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

}  // namespace glance
