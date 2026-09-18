# 面板的构建入口。
#
# 真正干活的工程文件是 panel/panel.vcxproj（官方 WinUI3 C++ 路线），这里只负责
# 用 VS 生成工具自带的 MSBuild 把它建出来，再把产物装到核心旁边。
#
# 为什么不自己编：XAML 的主题资源、控件模板、应用清单、PRI 资源索引，全靠
# WindowsAppSDK 的 MSBuild targets 在构建期建立。之前手搓 CMake 把编译、bootstrap、
# 与核心握手都跑通了，却始终卡在"XAML 找不到主题资源"这一步——那部分不该由使用者
# 复刻。完整排查记录见 panel/README.md。
#
# 用法（和核心那套 CMake 一个路子）：
#   cmake -S panel -B panel/build -G "Visual Studio 17 2022" -A x64
#   cmake --build panel/build --config Release

cmake_minimum_required(VERSION 3.28)
project(glance_panel LANGUAGES CXX)

if (NOT CMAKE_VS_MSBUILD_COMMAND)
  message(FATAL_ERROR
    "这个工程要用 Visual Studio 生成器配置，例如：\n"
    "  cmake -S panel -B panel/build -G \"Visual Studio 17 2022\" -A x64")
endif()
message(STATUS "MSBuild: ${CMAKE_VS_MSBUILD_COMMAND}")

set(PANEL_CONFIG "Release" CACHE STRING "面板构建配置")
set(PANEL_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/${PANEL_CONFIG}"
    CACHE PATH "面板产物目录")

# 面板装到哪里：核心找面板的顺序是 <核心目录>/panel/panel.exe → <核心目录>/panel.exe，
# 所以装进 panel/ 子目录就会自动被托盘的"设置"用上。
set(PANEL_DEPLOY_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../build/windows/x64/runner/Release/panel"
    CACHE PATH "把面板装到核心旁边")

add_custom_target(panel ALL
  COMMAND "${CMAKE_VS_MSBUILD_COMMAND}"
          "${CMAKE_CURRENT_SOURCE_DIR}/panel.vcxproj"
          /restore
          /p:Configuration=${PANEL_CONFIG}
          /p:Platform=x64
          "/p:PanelOutDir=${PANEL_OUT_DIR}"
          "/p:PanelIntDir=${CMAKE_CURRENT_BINARY_DIR}/obj"
          /v:minimal
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "构建 WinUI3 面板（panel.vcxproj）"
  VERBATIM)

add_custom_command(TARGET panel POST_BUILD
  # 先清空再拷：面板输出目录会随构建方式变化（比如从自包含切回框架依赖），
  # 留着上一轮的框架 DLL 会和新版本混在一起，运行时到底加载哪个说不清。
  COMMAND "${CMAKE_COMMAND}" -E remove_directory "${PANEL_DEPLOY_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PANEL_DEPLOY_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E copy_directory
          "${PANEL_OUT_DIR}" "${PANEL_DEPLOY_DIR}"
  COMMENT "安装面板到 ${PANEL_DEPLOY_DIR}")
