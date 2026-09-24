// 应用状态：布局与设置的模型层。
//
// 与 Flutter 版**共享同一份 userdata/state.json**（不做格式转换、不做迁移）：
// 两个版本读同一个文件，原生版才能贴着真实布局开发、也能随时并排对比。
// 同一时刻只跑一个版本即可，不存在并发写的问题。
#ifndef GLANCE_NATIVE_CORE_APP_STATE_H_
#define GLANCE_NATIVE_CORE_APP_STATE_H_

#include <string>
#include <vector>

#include "core/json.h"

namespace glance {

// 网格系统（对应 lib/core/grid.dart 与 lib/model/settings.dart）
struct GridSettings {
  float cell = 112.0f;      // gridCell：单元边长（逻辑像素）
  float gap = 12.0f;        // gridGap
  float card_radius = 18.0f;  // cardRadius
  bool locked = false;      // 锁定后不许拖动
  std::string theme = "auto";  // auto / light / dark
  std::string material = "acrylic";
};

// 一张磁贴的持久化数据（对应 lib/model/card.dart 的 WidgetCard）
struct CardData {
  std::string id;
  std::string plugin_id;
  float x = 0.0f;  // 逻辑像素
  float y = 0.0f;
  int cols = 1;  // size "2x3" 拆出来的
  int rows = 1;
  int z = 0;
  JsonValue settings;  // 组件自己的设置（原样保留，组件自己解释）
};

struct AppState {
  GridSettings grid;
  std::vector<CardData> cards;

  // 从 state.json 读取。文件缺失/格式错返回 false，调用方用默认布局兜底。
  bool LoadFromFile(const std::wstring& path);

  // 逻辑尺寸 → 物理像素
  float CardWidth(const CardData& card, float dpi_scale) const {
    return (card.cols * grid.cell + (card.cols - 1) * grid.gap) * dpi_scale;
  }
  float CardHeight(const CardData& card, float dpi_scale) const {
    return (card.rows * grid.cell + (card.rows - 1) * grid.gap) * dpi_scale;
  }
};

// 在 exe 附近逐级向上找 userdata 下的某个文件（state.json / plugindata/*）。
// 开发时 exe 在 native\build\Release，而 userdata 在 Flutter 版的构建产物里
// ——两个位置都试，这样两个版本共享同一份运行数据。
std::wstring FindUserDataFile(const std::wstring& relative_path);

// FindUserDataFile("state.json") 的快捷方式
std::wstring FindStateFilePath();

// 解析 "3x2"；失败返回 false
bool ParseCardSize(const std::string& size, int* cols, int* rows);

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_APP_STATE_H_
