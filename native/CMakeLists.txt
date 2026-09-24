cmake_minimum_required(VERSION 3.20)
project(glance_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

file(GLOB_RECURSE SRC CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")

add_executable(glance_native WIN32 ${SRC})

# 头文件按 src 内的相对路径书写（#include "platform/win_window.h"），
# 这样目录结构就是模块结构，不用满篇 ../。
target_include_directories(glance_native PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

# UNICODE/_UNICODE：全宽字符 API，和现有 runner 一致
# WIN32_LEAN_AND_MEAN + NOMINMAX：别拉进 winsock/旧 GDI 头，别让 windows.h 定义 max/min 宏
target_compile_definitions(glance_native PRIVATE
  UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)

# /utf-8：源码里有中文注释和字符串，不加这个 MSVC 会按 GBK 读，注释会把行尾吃掉
# /permissive-：标准一致模式，早暴露问题
target_compile_options(glance_native PRIVATE /utf-8 /W4 /permissive-)

# C++/WinRT（platform/smtc.cpp 读系统媒体控件）要求标准库异常可用。
# 用 C++20 的标准协程，不需要旧版的 /await。
target_compile_definitions(glance_native PRIVATE
  "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")

target_link_libraries(glance_native PRIVATE
  d2d1 d3d11 dxgi dwrite dcomp windowscodecs winhttp shell32)
# C++/WinRT 的运行时（RoGetActivationFactory 等）在 windowsapp.lib
target_link_libraries(glance_native PRIVATE "windowsapp.lib")

# 静态链接 CRT：目标是单 exe 分发，不依赖 VC++ 可再发行包
set_property(TARGET glance_native PROPERTY MSVC_RUNTIME_LIBRARY
  "MultiThreaded$<$<CONFIG:Debug>:Debug>")
