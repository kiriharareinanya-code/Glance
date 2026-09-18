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
/// 后脸：12 小时逐时预报 + 空气质量/UV 环境指数。每 8 秒自动翻转。
library;

import 'dart:convert';

import '../catalog.dart';
import '../kit.dart'
    show FlipSwap, NodeIcon, TapFeedback, nodeColor, nodeWeight, withGaps;
import 'package:flutter/material.dart';

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
        _startFlipTimer();
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

  /// 城市改了下次刷新生效
  @override
  void onSettingsChange() {}

  // ---- 前脸：当前天气 + 5 天预报（原生 Widget）----

  Widget _grid(
      {required int cols,
      required double gap,
      required bool fill,
      required List<Widget> kids}) {
    // 与旧 grid 节点逐行对应：fill 让各行均分可用高度（放在 flex 里
    // 不开这个的话，网格会缩在顶部，卡片放大后中间留一大块空白）。
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
    final kids = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: withGaps([
              Row(
                children: withGaps([
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        color: nodeColor('#7CC7FF'),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Text(loc.name, style: _ts(fg, size: 13, opacity: 0.55)),
                ], 6, horizontal: true),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_nest(cur, ['temperature', 'value']) ?? '--'}',
                      style: _ts(fg, size: 48, weight: 300, mono: true)),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, top: 4),
                    child: Text('°', style: _ts(fg, size: 22, weight: 300, opacity: 0.5)),
                  ),
                ],
              ),
            ], 3),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: withGaps([
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: nodeColor('${_iconColorOf(curCode)}26'),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: NodeIcon(
                      name: _iconOf(curCode),
                      size: 22,
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
      kids.add(Row(
        children: withGaps([
          for (final it in detail)
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              decoration: BoxDecoration(
                color: nodeColor('#FFFFFF12'),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
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
        ], 6, horizontal: true),
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
      return FlipSwap(flipKey: _face, front: front, back: back);
    }

    ctx.renderWidget(Builder(builder: (context) {
      final fg = DefaultTextStyle.of(context).style.color ?? Colors.white;
      return TapFeedback(
        animate: ctx.animate,
        onTap: () {
          _face = _face == 'f' ? 'b' : 'f';
          _draw();
        },
        child: body(fg),
      );
    }));
  }

  // ---- 翻转定时器 ----
  void _startFlipTimer() {
    if (_flipTimer != null) ctx.clearTimer(_flipTimer!);
    _flipTimer = ctx.interval(() {
      _face = _face == 'f' ? 'b' : 'f';
      _draw();
    }, 8000);
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
