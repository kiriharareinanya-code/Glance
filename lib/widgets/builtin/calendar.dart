/// 内置组件：日历。月视图，每格上面公历、下面农历/节气/节日。
/// 农历与节气的算法在 lunar.dart。
library;

import '../catalog.dart';
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

    // 固定 6 行 42 格：月份切换时高度不跳变
    final cells = <Map<String, Object?>>[];
    for (var i = 0; i < 42; i++) {
      final d = DateTime(_viewYear, _viewMonth + 1, 1 - lead + i);
      final inMonth = d.month == _viewMonth + 1;
      final col = i % 7;
      cells.add(_cell(d, inMonth, weekendCols.contains(col), showLunar, showFest));
    }

    final headCells = [
      for (var i = 0; i < heads.length; i++)
        {
          't': 'text',
          'v': heads[i],
          'size': 13,
          'align': 'center',
          'weight': 600,
          'spacing': 1,
          'opacity': weekendCols.contains(i) ? 0.8 : 0.62,
        }
    ];

    final prev = ctx.on((_) {
      _viewMonth--;
      if (_viewMonth < 0) {
        _viewMonth = 11;
        _viewYear--;
      }
      draw();
    });
    final next = ctx.on((_) {
      _viewMonth++;
      if (_viewMonth > 11) {
        _viewMonth = 0;
        _viewYear++;
      }
      draw();
    });
    final reset = ctx.on((_) {
      _viewYear = _today.year;
      _viewMonth = _today.month - 1;
      draw();
    });

    final offMonth = !(_viewYear == _today.year && _viewMonth == _today.month - 1);

    // key 变化时宿主做交叉淡入。只在真正换月时变，不会每次重绘都动画。
    final body = {
      't': 'col',
      'gap': 10,
      'key': '$_viewYear-$_viewMonth',
      'children': [
        {
          't': 'row',
          'main': 'between',
          'cross': 'center',
          'children': [
            {
              't': 'tap',
              'id': reset,
              'child': {
                't': 'row',
                'gap': 6,
                'cross': 'center',
                'children': [
                  {
                    't': 'text',
                    'v': '$_viewYear年${_viewMonth + 1}月',
                    'size': 17,
                    'weight': 600
                  },
                  offMonth
                      ? {
                          't': 'box',
                          'pad': [2, 7],
                          'radius': 5,
                          'bg': '#FFFFFF14',
                          'child': {
                            't': 'text',
                            'v': '今天',
                            'size': 10,
                            'opacity': 0.78
                          }
                        }
                      : {'t': 'box'},
                ]
              }
            },
            {
              't': 'row',
              'gap': 2,
              'children': [
                {
                  't': 'tap',
                  'id': prev,
                  'child': {
                    't': 'box',
                    'w': 26,
                    'h': 22,
                    'center': true,
                    'child': {
                      't': 'icon',
                      'v': 'up',
                      'size': 20,
                      'color': '#FFFFFF66'
                    }
                  }
                },
                {
                  't': 'tap',
                  'id': next,
                  'child': {
                    't': 'box',
                    'w': 26,
                    'h': 22,
                    'center': true,
                    'child': {
                      't': 'icon',
                      'v': 'down',
                      'size': 20,
                      'color': '#FFFFFF66'
                    }
                  }
                },
              ]
            },
          ]
        },
        {'t': 'grid', 'cols': 7, 'gap': 0, 'children': headCells},
        {
          't': 'flex',
          'f': 1,
          'child': {
            't': 'grid',
            'cols': 7,
            'gap': 5,
            'fill': true,
            'children': cells
          }
        },
      ]
    };

    // 尺寸分档：格子越多，能承载的信息越多。
    // 小档只放月历；中档加今日一行；大档在下方展开今日详情与近期节气/节日。
    final rows = ctx.grid.rows;
    if (rows >= 4) (body['children'] as List)[1] = _todayStrip();
    if (rows >= 5) {
      (body['children'] as List).addAll([
        {'t': 'divider'},
        _upcoming(),
      ]);
    }

    ctx.render(body);
  }

  /// 今日一行：农历全称 + 干支生肖
  Map<String, Object?> _todayStrip() {
    final l = Lunar.fromSolar(_today.year, _today.month, _today.day);
    if (l == null) return {'t': 'box'};
    final parts = <Map<String, Object?>>[
      {
        't': 'box',
        'pad': [2, 7],
        'radius': 6,
        'bg': '#FFFFFF12',
        'child': {
          't': 'text',
          'v': '${l.monthText}${l.dayText}',
          'size': 12
        }
      },
      {'t': 'text', 'v': '${Lunar.ganzhi(l.y)}年', 'size': 12, 'opacity': 0.58},
      {'t': 'text', 'v': '属${Lunar.zodiac(l.y)}', 'size': 12, 'opacity': 0.58},
    ];
    final t = Lunar.termOf(_today.year, _today.month, _today.day);
    if (t != null) {
      parts.add({
        't': 'box',
        'pad': [2, 7],
        'radius': 6,
        'bg': '#8FD6A022',
        'child': {'t': 'text', 'v': '今日$t', 'size': 12, 'color': '#8FD6A0'}
      });
    }
    return {
      't': 'row',
      'gap': 8,
      'cross': 'center',
      'children': parts,
    };
  }

  /// 大尺寸：下一个节气 + 本月剩余的节日
  Map<String, Object?> _upcoming() {
    final y = _today.year;
    final m = _today.month;
    final d = _today.day;
    final items = <Map<String, Object?>>[];

    final nt = Lunar.nextTerm(y, m, d);
    if (nt != null) {
      items.add({
        't': 'row',
        'gap': 6,
        'cross': 'center',
        'children': [
          {'t': 'box', 'w': 4, 'h': 4, 'radius': 2, 'bg': '#8FD6A0'},
          {'t': 'text', 'v': nt.name, 'size': 12.5},
          {'t': 'text', 'v': '${nt.days} 天后', 'size': 11.5, 'opacity': 0.55},
        ]
      });
    }

    // 本月内今天之后的节日，最多列 3 条
    final daysInMonth = DateTime(y, m + 1, 0).day;
    var listed = 0;
    for (var i = d + 1; i <= daysInMonth && listed < 3; i++) {
      final l = Lunar.fromSolar(y, m, i);
      final f = l != null ? Lunar.festivalOf(y, m, i, l) : null;
      if (f == null) continue;
      items.add({
        't': 'row',
        'gap': 6,
        'cross': 'center',
        'children': [
          {
            't': 'box',
            'w': 4,
            'h': 4,
            'radius': 2,
            'bg': f.statutory ? '#FF8A6B' : '#FFFFFF55'
          },
          {
            't': 'text',
            'v': f.name,
            'size': 12.5,
            'color': f.statutory ? '#FF8A6B' : null
          },
          {'t': 'text', 'v': '$m月$i日', 'size': 11.5, 'opacity': 0.55},
        ]
      });
      listed++;
    }

    if (items.isEmpty) {
      items.add({
        't': 'text',
        'v': '本月没有更多节日了',
        'size': 11.5,
        'opacity': 0.42
      });
    }
    return {'t': 'col', 'gap': 6, 'children': items};
  }

  /// 一格：上面公历日，下面农历/节气/节日
  Map<String, Object?> _cell(
      DateTime d, bool inMonth, bool weekend, bool showLunar, bool showFest) {
    final y = d.year;
    final m = d.month;
    final day = d.day;
    final isToday = _today.year == y && _today.month == m && _today.day == day;

    final lunar = Lunar.fromSolar(y, m, day);
    final term = Lunar.termOf(y, m, day);
    final fest = lunar != null ? Lunar.festivalOf(y, m, day, lunar) : null;

    // 下行文字的优先级：节日 > 节气 > 初一显示月份 > 农历日
    var sub = '';
    String? subColor;
    if (showFest && fest != null) {
      sub = fest.name;
      subColor = fest.statutory ? _holiday : null;
    } else if (showFest && term != null) {
      sub = term;
      subColor = _term;
    } else if (showLunar && lunar != null) {
      sub = lunar.d == 1 ? lunar.monthText : lunar.dayText;
    }

    // 节日/节气所在格给一个淡的圆底，让它从一片数字里跳出来
    final marked = !isToday && inMonth && showFest && (fest != null || term != null);

    // 法定节假日：日期数字也用节日色
    final statutory = showFest && fest != null && fest.statutory;

    String? dayColor;
    var dayOpacity = 1.0;
    if (isToday) {
      dayColor = '#0B1116';
    } else if (!inMonth) {
      // 非本月：弱化但保持可辨认
      dayOpacity = 0.4;
    } else if (weekend || statutory) {
      dayColor = _holiday;
      dayOpacity = 1;
    }

    final inner = {
      't': 'col',
      'gap': 2,
      'cross': 'center',
      'main': 'center',
      'children': [
        {
          't': 'text',
          'v': '$day',
          'size': 17,
          'weight': isToday ? 800 : 600,
          'spacing': 0.3,
          'align': 'center',
          'color': dayColor,
          'opacity': dayOpacity
        },
        sub.isNotEmpty
            ? {
                't': 'text',
                'v': sub,
                'size': 11,
                'align': 'center',
                'maxLines': 1,
                'color': isToday ? '#0B1116' : subColor,
                'opacity': isToday ? 0.9 : (inMonth ? 0.72 : 0.32)
              }
            : {'t': 'box'},
      ]
    };

    return {
      't': 'row',
      'main': 'center',
      'children': [
        {
          't': 'box',
          'w': 38,
          'h': 38,
          'radius': 19,
          'center': true,
          'bg': isToday ? _accent : (marked ? '#FFFFFF18' : null),
          'child': inner
        }
      ]
    };
  }
}
