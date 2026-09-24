#include "cards/placeholder_card.h"

namespace glance {

std::wstring DisplayNameForPlugin(const std::string& plugin_id) {
  if (plugin_id == "clock") return L"时钟";
  if (plugin_id == "weather") return L"天气";
  if (plugin_id == "calendar") return L"日历";
  if (plugin_id == "todo") return L"待办";
  if (plugin_id == "lyrics") return L"歌词";
  return L"未命名组件";
}

void PlaceholderCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  renderer.FillCardBackground(rect, theme.card_radius * s, theme.card_bg,
                              theme.CardTintAlpha());

  // 组件名（居中偏上）+ 迁移状态小字
  TextStyle name_style;
  name_style.size = 22.0f * s;
  name_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
  name_style.family = L"Microsoft YaHei UI";
  name_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  name_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  const float height = rect.bottom - rect.top;
  const D2D1_RECT_F name_rect =
      D2D1::RectF(rect.left, rect.top + height * 0.34f, rect.right,
                  rect.top + height * 0.34f + 34.0f * s);
  renderer.DrawText(display_name_, renderer.TextFormat(name_style), name_rect,
                    theme.fg);

  TextStyle hint_style;
  hint_style.size = 12.0f * s;
  hint_style.family = L"Microsoft YaHei UI";
  hint_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  hint_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  const D2D1_RECT_F hint_rect =
      D2D1::RectF(rect.left, rect.top + height * 0.34f + 36.0f * s, rect.right,
                  rect.top + height * 0.34f + 60.0f * s);
  renderer.DrawText(L"迁移中…", renderer.TextFormat(hint_style), hint_rect,
                    theme.fg_muted);
}

}  // namespace glance
