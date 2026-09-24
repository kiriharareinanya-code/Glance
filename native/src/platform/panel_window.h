// 设置窗口（原生版）。
//
// Flutter 版的设置窗口是"任务栏里有按钮的无边框窗口、界面由 Flutter 画"
// （runner/view_window.h）。原生版没有第二个 Flutter 视图可用，所以窗口和
// 界面都得自己来：窗口是无边框 WS_POPUP + WS_THICKFRAME（保留阴影与可缩放），
// 通过 WM_NCCALCSIZE 返回 0 把非客户区吃掉，圆角交给 DWM（Win11）——
// 这套组合能同时拿到"无边框"和"系统阴影 + 原生圆角 + 任务栏按钮"。
//
// 界面由 ui/panel_view.h 自绘，渲染走独立的一套 Renderer（自己的
// swapchain + DComp），和磁贴那套互不干扰。
#ifndef GLANCE_NATIVE_PLATFORM_PANEL_WINDOW_H_
#define GLANCE_NATIVE_PLATFORM_PANEL_WINDOW_H_

#include <windows.h>

#include "render/renderer.h"

namespace glance {

class PanelView;  // ui/panel_view.h

class PanelWindow {
 public:
  PanelWindow() = default;
  ~PanelWindow();

  PanelWindow(const PanelWindow&) = delete;
  PanelWindow& operator=(const PanelWindow&) = delete;

  bool Create(PanelView* view, int logical_width, int logical_height);
  void Show();
  void Hide();
  void Destroy();
  bool visible() const;

  HWND handle() const { return hwnd_; }
  float dpi_scale() const { return dpi_scale_; }
  Renderer& renderer() { return renderer_; }

 private:
  static LRESULT CALLBACK WndProcThunk(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void RenderFrame();

  HWND hwnd_ = nullptr;
  Renderer renderer_;
  PanelView* view_ = nullptr;
  float dpi_scale_ = 1.0f;
  bool tracking_leave_ = false;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_PANEL_WINDOW_H_
