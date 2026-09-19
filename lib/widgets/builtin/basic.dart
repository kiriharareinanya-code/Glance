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
    show HoverIconBtn, NodeIcon, TapFeedback, nodeColor, nodeWeight, withGaps;

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

  /// 正在展开日期编辑条的待办 id（null = 没有展开的）。
  String? _editingId;

  /// 'yyyy-MM-dd' 格式化（补零，跨月/跨年步进后仍可稳定解析）。
  static String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _parseDate(Object? due) {
    if (due is! String) return null;
    final p = due.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// due 距今天数：0=今天、1=明天、负数=已过 N 天。
  static int? _daysFromToday(Object? due) {
    final d = _parseDate(due);
    if (d == null) return null;
    return d.difference(_midnight(DateTime.now())).inDays;
  }

  @override
  void mount() {
    ctx.onCleanup(() {
      _inputCtrl?.dispose();
      _inputCtrl = null;
    });
    // 跨过午夜把倒计时徽章翻面（今天 → 超1天），与日历同款 60s 检查。
    var dayStamp = DateTime.now().day;
    ctx.interval(() {
      final now = DateTime.now();
      if (now.day != dayStamp) {
        dayStamp = now.day;
        if (_drawn) draw();
      }
    }, 60000);
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
    final editing = _editingId == item['id'];
    final days = _daysFromToday(item['due']);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      decoration: BoxDecoration(
        color: nodeColor(done ? '#FFFFFF08' : '#FFFFFF12'),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              // 倒计时徽章：完成态和编辑态不显示（编辑条里有完整日期信息）
              if (!done && !editing && days != null) _dueBadge(days),
              // 日历图标 = 加日期入口：点一下落"今天"并展开步进条，再点收起
              HoverIconBtn(
                icon: 'calendar',
                size: 14,
                color: editing ? nodeColor('#7CE38B') : fg,
                animate: ctx.animate,
                idleAlpha: editing ? 1.0 : 0.55,
                hitW: 20,
                hitH: 20,
                onTap: () {
                  if (editing) {
                    _editingId = null;
                  } else {
                    _editingId = '${item['id']}';
                    if (item['due'] == null) {
                      item['due'] = _fmtDay(DateTime.now());
                      _save();
                    }
                  }
                  draw();
                },
              ),
              TapFeedback(
                animate: ctx.animate,
                onTap: () {
                  items = items
                      .where((x) => x['id'] != item['id'])
                      .map((e) => e)
                      .toList();
                  if (_editingId == item['id']) _editingId = null;
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
          if (editing) ...[
            const SizedBox(height: 5),
            _dueEditor(item, fg),
          ],
        ],
      ),
    );
  }

  /// 倒计时徽章：今天/明天 accent 绿、剩N天中性、超N天暖红（中文惯例：
  /// 临近=提示、过期=警示，颜色跟内容语义走而不是跟着主题走）。
  Widget _dueBadge(int days) {
    final String text;
    final String bgHex;
    final String fgHex;
    if (days == 0 || days == 1) {
      text = days == 0 ? '今天' : '明天';
      bgHex = '#7CE38B26';
      fgHex = '#7CE38B';
    } else if (days > 1) {
      text = '剩$days天';
      bgHex = '#FFFFFF14';
      fgHex = '#FFFFFF9E';
    } else {
      text = '超${-days}天';
      bgHex = '#FF7A7A26';
      fgHex = '#FF7A7A';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: BoxDecoration(
        color: nodeColor(bgHex),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10.5, color: nodeColor(fgHex))),
    );
  }

  /// 行内日期步进条（磁贴窗口 region 外是穿透的，弹不出日期选择器，
  /// 所以用 [−]/[+] 按天步进 + 点日期回今天的行内交互）。
  Widget _dueEditor(Map<String, Object?> item, Color fg) {
    final d = _parseDate(item['due']) ?? _midnight(DateTime.now());
    final days = d.difference(_midnight(DateTime.now())).inDays;
    final dateText = '${d.month}月${d.day}日';
    final relText = days == 0
        ? '今天'
        : days == 1
            ? '明天'
            : days > 1
                ? '剩$days天'
                : '超${-days}天';

    void step(int delta) {
      item['due'] = _fmtDay(d.add(Duration(days: delta)));
      _save();
      draw();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      decoration: BoxDecoration(
        color: nodeColor('#FFFFFF0A'),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: withGaps([
          _stepBtn('minus', () => step(-1), fg),
          // 点日期文字 = 回到今天
          TapFeedback(
            animate: ctx.animate,
            onTap: () {
              item['due'] = _fmtDay(DateTime.now());
              _save();
              draw();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('$dateText · $relText',
                  style:
                      TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.9))),
            ),
          ),
          _stepBtn('add', () => step(1), fg),
          const Spacer(),
          // 清除日期并收起编辑条
          TapFeedback(
            animate: ctx.animate,
            onTap: () {
              item.remove('due');
              _editingId = null;
              _save();
              draw();
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: NodeIcon(
                name: 'close',
                size: 12,
                color: fg.withValues(alpha: 0.4),
                animate: ctx.animate,
              ),
            ),
          ),
        ], 6, horizontal: true),
      ),
    );
  }

  /// 步进小圆钮（[−]/[+]）。
  Widget _stepBtn(String icon, VoidCallback action, Color fg) {
    return TapFeedback(
      animate: ctx.animate,
      onTap: action,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: nodeColor('#FFFFFF14'),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: NodeIcon(
            name: icon,
            size: 14,
            color: fg.withValues(alpha: 0.75),
            animate: ctx.animate,
          ),
        ),
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
