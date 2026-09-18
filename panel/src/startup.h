// 启动参数：核心启动面板时通过命令行递过来的端点信息。
//
// 面板不自己去"发现"核心（读 panel-ipc.json 那条路是给 CLI 调试用的）：
// 端点和口令都以参数形式直接给它，短、明确、没有并发启动的歧义。
#pragma once

#include <string>

namespace panel {

struct StartupInfo {
  std::string socket_path;
  std::string token;
  // 诊断用：只开一个空窗口 + 一个 TextBlock，不建导航与任何设置控件。
  // 用来分辨"资源问题是整个进程级别的"还是"某个控件引出来的"。
  bool minimal = false;
  // 诊断用：最小窗口上再挂 XamlControlsResources
  bool minimal_with_resources = false;
  // 诊断用：数据到位后把每一页都建一遍，逐页记录成败（验证面板各页是否都能画）
  bool selftest = false;
};

inline StartupInfo& startup_storage() {
  static StartupInfo info;
  return info;
}

inline const StartupInfo& startup() { return startup_storage(); }
inline void set_startup(StartupInfo info) {
  startup_storage() = std::move(info);
}

}  // namespace panel
