/// 内置组件：日历。月视图，每格上面公历、下面农历/节气/节日。
/// 农历与节气的算法在 lunar.dart。
library;

import 'package:flutter/material.dart';

import '../catalog.dart';
import '../kit.dart'
    show NodeIcon, TapFeedback, nodeColor, nodeWeight, withGaps;
import '../node_anim.dart' show kNodeAnimDuration;
import 'lunar.dart';

class CalendarWidget extends BuiltinController {
  CalendarWidget(super.ctx);

  late DateTime _today;
  late int _viewYear;
  late int _viewMonth; // 0-11

  static const _accent = '#29B6F6'; // 今天的圆底
  static const _holiday = '#FF8A6B'; // 法定节假日
  static const _term = '#8FD6A0'; // 节气

  @override
  void mount() {
    _today = DateTime.now();
    _viewYear = _today.year;
    _viewMonth = _today.month - 1;
    draw();
    // 跨过午夜把"今天"挪过去
    ctx.interval(() {
      final now = DateTime.now();
      if (now.day != _today.day) {
        _today = now;
        draw();
      }
    }, 60000);
  }

  @override
  void onSettingsChange() => draw();

  // ---- 原生视图 ----

  TextStyle _ts(Color fg,
      {double? size,
      double? opacity,
      int? weight,
      double? spacing,
      Color? color}) {
    return TextStyle(
      fontSize: size,
      color: color ?? fg.withValues(alpha: opacity ?? 1.0),
      fontWeight: weight == null ? null : nodeWeight(weight),
      letterSpacing: spacing,
    );
  }

  Widget _grid(
      {required int cols,
      required double gap,
      required bool fill,
      required List<Widget> kids}) {
    final rows = <Widget>[];
    for (var i = 0; i < kids.length; i += cols) {
      final slice = kids.sublist(i, (i + cols).clamp(0, kids.length));
      final cells = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0 && gap > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(
            child: j < slice.length ? slice[j] : const SizedBox.shrink()));
      }
      if (rows.isNotEmpty && gap > 0) rows.add(SizedBox(height: gap));
      rows.add(fill ? Expanded(child: Row(children: cells)) : Row(children: cells));
    }
    return Column(
      mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
      children: rows,
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: const Color(0x1AFFFFFF),
        margin: const EdgeInsets.symmetric(vertical: 4),
      );

  Widget _dot(Color c) => Container(
        width: 4,
        height: 4,
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
      );

  Widget _chip(Widget child, {Color bg = const Color(0x14FFFFFF)}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: child,
      );

  void draw() {
    final showLunar = ctx.settings['lunar'] != false;
    final showFest = ctx.settings['festival'] != false;
    final mondayFirst = ctx.settings['mondayFirst'] != false;

    final heads = mondayFirst
        ? ['一', '二', '三', '四', '五', '六', '日']
        : ['日', '一', '二', '三', '四', '五', '六'];
    final weekendCols = mondayFirst ? [5, 6] : [0, 6];

    final startDow = DateTime(_viewYear, _viewMonth + 1, 1).weekday % 7; // 0=周日
    final lead = mondayFirst ? (startDow + 6) % 7 : startDow;

    final offMonth =
        !(_viewYear == _today.year && _viewMonth == _today.month - 1);

    Widget body(Color fg) {
      // 固定 6 行 42 格：月份切换时高度不跳变
      final cells = <Widget>[];
      for (var i = 0; i < 42; i++) {
        final d = DateTime(_viewYear, _viewMonth + 1, 1 - lead + i);
        final inMonth = d.month == _viewMonth + 1;
        final col = i % 7;
        cells.add(_cell(
            d, inMonth, weekendCols.contains(col), showLunar, showFest, fg));
      }

      final headCells = [
        for (var i = 0; i < heads.length; i++)
          Text(heads[i],
              textAlign: TextAlign.center,
              style: _ts(fg,
                  size: 13,
                  weight: 600,
                  spacing: 1,
                  opacity: weekendCols.contains(i) ? 0.8 : 0.62)),
      ];

      final header = Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TapFeedback(
            animate: ctx.animate,
            onTap: () {
              _viewYear = _today.year;
              _viewMonth = _today.month - 1;
              draw();
            },
            child: Row(
              children: withGaps([
                Text('$_viewYear年${_viewMonth + 1}月',
                    style: _ts(fg, size: 17, weight: 600)),
                offMonth
                    ? _chip(Text('今天',
                        style: _ts(fg, size: 10, opacity: 0.78)))
                    : const SizedBox.shrink(),
              ], 6, horizontal: true),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: withGaps([
              TapFeedback(
                animate: ctx.animate,
                onTap: () {
                  _viewMonth--;
                  if (_viewMonth < 0) {
                    _viewMonth = 11;
                    _viewYear--;
                  }
                  draw();
                },
                child: SizedBox(
                  width: 26,
                  height: 22,
                  child: Center(
                    child: NodeIcon(
                        name: 'up',
                        size: 20,
                        color: nodeColor('#FFFFFF66'),
                        animate: ctx.animate),
                  ),
                ),
              ),
              TapFeedback(
                animate: ctx.animate,
                onTap: () {
                  _viewMonth++;
                  if (_viewMonth > 11) {
                    _viewMonth = 0;
                    _viewYear++;
                  }
                  draw();
                },
                child: SizedBox(
                  width: 26,
                  height: 22,
                  child: Center(
                    child: NodeIcon(
                        name: 'down',
                        size: 20,
                        color: nodeColor('#FFFFFF66'),
                        animate: ctx.animate),
                  ),
                ),
              ),
            ], 2, horizontal: true),
          ),
        ],
      );

      // 尺寸分档：格子越多，能承载的信息越多。
      // 小档只放月历；中档加今日一行；大档在下方展开今日详情与近期节气/节日。
      final rows = ctx.grid.rows;
      final children = <Widget>[header];
      if (rows >= 4) children.add(_todayStrip(fg));
      children.add(_grid(cols: 7, gap: 0, fill: false, kids: headCells));
      children.add(Expanded(
        child: _grid(cols: 7, gap: 5, fill: true, kids: cells),
      ));
      if (rows >= 5) {
        children.add(_divider());
        children.add(_upcoming(fg));
      }

      // key 变化时宿主做交叉淡入（与旧根 key 同参数）。只在真正换月时变，
      // 不会每次重绘都动画。
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: withGaps(children, 10),
      );
      if (!ctx.animate) return content;
      return AnimatedSwitcher(
        duration: kNodeAnimDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(
            key: ValueKey('$_viewYear-$_viewMonth'), child: content),
      );
    }

    ctx.renderWidget(Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
      return body(fg);
    }));
  }

  /// 今日一行：农历全称 + 干支生肖
  Widget _todayStrip(Color fg) {
    final l = Lunar.fromSolar(_today.year, _today.month, _today.day);
    if (l == null) return const SizedBox.shrink();
    final parts = <Widget>[
      _chip(
        Text('${l.monthText}${l.dayText}', style: _ts(fg, size: 12)),
      ),
      Text('${Lunar.ganzhi(l.y)}年', style: _ts(fg, size: 12, opacity: 0.58)),
      Text('属${Lunar.zodiac(l.y)}', style: _ts(fg, size: 12, opacity: 0.58)),
    ];
    final t = Lunar.termOf(_today.year, _today.month, _today.day);
    if (t != null) {
      parts.add(_chip(
        Text('今日$t', style: _ts(fg, size: 12, color: nodeColor('#8FD6A0'))),
        bg: nodeColor('#8FD6A022'),
      ));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: withGaps(parts, 8, horizontal: true),
    );
  }

  /// 大尺寸：下一个节气 + 本月剩余的节日
  Widget _upcoming(Color fg) {
    final y = _today.year;
    final m = _today.month;
    final d = _today.day;
    final items = <Widget>[];

    final nt = Lunar.nextTerm(y, m, d);
    if (nt != null) {
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: withGaps([
          _dot(nodeColor('#8FD6A0')),
          Text(nt.name, style: _ts(fg, size: 12.5)),
          Text('${nt.days} 天后', style: _ts(fg, size: 11.5, opacity: 0.55)),
        ], 6, horizontal: true),
      ));
    }

    // 本月内今天之后的节日，最多列 3 条
    final daysInMonth = DateTime(y, m + 1, 0).day;
    var listed = 0;
    for (var i = d + 1; i <= daysInMonth && listed < 3; i++) {
      final l = Lunar.fromSolar(y, m, i);
      final f = l != null ? Lunar.festivalOf(y, m, i, l) : null;
      if (f == null) continue;
      items.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: withGaps([
          _dot(nodeColor(f.statutory ? '#FF8A6B' : '#FFFFFF55')),
          Text(f.name,
              style: _ts(fg,
                  size: 12.5,
                  color: f.statutory ? nodeColor('#FF8A6B') : null)),
          Text('$m月$i日', style: _ts(fg, size: 11.5, opacity: 0.55)),
        ], 6, horizontal: true),
      ));
      listed++;
    }

    if (items.isEmpty) {
      items.add(Text('本月没有更多节日了',
          style: _ts(fg, size: 11.5, opacity: 0.42)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: withGaps(items, 6),
    );
  }

  /// 一格：上面公历日，下面农历/节气/节日
  Widget _cell(DateTime d, bool inMonth, bool weekend, bool showLunar,
      bool showFest, Color fg) {
    final y = d.year;
    final m = d.month;
    final day = d.day;
    final isToday = _today.year == y && _today.month == m && _today.day == day;

    final lunar = Lunar.fromSolar(y, m, day);
    final term = Lunar.termOf(y, m, day);
    final fest = lunar != null ? Lunar.festivalOf(y, m, day, lunar) : null;

    // 下行文字的优先级：节日 > 节气 > 初一显示月份 > 农历日
    var sub = '';
    Color? subColor;
    if (showFest && fest != null) {
      sub = fest.name;
      subColor = fest.statutory ? nodeColor(_holiday) : null;
    } else if (showFest && term != null) {
      sub = term;
      subColor = nodeColor(_term);
    } else if (showLunar && lunar != null) {
      sub = lunar.d == 1 ? lunar.monthText : lunar.dayText;
    }

    // 节日/节气所在格给一个淡的圆底，让它从一片数字里跳出来
    final marked =
        !isToday && inMonth && showFest && (fest != null || term != null);

    // 法定节假日：日期数字也用节日色
    final statutory = showFest && fest != null && fest.statutory;

    Color? dayColor;
    var dayOpacity = 1.0;
    if (isToday) {
      dayColor = nodeColor('#0B1116');
    } else if (!inMonth) {
      // 非本月：弱化但保持可辨认
      dayOpacity = 0.4;
    } else if (weekend || statutory) {
      dayColor = nodeColor(_holiday);
      dayOpacity = 1;
    }

    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: withGaps([
        Text('$day',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              color: dayColor ?? fg.withValues(alpha: dayOpacity),
              fontWeight: nodeWeight(isToday ? 800 : 600),
              letterSpacing: 0.3,
            )),
        if (sub.isNotEmpty)
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isToday
                    ? nodeColor('#0B1116').withValues(alpha: 0.9)
                    : subColor?.withValues(alpha: 1.0) ??
                        fg.withValues(alpha: inMonth ? 0.72 : 0.32),
              )),
      ], 2),
    );

    // 格子原来是死钉 38x38 的：列宽由外层 Expanded 均分，卡片一窄（2x2 那种）
    // 每列只有 24px 左右，7 列 × 38 直接超出可用宽度，Row 溢出之后日期数字
    // 和农历文字各站一边——反馈 Fb0012 的"中文全部靠边站了、文字错位"就是这么
    // 来的。改成"取列宽但不超过 38"的正方形，格子缩小时内容跟着缩放。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 38, maxHeight: 38),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? nodeColor(_accent)
                  : (marked ? nodeColor('#FFFFFF18') : null),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
