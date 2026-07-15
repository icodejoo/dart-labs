import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:stomp_dart_client/stomp_dart_client.dart';

/// 解析后的 JSON 消息（约定顶层为对象），即 `Map<String, T>`（默认 dynamic）。
typedef Dictional<T> = Map<String, T>;

/// 订阅回调收到的消息体：[jsonDecode] 能解析成功时就是解析后的实际值（`Map`/`List`/
/// `String`/`num`/`bool`/`null` 都可能，不要求顶层必须是对象）；[jsonDecode] 本身
/// 抛异常（不是合法 JSON）时，原样传回收到的原始文本字符串——不在库内部替业务猜测/
/// 丢弃这段文本，由回调自行判断怎么处理。二进制解码失败（未配置 [binaryDecoder] 或
/// 它自己抛异常）仍然视为解析失败，不传给回调（见 [ParseFailureAck]）。
typedef ParsedMessage = dynamic;

/// 订阅回调。第二参 [ack] 恒有值：仅在 [AckMode.manual] 下用于手动 ACK/NACK，
/// 其余模式为 no-op（安全忽略即可，可写 `(json, _) { ... }`）。
typedef JsonCallback = void Function(ParsedMessage json, AckControl ack);

/// 订阅的确认模式（单一字段，覆盖“不应答/自动应答/手动应答”三态）。
enum AckMode {
  /// 默认：STOMP `ack:auto`，服务端自动确认，本封装**不发**任何 ACK/NACK。
  auto,

  /// STOMP `ack:client-individual`，本封装按处理结果**自动** ACK（成功）/NACK（失败）。
  smart,

  /// STOMP `ack:client-individual`，本封装**不自动应答**，通过回调的 [AckControl] 手动 ack/nack。
  manual;

  /// SUBSCRIBE 帧的 `ack` 头值；auto 返回 null（不带该头，即 STOMP 默认 auto）。
  String? get header => switch (this) {
        AckMode.auto => null,
        AckMode.smart => 'client-individual',
        AckMode.manual => 'client-individual',
      };
}

/// 手动确认句柄，随每条消息传入回调（见 [AckMode.manual]）。
///
/// 可存起来在**回调外部、任意时刻**调用（如按业务 id 存入 Map，异步完成后再 ack）。
/// 仅在同一条连接内有效：重连后旧句柄自动失效（no-op）；重复调用幂等。
abstract interface class AckControl {
  void ack();
  void nack();
}

/// 非 manual 模式下传给回调的空实现（本封装已负责应答或无需应答）。
class _NoopAck implements AckControl {
  const _NoopAck();
  @override
  void ack() {}
  @override
  void nack() {}
}

/// manual 模式下绑定单条消息的确认句柄。
class _MessageAck implements AckControl {
  _MessageAck(this._owner, this._ackId, this._generation);

  final Stompsocket _owner;
  final String? _ackId;
  final int _generation;
  bool _used = false;

  @override
  void ack() => _send(ackIt: true);

  @override
  void nack() => _send(ackIt: false);

  void _send({required bool ackIt}) {
    if (_used || _ackId == null) return;
    // 会话已变（重连）或已断开：ack id 失效，安全 no-op
    if (_generation != _owner._generation || !_owner.client.connected) return;
    _used = true;
    if (ackIt) {
      _owner.client.ack(id: _ackId);
    } else {
      _owner.client.nack(id: _ackId);
    }
  }
}

/// 消息体解析失败时的自动确认动作（仅在 [AckMode] 非 auto 时生效）。
enum ParseFailureAck {
  /// NACK：告知服务端未处理，通常触发重投。
  /// 注意：毒消息（永远解析失败）会反复重投，依赖 broker 的重投上限/死信队列兜底。
  nack,

  /// ACK：确认并丢弃坏消息，避免反复重投导致的死循环。
  ack,
}

/// 连接状态。通过 [Stompsocket.state]（当前值）、
/// [Stompsocket.stateListenable]（Flutter 原生响应式，可喂 ValueListenableBuilder）、
/// 或 [Stompsocket.onStateChanged]（命令式回调，便于桥接 GetX 等）观察。
enum StompConnectionState {
  /// 未启动（[Stompsocket.dispose] 后是 disconnected，不回到 idle）
  idle,

  /// 正在建立首次连接
  connecting,

  /// 已连接
  connected,

  /// 已断开，正在退避等待重连
  reconnecting,

  /// 已停止（主动 dispose，或重连达上限放弃）
  disconnected,
}

/// 解析结果：`(数据, 错误信息)`。
///
/// 用 record 而非直接返回值，是为了把错误信息带出后台 isolate，
/// 由主 isolate 统一记日志（[compute] 内的 print/log 在部分平台不汇聚到主控制台）。
/// `data` 为 dynamic：可以是 Map/List/String/num/bool/null（JSON 解析结果），
/// 或收到非合法 JSON 时的原始文本，或二进制解码结果。
typedef _ParseResult = (dynamic data, String? error);

/// 负载大小阈值（字节）。
///
/// 小于等于该值时在主线程同步解析（开销极小，避免 isolate 调度成本）；
/// 大于该值时通过 [compute] 放到后台 isolate 解析，防止卡住 UI。
/// 32KB 是经验值，可按实际负载分布调整。
///
/// 注意：[compute] 每次调用会新建 isolate（启动 + 双向数据拷贝）。
/// 若出现持续高频大包，应改为常驻 isolate + SendPort 的 worker 模式，
/// 此处阈值方案只适合"偶发大包"。
const _isolateThreshold = 32 * 1024;

/// 不传 id 时按 (destination, ack, onParseError, ordered) 生成确定性归并键的前缀。
/// `\x00` 作分隔符——STOMP destination 不含空字节，与用户显式 id 不会碰撞。
const _autoDestPrefix = 'auto#dest\x00';

/// 用于未提供 onUnhandled* 回调时占位（StompConfig 要求非空）。
void _noopFrame(StompFrame _) {}

/// 解析字符串消息体（顶层函数，可被 [compute] 发送到后台 isolate）。
///
/// [jsonDecode] 成功 → 返回解析后的值（Map/List/String/num/bool/null 都可能）；
/// [jsonDecode] 抛异常 → 原样返回原始文本，交由回调自行判断——不视为解析错误。
_ParseResult _decodeStringBody(String body) {
  try {
    return (jsonDecode(body), null);
  } catch (_) {
    return (body, null); // 不是合法 JSON → 原样传回原始文本
  }
}

/// [Stompsocket.subscribe] 的返回句柄，同时提供订阅 id 与就地取消能力。
class StompSubscription {
  StompSubscription._(this.id, this._unsubscribe);

  /// 订阅 id，可用于 [Stompsocket.unsubscribe]。
  final String id;

  final void Function() _unsubscribe;

  /// 取消本次注册的回调（引用计数）：当该 id 的最后一个回调被取消时，
  /// 才向服务端发送 UNSUBSCRIBE。重复调用安全（幂等）。
  void unsubscribe() => _unsubscribe();
}

/// 单次回调注册。用独立对象持有以便按身份精确移除
/// （同一个闭包可能被注册多次）。
class _CallbackReg {
  _CallbackReg(this.cb);
  final JsonCallback cb;
}

/// 一条待发送的出站消息（未连接时暂存于发送缓冲）。
class _Outbound {
  _Outbound(this.destination, this.body, this.headers);
  final String destination;
  final Object? body;
  final Map<String, String>? headers;
}

/// 单个订阅：内部维护一个回调队列。
///
/// 同一个订阅（相同 id）收到消息时只解析一次，
/// 再把同一份解析结果分发给队列里的所有回调。
class _Subscription {
  _Subscription({
    required this.id,
    required this.destination,
    required this.ordered,
    required this.ack,
    required this.onParseError,
  });

  /// 订阅 id（服务端 SUBSCRIBE 使用的 id header）
  final String id;

  /// 订阅的 topic
  final String destination;

  /// 是否按到达顺序分发（见 [Stompsocket.subscribe] 的 ordered 参数）
  final bool ordered;

  /// ACK 模式；非 auto 时收到消息会自动 ACK/NACK
  final AckMode ack;

  /// 解析失败时自动确认动作
  final ParseFailureAck onParseError;

  /// 回调注册队列
  final List<_CallbackReg> callbacks = [];

  /// 底层 stomp 返回的取消订阅函数（连接建立后才有值）
  StompUnsubscribe? unsubscribeFn;

  /// 有序分发时的串行链尾：把异步解析串起来，保证分发顺序 == 到达顺序。
  /// 频率由后端控制，正常不会无界增长。
  Future<void> tail = Future<void>.value();
}

class Stompsocket {
  Stompsocket({
    required String url,
    // ---- 透传给 stomp_dart 的原生参数（默认值沿用库） ----
    Duration heartbeatIncoming = const Duration(seconds: 5),
    Duration heartbeatOutgoing = const Duration(seconds: 5),
    Duration? pingInterval,
    Duration connectionTimeout = Duration.zero,
    this.reconnectDelay = const Duration(seconds: 5),
    Map<String, dynamic>? webSocketConnectHeaders,
    bool useSockJS = false,
    StompFrameCallback? onUnhandledFrame,
    StompFrameCallback? onUnhandledMessage,
    StompFrameCallback? onUnhandledReceipt,
    // ---- 由本插件拦截后再转出的原生回调 ----
    this.onStompError,
    this.onWebSocketError,
    this.onWebSocketDone,
    this.onDebugMessage,
    // ---- 本插件自有能力 ----
    Map<String, String>? connectHeaders,
    Future<Map<String, String>?> Function()? beforeConnect,
    this.binaryDecoder,
    this.onParseFailure,
    this.queueWhileDisconnected = true,
    this.maxQueuedMessages = 100,
    this.resumeOnForeground = false,
    this.debug = false,
    this.onLog,
    this.onConnected,
    this.onDisconnected,
    this.onStateChanged,
  })  : _userBeforeConnect = beforeConnect,
        _url = url,
        _heartbeatIncoming = heartbeatIncoming,
        _heartbeatOutgoing = heartbeatOutgoing,
        _pingInterval = pingInterval,
        _connectionTimeout = connectionTimeout,
        _webSocketConnectHeaders = webSocketConnectHeaders,
        _useSockJS = useSockJS,
        _onUnhandledFrame = onUnhandledFrame,
        _onUnhandledMessage = onUnhandledMessage,
        _onUnhandledReceipt = onUnhandledReceipt,
        _connectHeadersInit = connectHeaders {
    if (connectHeaders != null) _connectHeaders.addAll(connectHeaders);
    client = StompClient(
      config: StompConfig(
        url: url,
        beforeConnect: _beforeConnect,
        stompConnectHeaders: _connectHeaders, // 可变引用：token 刷新后连接时读取
        webSocketConnectHeaders: webSocketConnectHeaders,
        onConnect: _onConnect,
        onDisconnect: _onDisconnect,
        onStompError: _onStompError,
        onWebSocketError: _onWebSocketError,
        onWebSocketDone: _onWebSocketDone,
        onDebugMessage: _onDebugMessage, // 帧级流水日志（仅 debug 时输出）
        onUnhandledFrame: onUnhandledFrame ?? _noopFrame,
        onUnhandledMessage: onUnhandledMessage ?? _noopFrame,
        onUnhandledReceipt: onUnhandledReceipt ?? _noopFrame,
        heartbeatIncoming: heartbeatIncoming,
        heartbeatOutgoing: heartbeatOutgoing,
        pingInterval: pingInterval,
        connectionTimeout: connectionTimeout,
        useSockJS: useSockJS,
        // 交给库做固定频率自动重连（reconnectDelay>0 时无限重试；=0 时不重连）。
        // 我们只负责重连成功后在 _onConnect 里重新订阅。
        reconnectDelay: reconnectDelay,
      ),
    );
  }

  late final StompClient client;

  /// 连接成功（含每次重连成功）后触发，重放订阅之后调用
  final void Function(StompFrame frame)? onConnected;

  /// 断开连接（STOMP DISCONNECT）后触发
  final void Function(StompFrame frame)? onDisconnected;

  /// 连接状态每次变化都会触发（命令式桥接口，GetX 可一行接入：
  /// `onStateChanged: (s) => rxState.value = s`）
  final void Function(StompConnectionState state)? onStateChanged;

  /// WebSocket 自动重连间隔（固定频率，透传给 stomp_dart）。
  /// `> 0` 启用无限固定间隔重连；`Duration.zero` 关闭自动重连。
  final Duration reconnectDelay;

  /// 服务端 STOMP ERROR 帧回调（鉴权失败、目的地非法等）。本类内部已记日志，此处额外透出。
  final void Function(StompFrame frame)? onStompError;

  /// WebSocket 层错误回调（本类同时用它触发重连）。
  final void Function(dynamic error)? onWebSocketError;

  /// WebSocket 关闭回调（本类同时用它触发重连）。
  final void Function()? onWebSocketDone;

  /// 帧级流水回调，原样透传 stomp_dart 的 onDebugMessage（与 [debug]/[onLog] 独立）。
  final void Function(String message)? onDebugMessage;

  /// 未连接时是否缓冲出站消息，连上后补发
  final bool queueWhileDisconnected;

  /// 出站缓冲上限，超出丢弃最旧
  final int maxQueuedMessages;

  /// App 回到前台（[AppLifecycleState.resumed]）时若未连接则立即重连（默认 false）。
  /// 规避 App 被系统挂起/后台时定时器暂停、连接静默失活、回前台迟迟不恢复的问题。
  /// 为 true 时需运行在已初始化 WidgetsBinding 的 Flutter App 中。
  final bool resumeOnForeground;

  /// 二进制消息体解码器：收到二进制帧时调用，返回值不做类型约束（[ParsedMessage] 即
  /// `dynamic`），下游回调自行决定怎么接受（Map/List/String 都可以）。解码失败请抛异常
  /// （会按解析失败走 [ParseFailureAck] 策略）。
  ///
  /// 大包会经 [compute] 放到后台 isolate 执行，此时该函数**必须是顶层/静态函数**
  /// （可被发送到 isolate，不能捕获实例状态）。未提供时，收到二进制消息按解析失败处理。
  final ParsedMessage Function(Uint8List bytes)? binaryDecoder;

  /// 消息体解析失败（二进制帧未配置 [binaryDecoder]、或 binaryDecoder 自己抛异常）时触发，
  /// 用于业务侧监控消息丢弃：[AckMode.auto] 下解析失败的消息不会进任何订阅回调，没有这个
  /// 钩子的话只在 debug 日志里留一条痕迹，业务完全无感知。
  final void Function(StompFrame frame, String error)? onParseFailure;

  /// 是否输出日志（主开关）。含 stomp_dart 的帧级 [onDebugMessage] 流水。
  final bool debug;

  /// 日志输出方式。[debug] 为 true 时：提供了本回调则日志走它（使用方决定如何打印/
  /// 过滤/上报），否则回退到 `dart:developer` 的 log。[debug] 为 false 时不输出任何日志。
  final void Function(String message, {Object? error, StackTrace? stackTrace})? onLog;

  final Future<Map<String, String>?> Function()? _userBeforeConnect;

  // 仅用于 [copyWith] 复现构造参数（这些参数在构造时被消费、未单独留存为公开字段）。
  final String _url;
  final Duration _heartbeatIncoming;
  final Duration _heartbeatOutgoing;
  final Duration? _pingInterval;
  final Duration _connectionTimeout;
  final Map<String, dynamic>? _webSocketConnectHeaders;
  final bool _useSockJS;
  final StompFrameCallback? _onUnhandledFrame;
  final StompFrameCallback? _onUnhandledMessage;
  final StompFrameCallback? _onUnhandledReceipt;
  final Map<String, String>? _connectHeadersInit;

  /// CONNECT 头（可变引用）。[_beforeConnect] 会在每次连接前刷新它。
  final Map<String, String> _connectHeaders = {};

  /// 所有订阅，以订阅 id 为键
  final Map<String, _Subscription> _subscriptions = {};

  /// 未连接时暂存的出站消息，连接建立后按序 flush
  final List<_Outbound> _outbox = [];

  /// 连接状态（Flutter 原生响应式：自带当前值 + 变更通知，可喂 ValueListenableBuilder）
  final ValueNotifier<StompConnectionState> _stateNotifier =
      ValueNotifier(StompConnectionState.idle);

  bool _wantConnection = false; // activate..dispose 之间为 true
  AppLifecycleListener? _lifecycle;

  /// 会话代次：每次连接成功自增；manual 模式的 [AckControl] 据此在重连后失效。
  int _generation = 0;

  // ---------------------------------------------------------------------------
  // 状态观测
  // ---------------------------------------------------------------------------

  /// 当前连接状态（同步读取）
  StompConnectionState get state => _stateNotifier.value;

  /// 连接状态的响应式监听源。用法：
  /// - Flutter：`ValueListenableBuilder(valueListenable: client.stateListenable, ...)`
  /// - GetX：`rx.value = client.state; client.stateListenable.addListener(() => rx.value = client.state);`
  ///   （或直接用 [onStateChanged] 回调，更省事）
  ValueListenable<StompConnectionState> get stateListenable => _stateNotifier;

  bool get connected => client.connected;

  void _setState(StompConnectionState s) {
    if (_stateNotifier.value == s) return;
    _stateNotifier.value = s; // 仅在变化时通知监听者
    onStateChanged?.call(s);
  }

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  /// 启动（或在 [dispose] 之后重新启动）连接。
  void activate() {
    _wantConnection = true;
    if (resumeOnForeground) {
      _lifecycle ??= AppLifecycleListener(onResume: forceReconnect);
    }
    _setState(StompConnectionState.connecting);
    client.activate();
  }

  /// 立即重连（跳过 reconnectDelay 等待），仅在"期望连接但当前未连接"时生效。
  /// 供 [resumeOnForeground] 回前台自动调用，也可在网络恢复（如 connectivity_plus）时手动调用。
  ///
  /// 注：stomp_dart 的 `deactivate()` 是同步的（当场取消重连定时器、销毁 handler），
  /// 紧跟 `activate()` 没有竞态——与 stompjs（异步 deactivate、必须 await）不同。
  void forceReconnect() {
    if (!_wantConnection || client.connected) return;
    client.deactivate();
    client.activate();
  }

  /// 断开连接（可逆的停止）：dispose 之后仍可再次 [activate] 复用本实例。
  ///
  /// - [keepSubscriptions] 为 false（默认）：清空所有订阅并释放回调引用，
  ///   避免泄漏；再次 [activate] 后需重新订阅。适合彻底停止/页面销毁。
  /// - [keepSubscriptions] 为 true：保留订阅登记，再次 [activate] 连上后会
  ///   自动重放这些订阅（pause / resume 语义）。注意回调引用会一直被持有，
  ///   若回调捕获了将被销毁的对象，请勿用此选项。
  void dispose({bool keepSubscriptions = false}) {
    _wantConnection = false;
    _lifecycle?.dispose();
    _lifecycle = null;
    if (!keepSubscriptions) clear();
    client.deactivate();
    _setState(StompConnectionState.disconnected);
  }

  /// 复制一份新实例：提供的参数覆盖，未提供（null）的继承当前配置。
  /// 返回全新的、未连接的实例（不克隆订阅与连接状态），需自行 [activate]。
  Stompsocket copyWith({
    String? url,
    Duration? heartbeatIncoming,
    Duration? heartbeatOutgoing,
    Duration? pingInterval,
    Duration? connectionTimeout,
    Duration? reconnectDelay,
    Map<String, dynamic>? webSocketConnectHeaders,
    bool? useSockJS,
    StompFrameCallback? onUnhandledFrame,
    StompFrameCallback? onUnhandledMessage,
    StompFrameCallback? onUnhandledReceipt,
    void Function(StompFrame frame)? onStompError,
    void Function(dynamic error)? onWebSocketError,
    void Function()? onWebSocketDone,
    void Function(String message)? onDebugMessage,
    Map<String, String>? connectHeaders,
    Future<Map<String, String>?> Function()? beforeConnect,
    ParsedMessage Function(Uint8List bytes)? binaryDecoder,
    void Function(StompFrame frame, String error)? onParseFailure,
    bool? queueWhileDisconnected,
    int? maxQueuedMessages,
    bool? resumeOnForeground,
    bool? debug,
    void Function(String message, {Object? error, StackTrace? stackTrace})? onLog,
    void Function(StompFrame frame)? onConnected,
    void Function(StompFrame frame)? onDisconnected,
    void Function(StompConnectionState state)? onStateChanged,
  }) {
    return Stompsocket(
      url: url ?? _url,
      heartbeatIncoming: heartbeatIncoming ?? _heartbeatIncoming,
      heartbeatOutgoing: heartbeatOutgoing ?? _heartbeatOutgoing,
      pingInterval: pingInterval ?? _pingInterval,
      connectionTimeout: connectionTimeout ?? _connectionTimeout,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      webSocketConnectHeaders: webSocketConnectHeaders ?? _webSocketConnectHeaders,
      useSockJS: useSockJS ?? _useSockJS,
      onUnhandledFrame: onUnhandledFrame ?? _onUnhandledFrame,
      onUnhandledMessage: onUnhandledMessage ?? _onUnhandledMessage,
      onUnhandledReceipt: onUnhandledReceipt ?? _onUnhandledReceipt,
      onStompError: onStompError ?? this.onStompError,
      onWebSocketError: onWebSocketError ?? this.onWebSocketError,
      onWebSocketDone: onWebSocketDone ?? this.onWebSocketDone,
      onDebugMessage: onDebugMessage ?? this.onDebugMessage,
      connectHeaders: connectHeaders ?? _connectHeadersInit,
      beforeConnect: beforeConnect ?? _userBeforeConnect,
      binaryDecoder: binaryDecoder ?? this.binaryDecoder,
      onParseFailure: onParseFailure ?? this.onParseFailure,
      queueWhileDisconnected: queueWhileDisconnected ?? this.queueWhileDisconnected,
      maxQueuedMessages: maxQueuedMessages ?? this.maxQueuedMessages,
      resumeOnForeground: resumeOnForeground ?? this.resumeOnForeground,
      debug: debug ?? this.debug,
      onLog: onLog ?? this.onLog,
      onConnected: onConnected ?? this.onConnected,
      onDisconnected: onDisconnected ?? this.onDisconnected,
      onStateChanged: onStateChanged ?? this.onStateChanged,
    );
  }

  // ---------------------------------------------------------------------------
  // 发送
  // ---------------------------------------------------------------------------

  /// 发送一条消息到 [destination]。
  ///
  /// [body] 支持 `String`（原样）、`Map`/`List`（自动 json 编码，
  /// content-type 默认 application/json）、`Uint8List`（二进制）、null（无 body）。
  /// 未连接时：[queueWhileDisconnected] 为 true 则入缓冲、连上后按序发出
  /// （超过 [maxQueuedMessages] 丢弃最旧并告警）；为 false 则丢弃并告警。
  void send(String destination, {Object? body, Map<String, String>? headers}) {
    final out = _Outbound(destination, body, headers);
    if (client.connected) {
      _sendNow(out);
      return;
    }
    if (!queueWhileDisconnected) {
      _log('未连接，丢弃发往 $destination 的消息');
      return;
    }
    if (_outbox.length >= maxQueuedMessages) {
      _outbox.removeAt(0);
      _log('出站缓冲已满($maxQueuedMessages)，丢弃最旧消息');
    }
    _outbox.add(out);
  }

  void _sendNow(_Outbound out) {
    final body = out.body;
    if (body is Uint8List) {
      client.send(destination: out.destination, headers: out.headers, binaryBody: body);
    } else if (body is String) {
      client.send(destination: out.destination, headers: out.headers, body: body);
    } else if (body == null) {
      client.send(destination: out.destination, headers: out.headers);
    } else {
      // Map / List / 其它 → json，并补默认 content-type
      client.send(
        destination: out.destination,
        headers: {'content-type': 'application/json', ...?out.headers},
        body: jsonEncode(body),
      );
    }
  }

  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    final pending = List<_Outbound>.of(_outbox);
    _outbox.clear();
    for (var i = 0; i < pending.length; i++) {
      try {
        _sendNow(pending[i]);
      } catch (e, st) {
        // 补发中途又断线等 send 抛异常：把没发出去的（含当前这条）回退到缓冲头部，
        // 等下次连接成功再补发，不让剩余消息随循环中断一起丢掉。
        _outbox.insertAll(0, pending.sublist(i));
        _log('补发离线消息失败，剩余 ${pending.length - i} 条已回退到缓冲', e, st);
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 订阅
  // ---------------------------------------------------------------------------

  /// 订阅一个 topic。
  ///
  /// - **不传 [id]**（常见用法）：按 `(destination, ack, onParseError, ordered)` 四元组自动
  ///   归并。相同四元组的多次 subscribe 共享**一条** wire 订阅（只发一次 SUBSCRIBE，消息只
  ///   解析一次再分发给所有回调），通过 returned handle 的 `unsubscribe()` 引用计数释放，
  ///   最后一个取消才撤销订阅。`ack`/`ordered` 不同 → 归并键不同 → 独立订阅。
  /// - **传入 [id]**：精确控制归并键，与”不传 id”的自动键完全独立（自动键含 `\x00`，
  ///   用户 id 不可能含此字符）。用于同一 destination 下需要多份独立订阅的场景。
  /// - [ordered] 为 true（默认）时严格按消息到达顺序分发（即使大包走了异步解析也不会
  ///   乱序）；为 false 时解析完即分发，吞吐更高但可能乱序。
  /// - [ack] 非 [AckMode.auto] 时，每条消息处理完会自动 ACK（回调全部成功）
  ///   或 NACK（任一回调抛异常）。
  /// - [onParseError] 控制”二进制消息解析失败”时自动 NACK（默认）还是 ACK（丢弃）；
  ///   仅在 [ack] 非 auto 时生效。
  /// - 未连接时只登记到本地，连接建立后（含重连）自动向服务端重放。
  ///
  /// 返回 [StompSubscription] 句柄：`.id` 可用于 [unsubscribe]，
  /// `.unsubscribe()` 可就地取消本次回调（引用计数，最后一个回调取消时才 UNSUBSCRIBE）。
  StompSubscription subscribe(
    String destination,
    JsonCallback callback, {
    String? id,
    bool ordered = true,
    AckMode ack = AckMode.auto,
    ParseFailureAck onParseError = ParseFailureAck.nack,
  }) {
    // 不传 id → 四元组确定性键（含 \x00 分隔符，与用户显式 id 命名空间隔离）；
    // 传了 id → 直接用，可在同 destination 下保持多份独立订阅。
    final subId = id ?? '$_autoDestPrefix$destination\x00${ack.name}\x00${onParseError.name}\x00$ordered';

    var sub = _subscriptions[subId];
    if (sub != null && sub.destination != destination) {
      // 只有显式传 id 时才可能触发（自动键已含 destination，不会错位）
      _log('subscribe: id “$subId” 已绑定 ${sub.destination}，传入的新 destination “$destination” 被忽略（回调追加到原订阅）');
    }
    if (sub == null) {
      sub = _Subscription(
        id: subId,
        destination: destination,
        ordered: ordered,
        ack: ack,
        onParseError: onParseError,
      );
      _subscriptions[subId] = sub;
      // 已连接则立即上线；未连接则等 _onConnect 统一重放
      if (client.connected) {
        _openOnWire(sub);
      }
    }

    final reg = _CallbackReg(callback);
    sub.callbacks.add(reg);

    final owner = sub;
    return StompSubscription._(subId, () => _cancelReg(owner, reg));
  }

  /// 取消单次回调注册（引用计数）：队列空了才撤销整条订阅。
  void _cancelReg(_Subscription sub, _CallbackReg reg) {
    // 该订阅可能已被 unsubscribe/clear 整体移除，或被同 id 重新订阅（换了新对象）
    if (!identical(_subscriptions[sub.id], sub)) return;
    sub.callbacks.remove(reg);
    if (sub.callbacks.isEmpty) {
      _remove(sub);
    }
  }

  /// 取消订阅。
  ///
  /// - 传入 [id]：取消单个订阅。
  /// - 传入 [destination]：批量取消该 topic 下的所有订阅。
  /// - 两者都传：优先按 [id] 取消。
  /// - 两者都不传：无操作。
  ///
  /// 返回被取消的订阅数量。
  int unsubscribe({String? id, String? destination}) {
    if (id != null) {
      return _remove(_subscriptions[id]) ? 1 : 0;
    }
    if (destination != null) {
      final matched = _subscriptions.values.where((s) => s.destination == destination).toList(growable: false);
      var count = 0;
      for (final s in matched) {
        if (_remove(s)) count++;
      }
      return count;
    }
    return 0;
  }

  /// 取消所有订阅。
  void clear() {
    final all = _subscriptions.values.toList(growable: false);
    for (final s in all) {
      _remove(s);
    }
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  /// 向服务端真正发起 SUBSCRIBE 并记录取消函数
  void _openOnWire(_Subscription sub) {
    final headers = {'id': sub.id};
    final ackHeader = sub.ack.header;
    if (ackHeader != null) headers['ack'] = ackHeader; // auto 模式不带 ack 头
    sub.unsubscribeFn = client.subscribe(
      destination: sub.destination,
      callback: _onIncoming(sub),
      headers: headers,
    );
  }

  /// 移除并取消一个订阅，返回是否成功移除。
  bool _remove(_Subscription? sub) {
    if (sub == null) return false;
    _subscriptions.remove(sub.id);
    sub.callbacks.clear();
    // 未连接时不碰 unsubscribeFn：断线后服务端订阅已随会话消失，往死 socket 发
    // UNSUBSCRIBE 帧没有意义。
    if (client.connected) sub.unsubscribeFn?.call();
    return true;
  }

  void _onConnect(StompFrame frame) {
    _generation++; // 新会话：旧的 manual AckControl 句柄据此失效
    // 重连是全新会话，服务端订阅已失效；首连时本地订阅也还没上线。
    // 两种情况都用同一套逻辑：重放本地所有订阅。
    for (final sub in _subscriptions.values) {
      _openOnWire(sub);
    }
    _flushOutbox(); // 补发未连接期间缓冲的出站消息
    _setState(StompConnectionState.connected);
    onConnected?.call(frame);
  }

  void _onDisconnect(StompFrame frame) {
    _log('已断开连接');
    onDisconnected?.call(frame);
  }

  void _onStompError(StompFrame frame) {
    _log('STOMP 错误: ${frame.body}', frame.headers['message']);
    onStompError?.call(frame);
  }

  void _onWebSocketError(dynamic error) {
    _log('WebSocket 错误', error);
    onWebSocketError?.call(error);
  }

  void _onWebSocketDone() {
    onWebSocketDone?.call();
    // 连接断开：库会按 reconnectDelay 自动重连（>0 时）。dispose 时 _wantConnection
    // 已置 false，由 dispose 负责置 disconnected，这里不覆盖。
    if (!_wantConnection) return;
    _setState(reconnectDelay > Duration.zero
        ? StompConnectionState.reconnecting
        : StompConnectionState.disconnected);
  }

  /// 每次连接前调用：跑用户 beforeConnect（可刷新 token）并更新 CONNECT 头。
  /// 内部吞异常，避免打断连接流程（失败会连不上 → 由库的自动重连兜底）。
  Future<void> _beforeConnect() async {
    if (_userBeforeConnect == null) return;
    try {
      final headers = await _userBeforeConnect();
      if (headers != null) {
        _connectHeaders
          ..clear()
          ..addAll(headers);
      }
    } catch (e, st) {
      _log('beforeConnect 失败', e, st);
    }
  }

  StompFrameCallback _onIncoming(_Subscription sub) {
    return (StompFrame frame) {
      // 捕获消息到达时的会话代次：大包异步解析期间若断线重连，解析完成后不能对
      // 旧会话的 ack id 发 ACK/NACK（重连后 client.connected 又为 true，会误发）。
      final gen = _generation;
      if (sub.ordered) {
        // 串到该订阅的串行链尾，保证分发顺序 == 到达顺序。
        // 闭包内 catch 所有异常，避免链因一次失败而永久中断。
        sub.tail = sub.tail.then((_) async {
          try {
            _dispatch(sub, frame, await _parse(frame.binaryBody, frame.body, frame.headers['content-type']), gen);
          } catch (e, st) {
            _log('有序分发失败 (id=${sub.id})', e, st);
          }
        });
        return;
      }

      // 无序：解析完即分发
      final parsed = _parse(frame.binaryBody, frame.body, frame.headers['content-type']);
      if (parsed is Future<_ParseResult>) {
        parsed.then((r) => _dispatch(sub, frame, r, gen)).catchError((Object e, StackTrace st) {
          _log('分发失败 (id=${sub.id})', e, st);
        });
      } else {
        _dispatch(sub, frame, parsed, gen);
      }
    };
  }

  /// 按负载大小决定同步解析或丢到后台 isolate 解析。
  ///
  /// [contentType] 用于二进制分流：stomp_dart 的 parser 在 content-type 为
  /// `application/octet-stream` **或缺失** 时都会把 body 归入 [binary]——而 ActiveMQ 等
  /// 服务端常不写 content-type，JSON 文本也会走到 binary 分支。所以：
  /// - 显式标注 octet-stream → 直接走 [binaryDecoder]（快路径，声明了就不再校验）；
  /// - 其余（含 content-type 缺失）→ 先做**严格 UTF-8 解码**探测：成功就按文本路径解析，
  ///   失败（压缩/真二进制数据几乎必然在极短字节内违反 UTF-8 结构规则、快速失败）才走
  ///   [binaryDecoder]。这是字节结构层面的确定性校验，不能反过来用"JSON 解析抛没抛异常"
  ///   猜测——二进制数据凑巧解出可解析文本会把损坏数据当合法结果静默交给业务。
  FutureOr<_ParseResult> _parse(Uint8List? binary, String? body, String? contentType) {
    if (binary != null) {
      if (contentType != 'application/octet-stream') {
        final String text;
        try {
          text = utf8.decode(binary); // 严格模式（allowMalformed 默认 false）
        } on FormatException {
          return _parseBinary(binary);
        }
        return text.length <= _isolateThreshold ? _decodeStringBody(text) : compute(_decodeStringBody, text);
      }
      return _parseBinary(binary);
    }
    if (body != null) {
      // 用字符长度估算体量即可，无需精确字节数
      return body.length <= _isolateThreshold ? _decodeStringBody(body) : compute(_decodeStringBody, body);
    }
    return (null, null);
  }

  /// 二进制路径：走注入的 [binaryDecoder]，未配置/抛异常都记为解析失败。
  FutureOr<_ParseResult> _parseBinary(Uint8List binary) {
    final decoder = binaryDecoder;
    if (decoder == null) {
      return (null, '收到二进制消息但未配置 binaryDecoder');
    }
    if (binary.length <= _isolateThreshold) {
      try {
        return (decoder(binary), null);
      } catch (e) {
        return (null, '二进制解析失败: $e');
      }
    }
    // 大包丢到后台 isolate（decoder 必须是顶层/静态函数），异常转为解析失败记录
    return compute(decoder, binary)
        .then<_ParseResult>((d) => (d, null))
        .catchError((Object e) => (null, '二进制解析失败: $e'));
  }

  /// 把同一份解析后的数据分发给该订阅队列中的所有回调，并按 [AckMode] 处理确认。
  /// [gen] 是消息到达时的会话代次，用于避免异步解析后对旧会话误发 ACK/NACK。
  void _dispatch(_Subscription sub, StompFrame frame, _ParseResult result, int gen) {
    final (json, error) = result;
    if (error != null) {
      _log(error);
      onParseFailure?.call(frame, error);
    }

    // 异步解析期间订阅可能已被取消，或被同 id 重新订阅（换了新对象）：直接返回。
    if (!identical(_subscriptions[sub.id], sub)) return;

    switch (sub.ack) {
      case AckMode.auto:
        // 服务端自动确认：不发 ACK/NACK，仅分发成功解析的消息
        if (json != null) _runCallbacks(sub, json, const _NoopAck());
      case AckMode.smart:
        // 本封装按处理结果自动应答
        final bool handled;
        if (error != null) {
          handled = sub.onParseError == ParseFailureAck.ack;
        } else if (json == null) {
          handled = true; // 空体，视为已处理
        } else {
          handled = _runCallbacks(sub, json, const _NoopAck());
        }
        _sendAck(frame, handled: handled, gen: gen);
      case AckMode.manual:
        if (error != null) {
          // 未解析成功，回调拿不到 json，按策略自动应答
          _sendAck(frame, handled: sub.onParseError == ParseFailureAck.ack, gen: gen);
        } else if (json == null) {
          _sendAck(frame, handled: true, gen: gen);
        } else {
          // 交给回调手动 ack/nack；本封装不自动应答
          _runCallbacks(sub, json, _MessageAck(this, _ackIdOf(frame), gen));
        }
    }
  }

  /// 分发给队列中所有回调，返回是否全部成功（任一抛异常即 false）。
  /// 复制一份队列，避免回调内部增删订阅时并发修改。
  bool _runCallbacks(_Subscription sub, ParsedMessage json, AckControl ack) {
    var ok = true;
    for (final reg in List<_CallbackReg>.of(sub.callbacks)) {
      try {
        reg.cb(json, ack);
      } catch (e, st) {
        ok = false;
        _log('订阅回调异常 (id=${sub.id})', e, st);
      }
    }
    return ok;
  }

  /// 处理成功发 ACK，失败发 NACK。[gen] 为消息到达时的会话代次。
  void _sendAck(StompFrame frame, {required bool handled, required int gen}) {
    // 断线、或已重连到新会话（大包异步解析期间断线重连）时 ACK/NACK 无意义：
    // ack id 属于旧会话，发出去服务端认不得。
    if (!client.connected || gen != _generation) return;
    final id = _ackIdOf(frame);
    if (id == null) {
      _log('无法自动${handled ? "ACK" : "NACK"}：消息缺少 ack/message-id 头');
      return;
    }
    if (handled) {
      client.ack(id: id);
    } else {
      client.nack(id: id);
    }
  }

  /// ack id：STOMP 1.2 用 MESSAGE 帧的 `ack` 头，回退 `message-id`。
  String? _ackIdOf(StompFrame frame) => frame.headers['ack'] ?? frame.headers['message-id'];

  /// stomp_dart 的帧级流水日志（`>>>`/`<<<` 帧、PING/PONG 等）。
  /// 原样透传给 [onDebugMessage]，并在 [debug] 开启时经 [_log] 输出。
  void _onDebugMessage(String message) {
    onDebugMessage?.call(message);
    if (debug) _log(message);
  }

  void _log(String message, [Object? error, StackTrace? stackTrace]) {
    if (!debug) return; // 主开关：关闭时不产生任何日志
    final sink = onLog;
    if (sink != null) {
      sink(message, error: error, stackTrace: stackTrace); // 由使用方决定如何打印
    } else {
      developer.log(message, name: 'stomp', error: error, stackTrace: stackTrace);
    }
  }
}
