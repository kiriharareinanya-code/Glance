// 卡片背景用的"预模糊壁纸"。
//
// 为什么要预模糊而不是让 D2D 每帧实时模糊：卡片是静态的，壁纸在两次刷新
// 之间不会变；实时模糊等于每次重绘都做一遍全屏卷积，白烧 GPU。
// 抓一次、模糊一次、存成位图，卡片直接用位图刷子取对应区域——这是
// Windows 自己的 Acrylic 材质在桌面窗口上的做法。
//
// 抓的是桌面窗口（Progman / 承载图标的 WorkerW）而不是整屏截图：详见
// platform/desktop_capture.h——那样天然不会把磁贴自己拍进去，
// 避免"模糊图里套着上一帧模糊图"的自我反馈。
#ifndef GLANCE_NATIVE_RENDER_BACKDROP_H_
#define GLANCE_NATIVE_RENDER_BACKDROP_H_

#include <string>

#include "render/renderer.h"

namespace glance {

// 抓桌面 → 盒式模糊 → 交给渲染器当卡片背景。
// screen_w/h 是物理像素的屏幕尺寸。失败返回 false（卡片退回纯色底）。
bool PrepareBackdrop(Renderer& renderer, int screen_w, int screen_h);

// 从壁纸文件路径准备（动态壁纸软件抓不到桌面时的兜底），当前未使用，
// 保留接口以便后续接"换壁纸自动刷新"。
bool PrepareBackdropFromFile(Renderer& renderer, const std::wstring& path,
                             int screen_w, int screen_h);

}  // namespace glance

#endif  // GLANCE_NATIVE_RENDER_BACKDROP_H_
