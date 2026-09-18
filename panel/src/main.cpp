// 面板进程入口。
//
// 这个程序不单独运行：端点与口令都由核心经命令行传进来（见 startup.h）。
//
// Windows App Runtime 的启动**不在这里**——它由 NuGet 包里的
// WindowsAppRuntimeAutoInitializer.cpp 在静态初始化阶段完成（自动建立
// 动态依赖 + 无清单的 WinRT 激活支持）。所以下面只管解析参数、起公寓、
// 交给 WinUI3 的 Application::Start。
#include <windows.h>

#include <shellapi.h>

#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/base.h>

#include <string>

#include "app.h"
#include "startup.h"
#include "text.h"

namespace {

void ShowError(const std::wstring& text) {
  ::MessageBoxW(nullptr, text.c_str(), L"Glance 设置",
                MB_ICONERROR | MB_OK | MB_SETFOREGROUND);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  panel::StartupInfo info;
  int argc = 0;
  if (LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc)) {
    for (int i = 1; i < argc; ++i) {
      const std::wstring arg = argv[i];
      if (arg == L"--socket" && i + 1 < argc) {
        info.socket_path = panel::Utf8FromWide(argv[++i]);
      } else if (arg == L"--token" && i + 1 < argc) {
        info.token = panel::Utf8FromWide(argv[++i]);
      }
    }
    ::LocalFree(argv);
  }

  if (info.socket_path.empty() || info.token.empty()) {
    // 直接双击进来就是这个结果：这里没有"配置界面"，面板只是核心的一层皮。
    ::MessageBoxW(nullptr,
                  L"这个程序由 Glance 核心启动，不单独运行。\n\n"
                  L"请右键任务栏托盘里的 Glance 图标，选“设置”。",
                  L"Glance 设置", MB_ICONINFORMATION | MB_OK);
    return 2;
  }
  panel::set_startup(std::move(info));

  try {
    // WinUI3 要求 STA
    winrt::init_apartment(winrt::apartment_type::single_threaded);
    winrt::Microsoft::UI::Xaml::Application::Start(
        [](auto&&) { winrt::make<App>(); });
  } catch (const winrt::hresult_error& e) {
    std::wstring msg = L"面板启动失败：\n";
    msg += e.message().c_str();
    msg += L"\n\n（多半是 Windows App Runtime 没装好。核心的日志里有更多线索。）";
    ShowError(msg);
    return 1;
  } catch (const std::exception& e) {
    ShowError(L"面板启动失败：\n" +
              panel::WideFromUtf8(static_cast<std::string>(e.what())));
    return 1;
  }
  return 0;
}
