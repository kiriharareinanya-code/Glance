// 日历卡片：月视图，每格上面公历、下面农历/节气/节日。
//
// 版式与配色对齐 Flutter 版 lib/widgets/builtin/calendar.dart：
//   accent  #29B6F6  今天的圆底
//   holiday #FF8A6B  法定节假日 / 周末
//   term    #8FD6A0  二十四节气
// 固定 6 行 42 格（换月时高度不跳变），周标题跟着 mondayFirst 走。
//
// 本轮先做渲染：当月视图 + 今天高亮 + 农历/节气/节日小字。
// 翻月、点选日期（距今天数）等交互归到命中系统那一步统一做。
#ifndef GLANCE_NATIVE_CARDS_CALENDAR_CARD_H_
#define GLANCE_NATIVE_CARDS_CALENDAR_CARD_H_

#include "cards/card.h"
#include "core/lunar.h"

namespace glance {

class CalendarCard : public Card {
 public:
  CalendarCard(bool show_lunar, bool show_festival, bool monday_first);

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;

 private:
  bool show_lunar_ = true;
  bool show_festival_ = true;
  bool monday_first_ = true;

  int today_year_ = 0;
  int today_month_ = 0;
  int today_day_ = 0;
  // 视图年月（交互阶段会改它翻月；现在就是当前月）
  int view_year_ = 0;
  int view_month_ = 0;  // 1-12
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CALENDAR_CARD_H_
