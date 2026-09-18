// 面板界面：导航 + 组件库 / 已放置 / 外观 / 布局 / 其他 / 关于。
//
// 设计原则与 Flutter 面板一致：**页面不硬编码任何设置项**。
// 全局设置页由 settings.schema 驱动，卡片设置页由插件的 settings 描述驱动，
// 组件库由 plugins.list 驱动。核心加一个插件/一项设置，这里不用改一行。
#include <windows.h>  // 必须最先：dwmapi/shellapi 依赖它的声明

#include <dwmapi.h>
#include <microsoft.ui.xaml.window.h>
#include <shellapi.h>

#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Interop.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Text.h>

#include <algorithm>
#include <cstdio>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "app.h"
#include "json.h"
#include "log.h"
#include "startup.h"
#include "text.h"
#include "ui.h"

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using panel::Json;  // 协议里的 JSON 值类型，全文都在用

namespace mux = winrt::Microsoft::UI::Xaml;
namespace muxc = winrt::Microsoft::UI::Xaml::Controls;
namespace muxm = winrt::Microsoft::UI::Xaml::Media;

namespace {

// ---------------- 数据模型（都是协议返回值的薄封装）----------------

struct FieldSpec {
  std::string key;
  std::string type;
  std::string label;
  std::string desc;
  Json raw;
};

struct PluginInfo {
  std::string id;
  std::string name;
  std::string icon;
  std::string desc;
  std::string version;
  std::string default_size;
  std::vector<std::string> sizes;
  std::vector<FieldSpec> settings;
};

struct CardInfo {
  std::string id;
  std::string plugin_id;
  std::string plugin_name;
  std::string size;
  std::string monitor_id;
  std::vector<std::string> sizes;
  Json settings;
};

enum class Page { Gallery, Cards, Appearance, Layout, Other, About };

struct Section {
  std::string id;
  std::string title;
  std::vector<FieldSpec> fields;
};

std::vector<std::string> StringList(const Json& arr) {
  std::vector<std::string> out;
  for (const auto& v : arr.items()) out.push_back(v.as_string());
  return out;
}

std::vector<FieldSpec> ParseFields(const Json& arr) {
  std::vector<FieldSpec> out;
  for (const auto& f : arr.items()) {
    FieldSpec spec;
    spec.key = f.str("key");
    spec.type = f.str("type");
    spec.label = f.str("label");
    spec.desc = f.str("desc");
    spec.raw = f;
    if (!spec.key.empty()) out.push_back(std::move(spec));
  }
  return out;
}

std::wstring Utf8ToWide(const std::string& s) {
  return panel::WideFromUtf8(s);
}
hstring Hs(const std::string& s) { return hstring(Utf8ToWide(s)); }
std::string ToUtf8(const hstring& s) {
  return panel::Utf8FromWide(std::wstring_view(s));
}

// 颜色：协议里可能是 "#RRGGBB" / "#AARRGGBB" 字符串，也可能是 ARGB 整数
winrt::Windows::UI::Color ParseColor(const Json& v, uint32_t fallback) {
  uint32_t argb = fallback;
  if (v.is_number()) {
    argb = static_cast<uint32_t>(v.as_double());
  } else if (v.is_string()) {
    std::string s = v.as_string();
    if (!s.empty() && s[0] == '#') s.erase(0, 1);
    try {
      const auto value = std::stoul(s, nullptr, 16);
      argb = s.size() <= 6 ? (0xFF000000u | value) : value;
    } catch (...) {
    }
  }
  return winrt::Windows::UI::ColorHelper::FromArgb(
      static_cast<uint8_t>((argb >> 24) & 0xFF),
      static_cast<uint8_t>((argb >> 16) & 0xFF),
      static_cast<uint8_t>((argb >> 8) & 0xFF),
      static_cast<uint8_t>(argb & 0xFF));
}

std::string ColorToHex(const winrt::Windows::UI::Color& c) {
  char buf[16];
  std::snprintf(buf, sizeof(buf), "#%02X%02X%02X", c.R, c.G, c.B);
  return buf;
}

// 命名的导航项：图标 + 标题
muxc::NavigationViewItem NavItem(const wchar_t* glyph, const hstring& text,
                                 const hstring& tag) {
  muxc::NavigationViewItem item;
  item.Content(box_value(text));
  item.Tag(box_value(tag));
  item.Icon(ui::Glyph(glyph, 16));
  return item;
}

}  // namespace

// =====================================================================
// PanelUi
// =====================================================================

struct PanelUi {
  PanelUi(App* app, mux::Window window) : app_(app), window_(window) {}

  App* app_;
  mux::Window window_;
  winrt::Microsoft::UI::Dispatching::DispatcherQueue queue_{nullptr};

  muxc::NavigationView nav_;
  muxc::ScrollViewer scroller_;
  muxc::StackPanel content_;      // 当前页面的内容容器
  muxc::Grid title_bar_;
  muxc::TextBlock status_text_;   // 底部/标题里的连接状态

  Page page_ = Page::Gallery;

  // 缓存的核心状态
  Json app_info_;
  std::vector<PluginInfo> plugins_;
  std::vector<Section> sections_;
  std::vector<CardInfo> cards_;
  std::map<std::string, bool> can_add_;
  bool connected_ = false;
  std::string connect_error_;

  int pending_ = 0;
  bool first_load_done_ = false;

  // ---------------- 与核心对话 ----------------

  // 回调统一切回 UI 线程：接收线程上碰 UI 对象会直接崩。
  void CallAsync(const std::string& method, Json params,
                 std::function<void(const panel::PanelResult&)> done) {
    auto queue = queue_;
    app_->core_.Call(method, std::move(params),
                     [queue, done](const panel::PanelResult& r) {
                       if (!queue) return;
                       queue.TryEnqueue([r, done] {
                         // 回调里做的事（重建 UI）最容易出例外。不兜住的话
                         // 表现就是"窗口突然没了"，且什么都不留。
                         panel::Guard("ipc.callback", [&] { done(r); });
                       });
                     });
  }

  void SetSetting(const std::string& key, Json value,
                  std::function<void(const panel::PanelResult&)> done = {}) {
    Json p = Json::Object();
    p.set("key", Json(key));
    p.set("value", std::move(value));
    CallAsync(panel::kMethodSettingsSet, std::move(p),
              [done](const panel::PanelResult& r) {
                if (done) done(r);
              });
  }

  void SetCardSetting(const std::string& card_id, const std::string& key,
                      Json value) {
    Json p = Json::Object();
    p.set("id", Json(card_id));
    p.set("key", Json(key));
    p.set("value", std::move(value));
    CallAsync(panel::kMethodCardsSetSetting, std::move(p), {});
  }

  // ---------------- 构建窗口 ----------------

  void Build(int width, int height) {
    queue_ = window_.DispatcherQueue();
    ApplyThemeToWindow();

    nav_ = muxc::NavigationView();
    nav_.IsSettingsVisible(false);
    nav_.IsBackButtonVisible(
        muxc::NavigationViewBackButtonVisible::Collapsed);
    nav_.PaneDisplayMode(muxc::NavigationViewPaneDisplayMode::Left);
    nav_.OpenPaneLength(196);
    nav_.IsPaneToggleButtonVisible(false);

    nav_.MenuItems().Append(NavItem(L"\uE8F1", L"组件库", L"gallery"));
    nav_.MenuItems().Append(NavItem(L"\uE8A5", L"已放置", L"cards"));
    nav_.MenuItems().Append(NavItem(L"\uE790", L"外观", L"appearance"));
    nav_.MenuItems().Append(NavItem(L"\uE7C4", L"布局", L"layout"));
    nav_.MenuItems().Append(NavItem(L"\uE713", L"其他", L"other"));
    nav_.MenuItems().Append(NavItem(L"\uE946", L"关于", L"about"));

    scroller_ = muxc::ScrollViewer();
    scroller_.VerticalScrollBarVisibility(
        muxc::ScrollBarVisibility::Auto);
    scroller_.HorizontalScrollMode(muxc::ScrollMode::Disabled);

    content_ = muxc::StackPanel();
    content_.Spacing(16);
    content_.Padding(mux::ThicknessHelper::FromLengths(28, 8, 28, 28));
    scroller_.Content(content_);
    nav_.Content(scroller_);

    // 导航项加完就选中第一项：NavigationView 默认不会自己选，
    // 不选的话右侧内容区一开始是空的
    nav_.SelectedItem(nav_.MenuItems().GetAt(0));

    nav_.SelectionChanged([this](const auto&, const auto& args) {
      const auto item = args.SelectedItem().try_as<muxc::NavigationViewItem>();
      if (!item) return;
      const std::string tag = ToUtf8(unbox_value_or<hstring>(item.Tag(), L""));
      if (tag == "gallery") page_ = Page::Gallery;
      else if (tag == "cards") page_ = Page::Cards;
      else if (tag == "appearance") page_ = Page::Appearance;
      else if (tag == "layout") page_ = Page::Layout;
      else if (tag == "other") page_ = Page::Other;
      else if (tag == "about") page_ = Page::About;
      RenderPage();
    });

    // 自绘标题栏：48 高的空白区域当拖拽区，标题写在左边
    title_bar_ = muxc::Grid();
    title_bar_.Height(48);
    title_bar_.Background(ui::Brush(ui::theme().window_bg));
    title_bar_.ColumnDefinitions().Append(muxc::ColumnDefinition{});
    muxc::StackPanel title_stack;
    title_stack.Orientation(muxc::Orientation::Horizontal);
    title_stack.Spacing(10);
    title_stack.VerticalAlignment(mux::VerticalAlignment::Center);
    title_stack.Margin(mux::ThicknessHelper::FromLengths(16, 0, 0, 0));
    auto mark = ui::Glyph(L"\uE71D", 14);
    mark.Foreground(ui::Brush(ui::theme().accent));
    title_stack.Children().Append(mark);
    auto title = ui::Text(L"Glance 一瞥", 13, ui::theme().text);
    title.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    title_stack.Children().Append(title);
    status_text_ = ui::Text(L"", 12, ui::theme().text_faint);
    status_text_.VerticalAlignment(mux::VerticalAlignment::Center);
    status_text_.Margin(mux::ThicknessHelper::FromLengths(10, 0, 0, 0));
    title_stack.Children().Append(status_text_);
    title_bar_.Children().Append(title_stack);

    // 标题栏和导航必须是同一个根容器的两个孩子：SetTitleBar 传的元素
    // 得在窗口的视觉树里，否则拖拽区不生效。
    auto root = muxc::Grid();
    auto title_row = muxc::RowDefinition{};
    title_row.Height(mux::GridLengthHelper::FromPixels(48));
    root.RowDefinitions().Append(title_row);
    auto body_row = muxc::RowDefinition{};
    body_row.Height(
        mux::GridLengthHelper::FromValueAndType(1, mux::GridUnitType::Star));
    root.RowDefinitions().Append(body_row);
    root.Background(ui::Brush(ui::theme().window_bg));
    muxc::Grid::SetRow(title_bar_, 0);
    root.Children().Append(title_bar_);
    muxc::Grid::SetRow(nav_, 1);
    root.Children().Append(nav_);

    window_.Content(root);
    window_.ExtendsContentIntoTitleBar(true);
    window_.SetTitleBar(title_bar_);
    window_.Title(L"Glance 设置");

    if (auto app_window = window_.AppWindow()) {
      app_window.Resize(
          {static_cast<int32_t>(width), static_cast<int32_t>(height)});
      // 居中到当前显示器工作区。不居中的话会缩在左上角，看着像没摆好。
      try {
        const auto area = winrt::Microsoft::UI::Windowing::DisplayArea::
            GetFromWindowId(app_window.Id(),
                            winrt::Microsoft::UI::Windowing::
                                DisplayAreaFallback::Primary);
        const auto work = area.WorkArea();
        app_window.Move(
            {work.X + (work.Width - app_window.Size().Width) / 2,
             work.Y + (work.Height - app_window.Size().Height) / 2});
      } catch (...) {
      }
    }
    window_.Activate();
  }

  // 窗口句柄：走官方的 IWindowNative 互操作（WASDK 文档里的标准做法）
  HWND Hwnd() {
    try {
      auto native = window_.as<::IWindowNative>();
      HWND hwnd = nullptr;
      if (native && SUCCEEDED(native->get_WindowHandle(&hwnd))) return hwnd;
    } catch (...) {
    }
    return nullptr;
  }

  void ApplyThemeToWindow() {
    // 深色时让窗口边框/标题栏区域也走深色，否则浅色边框配深色内容很割裂
    HWND hwnd = Hwnd();
    if (!hwnd) return;
    BOOL dark = ui::theme().dark ? TRUE : FALSE;
    ::DwmSetWindowAttribute(hwnd, 20 /*DWMWA_USE_IMMERSIVE_DARK_MODE*/, &dark,
                            sizeof(dark));
  }

  // ---------------- 数据加载 ----------------

  void LoadAll() {
    pending_ = 4;
    LoadAppInfo();
    LoadPlugins();
    LoadSchema();
    LoadCards();
  }

  void LoadAppInfo() {
    CallAsync(panel::kMethodAppInfo, Json::Object(),
              [this](const panel::PanelResult& r) {
                if (r.ok) app_info_ = r.value;
                Done();
              });
  }

  void LoadPlugins() {
    CallAsync(panel::kMethodPluginsList, Json::Object(),
              [this](const panel::PanelResult& r) {
                if (!r.ok) return Done();
                plugins_.clear();
                for (const auto& p : r.value["plugins"].items()) {
                  PluginInfo info;
                  info.id = p.str("id");
                  info.name = p.str("name");
                  info.icon = p.str("icon");
                  info.desc = p.str("description");
                  info.version = p.str("version");
                  info.default_size = p.str("defaultSize");
                  info.sizes = StringList(p["sizes"]);
                  info.settings = ParseFields(p["settings"]);
                  plugins_.push_back(std::move(info));
                }
                Done();
              });
  }

  void LoadSchema() {
    CallAsync(panel::kMethodSettingsSchema, Json::Object(),
              [this](const panel::PanelResult& r) {
                if (!r.ok) return Done();
                sections_.clear();
                for (const auto& g : r.value["groups"].items()) {
                  Section s;
                  s.id = g.str("id");
                  s.title = g.str("title");
                  s.fields = ParseFields(g["fields"]);
                  sections_.push_back(std::move(s));
                }
                Done();
              });
  }

  void LoadCards() {
    CallAsync(panel::kMethodCardsList, Json::Object(),
              [this](const panel::PanelResult& r) {
                if (!r.ok) return Done();
                cards_.clear();
                can_add_.clear();
                for (const auto& c : r.value["cards"].items()) {
                  CardInfo info;
                  info.id = c.str("id");
                  info.plugin_id = c.str("pluginId");
                  info.plugin_name = c.str("pluginName");
                  info.size = c.str("size");
                  info.monitor_id = c.str("monitorId");
                  info.sizes = StringList(c["sizes"]);
                  info.settings = c["settings"];
                  cards_.push_back(std::move(info));
                }
                for (const auto& kv : r.value["canAdd"].pairs()) {
                  can_add_[kv.first] = kv.second.as_bool();
                }
                Done();
              });
  }

  // 四个请求都回来了才重画：不然页面会抖四下
  void Done() {
    if (--pending_ > 0) return;
    if (pending_ < 0) pending_ = 0;
    first_load_done_ = true;
    UpdateStatus();
    RenderPage();
  }

  void UpdateStatus() {
    std::string text = "核心 " + app_->core_.core_display_version();
    if (!connected_) text = "未连接";
    status_text_.Text(Hs(text));
    status_text_.Foreground(ui::Brush(ui::theme().text_faint));
  }

  // ---------------- 页面 ----------------

  void RenderPage() {
    content_.Children().Clear();

    if (!connected_) {
      content_.Children().Append(BuildDisconnectedPage());
      return;
    }
    if (!first_load_done_) {
      muxc::ProgressRing ring;
      ring.IsActive(true);
      ring.Margin(mux::ThicknessHelper::FromLengths(0, 40, 0, 0));
      content_.Children().Append(ring);
      return;
    }

    switch (page_) {
      case Page::Gallery: BuildGallery(); break;
      case Page::Cards: BuildCards(); break;
      case Page::Appearance:
        BuildSettingsSection("appearance", "外观",
                             "主题、字体、卡片外观");
        break;
      case Page::Layout:
        BuildSettingsSection("layout", "布局",
                             "网格与卡片尺寸的摆放规则");
        break;
      case Page::Other:
        BuildSettingsSection("update", "其他", "更新与启动行为");
        break;
      case Page::About: BuildAbout(); break;
    }
  }

  mux::UIElement BuildDisconnectedPage() {
    muxc::StackPanel panel;
    panel.Spacing(12);
    panel.Margin(mux::ThicknessHelper::FromLengths(0, 60, 0, 0));
    panel.Children().Append(ui::Heading(L"没连上核心"));
    panel.Children().Append(
        ui::Dim(Hs("错误：" + connect_error_), 13));
    panel.Children().Append(ui::Dim(
        L"面板是核心启动它时才拿得到端点与口令的。请从托盘菜单打开设置，"
        L"或者关掉这个窗口后重新点一次。", 13));
    auto retry = muxc::Button();
    retry.Content(box_value(hstring(L"重试")));
    retry.Margin(mux::ThicknessHelper::FromLengths(0, 8, 0, 0));
    retry.Click([this](const auto&, const auto&) {
      // 重新走一遍连接流程（核心若重启过，token 与路径都会变，得让核心自己拉起）
      content_.Children().Clear();
      auto ring = muxc::ProgressRing();
      ring.IsActive(true);
      content_.Children().Append(ring);
      app_->Start(app_->socket_path_, app_->token_);
    });
    panel.Children().Append(retry);
    return panel;
  }

  // ---- 组件库 ----
  void BuildGallery() {
    content_.Children().Append(ui::Heading(L"组件库"));
    content_.Children().Append(
        ui::Dim(L"这些是编译进核心的组件。点“添加”就会在空闲的屏幕上放一张卡片。"));

    for (const auto& plugin : plugins_) {
      muxc::StackPanel body;
      body.Spacing(6);

      muxc::StackPanel head;
      head.Orientation(muxc::Orientation::Horizontal);
      head.Spacing(10);
      head.VerticalAlignment(mux::VerticalAlignment::Center);
      auto icon = ui::Text(Hs(plugin.icon), 20, ui::theme().text);
      head.Children().Append(icon);
      auto name = ui::Label(Hs(plugin.name));
      name.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
      head.Children().Append(name);
      auto ver = ui::Dim(Hs("v" + plugin.version), 12);
      ver.VerticalAlignment(mux::VerticalAlignment::Center);
      head.Children().Append(ver);
      body.Children().Append(head);

      body.Children().Append(ui::Dim(Hs(plugin.desc), 13));

      std::string size_text = "可用尺寸：";
      for (size_t i = 0; i < plugin.sizes.size(); ++i) {
        if (i) size_text += " / ";
        size_text += plugin.sizes[i];
      }
      size_text += "（默认 " + plugin.default_size + "）";
      body.Children().Append(ui::Dim(Hs(size_text), 12));

      const bool can_add =
          can_add_.find(plugin.id) != can_add_.end() && can_add_[plugin.id];
      auto add = muxc::Button();
      add.Content(box_value(hstring(L"添加")));
      add.IsEnabled(can_add);
      if (!can_add) {
        add.Content(box_value(hstring(L"没有空闲的屏幕")));
      }
      const std::string plugin_id = plugin.id;
      add.Margin(mux::ThicknessHelper::FromLengths(0, 6, 0, 0));
      add.Click([this, plugin_id](const auto&, const auto&) {
        Json p = Json::Object();
        p.set("pluginId", Json(plugin_id));
        CallAsync(panel::kMethodCardsAdd, std::move(p),
                  [this](const panel::PanelResult& r) {
                    if (!r.ok) ShowError(r);
                    LoadCards();
                  });
      });
      body.Children().Append(add);

      content_.Children().Append(ui::Card(body));
    }
  }

  // ---- 已放置 ----
  void BuildCards() {
    content_.Children().Append(ui::Heading(L"已放置"));
    if (cards_.empty()) {
      content_.Children().Append(
          ui::Dim(L"桌面上还没有卡片。去“组件库”添加一个。"));
      return;
    }
    content_.Children().Append(ui::Dim(
        L"每张卡片都可以单独改尺寸和设置；位置直接用鼠标在桌面上拖。"));

    for (const auto& card : cards_) {
      muxc::StackPanel body;
      body.Spacing(10);

      // 头一行：名字 + 尺寸 + 移除
      muxc::Grid head;
      head.ColumnDefinitions().Append(muxc::ColumnDefinition{});
      auto auto1 = muxc::ColumnDefinition{};
      auto1.Width(
          mux::GridLengthHelper::FromValueAndType(0, mux::GridUnitType::Auto));
      head.ColumnDefinitions().Append(auto1);
      auto auto2 = muxc::ColumnDefinition{};
      auto2.Width(
          mux::GridLengthHelper::FromValueAndType(0, mux::GridUnitType::Auto));
      head.ColumnDefinitions().Append(auto2);
      head.ColumnSpacing(10);

      muxc::StackPanel name_box;
      name_box.Spacing(2);
      name_box.VerticalAlignment(mux::VerticalAlignment::Center);
      auto name = ui::Label(Hs(card.plugin_name));
      name.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
      name_box.Children().Append(name);
      name_box.Children().Append(
          ui::Dim(Hs(card.monitor_id.empty() ? std::string("默认屏幕")
                                             : card.monitor_id),
                  12));
      muxc::Grid::SetColumn(name_box, 0);
      head.Children().Append(name_box);

      muxc::ComboBox size_combo;
      size_combo.MinWidth(96);
      for (const auto& s : card.sizes) {
        size_combo.Items().Append(box_value(Hs(s)));
        if (s == card.size) size_combo.SelectedIndex(size_combo.Items().Size() - 1);
      }
      const std::string card_id = card.id;
      size_combo.SelectionChanged(
          [this, card_id](const auto& sender, const auto&) {
            const auto combo = sender.as<muxc::ComboBox>();
            const auto index = combo.SelectedIndex();
            if (index < 0) return;
            const std::string size =
                ToUtf8(unbox_value<hstring>(combo.Items().GetAt(index)));
            Json p = Json::Object();
            p.set("id", Json(card_id));
            p.set("size", Json(size));
            CallAsync(panel::kMethodCardsSetSize, std::move(p),
                      [this](const panel::PanelResult& r) {
                        if (!r.ok) ShowError(r);
                      });
          });
      muxc::Grid::SetColumn(size_combo, 1);
      head.Children().Append(size_combo);

      auto remove = muxc::Button();
      remove.Content(box_value(hstring(L"移除")));
      remove.Foreground(ui::Brush(ui::theme().danger));
      remove.Click([this, card_id](const auto&, const auto&) {
        Json p = Json::Object();
        p.set("id", Json(card_id));
        CallAsync(panel::kMethodCardsRemove, std::move(p),
                  [this](const panel::PanelResult& r) {
                    if (!r.ok) ShowError(r);
                    LoadCards();
                  });
      });
      muxc::Grid::SetColumn(remove, 2);
      head.Children().Append(remove);

      body.Children().Append(head);

      // 这张卡自己的设置项（描述来自插件清单，当前值来自卡片）
      const PluginInfo* plugin = FindPlugin(card.plugin_id);
      if (plugin && !plugin->settings.empty()) {
        auto line = mux::Shapes::Rectangle();
        line.Height(1);
        line.Fill(ui::Brush(ui::theme().stroke));
        body.Children().Append(line);
        for (const auto& field : plugin->settings) {
          Json current = card.settings.has(field.key) ? card.settings[field.key]
                                                     : field.raw["default"];
          body.Children().Append(BuildField(
              field, current,
              [this, card_id, key = field.key](const panel::PanelResult& r) {
                if (!r.ok) ShowError(r);
                (void)key;
                (void)card_id;
              },
              [this, card_id](const std::string& key, Json value) {
                SetCardSetting(card_id, key, std::move(value));
              }));
        }
      }

      content_.Children().Append(ui::Card(body));
    }
  }

  const PluginInfo* FindPlugin(const std::string& id) {
    for (const auto& p : plugins_) {
      if (p.id == id) return &p;
    }
    return nullptr;
  }

  // ---- 全局设置（schema 驱动）----
  void BuildSettingsSection(const std::string& section_id,
                            const std::string& fallback_title,
                            const std::string& subtitle) {
    content_.Children().Append(ui::Heading(Hs(fallback_title)));
    content_.Children().Append(ui::Dim(Hs(subtitle)));

    const Section* section = nullptr;
    for (const auto& s : sections_) {
      if (s.id == section_id) section = &s;
    }
    if (!section) {
      content_.Children().Append(
          ui::Dim(L"核心没有提供这一组设置（协议版本可能不匹配）。"));
      return;
    }

    muxc::StackPanel body;
    body.Spacing(2);
    for (const auto& field : section->fields) {
      const std::string key = field.key;
      body.Children().Append(BuildField(
          field, field.raw["value"],
          [this, key](const panel::PanelResult& r) {
            if (!r.ok) {
              ShowError(r);
              LoadSchema();  // 值没落进去，把界面拉回真实状态
              return;
            }
            (void)key;
          },
          [this](const std::string& k, Json v) {
            SetSetting(k, std::move(v), [this](const panel::PanelResult& r) {
              if (!r.ok) {
                ShowError(r);
                LoadSchema();
              }
            });
          }));
    }
    content_.Children().Append(ui::Card(body));
  }

  // ---- 一个设置项 → 一个控件 ----
  // on_write(key, value) 负责真正写回核心；on_result 处理写回结果。
  mux::UIElement BuildField(
      const FieldSpec& field, const Json& value,
      std::function<void(const panel::PanelResult&)> on_result,
      std::function<void(const std::string&, Json)> on_write) {
    const std::string& type = field.type;
    const std::string key = field.key;

    if (type == "boolean") {
      auto toggle = muxc::ToggleSwitch();
      toggle.IsOn(value.is_bool() ? value.as_bool()
                                  : field.raw.flag("default"));
      toggle.OnContent(box_value(hstring(L"开")));
      toggle.OffContent(box_value(hstring(L"关")));
      toggle.Toggled([toggle, key, on_write, on_result](const auto&,
                                                        const auto&) {
        on_write(key, Json(toggle.IsOn()));
      });
      return ui::SettingRow(Hs(field.label), Hs(field.desc), toggle);
    }

    if (type == "number") {
      auto box = muxc::NumberBox();
      box.MinWidth(140);
      box.SpinButtonPlacementMode(
          muxc::NumberBoxSpinButtonPlacementMode::Compact);
      if (field.raw.has("min")) box.Minimum(field.raw.num("min"));
      if (field.raw.has("max")) box.Maximum(field.raw.num("max"));
      const double step = field.raw.num("step", 1);
      box.SmallChange(step > 0 ? step : 1);
      box.Value(value.num_or(field.raw.num("default")));
      box.ValueChanged([box, key, on_write, on_result](const auto&,
                                                      const auto& args) {
        if (std::isnan(args.NewValue())) return;
        on_write(key, Json(args.NewValue()));
      });
      return ui::SettingRow(Hs(field.label), Hs(field.desc), box);
    }

    if (type == "select") {
      auto combo = muxc::ComboBox();
      combo.MinWidth(160);
      std::vector<std::pair<std::string, std::string>> options;  // value,label
      for (const auto& o : field.raw["options"].items()) {
        options.emplace_back(o.str("value"), o.str("label"));
        combo.Items().Append(box_value(Hs(o.str("label"))));
      }
      const std::string current = value.is_string()
                                      ? value.as_string()
                                      : field.raw["default"].as_string();
      for (size_t i = 0; i < options.size(); ++i) {
        if (options[i].first == current) combo.SelectedIndex(
            static_cast<int32_t>(i));
      }
      combo.SelectionChanged([combo, options, key, on_write, on_result](
                                 const auto&, const auto&) {
        const auto index = combo.SelectedIndex();
        if (index < 0 || static_cast<size_t>(index) >= options.size()) return;
        on_write(key, Json(options[static_cast<size_t>(index)].first));
      });
      return ui::SettingRow(Hs(field.label), Hs(field.desc), combo);
    }

    if (type == "color") {
      auto button = muxc::Button();
      button.MinWidth(140);
      const uint32_t fallback =
          static_cast<uint32_t>(field.raw.num("default", 0xFF000000u));
      const auto color = ParseColor(value, fallback);
      muxc::StackPanel row;
      row.Orientation(muxc::Orientation::Horizontal);
      row.Spacing(8);
      auto swatch = mux::Shapes::Rectangle();
      swatch.Width(18);
      swatch.Height(18);
      swatch.RadiusX(4);
      swatch.RadiusY(4);
      swatch.Stroke(ui::Brush(ui::theme().stroke));
      swatch.StrokeThickness(1);
      swatch.Fill(muxm::SolidColorBrush(color));
      auto hex_text = ui::Text(Hs(ColorToHex(color)), 13, ui::theme().text);
      hex_text.VerticalAlignment(mux::VerticalAlignment::Center);
      row.Children().Append(swatch);
      row.Children().Append(hex_text);
      button.Content(row);

      // 取色器放在 Flyout 里，关闭时提交最终颜色（拖动过程中不写盘）
      auto picker = muxc::ColorPicker();
      picker.Color(color);
      picker.IsAlphaEnabled(false);
      auto flyout = muxc::Flyout();
      flyout.Content(picker);
      flyout.Closed([picker, key, swatch, hex_text, on_write](
                        const auto&, const auto&) {
        const auto picked = picker.Color();
        const std::string hex = ColorToHex(picked);
        swatch.Fill(muxm::SolidColorBrush(picked));
        hex_text.Text(Hs(hex));
        on_write(key, Json(hex));
      });
      button.Flyout(flyout);
      return ui::SettingRow(Hs(field.label), Hs(field.desc), button);
    }

    // text（默认兜底）
    auto box = muxc::TextBox();
    box.MinWidth(160);
    box.Text(Hs(value.as_string(field.raw["default"].as_string())));
    if (field.raw.has("placeholder")) {
      box.PlaceholderText(Hs(field.raw.str("placeholder")));
    }
    box.LostFocus([box, key, on_write](const auto&, const auto&) {
      on_write(key, Json(ToUtf8(box.Text())));
    });
    box.KeyDown([box, key, on_write](const auto&, const auto& args) {
      if (args.Key() == winrt::Windows::System::VirtualKey::Enter) {
        on_write(key, Json(ToUtf8(box.Text())));
      }
    });
    return ui::SettingRow(Hs(field.label), Hs(field.desc), box);
  }

  // ---- 关于 ----
  void BuildAbout() {
    content_.Children().Append(ui::Heading(L"关于"));

    muxc::StackPanel body;
    body.Spacing(2);
    auto info_row = [&](const wchar_t* label, const std::string& value) {
      auto t = ui::Text(Hs(value), 13, ui::theme().text);
      t.IsTextSelectionEnabled(true);
      body.Children().Append(ui::SettingRow(label, hstring{}, t));
    };
    info_row(L"核心版本", app_info_.str("displayVersion", "未知"));
    info_row(L"版本号", app_info_.str("version", "未知"));
    info_row(L"组件",
             std::to_string(static_cast<int>(app_info_.num("plugins", 0))));
    info_row(L"卡片",
             std::to_string(static_cast<int>(app_info_.num("cards", 0))));
    info_row(L"数据目录", app_info_.str("userDataDir", "未知"));
    info_row(L"面板", "WinUI3 原生面板 · 协议 v1");
    content_.Children().Append(ui::Card(body));

    muxc::StackPanel actions;
    actions.Spacing(8);

    auto open_dir = muxc::Button();
    open_dir.Content(box_value(hstring(L"打开数据目录")));
    const std::string dir = app_info_.str("userDataDir");
    open_dir.Click([this, dir](const auto&, const auto&) {
      if (dir.empty()) return;
      // 面板是原生进程，这种事自己就能干，不用麻烦核心
      const std::wstring wide = panel::WideFromUtf8(dir);
      ::ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr,
                      SW_SHOWNORMAL);
    });
    actions.Children().Append(open_dir);

    auto quit = muxc::Button();
    quit.Content(box_value(hstring(L"退出 Glance")));
    quit.Foreground(ui::Brush(ui::theme().danger));
    quit.Click([this](const auto&, const auto&) { ConfirmQuit(); });
    actions.Children().Append(quit);

    content_.Children().Append(ui::Card(actions));
  }

  void ConfirmQuit() {
    auto dialog = muxc::ContentDialog();
    dialog.XamlRoot(nav_.XamlRoot());
    dialog.Title(box_value(hstring(L"退出 Glance？")));
    dialog.Content(box_value(
        hstring(L"磁贴会一起关闭，之后可以从开始菜单重新启动。")));
    dialog.PrimaryButtonText(L"退出");
    dialog.CloseButtonText(L"取消");
    dialog.DefaultButton(muxc::ContentDialogButton::Close);
    dialog.PrimaryButtonClick([this](const auto&, const auto&) {
      CallAsync(panel::kMethodQuit, Json::Object(), {});
    });
    dialog.ShowAsync();
  }

  // 出错时给一条不打扰的提示：文案就在标题栏下面冒一行
  void ShowError(const panel::PanelResult& r) {
    const std::string text =
        "操作失败：" + r.error_code + " —— " + r.error_msg;
    status_text_.Text(Hs(text));
    status_text_.Foreground(ui::Brush(ui::theme().danger));
  }

  // ---------------- 事件 ----------------

  void HandleEvent(const std::string& name, const Json& payload) {
    (void)payload;
    if (name == panel::kEventCardsChanged) {
      LoadCards();
    } else if (name == panel::kEventSettingsChanged) {
      LoadSchema();
    } else if (name == panel::kEventActivate) {
      if (auto app_window = window_.AppWindow()) {
        app_window.Show();
      }
      window_.Activate();
      if (HWND hwnd = Hwnd()) {
        ::SetForegroundWindow(hwnd);
      }
    }
  }

  void SetConnected(bool ok, const std::string& error) {
    connected_ = ok;
    connect_error_ = error;
    UpdateStatus();
    RenderPage();
  }
};

// =====================================================================
// App
// =====================================================================

// PanelUi 的完整定义就在上面；unique_ptr 的清理路径需要它，所以写在这里
App::App() = default;
App::~App() = default;

void App::Start(const std::string& socket_path, const std::string& token) {
  socket_path_ = socket_path;
  token_ = token;

  core_.Close();
  std::string error;
  if (!core_.Connect(socket_path, token, &error)) {
    panel::LogLine("W [app] 连不上核心：" + error);
    if (ui_) ui_->SetConnected(false, error);
    return;
  }
  panel::LogLine("I [app] 已连上核心 " + core_.core_display_version());

  if (ui_) {
    ui_->SetConnected(true, {});
    ui_->LoadAll();
  }
}

void App::OnLaunched(const LaunchActivatedEventArgs&) {
  socket_path_ = panel::startup().socket_path;
  token_ = panel::startup().token;

  panel::LogLine("I [app] 面板启动，端点 " + socket_path_);
  const auto& theme = ui::DetectAndApplyTheme();
  panel::LogLine(std::string("I [app] 主题 ") + (theme.dark ? "深色" : "浅色"));

  // XAML 自己的回调路径（布局、事件分发）里抛出的异常不会经过我们的 try/catch，
  // 默认结果是 fail-fast：进程带着 0xC000027B 消失，什么都不留。
  // 这里接住它、记下来，并且不让它掀掉整个面板——设置界面画残了也好过没有。
  Application::Current().UnhandledException(
      [](const IInspectable&, const UnhandledExceptionEventArgs& args) {
        panel::Guard("xaml", [&] {
          panel::LogLine("E [xaml] 未处理异常：" +
                         panel::Utf8FromWide(args.Message().c_str()));
          args.Handled(true);
        });
      });

  // WinUI3 控件的主题资源（颜色/圆角/模板）都在 XamlControlsResources 里。
  // 有 App.xaml 的项目靠 XAML 自动挂上；我们是纯代码 UI，必须自己挂——
  // 否则控件的模板一展开就报 "Cannot find a Resource with the Name/Key ..."。
  Application::Current().Resources().MergedDictionaries().Append(
      muxc::XamlControlsResources());

  auto window = mux::Window();
  ui_ = std::make_unique<PanelUi>(this, window);
  panel::Guard("build", [&] { ui_->Build(980, 700); });
  panel::LogLine("I [app] 窗口就绪");

  core_.SetEventHandler([this](const std::string& name, const Json& payload) {
    auto queue = ui_ ? ui_->queue_ : nullptr;
    if (!queue) return;
    // payload 是引用，跨线程要拷贝
    const Json copy = payload;
    queue.TryEnqueue([this, name, copy] {
      panel::Guard("event", [&] {
        if (ui_) ui_->HandleEvent(name, copy);
      });
    });
  });

  Start(socket_path_, token_);
  panel::LogLine("I [app] 面板初始化完成");
}
