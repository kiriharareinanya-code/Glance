#include "app.h"

#include "cards/card_factory.h"
#include "platform/log.h"
#include "render/backdrop.h"
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

  LoadLayoutAndCards(window_.dpi_scale(), window_.width(), window_.height());
  window_.Show();
  SetTimer(window_.handle(), kTickTimerId, kTickMs, nullptr);
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
