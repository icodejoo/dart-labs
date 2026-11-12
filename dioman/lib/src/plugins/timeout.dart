import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// 宿主上报的网络档位；插件不探测网络，也不负责离线排队。
enum NetworkQuality {
  /// 强连接。
  excellent,

  /// 普通移动网络。
  good,

  /// 弱连接。
  poor,

  /// 无连接，仍作为普通配置档位处理。
  none,
}

/// 某档的超时；null 保留请求已有值。
class DiomanTimeouts {
  /// [connect]、[receive]、[send] 分别覆盖三个 Dio 超时，例如 `DiomanTimeouts(receive: Duration(seconds: 2))`。
  const DiomanTimeouts({this.connect, this.receive, this.send});

  /// 连接超时。
  final Duration? connect;

  /// 接收超时。
  final Duration? receive;

  /// 发送超时。
  final Duration? send;
}

/// 请求级超时配置，按档位取并集，单档整体替换。
class DiomanTimeoutOptions {
  /// [enabled] 为 false 时保留原配置，[timeouts] 只覆盖列出的档位。
  const DiomanTimeoutOptions({this.enabled, this.timeouts});

  /// 本次开关。
  final bool? enabled;

  /// 本次覆盖的档位。
  final Map<NetworkQuality, DiomanTimeouts>? timeouts;
}

/// 通过 next(patch) 写超时字段，实际计时交给 Dio。
class DiomanTimeout<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// [probe] 每请求同步求值一次，例如 `DiomanTimeout(probe: () => NetworkQuality.good)`。
  const DiomanTimeout(
      {required this.probe,
      this.timeouts = defaultTimeouts,
      this.enabled = true});

  /// 当前档位提供器，抛错按 bug 原样落定。
  final NetworkQuality Function() probe;

  /// 档位配置。
  final Map<NetworkQuality, DiomanTimeouts> timeouts;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:timeout';

  /// 请求级 bool 或 DiomanTimeoutOptions 键。
  static final option = DiomanOptionKey<DiomanTimeoutOptions>(pluginName);

  /// excellent 与 none 的默认连接时长。
  static const defaultConnect = Duration(seconds: 10);

  /// 旧版默认值：仅写连接超时。
  static const defaultTimeouts = {
    NetworkQuality.excellent: DiomanTimeouts(connect: defaultConnect),
    NetworkQuality.good: DiomanTimeouts(connect: Duration(seconds: 15)),
    NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 30)),
    NetworkQuality.none: DiomanTimeouts(connect: defaultConnect),
  };

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 请求整形阶段。
  @override
  DiomanStage get stage => DiomanStage.prepare;

  /// 复制配置映射，实例不共享可变状态。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) =>
      _Timeout<R>(probe, DiomanTimeoutOptions(timeouts: Map.of(timeouts)));
}

/// 每客户端的预合并配置。
class _Timeout<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> {
  /// 保存配置与档位回调。
  _Timeout(this.probe, this.base);

  /// 档位回调。
  final NetworkQuality Function() probe;

  /// 基础配置。
  final DiomanTimeoutOptions base;

  /// 缺档直接放行；null 字段保持原值。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) {
    final o = resolveOption<DiomanTimeoutOptions>(
        ctx.request.call.options[DiomanTimeout.option],
        base: base,
        merge: (a, b) => DiomanTimeoutOptions(
            enabled: b.enabled, timeouts: {...a.timeouts!, ...?b.timeouts}));
    if (o == null || o.enabled == false) return next();
    final t = o.timeouts![probe()];
    if (t == null) return next();
    return next(RequestPatch(
        connectTimeout: t.connect ?? ctx.request.connectTimeout,
        receiveTimeout: t.receive ?? ctx.request.receiveTimeout,
        sendTimeout: t.send ?? ctx.request.sendTimeout));
  }
}
