// 面板应用：WinUI3 窗口 + 导航 + 页面。
#pragma once

#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.h>

#include <memory>
#include <string>

#include "ipc.h"

struct PanelUi;

// WinUI3 的 Application 子类。整个进程只有一个窗口。
struct App : winrt::Microsoft::UI::Xaml::ApplicationT<App> {
  // 构造/析构都声明在这里、定义在 app.cpp：unique_ptr<PanelUi> 的清理路径
  // 需要 PanelUi 的完整定义，而 app.h 里它只是个前置声明
  App();
  ~App();

  void OnLaunched(
      const winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs& args);

  void Start(const std::string& socket_path, const std::string& token);

  panel::PanelClient core_;
  std::unique_ptr<PanelUi> ui_;
  std::string socket_path_;
  std::string token_;
};
