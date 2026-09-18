// 核心 IPC 客户端：Unix domain socket + NDJSON，一行一帧。
//
// 对应 docs/panel-protocol.md。这里的实现顺序刻意与文档一致：
// 连上 → 发 hello（带 token）→ 之后才是普通方法调用。
//
// 线程模型：**接收在独立线程**，回调也在这个线程上触发。UI 层拿到结果后
// 自己往 DispatcherQueue 上扔（见 app.cpp），别在这里碰 UI 对象。
#pragma once

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <string>
#include <thread>

#include "json.h"

namespace panel {

// 协议版本：与 lib/panel/protocol.dart 的 kPanelProtocolVersion 必须一致
constexpr int kProtocolVersion = 1;

constexpr const char* kMethodHello = "hello";
constexpr const char* kMethodAppInfo = "app.info";
constexpr const char* kMethodQuit = "app.quit";
constexpr const char* kMethodPluginsList = "plugins.list";
constexpr const char* kMethodSettingsSchema = "settings.schema";
constexpr const char* kMethodSettingsGet = "settings.get";
constexpr const char* kMethodSettingsSet = "settings.set";
constexpr const char* kMethodCardsList = "cards.list";
constexpr const char* kMethodCardsAdd = "cards.add";
constexpr const char* kMethodCardsRemove = "cards.remove";
constexpr const char* kMethodCardsSetSize = "cards.setSize";
constexpr const char* kMethodCardsSetSetting = "cards.setSetting";
constexpr const char* kMethodWallpaper = "wallpaper.get";

constexpr const char* kEventCardsChanged = "cards.changed";
constexpr const char* kEventSettingsChanged = "settings.changed";
constexpr const char* kEventWallpaperChanged = "wallpaper.changed";
constexpr const char* kEventActivate = "activate";

struct PanelResult {
  bool ok = false;
  Json value;              // ok 时为返回体
  std::string error_code;  // 失败时为错误码
  std::string error_msg;
};

class PanelClient {
 public:
  using Callback = std::function<void(const PanelResult&)>;
  using EventHandler = std::function<void(const std::string&, const Json&)>;

  PanelClient() = default;
  ~PanelClient();

  PanelClient(const PanelClient&) = delete;
  PanelClient& operator=(const PanelClient&) = delete;

  // 连上并完成 hello 握手。失败时 error 里是给人看的原因。
  bool Connect(const std::string& socket_path, const std::string& token,
               std::string* error);
  void Close();
  bool connected() const { return running_.load(); }

  // 发起一次调用。回调在接收线程执行。
  void Call(const std::string& method, Json params, Callback cb);

  void SetEventHandler(EventHandler h) { on_event_ = std::move(h); }

  // 握手拿到的核心版本（面板标题/关于页要显示）
  std::string core_version() const { return core_version_; }
  std::string core_display_version() const { return core_display_version_; }

 private:
  void ReaderLoop();

  std::atomic<bool> running_{false};
  intptr_t sock_ = -1;
  std::thread reader_;

  std::mutex write_mu_;
  std::mutex pending_mu_;
  std::map<int, Callback> pending_;
  int seq_ = 0;

  EventHandler on_event_;
  std::string core_version_;
  std::string core_display_version_;
};

}  // namespace panel
