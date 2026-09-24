#include "app.h"

#include <windowsx.h>

#include <algorithm>
#include <cmath>

#include "cards/card_factory.h"
#include "platform/log.h"
#include "platform/desktop_band.h"
#include "render/backdrop.h"
#include "platform/private_fonts.h"

namespace glance {
namespace {

// 刷新节拍：时钟的分辨率是分钟，200ms 查一次既够灵敏又不费电。
constexpr UINT_PTR kTickTimerId = 1;
constexpr UINT kTickMs = 200;
// 桌面带看门狗：Win+D / 全屏程序退出后 shell 可能把桌面带抬到磁贴上面，
// 周期性检查并抬回来（Flutter 版同一个思路）
constexpr UINT_PTR kWatchdogTimerId = 2;
constexpr UINT kWatchdogMs = 3000;
// 指针移动超过这个距离（物理像素）才算拖拽，否则算点击。
// 手感阈值：太小会把手的抖动算成拖拽，太大又点不动
constexpr float kDragThreshold = 5.0f;

}  // namespace

bool App::Start(HINSTANCE /*instance*/) {
  Log(L"[app] start");
  if (!window_.CreateOverlay(L"Glance · 一瞥")) {
    Log(L"[app] CreateOverlay failed, GetLastError=%lu", GetLastError());
    return false;
  }
  Log(L"[app] window ok %dx%d dpi_scale=%.2f", window_.width(), window_.height(),
      window_.dpi_scale());

  if (!renderer_.Initialize(window_.handle(), window_.width(), window_.height())) {
    Log(L"[app] renderer init failed, GetLastError=%lu", GetLastError());
    window_.Destroy();
    return false;
  }
  Log(L"[app] renderer ok");

  // 时钟圆体：DWrite 私有字体集合（GDI 那套对 DWrite 不可见，见 renderer.h）
  const std::wstring font_path = FindClockFontPath();
  const bool font_ok = !font_path.empty() && renderer_.LoadPrivateFontFile(font_path);
  Log(L"[app] clock font loaded=%d path=%s", font_ok ? 1 : 0, font_path.c_str());

  window_.set_message_handler(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
             bool& handled) {
        return OnMessage(hwnd, message, wparam, lparam, handled);
      });

  LoadLayoutAndCards(window_.dpi_scale(), window_.width(), window_.height());
  window_.Show();
  SetTimer(window_.handle(), kTickTimerId, kTickMs, nullptr);
  SetTimer(window_.handle(), kWatchdogTimerId, kWatchdogMs, nullptr);
  tray_.SetTilesVisible(true);
  tray_.Create(L"Glance · 一瞥", [this](int command) { OnTrayCommand(command); });
  Log(L"[app] started, cards=%zu", cards_.size());
  return true;
}

void App::LoadLayoutAndCards(float dpi_scale, int screen_w, int screen_h) {
  // 卡片毛玻璃的底：抓桌面 + 预模糊。失败就退回纯色底（不是致命错）。
  PrepareBackdrop(renderer_, screen_w, screen_h);

  const std::wstring state_path = FindStateFilePath();
  if (!state_path.empty() && state_.LoadFromFile(state_path)) {
    // 外观跟着用户的设置走：圆角 / 材质 / 毛玻璃染色强度
    theme_.card_radius = state_.grid.card_radius;
    theme_.material = state_.grid.material;
    theme_.glass_tint = state_.grid.glass_tint;
  } else {
    // 读不到布局就用一张时钟兜底：宁可少显示，也不要空窗口让人以为没启动
    Log(L"[app] state.json not found, fallback to a single clock");
    CardData fallback;
    fallback.id = "clock-fallback";
    fallback.plugin_id = "clock";
    fallback.x = 400.0f;
    fallback.y = 60.0f;
    fallback.cols = 2;
    fallback.rows = 2;
    state_.cards.clear();
    state_.cards.push_back(std::move(fallback));
  }

  cards_.clear();
  for (const CardData& data : state_.cards) {
    auto card = CreateCardFor(data, state_.grid, dpi_scale);
    if (card) cards_.push_back(std::move(card));
  }
  Log(L"[app] built %zu cards", cards_.size());
  SyncHitRects();
}

void App::SyncHitRects() {
  const float radius =
      theme_.card_radius * (cards_.empty() ? 1.0f : cards_[0]->scale);
  std::vector<HitRect> rects;
  rects.reserve(cards_.size());
  for (const auto& card : cards_) {
    rects.push_back(HitRect{card->rect.left, card->rect.top,
                            card->rect.right - card->rect.left,
                            card->rect.bottom - card->rect.top, radius});
  }
  HitRegion::Instance().SetRects(std::move(rects));
}

bool App::SaveLayout() {
  const std::wstring path = FindStateFilePath();
  if (path.empty()) return false;

  JsonValue root;
  if (!ParseJson(ReadFileUtf8(path), &root)) {
    Log(L"[layout] 读不到 state.json，位置只在本次会话有效");
    return false;
  }
  JsonValue* cards = root.Find("cards");
  if (cards == nullptr || !cards->IsArray()) return false;

  const float scale = window_.dpi_scale();
  for (JsonValue& entry : cards->array) {
    JsonValue* id = entry.Find("id");
    if (id == nullptr) continue;
    const std::string card_id = id->StringOr("");
    for (const auto& card : cards_) {
      if (card->id != card_id) continue;
      const float logical_x = card->rect.left / scale;
      const float logical_y = card->rect.top / scale;
      if (JsonValue* x = entry.Find("x")) x->number_value = logical_x;
      if (JsonValue* y = entry.Find("y")) y->number_value = logical_y;
      for (CardData& data : state_.cards) {
        if (data.id == card_id) {
          data.x = logical_x;
          data.y = logical_y;
          break;
        }
      }
      break;
    }
  }

  // 先备份再写：写坏用户配置的代价远大于多一个 .bak 文件
  CopyFileW(path.c_str(), (path + L".bak").c_str(), FALSE);
  const bool ok = WriteFileUtf8(path, StringifyJson(root));
  Log(L"[layout] saved=%d", ok ? 1 : 0);
  return ok;
}


int App::Run() {
  MSG message = {};
  while (GetMessageW(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  tray_.Destroy();
  renderer_.Shutdown();
  return static_cast<int>(message.wParam);
}

int App::RenderToPng(const std::wstring& path) {
  // 尺寸取虚拟屏幕，和覆盖层一致；DPI 取系统值（没有窗口可问）。
  const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  const UINT dpi = GetDpiForSystem();
  const float scale = dpi > 0 ? static_cast<float>(dpi) / 96.0f : 1.0f;

  if (!renderer_.InitializeForOffscreen(width, height)) {
    Log(L"[capture] offscreen init failed");
    return 1;
  }
  const bool font_ok = !FindClockFontPath().empty() &&
                       renderer_.LoadPrivateFontFile(FindClockFontPath());
  Log(L"[capture] clock font loaded=%d", font_ok ? 1 : 0);

  // 用与窗口模式完全相同的布局路径：同读 state.json、同建卡片，
  // 抓出来的图才等于桌面上真实的样子。
  LoadLayoutAndCards(scale, width, height);

  // 等异步组件（天气）把首帧数据拿到：最多 10 秒，每 100ms 让卡片
  // Update 一次把后台结果落地。没这一步，导出的图里天气还停在
  // "正在获取…"，等于没验证到。
  int waited_ms = 0;
  for (; waited_ms < 10000; waited_ms += 100) {
    bool ready = true;
    for (auto& card : cards_) {
      card->Update();
      if (!card->ReadyForCapture()) ready = false;
    }
    if (ready) break;
    Sleep(100);
  }
  Log(L"[capture] async wait done (%d ms)", waited_ms);

  RenderFrame();
  const bool saved = renderer_.SaveTargetToPng(path);
  renderer_.Shutdown();
  Log(L"[capture] %s (%dx%d scale=%.2f)", saved ? L"saved" : L"failed", width,
      height, scale);
  return saved ? 0 : 1;
}

LRESULT App::OnMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                       bool& handled) {
  switch (message) {
    case WM_TIMER:
      if (wparam == kTickTimerId) {
        Tick();
        handled = true;
        return 0;
      }
      if (wparam == kWatchdogTimerId) {
        // 先开门闩再抬，否则会被自己的 WM_WINDOWPOSCHANGING 压回底部
        window_.set_allow_z_change(true);
        if (KeepAboveDesktopBand(window_.handle())) {
          Log(L"[watchdog] 桌面带盖住了磁贴，已抬回");
        }
        handled = true;
        return 0;
      }
      break;

    case WM_SIZE:
      // 尺寸变化（分辨率/多屏调整）时重建交换链缓冲，并重画一帧。
      renderer_.Resize(LOWORD(lparam), HIWORD(lparam));
      needs_frame_ = true;
      handled = true;
      return 0;

    case WM_NCHITTEST: {
      // 窗口覆盖整屏，但只有落在卡片上的点归自己：其余返回 HTTRANSPARENT，
      // 让系统把消息交给下面的窗口（桌面图标、别的程序照常可点）。
      // 拖拽期间整窗放开——快速拖动时指针会甩出卡片，那时若还按命中区裁剪，
      // 窗口收不到 WM_MOUSEMOVE，拖拽就断在半路。
      handled = true;
      if (drag_.active) return HTCLIENT;
      const int screen_x = static_cast<short>(LOWORD(lparam));
      const int screen_y = static_cast<short>(HIWORD(lparam));
      POINT point = {screen_x, screen_y};
      ScreenToClient(hwnd, &point);
      const bool inside = HitRegion::Instance().Contains(point.x, point.y);
      if (hit_log_count_ < 6) {
        ++hit_log_count_;
        Log(L"[hit] nchittest client=(%ld,%ld) inside=%d rects=%zu", point.x,
            point.y, inside ? 1 : 0, HitRegion::Instance().RectCount());
      }
      return inside ? HTCLIENT : HTTRANSPARENT;
    }

    case WM_LBUTTONDOWN: {
      const float x = static_cast<float>(GET_X_LPARAM(lparam));
      const float y = static_cast<float>(GET_Y_LPARAM(lparam));
      if (hit_log_count_ < 12) {
        ++hit_log_count_;
        Log(L"[hit] lbuttondown (%.0f,%.0f) cards=%zu", x, y, cards_.size());
      }
      // 后加的卡片画在上面：从后往前找第一个命中的
      for (auto it = cards_.rbegin(); it != cards_.rend(); ++it) {
        Card* card = it->get();
        if (x < card->rect.left || x > card->rect.right || y < card->rect.top ||
            y > card->rect.bottom) {
          continue;
        }
        drag_.active = true;
        drag_.card = card;
        drag_.grab_dx = x - card->rect.left;
        drag_.grab_dy = y - card->rect.top;
        drag_.press_x = x;
        drag_.press_y = y;
        drag_.moved = false;
        HitRegion::Instance().SetDragging(true);
        break;
      }
      handled = true;
      return 0;
    }

    case WM_MOUSEMOVE: {
      if (!drag_.active || drag_.card == nullptr) break;
      const float x = static_cast<float>(GET_X_LPARAM(lparam));
      const float y = static_cast<float>(GET_Y_LPARAM(lparam));
      if (!drag_.moved) {
        const float dx = x - drag_.press_x;
        const float dy = y - drag_.press_y;
        // 还没超过阈值：当成手抖，不算拖拽（否则点一下卡片会微微挪位）
        if (dx * dx + dy * dy < kDragThreshold * kDragThreshold) break;
        drag_.moved = true;
      }
      const float width = drag_.card->rect.right - drag_.card->rect.left;
      const float height = drag_.card->rect.bottom - drag_.card->rect.top;
      float new_x = x - drag_.grab_dx;
      float new_y = y - drag_.grab_dy;
      // 至少留 40 逻辑像素在屏幕内：拖出边界还能抓回来
      const float scale = window_.dpi_scale();
      const float keep = 40.0f * scale;
      const float screen_w = static_cast<float>(window_.width());
      const float screen_h = static_cast<float>(window_.height());
      new_x = std::max(-width + keep, std::min(new_x, screen_w - keep));
      new_y = std::max(-height + keep, std::min(new_y, screen_h - keep));
      drag_.card->rect = D2D1::RectF(new_x, new_y, new_x + width, new_y + height);
      needs_frame_ = true;
      // 拖拽必须跟手：每来一个移动消息就出一帧。原先只置 needs_frame_、
      // 等 200ms 的节拍定时器去画——那个节拍是给静态内容定的，拖动时只有
      // 5fps，手感就是"卡"。这里限一下最小间隔（≈120fps）防止鼠标
      // 高频上报时把 GPU 打满。
      const ULONGLONG now = GetTickCount64();
      if (now - last_drag_frame_ms_ >= 8) {
        last_drag_frame_ms_ = now;
        ++drag_frame_count_;
        RenderFrame();
      }
      handled = true;
      return 0;
    }

    case WM_LBUTTONUP: {
      if (!drag_.active || drag_.card == nullptr) break;

      // 没移动过 = 点击：交给卡片自己处理（翻月、勾选…）
      if (!drag_.moved) {
        const float x = static_cast<float>(GET_X_LPARAM(lparam));
        const float y = static_cast<float>(GET_Y_LPARAM(lparam));
        Card* card = drag_.card;
        const float local_x = (x - card->rect.left) / card->scale;
        const float local_y = (y - card->rect.top) / card->scale;
        if (card->OnClick(local_x, local_y)) needs_frame_ = true;
        HitRegion::Instance().SetDragging(false);
        drag_.active = false;
        drag_.card = nullptr;
        handled = true;
        return 0;
      }

      // 松手吸附到网格（对齐 snapEnabled 设置）
      if (state_.grid.snap_enabled) {
        const float scale = window_.dpi_scale();
        const float cell = state_.grid.cell * scale;
        const float width = drag_.card->rect.right - drag_.card->rect.left;
        const float height = drag_.card->rect.bottom - drag_.card->rect.top;
        const float snapped_x = std::round(drag_.card->rect.left / cell) * cell;
        const float snapped_y = std::round(drag_.card->rect.top / cell) * cell;
        drag_.card->rect = D2D1::RectF(snapped_x, snapped_y, snapped_x + width,
                                       snapped_y + height);
      }
      SyncHitRects();
      SaveLayout();
      Log(L"[drag] frames=%d", drag_frame_count_);
      drag_frame_count_ = 0;
      HitRegion::Instance().SetDragging(false);
      drag_.active = false;
      drag_.card = nullptr;
      needs_frame_ = true;
      handled = true;
      return 0;
    }


    default:
      break;
  }
  handled = false;
  return 0;
}

void App::OnTrayCommand(int command) {
  switch (command) {
    case kTrayToggleTiles:
      tiles_visible_ = !tiles_visible_;
      tray_.SetTilesVisible(tiles_visible_);
      if (tiles_visible_) {
        window_.Show();  // Show 里含贴底
      } else {
        ShowWindow(window_.handle(), SW_HIDE);
      }
      Log(L"[tray] tiles visible=%d", tiles_visible_ ? 1 : 0);
      break;

    case kTrayReload:
      // 重读 state.json 重建卡片：Flutter 版那边改了布局/设置，这里跟上
      Log(L"[tray] reload layout");
      cards_.clear();
      state_ = AppState{};
      theme_ = Theme{};
      LoadLayoutAndCards(window_.dpi_scale(), window_.width(), window_.height());
      // 重建卡片后重新贴底：否则可能停在重建瞬间的 Z 序位置
      window_.Show();
      needs_frame_ = true;
      break;

    case kTrayExit:
      PostQuitMessage(0);
      break;

    default:
      break;  // 0 = 用户点了菜单外面
  }
}

void App::Tick() {
  bool dirty = false;
  for (auto& card : cards_) {
    if (card->Update()) dirty = true;
  }
  if (!tick_logged_) {
    Log(L"[tick] first tick, dirty=%d needs_frame=%d", dirty ? 1 : 0,
        needs_frame_ ? 1 : 0);
    tick_logged_ = true;
  }
  if (dirty || needs_frame_) RenderFrame();
}

void App::RenderFrame() {
  if (!renderer_.BeginFrame()) {
    Log(L"[frame] BeginFrame failed");
    return;
  }
  for (auto& card : cards_) card->Paint(renderer_, theme_);
  renderer_.EndFrame();
  needs_frame_ = false;
  ++frame_count_;
  if (frame_count_ <= 3) Log(L"[frame] rendered #%d", frame_count_);
}

}  // namespace glance
