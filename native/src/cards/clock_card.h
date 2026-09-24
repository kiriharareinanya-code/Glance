// 时钟卡片：时间 + 日期，第一块用原生渲染落地的组件。
//
// 布局参照 Flutter 版 lib/widgets/builtin/basic.dart 的时钟：
// 上部大号时间（圆体）、下方一行日期与星期（次要色）。
// 设置项（对应 spec.dart 里 clock 的两个）：
//   seconds  显示秒（打开后每秒重绘一次）
//   hour24   24 小时制
#ifndef GLANCE_NATIVE_CARDS_CLOCK_CARD_H_
#define GLANCE_NATIVE_CARDS_CLOCK_CARD_H_

#include <string>

#include "cards/card.h"

namespace glance {

class ClockCard : public Card {
 public:
  ClockCard(bool show_seconds, bool hour24)
      : show_seconds_(show_seconds), hour24_(hour24) {
    Update();
  }

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;

 private:
  bool show_seconds_ = false;
  bool hour24_ = true;
  std::wstring time_text_;
  std::wstring date_text_;
  int last_hour_ = -1;
  int last_minute_ = -1;
  int last_second_ = -1;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CLOCK_CARD_H_
