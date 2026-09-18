/// 面板服务：Unix domain socket 上的 NDJSON 端点。
///
/// 生命周期：应用启动、配置加载完之后 [start]；退出时 [stop]。
/// 一个核心进程只服务一个面板，但**允许多个连接**（开发期 CLI 与面板可以
/// 同时连着看状态），事件广播给所有已握手的会话。
///
/// 为什么核心做服务端而不是客户端：面板是"按需启动"的（用户点托盘设置），
/// 而核心一直在跑。核心持有 token 与 socket 路径，启动面板进程时递过去，
/// 面板连回来。这样不需要"发现已运行实例"的逻辑，也没有端口占用问题。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../core/logger.dart';
import 'core_host.dart';
import 'dispatch.dart';
import 'protocol.dart';

class PanelService {
  PanelService(this.host);

  final CoreHost host;

  /// socket 文件位置。
  ///
  /// Windows 的 UDS 路径上限约 108 字符，而 userdata 是 `exe 同目录`（便携
  /// 模型），exe 放得很深时可能超。超了就退化到系统临时目录——反正在哪儿
  /// 都无所谓：路径是**明确传给面板**的，不是靠约定发现。
  String get socketPath {
    final preferred = p.join(host.userDataDir, 'panel.sock');
    if (preferred.length <= 100) return preferred;
    final fallback = p.join(Directory.systemTemp.path, 'vectra-panel.sock');
    Log.w('panel', 'socket 路径过长（${preferred.length}），改用 $fallback');
    return fallback;
  }

  /// 每次核心启动重新随机；面板由核心启动，所以拿得到。
  final String token = _randomToken();

  /// 方法分发（域逻辑在 dispatch.dart，这里只管传输与会话）
  late final PanelDispatch dispatch = PanelDispatch(host);

  ServerSocket? _server;
  final Set<_PanelSession> _sessions = {};
  int _seq = 0;

  /// "没找到面板"只提醒一次：迁移期每次点设置都回落到 Flutter 面板，
  /// 每次都写一行警告会把日志刷满。
  bool _missingPanelLogged = false;

  bool get isRunning => _server != null;

  /// 有面板连着（托盘再点"设置"时用来决定"激活"还是"启动"）
  bool get hasPanel => _sessions.isNotEmpty;

  /// 面板可执行文件的位置（与核心同目录）。开发期通常不存在——这时
  /// [launchOrActivate] 会明确报"没找到面板"。
  List<String> get panelExeCandidates {
    final dir = p.dirname(Platform.resolvedExecutable);
    return [
      p.join(dir, 'panel', 'panel.exe'),
      p.join(dir, 'panel.exe'),
    ];
  }

  /// 把 socket 路径与 token 落到 `<userdata>/panel-ipc.json`。
  ///
  /// 只服务于开发期：`tool/panel_cli.dart` 靠它找到端点，省得每次手动传参。
  /// 面板进程**不走这条路**——它由核心启动时经命令行直接拿到（更短、更明确）。
  File get _ipcInfoFile => File(p.join(host.userDataDir, 'panel-ipc.json'));

  Future<void> _writeIpcInfo() async {
    try {
      await _ipcInfoFile.writeAsString(
          jsonEncode({'socket': socketPath, 'token': token}),
          flush: true);
    } catch (e) {
      Log.d('panel', '写 panel-ipc.json 失败（不影响服务）：$e');
    }
  }

  Future<void> start() async {
    if (_server != null) return;
    final path = socketPath;
    try {
      // 上次崩溃可能留下 socket 文件，占着名字会 bind 失败。
      // 注意：Windows 的 AF_UNIX socket 不是 `File.exists()` 认得的普通文件
      // （实测 existsSync() 返回 false），所以**不能"先判断再删"**——那样
      // 永远不会删。直接试着删，失败就放过。
      await _removeSocketFile(path);
      final server = await ServerSocket.bind(
          InternetAddress(path, type: InternetAddressType.unix), 0);
      _server = server;
      server.listen(_onClient, onError: (Object e) {
        Log.w('panel', '监听出错：$e');
      });
      await _writeIpcInfo();
      Log.i('panel', '面板服务已就绪 $path（协议 v$kPanelProtocolVersion）');
    } catch (e) {
      // 起不来不该影响主程序：面板只是"改设置"的一条路，核心照常跑
      Log.w('panel', '面板服务启动失败（不影响核心运行）：$e');
    }
  }

  Future<void> stop() async {
    for (final s in _sessions.toList()) {
      await s.close();
    }
    _sessions.clear();
    await _server?.close();
    _server = null;
    // 清掉 socket 文件：留着下次 bind 会失败（虽然 start 里也兜了一层）
    await _removeSocketFile(socketPath);
    try {
      if (await _ipcInfoFile.exists()) await _ipcInfoFile.delete();
    } catch (_) {}
  }

  /// 给所有已握手的会话推一条事件。面板不认识的事件自行忽略。
  void broadcast(String event, [Map<String, Object?> payload = const {}]) {
    if (_sessions.isEmpty) return;
    final line = encodeLine({'e': event, 'p': payload});
    for (final s in _sessions.toList()) {
      s.sendRaw(line);
    }
  }

  /// 用户在托盘点了"设置"：
  ///   - 已有面板连着 → 推 `activate`（面板自己提到前台）
  ///   - 没有 → 启动面板进程（把 socket 路径与 token 递过去）
  /// 返回是否"叫到了"面板（用来决定要不要提示用户找不到面板）。
  Future<bool> launchOrActivate() async {
    if (hasPanel) {
      broadcast(PanelEvent.activate);
      return true;
    }
    for (final exe in panelExeCandidates) {
      if (!await File(exe).exists()) continue;
      try {
        await Process.start(
          exe,
          ['--socket', socketPath, '--token', token],
          mode: ProcessStartMode.detached,
        );
        Log.i('panel', '已启动面板 $exe');
        _missingPanelLogged = false;
        return true;
      } catch (e) {
        Log.w('panel', '启动面板失败 $exe：$e');
      }
    }
    if (!_missingPanelLogged) {
      _missingPanelLogged = true;
      Log.w('panel',
          '没有找到原生面板程序，回落到 Flutter 面板（找过：${panelExeCandidates.join(' / ')}）');
    }
    return false;
  }

  // ------------------------------------------------------------------
  // 会话
  // ------------------------------------------------------------------

  void _onClient(Socket socket) {
    final session = _PanelSession(this, socket);
    _sessions.add(session);
    Log.d('panel', '面板连接接入（当前 ${_sessions.length} 个）');
    session.start();
  }

  void _removeSession(_PanelSession s) {
    if (_sessions.remove(s)) {
      Log.d('panel', '面板断开（剩 ${_sessions.length} 个）');
    }
  }

  int nextSeq() => ++_seq;
}

/// 一个连接：读行 → 校验握手 → 分发 → 回响应。
class _PanelSession {
  _PanelSession(this.service, this.socket);

  final PanelService service;
  final Socket socket;

  bool _authed = false;
  String _tail = '';

  /// 请求串行处理：设置类操作要落盘、要重新布局，并发跑没有好处且容易乱序。
  Future<void> _chain = Future.value();

  void start() {
    socket.listen(
      (data) => _onData(data),
      onError: (Object e) {
        Log.d('panel', '会话出错：$e');
        _close();
      },
      onDone: _close,
      cancelOnError: true,
    );
  }

  void _onData(List<int> data) {
    _tail += utf8.decode(data, allowMalformed: true);
    while (true) {
      final i = _tail.indexOf('\n');
      if (i < 0) break;
      final line = _tail.substring(0, i);
      _tail = _tail.substring(i + 1);
      final msg = decodeLine(line);
      if (msg == null) {
        sendError(null, PanelErrorCode.badRequest, '不是合法的 JSON 行');
        continue;
      }
      _chain = _chain.then((_) => _handle(msg));
    }
  }

  Future<void> _handle(Map<String, Object?> msg) async {
    final id = msg['id'];
    final method = msg['m'];
    final params = (msg['p'] as Map?)?.cast<String, Object?>() ?? const {};

    if (method is! String) {
      sendError(id, PanelErrorCode.badRequest, '缺少方法名 m');
      return;
    }

    // 握手：必须第一条，且版本/token 都对
    if (!_authed) {
      if (method != PanelMethod.hello) {
        sendError(id, PanelErrorCode.noHandshake, '第一条消息必须是 hello');
        await close();
        return;
      }
      final protocol = params['protocol'];
      final token = params['token'];
      if (protocol != kPanelProtocolVersion) {
        sendError(id, PanelErrorCode.badVersion,
            '协议版本不匹配：核心 v$kPanelProtocolVersion，面板 v$protocol');
        await close();
        return;
      }
      if (token != service.token) {
        sendError(id, PanelErrorCode.badToken, 'token 不对');
        await close();
        return;
      }
      _authed = true;
      send({
        'id': id,
        'ok': true,
        'r': {
          'protocol': kPanelProtocolVersion,
          'core': {
            'version': service.host.appVersion,
            'displayVersion': service.host.displayVersion,
          },
        },
      });
      Log.i('panel', '面板已握手（v$kPanelProtocolVersion）');
      return;
    }

    try {
      final r = await service.dispatch.handle(method, params);
      send({'id': id, 'ok': true, 'r': r});
      // 状态类操作回完响应再广播，面板不会在自己的请求回包之前收到事件
      _broadcastFor(method);
    } on PanelError catch (e) {
      sendError(id, e.code, e.msg);
    } catch (e) {
      Log.w('panel', '处理 $method 出错：$e');
      sendError(id, PanelErrorCode.internal, '$e');
    }
  }

  /// 哪些方法会改变状态 → 回包后广播，其他面板/CLI 立刻看到新状态。
  void _broadcastFor(String method) {
    switch (method) {
      case PanelMethod.cardsAdd:
      case PanelMethod.cardsRemove:
      case PanelMethod.cardsSetSize:
      case PanelMethod.cardsSetSetting:
        service.broadcast(PanelEvent.cardsChanged);
      case PanelMethod.settingsSet:
        service.broadcast(PanelEvent.settingsChanged);
    }
  }

  void send(Map<String, Object?> msg) => sendRaw(encodeLine(msg));

  void sendRaw(String line) {
    try {
      socket.write(line);
    } catch (_) {
      // 对端已经走了，等 onDone/onError 收尾
    }
  }

  void sendError(Object? id, String code, String msg) {
    send({
      'id': id,
      'ok': false,
      'err': {'code': code, 'msg': msg},
    });
  }

  Future<void> close() async {
    try {
      await socket.flush();
    } catch (_) {}
    _close();
  }

  void _close() {
    try {
      socket.destroy();
    } catch (_) {}
    service._removeSession(this);
  }
}

/// 尽力删掉 socket 文件。删不掉不算错——start() 里还会再试一次，
/// 而且真删不掉的话 bind 会自己报错，日志里看得到。
Future<void> _removeSocketFile(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}

String _randomToken() {
  final r = Random.secure();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}
