// Glance 原生版入口。
//
// 与 Flutter 版并存（native\ 目录），两边可以同时构建、对比内存与观感，
// 迁移完成前互不影响。
#include <windows.h>

#include <objbase.h>

#include <string>

#include "app.h"
#include "platform/log.h"

namespace {

// 解析 `--capture <png 路径>`：离屏渲染一帧存图，不开窗口。
// 参数就这一个，不值得上命令行解析库——按空格切、支持引号包路径即可。
std::wstring ParseCapturePath(const wchar_t* command_line) {
  if (command_line == nullptr || *command_line == L'\0') return {};
  const std::wstring args(command_line);
  const std::wstring key = L"--capture";
  const size_t pos = args.find(key);
  if (pos == std::wstring::npos) return {};

  size_t start = pos + key.size();
  while (start < args.size() && args[start] == L' ') ++start;
  if (start >= args.size()) return {};

  if (args[start] == L'"') {
    const size_t end = args.find(L'"', start + 1);
    return end == std::wstring::npos ? args.substr(start + 1)
                                     : args.substr(start + 1, end - start - 1);
  }
  const size_t end = args.find(L' ', start);
  return end == std::wstring::npos ? args.substr(start)
                                   : args.substr(start, end - start);
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE /*prev*/, LPWSTR command_line,
                      int /*show*/) {
  // 第一行就落日志：静态 CRT + GUI 子系统下，启动即崩时会连一行字都留不下。
  glance::Log(L"[boot] wWinMain entered");

  // 单实例：命名互斥体。没有这道闸，用户多点几次就是几个覆盖层叠着跑——
  // 每个都占 40MB 内存、都在画同一张卡，桌面组件的省内存就白省了。
  // （第一版忘了做，用户双击三次就起了三个实例。）
  HANDLE single_instance =
      CreateMutexW(nullptr, TRUE, L"GlanceNative.SingleInstance");
  if (single_instance != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    glance::Log(L"[boot] another instance is already running, exit");
    CloseHandle(single_instance);
    return 0;
  }

  // DPI 感知必须在创建任何窗口之前声明。PerMonitorV2 下 150% 缩放
  // 拿到的是真实物理像素；不声明的话系统会按 96 DPI 交一张被放大过的
  // 位图，再渲染出来字全是糊的（Flutter 版当年也踩过这个）。
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

  // D2D/DWrite 自身不强制 COM 单元，但 WIC（位图编解码、以后的壁纸解码）
  // 和系统媒体控件都在 COM 上，统一在这里初始化省得以后漏。
  const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // App 必须在内层作用域里析构：它持有的 WIC/D2D/D3D 对象是 COM 对象，
  // 释放动作要发生在 CoUninitialize() **之前**。放在外层的话（第一版就是
  // 这么写的）退出时会段错误——COM 运行时已经卸了，析构再去碰它们就炸。
  int exit_code = 0;
  {
    glance::App app;
    const std::wstring capture_path = ParseCapturePath(command_line);
    if (!capture_path.empty()) {
      exit_code = app.RenderToPng(capture_path);
    } else {
      exit_code = app.Start(instance) ? app.Run() : 1;
    }
  }
  glance::Log(L"[boot] exit code=%d", exit_code);

  if (single_instance != nullptr) {
    ReleaseMutex(single_instance);
    CloseHandle(single_instance);
  }
  if (SUCCEEDED(com)) CoUninitialize();
  return exit_code;
}
