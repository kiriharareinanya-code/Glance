/// 内置组件的静态描述。
///
/// 取代旧的 plugin.json 清单解析：组件已是编译进核心的 Dart 实现，
/// "描述"也顺势变成常量。settings 的 map 形状与旧 manifest 完全一致
/// （key/type/label/desc/default/min/max/step/options），面板的设置
/// 控件按同样的规则消费。
library;

class BuiltinSpec {
  const BuiltinSpec({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.icon,
    required this.sizes,
    required this.defaultSize,
    this.settings = const [],
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String icon;
  final List<String> sizes;
  final String defaultSize;

  /// 设置项描述，见面板的设置控件渲染
  final List<Map<String, Object?>> settings;

  /// 每个设置项的默认值
  Map<String, Object?> defaultSettings() => {
        for (final f in settings) f['key'] as String: f['default'],
      };
}

const List<BuiltinSpec> kBuiltinSpecs = [
  BuiltinSpec(
    id: 'clock',
    name: '时钟',
    version: '2.0.0',
    description: '数字时钟与日期',
    icon: '🕐',
    sizes: ['2x2', '3x2', '3x3', '4x2'],
    defaultSize: '2x2',
    settings: [
      {'key': 'seconds', 'type': 'boolean', 'label': '显示秒', 'default': false},
      {'key': 'hour24', 'type': 'boolean', 'label': '24 小时制', 'default': true},
    ],
  ),
  BuiltinSpec(
    id: 'weather',
    name: '天气',
    version: '2.0.0',
    description: 'Open-Meteo，无需 API key',
    icon: '☀',
    sizes: ['3x2', '3x3', '4x2', '4x3'],
    defaultSize: '3x2',
    settings: [
      {
        'key': 'city',
        'type': 'text',
        'label': '城市',
        'desc': '留空则按 IP 自动定位',
        'default': ''
      },
      {
        'key': 'refreshMin',
        'type': 'number',
        'label': '刷新间隔（分钟）',
        'min': 5,
        'max': 180,
        'step': 5,
        'default': 30
      },
      {
        'key': 'flipAuto',
        'type': 'boolean',
        'label': '自动翻页',
        'desc': '每 30 秒在实况与逐时预报之间翻一次；关掉后只剩点击手动翻',
        'default': true
      },
    ],
  ),
  BuiltinSpec(
    id: 'todo',
    name: '待办',
    version: '2.0.0',
    description: '清单，数据存在本地',
    icon: '✓',
    sizes: ['2x3', '3x3', '3x4', '4x4'],
    defaultSize: '2x3',
    settings: [
      {'key': 'hideDone', 'type': 'boolean', 'label': '隐藏已完成', 'default': false},
    ],
  ),
  BuiltinSpec(
    id: 'calendar',
    name: '日历',
    version: '3.0.0',
    description: '月历，带农历、二十四节气与节假日',
    icon: '📅',
    sizes: ['3x3', '4x3', '4x4', '5x4', '5x5'],
    defaultSize: '4x4',
    settings: [
      {'key': 'lunar', 'type': 'boolean', 'label': '显示农历', 'default': true},
      {
        'key': 'festival',
        'type': 'boolean',
        'label': '显示节假日',
        'desc': '节日与二十四节气会顶替农历日显示',
        'default': true
      },
      {'key': 'mondayFirst', 'type': 'boolean', 'label': '周一作为一周开始', 'default': true},
    ],
  ),
  BuiltinSpec(
    id: 'lyrics',
    name: '歌词',
    version: '1.0.0',
    description: '读系统正在播放的音乐，显示封面、进度与滚动歌词',
    icon: '🎵',
    sizes: ['4x2', '5x2', '6x2', '5x3', '6x3', '6x4', '7x4', '8x4'],
    defaultSize: '5x3',
    settings: [
      {
        'key': 'source',
        'type': 'select',
        'label': '歌词来源',
        'desc': '网易云中文歌覆盖更好；LRCLIB 是开放歌词库，欧美歌更全',
        'options': [
          {'value': 'auto', 'label': '网易云优先，找不到再试 LRCLIB'},
          {'value': 'netease', 'label': '只用网易云'},
          {'value': 'lrclib', 'label': '只用 LRCLIB'},
        ],
        'default': 'auto'
      },
      {
        'key': 'trans',
        'type': 'boolean',
        'label': '显示翻译',
        'desc': '只有网易云有翻译，且不是每首歌都有',
        'default': false
      },
      {
        'key': 'credits',
        'type': 'boolean',
        'label': '显示制作人员名单',
        'desc': '网易云歌词开头那几行「作词/作曲/编曲」，关掉更清爽',
        'default': false
      },
    ],
  ),
];

/// 按 id 查找；找不到返回 null（放置过的组件不可能出现这种情况，
/// 除非配置来自更新的版本）
BuiltinSpec? builtinSpecById(String id) {
  for (final s in kBuiltinSpecs) {
    if (s.id == id) return s;
  }
  return null;
}

/// 全部内置组件的描述（面板"组件库"页按 name 排序展示）
List<BuiltinSpec> builtinCatalog() {
  final list = List<BuiltinSpec>.from(kBuiltinSpecs)
    ..sort((a, b) => a.name.compareTo(b.name));
  return list;
}
