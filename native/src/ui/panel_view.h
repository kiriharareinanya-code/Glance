// 设置窗口的界面（自绘）。
//
// Flutter 版用 fluent_ui 画这套 Win11 风格界面；原生版没有控件库，这里手写
// 一小组够用的：分组卡片、滑块、分段选择、开关、导航项。控件都在 Paint 里
// **顺手记录命中区域**（hit_zones_），鼠标事件按这些区域判定——比起两套
// 布局代码，这种"画到哪就记到哪"的写法不会出现"看得见点不着"的错位。
//
// 页面按 Flutter 版 panel.dart 的分法：组件库 / 已放置 / 外观 / 其他 / 关于。
// 本轮先把框架和「外观」页做通（改一下立刻能在磁贴上看到效果），其余页逐个补。
#ifndef GLANCE_NATIVE_UI_PANEL_VIEW_H_
#define GLANCE_NATIVE_UI_PANEL_VIEW_H_

#include <functional>
#include <string>
#include <vector>

#include "core/app_state.h"
#include "render/renderer.h"

namespace glance {

// 面板要改设置、要关闭窗口，都得回到 App 去做（面板不持有 App）
struct PanelCallbacks {
  std::function<void()> on_settings_changed;  // 保存 state.json + 重建卡片 + 重绘磁贴
  std::function<void()> on_close;
  std::function<void()> on_minimize;
  std::function<void()> on_toggle_maximize;
};

class PanelView {
 public:
  enum class Page { kLibrary, kPlaced, kAppearance, kOther, kAbout };

  void SetContext(AppState* state, PanelCallbacks callbacks);
  // 磁贴那边改了设置（比如托盘重载）时刷新面板显示的值
  void Refresh() { needs_redraw_ = true; }

  void Paint(Renderer& renderer, float width, float height, float scale);
  void OnMouseMove(float x, float y, float scale);
  void OnMouseDown(float x, float y, float scale);
  void OnMouseUp(float x, float y, float scale);
  void OnMouseLeave();
  bool HitTitlebarButton(float x, float y, float scale) const;

 private:
  struct HitZone {
    enum class Kind { kNone, kNav, kSlider, kSegment, kToggle, kTitlebar } kind =
        Kind::kNone;
    int index = 0;  // 导航项 / 分段项序号
    int id = 0;     // 控件标识
    D2D1_RECT_F rect = {};
    float min_value = 0.0f;
    float max_value = 1.0f;
  };

  void PaintTitlebar(Renderer& r, float width, float scale);
  void PaintNav(Renderer& r, float height, float scale);
  void PaintPage(Renderer& r, float left, float width, float scale);
  void PaintAppearancePage(Renderer& r, float left, float top, float width,
                           float scale);
  void PaintPlaceholderPage(Renderer& r, const wchar_t* title,
                            const wchar_t* note, float left, float top,
                            float width, float scale);

  void ApplyChange();  // 通知 App：设置变了

  AppState* state_ = nullptr;
  PanelCallbacks callbacks_;
  Page page_ = Page::kAppearance;
  bool needs_redraw_ = true;

  float mouse_x_ = -1.0f;
  float mouse_y_ = -1.0f;
  int hover_zone_ = -1;    // hit_zones_ 的下标
  int drag_zone_ = -1;     // 正在拖的滑块
  std::vector<HitZone> hit_zones_;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_UI_PANEL_VIEW_H_
