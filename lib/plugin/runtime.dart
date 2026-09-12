/// 全体卡片共享一个 QuickJS 运行时。
///
/// 2026-09 起，从"一卡一实例"改为共享 + 命名空间隔离。原因：一个 QuickJS
/// 实例的固有成本（解释器、内建对象、引导脚本）远大于插件实际要存的数据，
/// 5 个实例就是白付 5 份；实测共享后私有内存明显下降。
///
/// 隔离怎么保：每个插件拿到一份**私有的** lw API（`__lwCreate(key)` 产出的
/// 闭包，pending/timers/handlers/impl/ctx 全在里面），源码被包进 IIFE，
/// `lw`/`sendMessage`/`setTimeout` 等全局一律被参数遮蔽——插件用 `var` 声明
/// 的东西出不了自己的 IIFE。消息出站时带 `__lw: key` 标签，宿主据此路由回
/// 对应的 [PluginRuntime]。
///
/// 共享后的边界（必须如实说明）：
///   - 全局作用域物理上只有一个，插件用**隐式全局**（不带 var 的赋值）仍会
///     漏出去；内置 5 个插件没有这种写法，第三方插件靠文档约束；
///   - 一个插件死循环会堵住共享的微任务队列。这跟旧方案对 UI 的影响相同
///     （JS 跑在主 isolate），失控检测（[_PluginRuntime._guard]）也仍然生效。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import '../core/logger.dart';
import 'manifest.dart';
import 'prelude.dart';
import 'sdk.dart';

typedef HostCall = Future<Object?> Function(String method, Map<String, Object?> args);

/// 共享运行时 + 客户端路由表。
///
/// 最后一个插件注销时整个运行时会被 dispose，下次挂载再重建——
/// 全空的运行时没有理由常驻。
class _JsBus {
  static JavascriptRuntime? _rt;
  static final Map<String, PluginRuntime> _clients = {};
  static bool _wired = false;

  static JavascriptRuntime acquire() {
    final rt = _rt ??= getJavascriptRuntime(xhr: false);
    if (!_wired) {
      _wired = true;
      rt.onMessage('lw', _dispatch);
    }
    return rt;
  }

  static void register(String key, PluginRuntime client) => _clients[key] = client;

  static void unregister(String key) {
    _clients.remove(key);
    if (_clients.isEmpty) {
      // 全空了：引擎和内建对象的成本不值得为"也许会有下一个插件"常驻
      _rt?.dispose();
      _rt = null;
      _wired = false;
    }
  }

  /// 消息按 __lw 标签路由。标签对不上的（插件已卸载/失控）直接丢弃——
  /// 和旧方案里 _dead 检查的语义一致。
  static void _dispatch(dynamic args) {
    Map<String, Object?>? msg;
    if (args is String) {
      try {
        msg = (jsonDecode(args) as Map).cast<String, Object?>();
      } catch (_) {}
    } else if (args is Map) {
      msg = args.cast<String, Object?>();
    }
    if (msg == null) return;
    final client = _clients[msg['__lw']];
    if (client == null) return;
    client.receive(msg);
    pump();
  }

  /// QuickJS 的 Promise 靠宿主推动微任务队列，不 pump 的话 await 永远不返回
  static void pump() {
    final rt = _rt;
    if (rt == null) return;
    var guardCount = 0;
    while (rt.executePendingJob() > 0 && guardCount++ < 1000) {}
  }
}

class PluginRuntime {
  PluginRuntime({
    required this.manifest,
    required this.source,
    required this.instanceId,
    required this.host,
    this.sdk,
    this.appVersion = '',
    this.pluginDir = '',
  }) : key = _sanitizeKey('${manifest.id}.$instanceId');

  final PluginManifest manifest;
  final String source;
  final String instanceId;

  /// 宿主能力（storage / http / 面板等）由外部注入，运行时本身不碰 IO
  final HostCall host;

  /// 本插件的 SDK 对象（可选，由 PluginCardBody 注入）
  PluginSdk? sdk;

  /// 应用版本号（传给插件的 onLoad / ctx.appVersion）
  String appVersion = '';

  /// 插件目录路径（传给插件的 onLoad / ctx.pluginDir）
  String pluginDir = '';

  /// 本实例在共享运行时里的全局命名空间键（已消毒，可安全拼进 JS）
  final String key;

  String? _gref; // "globalThis['__lw_<key>']" 的缓存形态

  /// 本实例的 Dart 侧定时器（JS 的 setTimeout/setInterval 真身）
  final Map<String, Timer> _timers = {};

  bool _dead = false;

  /// 已经被销毁（卡片没了）。
  ///
  /// 和 _dead 是两回事：_dead 是"插件失控了"，这个是"这张卡片不在了"。
  /// 分开的原因是善后方式不同——失控要把原因显示给用户，销毁则要求彻底闭嘴：
  /// 界面已经没了，再往 tree/error 里写就是往已 dispose 的 ValueNotifier 上写。
  bool _disposed = false;

  String? _error;

  /// 插件最近一次 render 出来的 UI 树
  final ValueNotifier<Map<String, Object?>?> tree = ValueNotifier(null);
  final ValueNotifier<String?> error = ValueNotifier(null);

  JavascriptRuntime? get _rt => _JsBus._rt;

  /// 单次 evaluate 的时间上限；超了就认为插件失控
  static const Duration kBudget = Duration(milliseconds: 800);

  static String _sanitizeKey(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return cleaned.isEmpty ? 'p' : cleaned;
  }

  Future<void> mount({
    required Map<String, Object?> settings,
    required double w,
    required double h,
    required int cols,
    required int rows,
    String? themeAccent,
  }) async {
    // 挂载耗时是启动慢的头号嫌疑：插件多起来之后，这里的累计时间直接决定
    // 启动幕布挂多久。逐个记下来，慢的那个一眼就能挑出来。
    final sw = Stopwatch()..start();
    try {
      final rt = _JsBus.acquire();
      _JsBus.register(key, this);
      _gref = "globalThis['__lw_$key']";

      // 时区偏移与引导脚本对整个运行时只装一次（幂等：重复 evaluate 结果相同）
      final tz = DateTime.now().timeZoneOffset.inMilliseconds;
      _guard(() => rt.evaluate('globalThis.__LW_TZ_MS = $tz;'));
      _guard(() => rt.evaluate('if (!globalThis.__lwCreate) { $kPrelude }'));

      // 一份私有的 lw API 挂到自己的命名空间
      _guard(() => rt.evaluate('$_gref = globalThis.__lwCreate(\'$key\');'));

      // 源码包进 IIFE：lw / sendMessage / 定时器全家都被参数遮蔽成
      // 本实例私有的实现，插件用 var/const 声明的东西出不了这个闭包
      _guard(() => rt.evaluate(_wrappedSource(),
          sourceUrl: '${manifest.id}/index.js'));

      final ctx = jsonEncode({
        'id': manifest.id,
        'instanceId': instanceId,
        'manifest': manifest.toJson(),
        'settings': settings,
        'size': {'w': w, 'h': h},
        'grid': {'cols': cols, 'rows': rows},
        'theme': {'accent': themeAccent},
        'appVersion': appVersion,
        'pluginDir': pluginDir,
      });
      _guard(() => rt.evaluate('$_gref.__mount($ctx);'));
      _JsBus.pump();
      sw.stop();
      Log.d('plugin',
          '${manifest.id} 挂载完成 $instanceId（${sw.elapsedMilliseconds}ms）');
    } catch (e) {
      sw.stop();
      _fail('插件挂载失败：$e');
    }
  }

  /// 把插件源码包进 IIFE。全局 shadows 一律取自本实例的 lw API：
  /// 定时器句柄留在自己的闭包里，卸载时统一回收才成立。
  String _wrappedSource() {
    return '(function (lw, sendMessage, setTimeout, setInterval, clearTimeout,'
        ' clearInterval) {\n'
        '$source\n'
        '})($_gref, $_gref.__send, $_gref.setTimeout, $_gref.setInterval,'
        ' $_gref.clearTimer, $_gref.clearTimer);\n';
  }

  /// 总线派发过来的消息入口（_JsBus._dispatch 按 __lw 标签调进来）
  void receive(Map<String, Object?> msg) {
    if (_dead || _disposed) return;
    _handleCall(msg);
  }

  /// 所有进入 JS 的调用都过这里：记录耗时、捕获异常、失控后不再派发
  ///
  /// 销毁之后一律不进：卡片重建时（改设置、装插件后重扫）实例会被卸载，
  /// 而那一刻插件可能还有 HTTP 请求在飞。请求回来时若照旧往下走，共享运行时
  /// 的路由表里已经没有自己，解引用就抛"Null check operator used on a null
  /// value"——日志里会冒出一条"插件抛出异常"，看着像插件的错，其实是我们
  /// 自己在拆掉的房子里开灯。
  JsEvalResult? _guard(JsEvalResult Function() body) {
    if (_dead || _disposed || _rt == null) return null;
    final sw = Stopwatch()..start();
    try {
      final r = body();
      if (r.isError) {
        _fail('插件报错：${r.stringResult}');
        return r;
      }
      return r;
    } catch (e) {
      _fail('插件抛出异常：$e');
      return null;
    } finally {
      sw.stop();
      if (sw.elapsed > kBudget) {
        _fail('插件执行超时（${sw.elapsedMilliseconds}ms），已停止调度');
      }
    }
  }

  Future<void> _handleCall(Map<String, Object?> msg) async {
    if (_dead || _disposed) return;
    final method = msg['method'] as String? ?? '';
    final args = (msg['args'] as Map?)?.cast<String, Object?>() ?? const {};
    final cb = msg['cb'] as String?;

    // render 是最高频的一条，单独短路
    if (method == 'render') {
      final t = msg['args'];
      tree.value = t is Map ? t.cast<String, Object?>() : null;
      return;
    }

    if (method == 'timer.set') {
      _setTimer(args);
      return;
    }
    if (method == 'timer.clear') {
      _timers.remove(args['id'])?.cancel();
      return;
    }

    Object? result;
    try {
      result = await host(method, args);
    } catch (e) {
      result = {'ok': false, 'error': '$e'};
    }
    // host 调用是异步的，等它回来时这张卡片可能已经没了（改设置、装插件后重扫
    // 都会重建卡片）。再往下走就是对着已销毁的实例说话。
    if (_disposed || _dead) return;
    if (cb != null) {
      _guard(() =>
          _rt!.evaluate('$_gref.__resolve(${jsonEncode(cb)}, ${jsonEncode(result)});'));
      _JsBus.pump();
    }
  }

  void _setTimer(Map<String, Object?> args) {
    final id = args['id'] as String?;
    if (id == null) return;
    final ms = (args['ms'] as num?)?.toInt() ?? 0;
    final repeat = args['repeat'] == true;
    _timers.remove(id)?.cancel();
    void fire() {
      if (_dead) return;
      _guard(() => _rt!.evaluate('$_gref.__timer(${jsonEncode(id)});'));
      _JsBus.pump();
    }

    _timers[id] = repeat
        ? Timer.periodic(Duration(milliseconds: ms), (_) => fire())
        : Timer(Duration(milliseconds: ms), () {
            _timers.remove(id);
            fire();
          });
  }

  /// 声明式 UI 里的事件回到 JS
  void dispatchEvent(String handlerId, Map<String, Object?> payload) {
    _guard(() =>
        _rt!.evaluate('$_gref.__event(${jsonEncode(handlerId)}, ${jsonEncode(payload)});'));
    _JsBus.pump();
  }

  void notifySettings(Map<String, Object?> settings) {
    _guard(() => _rt!.evaluate('$_gref.__settings(${jsonEncode(settings)});'));
    _JsBus.pump();
  }

  void notifyResize(double w, double h, int cols, int rows) {
    _guard(() => _rt!.evaluate('$_gref.__resize($w, $h, $cols, $rows);'));
    _JsBus.pump();
  }

  /// "莫奈取色"实时变化时推给插件，跟 notifyResize 是同一套思路——
  /// mount 时给过一次初始值，这里是壁纸换了之后的后续更新。
  /// accent 为 null 表示用户关掉了取色开关，插件应该退回自己写死的颜色。
  void notifyTheme(String? accent) {
    _guard(() => _rt!.evaluate('$_gref.__theme(${jsonEncode(accent)});'));
    _JsBus.pump();
  }

  void _fail(String message) {
    // 已经销毁的运行时不该再报错：界面早没了，tree/error 也已经 dispose，
    // 这时候写进去既没人看得到，还会往已释放的对象上写。
    if (_disposed) return;
    // 插件一旦失控就再也不调度了，界面上只剩一个错误框。不记下来的话，
    // 用户报"组件不动了"时无从查起 —— 是崩了、超时了、还是清单写错了。
    if (!_dead) Log.e('plugin', '${manifest.id}($instanceId) $message');
    _dead = true;
    _error = message;
    error.value = message;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  String? get failure => _error;

  void dispose() {
    if (_disposed) return;
    // 先置位再拆：拆的过程中如果有异步回调回来，上面那几处判断能拦住它
    _disposed = true;
    if (!_dead && _rt != null) {
      try {
        _rt!.evaluate('$_gref.__unmount();');
        // 释放自己在共享全局里的命名空间，JS 侧的闭包才能被 GC 收走
        _rt!.evaluate('try { delete globalThis[\'__lw_$key\']; } catch (_) {}');
        _JsBus.pump();
      } catch (_) {}
    }
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _JsBus.unregister(key);
    sdk?.dispose();
    tree.dispose();
    error.dispose();
  }
}
