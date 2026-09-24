// 通用弹出菜单（带一个隐藏宿主窗口）。
//
// 为什么必须有宿主窗口：TrackPopupMenu 要求调用前 SetForegroundWindow，
// 否则菜单"点别处不关"、会粘在屏幕上。如果拿磁贴那层覆盖窗口当前台，
// 整块磁贴就被顶到所有窗口前面（用户报过"莫名其妙全局置顶"）。
// 所以这里自带一个不显示的宿主窗口承接前台归属。
#ifndef GLANCE_NATIVE_PLATFORM_POPUP_MENU_H_
#define GLANCE_NATIVE_PLATFORM_POPUP_MENU_H_

#include <windows.h>

#include <string>
#include <vector>

namespace glance {

struct MenuItem {
  int id = 0;
  std::wstring label;
  bool checked = false;
  bool separator = false;  // true 时只画一条分隔线，label/id 忽略
};

// 在屏幕坐标 (x, y) 弹出菜单，返回选中项 id；用户取消返回 0。
int ShowPopupMenu(int screen_x, int screen_y, const std::vector<MenuItem>& items);

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_POPUP_MENU_H_
