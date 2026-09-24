// 托盘图标（Shell_NotifyIcon）与菜单。
//
// Flutter 版的托盘在 Dart 侧（system_tray 插件）；原生版没有插件层，
// 直接调 shell 的 API。菜单项对齐 Flutter 版那套：显示/隐藏磁贴、重载布局、
// 退出。设置窗口还没做，相应项先不出现而不是摆一个点不动的灰项。
//
// 图标从 Flutter 版的 app_icon.ico 加载（逐级往上找），找不到就用系统
// 默认图标——不为了一个托盘图标去内嵌资源节。
#ifndef GLANCE_NATIVE_PLATFORM_TRAY_H_
#define GLANCE_NATIVE_PLATFORM_TRAY_H_

#include <windows.h>

#include <string>

namespace glance {

// 托盘菜单命令（窗口过程把它转给 App）
enum TrayCommand {
  kTrayToggleTiles = 1,
  kTrayReload = 2,
  kTrayExit = 3,
};

class Tray {
 public:
  // 托盘的回调消息：窗口过程收到它说明用户点了图标
  static constexpr UINT kCallbackMessage = WM_APP + 1;

  bool Create(HWND hwnd, const std::wstring& tooltip);
  void Destroy();

  // 弹出右键菜单，返回选中的命令（0 = 用户取消）
  int ShowMenu(bool tiles_visible);

 private:
  HWND hwnd_ = nullptr;
  HICON icon_ = nullptr;
  bool created_ = false;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_TRAY_H_
