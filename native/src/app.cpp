#include "app.h"

#include "cards/clock_card.h"
#include "platform/log.h"
#include "platform/private_fonts.h"

namespace glance {
namespace {

// 刷新节拍：时钟的分辨率是分钟，200ms 查一次既够灵敏又不费电。
constexpr UINT_PTR kTickTimerId = 1;
constexpr UINT kTickMs = 200;

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

  BuildCards();
  window_.Show();
  SetTimer(window_.handle(), kTickTimerId, kTickMs, nullptr);
  Log(L"[app] started, cards=%zu", cards_.size());
  return true;
}

void App::BuildCards() {
  const float s = window_.dpi_scale();
  const float screen_w = static_cast<float>(window_.width());

  // 第一块：时钟，3x2。摆右上角，位置和 Flutter 版的默认布局同一区域，
  // 两个版本可以并排比对（布局持久化 / 拖拽在后续阶段做）。
  auto clock = std::make_unique<ClockCard>();
  const GridSize clock_grid{3, 2};
  const float card_w = GridWidth(clock_grid) * s;
  const float card_h = GridHeight(clock_grid) * s;
  const float margin = 48.0f * s;
  clock->scale = s;
  clock->rect = D2D1::RectF(screen_w - card_w - margin, margin,
                            screen_w - margin, margin + card_h);
  cards_.push_back(std::move(clock));
}

int App::Run() {
  MSG message = {};
  while (GetMessageW(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
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

  // 卡片布局和窗口模式共用 BuildCards 之外的同一条路径：这里直接摆，
  // 因为 capture 没有窗口句柄可传。
  auto clock = std::make_unique<ClockCard>();
  const GridSize grid{3, 2};
  const float card_w = GridWidth(grid) * scale;
  const float card_h = GridHeight(grid) * scale;
  const float margin = 48.0f * scale;
  clock->scale = scale;
  clock->rect = D2D1::RectF(static_cast<float>(width) - card_w - margin, margin,
                            static_cast<float>(width) - margin, margin + card_h);
  cards_.push_back(std::move(clock));

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
      break;

    case WM_SIZE:
      // 尺寸变化（分辨率/多屏调整）时重建交换链缓冲，并重画一帧。
      renderer_.Resize(LOWORD(lparam), HIWORD(lparam));
      needs_frame_ = true;
      handled = true;
      return 0;

    default:
      break;
  }
  handled = false;
  return 0;
}

void App::Tick() {
  bool dirty = false;
  for (auto& card : cards_) {
    if (card->Update()) dirty = true;
  }
  if (dirty || needs_frame_) RenderFrame();
}

void App::RenderFrame() {
  if (!renderer_.BeginFrame()) return;
  for (auto& card : cards_) card->Paint(renderer_, theme_);
  renderer_.EndFrame();
  needs_frame_ = false;
}

}  // namespace glance
