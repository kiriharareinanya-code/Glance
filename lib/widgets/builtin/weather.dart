/// 内置组件：天气。小米天气 v3 API（免签硬编码 appKey）+ 中国天气网城市
/// 搜索 + 自动定位。
///
/// 数据源说明（2026-08 实测，见原 JS 版注释）：
///   - v3 要求经纬度；城市码来自中国天气网 toy1 搜索（9 位码 +
///     "weathercn:" 前缀即小米的 locationKey）；
///   - daily/hourly 数组没有日期字段：index 0 = 今天/起始小时；
///   - 天气代码按 MIUI 内置表映射中文描述与图标。
///
/// 前脸：当前温度 + 体感/湿度/风/UV 徽章 + 5 天预报；
/// 后脸：12 小时逐时预报 + 空气质量/UV 环境指数。
///
/// 自动翻转的节奏（反馈"翻页太快、看不过来"）：
///   - 停留时长从 8s 拉到 [kFlipDwell]（30s），翻面动画 [kFlipAnim] 也从
///     600ms 放慢到 900ms——以前"咔"一下就换脸，内容还没读就到背面了；
///   - 手动干预优先：点一下立刻翻面并**重排计时**（[_.flipManual]），
///     鼠标停在卡片上不自动翻（[_.setHover]），这样停在某一面看多久都行；
///   - 设置里可以彻底关掉自动翻转（flipAuto=false），只靠点击切换。
library;

import 'dart:convert';

import '../catalog.dart';
import '../kit.dart'
    show FlipSwap, NodeIcon, TapFeedback, nodeColor, nodeWeight, withGaps;
import 'package:flutter/material.dart';

/// 自动翻面后停留多久（毫秒）。原来写死 8000，反馈说太快。
const int kFlipDwell = 30000;

/// 翻面动画时长。原来 600ms，跟着停留时长一起放慢，观感更"轻"。
const Duration kFlipAnim = Duration(milliseconds: 900);

class _Loc {
  _Loc(this.name, this.cityId, this.lat, this.lon);
  final String name;
  final String cityId;
  final double lat;
  final double lon;
}

class WeatherWidget extends BuiltinController {
  WeatherWidget(super.ctx);

  String _status = 'loading';
  String _error = '';
  Map<String, Object?>? _data;
  _Loc? _loc;
  String _face = 'f'; // flipKey：'f' = 正面，'b' = 背面
  String? _flipTimer;
  String? _refreshTimer;

  /// 鼠标是否停在卡片上。停着就不自动翻——正在看逐时预报的时候
  /// 被翻回正面是很恼人的事。
  bool _hover = false;

  /// 用户是否手动干预过（点过一下）。
  ///
  /// 手动之后**跳过一次**自动翻转：点了「切到背面」马上又被计时器翻回来
  /// 会让人以为点击丢了。下一次计时到点后自动恢复轮转。
  bool _manualHold = false;

  // 小米天气代码表：代码 -> [中文描述, 图标]
  static const Map<int, List<String>> _code = {
    0: ['晴', 'sun'], 1: ['多云', 'cloud'], 2: ['阴', 'cloud'], 3: ['阵雨', 'rain'],
    4: ['雷阵雨', 'storm'], 5: ['雷阵雨伴冰雹', 'storm'], 6: ['雨夹雪', 'sleet'],
    7: ['小雨', 'rain'], 8: ['中雨', 'rain'], 9: ['大雨', 'rain'], 10: ['暴雨', 'rain'],
    11: ['大暴雨', 'rain'], 12: ['特大暴雨', 'rain'], 13: ['阵雪', 'snow'],
    14: ['小雪', 'snow'], 15: ['中雪', 'snow'], 16: ['大雪', 'snow'], 17: ['暴雪', 'snow'],
    18: ['雾', 'fog'], 19: ['冻雨', 'rain'], 20: ['沙尘暴', 'fog'],
    21: ['小雨-中雨', 'rain'], 22: ['中雨-大雨', 'rain'], 23: ['大雨-暴雨', 'rain'],
    24: ['暴雨-大暴雨', 'rain'], 25: ['大暴雨-特大暴雨', 'rain'],
    26: ['小雪-中雪', 'snow'], 27: ['中雪-大雪', 'snow'], 28: ['大雪-暴雪', 'snow'],
    29: ['浮尘', 'fog'], 30: ['扬沙', 'fog'], 31: ['强沙尘暴', 'fog'],
    32: ['飑', 'storm'], 33: ['龙卷风', 'storm'], 34: ['高吹雪', 'snow'],
    35: ['轻雾', 'fog'], 53: ['霾', 'fog'], 99: ['未知', 'cloud'],
  };
  static String _descOf(int code) => (_code[code] ?? _code[99]!)[0];
  static String _iconOf(int code) => (_code[code] ?? _code[99]!)[1];

  // 图标颜色跟着天气语义走
  static const Map<String, String> _iconColor = {
    'sun': '#FFD79A', 'cloud': '#B8C4D9', 'fog': '#C7CFD9',
    'rain': '#7CC7FF', 'snow': '#DCEEFA', 'storm': '#B79CFF',
  };
  static String _iconColorOf(int code) =>
      _iconColor[_iconOf(code)] ?? _iconColor['cloud']!;

  static int _codeOf(Object? raw) {
    final v = int.tryParse('$raw');
    return v ?? 99;
  }

  @override
  void mount() {
    _draw();
    // 实例私有键值是同步读的：有缓存就先画，再拉新数据
    final cached = ctx.storageGetLocal('cache');
    if (cached is Map) {
      _data = (cached['data'] as Map?)?.cast<String, Object?>();
      final l = cached['loc'] as Map?;
      if (l != null) {
        _loc = _Loc('${l['name']}', '${l['cityId']}',
            (l['lat'] as num).toDouble(), (l['lon'] as num).toDouble());
      }
      if (_data != null && _loc != null) {
        _status = 'ok';
        _draw();
        // 走 _restartFlipTimer 而不是 _startFlipTimer：它内部会先看
        // "自动翻页"开关有没有被关掉（flipAuto=false 时不排计时）。
        _restartFlipTimer();
      }
    }
    _load();
    final mins = num.tryParse('${ctx.settings['refreshMin']}')?.toInt() ?? 30;
    _refreshTimer = ctx.interval(_load, (mins < 5 ? 5 : mins) * 60000);
    ctx.onCleanup(() {
      if (_refreshTimer != null) ctx.clearTimer(_refreshTimer!);
      if (_flipTimer != null) ctx.clearTimer(_flipTimer!);
    });
  }

  // ---- 前脸：当前天气 + 5 天预报（原生 Widget）----

  /// 按列数平分宽度的网格。
  ///
  /// 反馈"窄的时候不该硬塞一排"：卡片被拉窄（或用户在设置里把网格单元调小、
  /// 又把卡片放到小屏上）时，5 天预报 / 12 小时逐时这种"固定列数"的排布
  /// 会把每格挤成几十像素，字都糊在一起。所以这里加一道窄宽降级：
  ///
  ///   - 先算「一格至少 [minCell] 宽」能塞下几列，取 `cols` 与该值的较小者；
  ///   - 剩余放不下的格子**换行另起一排**（自动换行），而不是被压扁；
  ///   - 列数降到 1 时（极窄）自然变成从上到下的垂直堆叠，和手机端一致。
  ///
  /// [fill] 仍然只让"原始列数未变"的情形均分高度——换行后行数变多，
  /// 再均分会把上下间距撑得很怪。
  Widget _grid({
    required int cols,
    required double gap,
    required bool fill,
    required List<Widget> kids,
    double minCell = 44,
  }) {
    // 可用宽度来自卡片真实尺寸（ctx.size 已刨掉卡片内边距，见 surface.dart）
    final avail = ctx.size.width;
    final effective = <Widget>[];
    // 先按 minCell 约束把列数降下来，最少 1 列（= 纯垂直堆叠）
    var c = cols;
    while (c > 1 &&
        (avail - gap * (c - 1)) / c < minCell) {
      c--;
    }
    final wrapped = c != cols;

    for (var i = 0; i < kids.length; i += c) {
      final slice = kids.sublist(i, (i + c).clamp(0, kids.length));
      final cells = <Widget>[];
      for (var j = 0; j < c; j++) {
        if (j > 0 && gap > 0) cells.add(SizedBox(width: gap));
        cells.add(Expanded(
            child: j < slice.length ? slice[j] : const SizedBox.shrink()));
      }
      if (effective.isNotEmpty && gap > 0) {
        effective.add(SizedBox(height: gap));
      }
      final row = Row(children: cells);
      // 换行后不再均分高度：行数多了，均分反而把内容拉散
      effective.add(fill && !wrapped ? Expanded(child: row) : row);
    }
    return Column(
      mainAxisSize: fill && !wrapped ? MainAxisSize.max : MainAxisSize.min,
      children: effective,
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: const Color(0x1AFFFFFF),
        margin: const EdgeInsets.symmetric(vertical: 4),
      );

  /// 钉死可用高度的取景框：内容超了就裁，不会顶穿卡片（与旧 box h+clip 对应）。
  Widget _framed(Widget child) {
    return SizedBox(
      height: ctx.size.height,
      width: double.infinity,
      child: ClipRect(
        child: OverflowBox(
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }

  TextStyle _ts(Color fg,
      {double? size,
      double? opacity,
      int? weight,
      double? spacing,
      bool mono = false}) {
    return TextStyle(
      fontSize: size,
      color: fg.withValues(alpha: opacity ?? 1.0),
      fontWeight: weight == null ? null : nodeWeight(weight),
      letterSpacing: spacing,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
  }

  Widget _buildFront(
      Map<String, Object?> data, _Loc loc, int rows, Color fg) {
    final cur = (data['current'] as Map?)?.cast<String, Object?>() ?? {};
    final fd = (data['forecastDaily'] as Map?)?.cast<String, Object?>() ?? {};
    final compact = rows <= 2;
    final curCode = _codeOf(cur['weather']);
    // 窄宽度自适应：卡片被压窄时把温度字号和图标一起收一号，否则
    // 「48px 数字 + 40px 图标 + 间隔」会超出可用宽度（Row 直接溢出）。
    final narrow = ctx.size.width < 210;
    final bigSize = narrow ? 34.0 : 48.0;
    final iconBox = narrow ? 30.0 : 40.0;
    final kids = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: withGaps([
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: withGaps([
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                          color: nodeColor('#7CC7FF'),
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    // 城市名可能比可用宽度长（"内蒙古自治区锡林郭勒盟"那种），
                    // 弹性 + 省略号，别把整行顶破
                    Flexible(
                      child: Text(loc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _ts(fg, size: 13, opacity: 0.55)),
                    ),
                  ], 6, horizontal: true),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_nest(cur, ['temperature', 'value']) ?? '--'}',
                        style: _ts(fg, size: bigSize, weight: 300, mono: true)),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 4),
                      child: Text('°',
                          style: _ts(fg, size: 22, weight: 300, opacity: 0.5)),
                    ),
                  ],
                ),
              ], 3),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: withGaps([
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: nodeColor('${_iconColorOf(curCode)}26'),
                  borderRadius: BorderRadius.circular(iconBox / 2),
                ),
                child: Center(
                  child: NodeIcon(
                      name: _iconOf(curCode),
                      size: narrow ? 17 : 22,
                      color: nodeColor(_iconColorOf(curCode)),
                      animate: ctx.animate),
                ),
              ),
              Text(_descOf(curCode), style: _ts(fg, size: 12, opacity: 0.65)),
            ], 6),
          ),
        ],
      ),
    ];

    // 当前详情徽章：体感 / 湿度 / 风速 / UV
    final detail = <Map<String, String>>[];
    final feels = _nest(cur, ['feelsLike', 'value']);
    if (feels != null) {
      detail.add({'icon': 'thermostat', 'v': '体感 $feels°'});
    }
    final hum = _nest(cur, ['humidity', 'value']);
    if (hum != null) detail.add({'icon': 'rain', 'v': '$hum%'});
    final wind = _nest(cur, ['wind', 'speed', 'value']);
    if (wind != null) detail.add({'icon': 'air', 'v': '${wind}km/h'});
    final uv = cur['uvIndex'];
    if (uv != null && '$uv' != '') {
      detail.add({'icon': 'sun', 'v': 'UV $uv'});
    }
    if (detail.isNotEmpty) {
      // 徽章行改用 Wrap：卡片窄的时候"体感 26° / 湿度 62% / 风速 8km/h / UV 3"
      // 四个胶囊并排会溢出（Row 直接报 overflow 黄条）。Wrap 放不下就自动
      // 折到下一行，和手机端小组件的行为一致。
      kids.add(Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final it in detail)
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              decoration: BoxDecoration(
                color: nodeColor('#FFFFFF12'),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: withGaps([
                  NodeIcon(
                      name: it['icon']!,
                      size: 11,
                      color: fg.withValues(alpha: 0.55),
                      animate: ctx.animate),
                  Text(it['v']!, style: _ts(fg, size: 11, opacity: 0.75)),
                ], 4, horizontal: true),
              ),
            ),
        ],
      ));
    }

    // 5 天预报：forecastDaily index 0 = 今天，星期用本地日期加下标推算
    final days = <Widget>[];
    final temps =
        (_nest(fd, ['temperature', 'value']) as List?)?.cast<Object?>() ?? [];
    final wtrs =
        (_nest(fd, ['weather', 'value']) as List?)?.cast<Object?>() ?? [];
    for (var i = 0; i < 5; i++) {
      final hi = _numOf(temps.length > i ? _from(temps[i]) : null);
      final lo = _numOf(temps.length > i ? _to(temps[i]) : null);
      final wcode = _codeOf(i < wtrs.length ? _from(wtrs[i]) : null);
      final d = DateTime.now().add(Duration(days: i));
      const wk = ['日', '一', '二', '三', '四', '五', '六'];
      final label = i == 0 ? '今天' : '周${wk[d.weekday % 7]}';
      final cellKids = <Widget>[
        Text(label, textAlign: TextAlign.center, style: _ts(fg, size: 11, opacity: 0.45)),
        NodeIcon(
            name: _iconOf(wcode),
            size: 15,
            color: nodeColor(_iconColorOf(wcode)),
            animate: ctx.animate),
      ];
      if (hi != null) {
        cellKids.add(Text('${hi.round()}°',
            textAlign: TextAlign.center,
            style: _ts(fg, size: 12, weight: 600)));
        if (!compact && lo != null) {
          cellKids.add(Text('${lo.round()}°',
              textAlign: TextAlign.center,
              style: _ts(fg, size: 11, opacity: 0.4)));
        }
      }
      days.add(Container(
        padding: EdgeInsets.symmetric(
            vertical: compact ? 2 : 6, horizontal: 2),
        decoration: BoxDecoration(
          color: nodeColor(i == 0 ? '#FFFFFF1C' : '#FFFFFF0A'),
          borderRadius: BorderRadius.circular(10),
          border: i == 0
              ? Border.all(color: nodeColor('#FFFFFF2E'))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: withGaps(cellKids, 4),
        ),
      ));
    }
    if (days.isNotEmpty) {
      kids.add(_divider());
      kids.add(_grid(cols: 5, gap: 4, fill: false, kids: days));
    }
    // h + clip 兜底：钉死可用高度，不会顶穿卡片
    return _framed(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: withGaps(kids, 8),
    ));
  }

  // ---- 后脸：12 小时逐时 + 空气质量/UV 环境指数 ----
  Widget _buildBack(Map<String, Object?> data, int rows, Color fg) {
    final fh = (data['forecastHourly'] as Map?)?.cast<String, Object?>() ?? {};
    final aqi = (data['aqi'] as Map?)?.cast<String, Object?>() ?? {};
    final compact = rows <= 2;
    final kids = <Widget>[];

    final hTemps =
        (_nest(fh, ['temperature', 'value']) as List?)?.cast<Object?>() ?? [];
    final hWtrs =
        (_nest(fh, ['weather', 'value']) as List?)?.cast<Object?>() ?? [];
    if (hTemps.isNotEmpty) {
      // 起始小时从 pubTime 算，后面的按 index 递推
      final pubTime = _nest(fh, ['temperature', 'pubTime']);
      var startDate = DateTime.now();
      if (pubTime != null) {
        startDate = DateTime.tryParse('$pubTime') ?? DateTime.now();
      }
      final cols = <Widget>[];
      const hn = 12;
      for (var k = 0; k < hn && k < hTemps.length; k++) {
        final hd = startDate.add(Duration(hours: k));
        final hc = _codeOf(k < hWtrs.length ? hWtrs[k] : null);
        cols.add(Column(
          mainAxisSize: MainAxisSize.min,
          children: withGaps([
            Text('${hd.hour}时', style: _ts(fg, size: 10, opacity: 0.45)),
            NodeIcon(
                name: _iconOf(hc),
                size: 14,
                color: nodeColor(_iconColorOf(hc)),
                animate: ctx.animate),
            Text('${_asNum(hTemps[k]).round()}°',
                textAlign: TextAlign.center,
                style: _ts(fg, size: 11.5, weight: 600)),
          ], 3),
        ));
      }
      kids.add(Text('未来 ${cols.length} 小时',
          style: _ts(fg, size: 11, opacity: 0.45)));
      // 6 列：12 个小时格子排成 2 行 x 6 列
      kids.add(_grid(cols: 6, gap: 4, fill: false, kids: cols));
      if (!compact) kids.add(_divider());
    }

    // 环境指数：AQI 数值 + 一句话建议 + UV 等级
    {
      final env = <String>[];
      if (aqi['aqi'] != null && '${aqi['aqi']}' != '') {
        env.add('AQI ${aqi['aqi']}');
      }
      if (aqi['suggest'] != null && '${aqi['suggest']}' != '') {
        env.add('${aqi['suggest']}');
      }
      final uv = (data['current'] as Map?)?['uvIndex'];
      if (uv != null && '$uv' != '') {
        final uvN = int.tryParse('$uv') ?? 0;
        final uvLabel = uvN >= 11
            ? '极强'
            : uvN >= 8
                ? '很强'
                : uvN >= 6
                    ? '强'
                    : uvN >= 3
                        ? '中等'
                        : '弱';
        env.add('UV $uv（$uvLabel）');
      }
      if (env.isNotEmpty) {
        if (!compact) kids.add(_divider());
        kids.add(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in env)
              Text(s, style: _ts(fg, size: 11, opacity: 0.5)),
          ],
        ));
      }
    }

    return _framed(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: withGaps(kids, 8),
    ));
  }

  // ---- 主渲染 ----
  void _draw() {
    if (_status == 'loading') {
      ctx.renderWidget(Builder(builder: (context) {
        final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Text('正在获取天气…', style: _ts(fg, size: 12, opacity: 0.45))],
        );
      }));
      return;
    }
    if (_status == 'error') {
      ctx.renderWidget(Builder(builder: (context) {
        final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: withGaps([
            Row(
              mainAxisSize: MainAxisSize.min,
              children: withGaps([
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                      color: nodeColor('#FF9E7D'),
                      borderRadius: BorderRadius.circular(2)),
                ),
                Text('天气不可用',
                    style: _ts(fg, size: 12, weight: 600)),
              ], 6, horizontal: true),
            ),
            Text(_error,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _ts(fg, size: 10.5, opacity: 0.5)),
            TapFeedback(
              animate: ctx.animate,
              onTap: () {
                _status = 'loading';
                _draw();
                _load();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
                decoration: BoxDecoration(
                  color: nodeColor('#FFFFFF14'),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('重试', style: _ts(fg, size: 11)),
              ),
            ),
          ], 10),
        );
      }));
      return;
    }

    Widget body(Color fg) {
      final front = _buildFront(_data!, _loc!, ctx.grid.rows, fg);
      final back = _buildBack(_data!, ctx.grid.rows, fg);
      if (!ctx.animate) return front;
      // 翻面动画跟着停留时长一起放慢（kFlipAnim）：600ms 配上 8s 停留
      // 显得很急，900ms 配 30s 停留才像"翻页"而不是"闪一下"。
      return FlipSwap(
        flipKey: _face,
        front: front,
        back: back,
        duration: kFlipAnim,
      );
    }

    ctx.renderWidget(Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
      // MouseRegion 负责"停住就不翻"，TapFeedback 负责"点一下立刻翻"。
      // 两层都只是旁路信号，不改变卡片本身的命中区。
      return MouseRegion(
        onEnter: (_) => setHover(true),
        onExit: (_) => setHover(false),
        child: TapFeedback(
          animate: ctx.animate,
          onTap: flipManual,
          child: body(fg),
        ),
      );
    }));
  }

  // ---- 翻转节奏 ----

  /// 手动翻到另一面。点击与"下一面"按钮都走这里。
  ///
  /// 翻完**重排计时**：不重排的话手动翻过去可能 1 秒后又被自动翻回来，
  /// 用户会觉得"点了没用"。
  void flipManual() {
    _manualHold = true;
    _face = _face == 'f' ? 'b' : 'f';
    _draw();
    _restartFlipTimer();
  }

  /// 悬停状态变化。进入悬停时挂起自动翻转（不取消重排，退出后重新计时）。
  void setHover(bool on) {
    if (_hover == on) return;
    _hover = on;
    if (on) {
      // 停住：先把待触发的计时撤掉，不然鼠标一停就正好翻走
      if (_flipTimer != null) {
        ctx.clearTimer(_flipTimer!);
        _flipTimer = null;
      }
    } else {
      _restartFlipTimer();
    }
  }

  /// 自动翻转开关（设置项 flipAuto，默认开）。
  bool get _autoFlip => ctx.settings['flipAuto'] != false;

  void _restartFlipTimer() {
    if (_flipTimer != null) {
      ctx.clearTimer(_flipTimer!);
      _flipTimer = null;
    }
    if (!_autoFlip) return;
    _startFlipTimer();
  }

  // ---- 翻转定时器 ----
  //
  // 反馈"翻转太快"：停留从 8s 提到 kFlipDwell（30s）。到点时的判定仍然是
  // "翻到另一面"，而不是翻回正面——两面都有值得看的内容，一路轮着转才是
  // 本来想要的行为。
  void _startFlipTimer() {
    if (_flipTimer != null) ctx.clearTimer(_flipTimer!);
    if (!_autoFlip) return;
    _flipTimer = ctx.interval(() {
      // 悬停中不翻：等鼠标走开时 _restartFlipTimer 会重新计时
      if (_hover) return;
      // 刚被手动翻过，这一拍让给用户：清掉标记，等下一拍再自动翻。
      // 只跳过一拍而不是一直挂起——"手动暂停"由 flipAuto 开关和悬停负责，
      // 这里只要不打架就行。
      if (_manualHold) {
        _manualHold = false;
        return;
      }
      _face = _face == 'f' ? 'b' : 'f';
      _draw();
    }, kFlipDwell);
  }

  /// 设置面板里改了"自动翻页"开关，立即生效（不用等下次刷新重挂载）
  @override
  void onSettingsChange() {
    if (_autoFlip) {
      if (_flipTimer == null) _startFlipTimer();
    } else if (_flipTimer != null) {
      ctx.clearTimer(_flipTimer!);
      _flipTimer = null;
    }
    _draw();
  }

  void _fail(String msg) {
    _status = 'error';
    _error = msg;
    _draw();
  }

  // ---- 城市定位 ----
  //
  // 中国天气网 toy1 的返回是 JSONP 包装：([{"ref":"...~...~..."}])。
  // ref 用 ~ 分隔，第一个字段是城市码；结果里第一条通常是市级记录
  // （9 位 code）。Referer 必须有——不带的话 toy1 只回一个空的 "()"。
  Future<Map<String, String>?> _searchCity(String keyword) async {
    final u = 'https://toy1.weather.com.cn/search?cityname=$keyword';
    final r = await ctx.httpGetText(u, headers: {
      'Referer': 'https://www.weather.com.cn/',
    });
    if (r['ok'] != true) return null;
    final text = '${r['data']}';
    final m = RegExp(r'\[([\s\S]*)\]').firstMatch(text);
    if (m == null) return null;
    List<Object?> arr;
    try {
      arr = (jsonDecode('[${m.group(1)}]') as List).cast<Object?>();
    } catch (_) {
      return null;
    }
    for (final it in arr) {
      final ref = '${(it as Map)['ref'] ?? ''}'.split('~');
      // 9 位 = 市级。城市名取 ref[2]（中文名）
      if (ref.length > 2 && ref[0].length == 9) {
        return {
          'name': ref[2],
          'cityId': ref[0],
          'province': ref.length > 8 ? ref[8] : '',
        };
      }
    }
    return null;
  }

  /// 手填城市名的坐标：open-meteo geocoding，中英文都认
  Future<List<double>?> _searchCoord(String keyword) async {
    final u = 'https://geocoding-api.open-meteo.com/v1/search'
        '?name=$keyword&count=1&language=zh&format=json';
    final r = await ctx.httpGetJSON(u);
    if (r['ok'] != true) return null;
    final data = r['data'];
    if (data is! Map) return null;
    final results = (data['results'] as List?)?.cast<Object?>() ?? const [];
    if (results.isEmpty) return null;
    final hit = results.first as Map;
    return [
      (hit['latitude'] as num).toDouble(),
      (hit['longitude'] as num).toDouble()
    ];
  }

  // ---- 自动定位 ----
  //
  // 免费 IP 定位没有一家能长期独扛：ipapi.co 额度用尽、或者看到脚本 UA 时
  // 直接回 403（用户截图里那句"自动定位失败：HTTP 403"就是它），ipwho.is
  // 偶尔抽风。所以排一张降级表依次试，谁先给出坐标就用谁——宁可多花一次
  // 请求，也别让整张天气卡因为一家服务罢工而歇菜。
  static const List<String> _ipSources = [
    'https://ipapi.co/json/',
    'https://ipwho.is/',
    'http://ip-api.com/json/?fields=status,lat,lon,city&lang=zh-CN',
  ];

  /// 免费定位服务普遍把"非浏览器 UA"当爬虫拒之门外，这一条比换源还关键。
  static const Map<String, Object?> _ipHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 依次问各家定位服务，返回第一个能凑齐 {纬度, 经度, 城市名} 的结果。
  Future<({double lat, double lon, String city})?> _ipLocate() async {
    for (final u in _ipSources) {
      Map<String, Object?> r;
      try {
        r = await ctx.httpGetJSON(u, headers: _ipHeaders);
      } catch (_) {
        continue;
      }
      if (r['ok'] != true) continue;
      final hit = _pickIp((r['data'] as Map?)?.cast<String, Object?>());
      if (hit != null) return hit;
    }
    return null;
  }

  /// 各家字段名不统一，这里一次对齐成同一种形状：
  /// ipapi.co / ipwho.is 用 latitude|longitude，ip-api 用 lat|lon。
  ({double lat, double lon, String city})? _pickIp(Map<String, Object?>? d) {
    if (d == null) return null;
    double? num2(Object? v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    final lat = num2(d['latitude'] ?? d['lat']);
    final lon = num2(d['longitude'] ?? d['lon']);
    // 城市名兜底：city 三家都有；ip-api 在拿不到市时才回 regionName（省名）
    final city = '${d['city'] ?? d['regionName'] ?? ''}'.trim();
    if (lat == null || lon == null || city.isEmpty) return null;
    return (lat: lat, lon: lon, city: city);
  }

  Future<_Loc?> _resolveLocation() async {
    final city = '${ctx.settings['city'] ?? ''}'.trim();
    if (city.isNotEmpty) {
      // 手填城市名：toy1 拿城市码，open-meteo 拿坐标
      final hit = await _searchCity(Uri.encodeComponent(city));
      if (hit == null) {
        _fail('没找到城市「$city」');
        return null;
      }
      final coord = await _searchCoord(Uri.encodeComponent(city));
      if (coord == null) {
        _fail('城市「$city」坐标解析失败');
        return null;
      }
      return _Loc(hit['name']!, hit['cityId']!, coord[0], coord[1]);
    }
    // 自动定位：IP 归属地拿经纬度和城市名，再拿城市名去天气网换城市码
    final d = await _ipLocate();
    if (d == null) {
      _fail('自动定位失败（可在设置里手填城市）');
      return null;
    }
    final hit = await _searchCity(Uri.encodeComponent(d.city));
    if (hit == null) {
      _fail('定位到的「${d.city}」查不到城市码，请手填城市');
      return null;
    }
    return _Loc(hit['name']!, hit['cityId']!, d.lat, d.lon);
  }

  Future<void> _load() async {
    final loc = await _resolveLocation();
    if (loc == null) return;
    _loc = loc;
    // v3 主接口。appKey/sign 是逆向出的固定常量。
    final u = 'https://weatherapi.market.xiaomi.com/wtr-v3/weather/all'
        '?latitude=${loc.lat}&longitude=${loc.lon}'
        '&locationKey=${Uri.encodeComponent('weathercn:${loc.cityId}')}'
        '&days=5&appKey=weather20151024&sign=zUFJoAR2ZVrDy1vF3D07'
        '&isGlobal=false&locale=zh_cn';
    final r = await ctx.httpGetJSON(u);
    if (r['ok'] != true) {
      _fail('获取天气失败：${r['error']}');
      return;
    }
    final data = (r['data'] as Map?)?.cast<String, Object?>();
    if (data == null || data['current'] == null || data['forecastDaily'] == null) {
      _fail('天气数据不完整');
      return;
    }
    _data = data;
    _status = 'ok';
    _error = '';
    _face = 'f';
    ctx.storageSetLocal('cache', {'data': data, 'loc': _locMap()});
    _draw();
    _startFlipTimer();
  }

  Map<String, Object?> _locMap() => {
        'name': _loc!.name,
        'cityId': _loc!.cityId,
        'lat': _loc!.lat,
        'lon': _loc!.lon,
      };

  // ---- 小工具 ----

  /// 沿路径取嵌套字段，缺 anywhere 返回 null
  static Object? _nest(Map<String, Object?> m, List<String> path) {
    Object? cur = m;
    for (final k in path) {
      if (cur is! Map) return null;
      cur = cur[k];
    }
    return cur;
  }

  static Object? _from(Object? item) => item is Map ? item['from'] : null;
  static Object? _to(Object? item) => item is Map ? item['to'] : null;

  /// JS 的 Math.round 能吃数字字符串；Dart 需要先归一成 num
  static num? _numOf(Object? v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse('$v');
  }

  static num _asNum(Object? v) => _numOf(v) ?? 0;
}
