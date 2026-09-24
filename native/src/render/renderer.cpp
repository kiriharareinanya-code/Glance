#include "render/renderer.h"

#include <d2d1_1.h>
#include <d3d11.h>

#include "platform/log.h"

namespace glance {
namespace {

bool SameStyle(const TextStyle& a, const TextStyle& b) {
  // 字体族名字符串比较，不能比指针：同样两个字面量在不同翻译单元里地址不同，
  // 比指针会让缓存永远命中不了（然后格式数组很快塞满、文字直接不画）。
  const bool same_family =
      (a.family == b.family) ||
      (a.family != nullptr && b.family != nullptr && wcscmp(a.family, b.family) == 0);
  return a.size == b.size && a.weight == b.weight && same_family &&
         a.align == b.align && a.valign == b.valign && a.wrap == b.wrap &&
         a.use_private_font == b.use_private_font;
}

}  // namespace

bool Renderer::LoadPrivateFontFile(const std::wstring& path) {
  if (!dwrite_factory_) return false;

  ComPtr<IDWriteFactory5> factory5;
  if (FAILED(dwrite_factory_.As(&factory5))) {
    Log(L"[render] QI IDWriteFactory5 failed (need Win10+)");
    return false;
  }

  ComPtr<IDWriteFontFile> font_file;
  // 必须绝对路径：CreateFontFileReference 按当前工作目录解析相对路径，
  // 而我们的工作目录是随启动方式变的。
  if (FAILED(factory5->CreateFontFileReference(path.c_str(), nullptr,
                                               font_file.GetAddressOf()))) {
    Log(L"[render] CreateFontFileReference failed: %s", path.c_str());
    return false;
  }

  ComPtr<IDWriteFontSetBuilder1> builder;
  if (FAILED(factory5->CreateFontSetBuilder(builder.GetAddressOf())) ||
      FAILED(builder->AddFontFile(font_file.Get()))) {
    Log(L"[render] FontSetBuilder failed");
    return false;
  }
  ComPtr<IDWriteFontSet> font_set;
  if (FAILED(builder->CreateFontSet(font_set.GetAddressOf())) ||
      FAILED(factory5->CreateFontCollectionFromFontSet(
          font_set.Get(), private_font_collection_.GetAddressOf()))) {
    Log(L"[render] CreateFontCollectionFromFontSet failed");
    return false;
  }
  Log(L"[render] private font collection ready: %s", path.c_str());
  return true;
}

Renderer::~Renderer() { Shutdown(); }

bool Renderer::Initialize(HWND hwnd, int width, int height) {
  width_ = width;
  height_ = height;
  if (!CreateBaseFactories()) return false;
  return CreateDeviceResources() && CreateSwapChain(hwnd);
}

bool Renderer::InitializeForOffscreen(int width, int height) {
  width_ = width;
  height_ = height;
  if (!CreateBaseFactories()) return false;
  if (!CreateDeviceResources()) return false;
  return CreateDrawTargetTexture();
}

// 建绘制目标：一块 D3D 纹理 + 绑定它的 D2D 位图。
//
// 窗口模式也走这里（而不是直接画交换链的后台缓冲）。原因是踩过坑：
// 直接拿 flip-model 的后台缓冲当 D2D 目标，EndDraw 会返回
// D2DERR_WRONG_STATE（0x88990001），第一帧都画不出来；而且 flip 模式下
// Present 之后后台缓冲会换一块，绑定关系还得每帧重建。
// 统一画到自己的纹理、再拷给后台缓冲，路径和 --capture 完全一致（那条路
// 已稳定），flip 的坑也一并绕开了。代价是一帧一次 GPU 内拷贝：
// 静态桌面组件分钟级才更新一次，这点开销可以忽略。
bool Renderer::CreateDrawTargetTexture() {
  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  // SHADER_RESOURCE 是 D2D 的要求：只标 RENDER_TARGET 时
  // CreateBitmapFromDxgiSurface 会拒绝（实测）。
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  if (FAILED(d3d_device_->CreateTexture2D(&desc, nullptr,
                                          draw_target_texture_.GetAddressOf()))) {
    Log(L"[render] CreateTexture2D(draw target) failed");
    return false;
  }

  ComPtr<IDXGISurface> surface;
  if (FAILED(draw_target_texture_.As(&surface))) return false;
  const D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
      D2D1_BITMAP_OPTIONS_TARGET,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
  const HRESULT hr = d2d_context_->CreateBitmapFromDxgiSurface(
      surface.Get(), &props, target_bitmap_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) {
    Log(L"[render] CreateBitmapFromDxgiSurface(draw target) failed, hr=0x%08X", hr);
    return false;
  }
  d2d_context_->SetTarget(target_bitmap_.Get());
  return true;
}

bool Renderer::SaveTargetToPng(const std::wstring& path) {
  if (!wic_factory_ || !draw_target_texture_ || !d3d_context_) return false;

  // D2D 和 D3D 是两个 API 层：先 Flush 再 CopyResource，否则可能拷到半成品。
  d3d_context_->Flush();

  D3D11_TEXTURE2D_DESC desc = {};
  draw_target_texture_->GetDesc(&desc);
  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  desc.MiscFlags = 0;

  ComPtr<ID3D11Texture2D> staging;
  if (FAILED(d3d_device_->CreateTexture2D(&desc, nullptr, staging.GetAddressOf()))) {
    Log(L"[render] staging texture failed");
    return false;
  }
  d3d_context_->CopyResource(staging.Get(), draw_target_texture_.Get());

  D3D11_MAPPED_SUBRESOURCE mapped = {};
  if (FAILED(d3d_context_->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
    Log(L"[render] staging map failed");
    return false;
  }

  bool ok = false;
  ComPtr<IWICStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IWICBitmap> source;
  do {
    if (FAILED(wic_factory_->CreateBitmapFromMemory(
            static_cast<UINT>(width_), static_cast<UINT>(height_),
            GUID_WICPixelFormat32bppPBGRA, mapped.RowPitch,
            mapped.RowPitch * static_cast<UINT>(height_),
            static_cast<BYTE*>(mapped.pData), source.GetAddressOf()))) {
      Log(L"[render] CreateBitmapFromMemory failed");
      break;
    }
    if (FAILED(wic_factory_->CreateStream(stream.GetAddressOf())) ||
        FAILED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE))) {
      Log(L"[render] WIC stream init failed");
      break;
    }
    if (FAILED(wic_factory_->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                           encoder.GetAddressOf())) ||
        FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
      Log(L"[render] PNG encoder init failed");
      break;
    }
    if (FAILED(encoder->CreateNewFrame(frame.GetAddressOf(), nullptr)) ||
        FAILED(frame->Initialize(nullptr)) ||
        FAILED(frame->SetSize(static_cast<UINT>(width_),
                              static_cast<UINT>(height_)))) {
      Log(L"[render] PNG frame init failed");
      break;
    }
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    frame->SetPixelFormat(&format);
    if (FAILED(frame->WriteSource(source.Get(), nullptr)) ||
        FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
      Log(L"[render] PNG write failed");
      break;
    }
    ok = true;
  } while (false);

  d3d_context_->Unmap(staging.Get(), 0);
  return ok;
}

bool Renderer::CreateBaseFactories() {
  D2D1_FACTORY_OPTIONS options = {};
  if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                               __uuidof(ID2D1Factory1), &options,
                               reinterpret_cast<void**>(d2d_factory_.GetAddressOf())))) {
    Log(L"[render] D2D1CreateFactory failed");
    return false;
  }
  if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                 reinterpret_cast<IUnknown**>(dwrite_factory_.GetAddressOf())))) {
    Log(L"[render] DWriteCreateFactory failed");
    return false;
  }
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory2, nullptr, CLSCTX_INPROC_SERVER,
                              __uuidof(IWICImagingFactory),
                              reinterpret_cast<void**>(wic_factory_.GetAddressOf())))) {
    Log(L"[render] WIC factory failed");
    return false;
  }
  return true;
}

bool Renderer::CreateDeviceResources() {
  // BGRA 支持是 D2D 互操作的前提：D2D 只认 BGRA 表面的位图。
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0};
  D3D_FEATURE_LEVEL achieved = D3D_FEATURE_LEVEL_11_0;

  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
                                 levels, ARRAYSIZE(levels), D3D11_SDK_VERSION,
                                 d3d_device_.GetAddressOf(), &achieved,
                                 d3d_context_.GetAddressOf());
  if (FAILED(hr)) {
    // 没有独显/核显驱动兜底时退回 WARP（软件光栅）。慢，但桌面组件这点
    // 像素量撑得住，总比白屏强。
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, levels,
                           ARRAYSIZE(levels), D3D11_SDK_VERSION,
                           d3d_device_.GetAddressOf(), &achieved,
                           d3d_context_.GetAddressOf());
    if (FAILED(hr)) {
      Log(L"[render] D3D11CreateDevice failed both HW and WARP, hr=0x%08X", hr);
      return false;
    }
    Log(L"[render] fell back to WARP");
  }

  ComPtr<IDXGIDevice> dxgi_device;
  if (FAILED(d3d_device_.As(&dxgi_device))) {
    Log(L"[render] QI IDXGIDevice failed");
    return false;
  }
  if (FAILED(d2d_factory_->CreateDevice(dxgi_device.Get(), d2d_device_.GetAddressOf()))) {
    Log(L"[render] D2D CreateDevice failed");
    return false;
  }
  if (FAILED(d2d_device_->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
                                              d2d_context_.GetAddressOf()))) {
    Log(L"[render] D2D CreateDeviceContext failed");
    return false;
  }
  // 固定 96 DPI：尺寸换算统一在调用方做，别让 D2D 再缩一次。
  d2d_context_->SetDpi(96.0f, 96.0f);
  d2d_context_->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  // 文字用灰度抗锯齿：覆盖层带 alpha，ClearType 的子像素着色会在字边留彩边。
  d2d_context_->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

  const D2D1_COLOR_F white = D2D1::ColorF(D2D1::ColorF::White);
  if (FAILED(d2d_context_->CreateSolidColorBrush(white, brush_.GetAddressOf()))) {
    Log(L"[render] CreateSolidColorBrush failed");
    return false;
  }
  return true;
}

bool Renderer::CreateSwapChain(HWND hwnd) {
  ComPtr<IDXGIDevice> dxgi_device;
  if (FAILED(d3d_device_.As(&dxgi_device))) return false;
  ComPtr<IDXGIAdapter> adapter;
  if (FAILED(dxgi_device->GetAdapter(adapter.GetAddressOf()))) return false;
  ComPtr<IDXGIFactory2> factory;
  if (FAILED(adapter->GetParent(__uuidof(IDXGIFactory2),
                                reinterpret_cast<void**>(factory.GetAddressOf())))) {
    return false;
  }

  DXGI_SWAP_CHAIN_DESC1 desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  desc.BufferCount = 2;
  desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
  // 预乘 alpha：D2D 的输出就是预乘的，声明成直通会让半透明边缘发亮。
  // 注意这条只在 ForComposition 上受支持（见头文件里那段说明）。
  desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;

  HRESULT hr = factory->CreateSwapChainForComposition(
      d3d_device_.Get(), &desc, nullptr, swap_chain_.GetAddressOf());
  if (FAILED(hr)) {
    Log(L"[render] CreateSwapChainForComposition failed, hr=0x%08X", hr);
    return false;
  }

  // 交换链没有窗口归属，靠 DComp 把它挂到窗口上。
  hr = DCompositionCreateDevice(dxgi_device.Get(), __uuidof(IDCompositionDevice),
                                reinterpret_cast<void**>(dcomp_device_.GetAddressOf()));
  if (FAILED(hr)) {
    Log(L"[render] DCompositionCreateDevice failed, hr=0x%08X", hr);
    return false;
  }
  if (FAILED(dcomp_device_->CreateTargetForHwnd(hwnd, TRUE,
                                                dcomp_target_.GetAddressOf())) ||
      FAILED(dcomp_device_->CreateVisual(dcomp_visual_.GetAddressOf())) ||
      FAILED(dcomp_visual_->SetContent(swap_chain_.Get())) ||
      FAILED(dcomp_target_->SetRoot(dcomp_visual_.Get()))) {
    Log(L"[render] DComp visual tree setup failed");
    return false;
  }
  // Commit 之前视觉树不生效：这一步漏了的表现是"窗口全透明，什么都没有"。
  hr = dcomp_device_->Commit();
  if (FAILED(hr)) {
    Log(L"[render] DComp Commit failed, hr=0x%08X", hr);
    return false;
  }

  // 绘制目标是自己的纹理（见 CreateDrawTargetTexture 的说明），
  // 不是交换链的后台缓冲。
  return CreateDrawTargetTexture();
}

bool Renderer::BeginFrame() {
  if (!d2d_context_ || drawing_) return false;
  // 帧与帧之间才是处理挂起 resize 的时机（见 Resize 的说明）。
  if (pending_width_ > 0) {
    const int w = pending_width_;
    const int h = pending_height_;
    pending_width_ = 0;
    pending_height_ = 0;
    Resize(w, h);
  }
  d2d_context_->BeginDraw();
  d2d_context_->SetTransform(D2D1::Matrix3x2F::Identity());
  // 全透明打底：卡片之外的地方必须透出壁纸。
  d2d_context_->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
  drawing_ = true;
  return true;
}

void Renderer::EndFrame() {
  if (!drawing_) return;
  drawing_ = false;
  const HRESULT hr = d2d_context_->EndDraw();
  if (hr == D2DERR_RECREATE_TARGET) {
    // 设备丢了（显卡驱动更新/休眠恢复）：重建渲染目标，下一帧继续。
    // 不重建的话整个窗口从此不再出画面——这类问题在覆盖层上表现为"桌面变空"。
    Log(L"[render] EndDraw: recreate target");
    ReleaseDrawTarget();
    CreateDrawTargetTexture();
    return;
  }
  if (FAILED(hr)) {
    // 静默 return 过一次，结果就是"窗口全空、日志里什么都看不出来"。
    Log(L"[render] EndDraw failed hr=0x%08X", hr);
    return;
  }

  if (!swap_chain_) return;  // 离屏模式：画完等调用方保存位图

  // D2D 与 D3D 是两层 API：拷贝前 Flush，确保绘制的命令已经落到纹理上。
  d3d_context_->Flush();

  ComPtr<ID3D11Texture2D> backbuffer;
  if (SUCCEEDED(swap_chain_->GetBuffer(0, __uuidof(ID3D11Texture2D),
                                       reinterpret_cast<void**>(backbuffer.GetAddressOf())))) {
    d3d_context_->CopyResource(backbuffer.Get(), draw_target_texture_.Get());
  } else {
    Log(L"[render] GetBuffer(0) failed");
  }

  const HRESULT present_hr = swap_chain_->Present(1, 0);
  if (present_count_ < 3) {
    ++present_count_;
    Log(L"[render] Present #%d hr=0x%08X", present_count_, present_hr);
  }
}

void Renderer::Resize(int width, int height) {
  Log(L"[render] Resize(%d,%d) drawing=%d cur=%dx%d", width, height,
      drawing_ ? 1 : 0, width_, height_);
  if (!swap_chain_ || width <= 0 || height <= 0) return;
  if (width == width_ && height == height_) return;
  // BeginDraw 和 EndDraw 之间绝对不能碰 SetTarget/ResizeBuffers——
  // D2D 会直接判 D2DERR_WRONG_STATE（实测第一帧就是这么废掉的：
  // 窗口显示时的 WM_SIZE 插进了帧中间）。挪到帧之间做。
  if (drawing_) {
    pending_width_ = width;
    pending_height_ = height;
    return;
  }
  width_ = width;
  height_ = height;
  ReleaseDrawTarget();
  if (swap_chain_) {
    swap_chain_->ResizeBuffers(0, static_cast<UINT>(width), static_cast<UINT>(height),
                               DXGI_FORMAT_UNKNOWN, 0);
  }
  CreateDrawTargetTexture();
}

void Renderer::ReleaseDrawTarget() {
  // Shutdown 可能被调用两次（显式收尾 + 析构），这里的解引用必须带守卫：
  // 少这个判断，第二次进来就是空指针崩溃（实测退出时段错误）。
  if (d2d_context_) d2d_context_->SetTarget(nullptr);
  target_bitmap_.Reset();
  draw_target_texture_.Reset();
}

void Renderer::FillRoundRect(const D2D1_RECT_F& rect, float radius, const Color& color) {
  if (!d2d_context_) return;
  const D2D1_ROUNDED_RECT rounded =
      D2D1::RoundedRect(rect, radius, radius);
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  d2d_context_->FillRoundedRectangle(rounded, brush_.Get());
}

void Renderer::FillRect(const D2D1_RECT_F& rect, const Color& color) {
  if (!d2d_context_) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  d2d_context_->FillRectangle(rect, brush_.Get());
}

void Renderer::FillCircle(float center_x, float center_y, float radius,
                          const Color& color) {
  if (!d2d_context_) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  d2d_context_->FillEllipse(D2D1::Ellipse(D2D1::Point2F(center_x, center_y), radius,
                                          radius),
                            brush_.Get());
}

IDWriteTextFormat* Renderer::TextFormat(const TextStyle& style) {
  for (int i = 0; i < cached_count_; ++i) {
    if (SameStyle(cached_styles_[i], style)) return cached_formats_[i].Get();
  }
  if (cached_count_ >= static_cast<int>(ARRAYSIZE(cached_formats_))) return nullptr;

  ComPtr<IDWriteTextFormat> format;
  IDWriteFontCollection* collection =
      style.use_private_font ? private_font_collection_.Get() : nullptr;
  const HRESULT hr = dwrite_factory_->CreateTextFormat(
      style.family, collection, style.weight, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, style.size, L"zh-CN", format.GetAddressOf());
  if (FAILED(hr)) {
    Log(L"[render] CreateTextFormat failed family=%s private=%d hr=0x%08X",
        style.family, style.use_private_font ? 1 : 0, hr);
    return nullptr;
  }
  format->SetTextAlignment(style.align);
  format->SetParagraphAlignment(style.valign);
  format->SetWordWrapping(style.wrap ? DWRITE_WORD_WRAPPING_WRAP
                                     : DWRITE_WORD_WRAPPING_NO_WRAP);

  cached_styles_[cached_count_] = style;
  cached_formats_[cached_count_] = format;
  ++cached_count_;
  return format.Get();
}

void Renderer::DrawText(const std::wstring& text, IDWriteTextFormat* format,
                        const D2D1_RECT_F& rect, const Color& color) {
  if (!d2d_context_ || !format || text.empty()) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  d2d_context_->DrawTextW(text.c_str(), static_cast<UINT32>(text.size()), format,
                          rect, brush_.Get(), D2D1_DRAW_TEXT_OPTIONS_NONE,
                          DWRITE_MEASURING_MODE_NATURAL);
}

void Renderer::DrawCircleStroke(float center_x, float center_y, float radius,
                                float width, const Color& color) {
  if (!d2d_context_) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  d2d_context_->DrawEllipse(
      D2D1::Ellipse(D2D1::Point2F(center_x, center_y), radius, radius),
      brush_.Get(), width, nullptr);
}

void Renderer::DrawLine(float x1, float y1, float x2, float y2, float width,
                        const Color& color) {
  if (!d2d_context_) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));
  // 端点样式用默认（平头）：天气图标的雨丝只有几像素长，差别肉眼不可见，
  // 不值得为此维护一个 ID2D1StrokeStyle。
  d2d_context_->DrawLine(D2D1::Point2F(x1, y1), D2D1::Point2F(x2, y2), brush_.Get(),
                         width, nullptr);
}

void Renderer::FillPolygon(const D2D1_POINT_2F* points, int count,
                           const Color& color) {
  if (!d2d_context_ || points == nullptr || count < 3) return;
  brush_->SetColor(D2D1::ColorF(color.r, color.g, color.b, color.a));

  ComPtr<ID2D1PathGeometry> geometry;
  if (FAILED(d2d_factory_->CreatePathGeometry(geometry.GetAddressOf()))) return;
  ComPtr<ID2D1GeometrySink> sink;
  if (FAILED(geometry->Open(sink.GetAddressOf()))) return;
  sink->BeginFigure(points[0], D2D1_FIGURE_BEGIN_FILLED);
  sink->AddLines(points + 1, static_cast<UINT32>(count - 1));
  sink->EndFigure(D2D1_FIGURE_END_CLOSED);
  if (FAILED(sink->Close())) return;

  d2d_context_->FillGeometry(geometry.Get(), brush_.Get());
}

void Renderer::Shutdown() {
  ReleaseDrawTarget();
  cached_count_ = 0;
  for (auto& f : cached_formats_) f.Reset();
  brush_.Reset();
  d2d_context_.Reset();
  d2d_device_.Reset();
  // DComp 先松，再放交换链：视觉树还引用着内容时释放交换链是无效操作。
  dcomp_visual_.Reset();
  dcomp_target_.Reset();
  dcomp_device_.Reset();
  swap_chain_.Reset();
  d3d_context_.Reset();
  d3d_device_.Reset();
  private_font_collection_.Reset();
  dwrite_factory_.Reset();
  wic_factory_.Reset();
  d2d_factory_.Reset();
}

}  // namespace glance
