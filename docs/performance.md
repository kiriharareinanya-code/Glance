# 性能：这一轮改了什么，为什么

面向复查的人。每一条都写清「原来每帧/每次调用在干什么 → 现在在干什么 →
凭什么认为有效」，以及**哪些地方刻意没动**。

改动集中在四个方向：过度重建、长列表全量构建、主 isolate 上的重计算、
以及会把帧预算吃光的同步 I/O。

验证口径统一是两条：

- `flutter analyze --no-pub` → 全项目 0 issue
- `flutter test --no-pub` → **354/354 通过**（改动前是 350，多出的 4 条是
  本文 §1.1 引入的回归护栏）

---

## 1. 过度重建（收益最大的一块）

### 1.1 拖拽卡片：每帧 N 棵插件渲染树 → 1 棵

**原来**：`DesktopSurfaceState._onPointerMove` 每收到一个 pointer move 就
`setState`。`setState` 意味着 `build()` 重跑，Stack 里全部 N 张卡的
`CardView` 和插件正文（`buildPluginBody`）**全部**重建一遍。5 张卡就是每帧
5 份渲染树，60fps 的 16.7ms 帧预算根本不够分。

**现在**：位置不再存在 surface 的 State 里，而是每张卡一份
`ValueNotifier<Offset>`（`lib/ui/surface.dart:_pos`）。拖拽只写这一个 notifier，
由新的 `_CardTile` 组件自己监听、自己重建。拖拽期间 surface 一次也不重建，
其余 N-1 张卡连 `build()` 都不进。

配套：

- 「其余卡片的矩形表」只在 `_beginDrag` 算一次（整场拖拽只有被拖的那张在动）
- 吸附的窗口范围同样按下时取一次
- `_regionSig()` 每帧拼一个几百字节的字符串只为跟上一轮比对 → 改成
  数值比对 + 只在真变了时才回填
- 辅助线自带 `RepaintBoundary`，免得它每帧变化把整面墙的图层拖脏
- 「正在拖拽」也做成 notifier，这样"开始拖/结束拖"这两个瞬间不必重建整个
  surface 就能把位移动画掐成零时长（原来的语义）

**回归护栏**：`test/surface_drag_rebuild_test.dart`，4 条。实测 5 张卡拖 10 帧：

| | 被拖的卡 | 其余 4 张合计 |
|---|---|---|
| 改动前 | 10 | **40** |
| 改动后 | 10 | **0** |

顺带钉住了两件容易踩的事：`Stack → ValueListenableBuilder → AnimatedPositioned`
这条组合必须成立（ParentDataWidget 不能被夹在会产出 RenderObject 的 widget
中间），以及拖拽矩形缓存不能串到下一场拖拽。

### 1.2 设置面板：拖一个滑块重建整页 400+ 个控件

- `_commit()` 拆成 `_commitLive()`（不 setState）+ `_commit()`（setState）。
  拖动期间走 `_commitLive`，松手时 `_DragSlider` 补一次 `_commit`。
  **去抖和 `_logSettingsDiff` 原样保留在每一帧上** —— 前者是为了不让外层
  在拖动期间把插件运行时全销毁重建，后者是排查设置类问题唯一的线索。
- 新的 `_DragSlider` 把拖动中的值存在自己的 State 里（对齐
  `kit.dart` 里 `PluginSlider` 已有的做法），拖动中只重建那一行。
- 侧栏宽度拖动 → `ValueNotifier`，只重排侧栏那一小块。

**代价（要知道）**：依赖滑块当前值才显示的提示文字（染色/透明度的警告）
会在**松手时**才出现，而不是拖动中。这是"只重建一行"的必然结果，数值本身
仍然每帧写穿。

### 1.3 其它过度重建

- 搜索框每敲一个字重建整个面板 → `ValueNotifier`，输入时零 `setState`
- `card_view.dart`：`_baseColor / _brightBackdrop / _fill / _foreground / _edge`
  原本是 getter，一次 build 里被问到四五遍（每次重跑 HSL 换算）→ 改成算一次传下去
- 同一个文件里 `Listenable.merge([...])` 原本每次 build 现建 → 提成 `static final`
- 天气卡正反面原本每次自动翻页都重建 ~275 行 → 缓存 `Widget` 实例，
  命中同一实例时 `Element.updateChild` 直接短路

---

## 2. build 路径上的同步 I/O（最隐蔽的一种）

### 2.1 `CardView`：每帧 3N 次 `File.existsSync()`

`_bgImageFile` 用了 `existsSync()`，而它在一次 build 里被问到**三次**
（`_brightBackdrop` 走两遍，`_edge`/`foreground` 各一次）。拖 N 张卡 =
每帧 3N 次同步磁盘 stat。在机械盘、映射盘或杀软挂钩的文件系统上，单次
stat 就够吃掉一帧。

改成 2 秒缓存。面板开着期间这些文件只有"选中背景图"和"清除背景图"两个写
入口，2 秒足够让外部改动被重新发现。同一改动也用在 `panel.dart:_bgPicker`
（那里更严重：每张卡一次，拖滑块时每帧触发）。

### 2.2 壁纸：`reg query` 每帧 fork 一个进程

`_wallpaperPath()` 每次 `refresh()` 都 `Process.run('reg', ...)`。一次进程
创建在 Windows 上通常 10~30ms（还带 DLL 加载和杀软扫描），已经抵得上大半帧
预算；而动态壁纸下刷新间隔可以调到几十毫秒，等于每一帧都在拉起 `reg.exe`。
现在缓存，托盘「刷新壁纸模糊」和显示器插拔时显式作废。

### 2.3 改任何设置都重抓整屏桌面

`onPanelChanged` 无条件调 `_loadWallpaper()`，而它是一次**全桌面捕获 +
高斯模糊 + 缩略图回读 + 莫奈取色**，几百毫秒起步。于是「改网格间距」、
「改吸附阈值」这种跟壁纸八竿子打不着的操作也会白抓一次，表现就是松手后
面板卡一下。现在只比对壁纸相关的 5 项；显示器插拔那条路径特意抹掉记账，
保证分辨率变化时仍然重抓。

---

## 3. 长列表 / 每帧重复计算

- 待办列表 `SingleChildScrollView + Column` → `ListView.builder`
  （视口是有界的，滚动行为逐条比对过一致），并把 `DateTime.now()` 从
  每行一次提到每次重绘一次
- 日历：42 格每次 draw 都重算农历 → 按日期 memo，跨月/跨天才清
- `LyricsView.hasTranslation` 从 O(n) getter 改成构造时算一次
- `snap.resolve`：`<double>{0, gutter}` 这个 Set 原本写在遍历每张卡的循环体里，
  等于每帧每张卡各 new 两个哈希 Set → 提到循环外
- 16 元素饱和度矩阵每帧 new 一个 → 按值缓存
- 天气 5 天预报循环里的 5 次 `DateTime.now()` → 提到循环外

---

## 4. 主 isolate 上的重计算（歌词链路）

歌词的 60ms tick 在 UI isolate 上跑解析、打分、优化。这里原来一次换歌能吃掉
几百毫秒，表现为歌词卡卡住。

| 改动 | 位置 | A/B 实测 |
|---|---|---|
| 3DES（QQ 音乐 QRC）上 `compute()` + 每块复用暂存缓冲 + 密钥表只排一次 | `decrypters/qrc/` | **2.15×**，80 kB 从 ~115ms → ~54ms，且不再占 UI isolate |
| `compareName` 删掉 2 次冗余归一化 + 单条 memo | `name_match.dart` | **1.77×**（26.0 → 14.7 µs/候选） |
| 词表预小写（原来每次比较都 `toLowerCase()` 全部 ~94 条，最坏一行扫 6 遍） | `info_lines.dart` | **2.68×**，最坏 564 次扫描 → 1 次 |
| `chineselizeArtist` 线性扫 2077 条 → Map 查表 | `artist_helper.dart` | O(2077) → O(1) |
| `XmlName.parts(...)` 从"每次比较 new 一个"提成 9 个 `const` | `ttml_parser.dart` | 分配归零 |
| 类型探测：`_get()` 兜底的全表扫 + 整包 `toLowerCase().contains()` | `lyrics_type_detector.dart` | KRC **6.3×** / QRC **4.5×** / LRC **4.3×** / YRC **5.4×** |
| `toSC(force:true)` 两次全量字典转换 → 一次 | `chinese_helper.dart` | — |
| `removeDuoSpaces` 重扫循环 → 单次正则 | `string_helper.dart` | — |
| `BigInt.from(16).pow()` 每位一次 → Horner | `netease/api.dart` | 一次性，收益小 |

数字来自对着旧代码逐字拷贝做的 A/B 对拍，输出断言逐位一致。注意这是
`dart run` JIT 下的绝对值，**比例**才是能带到设备上的。

---

## 5. 刻意没动的地方

性能优化最容易干出来的事就是"顺手把有理由的设计当成 bug 删了"。以下全部
保留，理由都写在代码注释里：

- **歌词整列铺开 + 60ms 慢 tick**（`lyrics.dart:621-655`、`:1171-1174`）
  注释里写着"数组铺的行数随进度增长"和"整棵树 13ms/帧"，是量过的取舍。
  只在里面把重复的 `TextStyle` 分配提成了缓存，改前改后渲染出的
  `lyrics.png` **SHA-256 完全一致**。
- **`PluginSlider` 的本地拖动值**（`kit.dart:156-160`）、**`_TileHover` 的
  每格独立 State**、**`morph_icons` 的 `_rest` didUpdateWidget**、
  **`context.unmount()` 批量清 timer** —— 都是有意为之。
- **面板里不对称的 `AnimatedSwitcher` 时长**、**懒加载的 `_currentPage()`**、
  **260ms 的 `_commit` 去抖** —— 各自都有对应的用户反馈记录。
- **`BuiltinCardBody` 的 key 不含全局 `_revision`** —— 故意让外观类设置
  不炸掉 5 个 QuickJS 运行时。
- **PerfProbe 临时诊断**（`【临时诊断】`/`【临时定位C】`）—— 是调试留下的，
  要不要撤由人决定，不在性能范围内。
- **`sentry.initSentry()` 在 `runWidget` 之前 await** —— 注释说明是为了
  抓到引擎初始化期间的异常。改成不等会丢早期错误，是取舍不是缺陷。

子代理还列了几条**自己查了但决定不做**的，也记在这里免得下次重复调查：
- 类型探测的输入没法截断到 4KB —— `_getJsonType` 要读到巨大的 `yrc.lyric`，
  截断会把真数据判成 `unknown`
- `detect()` 上 `compute()` 不划算 —— 剩下的开销是 `jsonDecode` 本身
  （33~55 kB 各约 1.2ms），加上 spawn + 拷贝后净收益 < 一帧的 6%

---

## 6. 还没做、但值得排期的

- `Lunar.nextTerm` 每次日历 draw 仍是 O(40 × termOf)
- `WidgetCard.settings` 每次参与 key 计算都 `jsonEncode` 一遍。现在因为
  surface 不再每帧重建，代价已经很轻；要彻底消掉需要让 map 自己记版本号。
- 启动路径上 `sentry.initSentry()` 是 `runWidget` 的硬前置，见 §5。

## 7. 顺带修掉的

- `panel.dart` 里 `resizeHandles(NativeWindow.panel)` 重复了两遍 —— 复制粘贴
  留下的，每次重建多 8 个 `Positioned`+`MouseRegion`，还让窗口边缘的命中
  测试条目翻倍
- `NativeBridge` 把回调存在 `static` 字段里，`AppRootState.dispose()` 没清，
  静态闭包会一直吊着已经销毁的 State（热重载时尤其明显）
- `FlipSwap` 的 `duration` 改了不生效（`late final AnimationController`）
