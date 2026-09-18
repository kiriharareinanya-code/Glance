# WinUI3 原生面板的构建脚本。
#
# 为什么是 CMake 而不是 .vcxproj：
#   1. 这台机器只装了 VS 生成工具，没有 IDE；CMake 的 VS 生成器照样能驱动它，
#      而且和核心（Flutter 那套 CMake）是同一种构建方式；
#   2. 面板要的 WindowsAppSDK 依赖可以有话直说地写在这里（下载/解包/生成
#      C++/WinRT 投射），不用去猜 MSBuild 的 NuGet 还原。
#
# 构建：
#   cmake -S panel -B panel/build -G "Visual Studio 17 2022" -A x64
#   cmake --build panel/build --config Release
# 或者直接用仓库里的 tool/build_panel.dart（会顺手找 VS 自带的 cmake）。
#
# 依赖放在仓库根的 .wasdk/（已 gitignore），首次构建会从 NuGet 镜像下载。

cmake_minimum_required(VERSION 3.28)
project(glance_panel LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 与已安装的 Windows App Runtime 1.8 对齐。换成别的版本要同时确认机器上
# 装了对应版本的运行时（`Get-AppxPackage *WindowsAppRuntime*`）。
set(WASDK_VER_SDK 1.8.251003001)
set(WASDK_VER_BASE 1.8.250831001)
set(WASDK_VER_FOUNDATION 1.8.250906002)
set(WASDK_VER_WINUI 1.8.250906003)
set(WASDK_VER_IX 1.8.250906004)
set(WASDK_VER_RUNTIME 1.8.251003001)  # 只有它带 WindowsAppSDK-VersionInfo.h
set(WASDK_VER_WEBVIEW2 1.0.3179.45)

# 静态库是别人编好的，运行时库必须对得上，否则 LNK2038
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")

set(WASDK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.wasdk")
set(WASDK_FEED "${WASDK_ROOT}/feed")
set(WASDK_PKGS "${WASDK_ROOT}/pkgs")
set(WASDK_MIRROR "https://nuget.azure.cn/v3-flatcontainer"
    CACHE STRING "NuGet 源（国内镜像；官方是 api.nuget.org/v3-flatcontainer）")

# ---------------------------------------------------------------------------
# 依赖：下载 + 按需解包（只要 metadata / include / 静态库 / x64 运行时）
# ---------------------------------------------------------------------------
function(wasdk_package id ver)
  set(nupkg "${WASDK_FEED}/${id}.${ver}.nupkg")
  if (NOT EXISTS "${nupkg}")
    message(STATUS "下载 ${id} ${ver} …")
    file(DOWNLOAD "${WASDK_MIRROR}/${id}/${ver}/${id}.${ver}.nupkg" "${nupkg}"
         STATUS download_status)
    list(GET download_status 0 download_code)
    if (NOT download_code EQUAL 0)
      list(GET download_status 1 download_message)
      message(FATAL_ERROR
        "下载 ${id} ${ver} 失败：${download_message}\n"
        "也可以手动把 nupkg 放到 ${WASDK_FEED}/ 再重新配置。")
    endif()
  endif()

  set(dest "${WASDK_PKGS}/${id}/${ver}")
  if (NOT EXISTS "${dest}/.unpacked")
    file(MAKE_DIRECTORY "${dest}")
    # 整包解出。想只挑需要的子目录（metadata/include/lib/runtimes）用
    # PATTERNS 也行，但各子包目录结构不一致，少一个模式 tar 就报错退出，
    # 换来的是脆弱的构建脚本——多占几百兆磁盘更划算。
    file(ARCHIVE_EXTRACT INPUT "${nupkg}" DESTINATION "${dest}")
    file(TOUCH "${dest}/.unpacked")
  endif()
endfunction()

wasdk_package(microsoft.windowsappsdk.winui ${WASDK_VER_WINUI})
wasdk_package(microsoft.windowsappsdk.foundation ${WASDK_VER_FOUNDATION})
wasdk_package(microsoft.windowsappsdk.interactiveexperiences ${WASDK_VER_IX})
wasdk_package(microsoft.windowsappsdk.runtime ${WASDK_VER_RUNTIME})
wasdk_package(microsoft.web.webview2 ${WASDK_VER_WEBVIEW2})

set(WINUI_DIR "${WASDK_PKGS}/microsoft.windowsappsdk.winui/${WASDK_VER_WINUI}")
set(FOUNDATION_DIR
    "${WASDK_PKGS}/microsoft.windowsappsdk.foundation/${WASDK_VER_FOUNDATION}")
set(IX_DIR
    "${WASDK_PKGS}/microsoft.windowsappsdk.interactiveexperiences/${WASDK_VER_IX}")
set(WEBVIEW2_DIR
    "${WASDK_PKGS}/microsoft.web.webview2/${WASDK_VER_WEBVIEW2}")
set(RUNTIME_DIR
    "${WASDK_PKGS}/microsoft.windowsappsdk.runtime/${WASDK_VER_RUNTIME}")

# ---------------------------------------------------------------------------
# C++/WinRT 投射：WinUI3 的 C++ 头文件不是现成的，得从 WinMD 生成。
# 官方靠 MSBuild 目标做这件事；这里等价地自己调一次 cppwinrt.exe。
# ---------------------------------------------------------------------------
if (NOT PANEL_CPPWINRT)
  file(GLOB _cppwinrt_candidates
       "C:/Program Files (x86)/Windows Kits/10/bin/*/x64/cppwinrt.exe"
       "C:/Program Files/Windows Kits/10/bin/*/x64/cppwinrt.exe")
  if (_cppwinrt_candidates)
    list(SORT _cppwinrt_candidates)
    list(GET _cppwinrt_candidates -1 PANEL_CPPWINRT)
  endif()
endif()
if (NOT PANEL_CPPWINRT OR NOT EXISTS "${PANEL_CPPWINRT}")
  message(FATAL_ERROR
    "找不到 cppwinrt.exe。装一个 Windows 10/11 SDK（含 C++ 工具）即可，"
    "或者用 -DPANEL_CPPWINRT=<路径> 指定。")
endif()
message(STATUS "cppwinrt: ${PANEL_CPPWINRT}")

set(GEN_DIR "${CMAKE_BINARY_DIR}/gen")
set(GEN_STAMP "${GEN_DIR}/.generated")

# 注意顺序：cppwinrt 要一次拿到全部 WinMD，缺一个就会报
# "Type '…' could not be found"（依赖是逐个暴露出来的）。
file(GLOB FOUNDATION_WINMDS "${FOUNDATION_DIR}/metadata/*.winmd")
set(WINMDS
    "${WINUI_DIR}/metadata/Microsoft.UI.Xaml.winmd"
    "${WINUI_DIR}/metadata/Microsoft.UI.Text.winmd"
    "${IX_DIR}/metadata/10.0.18362.0/Microsoft.UI.winmd"
    "${IX_DIR}/metadata/10.0.18362.0/Microsoft.Foundation.winmd"
    "${IX_DIR}/metadata/10.0.18362.0/Microsoft.Graphics.winmd"
    "${WEBVIEW2_DIR}/lib/Microsoft.Web.WebView2.Core.winmd"
    ${FOUNDATION_WINMDS})

add_custom_command(
  OUTPUT "${GEN_STAMP}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${GEN_DIR}"
  COMMAND "${PANEL_CPPWINRT}" -in ${WINMDS} -ref sdk -out "${GEN_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E touch "${GEN_STAMP}"
  DEPENDS ${WINMDS}
  COMMENT "生成 C++/WinRT 投射头（Microsoft.UI.Xaml 等）"
  VERBATIM)

add_custom_target(panel_projections DEPENDS "${GEN_STAMP}")

# ---------------------------------------------------------------------------
# 面板可执行文件
# ---------------------------------------------------------------------------
add_executable(panel WIN32
  src/main.cpp
  src/app.cpp
  src/ipc.cpp
  src/log.cpp
  src/ui.cpp
  # Windows App Runtime 的自动初始化。三个文件是一组，缺一不可：
  #   AutoInitializer = 聚合器（带 init_seg(lib) 的静态对象，趁早跑）
  #   MddBootstrapAutoInitializer = 真正调 MddBootstrapInitialize2 建动态依赖
  #   UndockedRegFreeWinRT-AutoInitializer = 让 WinUI3 的类在**无清单**的
  #                                          情况下也能被激活（少了它会"类未注册"）
  "${FOUNDATION_DIR}/include/WindowsAppRuntimeAutoInitializer.cpp"
  "${FOUNDATION_DIR}/include/MddBootstrapAutoInitializer.cpp"
  "${FOUNDATION_DIR}/include/UndockedRegFreeWinRT-AutoInitializer.cpp")

add_dependencies(panel panel_projections)

target_include_directories(panel PRIVATE
  "${GEN_DIR}"
  "${WINUI_DIR}/include"
  "${IX_DIR}/include"
  "${FOUNDATION_DIR}/include"
  "${WEBVIEW2_DIR}/include"
  # WindowsAppSDK-VersionInfo.h 只有 Runtime 包里有：自动初始化要拿它
  # 读出"该找哪个版本的运行时"
  "${RUNTIME_DIR}/include")

target_compile_definitions(panel PRIVATE
  UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX
  MICROSOFT_WINDOWSAPPSDK_AUTOINITIALIZE_BOOTSTRAP
  MICROSOFT_WINDOWSAPPSDK_AUTOINITIALIZE_UNDOCKEDREGFREEWINRT
  MICROSOFT_WINDOWSAPPSDK_UNDOCKEDREGFREEWINRT_AUTO_INITIALIZE
  # 关键：Microsoft.WindowsAppRuntime.dll 住在框架包里，进程启动那一刻
  # 动态依赖还没建立、按名字根本找不到它。静态导入的后果是 exe 一启动就
  # 因为"找不到 DLL"退出（报的还是别的 api-set 名字，很难猜）。
  # 打开这个开关后改成：等 bootstrap 建好依赖，再 LoadLibrary 加载它。
  MICROSOFT_WINDOWSAPPSDK_UNDOCKEDREGFREEWINRT_AUTO_INITIALIZE_LOADLIBRARY)

# /utf-8 必须有：源码里全是中文，MSVC 默认按本地代码页读，会乱码
target_compile_options(panel PRIVATE /utf-8 /W3 /permissive-)

target_link_libraries(panel PRIVATE
  "${FOUNDATION_DIR}/lib/native/x64/Microsoft.WindowsAppRuntime.Bootstrap.lib"
  "${FOUNDATION_DIR}/lib/native/x64/Microsoft.WindowsAppRuntime.lib"
  windowsapp.lib
  ole32.lib
  shell32.lib
  dwmapi.lib
  ws2_32.lib
  user32.lib)

# Bootstrap.dll 必须和 exe 放在一起
add_custom_command(TARGET panel POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${FOUNDATION_DIR}/runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"
    "$<TARGET_FILE_DIR:panel>"
  COMMENT "拷 Bootstrap.dll 到输出目录")

# 顺手装到核心旁边：核心找面板的顺序是 <核心目录>/panel/panel.exe → panel.exe，
# 所以拷到 panel/ 子目录就会自动被托盘的"设置"用上。
set(PANEL_DEPLOY_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../build/windows/x64/runner/Release/panel"
    CACHE PATH "把面板装到核心旁边（托盘设置会优先用它）")
add_custom_command(TARGET panel POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${PANEL_DEPLOY_DIR}"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "$<TARGET_FILE:panel>" "${PANEL_DEPLOY_DIR}/panel.exe"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${FOUNDATION_DIR}/runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"
    "${PANEL_DEPLOY_DIR}/Microsoft.WindowsAppRuntime.Bootstrap.dll"
  COMMENT "安装面板到 ${PANEL_DEPLOY_DIR}")
