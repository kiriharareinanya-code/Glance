#include "core/app_state.h"

#include <windows.h>

#include "platform/log.h"

namespace glance {
namespace {

}  // namespace

bool ParseCardSize(const std::string& size, int* cols, int* rows) {
  const size_t x = size.find('x');
  if (x == std::string::npos) return false;
  try {
    *cols = std::stoi(size.substr(0, x));
    *rows = std::stoi(size.substr(x + 1));
  } catch (...) {
    return false;
  }
  return *cols > 0 && *rows > 0 && *cols <= 8 && *rows <= 8;
}

bool AppState::LoadFromFile(const std::wstring& path) {
  const std::string text = ReadFileUtf8(path);
  if (text.empty()) return false;

  JsonValue root;
  if (!ParseJson(text, &root)) {
    Log(L"[state] JSON parse failed: %s", path.c_str());
    return false;
  }

  if (const JsonValue* settings = root.Find("settings")) {
    grid.cell = static_cast<float>(settings->Find("gridCell")
                                       ? settings->Find("gridCell")->NumberOr(grid.cell)
                                       : grid.cell);
    if (const JsonValue* gap = settings->Find("gridGap")) {
      grid.gap = static_cast<float>(gap->NumberOr(grid.gap));
    }
    if (const JsonValue* radius = settings->Find("cardRadius")) {
      grid.card_radius = static_cast<float>(radius->NumberOr(grid.card_radius));
    }
    if (const JsonValue* locked = settings->Find("locked")) {
      grid.locked = locked->BoolOr(false);
    }
    if (const JsonValue* theme = settings->Find("theme")) {
      grid.theme = theme->StringOr("auto");
    }
    if (const JsonValue* material = settings->Find("material")) {
      grid.material = material->StringOr("acrylic");
    }
  }

  // 注意命名：局部变量不要叫 cards —— 那是成员名，会遮蔽（第一版就是这么
  // 编译不过的：cards.clear() 作用在 JsonValue* 上）。
  const JsonValue* cards_node = root.Find("cards");
  if (cards_node == nullptr || !cards_node->IsArray()) {
    Log(L"[state] no cards array");
    return false;
  }

  cards.clear();
  for (const JsonValue& item : cards_node->array) {
    if (!item.IsObject()) continue;
    CardData card;
    if (const JsonValue* id = item.Find("id")) card.id = id->StringOr("");
    if (const JsonValue* plugin = item.Find("pluginId")) {
      card.plugin_id = plugin->StringOr("");
    }
    if (card.plugin_id.empty()) continue;
    if (const JsonValue* x = item.Find("x")) card.x = static_cast<float>(x->NumberOr(0));
    if (const JsonValue* y = item.Find("y")) card.y = static_cast<float>(y->NumberOr(0));
    if (const JsonValue* z = item.Find("z")) {
      card.z = static_cast<int>(z->NumberOr(0));
    }
    if (const JsonValue* size = item.Find("size")) {
      if (!ParseCardSize(size->StringOr("2x2"), &card.cols, &card.rows)) {
        card.cols = 2;
        card.rows = 2;
      }
    }
    if (const JsonValue* own = item.Find("settings")) card.settings = *own;
    cards.push_back(std::move(card));
  }

  Log(L"[state] loaded %zu cards, cell=%.0f gap=%.0f radius=%.0f", cards.size(),
      grid.cell, grid.gap, grid.card_radius);
  return true;
}

std::wstring FindUserDataFile(const std::wstring& relative_path) {
  wchar_t exe_path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) return {};
  std::wstring dir(exe_path);
  const size_t slash = dir.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return {};
  dir.resize(slash);

  std::wstring base = dir;
  for (int level = 0; level < 6; ++level) {
    // 候选一：exe 同级的 userdata（原生版自己的包）
    const std::wstring direct = base + L"\\userdata\\" + relative_path;
    if (GetFileAttributesW(direct.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return direct;
    }
    // 候选二：Flutter 版构建产物里的 userdata（开发期共享运行数据）
    const std::wstring flutter_release =
        base + L"\\build\\windows\\x64\\runner\\Release\\userdata\\" +
        relative_path;
    if (GetFileAttributesW(flutter_release.c_str()) != INVALID_FILE_ATTRIBUTES) {
      return flutter_release;
    }
    base += L"\\..";
  }
  return {};
}

std::wstring FindStateFilePath() { return FindUserDataFile(L"state.json"); }

}  // namespace glance
