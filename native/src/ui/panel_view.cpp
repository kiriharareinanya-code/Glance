#include "ui/panel_view.h"

#include <windows.h>

#include <algorithm>
#include <cmath>

namespace glance {
namespace {

// 配色（对着 Win11 设置的观感调的，深色主题）
const Color kPanelBg = Color::Hex(0x202020);
const Color kNavBg = Color::Hex(0x1B1B1B);
const Color kCardBg = Color::Hex(0x2B2B2B);
const Color kAccent = Color::Hex(0x4CC2FF);
const Color kText = Color::Hex(0xFFFFFF, 0.94f);
const Color kTextDim = Color::Hex(0xFFFFFF, 0.58f);
const Color kTrack = Color::Hex(0xFFFFFF, 0.16f);

constexpr float kTitlebarHeight = 40.0f;
constexpr float kNavWidth = 200.0f;
constexpr float kPad = 28.0f;

struct NavEntry {
  PanelView::Page page;
  const wchar_t* label;
};

const NavEntry kNavs[] = {
    {PanelView::Page::kLibrary, L"组件库"}, {PanelView::Page::kPlaced, L"已放置"},
    {PanelView::Page::kAppearance, L"外观"}, {PanelView::Page::kOther, L"其他"},
    {PanelView::Page::kAbout, L"关于"},
};

TextStyle TextOf(float size, DWRITE_FONT_WEIGHT weight = DWRITE_FONT_WEIGHT_NORMAL,
                 DWRITE_TEXT_ALIGNMENT align = DWRITE_TEXT_ALIGNMENT_LEADING) {
  TextStyle style;
  style.size = size;
  style.weight = weight;
  style.family = L"Microsoft YaHei UI";
  style.align = align;
  style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  return style;
}

const wchar_t* PageTitle(PanelView::Page page) {
  switch (page) {
    case PanelView::Page::kLibrary: return L"组件库";
    case PanelView::Page::kPlaced: return L"已放置";
    case PanelView::Page::kAppearance: return L"外观";
    case PanelView::Page::kOther: return L"其他";
    case PanelView::Page::kAbout: return L"关于";
  }
  return L"";
}

}  // namespace

void PanelView::SetContext(AppState* state, PanelCallbacks callbacks) {
  state_ = state;
  callbacks_ = std::move(callbacks);
  needs_redraw_ = true;
}

bool PanelView::HitTitlebarButton(float x, float y, float scale) const {
  const float h = kTitlebarHeight * scale;
  if (y > h) return false;
  // 右上角三个按钮（关闭/最大化/最小化），各 46 逻辑像素宽
  const float button_w = 46.0f * scale;
  return x > -1.0f && x > 0.0f;  // 宽度在 Paint 时才知道，这里只兜住高度
}

void PanelView::Paint(Renderer& r, float width, float height, float scale) {
  hit_zones_.clear();
  needs_redraw_ = false;

  r.FillRect(D2D1::RectF(0, 0, width, height), kPanelBg);

  PaintTitlebar(r, width, scale);
  PaintNav(r, height, scale);

  const float content_left = kNavWidth * scale;
  const float content_top = kTitlebarHeight * scale;
  if (page_ == Page::kAppearance) {
    PaintAppearancePage(r, content_left + kPad * scale, content_top + kPad * scale,
                        width - content_left - kPad * 2 * scale, scale);
  } else if (page_ == Page::kLibrary) {
    PaintPlaceholderPage(r, L"组件库", L"（待补：五个组件的添加入口）",
                         content_left + kPad * scale, content_top + kPad * scale,
                         width - content_left - kPad * 2 * scale, scale);
  } else if (page_ == Page::kPlaced) {
    PaintPlaceholderPage(r, L"已放置", L"（待补：卡片列表与逐项设置）",
                         content_left + kPad * scale, content_top + kPad * scale,
                         width - content_left - kPad * 2 * scale, scale);
  } else if (page_ == Page::kOther) {
    PaintPlaceholderPage(r, L"其他", L"（待补：开机自启、数据目录、更新）",
                         content_left + kPad * scale, content_top + kPad * scale,
                         width - content_left - kPad * 2 * scale, scale);
  } else {
    PaintPlaceholderPage(r, L"关于", L"Glance · 原生版",
                         content_left + kPad * scale, content_top + kPad * scale,
                         width - content_left - kPad * 2 * scale, scale);
  }
}

void PanelView::PaintTitlebar(Renderer& r, float width, float scale) {
  const float h = kTitlebarHeight * scale;

  // 右上角窗控按钮（自绘，因为我们把系统标题栏吃掉了）
  const float button_w = 46.0f * scale;
  const wchar_t* symbols[3] = {L"\u2500", L"\u25A1", L"\u2715"};  // ─ □ ✕
  for (int i = 0; i < 3; ++i) {
    const float right = width - button_w * static_cast<float>(2 - i);
    const float left = right - button_w;
    const bool hover = mouse_x_ >= left && mouse_x_ <= right && mouse_y_ >= 0 &&
                       mouse_y_ <= h;
    if (hover) {
      // 关闭按钮悬停用红底，和系统一致
      const Color hover_bg = (i == 2) ? Color::Hex(0xC42B1C) : Color::Hex(0xFFFFFF, 0.08f);
      r.FillRect(D2D1::RectF(left, 0, right, h), hover_bg);
    }
    TextStyle style = TextOf(11.0f * scale, DWRITE_FONT_WEIGHT_NORMAL,
                            DWRITE_TEXT_ALIGNMENT_CENTER);
    r.DrawText(symbols[i], r.TextFormat(style),
               D2D1::RectF(left, 0, right, h), kText.WithAlpha(hover ? 1.0f : 0.8f));

    HitZone zone;
    zone.kind = HitZone::Kind::kTitlebar;
    zone.index = i;  // 0=最小化 1=最大化 2=关闭
    zone.rect = D2D1::RectF(left, 0, right, h);
    hit_zones_.push_back(zone);
  }

  // 左侧标题
  TextStyle title = TextOf(13.0f * scale, DWRITE_FONT_WEIGHT_SEMI_BOLD);
  r.DrawText(L"设置", r.TextFormat(title),
             D2D1::RectF(16.0f * scale, 0, 200.0f * scale, h),
             kText.WithAlpha(0.85f));
}

void PanelView::PaintNav(Renderer& r, float height, float scale) {
  const float nav_w = kNavWidth * scale;
  const float top = kTitlebarHeight * scale;
  r.FillRect(D2D1::RectF(0, top, nav_w, height), kNavBg);

  float y = top + 12.0f * scale;
  const float item_h = 40.0f * scale;
  for (size_t i = 0; i < std::size(kNavs); ++i) {
    const D2D1_RECT_F item =
        D2D1::RectF(8.0f * scale, y, nav_w - 8.0f * scale, y + item_h);
    const bool selected = kNavs[i].page == page_;
    const bool hover = mouse_x_ >= item.left && mouse_x_ <= item.right &&
                       mouse_y_ >= item.top && mouse_y_ <= item.bottom;

    if (selected || hover) {
      r.FillRoundRect(item, 5.0f * scale,
                      selected ? Color::Hex(0xFFFFFF, 0.09f)
                               : Color::Hex(0xFFFFFF, 0.05f));
    }
    if (selected) {
      // Win11 那条竖直选中条
      r.FillRoundRect(D2D1::RectF(item.left + 1.0f * scale, item.top + 10.0f * scale,
                                  item.left + 4.0f * scale, item.bottom - 10.0f * scale),
                      1.5f * scale, kAccent);
    }
    TextStyle style = TextOf(13.5f * scale, selected ? DWRITE_FONT_WEIGHT_SEMI_BOLD
                                                     : DWRITE_FONT_WEIGHT_NORMAL);
    r.DrawText(kNavs[i].label, r.TextFormat(style),
               D2D1::RectF(item.left + 16.0f * scale, item.top, item.right, item.bottom),
               selected ? kText : kText.WithAlpha(0.8f));

    HitZone zone;
    zone.kind = HitZone::Kind::kNav;
    zone.index = static_cast<int>(i);
    zone.rect = item;
    hit_zones_.push_back(zone);
    y += item_h + 2.0f * scale;
  }
}

void PanelView::PaintPlaceholderPage(Renderer& r, const wchar_t* title,
                                     const wchar_t* note, float left, float top,
                                     float width, float scale) {
  r.DrawText(title, r.TextFormat(TextOf(24.0f * scale, DWRITE_FONT_WEIGHT_SEMI_BOLD)),
             D2D1::RectF(left, top, left + width, top + 40.0f * scale), kText);
  r.DrawText(note, r.TextFormat(TextOf(13.0f * scale)),
             D2D1::RectF(left, top + 48.0f * scale, left + width,
                         top + 76.0f * scale),
             kTextDim);
}

void PanelView::PaintAppearancePage(Renderer& r, float left, float top, float width,
                                    float scale) {
  if (state_ == nullptr) return;
  GridSettings& grid = state_->grid;
  float y = top;

  // 页标题
  r.DrawText(L"外观", r.TextFormat(TextOf(24.0f * scale, DWRITE_FONT_WEIGHT_SEMI_BOLD)),
             D2D1::RectF(left, y, left + width, y + 40.0f * scale), kText);
  y += 56.0f * scale;

  const float card_w = std::min(width, 660.0f * scale);
  const float row_h = 56.0f * scale;

  // ---- 分组：网格 ----
  const float grid_card_h = row_h * 2 + 16.0f * scale;
  r.FillRoundRect(D2D1::RectF(left, y, left + card_w, y + grid_card_h), 6.0f * scale,
                  kCardBg);
  r.DrawText(L"网格", r.TextFormat(TextOf(12.0f * scale, DWRITE_FONT_WEIGHT_SEMI_BOLD)),
             D2D1::RectF(left + 16.0f * scale, y + 6.0f * scale,
                         left + card_w, y + 28.0f * scale),
             kTextDim);
  {
    float row_y = y + 30.0f * scale;
    // 网格边长
    const D2D1_RECT_F row1 =
        D2D1::RectF(left + 16.0f * scale, row_y, left + card_w - 16.0f * scale,
                    row_y + row_h);
    r.DrawText(L"单元边长", r.TextFormat(TextOf(13.5f * scale)),
               row1, kText);
    const float slider_left = row1.left + 150.0f * scale;
    const float slider_right = row1.right - 70.0f * scale;
    const float track_y = (row1.top + row1.bottom) * 0.5f;
    r.FillRoundRect(D2D1::RectF(slider_left, track_y - 2.0f * scale, slider_right,
                                track_y + 2.0f * scale),
                    2.0f * scale, kTrack);
    const float ratio = std::clamp((static_cast<float>(grid.cell) - 40.0f) / 160.0f,
                                   0.0f, 1.0f);
    const float knob_x = slider_left + (slider_right - slider_left) * ratio;
    r.FillRoundRect(D2D1::RectF(slider_left, track_y - 2.0f * scale, knob_x,
                                track_y + 2.0f * scale),
                    2.0f * scale, kAccent);
    r.FillCircle(knob_x, track_y, 8.0f * scale, Color::Hex(0xFFFFFF));
    r.DrawText(std::to_wstring(static_cast<int>(grid.cell)),
               r.TextFormat(TextOf(13.0f * scale, DWRITE_FONT_WEIGHT_NORMAL,
                                   DWRITE_TEXT_ALIGNMENT_TRAILING)),
               D2D1::RectF(slider_right, row1.top, row1.right, row1.bottom), kText);
    HitZone zone;
    zone.kind = HitZone::Kind::kSlider;
    zone.id = 1;  // 1 = gridCell
    zone.rect = D2D1::RectF(slider_left, track_y - 14.0f * scale, slider_right,
                            track_y + 14.0f * scale);
    zone.min_value = 40.0f;
    zone.max_value = 200.0f;
    hit_zones_.push_back(zone);

    // 网格间距
    row_y += row_h;
    const D2D1_RECT_F row2 =
        D2D1::RectF(left + 16.0f * scale, row_y, left + card_w - 16.0f * scale,
                    row_y + row_h);
    r.DrawText(L"间距", r.TextFormat(TextOf(13.5f * scale)), row2, kText);
    const float t2 = (row2.top + row2.bottom) * 0.5f;
    r.FillRoundRect(
        D2D1::RectF(slider_left, t2 - 2.0f * scale, slider_right, t2 + 2.0f * scale),
        2.0f * scale, kTrack);
    const float ratio2 = std::clamp(static_cast<float>(grid.gap) / 40.0f, 0.0f, 1.0f);
    const float knob2 = slider_left + (slider_right - slider_left) * ratio2;
    r.FillRoundRect(D2D1::RectF(slider_left, t2 - 2.0f * scale, knob2,
                                t2 + 2.0f * scale),
                    2.0f * scale, kAccent);
    r.FillCircle(knob2, t2, 8.0f * scale, Color::Hex(0xFFFFFF));
    r.DrawText(std::to_wstring(static_cast<int>(grid.gap)),
               r.TextFormat(TextOf(13.0f * scale, DWRITE_FONT_WEIGHT_NORMAL,
                                   DWRITE_TEXT_ALIGNMENT_TRAILING)),
               D2D1::RectF(slider_right, row2.top, row2.right, row2.bottom), kText);
    HitZone zone2;
    zone2.kind = HitZone::Kind::kSlider;
    zone2.id = 2;  // 2 = gridGap
    zone2.rect = D2D1::RectF(slider_left, t2 - 14.0f * scale, slider_right,
                             t2 + 14.0f * scale);
    zone2.min_value = 0.0f;
    zone2.max_value = 40.0f;
    hit_zones_.push_back(zone2);
  }
  y += grid_card_h + 16.0f * scale;

  // ---- 分组：卡片 ----
  const float card_h = row_h * 3 + 16.0f * scale;
  r.FillRoundRect(D2D1::RectF(left, y, left + card_w, y + card_h), 6.0f * scale,
                  kCardBg);
  r.DrawText(L"卡片", r.TextFormat(TextOf(12.0f * scale, DWRITE_FONT_WEIGHT_SEMI_BOLD)),
             D2D1::RectF(left + 16.0f * scale, y + 6.0f * scale, left + card_w,
                         y + 28.0f * scale),
             kTextDim);
  {
    float row_y = y + 30.0f * scale;
    // 圆角
    const D2D1_RECT_F row1 =
        D2D1::RectF(left + 16.0f * scale, row_y, left + card_w - 16.0f * scale,
                    row_y + row_h);
    r.DrawText(L"圆角", r.TextFormat(TextOf(13.5f * scale)), row1, kText);
    const float slider_left = row1.left + 150.0f * scale;
    const float slider_right = row1.right - 70.0f * scale;
    const float track_y = (row1.top + row1.bottom) * 0.5f;
    r.FillRoundRect(D2D1::RectF(slider_left, track_y - 2.0f * scale, slider_right,
                                track_y + 2.0f * scale),
                    2.0f * scale, kTrack);
    const float ratio =
        std::clamp(static_cast<float>(grid.card_radius) / 48.0f, 0.0f, 1.0f);
    const float knob_x = slider_left + (slider_right - slider_left) * ratio;
    r.FillRoundRect(D2D1::RectF(slider_left, track_y - 2.0f * scale, knob_x,
                                track_y + 2.0f * scale),
                    2.0f * scale, kAccent);
    r.FillCircle(knob_x, track_y, 8.0f * scale, Color::Hex(0xFFFFFF));
    r.DrawText(std::to_wstring(static_cast<int>(grid.card_radius)),
               r.TextFormat(TextOf(13.0f * scale, DWRITE_FONT_WEIGHT_NORMAL,
                                   DWRITE_TEXT_ALIGNMENT_TRAILING)),
               D2D1::RectF(slider_right, row1.top, row1.right, row1.bottom), kText);
    HitZone zone;
    zone.kind = HitZone::Kind::kSlider;
    zone.id = 3;  // 3 = 圆角
    zone.rect = D2D1::RectF(slider_left, track_y - 14.0f * scale, slider_right,
                            track_y + 14.0f * scale);
    zone.min_value = 0.0f;
    zone.max_value = 48.0f;
    hit_zones_.push_back(zone);

    // 材质（分段）
    row_y += row_h;
    const D2D1_RECT_F row2 =
        D2D1::RectF(left + 16.0f * scale, row_y, left + card_w - 16.0f * scale,
                    row_y + row_h);
    r.DrawText(L"材质", r.TextFormat(TextOf(13.5f * scale)), row2, kText);
    const wchar_t* kMaterials[3] = {L"不透明", L"云母", L"毛玻璃"};
    const char* kMaterialIds[3] = {"opaque", "mica", "acrylic"};
    const float seg_w = 78.0f * scale;
    const float seg_h = 30.0f * scale;
    const float seg_top = row2.top + (row_h - seg_h) * 0.5f;
    for (int i = 0; i < 3; ++i) {
      const D2D1_RECT_F seg =
          D2D1::RectF(row2.left + 150.0f * scale + seg_w * static_cast<float>(i),
                      seg_top, row2.left + 150.0f * scale + seg_w * static_cast<float>(i + 1),
                      seg_top + seg_h);
      const bool active = grid.material == kMaterialIds[i];
      const bool hover = mouse_x_ >= seg.left && mouse_x_ <= seg.right &&
                         mouse_y_ >= seg.top && mouse_y_ <= seg.bottom;
      if (active || hover) {
        r.FillRoundRect(seg, 5.0f * scale,
                        active ? kAccent.WithAlpha(0.22f)
                               : Color::Hex(0xFFFFFF, 0.06f));
      }
      r.DrawText(kMaterials[i],
                 r.TextFormat(TextOf(12.5f * scale,
                                     active ? DWRITE_FONT_WEIGHT_SEMI_BOLD
                                            : DWRITE_FONT_WEIGHT_NORMAL,
                                     DWRITE_TEXT_ALIGNMENT_CENTER)),
                 seg, active ? kText : kText.WithAlpha(0.75f));
      HitZone zone2;
      zone2.kind = HitZone::Kind::kSegment;
      zone2.id = 4;  // 4 = 材质
      zone2.index = i;
      zone2.rect = seg;
      hit_zones_.push_back(zone2);
    }

    // 吸附开关
    row_y += row_h;
    const D2D1_RECT_F row3 =
        D2D1::RectF(left + 16.0f * scale, row_y, left + card_w - 16.0f * scale,
                    row_y + row_h);
    r.DrawText(L"拖动后吸附到网格", r.TextFormat(TextOf(13.5f * scale)), row3, kText);
    {
      const float sw = 44.0f * scale;
      const float sh = 22.0f * scale;
      const float sx = row3.left + 150.0f * scale;
      const float sy = row3.top + (row_h - sh) * 0.5f;
      const D2D1_RECT_F track = D2D1::RectF(sx, sy, sx + sw, sy + sh);
      const bool on = grid.snap_enabled;
      r.FillRoundRect(track, sh * 0.5f, on ? kAccent : kTrack);
      const float knob_cx = on ? (track.right - sh * 0.5f) : (track.left + sh * 0.5f);
      r.FillCircle(knob_cx, track.top + sh * 0.5f, (sh - 8.0f * scale) * 0.5f,
                   Color::Hex(0xFFFFFF));
      HitZone zone3;
      zone3.kind = HitZone::Kind::kToggle;
      zone3.id = 5;  // 5 = 吸附
      zone3.rect = D2D1::RectF(track.left - 6.0f * scale, track.top - 6.0f * scale,
                               track.right + 6.0f * scale, track.bottom + 6.0f * scale);
      hit_zones_.push_back(zone3);
    }
  }
}

void PanelView::ApplyChange() {
  if (callbacks_.on_settings_changed) callbacks_.on_settings_changed();
  needs_redraw_ = true;
}

void PanelView::OnMouseMove(float x, float y, float scale) {
  mouse_x_ = x;
  mouse_y_ = y;

  // 拖动滑块：值跟着指针走
  if (drag_zone_ >= 0 && drag_zone_ < static_cast<int>(hit_zones_.size())) {
    const HitZone& zone = hit_zones_[static_cast<size_t>(drag_zone_)];
    const float ratio = std::clamp(
        (x - zone.rect.left) / std::max(1.0f, zone.rect.right - zone.rect.left), 0.0f,
        1.0f);
    const float value =
        zone.min_value + (zone.max_value - zone.min_value) * ratio;
    if (state_ != nullptr) {
      if (zone.id == 1) state_->grid.cell = std::round(value);
      if (zone.id == 2) state_->grid.gap = std::round(value);
      if (zone.id == 3) state_->grid.card_radius = std::round(value);
    }
    ApplyChange();
  }

  // 悬停高亮：只需要知道有没有换区域
  int hover = -1;
  for (size_t i = 0; i < hit_zones_.size(); ++i) {
    const HitZone& zone = hit_zones_[i];
    if (x >= zone.rect.left && x <= zone.rect.right && y >= zone.rect.top &&
        y <= zone.rect.bottom) {
      hover = static_cast<int>(i);
      break;
    }
  }
  if (hover != hover_zone_) {
    hover_zone_ = hover;
    needs_redraw_ = true;
  }
}

void PanelView::OnMouseDown(float x, float y, float scale) {
  for (size_t i = 0; i < hit_zones_.size(); ++i) {
    const HitZone& zone = hit_zones_[i];
    if (x < zone.rect.left || x > zone.rect.right || y < zone.rect.top ||
        y > zone.rect.bottom) {
      continue;
    }
    switch (zone.kind) {
      case HitZone::Kind::kNav: {
        if (zone.index >= 0 && zone.index < static_cast<int>(std::size(kNavs))) {
          page_ = kNavs[zone.index].page;
          needs_redraw_ = true;
        }
        break;
      }
      case HitZone::Kind::kSlider:
        drag_zone_ = static_cast<int>(i);
        OnMouseMove(x, y, scale);  // 按下即跳到该位置
        break;
      case HitZone::Kind::kSegment: {
        if (state_ != nullptr && zone.id == 4) {
          const char* ids[3] = {"opaque", "mica", "acrylic"};
          if (zone.index >= 0 && zone.index < 3) {
            state_->grid.material = ids[zone.index];
            ApplyChange();
          }
        }
        break;
      }
      case HitZone::Kind::kToggle: {
        if (state_ != nullptr && zone.id == 5) {
          state_->grid.snap_enabled = !state_->grid.snap_enabled;
          ApplyChange();
        }
        break;
      }
      case HitZone::Kind::kTitlebar: {
        if (callbacks_.on_close == nullptr) break;
        if (zone.index == 0 && callbacks_.on_minimize) callbacks_.on_minimize();
        if (zone.index == 1 && callbacks_.on_toggle_maximize)
          callbacks_.on_toggle_maximize();
        if (zone.index == 2 && callbacks_.on_close) callbacks_.on_close();
        break;
      }
      default:
        break;
    }
    break;
  }
}

void PanelView::OnMouseUp(float x, float y, float scale) {
  (void)x;
  (void)y;
  (void)scale;
  drag_zone_ = -1;
}

void PanelView::OnMouseLeave() {
  mouse_x_ = -1.0f;
  mouse_y_ = -1.0f;
  hover_zone_ = -1;
  needs_redraw_ = true;
}

}  // namespace glance
