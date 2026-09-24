// 卡片工厂：按 pluginId 把布局数据变成可绘制的卡片对象。
//
// 新增一个组件的迁移动作就是：写它的 Card 子类，在这里加一个分支。
// 还没迁的落到占位卡片（显示名字 + "迁移中…"），布局照旧占位——
// 这样"布局复现"和"组件实现"两件事可以分开推进、各自验证。
#ifndef GLANCE_NATIVE_CARDS_CARD_FACTORY_H_
#define GLANCE_NATIVE_CARDS_CARD_FACTORY_H_

#include <memory>

#include "cards/card.h"
#include "core/app_state.h"

namespace glance {

// 位置与尺寸按 state.json（逻辑像素）× dpi_scale 换算成物理像素。
// 返回 nullptr 表示这条卡片数据不完整（跳过）。
std::unique_ptr<Card> CreateCardFor(const CardData& data,
                                    const GridSettings& grid, float dpi_scale);

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_CARD_FACTORY_H_
