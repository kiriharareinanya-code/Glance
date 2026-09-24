// 时钟卡片：时间 + 日期，第一块用原生渲染落地的组件。
//
// 布局参照 Flutter 版 lib/widgets/builtin/basic.dart 的时钟：
// 上部大号时间（圆体）、下方一行日期与星期（次要色）。
#ifndef GLANCE_NATIVE_CARDS_CLOCK_CARD_H_
#define GLANCE_NATIVE_CARDS_CLOCK_CARD_H_

#include <string>

#include "cards/card.h"

namespace glance {

class ClockCard : public Card {
 public:
  ClockCard() { Update(); }

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;

 private:
  std::wstring time_text_;
  std::wstring date_text_;
  int last_hour_ = -1;
  int last_minute_ = -1;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CLOCK_CARD_H_
