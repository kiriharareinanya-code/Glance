# Glance · 一瞥

Windows 桌面组件层——把时钟、天气、日历、待办、歌词做成可自由摆放的磁贴，贴在桌面上。Flutter + Win32，单进程，无常驻服务。

## 组件

- **时钟** —— 数字时钟，24/12 小时制、可选秒
- **天气** —— 小米天气数据，实况 + 5 日预报，IP 自动定位或手填城市
- **日历** —— 月历，农历、二十四节气、节假日，点选日期看倒计时
- **待办** —— 本地清单，行内设定截止日期
- **歌词** —— 读系统正在播放的音乐，滚动歌词、封面、进度控制。词源并行汇总**网易云 / QQ 音乐 / 酷狗**，统一打分选出最匹配的一首（LRCLIB 兜底）

## 特性

- 磁贴自由拖拽 / 吸附 / 离散缩放（手机小组件式的「列×行」规格），每块屏一组布局
- 卡片记住自己「家在哪块屏的哪个位置」，改分辨率 / 缩放 / 插拔显示器后按屏内相对位置钉回原处
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

### 预览图生成

改了组件外观后重新生成组件库预览图（真实组件离线渲染，深浅两套）：

```
flutter test --tags gen --run-skipped
```

`test/` 下有几个文件顶着 `_test.dart` 后缀，但自述都不是断言测试——它们是
**生成工具**（出预览图、logo）或**联网自证**，会写真实文件、发真实网络请求。
`dart_test.yaml` 里用 `gen` / `live` 两个 tag 默认跳过（实测跑测试 58s → 23s，
且不再污染 `assets/previews/*.png`）。

**必须带 `--run-skipped`**：`skip` 是无条件跳过，`--tags` 只是筛选，两者独立、
互不覆盖——只写 `--tags gen` 会得到 "All tests skipped"。
