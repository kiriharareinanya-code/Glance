# Glance · 一瞥

Windows 桌面组件层——把时钟、天气、日历、待办、歌词做成可自由摆放的磁贴，贴在桌面上。Flutter + Win32，单进程，无常驻服务。

## 组件

- **时钟** —— 数字时钟，24/12 小时制、可选秒
- **天气** —— 小米天气数据，实况 + 5 日预报，IP 自动定位或手填城市
- **日历** —— 月历，农历、二十四节气、节假日，点选日期看倒计时
- **待办** —— 本地清单，行内设定截止日期
- **歌词** —— 读系统正在播放的音乐（网易云 + LRCLIB），滚动歌词、封面、进度控制

## 特性

- 磁贴自由拖拽 / 吸附 / 离散缩放（手机小组件式的「列×行」规格），每块屏一组布局
- 毛玻璃卡片 + Mica 质感背景，深浅色跟随系统
- 任务栏独立设置窗口，改动实时生效、自动落盘
- 桌面层常驻：显示桌面（Win+D）磁贴自动归位，开机自启

## 构建

依赖 Flutter（Windows desktop）与 Visual Studio C++ 工具链：

```bat
flutter build windows --release
```

产物：`build\windows\x64\runner\Release\glance.exe`

## 发版

```bat
tool\build_release.bat
```

构建 release → 拷贝 VC++ 运行库 → Inno Setup 打便携安装包（输出 `installer\out\`）。版本号唯一来源是 `pubspec.yaml` 的 `version:`；发版更新日志由 git-cliff 依据提交信息生成（`tool\cliff.toml`）。

## 开发说明

改了组件外观后重新生成组件库预览图（真实组件离线渲染，深浅两套）：

```
flutter test test/gen_previews_test.dart
```

`test/` 下的两个文件是**生成工具**而非断言测试：`gen_previews_test.dart` 出预览图，`logo_asset_gen_test.dart` 出关于页 logo。
