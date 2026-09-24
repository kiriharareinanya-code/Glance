#include "cards/card_factory.h"

#include "cards/clock_card.h"
#include "cards/placeholder_card.h"

namespace glance {

std::unique_ptr<Card> CreateCardFor(const CardData& data,
                                    const GridSettings& grid, float dpi_scale) {
  if (data.id.empty() || data.cols <= 0 || data.rows <= 0) return nullptr;

  std::unique_ptr<Card> card;
  if (data.plugin_id == "clock") {
    const JsonValue* seconds = data.settings.Find("seconds");
    const JsonValue* hour24 = data.settings.Find("hour24");
    card = std::make_unique<ClockCard>(seconds != nullptr && seconds->BoolOr(false),
                                       hour24 == nullptr || hour24->BoolOr(true));
  } else {
    // 天气 / 日历 / 待办 / 歌词：布局先占位，组件逐个迁移
    card = std::make_unique<PlaceholderCard>(DisplayNameForPlugin(data.plugin_id));
  }

  card->id = data.id;
  card->plugin_id = data.plugin_id;
  card->scale = dpi_scale;

  const float x = data.x * dpi_scale;
  const float y = data.y * dpi_scale;
  const float width =
      (data.cols * grid.cell + (data.cols - 1) * grid.gap) * dpi_scale;
  const float height =
      (data.rows * grid.cell + (data.rows - 1) * grid.gap) * dpi_scale;
  card->rect = D2D1::RectF(x, y, x + width, y + height);
  return card;
}

}  // namespace glance
