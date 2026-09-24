// 渲染层：D3D11 → DXGI flip-model 交换链 → DirectComposition → D2D 设备上下文。
//
// 为什么不用 ID2D1HwndRenderTarget（看着更短的写法）：
//   1. 拿不到 flip-model 交换链，低功耗呈现走不通；
//   2. resize / DPI 变化下的位图重建它自己管不明白，迟早要重写。
//
// 为什么要 DirectComposition 而不是 CreateSwapChainForHwnd：
//   桌面 Win32 的 hwnd 交换链**不支持预乘 alpha**，传
//   DXGI_ALPHA_MODE_PREMULTIPLIED 会直接失败（DXGI_ERROR_INVALID_CALL，
//   实测 0x887A0001）。逐像素透明的正道是 CreateSwapChainForComposition
//   + DComp 视觉树——WinUI 3 走的也是这条线，以后加动效/系统模糊都在上面。
//
// 坐标与字号全部按**物理像素**计：DeviceContext 的 DPI 固定 96，
// 150% 缩放的换算由调用方乘 dpi_scale 完成，避免两处各缩一次。
#ifndef GLANCE_NATIVE_RENDER_RENDERER_H_
#define GLANCE_NATIVE_RENDER_RENDERER_H_

#include <windows.h>
#include <d2d1.h>
#include <d2d1_1.h>  // ID2D1Device / ID2D1DeviceContext：D2D 从 HWND 目标升级到设备上下文
#include <d3d11.h>
#include <dcomp.h>
#include <dwrite.h>
#include <dwrite_3.h>  // IDWriteFactory5 / IDWriteFontSetBuilder：私有字体集合
#include <dxgi1_2.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <string>

namespace glance {

using Microsoft::WRL::ComPtr;

struct Color {
  float r = 1, g = 1, b = 1, a = 1;

  static constexpr Color Rgba(float r, float g, float b, float a) {
    return Color{r, g, b, a};
  }
  static constexpr Color Hex(unsigned int rgb, float alpha = 1.0f) {
    return Color{((rgb >> 16) & 0xFF) / 255.0f, ((rgb >> 8) & 0xFF) / 255.0f,
                 (rgb & 0xFF) / 255.0f, alpha};
  }
  Color WithAlpha(float alpha) const { return Color{r, g, b, alpha}; }
};

// 文字排版规格。字号单位是物理像素。
struct TextStyle {
  float size = 14.0f;
  DWRITE_FONT_WEIGHT weight = DWRITE_FONT_WEIGHT_NORMAL;
  const wchar_t* family = L"Segoe UI";
  DWRITE_TEXT_ALIGNMENT align = DWRITE_TEXT_ALIGNMENT_LEADING;
  DWRITE_PARAGRAPH_ALIGNMENT valign = DWRITE_PARAGRAPH_ALIGNMENT_NEAR;
  bool wrap = false;
  // 是否用私有字体集合（时钟的圆体走这条）。系统字体保持 false。
  bool use_private_font = false;
};

class Renderer {
 public:
  Renderer() = default;
  ~Renderer();

  Renderer(const Renderer&) = delete;
  Renderer& operator=(const Renderer&) = delete;

  bool Initialize(HWND hwnd, int width, int height);
  void Shutdown();
  void Resize(int width, int height);

  // 离屏模式：不开窗口、不建交换链，渲染目标是自己的 D3D 纹理。
  //
  // 存在的意义是**视觉验证不依赖屏幕**：桌面上可能盖着别的窗口
  // （QQ 全屏置顶时 PrintWindow 也抓不到 DComp 内容），而组件渲染对不对
  // 必须能随时检查。`--capture <png>` 走的就是这条路。
  //
  // 目标不能用 WIC 位图：CreateBitmapFromWicBitmap 建的是 WIC 位图的**副本**，
  // 画上去不会回写（第一版就这么写的，导出全是透明）。正道是画进 D3D 纹理、
  // 再经 staging 纹理读回 CPU，交给 WIC 编码。
  bool InitializeForOffscreen(int width, int height);
  bool SaveTargetToPng(const std::wstring& path);

  // 一帧：BeginFrame 清成全透明，画完 EndFrame 呈现（垂直同步）。
  bool BeginFrame();
  void EndFrame();

  void FillRoundRect(const D2D1_RECT_F& rect, float radius, const Color& color);
  void FillRect(const D2D1_RECT_F& rect, const Color& color);

  // 在 rect 内绘制文字。format 由 CreateTextFormat 创建并被本类持有复用。
  void DrawText(const std::wstring& text, IDWriteTextFormat* format,
                const D2D1_RECT_F& rect, const Color& color);

  // 按样式取（并缓存）一个排版格式。相同样式重复调用返回同一个对象。
  IDWriteTextFormat* TextFormat(const TextStyle& style);

  // 从 ttf 文件建私有字体集合（时钟的圆体）。
  //
  // 不能用 GDI 的 AddFontResourceEx + 族名硬拼：那条路加载的字体**对
  // DirectWrite 不可见**（实测：GDI 报 added=2，DWrite 照旧回退系统字体）。
  // DWrite 侧的正道是 Factory5 的 FontSetBuilder —— 直接引用字体文件生成
  // 集合，CreateTextFormat 时把集合传进去。
  bool LoadPrivateFontFile(const std::wstring& path);

  int width() const { return width_; }
  int height() const { return height_; }

 private:
  bool CreateDrawTargetTexture();
  void ReleaseDrawTarget();
  bool CreateBaseFactories();
  bool CreateDeviceResources();
  bool CreateSwapChain(HWND hwnd);

  // CreateDevice 是 ID2D1Factory1 上的方法（d2d1_1.h），基类没有。
  ComPtr<ID2D1Factory1> d2d_factory_;
  ComPtr<IDWriteFactory> dwrite_factory_;
  ComPtr<IDWriteFontCollection1> private_font_collection_;
  ComPtr<IWICImagingFactory> wic_factory_;
  ComPtr<ID3D11Device> d3d_device_;
  ComPtr<ID3D11DeviceContext> d3d_context_;
  ComPtr<IDXGISwapChain1> swap_chain_;
  ComPtr<ID2D1Device> d2d_device_;
  ComPtr<ID2D1DeviceContext> d2d_context_;
  ComPtr<ID2D1Bitmap1> target_bitmap_;
  // 绘制目标纹理：窗口模式与 --capture 共用同一条渲染路径（见 .cpp 的说明）
  ComPtr<ID3D11Texture2D> draw_target_texture_;
  ComPtr<ID2D1SolidColorBrush> brush_;

  // DirectComposition：交换链的内容经视觉树合成到窗口上，
  // 这条路才允许逐像素 alpha。
  ComPtr<IDCompositionDevice> dcomp_device_;
  ComPtr<IDCompositionTarget> dcomp_target_;
  ComPtr<IDCompositionVisual> dcomp_visual_;

  // 排版格式缓存：时钟每分钟重绘，每帧新建 TextFormat 会白白吃内存。
  ComPtr<IDWriteTextFormat> cached_formats_[8];
  TextStyle cached_styles_[8];
  int cached_count_ = 0;

  int width_ = 0;
  int height_ = 0;
  // BeginDraw 期间到来的 resize 请求，暂存到帧之间处理
  int pending_width_ = 0;
  int pending_height_ = 0;
  bool drawing_ = false;
  int present_count_ = 0;  // 诊断用：只记前几次 Present 的结果
};

}  // namespace glance

#endif  // GLANCE_NATIVE_RENDER_RENDERER_H_
