/// 内置组件的运行上下文。
///
/// 原来这层叫 PluginHost：插件在 JS 里通过 lw.call 请求宿主能力，宿主一个
/// switch 分发。组件内置化之后不再有跨语言调用，这层变成组件直接持有的
/// 一个对象——但能力集合与语义一字未改（同一个 storage 键、同一套 HTTP
/// 头白名单、同一个 SMTC 快照形状），保证存量数据与行为完全延续。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_version.dart';
import '../core/logger.dart';
import '../core/grid.dart';
import '../model/card.dart';
import '../native/native_bridge.dart';
import '../store/store.dart';
import '../widgets/images.dart';

/// 组件 HTTP 共享客户端：进程级复用连接池。
final http.Client _widgetHttp = http.Client();

class WidgetContext {
  WidgetContext({
    required this.store,
    required this.card,
    required this.pluginId,
    required this.onRequestSize,
    required this.onOpenSettings,
    required this.settings,
    required this.grid,
    required this.size,
    this.themeAccent,
  });

  final Store store;
  final WidgetCard card;
  final String pluginId;
  final void Function(String size) onRequestSize;
  final void Function() onOpenSettings;

  /// 由卡片按默认值 + 用户设置合成；面板里改设置后整体替换
  Map<String, Object?> settings;
  GridSize grid;
  Size size;
  String? themeAccent;

  /// 组件最近一次渲染出的 Flutter Widget（原生通道）。
  ///
  /// 历史上这层还有一条 JSON 树协议（组件产出 Map，NodeView 解释）——
  /// 当初为 QuickJS 插件而设。插件系统移除后五个组件已全部迁到原生
  /// 通道，协议与解释器随之删除。
  final ValueNotifier<Widget?> widget = ValueNotifier(null);

  /// 动画开关（卡片侧的"动画效果"设置）。由卡片在构建时推入，与
  /// [themeAccent] 同一手法：组件在下次重绘时读到新值。
  bool animate = true;

  final Map<String, Timer> _timers = {};
  int _timerSeq = 0;
  final List<void Function()> _cleanups = [];

  /// 在途网络请求的超时定时器（unmount 时统一取消）
  final Set<Timer> _netTimeouts = {};
  bool _alive = true;

  /// 卡片销毁后，在途的异步回调（网络请求回来、定时器最后一跳）仍会调用
  /// renderWidget()——置 dead 后变成空操作，不会写已释放的 notifier。
  void renderWidget(Widget w) {
    if (!_alive) return;
    widget.value = w;
  }

  // ---- 定时器：真实 Timer，卸载时统一回收 ----

  String _setTimer(void Function() fn, int ms, bool repeat) {
    final id = 't${++_timerSeq}';
    Log.d('widgets', '定时器+ $pluginId/$id ${ms}ms repeat=$repeat');
    if (repeat) {
      _timers[id] = Timer.periodic(Duration(milliseconds: ms), (_) => fn());
    } else {
      _timers[id] = Timer(Duration(milliseconds: ms), () {
        _timers.remove(id);
        fn();
      });
    }
    return id;
  }

  String interval(void Function() fn, int ms) => _setTimer(fn, ms, true);
  String timeout(void Function() fn, int ms) => _setTimer(fn, ms, false);
  void clearTimer(String id) {
    if (_timers.remove(id) != null) {
      Log.d('widgets', '定时器- $pluginId/$id');
    }
  }
  void onCleanup(void Function() fn) => _cleanups.add(fn);

  /// 卸载：倒序跑 cleanup，再掐掉所有定时器。
  /// 之后 renderWidget 变成空操作（在途回调的兜底）。
  /// 幂等：重复调用只生效一次（配置窗口"按内容构建、切页即销毁"的路径下
  /// 控制器与卡片可能各喊一次，timer 表已空，绝不能碰已 dispose 的 notifier）。
  bool _disposed = false;
  void unmount() {
    if (_disposed) return;
    _disposed = true;
    _alive = false;
    for (var i = _cleanups.length - 1; i >= 0; i--) {
      try {
        _cleanups[i]();
      } catch (_) {}
    }
    _cleanups.clear();
    for (final t in _timers.values) {
      Log.d('widgets', '定时器- $pluginId (unmount 批量)');
      t.cancel();
    }
    _timers.clear();
    for (final t in _netTimeouts) {
      t.cancel();
    }
    _netTimeouts.clear();
    widget.dispose();
  }

  // ---- 宿主能力（原 PluginHost 的能力层，语义一字未改）----

  /// 实例私有键：同一组件的不同卡片各存各的
  String _localKey(String key) => '@inst:${card.id}:$key';

  Object? storageGet(String key, [Object? fallback]) =>
      store.nsGet(pluginId, key, fallback);
  void storageSet(String key, Object? value) =>
      store.nsSet(pluginId, key, value);
  Object? storageGetLocal(String key, [Object? fallback]) =>
      store.nsGet(pluginId, _localKey(key), fallback);
  void storageSetLocal(String key, Object? value) =>
      store.nsSet(pluginId, _localKey(key), value);
  Future<Object?> cacheGet(String key) => store.cacheGet(pluginId, key);
  Future<void> cacheSet(String key, Object? value) =>
      store.cacheSet(pluginId, key, value);

  Future<Map<String, Object?>> httpGetJSON(String url,
          {Map<String, Object?>? headers}) async =>
      _wrapJson(await _fetch(url, headers));

  Future<Map<String, Object?>> httpGetText(String url,
          {Map<String, Object?>? headers}) async =>
      _wrapText(await _fetch(url, headers));

  Future<Map<String, Object?>> mediaState() => _mediaState();

  Future<Map<String, Object?>> mediaControl(String cmd, {int posMs = 0}) async {
    final r = await NativeBridge.smtcControl(cmd, posMs: posMs);
    return {'ok': true, 'data': r};
  }

  void requestSize(String s) => onRequestSize(s);
  void openSettings() => onOpenSettings();

  void toast(String message) {
    // 目前只落日志。真正的 toast UI 等面板做好再接。
    Log.i('widgets', '$pluginId: $message');
  }

  Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    try {
      await launchUrl(uri);
      Log.i('widgets', '$pluginId 打开外部链接 ${uri.host}${uri.path}');
      return true;
    } catch (e) {
      Log.w('widgets', '$pluginId 打开外部链接失败 ${uri.host}: $e');
      return false;
    }
  }

  /// launcher 之类快捷启动的落点：启动本地程序。openExternal 只放行
  /// http/https，本地路径走这条路，白名单收得和 pickFile 的 ext 过滤一致。
  static const _launchExtWhitelist = {'exe', 'lnk', 'bat', 'cmd', 'msc'};

  /// 盘符路径（C:\ 或 C:/）或 UNC（\\server\share）才算绝对路径。
  static final _winAbsPathRe = RegExp(r'^(?:[a-zA-Z]:[\\/]|\\\\)');

  Future<bool> launch(String path) async {
    if (!_winAbsPathRe.hasMatch(path)) return false;
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    if (!_launchExtWhitelist.contains(ext)) return false;
    try {
      final ok = await NativeBridge.launchApp(path);
      if (!ok) return false;
      Log.i('widgets', '$pluginId 启动程序 $path');
      return true;
    } catch (e) {
      Log.w('widgets', '$pluginId 启动异常 $path: $e');
      return false;
    }
  }

  Future<String?> pickFile({String title = '选择文件', List<String> ext = const []}) =>
      NativeBridge.pickFile(title: title, ext: ext);

  // ---- 内部实现（与原 PluginHost 逐行对应）----

  /// 正在播放的媒体状态（SMTC）。
  ///
  /// 顺手把封面解码进图片缓存：组件只会拿到 artKey 这个字符串，
  /// 永远碰不到字节。
  Future<Map<String, Object?>> _mediaState() async {
    try {
      final s = await NativeBridge.smtcState();
      if (s == null) return {'ok': false, 'error': '取不到媒体状态'};

      final artId = (s['artId'] as num?)?.toInt() ?? 0;
      final available = s['available'] == true;
      String? artKey;
      if (available && artId > 0) {
        final key = 'smtc:$artId';
        if (WidgetImages.has(key)) {
          artKey = key;
        } else {
          final bytes = await NativeBridge.smtcArt(artId);
          if (bytes != null && await WidgetImages.decodeAndPut(key, bytes)) {
            artKey = key;
          }
        }
      }
      return {'ok': true, 'data': {...s, 'artKey': artKey}};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<Map<String, Object?>> _wrapJson(Map<String, Object?>? res) async {
    if (res == null) return {'ok': false, 'error': '只允许 http/https'};
    if (res['ok'] != true) return res;
    try {
      return {'ok': true, 'data': jsonDecode(res['text'] as String)};
    } catch (e) {
      Log.w('widgets', 'JSON 解析失败: $e');
      return {'ok': false, 'error': '响应不是合法 JSON'};
    }
  }

  Future<Map<String, Object?>> _wrapText(Map<String, Object?>? res) async {
    if (res == null) return {'ok': false, 'error': '只允许 http/https'};
    if (res['ok'] != true) return res;
    return {'ok': true, 'data': res['text'] as String};
  }

  /// 共用请求骨架：URL 校验、头白名单、日志留痕、超时。
  /// 超时定时器登记在 [_netTimeouts] 里，unmount 时统一取消——
  /// 组件测试环境下（假时钟）挂着的 Timer 会让测试不变式炸掉。
  Future<Map<String, Object?>?> _fetch(
      String url, Map<String, Object?>? extraHeaders) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return {'ok': false, 'error': '只允许 http/https'};
    }
    const allowed = {'user-agent', 'referer', 'accept', 'accept-language'};
    final headers = <String, String>{'User-Agent': appUserAgent};
    if (extraHeaders != null) {
      for (final e in extraHeaders.entries) {
        if (allowed.contains(e.key.toLowerCase())) {
          headers[e.key] = '${e.value}';
        }
      }
    }
    final target = '${uri.host}${uri.path}';
    Log.d('widgets', '$pluginId 请求 $target');
    final sw = Stopwatch()..start();
    final completer = Completer<http.Response>();
    final timeout = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('请求超时（15s）'));
      }
    });
    _netTimeouts.add(timeout);
    _widgetHttp.get(uri, headers: headers).then((res) {
      if (!completer.isCompleted) completer.complete(res);
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    });
    try {
      final res = await completer.future;
      timeout.cancel();
      sw.stop();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        Log.w('widgets',
            '$pluginId 请求返回 ${res.statusCode} $target（${sw.elapsedMilliseconds}ms）');
        return {'ok': false, 'error': 'HTTP ${res.statusCode}'};
      }
      Log.i('widgets',
          '$pluginId 请求成功 $target ${res.bodyBytes.length}B（${sw.elapsedMilliseconds}ms）');
      return {'ok': true, 'text': utf8.decode(res.bodyBytes)};
    } catch (e) {
      timeout.cancel();
      sw.stop();
      Log.w('widgets', '$pluginId 请求失败 $target（${sw.elapsedMilliseconds}ms）: $e');
      return {'ok': false, 'error': '请求失败：${uri.host}'};
    } finally {
      _netTimeouts.remove(timeout);
    }
  }
}
