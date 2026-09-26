/// 设置窗口里的那棵 widget 树。
///
/// 它跑在**第二个视图**上，但和桌面磁贴共用同一个引擎、同一个 isolate，
/// 所以这里拿到的 state / store / registry 就是磁贴那边同一批对象——
/// 控制面板改设置仍然是就地改，不需要任何跨进程同步。
///
/// 添加/删除卡片、改完设置后的重建，都要落到 AppRoot 上执行：找空位要读
/// **桌面那个视图**的尺寸。所以这里直接持有
/// AppRoot 的 State（同一个 isolate，是真正的对象引用，不是消息）。
///
/// 界面用 fluent_ui 的 Windows 11 风格（小组件磁贴那边不用它，保持原样）。
library;

import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';

import '../core/logger.dart';
import '../core/theme.dart';
import '../native/native_bridge.dart';
import '../store/store.dart';
import 'app_root.dart';
import 'panel.dart';
import 'wallpaper.dart';

/// 设置窗口该显示哪一页 / 定位到哪张卡片。
/// 托盘、右键卡片都往这里写，设置窗口监听。
final ValueNotifier<int?> panelTabRequest = ValueNotifier(null);
final ValueNotifier<String?> panelCardRequest = ValueNotifier(null);

/// 面板主题重建信号。
///
/// 控制面板里改了"主题"（auto/light/dark）时 bump 一下，让这棵 FluentApp
/// 树重建——否则 FluentApp 的 FluentThemeData 只在 PanelApp 第一次 build
/// 时算一次，scaffoldBackgroundColor / accentColor / 各种 fluent 控件的
/// 主题色就卡在旧亮度里不动。
///
/// 系统深浅色的翻转由 AnimatedBuilder 直接监听 systemBrightness，
/// 这个 notifier 只负责"用户手动改了 settings.theme"的那一条路径。
final ValueNotifier<int> panelThemeRevision = ValueNotifier(0);

class PanelApp extends StatefulWidget {
  const PanelApp({
    super.key,
    required this.state,
    required this.store,
    required this.appKey,
  });

  final AppState state;
  final Store store;
  final GlobalKey<AppRootState> appKey;

  @override
  State<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends State<PanelApp> {
  /// 已经推给 native 的窗口深色状态，用来去重。
  ///
  /// 同步动作放在 build 里：面板窗口的 DWM 边框只认这个属性，而它的来源
  /// （settings.theme 与系统深浅色）都在 Dart 侧，任何一个变了这棵树都会重建。
  /// 函数内部去重，实际只在亮度真的变化时才发通道调用。
  bool? _pushedDark;

  void _syncWindowTheme(bool light) {
    final dark = !light;
    if (_pushedDark == dark) return;
    _pushedDark = dark;
    Log.i('panel', '窗口深浅色 → ${dark ? '深色' : '浅色'}');
    NativeWindow.panel.setDarkMode(dark).catchError((Object e) {
      Log.i('panel', '窗口深浅色推送失败: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    // 双重监听重建 FluentApp：
    //   1. systemBrightness 翻转（系统深浅色切换 / 显式 light+dark 不影响）
    //   2. panelThemeRevision 被 bump（用户手动改了 settings.theme）
    // AnimatedBuilder 内部 setState，外层 PanelApp 不会重建。
    return AnimatedBuilder(
      animation: Listenable.merge([systemBrightness, panelThemeRevision]),
      builder: (context, _) {
        final light =
            effectiveBrightness(widget.state.settings) == Brightness.light;
        // 窗口级深浅色跟着生效亮度走（DWM 边框/阴影/窗口菜单）
        _syncWindowTheme(light);
        // 窗口底色改由亚克力层自己画（见 [_AcrylicBackdrop]），
        // Scaffold 不能再铺一层不透明底，否则整块把壁纸盖住。
        const bg = Colors.transparent;
        return FluentApp(
          debugShowCheckedModeBanner: false,
          title: 'Glance 设置',
          color: bg,
          // FluentApp 默认就会带上 FluentLocalizations + Material/Cupertino/Widgets
          // 三套 Global delegates 和它的 supportedLocales（含 zh_CN），不用自己再传
          locale: const Locale('zh', 'CN'),
          theme: FluentThemeData(
            brightness: light ? Brightness.light : Brightness.dark,
            fontFamily: 'TsukushiBMaru',
            // 主色沿用磁贴那套天蓝：浅色下加深一档，保证对比度
            accentColor: AccentColor.swatch({
              'normal':
                  light ? const Color(0xFF1565C0) : const Color(0xFF7CC7FF),
            }),
            scaffoldBackgroundColor: bg,
          ),
          home: Stack(
            fit: StackFit.expand,
            children: [
              _AcrylicBackdrop(light: light),
              ScaffoldPage(
                padding: EdgeInsets.zero,
                content: ValueListenableBuilder<int?>(
                  valueListenable: panelTabRequest,
                  builder: (context, tab, _) =>
                      ValueListenableBuilder<String?>(
                    valueListenable: panelCardRequest,
                    builder: (context, cardId, _) => ControlPanel(
                      // 换页/换定位卡片时重建，其余时候不动
                      key: ValueKey('panel:$tab:$cardId'),
                      state: widget.state,
                      store: widget.store,
                      focusCardId: cardId,
                      initialTab: tab,
                      // 独立窗口里不要遮罩、不要固定尺寸、不要自绘关闭按钮
                      embedded: false,
                      onClose: () => widget.appKey.currentState?.hidePanelWindow(),
                      onChanged: () => widget.appKey.currentState?.onPanelChanged(),
                      onAdd: (plugin) => widget.appKey.currentState?.addCard(plugin),
                      // 每块屏都放过这种组件了就不让再加。判断要用磁贴那边的
                      // 显示器信息，所以问 appKey 而不是在面板里自己算。
                      canAdd: (pluginId) =>
                          widget.appKey.currentState?.canAddPlugin(pluginId) ??
                          true,
                      onRemove: (card) =>
                          widget.appKey.currentState?.removeCard(card),
                      // 应用更新：保存退出 + 拉起静默安装器都在磁贴那边编排
                      onInstallUpdate: (path) async =>
                          widget.appKey.currentState?.installUpdate(path) ??
                          false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 设置窗口的亚克力底：**预模糊壁纸 + 一层主题色调蒙版**。
///
/// 路子抄的是 Windows 11「设置」那种 Mica——底色跟着桌面壁纸走，而不是一块
/// 死灰；窗口拖到哪儿都一样（Mica 本来就不跟随窗口背后的内容，跟随的那是
/// Acrylic）。
///
/// 为什么不吃系统那套：WCA 亚克力在这个项目上试过，Win10 下渲染成整窗透明、
/// 还拖慢合成（见 view_window.cpp 里的注释）。这里用的是磁贴卡片早就在用的那张
/// **预模糊壁纸**（[Wallpaper.image]，sigma 18、长边上限 768），纯 Dart 合成、
/// 零额外采样，拖动窗口时不会掉帧。
class _AcrylicBackdrop extends StatelessWidget {
  const _AcrylicBackdrop({required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<ui.Image?>(
          valueListenable: Wallpaper.image,
          builder: (context, img, _) {
            // 壁纸还没抓到就只留蒙版，本身也是一块干净的纯色底
            if (img == null) return const SizedBox.shrink();
            final s = 1 / Wallpaper.scale;
            return RawImage(
              image: img,
              width: img.width * s,
              height: img.height * s,
              // cover 而不是 fill：窗口是长方形、壁纸是整屏，铺满就行
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            );
          },
        ),
        // 色调蒙版。留一点壁纸颜色透出来，这就是"亚克力"和纯色的全部区别。
        // 透明度是拿真机截图校的：85% 时深色壁纸只透 15%，明暗起伏完全被
        // 压平，整块退化成注释里最忌讳的"死灰"——Win11 设置的 Mica 在深
        // 壁纸下是明显看得出深浅的。七成上下：壁纸的月亮/海面层次透得出，
        // 正文对比度也还充足。
        ColoredBox(
          color: light ? const Color(0xB0F3F3F6) : const Color(0xB3171B1B),
        ),
      ],
    );
  }
}
