/// 架构边界守卫 + 插件清单校验。
///
/// 这些断言不测组件行为，测的是**依赖方向**与**清单合法性**——让
/// "壳不认识具体插件""清单字段齐全"这类约定靠测试锁住，而不是靠自觉。
/// 破坏边界时会立刻炸，而不是半年后变成一团谁也拆不开的耦合。
///
/// 边界（见 lib/widgets/plugin_api.dart 的图）：
///
/// ```
///   lib/ui/**（面板、桌面层）     只能 import plugin_api + registry
///        ▼
///   registry.dart                唯一 import widgets/builtin/** 的地方
///        ▼
///   widgets/builtin/<插件>        实现 + manifest + 工厂
/// ```
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/widgets/registry.dart';

/// 从 Dart 源码里抽出所有 import 的目标路径。
List<String> importsOf(File file) {
  final out = <String>[];
  final re = RegExp(r"^\s*import\s+'([^']+)'", multiLine: true);
  for (final m in re.allMatches(file.readAsStringSync())) {
    out.add(m.group(1)!);
  }
  return out;
}

List<File> dartFilesIn(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String norm(String p) => p.replaceAll('\\', '/');

/// import 目标是否指向具体插件实现目录。
bool importsPluginImpl(String target) => norm(target).contains('builtin/');

void main() {
  group('依赖方向', () {
    test('壳（lib/ui）永不 import 具体插件实现', () {
      final offenders = <String>[];
      for (final f in dartFilesIn('lib/ui')) {
        for (final t in importsOf(f)) {
          if (importsPluginImpl(t)) offenders.add('${norm(f.path)} → $t');
        }
      }
      expect(offenders, isEmpty,
          reason: '面板/桌面层必须只依赖 plugin_api + registry。插件是'
              '"可替换的实现细节"，壳直接 import 它们之后，加/换插件就得改壳，'
              '边界就白画了。\n违规：\n${offenders.join('\n')}');
    });

    test('widgets 根目录下的壳组件也不 import 具体插件', () {
      final offenders = <String>[];
      for (final f in dartFilesIn('lib/widgets')) {
        // 只看根目录的壳文件，不看 builtin/ 子目录（插件自己人）
        final rel = norm(f.path);
        if (!rel.startsWith('lib/widgets/')) continue;
        if (rel.startsWith('lib/widgets/builtin/')) continue;
        if (rel.endsWith('registry.dart')) continue;
        for (final t in importsOf(f)) {
          if (importsPluginImpl(t)) offenders.add('$rel → $t');
        }
      }
      expect(offenders, isEmpty, reason: '违规：\n${offenders.join('\n')}');
    });

    test('registry.dart 是唯一组装点', () {
      final offenders = <String>[];
      for (final f in dartFilesIn('lib')) {
        final rel = norm(f.path);
        if (rel.startsWith('lib/widgets/builtin/')) continue; // 插件内部
        if (rel.endsWith('registry.dart')) continue; // 组装点本身
        for (final t in importsOf(f)) {
          if (importsPluginImpl(t)) offenders.add('$rel → $t');
        }
      }
      expect(offenders, isEmpty,
          reason: '除 registry.dart 外，任何壳/UI 代码都不该 import 插件实现。'
              '\n违规：\n${offenders.join('\n')}');
    });

    test('契约层不反向依赖实现或注册表', () {
      final f = File('lib/widgets/plugin_api.dart');
      expect(f.existsSync(), isTrue);
      for (final t in importsOf(f)) {
        expect(importsPluginImpl(t), isFalse, reason: '契约层不能依赖实现：$t');
        expect(t.contains('registry.dart'), isFalse,
            reason: '契约层不能依赖注册表（依赖方向反了）：$t');
      }
    });
  });

  group('清单合法性（新增/修改插件时最容易写错的地方）', () {
    test('id 非空、唯一、且是合法标识符', () {
      final seen = <String>{};
      for (final p in kPlugins) {
        expect(p.id, isNotEmpty);
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(p.id), isTrue,
            reason: '插件 id「${p.id}」必须是 snake_case（它会成为存储命名空间）');
        expect(seen.add(p.id), isTrue, reason: '插件 id 重复：${p.id}');
      }
    });

    test('defaultSize 必须落在 sizes 里', () {
      for (final p in kPlugins) {
        expect(p.sizes, contains(p.defaultSize),
            reason: '插件 ${p.id}：defaultSize「${p.defaultSize}」不在 '
                'sizes $p.sizes 里——放置这张卡片时会拿到一个不允许的尺寸');
      }
    });

    test('sizes 写成 宽x高 的 grid 单位且非空', () {
      final re = RegExp(r'^\d+x\d+$');
      for (final p in kPlugins) {
        expect(p.sizes, isNotEmpty, reason: '插件 ${p.id} 没声明任何尺寸');
        for (final s in p.sizes) {
          expect(re.hasMatch(s), isTrue,
              reason: '插件 ${p.id} 的尺寸「$s」不是 "宽x高" 格式');
        }
      }
    });

    test('设置项 schema 合法（面板按这套规则渲染控件）', () {
      // 面板认识的四类控件见 lib/ui/panel.dart 的 _settingField 分发：
      // boolean / select / number 各有专属控件，其余一律退化成文本框。
      // 所以写错类型不会报错、只会**悄悄变成文本框**——必须靠这条测试拦住。
      const knownTypes = {'boolean', 'number', 'text', 'select'};
      for (final p in kPlugins) {
        final keys = <String>{};
        for (final f in p.settings) {
          final key = f['key'];
          final type = f['type'];
          expect(key, isA<String>(),
              reason: '插件 ${p.id} 有设置项缺 key');
          expect(keys.add(key as String), isTrue,
              reason: '插件 ${p.id} 的设置键重复：$key');
          expect(knownTypes.contains(type), isTrue,
              reason: '插件 ${p.id} 的设置「$key」类型「$type」不是面板认识的类型'
                  '（会静默退化成文本框，用户看到的控件和预期不符）。'
                  '可用：$knownTypes');
          expect(f.containsKey('label'), isTrue,
              reason: '插件 ${p.id} 的设置「$key」缺 label（设置页会显示空标题）');
          expect(f.containsKey('default'), isTrue,
              reason: '插件 ${p.id} 的设置「$key」缺 default'
                  '（defaultSettings() 会塞进 null，组件读到没意义的值）');
          if (type == 'number') {
            for (final need in ['min', 'max', 'step']) {
              expect(f.containsKey(need), isTrue,
                  reason: 'number 类型的「$key」缺 $need'
                      '（面板会退回 0~100/步长 1，滑条范围可能完全不对）');
            }
          }
          if (type == 'select') {
            final opts = f['options'];
            expect(opts, isA<List>(), reason: 'select 类型的「$key」缺 options');
            expect((opts as List), isNotEmpty);
            final values =
                opts.whereType<Map>().map((o) => o['value']).toList();
            expect(values, contains(f['default']),
                reason: 'select 类型的「$key」默认值不在 options 里'
                    '（下拉框初始显示空白）');
          }
        }
        // defaultSettings 必须和 settings 一一对应
        expect(p.defaultSettings().length, p.settings.length);
      }
    });

    test('每个注册插件都有对应工厂（忘了登记会在这里炸）', () {
      for (final p in kPlugins) {
        expect(pluginFactoryById(p.id), isNotNull,
            reason: '插件 ${p.id} 在清单里，但 registry 的工厂表里没有它——'
                '运行时才会发现"卡片起不来"。加插件时清单和工厂要一起登记。');
      }
      // 反向：工厂表里不该有清单外的孤儿
      for (final p in kPlugins) {
        expect(pluginById(p.id), isNotNull);
      }
    });

    test('插件描述 / 名称 / 图标不为空（面板组件库要靠它们展示）', () {
      for (final p in kPlugins) {
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} 缺名称');
        expect(p.description.trim(), isNotEmpty,
            reason: '${p.id} 缺描述（组件库卡片会空白）');
        expect(p.icon.trim(), isNotEmpty, reason: '${p.id} 缺图标');
      }
    });
  });
}
