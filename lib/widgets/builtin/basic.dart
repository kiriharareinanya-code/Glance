/// 内置组件：时钟与待办。
///
/// 从 assets/plugins/{clock,todo}/index.js 逐行移植为 Dart 实现，
/// 渲染树的结构、属性与刷新节奏与原 JS 版本完全一致。
library;

import 'dart:math';

import '../catalog.dart';

// ---------------------------------------------------------------------------
// 时钟：每秒重绘一次。
//
// 数字的切换动效走"机械翻页"（trans: 'flip'，实现在 flip_transition.dart）：
// 上半页翻下去、下半页翻上来，时分秒三位各自独立翻，节奏一致。日期和星期
// 不是数字，保持交叉淡入（trans: true）。
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

  @override
  void mount() {
    draw();
    _timer = ctx.interval(draw, 1000);
    ctx.onCleanup(() => ctx.clearTimer(_timer!));
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
    final accent = (ctx.themeAccent) ?? '#7CC7FF';

    // 日期行装进一个用主题色打底的圆角胶囊（Material 3 Expressive 的
    // tonal chip 手法），不再是两段裸文字。
    final dateRow = {
      't': 'box',
      'pad': [5, 10],
      'radius': 14,
      'bg': '$accent${'1F'}',
      'child': {
        't': 'row',
        'gap': 7,
        'cross': 'center',
        'children': [
          {'t': 'box', 'w': 5, 'h': 5, 'radius': 3, 'bg': accent},
          {
            't': 'text',
            'font': 'TsukushiBMaru',
            'v': '${now.month} 月 ${now.day} 日',
            'size': 13,
            'opacity': 0.7,
            'trans': true
          },
          {
            't': 'text',
            'font': 'TsukushiBMaru',
            'v': week,
            'size': 13,
            'opacity': 0.7,
            'trans': true
          },
        ]
      }
    };

    final stacked = ctx.grid.rows >= 3;

    if (stacked) {
      // 140：两行堆叠总高实测 238px，3x3 卡片能给的内容高度约 296px，
      // 扣掉日期行和间距还有 30px+ 的余量。
      const stackSize = 140;
      final minuteRow = [
        {
          't': 'text',
          'font': 'TsukushiBMaru',
          'v': _two(now.minute),
          'size': stackSize,
          'weight': 300,
          'mono': true,
          'lh': 0.85,
          'color': accent,
          'trans': 'flip'
        }
      ];
      if (ctx.settings['seconds'] == true) {
        minuteRow.add({
          't': 'box',
          'pad': [0, 0, 0, 8],
          'child': {
            't': 'text',
            'font': 'TsukushiBMaru',
            'v': _two(now.second),
            'size': 20,
            'weight': 400,
            'mono': true,
            'opacity': 0.4,
            'trans': 'flip'
          }
        });
      }
      if (suffix.isNotEmpty) {
        minuteRow.add({
          't': 'box',
          'pad': [0, 0, 0, 10],
          'child': {
            't': 'text',
            'font': 'TsukushiBMaru',
            'v': suffix,
            'size': 16,
            'weight': 600,
            'opacity': 0.4
          }
        });
      }
      ctx.render({
        't': 'col',
        'main': 'center',
        'cross': 'start',
        'gap': 10,
        'children': [
          {
            't': 'text',
            'font': 'TsukushiBMaru',
            'v': _two(h),
            'size': stackSize,
            'weight': 300,
            'mono': true,
            'lh': 0.85,
            'color': accent,
            'trans': 'flip'
          },
          {'t': 'row', 'cross': 'end', 'children': minuteRow},
          dateRow
        ]
      });
      return;
    }

    final big = ctx.grid.cols >= 3 ? 58 : 44;
    // 时:分拆成三个独立节点：小时粗体+默认色，冒号 0.35 透明度弱化成分隔符，
    // 分钟用细体 + ACCENT 上色收尾。
    final timeRow = [
      {
        't': 'text',
        'font': 'TsukushiBMaru',
        'v': _two(h),
        'size': big,
        'weight': 900,
        'mono': true,
        'lh': 1.0,
        'color': accent,
        'trans': 'flip'
      },
      {
        't': 'box',
        'pad': [0, 2],
        'child': {
          't': 'text',
          'font': 'TsukushiBMaru',
          'v': ':',
          'size': big,
          'weight': 300,
          'opacity': 0.35,
          'mono': true,
          'lh': 1.0
        }
      },
      {
        't': 'text',
        'font': 'TsukushiBMaru',
        'v': _two(now.minute),
        'size': big,
        'weight': 400,
        'mono': true,
        'lh': 1.0,
        'color': accent,
        'trans': 'flip'
      }
    ];
    if (ctx.settings['seconds'] == true) {
      timeRow.add({
        't': 'box',
        'pad': [0, 0, 0, 4],
        'child': {
          't': 'text',
          'font': 'TsukushiBMaru',
          'v': _two(now.second),
          'size': (big * 0.42).round(),
          'weight': 400,
          'mono': true,
          'opacity': 0.45,
          'trans': 'flip'
        }
      });
    }
    if (suffix.isNotEmpty) {
      timeRow.add({
        't': 'box',
        'pad': [0, 0, 0, 5],
        'child': {
          't': 'text',
          'font': 'TsukushiBMaru',
          'v': suffix,
          'size': (big * 0.3).round(),
          'weight': 600,
          'opacity': 0.4
        }
      });
    }

    ctx.render({
      't': 'col',
      'main': 'center',
      'cross': 'start',
      'gap': 6,
      'children': [
        {'t': 'row', 'cross': 'end', 'children': timeRow},
        dateRow
      ]
    });
  }
}

// ---------------------------------------------------------------------------
// 待办：清单，数据按实例存（每张卡片一份）。
// ---------------------------------------------------------------------------

class TodoWidget extends BuiltinController {
  TodoWidget(super.ctx);

  List<Map<String, Object?>> items = [];

  void _save() => ctx.storageSetLocal('items', items);

  Map<String, Object?> _row(Map<String, Object?> item) {
    final toggle = ctx.on((_) {
      item['done'] = !(item['done'] == true);
      _save();
      draw();
    });
    final remove = ctx.on((_) {
      items = items
          .where((x) => x['id'] != item['id'])
          .map((e) => e)
          .toList();
      _save();
      draw();
    });
    final done = item['done'] == true;
    return {
      't': 'box',
      'pad': [5, 6],
      'radius': 8,
      'bg': done ? '#FFFFFF08' : '#FFFFFF12',
      'child': {
        't': 'row',
        'gap': 8,
        'cross': 'center',
        'children': [
          {
            't': 'tap',
            'id': toggle,
            'child': {
              't': 'icon',
              'v': done ? 'check_circle' : 'circle',
              'size': 16,
              'color': done ? '#7CE38B' : '#FF7A7A'
            }
          },
          {
            't': 'flex',
            'f': 1,
            'child': {
              't': 'text',
              'v': item['text'],
              'size': 13,
              'maxLines': 1,
              'strike': done,
              'opacity': done ? 0.4 : 0.95
            }
          },
          {
            't': 'tap',
            'id': remove,
            'child': {
              't': 'box',
              'w': 18,
              'h': 18,
              'radius': 9,
              'center': true,
              'bg': '#D9000000',
              'child': {
                't': 'icon',
                'v': 'close',
                'size': 12,
                'color': '#FFFFFF'
              }
            }
          },
        ]
      }
    };
  }

  void draw() {
    final hideDone = ctx.settings['hideDone'] == true;
    final shown = hideDone
        ? items.where((i) => i['done'] != true).map((e) => e).toList()
        : items;
    final left = items.where((i) => i['done'] != true).length;
    final rows = [for (final item in shown) _row(item)];

    final submit = ctx.on((p) {
      final text = '${p['value'] ?? ''}'.trim();
      if (text.isEmpty) return;
      items.add({
        'id':
            '${DateTime.now().millisecondsSinceEpoch}-${Random().nextDouble().toStringAsFixed(6).substring(2, 6)}',
        'text': text,
        'done': false,
      });
      _save();
      draw();
    });

    ctx.render({
      't': 'col',
      'gap': 10,
      'children': [
        {
          't': 'row',
          'main': 'between',
          'cross': 'center',
          'children': [
            {
              't': 'row',
              'gap': 7,
              'cross': 'center',
              'children': [
                {
                  't': 'box',
                  'w': 4,
                  'h': 4,
                  'radius': 2,
                  'bg': '#7CE38B'
                },
                {'t': 'text', 'v': '待办', 'size': 13, 'weight': 600},
              ]
            },
            {
              't': 'box',
              'pad': [2, 7],
              'radius': 8,
              'bg': '#FFFFFF12',
              'child': {
                't': 'text',
                'v': left > 0 ? '$left 项未完成' : '全部完成',
                'size': 11,
                'opacity': 0.6
              }
            },
          ]
        },
        {
          't': 'input',
          'id': 'new',
          'value': '',
          'placeholder': '添加一项，回车确认',
          'submit': submit,
        },
        {
          't': 'flex',
          'f': 1,
          'child': {
            't': 'scroll',
            'child': {
              't': 'col',
              'gap': 5,
              'children': rows.isNotEmpty
                  ? rows
                  : [
                      {
                        't': 'box',
                        'pad': [10, 0],
                        'child': {
                          't': 'text',
                          'v': '还没有待办',
                          'size': 11,
                          'opacity': 0.28
                        }
                      }
                    ]
            }
          }
        },
      ]
    });
  }

  @override
  void mount() {
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

  /// 勾选项变化下次绘制生效
  @override
  void onSettingsChange() {
    if (ctx.tree.value != null) draw();
  }
}
