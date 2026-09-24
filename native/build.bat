@echo off
rem 一键构建 glance_native（CMake + Visual Studio 生成器）。
rem
rem 用 VS 生成器而不是 Ninja：它自己找 MSVC 工具链，不依赖 vcvars 环境，
rem 也不需要额外装 Ninja。命令行下等价于：
rem   cmake -S . -B build -G "Visual Studio 17 2022" -A x64
rem   cmake --build build --config Release
rem
rem 产物：native\build\Release\glance_native.exe（静态 CRT，单文件）
rem
rem 常用参数：
rem   --capture <png>   离屏渲染一帧存图，不开窗口（视觉验证用）
setlocal

set "BT=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
set "CMAKE=%BT%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"

if not exist "%CMAKE%" (
    where cmake >nul 2>nul && set "CMAKE=cmake"
)
if not exist "%CMAKE%" (
    echo [ERROR] cmake not found. Install Visual Studio Build Tools with the CMake component.
    exit /b 1
)

"%CMAKE%" -S "%~dp0." -B "%~dp0build" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 ( echo [ERROR] configure failed & exit /b 1 )

"%CMAKE%" --build "%~dp0build" --config Release
if errorlevel 1 ( echo [ERROR] build failed & exit /b 1 )

echo.
echo [OK] native\build\Release\glance_native.exe
endlocal
