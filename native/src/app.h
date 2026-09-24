// 应用装配：窗口 + 渲染器 + 卡片集合 + 刷新节拍 + 鼠标交互。
//
// 刷新策略是这块桌面层应用最要紧的一条：**内容不变就不出帧**。
// 时钟每分钟才变一次，若照 60fps 空转，一个常驻桌面的东西会一直占着
// GPU/CPU 和电池；所以走 200ms 检查一次、数据变了才画。
// 以后接动画（翻页、颜色过渡）时再引入"动画进行中临时提速"的机制。
//
// 鼠标交互靠命中区（platform/hit_region.h）：窗口覆盖整屏，只有落在卡片
// 上的点才归自己，其余穿透给桌面——否则桌面图标就点不着了。
#ifndef GLANCE_NATIVE_APP_H_
#define GLANCE_NATIVE_APP_H_

#include <windows.h>

#include <memory>
#include <vector>

#include "cards/card.h"
#include "core/app_state.h"
#include "platform/hit_region.h"
#include "platform/popup_menu.h"
#include "platform/popup_menu.h"
#include "platform/popup_menu.h"
#include "platform/tray.h"
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
  // 读 state.json（与 Flutter 版共享同一份）并按真实布局建卡片。
  // 窗口模式与 --capture 共用，两条路的画面才可比。
  void LoadLayoutAndCards(float dpi_scale, int screen_w, int screen_h);

  // 把卡片矩形推给命中区（拖拽期间由命中区整体放开）
  void SyncHitRects();

  // 把当前卡片位置写回 state.json（先备份 .bak，再原子替换）
  bool SaveLayout();

  // 托盘菜单命令（显示/隐藏磁贴、重载布局、退出）
  void OnTrayCommand(int command);

  // 卡片右键菜单：改尺寸 / 置于顶层 / 移除
  void ShowCardMenu(size_t card_index, int screen_x, int screen_y);
  CardData* FindCardData(const std::string& id);



  void Tick();
  void RenderFrame();
  LRESULT OnMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                    bool& handled);

  struct DragState {
    bool active = false;
    Card* card = nullptr;
    float grab_dx = 0.0f;  // 抓取点相对卡片左上角（物理像素）
    float grab_dy = 0.0f;
    float press_x = 0.0f;  // 按下点：用来区分"点击"和"拖拽"
    float press_y = 0.0f;
    bool moved = false;    // 移动超过阈值才算拖拽
  };

  WinWindow window_;
  Renderer renderer_;
  AppState state_;
  Theme theme_;
  std::vector<std::unique_ptr<Card>> cards_;
  DragState drag_;
  Tray tray_;
  bool tiles_visible_ = true;
  bool needs_frame_ = true;
  // 诊断用：前几帧/首个 tick 落日志，定位"窗口是空的"这类问题。
  int frame_count_ = 0;
  int hit_log_count_ = 0;  // 诊断：只记前几次命中测试
  unsigned long long last_drag_frame_ms_ = 0;  // 拖拽出帧的最小间隔控制
  int drag_frame_count_ = 0;                   // 诊断：一次拖拽出了多少帧
  bool tick_logged_ = false;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_APP_H_
