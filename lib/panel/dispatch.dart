/// 方法分发：把协议请求变成对 [CoreHost] 的调用。
///
/// 这里**不做传输**（那是 service.dart 的事），也不碰 UI——只做参数校验、
/// 调 host、拼返回值。所以它能脱离 socket 单测：`dispatch.handle('cards.list', {})`。
library;

import '../core/grid.dart';
import '../model/card.dart';
import '../widgets/registry.dart';
import 'core_host.dart';
import 'protocol.dart';
import 'settings_schema.dart';

class PanelDispatch {
  PanelDispatch(this.host);

  final CoreHost host;

  /// 处理一个请求。返回 `r` 字段的内容。
  Future<Map<String, Object?>> handle(
      String method, Map<String, Object?> params) async {
    switch (method) {
      case PanelMethod.ping:
        return {'pong': true, 't': DateTime.now().millisecondsSinceEpoch};

      case PanelMethod.appInfo:
        return {
          'version': host.appVersion,
          'displayVersion': host.displayVersion,
          'userDataDir': host.userDataDir,
          'plugins': kPlugins.length,
          'cards': host.cards.length,
        };

      case PanelMethod.appQuit:
        // 先回响应再退（面板要看到 ok 才好收尾），退出在下一帧发生。
        Future.microtask(host.quit);
        return {'quitting': true};

      case PanelMethod.pluginsList:
        return {
          'plugins': [for (final p in kPlugins) p.describe()],
        };

      case PanelMethod.settingsSchema:
        return {
          'groups': [
            for (final g in kSettingGroupTitles.entries)
              {
                'id': g.key,
                'title': g.value,
                'fields': [
                  for (final f in kSettingFields)
                    if (f.group == g.key) f.describe(host.settings),
                ],
              },
          ],
        };

      case PanelMethod.settingsGet:
        return {
          'values': {
            for (final f in kSettingFields) f.key: f.get(host.settings),
          },
        };

      case PanelMethod.settingsSet:
        return _settingsSet(params);

      case PanelMethod.cardsList:
        return _cardsList();

      case PanelMethod.cardsAdd:
        return _cardsAdd(params);

      case PanelMethod.cardsRemove:
        return _cardsRemove(params);

      case PanelMethod.cardsSetSize:
        return _cardsSetSize(params);

      case PanelMethod.cardsSetSetting:
        return _cardsSetSetting(params);

      case PanelMethod.wallpaperGet:
        return host.wallpaperInfo();

      default:
        throw PanelError(PanelErrorCode.unsupported, '核心不认识方法「$method」');
    }
  }

  // ------------------------------------------------------------------
  // 全局设置
  // ------------------------------------------------------------------

  Map<String, Object?> _settingsSet(Map<String, Object?> p) {
    final key = _str(p, 'key');
    final field = settingField(key);
    if (field == null) {
      throw PanelError(PanelErrorCode.notFound, '未知设置项「$key」');
    }
    if (!p.containsKey('value')) {
      throw PanelError(PanelErrorCode.badRequest, '缺少 value');
    }
    final value = _coerce(field, p['value']);
    field.set(host.settings, value);
    host.onSettingsChanged([key]);
    return {'key': key, 'value': field.get(host.settings)};
  }

  /// 按 schema 校验并归一化值。宁可在核心侧严格一点，也别让面板传什么就
  /// 存什么——设置会落盘，脏数据的代价是"下次启动行为莫名"。
  Object? _coerce(SettingField f, Object? v) {
    switch (f.type) {
      case SettingType.boolean:
        if (v is! bool) {
          throw PanelError(PanelErrorCode.badRequest, '${f.key} 需要布尔值');
        }
        return v;

      case SettingType.number:
        if (v is! num) {
          throw PanelError(PanelErrorCode.badRequest, '${f.key} 需要数字');
        }
        var n = v.toDouble();
        if (f.min != null) n = n < f.min! ? f.min!.toDouble() : n;
        if (f.max != null) n = n > f.max! ? f.max!.toDouble() : n;
        // 步长是整数时返回 int（设置面板显示 "112" 而不是 "112.0"）
        final step = f.step ?? 1;
        if (step >= 1 && step == step.roundToDouble()) return n.round();
        return n;

      case SettingType.text:
        if (v is! String) {
          throw PanelError(PanelErrorCode.badRequest, '${f.key} 需要字符串');
        }
        return v;

      case SettingType.select:
        final ok = f.options.any((o) => '${o['value']}' == '$v');
        if (!ok) {
          throw PanelError(PanelErrorCode.badRequest,
              '${f.key} 的值「$v」不在选项里');
        }
        return '$v';

      case SettingType.color:
        if (v is num) return v.toInt();
        final s = '$v'.replaceFirst('#', '');
        final ok = RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(s);
        if (!ok) {
          throw PanelError(PanelErrorCode.badRequest,
              '${f.key} 需要 #RRGGBB / #RRGGBBAA 或 ARGB 整数');
        }
        return s.length == 6 ? 0xFF000000 | int.parse(s, radix: 16) : int.parse(s, radix: 16);
    }
  }

  // ------------------------------------------------------------------
  // 卡片
  // ------------------------------------------------------------------

  Map<String, Object?> _cardsList() {
    final cell = host.settings.gridCell;
    final gap = host.settings.gridGap;
    return {
      'grid': {'cell': cell, 'gap': gap},
      'displays': host.displays,
      'cards': [for (final c in host.cards) _cardJson(c, cell, gap)],
      'canAdd': {
        for (final p in kPlugins) p.id: host.canAddPlugin(p.id),
      },
    };
  }

  Map<String, Object?> _cardJson(WidgetCard c, int cell, int gap) {
    final px = sizeToPx(c.size, cell, gap);
    return {
      'id': c.id,
      'pluginId': c.pluginId,
      'pluginName': pluginById(c.pluginId)?.name ?? c.pluginId,
      'size': c.size,
      'sizes': pluginById(c.pluginId)?.sizes ?? const <String>[],
      'x': c.x,
      'y': c.y,
      'w': px.w,
      'h': px.h,
      'z': c.z,
      'monitorId': c.monitorId,
      'settings': c.settings,
    };
  }

  Map<String, Object?> _cardsAdd(Map<String, Object?> p) {
    final pluginId = _str(p, 'pluginId');
    if (pluginById(pluginId) == null) {
      throw PanelError(PanelErrorCode.notFound, '未知插件「$pluginId」');
    }
    if (!host.canAddPlugin(pluginId)) {
      throw PanelError(PanelErrorCode.rejected,
          '没有空闲屏幕能放下「${pluginById(pluginId)!.name}」');
    }
    final card = host.addCard(pluginId);
    if (card == null) {
      throw PanelError(PanelErrorCode.rejected, '添加失败：找不到落点');
    }
    return {
      'id': card.id,
      'card': _cardJson(card, host.settings.gridCell, host.settings.gridGap),
    };
  }

  Map<String, Object?> _cardsRemove(Map<String, Object?> p) {
    final id = _str(p, 'id');
    if (!host.removeCard(id)) {
      throw PanelError(PanelErrorCode.notFound, '没有卡片「$id」');
    }
    return {'id': id};
  }

  Map<String, Object?> _cardsSetSize(Map<String, Object?> p) {
    final id = _str(p, 'id');
    final size = _str(p, 'size');
    final card = _findCard(id);
    final allowed = pluginById(card.pluginId)?.sizes ?? const <String>[];
    if (!allowed.contains(size)) {
      throw PanelError(PanelErrorCode.badRequest,
          '插件 ${card.pluginId} 不支持尺寸「$size」');
    }
    if (!host.resizeCard(id, size)) {
      throw PanelError(PanelErrorCode.notFound, '没有卡片「$id」');
    }
    return {'id': id, 'size': size};
  }

  Map<String, Object?> _cardsSetSetting(Map<String, Object?> p) {
    final id = _str(p, 'id');
    final key = _str(p, 'key');
    if (!p.containsKey('value')) {
      throw PanelError(PanelErrorCode.badRequest, '缺少 value');
    }
    final card = _findCard(id);
    final manifest = pluginById(card.pluginId);
    Map<String, Object?>? field;
    for (final f in manifest?.settings ?? const <Map<String, Object?>>[]) {
      if (f['key'] == key) {
        field = f;
        break;
      }
    }
    if (field == null) {
      throw PanelError(PanelErrorCode.notFound,
          '插件 ${manifest?.id} 没有设置项「$key」');
    }
    if (!host.setCardSetting(id, key, p['value'])) {
      throw PanelError(PanelErrorCode.notFound, '没有卡片「$id」');
    }
    return {'id': id, 'key': key};
  }

  WidgetCard _findCard(String id) {
    for (final c in host.cards) {
      if (c.id == id) return c;
    }
    throw PanelError(PanelErrorCode.notFound, '没有卡片「$id」');
  }

  String _str(Map<String, Object?> p, String key) {
    final v = p[key];
    if (v is! String || v.isEmpty) {
      throw PanelError(PanelErrorCode.badRequest, '缺少参数 $key');
    }
    return v;
  }
}
