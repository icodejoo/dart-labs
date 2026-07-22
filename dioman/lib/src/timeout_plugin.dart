import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Coarse network-quality tiers a host app reports to [DiomanTimeout], which
/// maps each to its own set of timeouts. Deliberately coarse — the plugin
/// never measures anything itself (it's pure Dart, no Flutter / no
/// connectivity detection); the host classifies and reports.
///
/// 宿主app上报给[DiomanTimeout]的粗粒度网络质量档位，插件为每一档映射一套
/// 超时。刻意做粗——插件自己从不测量任何东西（纯Dart，无Flutter/无连通性
/// 检测）；由宿主负责分类并上报。
enum NetworkQuality {
  /// Strong connection (e.g. WiFi / ethernet).
  ///
  /// 强连接（如WiFi/以太网）。
  excellent,

  /// Decent mobile connection (e.g. 4G).
  ///
  /// 尚可的移动连接（如4G）。
  good,

  /// Weak connection (e.g. 3G / 2G) — usually wants longer timeouts.
  ///
  /// 弱连接（如3G/2G）——通常需要更长的超时。
  poor,

  /// No usable connectivity. Just another tier here — fail-fast / offline
  /// queueing is deliberately out of scope (a future offline plugin's job).
  ///
  /// 无可用连接。这里只当作普通一档——fail-fast/断网入队刻意不在本插件范围内
  /// （交给将来的断网插件）。
  none,
}

/// One tier's timeout overrides. Every field is nullable: a `null` field is
/// **left untouched**, preserving whatever the request already carries (from
/// [BaseOptions] or the caller's own [Options]). Only non-null fields are
/// written onto the request.
///
/// 某一档的超时覆盖。每个字段都可空：`null`的字段**保持不动**，沿用请求本身
/// 已带的值（来自[BaseOptions]或调用方自己的[Options]）。只有非null字段才会
/// 写到请求上。
class DiomanTimeouts {
  /// Creates a tier's timeout set; omit any field to leave that timeout alone.
  ///
  /// 创建某一档的超时集合；省略任一字段即保持该超时不变。
  ///
  /// @param connect Overrides [RequestOptions.connectTimeout] when non-null.
  ///
  ///   非null时覆盖[RequestOptions.connectTimeout]。
  ///
  /// @param receive Overrides [RequestOptions.receiveTimeout] when non-null.
  ///
  ///   非null时覆盖[RequestOptions.receiveTimeout]。
  ///
  /// @param send Overrides [RequestOptions.sendTimeout] when non-null.
  ///
  ///   非null时覆盖[RequestOptions.sendTimeout]。
  const DiomanTimeouts({this.connect, this.receive, this.send});

  /// Overrides `connectTimeout`; `null` leaves it untouched.
  ///
  /// 覆盖`connectTimeout`；`null`则不动。
  final Duration? connect;

  /// Overrides `receiveTimeout`; `null` leaves it untouched.
  ///
  /// 覆盖`receiveTimeout`；`null`则不动。
  final Duration? receive;

  /// Overrides `sendTimeout`; `null` leaves it untouched.
  ///
  /// 覆盖`sendTimeout`；`null`则不动。
  final Duration? send;
}

/// Built-in default tier→timeouts map. Mirrors the common weak-network
/// pattern: stretch the connect timeout as quality drops so a request on a
/// slow link isn't killed prematurely. Only `connectTimeout` is set per tier;
/// `receive`/`send` are left untouched by default.
///
/// 内置的默认「档位→超时」映射。对齐常见弱网做法：质量越差、连接超时越长，
/// 避免慢链路上的请求过早被杀。默认每档只设`connectTimeout`；`receive`/`send`
/// 默认不动。
const Map<NetworkQuality, DiomanTimeouts> _defaultTimeouts = {
  NetworkQuality.excellent: DiomanTimeouts(connect: Duration(seconds: 10)),
  NetworkQuality.good: DiomanTimeouts(connect: Duration(seconds: 15)),
  NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 30)),
  NetworkQuality.none: DiomanTimeouts(connect: Duration(seconds: 10)),
};

/// Per-request override for [DiomanTimeout], read from `extra['dioman:timeout']`.
/// Any field left `null` falls back to the plugin-level value of the same name.
///
/// [DiomanTimeout]的单请求覆盖，从`extra['dioman:timeout']`读取。留`null`的字段
/// 各自回退到插件级同名值。
class DiomanTimeoutOptions {
  /// Creates a per-request override; every field is optional.
  ///
  /// 创建单请求覆盖；每个字段都可选。
  const DiomanTimeoutOptions({this.enabled, this.timeouts});

  /// `false` skips dynamic timeouts for this request — it keeps whatever
  /// timeouts it already carries. `null` (default) inherits
  /// [DiomanTimeout.enabled].
  ///
  /// `false`表示本次请求跳过动态超时——保留它本来带的超时。`null`（默认）沿用
  /// [DiomanTimeout.enabled]。
  final bool? enabled;

  /// Per-request tier→timeouts overrides, **merged (union) by tier** with the
  /// plugin's map — an entry here replaces that tier's entry, tiers not listed
  /// keep the plugin's default.
  ///
  /// 单请求的「档位→超时」覆盖，与插件的映射**按档合并（union）**——这里的
  /// 某档会替换该档的条目，未列出的档保留插件默认。
  final Map<NetworkQuality, DiomanTimeouts>? timeouts;
}

/// Dynamically sets each request's connect/receive/send timeouts based on the
/// current network quality reported by an injected [probe] — stretch timeouts
/// on a weak link so a request isn't killed prematurely, tighten them on a
/// strong one.
///
/// 根据注入的[probe]上报的当前网络质量，动态设置每个请求的
/// connect/receive/send超时——弱网拉长、避免请求过早被杀，强网收紧。
///
/// Pure Dart: this plugin never detects connectivity itself. The host app
/// (e.g. via `connectivity_plus`) classifies the connection into a
/// [NetworkQuality] and returns it from [probe], which is called once per
/// request in [onRequest]. Each tier maps to a [DiomanTimeouts]; only the
/// non-null fields of the matched tier are written onto the request, so a
/// partially-configured tier leaves the other timeouts as [BaseOptions] set
/// them. A tier absent from the map is a complete no-op for that request.
///
/// 纯Dart：本插件自己从不检测连通性。宿主app（如用`connectivity_plus`）把连接
/// 分类成[NetworkQuality]并从[probe]返回，[probe]在[onRequest]中每请求调用一次。
/// 每档映射到一个[DiomanTimeouts]；只有命中档的非null字段才写到请求上，所以
/// 部分配置的档会让其它超时保持[BaseOptions]的设定。映射中不存在的档对该请求
/// 完全不做处理。
///
/// Install EARLY — right after [DiomanEnvs], before everything else — since it
/// is pure per-request configuration with no request/response coupling.
///
/// 装在**最前面**——紧跟[DiomanEnvs]、在其它一切之前——因为它是纯per-request
/// 配置，与请求/响应阶段无耦合。
///
/// ```dart
/// final timeout = DiomanTimeout(
///   probe: () => myConnectivity.quality, // your NetworkQuality source
///   timeouts: {
///     NetworkQuality.poor: const DiomanTimeouts(
///       connect: Duration(seconds: 30),
///       receive: Duration(seconds: 30),
///     ),
///   },
/// );
/// dio.interceptors.add(timeout); // first, or via Dioman.install(timeout: ...)
/// ```
class DiomanTimeout extends DiomanPlugin {
  /// Creates a dynamic-timeout plugin.
  ///
  /// 创建一个动态超时插件。
  ///
  /// @param probe Returns the current [NetworkQuality]; called once per
  ///   request. Required, constructor-level only (not overridable per request).
  ///
  ///   返回当前[NetworkQuality]；每请求调用一次。必填，仅构造级
  ///   （不支持单请求覆盖）。
  ///
  /// @param timeouts Tier→timeouts map. Defaults to a weak-network-friendly
  ///   set (connect 10s/15s/30s/10s for excellent/good/poor/none).
  ///
  ///   「档位→超时」映射。默认一套弱网友好的配置（excellent/good/poor/none 的
  ///   connect 分别为 10s/15s/30s/10s）。
  ///
  /// @param enabled `false` disables the whole plugin. Defaults to `true`.
  ///
  ///   `false`时整体禁用插件。默认`true`。
  DiomanTimeout({
    required NetworkQuality Function() probe,
    this.timeouts = _defaultTimeouts,
    this.enabled = true,
  }) : _probe = probe;

  /// Reports the current network quality; called once per request. Not
  /// overridable per request — quality is an ambient property, not a per-call
  /// one.
  ///
  /// 上报当前网络质量；每请求调用一次。不支持单请求覆盖——质量是环境属性，
  /// 不是单次调用的属性。
  final NetworkQuality Function() _probe;

  /// Tier→timeouts map. Overridable (merged by tier) per request via
  /// [DiomanTimeoutOptions.timeouts].
  ///
  /// 「档位→超时」映射。可通过[DiomanTimeoutOptions.timeouts]按请求覆盖
  /// （按档合并）。
  final Map<NetworkQuality, DiomanTimeouts> timeouts;

  /// `false` disables the plugin entirely — every request keeps whatever
  /// timeouts it already carries.
  ///
  /// `false`时插件整体失效——所有请求保留它本来带的超时。
  final bool enabled;

  /// Public plugin name / extra key for this plugin, accessible without an
  /// instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:timeout';

  @override
  String get name => pluginName;

  // ── Per-request override resolution ─────────────────────────────────────────

  DiomanTimeoutOptions? _overrideObject(RequestOptions config) {
    final v = config.extra[name];
    return v is DiomanTimeoutOptions ? v : null;
  }

  bool _enabledFor(RequestOptions config) =>
      _overrideObject(config)?.enabled ?? enabled;

  /// Effective tier→timeouts map: the plugin's map, with any per-request
  /// entries merged in by tier (a per-request tier replaces that tier only).
  ///
  /// 生效的「档位→超时」映射：插件的映射，叠加按档合并进来的单请求条目
  /// （单请求的某档只替换该档）。
  Map<NetworkQuality, DiomanTimeouts> _resolveTimeouts(RequestOptions config) {
    final override = _overrideObject(config)?.timeouts;
    if (override == null) return timeouts;
    return {...timeouts, ...override};
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_enabledFor(options)) return handler.next(options);

    final t = _resolveTimeouts(options)[_probe()];
    if (t == null) return handler.next(options); // tier not configured → no-op

    // Only non-null fields are written — a null leaves the request's existing
    // timeout (from BaseOptions / the caller's Options) untouched.
    if (t.connect != null) options.connectTimeout = t.connect;
    if (t.receive != null) options.receiveTimeout = t.receive;
    if (t.send != null) options.sendTimeout = t.send;

    handler.next(options);
  }
}
