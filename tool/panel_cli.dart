/// 面板 CLI：核心 IPC 端点的命令行客户端。
///
/// **刻意不 import vectra 包**——只用 dart:io/env/convert，原因有两个：
///   1. `dart run` 会把包里的 FFI 代码一起编译，这个 Dart 版本上会崩
///      （`_FfiUseSiteTransformer` 的 type cast 失败）；
///   2. 它因此成了**协议的无依赖参考实现**：C++/WinUI3 那边照着这个文件
///      就能把 UDS + NDJSON 接起来，不需要先读懂 Dart 项目结构。
///
/// 用法（核心必须在跑）：
///
/// ```bash
/// dart run tool/panel_cli.dart info                 # 版本、插件数、卡片数
/// dart run tool/panel_cli.dart plugins              # 插件清单（含设置 schema）
/// dart run tool/panel_cli.dart schema               # 全局设置 schema
/// dart run tool/panel_cli.dart settings             # 读全部全局设置
/// dart run tool/panel_cli.dart set gridCell 128     # 改一项全局设置
/// dart run tool/panel_cli.dart cards                # 列卡片（含像素矩形、显示器）
/// dart run tool/panel_cli.dart add clock            # 加一张卡
/// dart run tool/panel_cli.dart rm <cardId>          # 删卡片
/// dart run tool/panel_cli.dart size <cardId> 3x3    # 改尺寸
/// dart run tool/panel_cli.dart card-set <id> k v    # 改卡片设置项
/// dart run tool/panel_cli.dart watch                # 连着看事件推送
/// dart run tool/panel_cli.dart call <method> [json] # 打任意方法（调试）
/// ```
///
/// 找不到端点时用 `--ipc <path/to/panel-ipc.json>` 显式指定。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---- 协议常量（与 lib/panel/protocol.dart 一致；改动要同步）----
const int kProtocol = 1;
const String mHello = 'hello';
const String mAppInfo = 'app.info';
const String mPluginsList = 'plugins.list';
const String mSettingsSchema = 'settings.schema';
const String mSettingsGet = 'settings.get';
const String mSettingsSet = 'settings.set';
const String mCardsList = 'cards.list';
const String mCardsAdd = 'cards.add';
const String mCardsRemove = 'cards.remove';
const String mCardsSetSize = 'cards.setSize';
const String mCardsSetSetting = 'cards.setSetting';
const String mWallpaperGet = 'wallpaper.get';

Future<void> main(List<String> rawArgs) async {
  // 先把全局参数摘掉（`--ipc <path>`），剩下的第一个才是命令——
  // 否则 `--ipc x info` 会被当成命令 `--ipc` 打出用法。
  final args = <String>[];
  String? ipcOverride;
  for (var i = 0; i < rawArgs.length; i++) {
    if (rawArgs[i] == '--ipc' && i + 1 < rawArgs.length) {
      ipcOverride = rawArgs[++i];
      continue;
    }
    args.add(rawArgs[i]);
  }
  if (args.isEmpty || args.first == 'help' || args.first == '-h') {
    _usage();
    return;
  }

  final ipc = _readIpcInfo(ipcOverride);
  if (ipc == null) {
    stderr.writeln('找不到面板 IPC 信息。核心在跑吗？'
        '（核心启动时会写 userdata/panel-ipc.json）');
    exitCode = 1;
    return;
  }
  stderr.writeln('端点 ${ipc['socket']}');

  final socket = await Socket.connect(
      InternetAddress(ipc['socket']!, type: InternetAddressType.unix), 0);
  final client = _Cli(socket);

  await client.request(mHello, {'protocol': kProtocol, 'token': ipc['token']});

  final cmd = args.first;
  switch (cmd) {
    case 'info':
      _print(await client.request(mAppInfo));

    case 'plugins':
      final r = await client.request(mPluginsList);
      for (final pl in (r['plugins'] as List).cast<Map>()) {
        stdout.writeln('${pl['id']}  ${pl['name']}  v${pl['version']}  '
            '${pl['icon']}  ${pl['description']}');
        stdout.writeln('    尺寸 ${(pl['sizes'] as List).join(' ')}'
            '（默认 ${pl['defaultSize']}）');
        for (final s in (pl['settings'] as List?) ?? const []) {
          final m = s as Map;
          stdout.writeln('    设置 ${m['key']} (${m['type']}) ${m['label']}'
              ' 默认=${m['default']}');
        }
      }

    case 'schema':
      final r = await client.request(mSettingsSchema);
      for (final g in (r['groups'] as List).cast<Map>()) {
        stdout.writeln('[${g['title']}]');
        for (final f in (g['fields'] as List).cast<Map>()) {
          stdout.writeln('  ${f['key']} (${f['type']}) ${f['label']}'
              ' = ${f['value']}');
        }
      }

    case 'settings':
      _print(await client.request(mSettingsGet));

    case 'wallpaper':
      _print(await client.request(mWallpaperGet));

    case 'set':
      _need(args, 3, 'set <key> <value>');
      _print(await client.request(
          mSettingsSet, {'key': args[1], 'value': _parseValue(args[2])}));

    case 'cards':
      final r = await client.request(mCardsList);
      stdout.writeln('显示器：');
      for (final d in (r['displays'] as List).cast<Map>()) {
        stdout.writeln('  ${d['id']}  ${d['w']}x${d['h']} @${d['x']},${d['y']}');
      }
      stdout.writeln('卡片：');
      for (final c in (r['cards'] as List).cast<Map>()) {
        stdout.writeln('  ${c['id']}  ${c['pluginName']}(${c['pluginId']})  '
            '${c['size']}  ${(c['w'] as num).round()}x${(c['h'] as num).round()} '
            '@${(c['x'] as num).round()},${(c['y'] as num).round()}  '
            '屏=${c['monitorId'] ?? '-'}');
        final s = (c['settings'] as Map?) ?? const {};
        if (s.isNotEmpty) stdout.writeln('    设置 $s');
      }
      final canAdd = (r['canAdd'] as Map?) ?? const {};
      stdout.writeln('可添加：'
          '${canAdd.entries.where((e) => e.value == true).map((e) => e.key).join(', ')}');

    case 'add':
      _need(args, 2, 'add <pluginId>');
      _print(await client.request(mCardsAdd, {'pluginId': args[1]}));

    case 'rm':
      _need(args, 2, 'rm <cardId>');
      _print(await client.request(mCardsRemove, {'id': args[1]}));

    case 'size':
      _need(args, 3, 'size <cardId> <宽x高>');
      _print(await client
          .request(mCardsSetSize, {'id': args[1], 'size': args[2]}));

    case 'card-set':
      _need(args, 4, 'card-set <cardId> <key> <value>');
      _print(await client.request(mCardsSetSetting,
          {'id': args[1], 'key': args[2], 'value': _parseValue(args[3])}));

    case 'call':
      _need(args, 2, 'call <method> [jsonParams]');
      final params = args.length > 2
          ? (jsonDecode(args[2]) as Map).cast<String, Object?>()
          : <String, Object?>{};
      _print(await client.request(args[1], params));

    case 'watch':
      stdout.writeln('监听事件（Ctrl+C 退出）…');
      client.onEvent = (e, pl) => stdout.writeln('事件 $e ${jsonEncode(pl)}');
      await Future<void>.delayed(const Duration(days: 1));

    default:
      _usage();
      exitCode = 1;
  }

  await client.close();
  exit(0);
}

/// 极简客户端：一次一个请求（CLI 不需要流水线），事件回调可选。
class _Cli {
  _Cli(this.socket) {
    socket.listen((d) {
      _tail += utf8.decode(d, allowMalformed: true);
      while (true) {
        final i = _tail.indexOf('\n');
        if (i < 0) break;
        final line = _tail.substring(0, i);
        _tail = _tail.substring(i + 1);
        if (line.trim().isEmpty) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(line);
        } catch (_) {
          continue;
        }
        if (decoded is! Map) continue;
        final msg = decoded.cast<String, Object?>();
        if (msg['e'] != null) {
          onEvent?.call(
              '${msg['e']}', (msg['p'] as Map?)?.cast<String, Object?>() ?? {});
          continue;
        }
        _pending.remove(msg['id'])?.complete(msg);
      }
    });
  }

  final Socket socket;
  String _tail = '';
  int _seq = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  void Function(String event, Map<String, Object?> payload)? onEvent;

  Future<Map<String, Object?>> request(String method,
      [Map<String, Object?> params = const {}]) async {
    final id = ++_seq;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    socket.write('${jsonEncode({'id': id, 'm': method, 'p': params})}\n');
    final msg = await c.future.timeout(const Duration(seconds: 10));
    if (msg['ok'] != true) {
      final err = (msg['err'] as Map?) ?? const {};
      throw StateError('${err['code']}: ${err['msg']}');
    }
    return (msg['r'] as Map?)?.cast<String, Object?>() ?? {};
  }

  Future<void> close() async {
    try {
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }
}

/// 找端点信息：`--ipc <path>` 优先，否则按常见位置找。
Map<String, String>? _readIpcInfo(String? override) {
  final env = Platform.environment['VECTRA_IPC'];
  final candidates = <String>[
    ?override,
    ?env,
    // 开发期：从仓库根跑，核心在 build 目录里
    'build/windows/x64/runner/Release/userdata/panel-ipc.json',
    'userdata/panel-ipc.json',
    // exe 旁边（CLI 被编译进程序时）
    '${File(Platform.resolvedExecutable).parent.path}/userdata/panel-ipc.json',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    try {
      final m =
          (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
      final socket = '${m['socket']}';
      final token = '${m['token']}';
      if (socket.isEmpty || token.isEmpty) continue;
      return {'socket': socket, 'token': token};
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// 命令行上的 `true/false/数字/JSON` 都按语义解析，其余当字符串。
Object? _parseValue(String raw) {
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  final n = num.tryParse(raw);
  if (n != null) return n;
  if (raw.startsWith('{') || raw.startsWith('[')) {
    try {
      return jsonDecode(raw);
    } catch (_) {}
  }
  return raw;
}

void _print(Map<String, Object?> r) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(r));

void _need(List<String> args, int n, String usage) {
  if (args.length < n) {
    stderr.writeln('参数不足：$usage');
    exit(1);
  }
}

void _usage() {
  stdout.writeln('''
面板 CLI —— 核心 IPC 端点的命令行客户端（零依赖，可作协议参考实现）

  info                       版本、插件数、卡片数
  plugins                    插件清单（含设置 schema）
  schema                     全局设置 schema（面板据此渲染控件）
  settings                   读全部全局设置
  set <key> <value>          改一项全局设置
  wallpaper                  壁纸与取色现状
  cards                      列卡片（含像素矩形、显示器、可添加性）
  add <pluginId>             加一张卡
  rm <cardId>                删卡片
  size <cardId> <宽x高>       改卡片尺寸
  card-set <id> <key> <val>  改卡片自己的设置项
  watch                      连着看事件推送
  call <method> [json]       打任意方法（调试）

  全局：--ipc <path>           显式指定 panel-ipc.json
''');
}
