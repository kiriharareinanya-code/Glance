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

  // ---- 前脸：当前天气 + 5 天预报 ----
  Map<String, Object?> _buildFront(
      Map<String, Object?> data, _Loc loc, int rows) {
    final cur = (data['current'] as Map?)?.cast<String, Object?>() ?? {};
    final fd = (data['forecastDaily'] as Map?)?.cast<String, Object?>() ?? {};
    final compact = rows <= 2;
    final curCode = _codeOf(cur['weather']);
    final kids = <Map<String, Object?>>[
      {
        't': 'row',
        'main': 'between',
        'cross': 'start',
        'children': [
          {
            't': 'col',
            'gap': 3,
            'children': [
              {
                't': 'row',
                'gap': 6,
                'cross': 'center',
                'children': [
                  {'t': 'box', 'w': 4, 'h': 4, 'radius': 2, 'bg': '#7CC7FF'},
                  {'t': 'text', 'v': loc.name, 'size': 13, 'opacity': 0.55},
                ]
              },
              {
                't': 'row',
                'cross': 'start',
                'children': [
                  {
                    't': 'text',
                    'v': '${_nest(cur, ['temperature', 'value']) ?? '--'}',
                    'size': 48,
                    'weight': 300,
                    'lh': 1.0,
                    'mono': true
                  },
                  {
                    't': 'box',
                    'pad': [4, 0, 0, 2],
                    'child': {
                      't': 'text',
                      'v': '°',
                      'size': 22,
                      'weight': 300,
                      'opacity': 0.5
                    }
                  },
                ]
              },
            ]
          },
          {
            't': 'col',
            'cross': 'end',
            'gap': 6,
            'children': [
              {
                't': 'box',
                'w': 40,
                'h': 40,
                'radius': 20,
                'center': true,
                'bg': '${_iconColorOf(curCode)}26',
                'child': {
                  't': 'icon',
                  'v': _iconOf(curCode),
                  'size': 22,
                  'color': _iconColorOf(curCode)
                }
              },
              {'t': 'text', 'v': _descOf(curCode), 'size': 12, 'opacity': 0.65},
            ]
          },
        ]
      },
    ];

    // 当前详情徽章：体感 / 湿度 / 风速 / UV
    final detail = <Map<String, Object?>>[];
    final feels = _nest(cur, ['feelsLike', 'value']);
    if (feels != null) {
      detail.add({
        'icon': 'thermostat',
        'v': '体感 $feels°',
      });
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
      kids.add({
        't': 'row',
        'gap': 6,
        'children': [
          for (final it in detail)
            {
              't': 'box',
              'pad': [3, 8],
              'radius': 9,
              'bg': '#FFFFFF12',
              'child': {
                't': 'row',
                'gap': 4,
                'cross': 'center',
                'children': [
                  {
                    't': 'icon',
                    'v': it['icon'],
                    'size': 11,
                    'opacity': 0.55
                  },
                  {'t': 'text', 'v': it['v'], 'size': 11, 'opacity': 0.75},
                ]
              }
            }
        ]
      });
    }

    // 5 天预报：forecastDaily index 0 = 今天，星期用本地日期加下标推算
    final days = <Map<String, Object?>>[];
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
      final cellKids = <Map<String, Object?>>[
        {'t': 'text', 'v': label, 'size': 11, 'opacity': 0.45, 'align': 'center'},
        {'t': 'icon', 'v': _iconOf(wcode), 'size': 15, 'color': _iconColorOf(wcode)},
      ];
      if (hi != null) {
        cellKids.add({
          't': 'text',
          'v': '${hi.round()}°',
          'size': 12,
          'align': 'center',
          'weight': 600
        });
        if (!compact && lo != null) {
          cellKids.add({
            't': 'text',
            'v': '${lo.round()}°',
            'size': 11,
            'align': 'center',
            'opacity': 0.4
          });
        }
      }
      days.add({
        't': 'box',
        'pad': compact ? [2, 2] : [6, 2],
        'radius': 10,
        'bg': i == 0 ? '#FFFFFF1C' : '#FFFFFF0A',
        'border': i == 0 ? '#FFFFFF2E' : null,
        'child': {
          't': 'col',
          'gap': 4,
          'cross': 'center',
          'children': cellKids
        }
      });
    }
    if (days.isNotEmpty) {
      kids.add({'t': 'divider'});
      kids.add({'t': 'grid', 'cols': 5, 'gap': 4, 'children': days});
    }
    // h + clip 兜底：钉死可用高度，不会顶穿卡片
    return {
      't': 'box',
      'h': ctx.size.height,
      'clip': true,
      'child': {'t': 'col', 'gap': 8, 'children': kids}
    };
  }

  // ---- 后脸：12 小时逐时 + 空气质量/UV 环境指数 ----
  Map<String, Object?> _buildBack(Map<String, Object?> data, int rows) {
    final fh = (data['forecastHourly'] as Map?)?.cast<String, Object?>() ?? {};
    final aqi = (data['aqi'] as Map?)?.cast<String, Object?>() ?? {};
    final compact = rows <= 2;
    final kids = <Map<String, Object?>>[];

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
      final cols = <Map<String, Object?>>[];
      const hn = 12;
      for (var k = 0; k < hn && k < hTemps.length; k++) {
        final hd = startDate.add(Duration(hours: k));
        final hc = _codeOf(k < hWtrs.length ? hWtrs[k] : null);
        cols.add({
          't': 'col',
          'gap': 3,
          'cross': 'center',
          'children': [
            {'t': 'text', 'v': '${hd.hour}时', 'size': 10, 'opacity': 0.45},
            {'t': 'icon', 'v': _iconOf(hc), 'size': 14, 'color': _iconColorOf(hc)},
            {
              't': 'text',
              'v': '${_asNum(hTemps[k]).round()}°',
              'size': 11.5,
              'weight': 600,
              'align': 'center'
            },
          ]
        });
      }
      kids.add({
        't': 'text',
        'v': '未来 ${cols.length} 小时',
        'size': 11,
        'opacity': 0.45
      });
      // 6 列：12 个小时格子排成 2 行 x 6 列
      kids.add({'t': 'grid', 'cols': 6, 'gap': 4, 'children': cols});
      if (!compact) kids.add({'t': 'divider'});
    }

    // 环境指数：AQI 数值 + 一句话建议 + UV 等级
    {
      final env = <String>[];
      if (aqi['aqi'] != null && '${aqi['aqi']}' != '') env.add('AQI ${aqi['aqi']}');
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
        if (!compact) kids.add({'t': 'divider'});
        kids.add({
          't': 'col',
          'gap': 4,
          'children': [
            for (final s in env)
              {'t': 'text', 'v': s, 'size': 11, 'opacity': 0.5}
          ]
        });
      }
    }

    return {
      't': 'box',
      'h': ctx.size.height,
      'clip': true,
      'child': {'t': 'col', 'gap': 8, 'children': kids}
    };
  }

  // ---- 主渲染 ----
  void _draw() {
    if (_status == 'loading') {
      ctx.render({
        't': 'col',
        'main': 'center',
        'children': [
          {'t': 'text', 'v': '正在获取天气…', 'size': 12, 'opacity': 0.45}
        ]
      });
      return;
    }
    if (_status == 'error') {
      final retry = ctx.on((_) {
        _status = 'loading';
        _draw();
        _load();
      });
      ctx.render({
        't': 'col',
        'gap': 10,
        'main': 'center',
        'children': [
          {
            't': 'row',
            'gap': 6,
            'cross': 'center',
            'children': [
              {'t': 'box', 'w': 4, 'h': 4, 'radius': 2, 'bg': '#FF9E7D'},
              {'t': 'text', 'v': '天气不可用', 'size': 12, 'weight': 600},
            ]
          },
          {
            't': 'text',
            'v': _error,
            'size': 10.5,
            'opacity': 0.5,
            'maxLines': 3
          },
          {
            't': 'tap',
            'id': retry,
            'child': {
              't': 'box',
              'pad': [5, 12],
              'radius': 8,
              'bg': '#FFFFFF14',
              'child': {'t': 'text', 'v': '重试', 'size': 11}
            }
          },
        ]
      });
      return;
    }

    final flipId = ctx.on((_) {
      _face = _face == 'f' ? 'b' : 'f';
      _draw();
    });

    ctx.render({
      't': 'tap',
      'id': flipId,
      'child': {
        't': 'flip',
        'flipKey': _face,
        'children': [
          _buildFront(_data!, _loc!, ctx.grid.rows),
          _buildBack(_data!, ctx.grid.rows),
        ]
      }
    });
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
    // 自动定位：ipapi 拿经纬度和城市名（英文/拼音），再用拼音搜城市码
    final r = await ctx.httpGetJSON('https://ipapi.co/json/');
    if (r['ok'] != true) {
      _fail('自动定位失败：${r['error']}（可在设置里手填城市）');
      return null;
    }
    final d = (r['data'] as Map?)?.cast<String, Object?>() ?? {};
    if (d['latitude'] is! num) {
      _fail('定位没返回坐标，请手填城市');
      return null;
    }
    final cityName = '${d['city'] ?? ''}';
    if (cityName.isEmpty) {
      _fail('定位没拿到城市名，请手填城市');
      return null;
    }
    final hit = await _searchCity(Uri.encodeComponent(cityName));
    if (hit == null) {
      _fail('定位到的「$cityName」查不到城市码，请手填城市');
      return null;
    }
    return _Loc(hit['name']!, hit['cityId']!,
        (d['latitude'] as num).toDouble(), (d['longitude'] as num).toDouble());
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
