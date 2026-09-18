# 面板（WinUI3 原生）

Glance 设置面板的原生实现：C++/WinUI3，**独立进程**，通过 Unix domain socket
与核心通信（协议见 [../docs/panel-protocol.md](../docs/panel-protocol.md)）。

## 怎么建

```bash
# 依赖会自动从 NuGet 镜像下到仓库根的 .wasdk/（已 gitignore）
cmake -S panel -B panel/build -G "Visual Studio 17 2022" -A x64
cmake --build panel/build --config Release
```

找不到 `cmake` 的话，VS 生成工具自带的那个在：

```
C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\
  Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe
```

构建产物：
- `panel/build/Release/panel.exe`（+ 必须同目录的 `Microsoft.WindowsAppRuntime.Bootstrap.dll`）
- 同时会**自动装到核心旁边** `build/windows/x64/runner/Release/panel/panel.exe`——
  核心找面板的顺序就是 `<核心目录>/panel/panel.exe`，装好之后托盘的"设置"就会用它。

运行时要求：机器上装了 **Windows App Runtime 1.8**（`Get-AppxPackage *WindowsAppRuntime*`）。
没有的话面板会弹窗提示装运行时。

## 它长什么样

NavigationView 六个页面，**没有一个页面硬编码设置项**：

| 页面 | 数据来源 |
|---|---|
| 组件库 | `plugins.list`（点"添加"→ `cards.add`） |
| 已放置 | `cards.list`（改尺寸 / 移除 / 每张卡自己的设置项） |
| 外观 · 布局 · 其他 | `settings.schema` 的分组（boolean→开关，number→数字框，select→下拉，color→取色器，text→文本框） |
| 关于 | `app.info` + 打开数据目录 + 退出核心 |

核心加一个设置项或一个插件，**这里一行都不用改**。

## 这个构建为什么要自己搭

机器上只有 VS 生成工具（没有 IDE），而且这是 Flutter 工程里的一个独立小项目，
所以没有走 WinUI3 默认的 .vcxproj + NuGet 那套。CMake 里做的事，逐条对应
MSBuild 官方 targets 的等价物：

| 官方 targets 做的 | 这里怎么做的 |
|---|---|
| 下 NuGet 包 | `wasdk_package()`：下载到 `.wasdk/feed/`、解包到 `.wasdk/pkgs/` |
| 生成 C++/WinRT 投射头 | 直接调 Windows SDK 的 `cppwinrt.exe`（输入是 WinUI/IX/Foundation/WebView2 的 WinMD） |
| Windows App Runtime 启动 | 编 `WindowsAppRuntimeAutoInitializer.cpp` + `MddBootstrapAutoInitializer.cpp` + `UndockedRegFreeWinRT-AutoInitializer.cpp` |

## 踩过的坑（都写在代码注释里）

1. **`cppwinrt` 要一次给全 WinMD**：只给 `Microsoft.UI.Xaml.winmd` 会报
   `Type 'Microsoft.UI.Dispatching.DispatcherQueue' could not be found`，
   补一个又冒下一个。真正的集合是：WinUI 2 个 + InteractiveExperiences 3 个
   （`Microsoft.UI/Foundation/Graphics.winmd`，取 `metadata/10.0.18362.0/`）+
   Foundation 20 个 + WebView2 1 个。
2. **`Microsoft.WindowsAppRuntime.dll` 不能静态导入**：它在框架包里，进程启动
   那一刻动态依赖还没建立、按名字找不到它。必须开
   `MICROSOFT_WINDOWSAPPSDK_UNDOCKEDREGFREEWINRT_AUTO_INITIALIZE_LOADLIBRARY`，
   改成 bootstrap 之后再 `LoadLibrary`。
3. **`WindowsAppSDK-VersionInfo.h` 只在 Runtime 包里**（不在 WinUI/Foundation/Base
   里），自动初始化源文件要 `#include` 它。
4. **C++/WinRT 投射头要一个个显式 include**：少了
   `Windows.Foundation.Collections.h` 会报"必须首先定义此函数"这种看不出因果的错。
5. **`TextBlock`/`Control` 在 `Controls` 命名空间**，`UIElement`/`FrameworkElement`
   在 `Microsoft.UI.Xaml`——混了就是一堆 "缺少类型说明符"。
6. `shellapi.h`/`dwmapi.h` 必须排在 `windows.h` 后面；`afunix.h` 必须排在
   `winsock2.h` 后面。
7. **纯代码 UI 要自己挂 `XamlControlsResources`**（有 App.xaml 的项目是 XAML
   代劳的），否则控件模板一展开就找不到主题资源。
8. 面板必须自己写日志（GUI 子系统没控制台），并把 XAML 的
   `Application.UnhandledException` 接住——不然崩了是"窗口一闪没了"，现场不留。

## 当前状态：**卡在最后一步**

已经跑通：
- 编译链接通过，exe 能启动；
- Windows App Runtime bootstrap 成功；
- **连上核心、完成 hello 握手**（核心日志有 `[panel] 面板已握手（v1）`）；
- 主题检测（跟随系统深浅色）、日志、异常兜底都在工作。

**没跑通**：创建 WinUI 控件时 XAML 找不到主题资源：

```
E [xaml] 未处理异常：Cannot find a resource with the given key: AcrylicBackgroundFillColorDefaultBrush.
```

（挂 `XamlControlsResources` 之前是 `TabViewButtonBackground`，同一个病。）

已经排除：应用自己的 `resources.pri`（用 makepri 生成过，无效）、把框架的
`Microsoft.UI.Xaml.Controls.pri` 与 `Microsoft.ui.xaml.resources.*.dll` 拷到 exe
旁边（无效）。**说明这不是"文件不在"，而是框架资源要经过 MSBuild targets 建立的
那套资源/清单注册链路**——手搓 CMake 到这一步成本已经不划算。

两条出路（见仓库提交记录里的讨论）：
- **A. 面板改用官方 .vcxproj + PackageReference**（仍由 CMake 的构建命令驱动调用，
  这样 PRI 生成、应用清单、XamlControlsResources 的注册全交给微软的 targets）；
- B. 继续在 CMake 里手搓应用清单 + PRI 合并（不确定性高）。
