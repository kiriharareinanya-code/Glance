// 托盘图标（Shell_NotifyIcon）与菜单。
//
// Flutter 版的托盘在 Dart 侧（system_tray 插件）；原生版直接调 shell。
// 菜单项对齐 Flutter 版那套：显示/隐藏磁贴、重载布局、退出。
//
// **为什么要一个自己的隐藏窗口当宿主**：TrackPopupMenu 前必须
// SetForegroundWindow，否则菜单点了别处不会关。早先图省事拿磁贴那层覆盖窗口
// 当宿主，结果点一次托盘就把整块磁贴顶到前台——用户看到的是"莫名其妙全局
// 置顶"。现在宿主是这个不显示的小窗口，前台归属变了也影响不到磁贴层。
#ifndef GLANCE_NATIVE_PLATFORM_TRAY_H_
#define GLANCE_NATIVE_PLATFORM_TRAY_H_

#include <windows.h>

#include <functional>
#include <string>

namespace glance {

// 托盘菜单命令
enum TrayCommand {
  kTrayToggleTiles = 1,
  kTrayReload = 2,
  kTrayExit = 3,
  kTrayAutostart = 4,  // 这是个开关：菜单里显示勾选状态
  kTraySettings = 5,
};

class Tray {
 public:
  using CommandHandler = std::function<void(int command)>;

  ~Tray();

  Tray(const Tray&) = delete;
  Tray& operator=(const Tray&) = delete;
  Tray() = default;

  bool Create(const std::wstring& tooltip, CommandHandler handler);
  void Destroy();

  // 菜单文案跟着磁贴显隐状态走
  void SetTilesVisible(bool visible) { tiles_visible_ = visible; }

 private:
  static LRESULT CALLBACK WndProcThunk(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void ShowMenu();
  static std::wstring FindIconPath();

  static constexpr UINT kCallbackMessage = WM_APP + 1;

  HWND hwnd_ = nullptr;  // 宿主隐藏窗口（不是磁贴那层）
  HICON icon_ = nullptr;
  bool created_ = false;
  bool tiles_visible_ = true;
  CommandHandler handler_;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_TRAY_H_
