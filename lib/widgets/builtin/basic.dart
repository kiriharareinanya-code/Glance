/// 内置组件：时钟与待办。
///
/// 从 assets/plugins/{clock,todo}/index.js 逐行移植，后经"原生渲染通道"
/// 迁移：直接产出 Flutter Widget（ctx.renderWidget），不再经 JSON 树 /
/// NodeView 解释。结构与刷新节奏与原版本一致。
///
/// 字体红线：时钟用 TsukushiBMaru——原生 Text 不写 fontFamily 时会继承
/// 卡片环境的全局字体（card_view 设的就是 TsukushiBMaru），这里仍显式
/// 写出，让依赖一目了然。
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../catalog.dart';
import '../flip_transition.dart' show FlipTransition;
import '../kit.dart'
    show NodeIcon, TapFeedback, nodeColor, nodeWeight, withGaps;

// ---------------------------------------------------------------------------
// 时钟：每秒重绘一次。
//
// 数字的切换动效走"机械翻页"（FlipTransition，原 trans: 'flip'）：
// 上半页翻下去、下半页翻上来，时分秒三位各自独立翻，节奏一致。日期和星期
// 不是数字，保持交叉淡入（原 trans: true）。
//
// 两套排版：
//   - 3x3（够高够方）：仿安卓锁屏那种"时/分各占一行"的堆叠大字；
//   - 2x2 / 3x2 / 4x2（都是 2 行高）：横排 "HH:MM"，小时粗体、冒号压淡、
//     分钟用细体，靠字重梯度做出层次。
// ---------------------------------------------------------------------------

class ClockWidget extends BuiltinController {
  ClockWidget(super.ctx);

  String? _timer;

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  static const _font = 'TsukushiBMaru';

  @override
  void mount() {
    draw();
    _timer = ctx.interval(draw, 1000);
    ctx.onCleanup(() => ctx.clearTimer(_timer!));
  }

  /// 机械翻页数字（原 trans: 'flip'）
  Widget _flipDigit(String v, double size, int weight, Color color,
      {double? lh}) {
    final style = TextStyle(
      fontSize: size,
      fontWeight: nodeWeight(weight),
      fontFamily: _font,
      color: color,
      height: lh,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return FlipTransition(
      value: v,
      animate: ctx.animate,
      textBuilder: (val) => Text(val, style: style),
    );
  }

  /// 交叉淡入 + 轻微上移（原 trans: true，220ms）
  Widget _fadeText(String v, double size, double opacity, Color fg) {
    final style = TextStyle(
        fontSize: size, fontFamily: _font, color: fg.withValues(alpha: opacity));
    if (!ctx.animate) return Text(v, style: style);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position:
              Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(anim),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(v), child: Text(v, style: style)),
    );
  }

  void draw() {
    final now = DateTime.now();
    var h = now.hour;
    var suffix = '';
    if (ctx.settings['hour24'] != true) {
      suffix = h < 12 ? 'AM' : 'PM';
      h = h % 12;
      if (h == 0) h = 12;
    }

    const weeks = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final week = weeks[now.weekday % 7];

    // 跟"莫奈取色"联动：ctx.themeAccent 是从当前壁纸实时算出来的强调色
    //（开关都没开时是 null，退回写死的主题蓝）。draw() 每秒重跑一次，
    //壁纸变了下一秒自然跟着变。
    final accentHex = ctx.themeAccent ?? '#7CC7FF';
    final accent = nodeColor(accentHex);

    Widget body(Color fg) {
      // 日期行装进一个用主题色打底的圆角胶囊（Material 3 Expressive 的
      // tonal chip 手法），不再是两段裸文字。
      final dateRow = Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        decoration: BoxDecoration(
          color: nodeColor('$accentHex 1F'.replaceAll(' ', '')),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: withGaps([
            Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: accent, borderRadius: BorderRadius.circular(3))),
            _fadeText('${now.month} 月 ${now.day} 日', 13, 0.7, fg),
            _fadeText(week, 13, 0.7, fg),
          ], 7, horizontal: true),
        ),
      );

      // 竖排（时在上、分在下）的两种触发条件：
      //   1. 卡片本身够高（3 行），横排的时分数字会显得空空荡荡；
      //   2. **宽度不够**——卡片被压窄时横排的「HH:MM:SS 时段」一行放不下，
      //      改成上下堆叠才不会溢出。这正是"窄的时候该像手机端那样竖着堆"。
      final stacked = ctx.grid.rows >= 3 || ctx.size.width < 190;

      if (stacked) {
        // 140：两行堆叠总高实测 238px，3x3 卡片能给的内容高度约 296px，
        // 扣掉日期行和间距还有 30px+ 的余量。
        // 窄卡片下再收一档，免得两行数字把宽度顶穿。
        final stackSize = ctx.size.width < 190 ? 104.0 : 140.0;
        final minuteRow = <Widget>[
          _flipDigit(_two(now.minute), stackSize, 300, accent, lh: 0.85),
        ];
        if (ctx.settings['seconds'] == true) {
          minuteRow.add(Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _flipDigit(_two(now.second), 20, 400, fg.withValues(alpha: 0.4)),
          ));
        }
        if (suffix.isNotEmpty) {
          minuteRow.add(Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(suffix,
                style: TextStyle(
                    fontFamily: _font,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.4))),
          ));
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: withGaps([
            _flipDigit(_two(h), stackSize, 300, accent, lh: 0.85),
            Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: minuteRow),
            dateRow,
          ], 10),
        );
      }

      // 横排走不到窄卡片（上面 stacked 已经把 width<190 接走了），
      // 所以这里按格数选字号就够了。
      final big = ctx.grid.cols >= 3 ? 58.0 : 44.0;
      // 时:分拆成三个独立节点：小时粗体+默认色，冒号 0.35 透明度弱化成分隔符，
      // 分钟用细体 + ACCENT 上色收尾。
      final timeRow = <Widget>[
        _flipDigit(_two(h), big, 900, accent, lh: 1.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(':',
              style: TextStyle(
                  fontFamily: _font,
                  fontSize: big,
                  fontWeight: FontWeight.w300,
                  color: fg.withValues(alpha: 0.35),
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        _flipDigit(_two(now.minute), big, 400, accent, lh: 1.0),
      ];
      if (ctx.settings['seconds'] == true) {
        timeRow.add(Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _flipDigit(
              _two(now.second), (big * 0.42).roundToDouble(), 400,
              fg.withValues(alpha: 0.45)),
        ));
      }
      if (suffix.isNotEmpty) {
        timeRow.add(Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text(suffix,
              style: TextStyle(
                  fontFamily: _font,
                  fontSize: (big * 0.3).roundToDouble(),
                  fontWeight: FontWeight.w600,
                  color: fg.withValues(alpha: 0.4))),
          ),
        );
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withGaps([
          Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: timeRow),
          dateRow,
        ], 6),
      );
    }

    ctx.renderWidget(Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
      return body(fg);
    }));
  }
}

// ---------------------------------------------------------------------------
// 待办：清单，数据按实例存（每张卡片一份）。
// ---------------------------------------------------------------------------

class TodoWidget extends BuiltinController {
  TodoWidget(super.ctx);

  List<Map<String, Object?>> items = [];

  /// 输入框控制器：原生通道下由组件自己持有，卸载时释放。
  TextEditingController? _inputCtrl;
  bool _drawn = false;

  @override
  void mount() {
    ctx.onCleanup(() {
      _inputCtrl?.dispose();
      _inputCtrl = null;
    });
    // 先画一次空的，别让卡片在加载期间是空白
    draw();
    final saved = ctx.storageGetLocal('items', <Object?>[]);
    if (saved is List && saved.isNotEmpty) {
      items = [
        for (final e in saved.cast<Map>()) Map<String, Object?>.from(e)
      ];
    }
    draw();
  }

  void _save() => ctx.storageSetLocal('items', items);

  void _addItem(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    items.add({
      'id':
          '${DateTime.now().millisecondsSinceEpoch}-${Random().nextDouble().toStringAsFixed(6).substring(2, 6)}',
      'text': text,
      'done': false,
    });
    _save();
    draw();
  }

  Widget _row(Map<String, Object?> item, Color fg) {
    final done = item['done'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      decoration: BoxDecoration(
        color: nodeColor(done ? '#FFFFFF08' : '#FFFFFF12'),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: withGaps([
          TapFeedback(
            animate: ctx.animate,
            onTap: () {
              item['done'] = !(item['done'] == true);
              _save();
              draw();
            },
            child: NodeIcon(
              name: done ? 'check_circle' : 'circle',
              size: 16,
              color: nodeColor(done ? '#7CE38B' : '#FF7A7A'),
              animate: ctx.animate,
            ),
          ),
          Expanded(
            child: Text(
              '${item['text']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: fg.withValues(alpha: done ? 0.4 : 0.95),
                decoration:
                    done ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
          TapFeedback(
            animate: ctx.animate,
            onTap: () {
              items = items
                  .where((x) => x['id'] != item['id'])
                  .map((e) => e)
                  .toList();
              _save();
              draw();
            },
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: nodeColor('#D9000000'),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: NodeIcon(
                  name: 'close',
                  size: 12,
                  color: Colors.white,
                  animate: ctx.animate,
                ),
              ),
            ),
          ),
        ], 8, horizontal: true),
      ),
    );
  }

  /// 输入框（原 input 节点）：样式与配色从 fg 派生（深浅色自动翻转），
  /// 提交即清空。控制器跨重绘复用，打字不会被重建打断。
  Widget _inputField(Color fg) {
    _inputCtrl ??= TextEditingController();
    return TextField(
      controller: _inputCtrl,
      style: TextStyle(fontSize: 13, color: fg),
      cursorColor: fg.withValues(alpha: 0.8),
      cursorHeight: 15,
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        hintText: '添加一项，回车确认',
        hintStyle: TextStyle(color: fg.withValues(alpha: 0.35), fontSize: 12),
        filled: true,
        fillColor: fg.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onSubmitted: (text) {
        _addItem(text);
        _inputCtrl?.clear();
      },
    );
  }

  void draw() {
    final hideDone = ctx.settings['hideDone'] == true;
    final shown = hideDone
        ? items.where((i) => i['done'] != true).map((e) => e).toList()
        : items;
    final left = items.where((i) => i['done'] != true).length;
    _drawn = true;

    ctx.renderWidget(Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;

      final rows = [
        for (final item in shown) _row(item, fg),
      ];

      final list = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows.isNotEmpty
              ? withGaps(rows, 5)
              : [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('还没有待办',
                        style: TextStyle(
                            fontSize: 11, color: fg.withValues(alpha: 0.28))),
                  ),
                ],
        ),
      );

      return Column(
        children: withGaps([
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 窄卡片下标题要能压缩：不加 Flexible 的话「待办」标题 +
              // 「N 项未完成」徽章会一起顶穿卡片（Row overflow）。
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: withGaps([
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                          color: nodeColor('#7CE38B'),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    Flexible(
                      child: Text('待办',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fg)),
                    ),
                  ], 7, horizontal: true),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
                decoration: BoxDecoration(
                  color: nodeColor('#FFFFFF12'),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(left > 0 ? '$left 项未完成' : '全部完成',
                    style: TextStyle(
                        fontSize: 11, color: fg.withValues(alpha: 0.6))),
              ),
            ],
          ),
          _inputField(fg),
          Expanded(child: list),
        ], 10),
      );
    }));
  }

  /// 勾选项变化下次绘制生效
  @override
  void onSettingsChange() {
    if (_drawn) draw();
  }
}
