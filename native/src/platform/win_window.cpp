#include "platform/win_window.h"

#include "platform/log.h"

namespace glance {
namespace {

constexpr const wchar_t kClassName[] = L"GlanceNativeWindow";

// 调试期退出口：不抢焦点的窗口收不到键盘，注册全局热键最省事。
// Ctrl+Alt+Q 退出（正式版会换成托盘菜单）。
constexpr int kExitHotkeyId = 1;

}  // namespace

WinWindow::~WinWindow() { Destroy(); }

bool WinWindow::CreateOverlay(const std::wstring& title) {
  // 窗口类只注册一次。放在成员函数里是因为 lpfnWndProc 指向 private 的
  // 静态成员函数，类外部（匿名命名空间的辅助函数）拿不到。
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &WinWindow::WndProcThunk;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    if (!RegisterClassExW(&wc)) return false;
    class_registered = true;
  }

  // 虚拟屏幕（多显示器时是所有屏的并集）的物理像素范围。
  const int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  width_ = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  height_ = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
                              WS_EX_NOREDIRECTIONBITMAP,
                          kClassName, title.c_str(), WS_POPUP, x, y, width_,
                          height_, nullptr, nullptr, GetModuleHandle(nullptr),
                          this);
  if (!hwnd_) return false;

  // 内容全部由 DirectComposition 提供（见 render/renderer.cpp）。窗口自己
  // 不保留 DWM 重定向表面（WS_EX_NOREDIRECTIONBITMAP）：
  //   1. 省下一整块屏幕大小的位图内存——这正是原生版要赢的地方之一；
  //   2. 之前用 DwmEnableBlurBehindWindow 打开逐像素 alpha 的办法在这里
  //      已不需要：DComp 的合成结果直接带上 alpha。

  // 主屏 DPI 换算基准。Per-monitor v2 下每块屏可能不同，
  // 多屏混 DPI 的精细处理等有真实需求再做（Flutter 版也是这么起步的）。
  const UINT dpi = GetDpiForWindow(hwnd_);
  dpi_scale_ = dpi > 0 ? static_cast<float>(dpi) / 96.0f : 1.0f;

  if (!RegisterHotKey(hwnd_, kExitHotkeyId, MOD_CONTROL | MOD_ALT, 'Q')) {
    // 热键注册失败不致命（可能被别的程序占了），记下来继续跑。
    OutputDebugStringW(L"[glance] RegisterHotKey failed\n");
  }
  return true;
}

void WinWindow::Show() {
  if (!hwnd_) return;
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  // 贴底：桌面组件活在壁纸之上、所有普通窗口之下。
  SetWindowPos(hwnd_, HWND_BOTTOM, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void WinWindow::Destroy() {
  if (!hwnd_) return;
  UnregisterHotKey(hwnd_, kExitHotkeyId);
  DestroyWindow(hwnd_);
  hwnd_ = nullptr;
}

LRESULT CALLBACK WinWindow::WndProcThunk(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam) {
  WinWindow* self = nullptr;
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<WinWindow*>(cs->lpCreateParams);
    self->hwnd_ = hwnd;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<WinWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self) return self->HandleMessage(message, wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT WinWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  bool handled = true;

  switch (message) {
    case WM_ERASEBKGND:
      // 画面全部由 D3D 呈现，GDI 擦背景只会闪一下白的。
      return 1;

    case WM_PAINT: {
      // 同理：ValidateRect 清掉脏区，真实内容等下一次 present。
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_SIZE:
      width_ = LOWORD(lparam);
      height_ = HIWORD(lparam);
      break;

    case WM_WINDOWPOSCHANGING: {
      // 把自己按回 Z 序最底。少了这一条，任何 SetWindowPos / 激活操作
      // 都可能把整块覆盖层抬到用户窗口前面，桌面直接被盖住。
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      pos->hwndInsertAfter = HWND_BOTTOM;
      pos->flags &= ~SWP_NOZORDER;
      return 0;
    }

    case WM_HOTKEY:
      if (wparam == kExitHotkeyId) {
        PostQuitMessage(0);
        return 0;
      }
      break;

    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;

    default:
      handled = false;
      break;
  }

  if (handler_) {
    const LRESULT result = handler_ ? handler_(hwnd_, message, wparam, lparam, handled) : 0;
    if (handled) return result;
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

}  // namespace glance
