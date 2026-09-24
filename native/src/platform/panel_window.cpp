#include "platform/panel_window.h"

#include <dwmapi.h>
#include <windowsx.h>  // GET_X_LPARAM / GET_Y_LPARAM

#include <algorithm>

#include "platform/log.h"
#include "ui/panel_view.h"

namespace glance {
namespace {

constexpr const wchar_t kPanelClass[] = L"GlanceNativePanel";
constexpr int kTitlebarHeightLogical = 40;  // 自绘标题栏高度（逻辑像素）

// Win10 没有圆角属性，调了会返回失败——不影响，当没有即可
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

}  // namespace

PanelWindow::~PanelWindow() { Destroy(); }

bool PanelWindow::Create(PanelView* view, int logical_width, int logical_height) {
  view_ = view;

  static bool registered = false;
  if (!registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = &PanelWindow::WndProcThunk;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    // 标题栏和内容区的背景都自绘，不给系统刷子
    wc.hbrBackground = nullptr;
    wc.lpszClassName = kPanelClass;
    if (!RegisterClassExW(&wc)) return false;
    registered = true;
  }

  dpi_scale_ = static_cast<float>(GetDpiForSystem()) / 96.0f;
  const int width = static_cast<int>(logical_width * dpi_scale_);
  const int height = static_cast<int>(logical_height * dpi_scale_);

  // 居中于主屏
  RECT work = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const int x = work.left + ((work.right - work.left) - width) / 2;
  const int y = work.top + ((work.bottom - work.top) - height) / 2;

  // WS_THICKFRAME 保留系统阴影与缩放边框；WS_CAPTION 的标题栏会被
  // WM_NCCALCSIZE 吃掉（这样就同时拿到无边框外观和原生阴影）。
  hwnd_ = CreateWindowExW(0, kPanelClass, L"设置",
                          WS_POPUP | WS_THICKFRAME | WS_CAPTION |
                              WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU,
                          x, y, width, height, nullptr, nullptr,
                          GetModuleHandle(nullptr), this);
  if (hwnd_ == nullptr) return false;

  // Win11 圆角（Win10 上这个调用会失败，忽略即可）
  const DWORD corner = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                        sizeof(corner));

  if (!renderer_.Initialize(hwnd_, width, height)) {
    Log(L"[panel] renderer init failed");
    Destroy();
    return false;
  }
  Log(L"[panel] created %dx%d scale=%.2f", width, height, dpi_scale_);
  return true;
}

void PanelWindow::Show() {
  if (hwnd_ == nullptr) return;
  ShowWindow(hwnd_, SW_SHOW);
  SetForegroundWindow(hwnd_);
  RenderFrame();
}

void PanelWindow::Hide() {
  if (hwnd_ != nullptr) ShowWindow(hwnd_, SW_HIDE);
}

bool PanelWindow::visible() const {
  return hwnd_ != nullptr && IsWindowVisible(hwnd_) != FALSE;
}

void PanelWindow::Destroy() {
  if (hwnd_ == nullptr) return;
  renderer_.Shutdown();
  DestroyWindow(hwnd_);
  hwnd_ = nullptr;
}

void PanelWindow::RenderFrame() {
  if (hwnd_ == nullptr || view_ == nullptr) return;
  RECT client = {};
  GetClientRect(hwnd_, &client);
  const float width = static_cast<float>(client.right - client.left);
  const float height = static_cast<float>(client.bottom - client.top);
  if (width <= 0 || height <= 0) return;

  if (!renderer_.BeginFrame()) return;
  view_->Paint(renderer_, width, height, dpi_scale_);
  renderer_.EndFrame();
}

LRESULT CALLBACK PanelWindow::WndProcThunk(HWND hwnd, UINT message, WPARAM wparam,
                                          LPARAM lparam) {
  PanelWindow* self = nullptr;
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = static_cast<PanelWindow*>(cs->lpCreateParams);
    self->hwnd_ = hwnd;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<PanelWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  }
  if (self != nullptr) return self->HandleMessage(message, wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT PanelWindow::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (wparam == FALSE) break;
      // 把整个窗口都当客户区：标题栏由我们自绘，系统那圈边框不要。
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      if (IsZoomed(hwnd_)) {
        // 最大化的一个坑：吃掉边框后窗口会盖住任务栏。按工作区裁一下。
        const HMONITOR monitor = MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
        MONITORINFO info = {};
        info.cbSize = sizeof(info);
        if (GetMonitorInfoW(monitor, &info)) {
          params->rgrc[0] = info.rcWork;
        }
      }
      return 0;
    }

    case WM_NCHITTEST: {
      const LRESULT base = DefWindowProcW(hwnd_, message, wparam, lparam);
      // 边缘留给系统做缩放
      if (base != HTCLIENT) return base;

      POINT cursor = {static_cast<short>(LOWORD(lparam)),
                      static_cast<short>(HIWORD(lparam))};
      ScreenToClient(hwnd_, &cursor);

      // 右上角三个按钮：先问 view 是不是按钮区（是就别当标题栏拖）
      if (view_ != nullptr) {
        const float x = static_cast<float>(cursor.x);
        const float y = static_cast<float>(cursor.y);
        if (view_->HitTitlebarButton(x, y, dpi_scale_)) return HTCLIENT;
      }
      if (cursor.y < static_cast<int>(kTitlebarHeightLogical * dpi_scale_)) {
        return HTCAPTION;  // 顶部一条 = 拖动窗口
      }
      return HTCLIENT;
    }

    case WM_MOUSEMOVE: {
      if (view_ != nullptr) {
        view_->OnMouseMove(static_cast<float>(GET_X_LPARAM(lparam)),
                           static_cast<float>(GET_Y_LPARAM(lparam)), dpi_scale_);
        RenderFrame();
      }
      if (!tracking_leave_) {
        TRACKMOUSEEVENT track = {};
        track.cbSize = sizeof(track);
        track.dwFlags = TME_LEAVE;
        track.hwndTrack = hwnd_;
        TrackMouseEvent(&track);
        tracking_leave_ = true;
      }
      return 0;
    }

    case WM_MOUSELEAVE: {
      tracking_leave_ = false;
      if (view_ != nullptr) {
        view_->OnMouseLeave();
        RenderFrame();
      }
      return 0;
    }

    case WM_LBUTTONDOWN: {
      if (view_ != nullptr) {
        view_->OnMouseDown(static_cast<float>(GET_X_LPARAM(lparam)),
                           static_cast<float>(GET_Y_LPARAM(lparam)), dpi_scale_);
        RenderFrame();
      }
      SetCapture(hwnd_);  // 拖滑块时指针移出窗口也要收得到
      return 0;
    }

    case WM_LBUTTONUP: {
      ReleaseCapture();
      if (view_ != nullptr) {
        view_->OnMouseUp(static_cast<float>(GET_X_LPARAM(lparam)),
                         static_cast<float>(GET_Y_LPARAM(lparam)), dpi_scale_);
        RenderFrame();
      }
      return 0;
    }

    case WM_CLOSE:
      // 关掉只是隐藏：下次从托盘菜单再打开不用重建窗口和渲染器
      Hide();
      return 0;

    case WM_SIZE: {
      renderer_.Resize(LOWORD(lparam), HIWORD(lparam));
      RenderFrame();
      return 0;
    }

    case WM_ERASEBKGND:
      return 1;  // 画面由 D3D 呈现，别让 GDI 擦背景

    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_DESTROY:
      hwnd_ = nullptr;
      return 0;

    default:
      break;
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

}  // namespace glance
