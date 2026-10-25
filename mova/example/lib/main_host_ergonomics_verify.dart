// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

import 'verify_auto/auto_kit.dart';
import 'verify_auto/he_auto.dart';

/// 宿主易用性增强的真机验证页（计划 doc/plans/2026-10-23-host-ergonomics.md 的 Task 16 用）。
///
/// 一个页面只验这一批：声明式 `MovaView`、封面与 `MovaFirstFrame`、起播/卡顿超时与重试、
/// 多地址兜底、滚出视口/切 Tab/被路由盖住/进后台的自动暂停。所有事件带时间戳，以固定前缀
/// `[MOVA-HE]` 打印，方便 `adb logcat | grep MOVA-HE`。
///
/// 跑法（地址按需替换；`LIVE=true` 按直播处理）：
/// `flutter run --release -t lib/main_host_ergonomics_verify.dart \
///    --dart-define=PRIMARY=https://host/a.m3u8 --dart-define=ALT=https://host/b.m3u8 --dart-define=LIVE=true`
///
/// 本页只有根 Navigator 一层，被盖住靠 `ModalRoute.isCurrentOf` 即可察觉，不需要 `routeObservers`
/// （嵌套 Navigator/外层半透明路由才需要，且每个 Navigator 要各自一个观察者）。
///
/// 每次打开都给地址追加 `?t=<微秒时间戳>` 防缓存；多次测量请重复点「重开」取平均。
///
/// 脚本化模式（不传 AUTORUN 时本页行为不变）：加 `--dart-define=AUTORUN=true`，按固定顺序自动跑 V1–V8、V10、V12，
/// 每个场景 `RUNS`（默认 3）次，跑完打印汇总并退出（`AUTOEXIT=false` 则停住）。可选参数：`BASE`（本地源服务器基地址）、
/// `LOG_FILE`（日志同时追加写入的文件，未传则读环境变量 `MOVA_LOG`）、`ONLY=V5,V7`（只跑部分）、`GOP`、`V4_REPS`、
/// `START_TIMEOUT_S`、`STALL_TIMEOUT_S`。详见 `verify_auto/he_auto.dart`。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(MaterialApp(home: kAutoRun ? const HeAutoPage() : const _VerifyPage()));
}

/// 主地址（编译期传入）。
const String _kPrimary = String.fromEnvironment('PRIMARY');

/// 备选地址（编译期传入，可空）。
const String _kAlt = String.fromEnvironment('ALT');

/// 是否按直播处理。
const bool _kLive = bool.fromEnvironment('LIVE');

/// 日志固定前缀，便于 logcat 过滤。
const String _kTag = '[MOVA-HE]';

/// 验证页：一个可滚动列表，中间夹着一张 `MovaView` 卡片，外加两个触发按钮。
class _VerifyPage extends StatefulWidget {
  const _VerifyPage();

  @override
  State<_VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<_VerifyPage> {
  /// 当前要播的源；点「重开」时换一个带新时间戳的实例。
  MovaSource? _source;

  /// 页面上展示的最近日志。
  final List<String> _lines = <String>[];

  /// 当前引擎事件订阅。
  StreamSubscription<MovaEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _reopen();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  /// 打一行带时间戳的日志（同时进页面和 stdout）。
  void _log(String msg) {
    final line = '${DateTime.now().toIso8601String().substring(11, 23)} $msg';
    print('$_kTag $line');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  /// 追加防缓存时间戳。
  String _stamp(String url) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'}).toString();
  }

  /// 用新时间戳重开（`sameAs` 会因 uri 变化而判为新源）。
  void _reopen() {
    if (_kPrimary.isEmpty) {
      _log('缺少 --dart-define=PRIMARY');
      return;
    }
    setState(() {
      _source = MovaSource.pick(
        [_stamp(_kPrimary), if (_kAlt.isNotEmpty) _stamp(_kAlt)],
        type: _kLive ? MovaStreamType.live : MovaStreamType.vod,
      );
    });
    _log('reopen ${_source?.uris}');
  }

  /// 引擎创建后订阅关心的事件。
  void _onEngine(MovaApi api) {
    unawaited(_sub?.cancel());
    _sub = api.events.listen((e) {
      switch (e) {
        case MovaFirstFrame():
          _log('FirstFrame sinceOpen=${e.sinceOpen.inMilliseconds}ms signal=${e.signal.name}');
        case MovaPlayFailure():
          _log('PlayFailure kind=${e.fail.kind.name} attempt=${e.fail.attempt} idx=${e.fail.sourceIndex} action=${e.action.name}');
        case MovaFailover():
          _log('Failover ${e.from}->${e.to} ${e.uri}');
        case MovaRecovered():
          _log('Recovered attempts=${e.attempts}');
        case MovaPause():
          _log('Pause');
        case MovaPlay():
          _log('Play');
        case MovaLiveEdgeReach():
          _log('LiveEdgeReach');
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('host ergonomics verify')),
      body: ListView(
        children: [
          for (var i = 0; i < 3; i++) const SizedBox(height: 160, child: Center(child: Text('filler'))),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MovaView(
              source: _source,
              fit: MovaFit.cover,
              poster: const ColoredBox(color: Color(0xFF223344), child: Center(child: Text('POSTER'))),
              skin: const MovaMinimalSkin(),
              options: const MovaOpts(
                recovery: MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 8), stallTimeout: Duration(seconds: 8)),
              ),
              autoPause: const MovaAutoPauseConfig(),
              onEngine: _onEngine,
              onOpenError: (e, s) => _log('openError $e'),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(onPressed: _reopen, child: const Text('重开(新 t=)')),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('covering page'))))),
                child: const Text('盖一层路由'),
              ),
            ],
          ),
          for (var i = 0; i < 6; i++) const SizedBox(height: 160, child: Center(child: Text('filler'))),
          for (final l in _lines.take(40)) Text(l, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
