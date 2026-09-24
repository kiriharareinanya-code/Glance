// 桌面层窗口：一块覆盖整个虚拟屏幕、贴在最底、逐像素透明的画面。
//
// 这几条设置都是从 Flutter 版 runner（windows/runner/win32_window.cpp）踩过
// 的坑里搬过来的，不是随手写的：
//   1. WS_EX_TOOLWINDOW —— 不进任务栏、不进 Alt+Tab。桌面组件不该在那出现。
//   2. WS_EX_NOACTIVATE —— 点它不抢焦点。用户在别处打字时点一下磁贴，
//      输入焦点不能跑到磁贴上来。
//   3. WS_EX_NOREDIRECTIONBITMAP —— 不保留 DWM 重定向表面：省下一整块屏幕
//      大小的位图内存（原生版要赢的地方之一），内容由 DirectComposition
//      直接合成，逐像素 alpha 也从此来（见 render/renderer.cpp）。
//   4. 全屏按虚拟屏幕的**物理像素**取，不做 DPI 缩放：覆盖层要对齐整块屏，
//      缩放交给卡片布局自己算（dpi_scale）。
#ifndef GLANCE_NATIVE_PLATFORM_WIN_WINDOW_H_
#define GLANCE_NATIVE_PLATFORM_WIN_WINDOW_H_

#include <windows.h>

#include <functional>
#include <string>

namespace glance {

class WinWindow {
 public:
  // handled 置 true 表示消息已被处理，不要再走 DefWindowProc。
  using MessageHandler = std::function<LRESULT(HWND, UINT, WPARAM, LPARAM, bool&)>;

  WinWindow() = default;
  ~WinWindow();

  WinWindow(const WinWindow&) = delete;
  WinWindow& operator=(const WinWindow&) = delete;

  // 创建覆盖虚拟屏幕的桌面层窗口。失败返回 false。
  bool CreateOverlay(const std::wstring& title);

  void Show();
  void Destroy();

  HWND handle() const { return hwnd_; }
  int width() const { return width_; }
  int height() const { return height_; }

  // 系统 DPI / 96。150% 缩放时是 1.5。卡片布局用它把逻辑尺寸换算成物理像素。
  float dpi_scale() const { return dpi_scale_; }

  void set_message_handler(MessageHandler handler) { handler_ = std::move(handler); }

  // 看门狗要把磁贴从桌面带下面抬回来时先开门闩：窗口过程默认会把任何
  // Z 序改动压回最底（防止被别的操作顶上去），抬升那一次必须放行。
  void set_allow_z_change(bool allow) { allow_z_change_ = allow; }

 private:
  static LRESULT CALLBACK WndProcThunk(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  HWND hwnd_ = nullptr;
  int width_ = 0;
  int height_ = 0;
  float dpi_scale_ = 1.0f;
  bool allow_z_change_ = false;
  MessageHandler handler_;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_WIN_WINDOW_H_
