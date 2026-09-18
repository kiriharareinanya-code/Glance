/// 全局设置的 schema：**单一事实来源**。
///
/// 面板（WinUI3 原生）不硬编码任何一个设置项——它调 `settings.schema` 拿到
/// 这张表，按 type 渲染控件，按 key 读写值。和插件自己的 settings 是同一套
/// 思路（见 plugin_api.dart），所以"加一个全局设置"= 在这里加一行。
///
/// 每个字段有三部分：
///   - 描述（key/type/label/desc/范围/选项）→ 给面板
///   - [get] / [set] → 给核心读写真实的 [AppSettings]
///
/// 这样"描述"和"实现"不会漂移：加字段时编译器会强制你把读写补上。
library;

import '../model/settings.dart';

/// 面板认识的控件类型（两侧约定，见 docs/panel-protocol.md）。
/// `color` 是给原生面板新增的：Flutter 版面板当年是自己画的取色器。
enum SettingType { boolean, number, text, select, color }

/// 一个全局设置项。
class SettingField {
  const SettingField({
    required this.key,
    required this.type,
    required this.label,
    required this.group,
    required this.get,
    required this.set,
    this.desc,
    this.min,
    this.max,
    this.step,
    this.options = const [],
  });

  final String key;
  final SettingType type;
  final String label;

  /// 面板上的分组（页签 / 卡片分组）。见 [kSettingGroupTitles]。
  final String group;
  final String? desc;

  final num? min;
  final num? max;
  final num? step;

  /// select 的选项：[{value, label}]
  final List<Map<String, Object?>> options;

  final Object? Function(AppSettings s) get;
  final void Function(AppSettings s, Object? v) set;

  /// 给面板的描述（不含闭包，可 JSON 化）。
  Map<String, Object?> describe(AppSettings s) => {
        'key': key,
        'type': type.name,
        'label': label,
        'group': group,
        if (desc != null) 'desc': desc,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
        if (options.isNotEmpty) 'options': options,
        'value': get(s),
      };
}

/// 分组标题（面板按这个顺序出页签 / 卡片）。
const Map<String, String> kSettingGroupTitles = {
  'appearance': '外观',
  'layout': '布局',
  'behavior': '行为',
  'update': '更新',
};

String _hex(int argb) =>
    '#${argb.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

int _argb(Object? v) {
  if (v is num) return v.toInt();
  final s = '${v ?? ''}'.replaceFirst('#', '');
  if (s.isEmpty) return 0xFF2A2A2E;
  return int.tryParse(s, radix: 16) != null
      ? (s.length == 6 ? 0xFF000000 | int.parse(s, radix: 16) : int.parse(s, radix: 16))
      : 0xFF2A2A2E;
}

num _num(Object? v, num fallback) => v is num ? v : (num.tryParse('$v') ?? fallback);

/// 全局设置的完整表。
const List<SettingField> kSettingFields = [
  // —— 外观 ——
  SettingField(
    key: 'cardColor',
    type: SettingType.color,
    label: '卡片底色',
    group: 'appearance',
    desc: '不透明模式下卡片的填充色',
    get: _getCardColor,
    set: _setCardColor,
  ),
  SettingField(
    key: 'cardRadius',
    type: SettingType.number,
    label: '圆角半径',
    group: 'appearance',
    desc: '必须与命中区半径一致，否则视觉与输入错位',
    min: 0,
    max: 60,
    step: 1,
    get: _getCardRadius,
    set: _setCardRadius,
  ),
  SettingField(
    key: 'material',
    type: SettingType.select,
    label: '卡片材质',
    group: 'appearance',
    options: [
      {'value': 'opaque', 'label': '不透明'},
      {'value': 'glass', 'label': '毛玻璃'},
    ],
    get: _getMaterial,
    set: _setMaterial,
  ),
  SettingField(
    key: 'theme',
    type: SettingType.select,
    label: '深浅色',
    group: 'appearance',
    options: [
      {'value': 'auto', 'label': '跟随系统'},
      {'value': 'light', 'label': '浅色'},
      {'value': 'dark', 'label': '深色'},
    ],
    get: _getTheme,
    set: _setTheme,
  ),
  SettingField(
    key: 'glassTint',
    type: SettingType.number,
    label: '毛玻璃浓度',
    group: 'appearance',
    min: 0,
    max: 1,
    step: 0.05,
    get: _getGlassTint,
    set: _setGlassTint,
  ),
  SettingField(
    key: 'glassBlur',
    type: SettingType.number,
    label: '毛玻璃模糊',
    group: 'appearance',
    min: 0,
    max: 40,
    step: 1,
    get: _getGlassBlur,
    set: _setGlassBlur,
  ),
  SettingField(
    key: 'autoColorFromWallpaper',
    type: SettingType.boolean,
    label: '从壁纸取强调色',
    group: 'appearance',
    get: _getAutoColor,
    set: _setAutoColor,
  ),
  SettingField(
    key: 'autoForegroundFromWallpaper',
    type: SettingType.boolean,
    label: '文字颜色也从壁纸取',
    group: 'appearance',
    get: _getAutoFg,
    set: _setAutoFg,
  ),

  // —— 布局 ——
  SettingField(
    key: 'gridCell',
    type: SettingType.number,
    label: '网格单元',
    group: 'layout',
    desc: '卡片尺寸按格数乘以这个值',
    min: 40,
    max: 320,
    step: 2,
    get: _getGridCell,
    set: _setGridCell,
  ),
  SettingField(
    key: 'gridGap',
    type: SettingType.number,
    label: '网格间距',
    group: 'layout',
    min: 0,
    max: 80,
    step: 1,
    get: _getGridGap,
    set: _setGridGap,
  ),
  SettingField(
    key: 'snapEnabled',
    type: SettingType.boolean,
    label: '拖动时吸附对齐',
    group: 'layout',
    get: _getSnap,
    set: _setSnap,
  ),
  SettingField(
    key: 'snapThreshold',
    type: SettingType.number,
    label: '吸附距离',
    group: 'layout',
    min: 0,
    max: 60,
    step: 1,
    get: _getSnapThreshold,
    set: _setSnapThreshold,
  ),
  SettingField(
    key: 'locked',
    type: SettingType.boolean,
    label: '锁定布局',
    group: 'layout',
    desc: '禁止拖动与改尺寸',
    get: _getLocked,
    set: _setLocked,
  ),
  SettingField(
    key: 'animations',
    type: SettingType.boolean,
    label: '动画效果',
    group: 'layout',
    get: _getAnimations,
    set: _setAnimations,
  ),
  SettingField(
    key: 'liveRefreshMs',
    type: SettingType.number,
    label: '实时刷新间隔',
    group: 'layout',
    desc: '0 表示关闭',
    min: 0,
    max: 2000,
    step: 50,
    get: _getLiveRefresh,
    set: _setLiveRefresh,
  ),

  // —— 更新 ——
  SettingField(
    key: 'autoDownloadUpdate',
    type: SettingType.boolean,
    label: '自动下载更新',
    group: 'update',
    get: _getAutoDownload,
    set: _setAutoDownload,
  ),
  SettingField(
    key: 'updateSource',
    type: SettingType.select,
    label: '更新源',
    group: 'update',
    options: [
      {'value': 'auto', 'label': '自动（GitHub 优先）'},
      {'value': 'github', 'label': '只用 GitHub'},
      {'value': 'mirror', 'label': '只用镜像'},
    ],
    get: _getUpdateSource,
    set: _setUpdateSource,
  ),
];

// —— 读写实现 ——
// 单列成顶层函数而不是闭包，是为了让 kSettingFields 能保持 const。

String _getCardColor(AppSettings s) => _hex(s.cardColor);
void _setCardColor(AppSettings s, Object? v) => s.cardColor = _argb(v);

double _getCardRadius(AppSettings s) => s.cardRadius;
void _setCardRadius(AppSettings s, Object? v) => s.cardRadius = _num(v, 26).toDouble();

String _getMaterial(AppSettings s) => s.material;
void _setMaterial(AppSettings s, Object? v) => s.material = '${v ?? 'opaque'}';

String _getTheme(AppSettings s) => s.theme;
void _setTheme(AppSettings s, Object? v) => s.theme = '${v ?? 'auto'}';

double _getGlassTint(AppSettings s) => s.glassTint;
void _setGlassTint(AppSettings s, Object? v) => s.glassTint = _num(v, 0.35).toDouble();

double _getGlassBlur(AppSettings s) => s.glassBlur;
void _setGlassBlur(AppSettings s, Object? v) => s.glassBlur = _num(v, 18).toDouble();

bool _getAutoColor(AppSettings s) => s.autoColorFromWallpaper;
void _setAutoColor(AppSettings s, Object? v) => s.autoColorFromWallpaper = v == true;

bool _getAutoFg(AppSettings s) => s.autoForegroundFromWallpaper;
void _setAutoFg(AppSettings s, Object? v) => s.autoForegroundFromWallpaper = v == true;

int _getGridCell(AppSettings s) => s.gridCell;
void _setGridCell(AppSettings s, Object? v) => s.gridCell = _num(v, 112).round();

int _getGridGap(AppSettings s) => s.gridGap;
void _setGridGap(AppSettings s, Object? v) => s.gridGap = _num(v, 12).round();

bool _getSnap(AppSettings s) => s.snapEnabled;
void _setSnap(AppSettings s, Object? v) => s.snapEnabled = v == true;

double _getSnapThreshold(AppSettings s) => s.snapThreshold;
void _setSnapThreshold(AppSettings s, Object? v) =>
    s.snapThreshold = _num(v, 10).toDouble();

bool _getLocked(AppSettings s) => s.locked;
void _setLocked(AppSettings s, Object? v) => s.locked = v == true;

bool _getAnimations(AppSettings s) => s.animations;
void _setAnimations(AppSettings s, Object? v) => s.animations = v == true;

int _getLiveRefresh(AppSettings s) => s.liveRefreshMs;
void _setLiveRefresh(AppSettings s, Object? v) => s.liveRefreshMs = _num(v, 0).round();

bool _getAutoDownload(AppSettings s) => s.autoDownloadUpdate;
void _setAutoDownload(AppSettings s, Object? v) => s.autoDownloadUpdate = v == true;

String _getUpdateSource(AppSettings s) => s.updateSource;
void _setUpdateSource(AppSettings s, Object? v) => s.updateSource = '${v ?? 'auto'}';

/// 按 key 找字段；找不到返回 null（面板可能拿着旧 schema）。
SettingField? settingField(String key) {
  for (final f in kSettingFields) {
    if (f.key == key) return f;
  }
  return null;
}
