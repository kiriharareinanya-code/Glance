// 待办卡片：清单的显示。数据与 Flutter 版共享 plugindata/todo.json。
//
// 版式对齐 Flutter 版 basic.dart 的 todo：
//   行背景 done #FFFFFF08 / 未完成 #FFFFFF12
//   勾选框 done 实心 #7CE38B（带勾）/ 未完成 描边 #FF7A7A
//   文本 done 40% 透明度 + 删除线 / 未完成 95%
//   右侧截止徽章（未完成才显示）
//
// 本轮范围：列表渲染 + 文件变化自动重载。
// 勾选、增删改、输入框（IME）依赖交互层，放在后面统一做——那时窗口要能
// 临时接受输入焦点，和现在"不抢焦点"的桌面层是两套状态。
#ifndef GLANCE_NATIVE_CARDS_TODO_CARD_H_
#define GLANCE_NATIVE_CARDS_TODO_CARD_H_

#include <string>
#include <vector>

#include "cards/card.h"

namespace glance {

class TodoCard : public Card {
 public:
  explicit TodoCard(bool hide_done) : hide_done_(hide_done) {}

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;
  void OnConfigured() override;
  // 点任意一行切换它的完成状态，并写回 plugindata/todo.json
  bool OnClick(float local_x, float local_y) override;

 private:
  struct Item {
    std::wstring text;
    bool done = false;
    std::wstring due;  // "2026-09-21"，可能为空
  };

  void Load();          // 读 plugindata/todo.json
  bool Save() const;    // 写回 plugindata/todo.json（先备份 .bak）
  int64_t ModifiedTime() const;

  bool hide_done_ = false;
  std::vector<Item> items_;
  int64_t last_mtime_ = 0;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_TODO_CARD_H_
