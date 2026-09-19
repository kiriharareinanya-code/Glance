/// 生成组件库用的**真实渲染截图**（`assets/previews/<id>.png` / `<id>-light.png`）。
///
/// 之前那套是 PIL 手绘的示意图——画得再像也不是组件本尊。这里把**真实的
/// 组件控制器**在测试环境里挂起来（和实时预览同一套隔离宿主：假卡片 +
/// 独立 Store），真实渲染之后用 RepaintBoundary.toImage 导出 PNG，所见即
/// 组件在桌面上的样子：字体、间距、圆角、配色全部是真的。
///
/// 这是**生成工具**不是常规测试：会发真实网络请求（天气的定位与气象 API）、
/// 写真实文件（assets/previews/）。改了组件外观就跑一遍：
///
///     flutter test test/gen_previews_test.dart
///
/// 然后把产物提交进仓库。运行时（panel_preview.dart）只读图，零请求零定时器。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vectra/core/grid.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/store/store.dart';
import 'package:vectra/widgets/builtin/lrc.dart';
import 'package:vectra/widgets/builtin/lyrics.dart';
import 'package:vectra/widgets/catalog.dart';
import 'package:vectra/widgets/context.dart';
import 'package:vectra/widgets/spec.dart';

const _outDir = 'assets/previews';

/// 统一画布：所有组件都按同一块 4x4（484×484）渲染。
///
/// 以前按各组件 defaultSize 出图（时钟 236²、天气 360×236、日历 484²、
/// 歌词 604×360……），组件库页面上每张图的内容缩放基准都不同——同样是
/// 14px 的字，在小画布里显得大、在大画布里显得小，摆在一起就是"大小
/// 不一、字体不齐"。统一到一块画布后：组件内部按同一尺寸自适应布局，
/// 字体/间距的相对比例完全一致；展示端也因此可以统一宽高比。
/// 各组件都是自适应布局（见各自 draw() 对 ctx.size 的处理），4x4 下
/// 时钟走堆叠、天气走完整实况、歌词走大字号档，均安全。
const _previewGrid = GridSize(4, 4);

/// 磁贴内容区四周的留白——**必须和 card_view.dart 的
/// CardView.contentPadding 保持一致**。
///
/// 桌面上插件拿到的 ctx.size 是"卡片外框刨掉这一圈"之后的可用区，内容
/// 天然离卡片边缘有一圈呼吸留白。生成器以前直接把整块外框尺寸塞给
/// ctx.size，组件内容全画到画布边上（天气的城市名/状态图标贴着像素边，
/// 观感像被裁切），和桌面观感对不上。这里同样分两步：ctx.size 按刨完
/// 的可用区给，渲染时内容外面再包一层同款 padding。
const _contentPadding = EdgeInsets.fromLTRB(18, 16, 18, 16);

/// 歌词预览的演示文案（原创，每行 7 秒）。只在生成预览图时使用，
/// 不进组件代码。12 行覆盖 84 秒，截图取 42 秒处——正好在中间，
/// 滚动歌词区上下都有行，当前行高亮的效果最完整。
const _demoLyrics = [
  '窗外的光落在桌面上',
  '磁贴安安静静地亮着',
  '时钟走它自己的节拍',
  '天气刚更新过一场雨',
  '待办清单还剩三件事',
  '日历翻到九月的末尾',
  '而这首歌刚唱到副歌',
  '封面在角落里转啊转',
  '歌词一行一行地擦过',
  '像玻璃上流动的霓虹',
  '暂停键留着一份安静',
  '下一首已经在路上',
];

/// flutter test 的默认字体是 Ahem——每个字画一个方块，截图里全是豆腐。
/// 把真字体喂进去：正文走主题默认 family（Roboto，喂微软雅黑，观感接近
/// 桌面上的实际渲染），时钟走 assets 里的筑紫丸。
Future<void> _loadRealFonts() async {
  Future<void> load(
      String family, Future<ByteData> Function() data) async {
    final loader = FontLoader(family)..addFont(data());
    await loader.load();
  }

  await load('Roboto', () async {
    final bytes = await File(r'C:\Windows\Fonts\msyh.ttc').readAsBytes();
    return ByteData.view(bytes.buffer);
  });
  await load(
      'TsukushiBMaru', () => rootBundle.load('assets/fonts/tsukushi_b_maru.ttf'));

  // MaterialIcons：天气卡的状态图标那些 Icons.xxx，不喂就全是方块。
  // 测试的 asset bundle 里带的是 fonts/MaterialIcons-Regular.otf（pubspec
  // 的 uses-material-design），拿不到就退回 SDK 缓存里的原件。
  try {
    final data = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(data));
    await loader.load();
  } catch (_) {
    final sdk = File(
        r'C:\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf');
    if (sdk.existsSync()) {
      final bytes = await sdk.readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
}

void main() {
  testWidgets('生成全部内置组件的概览截图（深色 + 浅色两套）', (tester) async {
    // flutter test 会通过 HttpOverrides 把所有 HttpClient 拦成 400；这个
    // 工具要的就是真网络（天气的定位与气象 API），把它摘掉。
    HttpOverrides.global = null;
    // 溢出告警之类的渲染问题不该让生成工具整轮失败——那黄条也确实会画进
    // debug 渲染的截图里，这里只记日志，产物问题靠肉眼验收。
    FlutterError.onError =
        (d) => debugPrint('render warning: ${d.exceptionAsString()}');
    // 字体加载的完成回调要真实异步才派发，直接 await 会在 fake-async 的
    // 测试 zone 里永远 pending（第一版就卡死在这）。runAsync 切回真实 zone。
    await tester.runAsync(_loadRealFonts);

    const themes = [
      (suffix: '', color: Color(0xFF2A2A2E)),
      (suffix: '-light', color: Color(0xFFF2F2F5)),
    ];

    for (final spec in kBuiltinSpecs) {
      for (final theme in themes) {
        final id = spec.id;
        // 统一画布（见 _previewGrid 注释）：不再用 spec.defaultSize
        final grid = _previewGrid;
        final px = sizeToPx(grid);
        // ctx.size = 内容区可用尺寸（外框刨掉 contentPadding），与桌面一致
        final innerW = px.w - _contentPadding.horizontal;
        final innerH = px.h - _contentPadding.vertical;

        // 和实时预览同一套隔离宿主：假卡片 + 独立 Store，不碰真实 pluginData。
        // 天气的 cache 也落在这里，浅色那一轮直接命中，不用再拉一遍网络。
        final store = Store(
            p.join(Directory.systemTemp.path, 'glance-shot', '$id${theme.suffix}'));
        await tester.runAsync(store.load);

        final card = WidgetCard(
            id: 'shot',
            pluginId: id,
            x: 0,
            y: 0,
            size: grid.toString(),
            z: 0);
        final settings = spec.defaultSettings();
        // 天气的定位链路（IP 定位 -> 城市码）在测试环境里落点会漂，落到的
        // 地名还可能查无此码，整卡就变成"天气不可用"。钉成成品在用的城市，
        // 走和桌面上一模一样的成功路径；下面再把成品跑出来的真实缓存拷进来
        // 当双保险——mount 时缓存先命中直接画出完整数据，后台 _load 再刷新。
        settings['city'] = '天元';
        final ctx = WidgetContext(
          store: store,
          card: card,
          pluginId: id,
          onRequestSize: (_) {},
          onOpenSettings: () {},
          settings: settings,
          grid: grid,
          size: Size(innerW, innerH),
        );

        // 成品那份 weather.json 的结构是 {"@inst:<卡片id>:cache": {...}}，
        // 取值塞进隔离宿主的同名键，缓存命中路径就原样接上了。
        if (id == 'weather') {
          final src = File(
              'build/windows/x64/runner/Release/userdata/plugindata/weather.json');
          if (src.existsSync()) {
            final raw = await tester.runAsync(src.readAsString);
            final map = (jsonDecode(raw!) as Map).values.first;
            ctx.storageSetLocal('cache', map);
          }
        }

        // 待办塞几条演示数据，别让截图是一块空态
        ctx.storageSetLocal('items', [
          {'id': '1', 'text': '整理本周反馈', 'done': false},
          {'id': '2', 'text': '发版 0.2.0', 'done': true},
        ]);

        final controller = createBuiltinController(id, ctx);
        // mount 和等待都必须放进真实异步 zone：HttpClient 是在 mount 里创建
        // 的，留在 fake-async zone 会被测试框架整个拦成 400，天气就永远截到
        // "网络错误"的样子。runAsync 里的请求是真实的。
        await tester.runAsync(() async {
          controller.mount();
          // 歌词在测试环境里没有 SMTC 数据源（ctx.mediaState 拿不到系统播放
          // 状态），ctx.widget 永远停在"没有正在播放的音乐"的空态——预览图
          // 就只剩一句提示，展示不出组件真正的布局。用测试钩子顶上：
          // debugSetLyrics 塞一段演示歌词，渲染时 debugBuildFull 直接构建
          // 完整播放视图（假媒体快照 + 封面占位 + 控制条 + 滚动歌词）。
          // 必须放在 mount() 之后——mount 会 _lyrics = [] 清空歌词。
          if (id == 'lyrics') {
            (controller as LyricsWidget).debugSetLyrics([
              for (var i = 0; i < 12; i++)
                LrcLine(t: i * 7000, s: _demoLyrics[i]),
            ]);
          }
          await Future<void>.delayed(const Duration(milliseconds: 4500));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // 组件的文字色跟着宿主的 DefaultTextStyle 走（见各组件的 draw()），
        // 所以深浅两版只需要换底色和前景色。
        final fg = theme.color.computeLuminance() > 0.5
            ? const Color(0xFF16181C)
            : Colors.white;
        final key = GlobalKey();

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: px.w.toDouble(),
                height: px.h.toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: theme.color),
                  // 内容区垫一圈与桌面一致的 contentPadding（见
                  // _contentPadding 注释），组件内容不再贴着画布边
                  child: Padding(
                    padding: _contentPadding,
                    // 待办的输入框是 Material 组件，需要 Material 祖先；
                    // transparency 不额外画底，底色仍由外面的 DecoratedBox 给。
                    child: Material(
                      type: MaterialType.transparency,
                      child: DefaultTextStyle(
                        style: TextStyle(
                            fontSize: 14, color: fg, fontFamily: 'Roboto'),
                        child: ValueListenableBuilder<Widget?>(
                          valueListenable: ctx.widget,
                          builder: (context, w, _) {
                            // 歌词不走 ctx.widget（见上面的 debugSetLyrics
                            // 注释）：42 秒处的完整播放视图，滚动歌词上下
                            // 都有行，当前行高亮最完整。
                            if (id == 'lyrics') {
                              return (controller as LyricsWidget)
                                  .debugBuildFull(42,
                                      title: '桌面漫游指南',
                                      artist: 'Glance 电台');
                            }
                            return w ?? const SizedBox.expand();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));

        // 给真实时间（runAsync 切回非 fake 的异步 zone）：时钟也要走到下一个
        // 重绘点。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = (await tester
            .runAsync(() => boundary.toImage(pixelRatio: 2.0)))!;
        final data = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.png));
        Directory(_outDir).createSync(recursive: true);
        final path = p.join(_outDir, '$id${theme.suffix}.png');
        File(path).writeAsBytesSync(data!.buffer.asUint8List());
        debugPrint('generated $path (${image.width}x${image.height})');

        controller.unmount();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
