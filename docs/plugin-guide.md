# 插件开发规范

本文件是 Vectra / Glance 插件的**开发约定**。目标只有一个：**加插件、改插件都不用动壳**——
面板、桌面层、卡片容器永远不认识具体插件。

规范分两半：**代码里能自动执行的**（守卫测试，见 `test/architecture_test.dart`）和
**需要人遵守的**（本文档）。前者违反会立刻红，后者是判断依据。

---

## 1. 边界

```
   lib/ui/**（面板、桌面层）
        │  只能 import: plugin_api.dart + registry.dart
        ▼
   lib/widgets/registry.dart          ← 全项目唯一 import 插件实现的地方
        │
        ▼
   lib/widgets/builtin/<插件>.dart     实现 + manifest + 工厂
        │
        ▼
   plugin_api.dart   契约（PluginManifest / PluginController / WidgetContext）
   kit.dart          共享渲染件（滑条、按压反馈、图标、颜色…）
```

三条铁律（前两条由守卫测试强制）：

| # | 规则 | 为什么 |
|---|---|---|
| 1 | **壳不 import 插件实现** | 壳一旦认识具体插件，加/换插件就要改壳，边界白画 |
| 2 | **只有 `registry.dart` 能 import 插件实现** | 单一组装点；新增插件只需改这一个文件 |
| 3 | **插件之间不互相 import** | 需要共用的东西进 `kit.dart`，别让插件长成网状依赖 |

---

## 2. 新增一个插件

**第 1 步**：新建 `lib/widgets/builtin/<id>.dart`，导出三样东西：

```dart
import 'package:flutter/material.dart';

import '../kit.dart' show TapFeedback, nodeColor, withGaps;  // 按需
import '../plugin_api.dart';

// ① 清单：面板/桌面层要的全部静态信息
const kHelloManifest = PluginManifest(
  id: 'hello',                       // snake_case，会成为存储命名空间
  name: '示例',
  version: '1.0.0',                  // 插件自己的版本号，与程序版本解耦
  description: '一句话说明（组件库卡片上显示）',
  icon: '🙂',
  sizes: ['2x2', '3x2'],             // grid 单位，"宽x高"
  defaultSize: '2x2',                // 必须 ∈ sizes
  settings: [
    {'key': 'greet', 'type': 'text', 'label': '问候语', 'default': '你好'},
  ],
);

// ② 工厂：注册表按 id 找它
PluginController helloPlugin(WidgetContext ctx) => HelloWidget(ctx);

// ③ 控制器：实现挂载/卸载/渲染
class HelloWidget extends PluginController {
  HelloWidget(super.ctx);

  @override
  void mount() {
    ctx.renderWidget(_view());        // 起手先画一帧
    ctx.interval(() => ctx.renderWidget(_view()), 1000);  // 定时器走 ctx
  }

  Widget _view() => Builder(builder: (context) {
        // 前景色取自卡片环境（深浅色自适应），见第 5 节
        final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
        return Center(
          child: Text('${ctx.settings['greet']}',
              style: TextStyle(fontSize: 15, color: fg)),
        );
      });
}
```

**第 2 步**：在 `lib/widgets/registry.dart` **登记两处**（就这两处，别处不用动）：

```dart
import 'builtin/hello.dart' show helloPlugin, kHelloManifest;

const List<PluginManifest> kPlugins = [/* ... */ kHelloManifest];
final Map<String, PluginFactory> _factories = {/* ... */ 'hello': helloPlugin};
```

漏登记任何一处 → `architecture_test.dart` 会红（"清单里有、工厂里没有"）。

**第 3 步**：验收（第 7 节）。

---

## 3. 清单字段规范

| 字段 | 约束 | 守卫测试 |
|---|---|---|
| `id` | `^[a-z][a-z0-9_]*$`，全局唯一 | ✅ 格式/唯一性 |
| `defaultSize` | 必须出现在 `sizes` 里 | ✅ |
| `sizes` | 非空，`"宽x高"`（grid 单位，见 `core/grid.dart`） | ✅ 格式 |
| `version` | 插件自己的语义化版本，改插件时手动 +1 | — |
| `name` / `description` / `icon` | 非空（组件库卡片直接展示） | ✅ |
| `settings` | 见下 | ✅ schema 校验 |

### settings 的 schema

面板按 `type` 渲染控件（`lib/ui/panel.dart` 的 `_settingField`）：

| type | 面板控件 | 必填字段 |
|---|---|---|
| `boolean` | 开关 | `key` `type` `label` `default` |
| `select` | 下拉框 | 上面 + `options: [{value, label}]`，且 `default` ∈ options |
| `number` | 滑条 | 上面 + `min` `max` `step`（缺了会退回 0~100/步长 1） |
| `text` | 文本框 | 上面（可选 `placeholder`） |

其余字段可选：`desc` 显示在标题下方作为说明。

> **写错 type 不会报错**，会静默退化成文本框——守卫测试专门拦这一条。

新增设置项**不需要改面板**：面板完全由 schema 驱动。

---

## 4. 控制器契约

| 方法 | 何时被调用 | 该做什么 |
|---|---|---|
| `mount()` | 卡片出现 / 重建时一次 | 起定时器、发首个请求、渲染第一帧 |
| `unmount()` | 卡片销毁时一次 | **默认别覆写**，基类交给 `ctx` 统一回收 |
| `onSettingsChange()` | ⚠️ **当前未接入**，见下方说明 | 不要依赖它 |

### ⚠️ 设置变更 = 卡片重建

改设置时，卡片 key（`app_root.dart`）里含 `jsonEncode(card.settings)`，所以
**整张卡片连同控制器会被销毁重建，`mount()` 重新跑一遍**。这是当前唯一生效的机制。

推论（写插件时必须知道）：

- **`mount()` 里读到的 `ctx.settings` 就是最新值**，据此渲染初始状态即可，不要缓存设置；
- **`onSettingsChange()` 目前不会被调用**（契约里预留的钩子）。实现了它但发现"不生效"是正常的，
  不要靠它做正确性——需要它就说明要接入它，那是宿主侧的改动；
- 重建的代价是重新初始化（定时器重建、网络请求重发但命中缓存、输入框失焦）。
  当前 5 个插件的量级下可接受。

### 必须走 ctx 的资源（否则会泄漏）

| 资源 | 正确写法 | 错误写法 |
|---|---|---|
| 定时器 | `ctx.interval(fn, ms)` / `ctx.timeout(fn, ms)` | `Timer.periodic(...)`（卸载时收不回来） |
| 自持对象（如 `TextEditingController`） | `ctx.onCleanup(() => ctrl.dispose())` | 不释放（卡片重建即泄漏） |
| 网络 | `ctx.httpGetJSON/Text`（15s 超时、头白名单、日志留痕） | 自建 `http.Client` |

> **覆写基类方法时要小心**：历史上有组件写了空 `unmount() {}`，把基类的定时器
> 回收整个吞掉，留下一堆孤儿 Timer。只想"额外做点事"时**必须调 `super`**。

---

## 5. 渲染约定

### 取前景色：用 Builder 解析一次，往下传

插件拿不到 Flutter 的 `BuildContext`（控制器不是 Widget），所以渲染入口统一这么写：

```dart
ctx.renderWidget(Builder(builder: (context) {
  final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
  return _view(fg);   // _view 的每个色值都从 fg 派生
}));
```

`fg` 是卡片按壁纸明暗算出来的前景色。**所有文字/图标颜色从它派生**，否则浅色卡片上
白色文字会看不见。透明度用 `fg.withValues(alpha: 0.55)`。

### 字体是红线

- **不要写 `fontFamily`**——卡片环境的全局字体（`TsukushiBMaru`）会自动继承；
- 只有明确需要指定字体时（如时钟的数字）才显式写出来，且**不要改动既有字体设置**。

### 复用 kit，别重造

| 需求 | 用 | 不要 |
|---|---|---|
| 进度条 / 可拖条 | `PluginSlider`（含与卡片拖拽的指针协作） | 自己写 `Slider`（会把整张卡片拖走） |
| 可点元素 | `TapFeedback`（按压缩放反馈） | 裸 `GestureDetector`（点了没反馈） |
| 图标 | `NodeIcon`（形变 + 颜色过渡） | 裸 `Icon`（状态切换时啪一下） |
| 颜色字符串解析 | `nodeColor('#RRGGBB' / '#RRGGBBAA')` | 自己 `int.parse`（alpha 位置容易搞错） |
| 文字辉光 | `nodeGlow(color, sigma)` | 自配 `Shadow`（容易铺成一片亮） |
| 字重 | `nodeWeight(700)` | — |
| 间隔 | `withGaps(children, gap)` | 手写一堆 `SizedBox` |
| 3D 翻面 | `FlipSwap` | — |
| 数字机械翻页 | `FlipTransition` | — |

### 颜色语义

`nodeColor` 的 8 位写法是 **`#RRGGBBAA`（alpha 在后）**，与 Flutter 的 `AARRGGBB` 相反。
例：`#FFFFFF33` = 20% 白的白；`#D9000000` 是**全透明**（不是"85% 黑"）——这是历史语义，
改动会影响既有观感，不要"顺手修正"。

### 动画：显式声明才动

`ctx.animate` 跟随用户的"动画效果"开关。**所有过渡都要用它门控**（`animate: ctx.animate`），
关掉时直接到位。

> 内容切换动画在本项目有过事故：真实渲染下交叉过渡会闪白，所以当年整体移除了它。
> 现在只有显式声明的过渡才允许存在。**不要给组件加"无声明的内容切换动画"**。

### 尺寸自适应

`ctx.grid`（卡片的格数，cols/rows）和 `ctx.size`（内容区像素尺寸）都可用，
**按尺寸分档**而不是写死——同一组件在 2x2 和 5x3 上都要能看：

```dart
final compact = ctx.grid.rows <= 2;
final big = ctx.grid.cols >= 3 ? 58.0 : 44.0;
```

历史教训：歌词卡曾按"最坏情况"预留高度，在矮卡片上吃掉 37% 的空间，直接不可用。
**别为不存在的内容预留空间。**

### 滚动/裁切

需要"固定取景框 + 内容超出裁掉"时：

```dart
SizedBox(
  height: viewport, width: double.infinity,
  child: ClipRect(
    child: OverflowBox(
      minHeight: 0, maxHeight: double.infinity,   // 放开高度，别收紧
      alignment: Alignment.topCenter,
      child: content,
    ),
  ),
)
```

`OverflowBox` 是必需的：`SizedBox` 的高度约束会传给孩子，内容比取景框高就报
`RenderFlex overflow`。宽度则由 `SizedBox(width: infinity)` 收紧（否则 `Column` 会
缩到最宽那行文字的宽度，看起来一片空白——这个坑踩过两次）。

---

## 6. 数据与状态

| 用途 | 用 | 说明 |
|---|---|---|
| 全局数据（所有卡片共享，如天气缓存） | `ctx.storageGet/Set` | 按插件命名空间隔离 |
| **实例私有**（每张卡片各存各的，如待办清单） | `ctx.storageGetLocal/SetLocal` | 自动加 `@inst:<cardId>:` 前缀 |
| 带淘汰的缓存（歌词这类大块数据） | `ctx.cacheGet/Set` | 一条一个文件，有 LRU 上限 |
| 媒体状态 / 控制 | `ctx.mediaState()` / `ctx.mediaControl(cmd, posMs:)` | SMTC |
| 启动外部程序 / 打开链接 | `ctx.launch(path)` / `ctx.openExternal(url)` | 有白名单校验 |

---

## 7. 验收清单（提交前逐条过）

1. `flutter analyze` —— 零问题；
2. `flutter test` —— 全绿（含 `architecture_test.dart`：边界 + 清单守卫）；
3. `flutter build windows --release` —— 成功（构建前先 `Stop-Process glance`，
   否则 `LNK1104: 无法打开 glance.exe`）；
4. 实跑一次，检查启动日志：没有 `E [`、没有 `RenderFlex overflowed`；
5. 面板里走一遍：组件库能添加、预览正常、设置项能改且**改完立刻生效**、卡片能删除。

---

## 8. 已知缺口 / 待决

| 项 | 状态 |
|---|---|
| `onSettingsChange()` 未接入 | 设置变更走整卡重建。若将来"重建代价"变得不可接受（比如组件变重），再把它接上：卡片 key 去掉 settings + `didUpdateWidget` 里推新 settings 并调用钩子。**接入时 5 个插件都要补实现**。 |
| 插件拆成独立 pub package | 暂时不做：插件与程序一起发版，拆包只增加 pubspec 摩擦。真要拆时，`builtin/<id>.dart` 目录化成 package 是机械操作。 |
| 热更新插件 | **明确不做**：Flutter/Dart 是 AOT，运行时加载不了 Dart 代码；而插件只由第一方编写、跟版本发布，不需要脚本运行时或沙箱。 |
