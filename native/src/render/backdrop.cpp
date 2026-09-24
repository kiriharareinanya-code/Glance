#include "render/backdrop.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include "core/json.h"
#include "platform/desktop_capture.h"
#include "platform/log.h"

namespace glance {
namespace {

int ClampInt(int value, int lo, int hi) {
  return value < lo ? lo : (value > hi ? hi : value);
}

// 分离式盒式模糊（水平一遍、垂直一遍）。跑两轮小半径近似高斯——
// 单轮盒式的边缘会有明显的方块感，两轮叠起来就看不出来了。
void BoxBlurBgra(std::vector<uint8_t>& pixels, int width, int height, int radius) {
  if (radius < 1 || width <= 1 || height <= 1) return;
  const int window = radius * 2 + 1;
  std::vector<uint8_t> temp(pixels.size());

  // 水平
  for (int y = 0; y < height; ++y) {
    const size_t row = static_cast<size_t>(y) * width;
    for (int channel = 0; channel < 3; ++channel) {
      int sum = 0;
      for (int x = -radius; x <= radius; ++x) {
        sum += pixels[(row + ClampInt(x, 0, width - 1)) * 4 + channel];
      }
      for (int x = 0; x < width; ++x) {
        temp[(row + x) * 4 + channel] = static_cast<uint8_t>(sum / window);
        const int add = ClampInt(x + radius + 1, 0, width - 1);
        const int sub = ClampInt(x - radius, 0, width - 1);
        sum += pixels[(row + add) * 4 + channel] -
               pixels[(row + sub) * 4 + channel];
      }
    }
    for (int x = 0; x < width; ++x) temp[(row + x) * 4 + 3] = 255;
  }

  // 垂直
  for (int x = 0; x < width; ++x) {
    for (int channel = 0; channel < 3; ++channel) {
      int sum = 0;
      for (int y = -radius; y <= radius; ++y) {
        sum += temp[(static_cast<size_t>(ClampInt(y, 0, height - 1)) * width + x) * 4 +
                    channel];
      }
      for (int y = 0; y < height; ++y) {
        pixels[(static_cast<size_t>(y) * width + x) * 4 + channel] =
            static_cast<uint8_t>(sum / window);
        const int add = ClampInt(y + radius + 1, 0, height - 1);
        const int sub = ClampInt(y - radius, 0, height - 1);
        sum += temp[(static_cast<size_t>(add) * width + x) * 4 + channel] -
               temp[(static_cast<size_t>(sub) * width + x) * 4 + channel];
      }
    }
    for (int y = 0; y < height; ++y) {
      pixels[(static_cast<size_t>(y) * width + x) * 4 + 3] = 255;
    }
  }
}

}  // namespace

bool PrepareBackdrop(Renderer& renderer, int screen_w, int screen_h) {
  if (screen_w <= 0 || screen_h <= 0) return false;

  // 抓 1/4 尺寸：模糊图放大回去看不出差别，但像素量少 16 倍，
  // 盒式模糊的开销从几十毫秒掉到几毫秒。
  const int blur_w = std::max(16, screen_w / 4);
  const int blur_h = std::max(16, screen_h / 4);

  std::vector<uint8_t> pixels = CaptureDesktop(blur_w, blur_h);
  if (pixels.size() < static_cast<size_t>(blur_w) * blur_h * 4) {
    Log(L"[backdrop] desktop capture failed (%dx%d)", blur_w, blur_h);
    return false;
  }

  BoxBlurBgra(pixels, blur_w, blur_h, 5);
  BoxBlurBgra(pixels, blur_w, blur_h, 3);

  const bool ok = renderer.SetBackdropFromPixels(pixels.data(), blur_w, blur_h,
                                                 screen_w, screen_h);
  Log(L"[backdrop] %dx%d -> %dx%d: %s", blur_w, blur_h, screen_w, screen_h,
      ok ? L"ok" : L"failed");
  return ok;
}

bool PrepareBackdropFromFile(Renderer& renderer, const std::wstring& path,
                             int screen_w, int screen_h) {
  (void)renderer;
  (void)path;
  (void)screen_w;
  (void)screen_h;
  return false;  // 兜底路径还没接（动态壁纸场景优先，静态壁纸用抓屏也够）
}

}  // namespace glance
