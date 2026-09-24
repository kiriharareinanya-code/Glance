#include "cards/card_spec.h"

namespace glance {

const std::vector<std::string>& SizesForPlugin(const std::string& plugin_id) {
  // 与 spec.dart 一一对应，顺序也照抄（菜单里的排列顺序不变）
  static const std::vector<std::string> kClock = {"2x2", "3x2", "3x3", "4x2"};
  static const std::vector<std::string> kWeather = {"3x2", "3x3", "4x2", "4x3"};
  static const std::vector<std::string> kTodo = {"2x3", "3x3", "3x4", "4x4"};
  static const std::vector<std::string> kCalendar = {"3x3", "4x3", "4x4", "5x4",
                                                     "5x5"};
  static const std::vector<std::string> kLyrics = {"4x2", "5x2", "6x2", "5x3",
                                                   "6x3", "6x4", "7x4", "8x4"};
  static const std::vector<std::string> kEmpty;

  if (plugin_id == "clock") return kClock;
  if (plugin_id == "weather") return kWeather;
  if (plugin_id == "todo") return kTodo;
  if (plugin_id == "calendar") return kCalendar;
  if (plugin_id == "lyrics") return kLyrics;
  return kEmpty;
}

}  // namespace glance
