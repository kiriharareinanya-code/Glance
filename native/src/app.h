// 应用装配：窗口 + 渲染器 + 卡片集合 + 刷新节拍。
//
// 刷新策略是这块桌面层应用最要紧的一条：**内容不变就不出帧**。
// 时钟每分钟才变一次，若照 60fps 空转，一个常驻桌面的东西会一直占着
// GPU/CPU 和电池；所以走 200ms 检查一次、数据变了才画。
// 以后接动画（翻页、颜色过渡）时再引入"动画进行中临时提速"的机制。
#ifndef GLANCE_NATIVE_APP_H_
#define GLANCE_NATIVE_APP_H_

#include <windows.h>

#include <memory>
#include <vector>

#include "cards/card.h"
#include "platform/win_window.h"
#include "render/renderer.h"

namespace glance {

class App {
 public:
  App() = default;
  ~App() = default;

  App(const App&) = delete;
  App& operator=(const App&) = delete;

  bool Start(HINSTANCE instance);
  int Run();

  // 离屏渲染一帧并存成 PNG（`--capture <path>`）。
  // 返回 0 成功。用于无打扰的视觉验证：桌面被别的窗口盖着也能看到画面。
  int RenderToPng(const std::wstring& path);

 private:
  void BuildCards();
  void Tick();
  void RenderFrame();
  LRESULT OnMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                    bool& handled);

  WinWindow window_;
  Renderer renderer_;
  Theme theme_;
  std::vector<std::unique_ptr<Card>> cards_;
  bool needs_frame_ = true;
  // 诊断用：前几帧/首个 tick 落日志，定位"窗口是空的"这类问题。
  int frame_count_ = 0;
  bool tick_logged_ = false;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_APP_H_
