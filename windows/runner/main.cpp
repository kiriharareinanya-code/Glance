#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <ole2.h>
#include <windows.h>

#include "flutter_window.h"
#include "smtc.h"
#include "splash_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  //
  // 用 OleInitialize 而不是原来的 CoInitializeEx：它内部就是
  // CoInitializeEx(APARTMENTTHREADED)，额外把 OLE 子系统也起起来。
  // RegisterDragDrop 硬性要求 OLE 已初始化，只 CoInitializeEx 的话
  // 拖放注册会失败（返回 CO_E_NOTINITIALIZED）。
  ::OleInitialize(nullptr);

  // 启动幕布要赶在引擎之前立起来。
  //
  // 下面 FlutterWindow::CreateOverlay 会去构造 FlutterViewController，那一步
  // 阻塞几百毫秒；而磁贴窗口本身要等 Flutter 第一帧才显示。这中间屏幕上什么
  // 都没有，用户只能干等。幕布跑在自己的线程上，这段时间照样能动。
  SplashWindow::instance()->Start(instance);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // 先留一份副本：set_dart_entrypoint_arguments 会把原 vector move 走，
  // 之后再遍历它就是空的。
  const std::vector<std::string> args_copy = command_line_arguments;

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // 覆盖整个虚拟屏幕，而不是主显示器：多显示器下卡片可以放到任意一块屏上。
  // SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN 可能为负（副屏在主屏左侧或上方）。
  const int vx = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int vy = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int vw = ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int vh = ::GetSystemMetrics(SM_CYVIRTUALSCREEN);

  // --raise：让磁贴窗口浮到最前，只为了能截到图。
  //
  // 磁贴常驻 Z 序最底是它的本分，代价是任何屏幕截图都只会拍到压在上面的程序；
  // 而 PrintWindow 对 Flutter 的 DirectComposition 表面只返回全黑（实测），
  // 所以验证磁贴长什么样时需要这么一个开关。平时绝不要用。
  bool raise = false;
  for (const auto& a : args_copy) {
    if (a == "--raise") raise = true;
  }

  FlutterWindow window(project);
  if (!window.CreateOverlay(L"Glance 一瞥", vx, vy, vw, vh, /*topmost=*/raise)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // 幕布拉开时要让磁贴同时现身，把窗口句柄给它
  SplashWindow::instance()->SetRevealTarget(window.GetHandle());

  // --smtc-dump：把系统媒体控件里各播放器实际给出的字段原样打到 stdout。
  // 不同播放器给的东西差别很大（浏览器往往没有歌手），得先看真实数据再决定
  // 歌词怎么搜，不能照着文档想当然。
  for (const auto& a : args_copy) {
    if (a == "--smtc-dump") {
      Smtc::DumpOnce();
      break;
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::OleUninitialize();
  return EXIT_SUCCESS;
}
