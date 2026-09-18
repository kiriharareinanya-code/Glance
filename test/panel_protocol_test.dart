/// 面板 IPC 的契约测试。
///
/// 打的是**真的 Unix domain socket**（不是 mock）：这类协议最容易死的地方
/// 是分帧、握手顺序、错误码，只有真跑一遍连接才测得出来。C++ 面板来写的时候，
/// 这份测试就是"协议应该长什么样"的可执行答案。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/model/card.dart';
import 'package:vectra/model/settings.dart';
import 'package:vectra/panel/core_host.dart';
import 'package:vectra/panel/protocol.dart';
import 'package:vectra/panel/service.dart';

/// 假宿主：只实现协议用得到的域操作，不碰真实应用。
class _FakeHost implements CoreHost {
  _FakeHost(this.dir);

  final String dir;
  final AppSettings _settings = AppSettings();
  final List<WidgetCard> _cards = [];

  int added = 0;
  final List<String> settingsTouched = [];

  @override
  String get appVersion => '9.9.9';

  @override
  String get displayVersion => 'Test-9.9.9';

  @override
  String get userDataDir => dir;

  @override
  AppSettings get settings => _settings;

  @override
  List<WidgetCard> get cards => _cards;

  @override
  List<Map<String, Object?>> get displays => [
        {'id': r'\\.\DISPLAY1', 'x': 0, 'y': 0, 'w': 2560, 'h': 1440},
      ];

  @override
  bool canAddPlugin(String pluginId) => pluginId != 'lyrics';

  @override
  WidgetCard? addCard(String pluginId) {
    added++;
    final c = WidgetCard(
        id: 'card$added',
        pluginId: pluginId,
        x: 100.0 * added,
        y: 100,
        size: '3x3',
        z: added);
    _cards.add(c);
    return c;
  }

  @override
  bool removeCard(String id) {
    final n = _cards.length;
    _cards.removeWhere((c) => c.id == id);
    return _cards.length != n;
  }

  @override
  bool resizeCard(String id, String size) {
    for (final c in _cards) {
      if (c.id == id) {
        c.size = size;
        return true;
      }
    }
    return false;
  }

  @override
  bool setCardSetting(String id, String key, Object? value) {
    for (final c in _cards) {
      if (c.id == id) {
        c.settings[key] = value;
        return true;
      }
    }
    return false;
  }

  @override
  void onSettingsChanged(Iterable<String> keys) => settingsTouched.addAll(keys);

  @override
  Map<String, Object?> wallpaperInfo() =>
      {'source': 'test.jpg', 'dominant': '#334455', 'brightness': 0.4};

  @override
  Future<void> quit() async {}
}

/// 测试客户端：与 tool/panel_cli.dart 同构，但能故意发错。
class _Client {
  _Client(this.socket) {
    socket.listen((d) {
      _tail += utf8.decode(d, allowMalformed: true);
      while (true) {
        final i = _tail.indexOf('\n');
        if (i < 0) break;
        final line = _tail.substring(0, i);
        _tail = _tail.substring(i + 1);
        final msg = decodeLine(line);
        if (msg == null) continue;
        if (msg['e'] != null) {
          events.add('${msg['e']}');
          continue;
        }
        _pending.remove(msg['id'])?.complete(msg);
      }
    }, onDone: () => closed = true);
  }

  final Socket socket;
  String _tail = '';
  int _seq = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final List<String> events = [];
  bool closed = false;

  Future<Map<String, Object?>> raw(String method, Map<String, Object?> p) {
    final id = ++_seq;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    socket.write(encodeLine({'id': id, 'm': method, 'p': p}));
    return c.future.timeout(const Duration(seconds: 5));
  }

  Future<Map<String, Object?>> ok(String method,
      [Map<String, Object?> p = const {}]) async {
    final m = await raw(method, p);
    expect(m['ok'], isTrue, reason: '期望成功，实际：$m');
    return (m['r'] as Map?)?.cast<String, Object?>() ?? {};
  }

  Future<Map<String, Object?>> fail(String method,
      [Map<String, Object?> p = const {}]) async {
    final m = await raw(method, p);
    expect(m['ok'], isFalse, reason: '期望失败，实际：$m');
    return ((m['err'] as Map?) ?? const {}).cast<String, Object?>();
  }

  Future<void> close() async {
    try {
      await socket.close();
    } catch (_) {}
  }
}

void main() {
  late Directory tmp;
  late _FakeHost host;
  late PanelService service;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('vectra-panel');
    host = _FakeHost(tmp.path);
    service = PanelService(host);
    await service.start();
  });

  tearDown(() async {
    await service.stop();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<_Client> connect() async {
    final s = await Socket.connect(
        InternetAddress(service.socketPath, type: InternetAddressType.unix), 0);
    return _Client(s);
  }

  Future<_Client> connectAuthed() async {
    final c = await connect();
    await c.ok(PanelMethod.hello,
        {'protocol': kPanelProtocolVersion, 'token': service.token});
    return c;
  }

  group('握手', () {
    test('正确 token + 版本 → 拿到核心版本', () async {
      final c = await connect();
      final r = await c.ok(PanelMethod.hello,
          {'protocol': kPanelProtocolVersion, 'token': service.token});
      expect(r['protocol'], kPanelProtocolVersion);
      expect((r['core'] as Map)['displayVersion'], 'Test-9.9.9');
      await c.close();
    });

    test('没握手就调方法 → no_handshake 且断开', () async {
      final c = await connect();
      final err = await c.fail(PanelMethod.cardsList);
      expect(err['code'], PanelErrorCode.noHandshake);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.closed, isTrue, reason: '未握手的连接必须被断开');
      await c.close();
    });

    test('token 错 → bad_token 且断开', () async {
      final c = await connect();
      final err = await c.fail(PanelMethod.hello,
          {'protocol': kPanelProtocolVersion, 'token': 'x'});
      expect(err['code'], PanelErrorCode.badToken);
      await c.close();
    });

    test('协议版本不匹配 → bad_version（不静默降级）', () async {
      final c = await connect();
      final err = await c.fail(PanelMethod.hello,
          {'protocol': kPanelProtocolVersion + 99, 'token': service.token});
      expect(err['code'], PanelErrorCode.badVersion);
      await c.close();
    });

    test('多余的键不影响握手（向前兼容）', () async {
      final c = await connect();
      final r = await c.ok(PanelMethod.hello, {
        'protocol': kPanelProtocolVersion,
        'token': service.token,
        'future': 1,
      });
      expect(r['core'], isNotNull);
      await c.close();
    });
  });

  group('元信息与插件', () {
    test('app.info 给出面板要显示的信息', () async {
      final c = await connectAuthed();
      final r = await c.ok(PanelMethod.appInfo);
      expect(r['version'], '9.9.9');
      expect(r['userDataDir'], tmp.path);
      expect(r['plugins'], greaterThan(0));
      await c.close();
    });

    test('plugins.list 的设置 schema 足够面板渲染控件', () async {
      final c = await connectAuthed();
      final r = await c.ok(PanelMethod.pluginsList);
      final plugins = (r['plugins'] as List).cast<Map>();
      expect(plugins.length, greaterThanOrEqualTo(5));
      final clock = plugins.firstWhere((p) => p['id'] == 'clock');
      expect(clock['name'], '时钟');
      expect(clock['sizes'], contains(clock['defaultSize']));
      for (final f in (clock['settings'] as List).cast<Map>()) {
        expect(f['key'], isNotNull);
        expect(f['type'], isNotNull);
        expect(f['label'], isNotNull);
        expect(f.containsKey('default'), isTrue);
      }
      await c.close();
    });
  });

  group('全局设置（schema 驱动）', () {
    test('schema 分组齐全，每项都带当前值', () async {
      final c = await connectAuthed();
      final r = await c.ok(PanelMethod.settingsSchema);
      final groups = (r['groups'] as List).cast<Map>();
      expect(groups.map((g) => g['id']), containsAll(['appearance', 'layout']));
      for (final g in groups) {
        for (final f in (g['fields'] as List).cast<Map>()) {
          expect(f.containsKey('value'), isTrue,
              reason: '面板要用 value 初始化控件（${f['key']}）');
        }
      }
      await c.close();
    });

    test('读写往返 + 宿主收到通知', () async {
      final c = await connectAuthed();
      await c.ok(PanelMethod.settingsSet, {'key': 'gridCell', 'value': 128});
      final r = await c.ok(PanelMethod.settingsGet);
      expect((r['values'] as Map)['gridCell'], 128);
      expect(host.settingsTouched, contains('gridCell'));
      await c.close();
    });

    test('number 越界被夹到范围内（不让脏值落盘）', () async {
      final c = await connectAuthed();
      final r = await c
          .ok(PanelMethod.settingsSet, {'key': 'gridCell', 'value': 999999});
      expect(r['value'], lessThanOrEqualTo(320));
      await c.close();
    });

    test('select 值不在选项里 → bad_request', () async {
      final c = await connectAuthed();
      final err = await c.fail(
          PanelMethod.settingsSet, {'key': 'material', 'value': '不存在'});
      expect(err['code'], PanelErrorCode.badRequest);
      await c.close();
    });

    test('类型不对 → bad_request', () async {
      final c = await connectAuthed();
      final err = await c.fail(
          PanelMethod.settingsSet, {'key': 'snapEnabled', 'value': 'yes'});
      expect(err['code'], PanelErrorCode.badRequest);
      await c.close();
    });

    test('未知设置项 → not_found', () async {
      final c = await connectAuthed();
      final err =
          await c.fail(PanelMethod.settingsSet, {'key': 'nope', 'value': 1});
      expect(err['code'], PanelErrorCode.notFound);
      await c.close();
    });

    test('颜色接受 #RRGGBB 与 ARGB 整数，非法值被拒', () async {
      final c = await connectAuthed();
      await c.ok(
          PanelMethod.settingsSet, {'key': 'cardColor', 'value': '#112233'});
      expect(host.settings.cardColor, 0xFF112233);
      await c.ok(
          PanelMethod.settingsSet, {'key': 'cardColor', 'value': 0xFF445566});
      expect(host.settings.cardColor, 0xFF445566);
      final err = await c
          .fail(PanelMethod.settingsSet, {'key': 'cardColor', 'value': 'zzz'});
      expect(err['code'], PanelErrorCode.badRequest);
      await c.close();
    });
  });

  group('卡片', () {
    test('cards.list 带像素矩形、显示器、可添加性', () async {
      final c = await connectAuthed();
      await c.ok(PanelMethod.cardsAdd, {'pluginId': 'clock'});
      final r = await c.ok(PanelMethod.cardsList);
      final cards = (r['cards'] as List).cast<Map>();
      expect(cards, hasLength(1));
      expect(cards.first['pluginName'], '时钟');
      expect((cards.first['w'] as num), greaterThan(0));
      expect((r['displays'] as List), hasLength(1));
      expect((r['canAdd'] as Map)['lyrics'], isFalse);
      expect((r['canAdd'] as Map)['clock'], isTrue);
      await c.close();
    });

    test('add → 返回新卡；未知插件 → not_found', () async {
      final c = await connectAuthed();
      final r = await c.ok(PanelMethod.cardsAdd, {'pluginId': 'todo'});
      expect(r['id'], isNotNull);
      final err = await c.fail(PanelMethod.cardsAdd, {'pluginId': 'nope'});
      expect(err['code'], PanelErrorCode.notFound);
      await c.close();
    });

    test('没有空闲屏 → rejected（而不是静默失败）', () async {
      final c = await connectAuthed();
      final err = await c.fail(PanelMethod.cardsAdd, {'pluginId': 'lyrics'});
      expect(err['code'], PanelErrorCode.rejected);
      await c.close();
    });

    test('setSize 校验尺寸在插件允许列表里', () async {
      final c = await connectAuthed();
      final add = await c.ok(PanelMethod.cardsAdd, {'pluginId': 'clock'});
      final id = add['id'];
      await c.ok(PanelMethod.cardsSetSize, {'id': id, 'size': '3x3'});
      final err =
          await c.fail(PanelMethod.cardsSetSize, {'id': id, 'size': '9x9'});
      expect(err['code'], PanelErrorCode.badRequest);
      await c.close();
    });

    test('setSetting 校验设置项存在', () async {
      final c = await connectAuthed();
      final add = await c.ok(PanelMethod.cardsAdd, {'pluginId': 'clock'});
      final id = add['id'];
      await c.ok(PanelMethod.cardsSetSetting,
          {'id': id, 'key': 'seconds', 'value': true});
      expect(host.cards.first.settings['seconds'], isTrue);
      final err = await c.fail(PanelMethod.cardsSetSetting,
          {'id': id, 'key': 'noSuchKey', 'value': 1});
      expect(err['code'], PanelErrorCode.notFound);
      await c.close();
    });

    test('remove 不存在的卡片 → not_found', () async {
      final c = await connectAuthed();
      final err = await c.fail(PanelMethod.cardsRemove, {'id': 'ghost'});
      expect(err['code'], PanelErrorCode.notFound);
      await c.close();
    });
  });

  group('错误与健壮性', () {
    test('未知方法 → unsupported', () async {
      final c = await connectAuthed();
      final err = await c.fail('no.such.method');
      expect(err['code'], PanelErrorCode.unsupported);
      await c.close();
    });

    test('非 JSON 行不致命，连接还能继续用', () async {
      final c = await connectAuthed();
      c.socket.write('这不是 json\n');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final r = await c.ok(PanelMethod.ping);
      expect(r['pong'], isTrue);
      await c.close();
    });

    test('缺参数 → bad_request', () async {
      final c = await connectAuthed();
      final err = await c.fail(PanelMethod.cardsSetSize, {'id': 'x'});
      expect(err['code'], PanelErrorCode.badRequest);
      await c.close();
    });
  });

  group('事件', () {
    test('改设置 → settings.changed；加卡 → cards.changed（广播给其他连接）',
        () async {
      final a = await connectAuthed();
      final b = await connectAuthed();

      await a.ok(PanelMethod.settingsSet, {'key': 'gridGap', 'value': 20});
      await a.ok(PanelMethod.cardsAdd, {'pluginId': 'clock'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(b.events, contains(PanelEvent.settingsChanged));
      expect(b.events, contains(PanelEvent.cardsChanged));
      await a.close();
      await b.close();
    });

    test('launchOrActivate：已有面板连着时推 activate 而非重复启动', () async {
      final c = await connectAuthed();
      expect(service.hasPanel, isTrue);
      expect(await service.launchOrActivate(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(c.events, contains(PanelEvent.activate));
      await c.close();
    });
  });

  group('生命周期', () {
    // 注意：**不要断言 socket 文件的存在性**。Windows 的 AF_UNIX socket 不是
    // `File.existsSync()` 认得的普通文件（实测恒为 false），断言它只会得到
    // 假信息。真正要保证的是行为：停掉之后还能重新起来并接受连接。
    test('stop 之后能重新 start，并且还能握手', () async {
      await service.stop();
      expect(service.isRunning, isFalse);

      await service.start();
      expect(service.isRunning, isTrue);

      final c = await connect();
      final r = await c.ok(PanelMethod.hello,
          {'protocol': kPanelProtocolVersion, 'token': service.token});
      expect(r['core'], isNotNull);
      await c.close();
    });

    test('panel-ipc.json 写了端点信息，stop 后删除', () async {
      final f = File('${tmp.path}/panel-ipc.json');
      expect(f.existsSync(), isTrue);
      final m = jsonDecode(f.readAsStringSync()) as Map;
      expect(m['socket'], service.socketPath);
      expect(m['token'], service.token);
      await service.stop();
      expect(f.existsSync(), isFalse);
    });
  });
}
