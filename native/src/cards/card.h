// 卡片层：所有磁贴的公共契约。
//
// 网格公式、默认值、圆角、主题色全部对齐 Flutter 版（lib/core/grid.dart、
// lib/ui/card_view.dart、lib/widgets/builtin/*）：同一份布局配置在两个版本
// 里必须摆出一样的卡片，否则没法并排对比、迁移时会全乱。
//
// 缩放语义也和 Flutter 版一致（见 lib/widgets/builtin_card_body.dart）：
// 组件内部**按基线尺寸排版**，再整体乘 scale 得到实际物理尺寸。
// 150% DPI 下 scale = 1.5，文字与间距等比例放大，不会出现半像素毛边。
#ifndef GLANCE_NATIVE_CARDS_CARD_H_
#define GLANCE_NATIVE_CARDS_CARD_H_

#include <d2d1.h>

#include <string>

#include "render/renderer.h"

namespace glance {

// 网格尺寸系统（对应 lib/core/grid.dart）
constexpr float kDefaultCell = 112.0f;
constexpr float kDefaultGap = 12.0f;

struct GridSize {
  int cols = 1;
  int rows = 1;
};

inline float GridWidth(const GridSize& g, float cell = kDefaultCell,
                       float gap = kDefaultGap) {
  return g.cols * cell + (g.cols - 1) * gap;
}

inline float GridHeight(const GridSize& g, float cell = kDefaultCell,
                        float gap = kDefaultGap) {
  return g.rows * cell + (g.rows - 1) * gap;
}

// 卡片外观。数值取自 Flutter 版深色主题的实测观感，不是拍脑袋。
// 三种材质（对齐 Flutter 版 card_view.dart）：
//   opaque  纯色不透明卡
//   mica    薄色板叠壁纸
//   acrylic 毛玻璃：预模糊壁纸 + glassTint 染色（默认材质）
struct Theme {
  Color card_bg = Color::Rgba(0.075f, 0.086f, 0.105f, 0.82f);
  Color fg = Color::Rgba(1.0f, 1.0f, 1.0f, 0.96f);
  Color fg_muted = Color::Rgba(1.0f, 1.0f, 1.0f, 0.55f);
  Color accent = Color::Hex(0x7CE38B);
  float card_radius = 18.0f;  // 逻辑像素
  float glass_tint = 0.0f;    // acrylic 的染色不透明度（0 = 纯模糊壁纸）
  std::string material = "acrylic";

  // 卡片染色层的不透明度：opaque 直接盖住壁纸，acrylic/mica 用用户设的强度
  float CardTintAlpha() const {
    return material == "opaque" ? 1.0f : glass_tint;
  }
};

class Card {
 public:
  virtual ~Card() = default;

  Card(const Card&) = delete;
  Card& operator=(const Card&) = delete;

  // 与 state.json 对应的身份（命中、拖拽、右键设置都要靠它找回来）
  std::string id;
  std::string plugin_id;

  // 物理像素矩形（已含 DPI 缩放）
  D2D1_RECT_F rect = D2D1::RectF(0, 0, 0, 0);

  // 基线 → 实际的缩放系数（150% DPI 时为 1.5）
  float scale = 1.0f;

  // 刷新数据；返回 true 表示画面需要重绘。
  // 时钟靠它做到"秒不动就不重绘"——静态桌面组件一秒一帧都嫌多。
  virtual bool Update() { return false; }

  virtual void Paint(Renderer& renderer, const Theme& theme) = 0;

  // 卡片内的点击。坐标是**相对卡片左上角的逻辑像素**（调用方已除掉
  // scale）。返回 true 表示吃掉了这次点击（调用方会重绘一帧）。
  //
  // 只在"按下 → 松开之间指针没怎么动"时调用；移动超过阈值就当成拖拽，
  // 不走这里（见 App 的 WM_LBUTTONUP）。
  virtual bool OnClick(float /*local_x*/, float /*local_y*/) { return false; }

  // 无窗口/离屏导出（--capture）时用：异步取数的组件（天气）数据没到
  // 就返回 false，调用方等一会儿再抓帧，免得导出的图里只有"正在获取…"。
  virtual bool ReadyForCapture() const { return true; }

  // 工厂把 id / plugin_id / rect 都填好之后调一次。
  // 需要按卡片 id 去读自己缓存数据的组件（天气读 plugindata）在这里做，
  // 不能在构造函数里做——那时 id 还是空的。
  virtual void OnConfigured() {}

 protected:
  Card() = default;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CARD_H_
