// 占位卡片：布局已就位、组件本体还没迁过来的那一类。
//
// 存在的意义是让"布局复现"这件独立的事能先落地并验证——五张卡片按
// state.json 的真实位置摆出来，已完成的（时钟）正常渲染，其余显示名字和
// 迁移状态。这样每迁一个组件都是可见的增量，而不是等全部做完才有画面。
#ifndef GLANCE_NATIVE_CARDS_PLACEHOLDER_CARD_H_
#define GLANCE_NATIVE_CARDS_PLACEHOLDER_CARD_H_

#include <string>

#include "cards/card.h"

namespace glance {

// pluginId → 中文显示名（与 spec.dart 里的 name 一致）
std::wstring DisplayNameForPlugin(const std::string& plugin_id);

class PlaceholderCard : public Card {
 public:
  explicit PlaceholderCard(std::wstring display_name)
      : display_name_(std::move(display_name)) {}

  bool Update() override { return false; }
  void Paint(Renderer& renderer, const Theme& theme) override;

 private:
  std::wstring display_name_;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_PLACEHOLDER_CARD_H_
