// 各组件的规格：可用尺寸。
//
// 从 Flutter 版 lib/widgets/spec.dart 抄来（那 5 个 BuiltinSpec 的 sizes 字段）。
// 右键菜单的"尺寸"项就是照这张表列的——两边不一致会让用户困惑
// （Flutter 版能选的尺寸，原生版这里点不到）。
#ifndef GLANCE_NATIVE_CARDS_CARD_SPEC_H_
#define GLANCE_NATIVE_CARDS_CARD_SPEC_H_

#include <string>
#include <vector>

namespace glance {

// pluginId → 该组件允许的尺寸（"3x2" 形式，逻辑网格）。
// 未知组件返回空表（调用方据此不显示尺寸项）。
const std::vector<std::string>& SizesForPlugin(const std::string& plugin_id);

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CARD_SPEC_H_
