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
