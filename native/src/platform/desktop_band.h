// 桌面带（图标层）与看门狗。
//
// 磁贴是"贴着桌面走"的一层：正常情况下它贴在桌面带之上、所有普通窗口之下。
// 但用户按 Win+D（显示桌面）或某些全屏程序退出时，shell 会把桌面带抬到
// 最顶——磁贴就被壁纸+图标盖住、看起来"消失"了。看门狗定期检查 Z 序，
// 一旦发现桌面带跑到前面就把磁贴插回桌面带正上方。
//
// FindDesktopBand 从 Flutter 版 utils.cpp 搬，KeepAboveDesktopBand 从
// flutter_window.cpp 搬——那边的注释解释了为什么认的是承载 SHELLDLL_DefView
// 的那个窗口（Wallpaper Engine 这类动态壁纸会把图标层挪进 WorkerW）。
#ifndef GLANCE_NATIVE_PLATFORM_DESKTOP_BAND_H_
#define GLANCE_NATIVE_PLATFORM_DESKTOP_BAND_H_

#include <windows.h>

namespace glance {

// 承载桌面图标层的顶层窗口（Progman 或某个 WorkerW）；找不到返回 nullptr
HWND FindDesktopBand();

// 若桌面带正盖在 hwnd 之上，把 hwnd 插到桌面带正上方。
// 返回 true 表示这次真的抬了一下（供日志判断）。
bool KeepAboveDesktopBand(HWND hwnd);

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_DESKTOP_BAND_H_
