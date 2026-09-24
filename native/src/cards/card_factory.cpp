#include "cards/card_factory.h"

#include "cards/calendar_card.h"
#include "cards/clock_card.h"
#include "cards/lyrics_card.h"
#include "cards/placeholder_card.h"
#include "cards/todo_card.h"
#include "cards/weather_card.h"

namespace glance {
namespace {

// 设置项缺省为 true 的小工具（与 spec.dart 里的 default 对齐）
bool SettingsBoolOr(const JsonValue& settings, const char* key, bool fallback) {
  const JsonValue* node = settings.Find(key);
  return node != nullptr ? node->BoolOr(fallback) : fallback;
}

}  // namespace

std::unique_ptr<Card> CreateCardFor(const CardData& data,
                                    const GridSettings& grid, float dpi_scale) {
  if (data.id.empty() || data.cols <= 0 || data.rows <= 0) return nullptr;

  std::unique_ptr<Card> card;
  if (data.plugin_id == "clock") {
    card = std::make_unique<ClockCard>(SettingsBoolOr(data.settings, "seconds", false),
                                       SettingsBoolOr(data.settings, "hour24", true));
  } else if (data.plugin_id == "calendar") {
    card = std::make_unique<CalendarCard>(
        SettingsBoolOr(data.settings, "lunar", true),
        SettingsBoolOr(data.settings, "festival", true),
        SettingsBoolOr(data.settings, "mondayFirst", true));
  } else if (data.plugin_id == "weather") {
    const JsonValue* city = data.settings.Find("city");
    const JsonValue* refresh = data.settings.Find("refreshMin");
    card = std::make_unique<WeatherCard>(
        city != nullptr ? city->StringOr("") : "",
        static_cast<int>(refresh != nullptr ? refresh->NumberOr(30.0) : 30.0));
  } else if (data.plugin_id == "lyrics") {
    const JsonValue* source = data.settings.Find("source");
    card = std::make_unique<LyricsCard>(
        SettingsBoolOr(data.settings, "trans", true),
        SettingsBoolOr(data.settings, "credits", false),
        source != nullptr ? source->StringOr("auto") : "auto");
  } else if (data.plugin_id == "todo") {
    // 本轮先做列表显示；勾选与输入框（IME）归到交互层一起做
    card = std::make_unique<TodoCard>(SettingsBoolOr(data.settings, "hideDone", false));
  } else {
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
  // id 之类的身份信息到这步才齐，需要读自己缓存的组件在这里做初始化
  card->OnConfigured();
  return card;
}

}  // namespace glance
