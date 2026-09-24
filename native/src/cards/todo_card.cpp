#include "cards/todo_card.h"

#include <windows.h>

#include <algorithm>

#include "core/app_state.h"
#include "core/date_util.h"
#include "core/json.h"
#include "platform/log.h"

namespace glance {
namespace {

const Color kCheckDone = Color::Hex(0x7CE38B);   // 完成：绿
const Color kCheckTodo = Color::Hex(0xFF7A7A);   // 未完成：红

// "2026-09-21" → 距今天数；解析不了返回 INT32_MAX（表示不显示徽章）
int DaysUntil(const std::wstring& due) {
  if (due.size() < 10) return INT32_MAX;
  const int year = _wtoi(due.substr(0, 4).c_str());
  const int month = _wtoi(due.substr(5, 2).c_str());
  const int day = _wtoi(due.substr(8, 2).c_str());
  if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
    return INT32_MAX;
  }
  SYSTEMTIME now = {};
  GetLocalTime(&now);
  const int64_t today = DaysFromCivil(now.wYear, now.wMonth, now.wDay);
  const int64_t target = DaysFromCivil(year, month, day);
  const int64_t diff = target - today;
  if (diff > 9999 || diff < -9999) return INT32_MAX;
  return static_cast<int>(diff);
}

std::wstring DueBadgeText(int days) {
  if (days == 0) return L"今天";
  if (days == 1) return L"明天";
  if (days == 2) return L"后天";
  if (days > 0) return L"剩 " + std::to_wstring(days) + L" 天";
  return L"过期 " + std::to_wstring(-days) + L" 天";
}

}  // namespace

void TodoCard::OnConfigured() { Load(); }

int64_t TodoCard::ModifiedTime() const {
  const std::wstring path = FindUserDataFile(L"plugindata\\todo.json");
  if (path.empty()) return 0;
  WIN32_FILE_ATTRIBUTE_DATA data = {};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return 0;
  return (static_cast<int64_t>(data.ftLastWriteTime.dwHighDateTime) << 32) |
         data.ftLastWriteTime.dwLowDateTime;
}

void TodoCard::Load() {
  items_.clear();
  const std::wstring path = FindUserDataFile(L"plugindata\\todo.json");
  if (path.empty()) return;

  JsonValue root;
  if (!ParseJson(ReadFileUtf8(path), &root)) return;

  // 每张卡片一份数据：@inst:<cardId>:items
  const JsonValue* list = root.Find("@inst:" + id + ":items");
  if (list == nullptr || !list->IsArray()) return;

  for (const JsonValue& entry : list->array) {
    Item item;
    if (const JsonValue* text = entry.Find("text")) {
      item.text = text->WStringOr(L"");
    }
    if (const JsonValue* done = entry.Find("done")) item.done = done->BoolOr(false);
    if (const JsonValue* due = entry.Find("due")) item.due = due->WStringOr(L"");
    if (!item.text.empty()) items_.push_back(std::move(item));
  }
  last_mtime_ = ModifiedTime();
  Log(L"[todo] loaded %zu items", items_.size());
}

bool TodoCard::Update() {
  // 数据是共享文件：Flutter 版那边改了东西，这边跟着重载
  const int64_t mtime = ModifiedTime();
  if (mtime != last_mtime_ && mtime != 0) {
    Load();
    return true;
  }
  return false;
}

void TodoCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  renderer.FillCardBackground(rect, theme.card_radius * s, theme.card_bg,
                              theme.CardTintAlpha());

  const float pad = 14.0f * s;
  const float left = rect.left + pad;
  const float right = rect.right - pad;
  float cursor = rect.top + pad;

  // 头部：标题 + 未完成计数
  TextStyle head_style;
  head_style.size = 14.0f * s;
  head_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
  head_style.family = L"Microsoft YaHei UI";
  head_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  const int total = static_cast<int>(items_.size());
  const int left_count = static_cast<int>(
      std::count_if(items_.begin(), items_.end(),
                    [](const Item& item) { return !item.done; }));

  renderer.DrawText(L"待办", renderer.TextFormat(head_style),
                    D2D1::RectF(left, cursor, right, cursor + 20.0f * s), theme.fg);
  TextStyle count_style = head_style;
  count_style.size = 11.0f * s;
  count_style.weight = DWRITE_FONT_WEIGHT_NORMAL;
  count_style.align = DWRITE_TEXT_ALIGNMENT_TRAILING;
  renderer.DrawText(std::to_wstring(left_count) + L"/" + std::to_wstring(total),
                    renderer.TextFormat(count_style),
                    D2D1::RectF(left, cursor, right, cursor + 20.0f * s),
                    theme.fg.WithAlpha(0.45f));
  cursor += 24.0f * s;

  // 列表（必要时过滤已完成）
  std::vector<const Item*> shown;
  for (const Item& item : items_) {
    if (hide_done_ && item.done) continue;
    shown.push_back(&item);
  }

  if (shown.empty()) {
    TextStyle empty_style = head_style;
    empty_style.size = 12.5f * s;
    empty_style.weight = DWRITE_FONT_WEIGHT_NORMAL;
    renderer.DrawText(items_.empty() ? L"还没有待办" : L"没有未完成的待办",
                      renderer.TextFormat(empty_style),
                      D2D1::RectF(left, cursor + 8.0f * s, right,
                                  cursor + 32.0f * s),
                      theme.fg.WithAlpha(0.35f));
    return;
  }

  const float list_height = rect.bottom - pad - cursor;
  const int count = static_cast<int>(shown.size());
  // 行高：按可用高度均分，但不小于 24、不超过 34 逻辑像素
  const float row_h = std::min(34.0f * s,
                               std::max(24.0f * s, list_height / count));
  const float box_r = 7.0f * s;
  const float gap = std::min(6.0f * s, row_h * 0.22f);
  const float row_block = row_h + gap * 0.5f;

  TextStyle text_style;
  text_style.size = 13.0f * s;
  text_style.family = L"Microsoft YaHei UI";
  text_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  TextStyle badge_style = text_style;
  badge_style.size = 10.0f * s;
  badge_style.align = DWRITE_TEXT_ALIGNMENT_TRAILING;

  float row_top = cursor;
  for (int i = 0; i < count; ++i) {
    const Item& item = *shown[static_cast<size_t>(i)];
    if (row_top + row_h > rect.bottom - pad + 1.0f) break;  // 放不下就截断

    // 行背景
    renderer.FillRoundRect(
        D2D1::RectF(left - 4.0f * s, row_top, right + 4.0f * s, row_top + row_h),
        8.0f * s,
        item.done ? Color::Hex(0xFFFFFF, 0.031f) : Color::Hex(0xFFFFFF, 0.071f));

    // 勾选框
    const float box_cx = left + 8.0f * s;
    const float box_cy = row_top + row_h * 0.5f;
    if (item.done) {
      renderer.FillCircle(box_cx, box_cy, box_r, kCheckDone);
      // 白色对勾（两段线）
      renderer.DrawLine(box_cx - box_r * 0.45f, box_cy,
                        box_cx - box_r * 0.1f, box_cy + box_r * 0.38f,
                        1.6f * s, Color::Hex(0x0B1116));
      renderer.DrawLine(box_cx - box_r * 0.1f, box_cy + box_r * 0.38f,
                        box_cx + box_r * 0.5f, box_cy - box_r * 0.4f, 1.6f * s,
                        Color::Hex(0x0B1116));
    } else {
      renderer.DrawCircleStroke(box_cx, box_cy, box_r, 1.6f * s, kCheckTodo);
    }

    // 截止徽章（已完成不显示）
    const int days = DaysUntil(item.due);
    float text_right = right;
    if (!item.done && days != INT32_MAX) {
      const float badge_w = 56.0f * s;
      renderer.DrawText(DueBadgeText(days), renderer.TextFormat(badge_style),
                        D2D1::RectF(right - badge_w, row_top, right,
                                    row_top + row_h),
                        theme.fg.WithAlpha(days < 0 ? 0.55f : 0.5f));
      text_right = right - badge_w - 4.0f * s;
    }

    // 文本（完成态：淡化 + 删除线用一条中线表达）
    const float text_left = box_cx + box_r + 8.0f * s;
    renderer.DrawText(item.text, renderer.TextFormat(text_style),
                      D2D1::RectF(text_left, row_top, text_right, row_top + row_h),
                      theme.fg.WithAlpha(item.done ? 0.4f : 0.95f));

    row_top += row_block;
  }
}

}  // namespace glance
