# 面板（WinUI3 原生）

Glance 设置面板的原生实现：C++/WinUI3，**独立进程**，通过 Unix domain socket
与核心通信（协议见 [../docs/panel-protocol.md](../docs/panel-protocol.md)）。

## 怎么建

```bash
# 用 VS 生成工具自带的 cmake 配置（PATH 里没有的话见下面的路径）
cmake -S panel -B panel/build -G "Visual Studio 17 2022" -A x64
cmake --build panel/build --config Release
```

cmake 在 VS 生成工具里的位置：

```
C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\
  Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe
```

构建入口是 `panel/CMakeLists.txt`，真正干活的是 **`panel/panel.vcxproj`**
（官方 WinUI3 C++ 工程文件），由 CMake 转手调用 MSBuild。产物：

- `panel/build/Release/panel.exe`（框架依赖：只要 `Microsoft.WindowsAppRuntime.Bootstrap.dll`
  + `panel.pri` 在它旁边就行，其余 DLL 由机器上装的 Windows App Runtime 提供）
- 构建结束会**自动装到核心旁边** `build/windows/x64/runner/Release/panel/`——
  核心找面板的顺序就是 `<核心目录>/panel/panel.exe`，装好之后托盘的"设置"就用它。

依赖：`Microsoft.WindowsAppSDK.{Base,Foundation,InteractiveExperiences,WinUI,Runtime}`
+ `Microsoft.Web.WebView2` + `Microsoft.Windows.CppWinRT`，版本钉死在 vcxproj 里。
NuGet 源见 `panel/nuget.config`（本地 `.wasdk/feed` 优先，其次国内镜像）。

运行时要求：机器上装着 **Windows App Runtime 1.8**（`Get-AppxPackage *WindowsAppRuntime*`）。

## 它长什么样

左侧自绘导航 + 右侧内容，六个页面**没有一个硬编码设置项**：

| 页面 | 数据来源 |
|---|---|
| 组件库 | `plugins.list`（点"添加"→ `cards.add`；没空闲屏时按钮置灰） |
| 已放置 | `cards.list`（改尺寸 / 移除 / 每张卡自己的设置项） |
| 外观 · 布局 · 其他 | `settings.schema` 的分组（boolean→开关，number→数字框，select→下拉，color→取色器，text→文本框） |
| 关于 | `app.info` + 打开数据目录 + 退出核心 |

核心加一个设置项或一个插件，**这里一行都不用改**。

## 诊断开关（排查这类问题很有用）

面板是 GUI 子系统，没有控制台，出问题就是"窗口一闪没了"。所以它自己写日志
（`panel.log`，在 exe 同目录，写不进去就退到 `%TEMP%`），并提供了几个开关：

| 开关 | 用途 |
|---|---|
| `--minimal` | 只开一个空窗口 + TextBlock，不连核心、不建任何控件 |
| `--minimal-xcr` | 上面这个 + 手动挂 `XamlControlsResources`（用来复验这件事能不能做） |
| `--selftest` | 数据到位后把六个页面逐个建一遍，逐页记日志（验证"每页都能画"） |

`--minimal` / `--minimal-xcr` 这一对就是当初挖出资源问题的那把刀：前者永远正常、
后者必崩，所以问题一定在"手动挂资源字典"这件事上，而不是整个进程的资源环境。

## 踩过的坑（按踩到的顺序）

### 构建方式

1. **`WindowsAppSDKSelfContained` 默认为 true**（用拆分包而不是聚合包
   `Microsoft.WindowsAppSDK` 时）。自包含模式要求应用自己携带整套框架文件 +
   合并好的资源索引，缺了后者就会在创建控件时报找不到主题资源。
   解决：显式 `<WindowsAppSDKSelfContained>false</WindowsAppSDKSelfContained>`，
   并加一条 `Microsoft.WindowsAppSDK.Runtime` 的引用（框架依赖模式的硬性要求，
   Base.targets 会检查）。
2. **WebView2 的 WinMD 要直接引用 `Microsoft.Web.WebView2` 包**：它是 WinUI 的
   传递依赖，而传递依赖的 `build/` 资产不会导入，于是 C++/WinRT 投射生成报
   `Type 'Microsoft.Web.WebView2.Core.CoreWebView2' could not be found`。
3. **`NuGetTargetMoniker` / `NuGetRuntimeIdentifier` 必须显式写**：C++ 工程不会
   自动填，缺了 NuGet 的解析任务就抛"序列不包含任何元素"（完全看不出因果）。
4. XML 注释里**不能出现 `--`**（我写了 `cmake --build`，MSBuild 直接判清单非法）。
5. 链接要带 `dwmapi`（深色边框）、`shell32`（打开数据目录）、`ws2_32`（UDS）、
   `windowsapp`。

### 运行时：两个真正让面板"窗口一闪没了"的原因

6. **不要手动挂 `XamlControlsResources`**。WinUI 1.8 里它构造时自己就会抛
   `Cannot find a resource with the given key: AcrylicBackgroundFillColorDefaultBrush`
   （那个键已经不在它包含的字典里了）。纯代码 UI 不需要它——框架自己提供控件主题资源。
   这是最初 `TabViewButtonBackground` / `AcrylicBackgroundFillColorDefaultBrush`
   两个"找不到资源"的真正来源，害我先去怀疑了构建系统（换成官方 vcxproj 也没用，
   因为根因不在那里）。
7. **`NavigationView` 在这版运行时里不能用**：它的默认模板引用
   `TabViewButtonBackground`，运行时那个键不存在，模板一展开就抛异常把进程带走。
   所以左侧导航是**自绘**的一列按钮（见 `Build()`），顺带更接近 Win11 设置页的观感。

### 排查手法（值得复用）

- **给 GUI 进程写日志文件**，并把 `Application::Current().UnhandledException`
  接住（`args.Message()`）——XAML 自己的回调路径里抛的异常不经过普通 try/catch，
  默认结果就是 fail-fast（退出码 `0xC000027B`），什么都不留。第 6、7 条就是这条
  钩子打印出来的。
- **把 UI 构建分块加护栏**（每页一个 `Guard`）：一页的控件缺资源只损失那一页，
  不至于整个面板打不开。
- **二分**：`--minimal` vs `--minimal-xcr` 一次就把范围从"整个进程"缩到"一个类型"。
