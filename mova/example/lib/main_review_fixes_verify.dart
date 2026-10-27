import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
// ignore: implementation_imports
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 本轮评审修复（V1-V9）的 Android 真机验证页。
///
/// 选组：启动时从 http://127.0.0.1:18082/group 取（adb reverse 到 PC 上的小服务），或编译期
/// `--dart-define=GROUP=v1a`。组名：all（v1a,v2..v7）、v1a、v1b、v2、v3、v4、v5、
/// v6、v7、v8a、v8b、v9。
///
/// 所有结论只来自事件时间戳与状态流，日志行格式 `RFV|毫秒时间戳|标签|内容`，
/// 用 `adb logcat -s flutter` 抓取。源由 example/tool/verify_sources 的本机服务
/// 提供（`adb reverse tcp:18080 tcp:18080`）。
const _kSrc = String.fromEnvironment('SRC', defaultValue: 'http://127.0.0.1:18080');

/// 每项重复次数。
const _kRuns = 3;

/// 启动参数里的组名；回落到编译期常量。
String _group = const String.fromEnvironment('GROUP', defaultValue: 'all');

/// 未捕获异常计数（Zone / FlutterError / PlatformDispatcher）。
int _uncaught = 0;

/// 屏幕上回显的日志。
final ValueNotifier<List<String>> _screen = ValueNotifier<List<String>>(<String>[]);

/// 自增序号，用于给 URL 加防缓存参数。
int _seq = 0;

/// 当前毫秒时间戳。
int _now() => DateTime.now().millisecondsSinceEpoch;

/// 打印一行带时间戳的日志。
void _log(String tag, String msg) {
  final line = 'RFV|${_now()}|$tag|$msg';
  // ignore: avoid_print
  print(line);
  final l = _screen.value;
  _screen.value = [...l.length > 60 ? l.sublist(l.length - 60) : l, line];
}

/// 打印一条结论行。
void _result(String id, int run, bool pass, String detail) =>
    _log('RESULT', '$id|run$run|${pass ? 'PASS' : 'FAIL'}|$detail');

/// 构造带防缓存参数的本机源 URL。
String _u(String path) => '$_kSrc/$path${path.contains('?') ? '&' : '?'}t=${_now()}${_seq++}';

/// 构造带标题的本机源。
MovaSource _s(String path, String title) => MovaSource(_u(path), title: title);

/// 一个被跟踪的引擎：记录销毁时刻与最近进度时刻。
class _Tr {
  _Tr(this.api);

  /// 被跟踪的引擎。
  final MovaApi api;

  /// 事件流关闭（即销毁）时刻。
  int? disposedAt;

  /// 最近一次位置变化时刻。
  int progAt = 0;

  /// 最近位置。
  Duration pos = Duration.zero;
}

/// 本次运行创建过的全部引擎。
final List<_Tr> _trs = <_Tr>[];

/// 验证用选项：cutover 开启、readyTimeout 5s、立即预热，广告开启。
MovaOpts _opts() => const MovaOpts(
  cutover: MovaCutoverConfig(enabled: true, readyTimeout: Duration(seconds: 5), trigger: MovaEagerWarm()),
  ads: MovaAdConfig(enabled: true),
);

/// 创建被跟踪的纯音频引擎（避免无渲染面时 media_kit 卡死）。
MovaApi _mk() => _track(createMovaEngine(audioOnly: true, options: _opts()));

/// 登记引擎的销毁/进度监听。
MovaApi _track(MovaApi e) {
  final t = _Tr(e);
  e.events.listen((_) {}, onDone: () => t.disposedAt = _now());
  e.progress.listen((p) {
    if (p.position != t.pos) t.progAt = _now();
    t.pos = p.position;
  });
  _trs.add(t);
  return e;
}

/// 剩余的"强制 open 抛异常"次数；V2b 用它让影子引擎的 open 抛错一次。
int _throwBudget = 0;

/// 在预算内对含 `throwme` 的地址让 open 抛 StateError，其余走真实 mpv 内核。
class _ThrowKernel extends MovaMpvKernel {
  _ThrowKernel() : super(audioOnly: true);

  @override
  Future<void> open(String uri, {bool play = true}) async {
    if (_throwBudget > 0 && uri.contains('throwme')) {
      _throwBudget--;
      throw StateError('forced open failure');
    }
    return super.open(uri, play: play);
  }
}

/// 创建内核会按预算抛错的纯音频引擎。
MovaApi _mkThrow() => _track(MovaEngine(kernel: _ThrowKernel(), options: _opts()));

/// 轮询等待条件成立，返回是否在期限内成立（仅用于等待，度量取自事件戳）。
Future<bool> _until(bool Function() c, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!c()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  return true;
}

/// 简写的延时。
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main(List<String> args) {
  for (final a in args) {
    if (a.startsWith('GROUP=')) _group = a.substring(6);
  }
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (d) {
        _uncaught++;
        _log('UNCAUGHT', 'FlutterError ${d.exceptionAsString()}');
      };
      ui.PlatformDispatcher.instance.onError = (e, s) {
        _uncaught++;
        _log('UNCAUGHT', 'Platform $e');
        return true;
      };
      MovaEngine.ensureInitialized();
      runApp(MaterialApp(home: const _Home(), navigatorKey: _nav));
    },
    (e, s) {
      _uncaught++;
      _log('UNCAUGHT', 'Zone $e\n$s');
    },
  );
}

/// 全局导航键，供 V8/V9 推页面。
final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

/// 首页：按组名跑验证并回显日志。
class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    unawaited(_main());
  }

  Future<void> _main() async {
    await _wait(1500);
    // 组名取自本机控制服务（adb reverse 18082），取不到就用编译期值。
    try {
      final c = HttpClient();
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:18082/group')).timeout(const Duration(seconds: 3));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final body = await resp.transform(const SystemEncoding().decoder).join();
      if (body.trim().isNotEmpty) _group = body.trim();
      c.close(force: true);
    } catch (e) {
      _log('START', 'control server unreachable: ${e.runtimeType}');
    }
    _log('START', 'group=$_group');
    final groups = _group == 'all' ? ['v1a', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7'] : [_group];
    for (final g in groups) {
      _log('GROUP', 'begin $g');
      try {
        switch (g) {
          case 'v1a':
            for (var i = 1; i <= _kRuns; i++) {
              await _v1(i, 'hang');
            }
          case 'v1b':
            await _probeNet();
            for (var i = 1; i <= _kRuns; i++) {
              await _v1(i, 'wifi');
            }
          case 'v1c':
            for (var i = 1; i <= _kRuns; i++) {
              await _v1(i, 'stall');
            }
          case 'v2':
            const bad = ['404', 'refused', 'scheme', '404'];
            for (var i = 0; i < bad.length; i++) {
              await _v2(i + 1, bad[i]);
            }
          case 'v2b':
            for (var i = 1; i <= _kRuns; i++) {
              await _v2b(i);
            }
          case 'v3':
            for (var i = 1; i <= _kRuns; i++) {
              await _v3(i, i != 2);
            }
          case 'v4':
            const delays = [0, 5, 15, 40, 80, 150];
            for (var i = 0; i < delays.length; i++) {
              await _v4(i + 1, delays[i]);
            }
          case 'v5':
            for (final m in ['deferred2', 'load', 'dispose']) {
              for (var i = 1; i <= _kRuns; i++) {
                await _v5(i, m);
              }
            }
          case 'v6':
            for (var i = 1; i <= _kRuns; i++) {
              await _v6(i);
            }
          case 'v7':
            const gaps = [0, 2, 10];
            var n = 0;
            for (final g in gaps) {
              for (var i = 0; i < _kRuns; i++) {
                await _v7(++n, g);
              }
            }
          case 'v8a':
            await _v8('landscape');
          case 'v8b':
            await _v8('fullscreen');
          case 'v9':
            await _v9();
        }
      } catch (e, s) {
        _log('GROUP', 'ERROR in $g: $e\n$s');
      }
      _log('GROUP', 'end $g uncaught=$_uncaught');
    }
    _log('DONE', 'group=$_group uncaught=$_uncaught');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ValueListenableBuilder<List<String>>(
        valueListenable: _screen,
        builder: (_, l, _) => ListView(children: [for (final s in l) Text(s, style: const TextStyle(fontSize: 9))]),
      ),
    ),
  );
}

/// 探测公网是否可达（V1b 断网前后对照）。
Future<void> _probeNet() async {
  final t0 = _now();
  try {
    final r = await _head('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8');
    _log('NET', 'public reachable=${r != null} status=$r in ${_now() - t0}ms');
  } catch (e) {
    _log('NET', 'public reachable=false err=${e.runtimeType} in ${_now() - t0}ms');
  }
}

/// 对公网地址发一次 HEAD，返回状态码；超时 4s。
Future<int?> _head(String url) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl('HEAD', Uri.parse(url)).timeout(const Duration(seconds: 4));
    final resp = await req.close().timeout(const Duration(seconds: 4));
    return resp.statusCode;
  } finally {
    c.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// V1 预热超时（#3）
// ---------------------------------------------------------------------------

/// V1：广告播放期间预热正片，正片源永不就绪；看 commit(waitForReady) 是否在
/// readyTimeout(5s) 附近以 false 结束，之后能否回退续播。
///
/// [kind] 为 hang（本机 /hang 端点：接受连接不回数据）、stall（本机 /stall.mp4：
/// 发 10% 后挂住，模拟传输中途断网）或 wifi（公网源，须已断网）。
Future<void> _v1(int run, String kind) async {
  final id = switch (kind) { 'hang' => 'V1a', 'stall' => 'V1c', _ => 'V1b' };
  final proxy = MovaCutoverEngine(engineFactory: _mk);
  var pos = Duration.zero;
  final subs = <StreamSubscription<Object?>>[
    proxy.progress.listen((p) => pos = p.position),
    proxy.cutoverPhases.listen((p) => _log(id, 'run$run phase=${p.name}')),
    proxy.events.listen((e) {
      if (e is MovaErrorEvent) _log(id, 'run$run proxyErrorEvent ${e.error}');
    }),
  ];
  await proxy.open(_s('ad.mp4', 'ad'));
  final playing = await _until(() => pos > Duration.zero, const Duration(seconds: 15));
  final content = kind == 'hang'
      ? _s('hang', 'content')
      : kind == 'stall'
      ? _s('stall.mp4?k=1', 'content')
      : MovaSource('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8?t=${_now()}${_seq++}', title: 'content');
  final epoch0 = proxy.state.renderEpoch;
  final t0 = _now();
  _log(id, 'run$run prepare called, adPlaying=$playing pos=$pos');
  await proxy.prepare(
    content,
    cue: const MovaWarmCue(remaining: Duration(seconds: 15), total: Duration(seconds: 20)),
    plan: const MovaWarmPlan(pauseWhenReady: true),
  );
  _log(id, 'run$run prepare returned +${_now() - t0}ms');
  final ok = await proxy
      .commit(waitForReady: true)
      .then<bool?>((v) => v)
      .timeout(const Duration(seconds: 30), onTimeout: () => null);
  final elapsed = _now() - t0;
  _log(id, 'run$run commit -> $ok after ${elapsed}ms (null = 挂起超过 30s)');
  final idleOk = await _until(() => proxy.cutoverPhase == MovaCutoverPhase.idle, const Duration(seconds: 2));
  final phase = proxy.cutoverPhase;
  _log(id, 'run$run phase back to ${phase.name} (waited ${_now() - t0 - elapsed}ms after commit returned)');
  // 回退续播：普通 open 正片，位置应持续推进。
  await proxy.open(_s('vod.mp4', 'fallback'));
  await _until(() => proxy.state.sourceTitle == 'fallback', const Duration(seconds: 5));
  await _wait(2500);
  final p1 = pos;
  await _wait(2000);
  final p2 = pos;
  final advancing = p2 - p1 >= const Duration(milliseconds: 1500);
  _log(id, 'run$run fallback title=${proxy.state.sourceTitle} p1=$p1 p2=$p2 epoch $epoch0->${proxy.state.renderEpoch}');
  // hang 必须在 readyTimeout 附近以 false 结束；stall/wifi 两种允许"就绪即 true"，但都不得挂起。
  final pass = kind == 'hang'
      ? ok == false && elapsed >= 4500 && elapsed <= 7000 && idleOk && advancing
      : ok != null && elapsed <= 7000 && (ok || (idleOk && advancing));
  _result(id, run, pass, 'commit=$ok elapsed=${elapsed}ms phaseAfter=${phase.name} fallbackAdvancing=$advancing');
  for (final s in subs) {
    await s.cancel();
  }
  await proxy.dispose();
}

// ---------------------------------------------------------------------------
// V2 预热 open 失败（#4）
// ---------------------------------------------------------------------------

/// V2：影子用坏地址，cutoverTo 应快速回退到 active.open，之后再 prepare 好源应正常。
Future<void> _v2(int run, String bad) async {
  const id = 'V2';
  final badUri = switch (bad) {
    '404' => '$_kSrc/nope404.mp4?t=${_now()}',
    'refused' => 'http://127.0.0.1:1/x.mp4',
    _ => 'bad://x/y',
  };
  final proxy = MovaCutoverEngine(engineFactory: _mk);
  var pos = Duration.zero;
  var errs = 0;
  final subs = <StreamSubscription<Object?>>[
    proxy.progress.listen((p) => pos = p.position),
    proxy.cutoverPhases.listen((p) => _log(id, 'run$run($bad) phase=${p.name}')),
    proxy.events.listen((e) {
      if (e is MovaErrorEvent) {
        errs++;
        _log(id, 'run$run($bad) proxyErrorEvent ${e.error.runtimeType}');
      }
    }),
  ];
  await proxy.open(_s('vod.mp4', 'A'));
  await _until(() => pos > Duration.zero, const Duration(seconds: 15));
  final epoch0 = proxy.state.renderEpoch;
  final t0 = _now();
  final ok = await proxy
      .cutoverTo(MovaSource(badUri, title: 'bad'))
      .then<bool?>((v) => v)
      .timeout(const Duration(seconds: 30), onTimeout: () => null);
  final t1 = _now();
  _log(id, 'run$run($bad) cutoverTo(bad) -> $ok after ${t1 - t0}ms phase=${proxy.cutoverPhase.name} errorEvents=$errs');
  // 再 prepare 一个好源，应不再被 _shadow 残留忽略。
  final t2 = _now();
  var readyAt = 0;
  final rs = proxy.cutoverPhases.listen((p) {
    if (p == MovaCutoverPhase.ready && readyAt == 0) readyAt = _now();
  });
  await proxy.prepare(_s('ad.mp4', 'B'), plan: const MovaWarmPlan());
  final reached = await _until(() => proxy.cutoverPhase == MovaCutoverPhase.ready, const Duration(seconds: 15));
  final committed = reached ? await proxy.commit() : false;
  await rs.cancel();
  final epoch1 = proxy.state.renderEpoch;
  await _wait(1500);
  final title = proxy.state.sourceTitle;
  _log(id, 'run$run($bad) prepare(good) ready=${reached ? '+${readyAt - t2}ms' : 'NO'} commit=$committed epoch $epoch0->$epoch1 title=$title');
  final pass = ok == false && t1 - t0 < 4000 && reached && committed && epoch1 == epoch0 + 1 && title == 'B';
  _result(id, run, pass, 'bad=$bad cutoverTo=$ok in ${t1 - t0}ms; reprepare ready=$reached commit=$committed epoch+${epoch1 - epoch0} title=$title');
  for (final s in subs) {
    await s.cancel();
  }
  await proxy.dispose();
}

/// V2b：影子的 open 真的抛异常（用 [_ThrowKernel] 精确触发），cutoverTo 应返回 false
/// 且不向调用方抛出，之后再 prepare 好源应正常。
Future<void> _v2b(int run) async {
  const id = 'V2b';
  _throwBudget = 0;
  final proxy = MovaCutoverEngine(engineFactory: _mkThrow);
  var pos = Duration.zero;
  var errs = 0;
  final subs = <StreamSubscription<Object?>>[
    proxy.progress.listen((p) => pos = p.position),
    proxy.cutoverPhases.listen((p) => _log(id, 'run$run phase=${p.name}')),
    proxy.events.listen((e) {
      if (e is MovaErrorEvent) {
        errs++;
        _log(id, 'run$run proxyErrorEvent ${e.error}');
      }
    }),
  ];
  await proxy.open(_s('vod.mp4', 'A'));
  await _until(() => pos > Duration.zero, const Duration(seconds: 15));
  final epoch0 = proxy.state.renderEpoch;
  _throwBudget = 1;
  final t0 = _now();
  bool? ok;
  Object? threw;
  try {
    ok = await proxy.cutoverTo(MovaSource(_u('throwme.mp4'), title: 'bad')).timeout(const Duration(seconds: 30));
  } catch (e) {
    threw = e;
  }
  final t1 = _now();
  _throwBudget = 0;
  _log(id, 'run$run cutoverTo(open throws) -> ok=$ok threw=${threw.runtimeType} after ${t1 - t0}ms phase=${proxy.cutoverPhase.name} errorEvents=$errs');
  var reached = false;
  var committed = false;
  Object? threw2;
  try {
    await proxy.prepare(_s('ad.mp4', 'B'), plan: const MovaWarmPlan());
    reached = await _until(() => proxy.cutoverPhase == MovaCutoverPhase.ready, const Duration(seconds: 12));
    committed = reached && await proxy.commit();
  } catch (e) {
    threw2 = e;
  }
  await _wait(1500);
  final epoch1 = proxy.state.renderEpoch;
  final title = proxy.state.sourceTitle;
  _log(id, 'run$run reprepare reached=$reached commit=$committed threw=${threw2.runtimeType} epoch $epoch0->$epoch1 title=$title phase=${proxy.cutoverPhase.name}');
  final pass = threw == null && ok == false && reached && committed && epoch1 == epoch0 + 1 && title == 'B';
  _result(id, run, pass, 'cutoverTo=$ok threw=${threw.runtimeType} errorEvents=$errs reprepare ready=$reached commit=$committed epoch+${epoch1 - epoch0} title=$title');
  for (final s in subs) {
    await s.cancel();
  }
  await proxy.dispose();
}

// ---------------------------------------------------------------------------
// V3 同引擎 cutoverTo 不同源（#5）
// ---------------------------------------------------------------------------

/// V3：prepare(B) 之后 cutoverTo(C)，最终应播放 C。
///
/// A、B 为 40s 的 vod，C 为 20s 的 ad，因此时长可独立区分 B 与 C。
/// [waitReady] 为 false 时 cutoverTo 紧跟 prepare（B 仍在预热中）。
Future<void> _v3(int run, bool waitReady) async {
  const id = 'V3';
  final proxy = MovaCutoverEngine(engineFactory: _mk);
  var pos = Duration.zero;
  final subs = <StreamSubscription<Object?>>[
    proxy.progress.listen((p) => pos = p.position),
    proxy.cutoverPhases.listen((p) => _log(id, 'run$run phase=${p.name}')),
  ];
  await proxy.open(_s('vod.mp4?x=A', 'A'));
  await _until(() => pos > Duration.zero, const Duration(seconds: 15));
  final epoch0 = proxy.state.renderEpoch;
  await proxy.prepare(_s('vod.mp4?x=B', 'B'));
  if (waitReady) await _until(() => proxy.cutoverPhase == MovaCutoverPhase.ready, const Duration(seconds: 15));
  _log(id, 'run$run before cutoverTo(C): phase=${proxy.cutoverPhase.name} waitReady=$waitReady');
  final t0 = _now();
  final ok = await proxy
      .cutoverTo(_s('ad.mp4?x=C', 'C'))
      .then<bool?>((v) => v)
      .timeout(const Duration(seconds: 30), onTimeout: () => null);
  final t1 = _now();
  await _until(() => proxy.state.sourceTitle == 'C' && proxy.state.duration > Duration.zero, const Duration(seconds: 10));
  await _wait(1500);
  final st = proxy.state;
  _log(id, 'run$run cutoverTo(C) -> $ok after ${t1 - t0}ms; title=${st.sourceTitle} duration=${st.duration} epoch $epoch0->${st.renderEpoch}');
  final durOk = (st.duration - const Duration(seconds: 20)).inMilliseconds.abs() < 2500;
  _result(id, run, st.sourceTitle == 'C' && durOk, 'cutoverTo=$ok title=${st.sourceTitle} duration=${st.duration} epoch+${st.renderEpoch - epoch0} waitReady=$waitReady');
  for (final s in subs) {
    await s.cancel();
  }
  await proxy.dispose();
}

// ---------------------------------------------------------------------------
// V4 提交中途 dispose（#6）
// ---------------------------------------------------------------------------

/// V4：commit 过程中在 [delayMs] 毫秒后 dispose 代理；期望无未捕获异常、
/// 本次创建的每个引擎都被销毁（事件流关闭）。
Future<void> _v4(int run, int delayMs) async {
  const id = 'V4';
  final before = _trs.length;
  final u0 = _uncaught;
  final proxy = MovaCutoverEngine(engineFactory: _mk);
  var pos = Duration.zero;
  final sub = proxy.progress.listen((p) => pos = p.position);
  await proxy.open(_s('vod.mp4', 'A'));
  await _until(() => pos > Duration.zero, const Duration(seconds: 15));
  await proxy.prepare(_s('ad.mp4', 'B'), plan: const MovaWarmPlan());
  final ready = await _until(() => proxy.cutoverPhase == MovaCutoverPhase.ready, const Duration(seconds: 15));
  final tC = _now();
  final f = proxy.commit().then<bool?>((v) => v).catchError((Object e) {
    _log(id, 'run$run commit threw $e');
    return null;
  });
  if (delayMs > 0) await _wait(delayMs);
  final tD = _now();
  Object? disposeErr;
  await proxy.dispose().timeout(const Duration(seconds: 10)).catchError((Object e) {
    disposeErr = e;
  });
  final tD2 = _now();
  final r = await f.timeout(const Duration(seconds: 10), onTimeout: () => null);
  await sub.cancel();
  await _wait(3000);
  final created = _trs.sublist(before);
  final undisposed = created.where((t) => t.disposedAt == null).length;
  final du = _uncaught - u0;
  _log(id, 'run$run delay=${delayMs}ms ready=$ready commit=$r dispose took ${tD2 - tD}ms (commit started +${tD - tC}ms before) engines=${created.length} undisposed=$undisposed uncaught+$du disposeErr=$disposeErr');
  _result(id, run, undisposed == 0 && du == 0 && disposeErr == null, 'delay=${delayMs}ms commit=$r engines=${created.length} undisposed=$undisposed uncaught+$du');
}

// ---------------------------------------------------------------------------
// V5 广告 deferred 解析过期（#7）
// ---------------------------------------------------------------------------

/// V5：loadDeferred(R1 慢解析 3s) 进行中再发起新调用，R1 晚到不得重开正片。
///
/// [mode]：deferred2（再 loadDeferred R2）、load（再 load S）、dispose（销毁控制器）。
Future<void> _v5(int run, String mode) async {
  const id = 'V5';
  final engine = _track(createMovaEngine(audioOnly: true, options: _opts()));
  final ctrl = MovaAds(engine);
  final opened = <String>[];
  final t0 = _now();
  final sub = engine.events.listen((e) {
    if (e is MovaSourceChange) opened.add('${e.source.title}@+${_now() - t0}ms');
  });
  var r1Done = 0;
  var r1Calls = 0;
  unawaited(
    ctrl.loadDeferred(() async {
      r1Calls++;
      await _wait(3000);
      r1Done = _now() - t0;
      return _s('vod.mp4?r=1', 'R1');
    }),
  );
  await _wait(400);
  switch (mode) {
    case 'deferred2':
      unawaited(ctrl.loadDeferred(() async {
        await _wait(300);
        return _s('ad.mp4?r=2', 'R2');
      }));
    case 'load':
      unawaited(ctrl.load(_s('ad.mp4?r=S', 'S')));
    case 'dispose':
      await ctrl.dispose();
  }
  await _wait(3600); // 跨过 R1 解析完成点（+3000ms）后再等一小段
  final mid = engine.state.sourceTitle;
  await _wait(2500);
  final fin = engine.state.sourceTitle;
  final want = switch (mode) {
    'deferred2' => 'R2',
    'load' => 'S',
    _ => null,
  };
  final onlyWant = mode == 'dispose' ? opened.isEmpty : opened.every((o) => o.startsWith('$want@')) && opened.isNotEmpty;
  _log(id, 'run$run mode=$mode r1ResolverDone=+${r1Done}ms opened=$opened titleAt+4000=$mid titleAtEnd=$fin');
  _result(id, run, onlyWant && fin == want, 'mode=$mode opened=$opened finalTitle=$fin r1ResolvedAt=+${r1Done}ms');
  await sub.cancel();
  if (mode != 'dispose') await ctrl.dispose();
  await engine.dispose();
  r1Calls.toString();
}

// ---------------------------------------------------------------------------
// V6 feed 池同索引重绑（#8）
// ---------------------------------------------------------------------------

/// V6：bind(0,A)→bind(0,B)→bind(0,C)→bind(0,D) 同索引连续重绑，再绑 1 并 focus(0)。
///
/// 期望创建的引擎数不超过 size、旧引擎被复用、同一时刻只有一个引擎在出声。
Future<void> _v6(int run) async {
  const id = 'V6';
  final before = _trs.length;
  var maxCount = 0;
  final pool = MovaFeedEnginePool(engineFactory: _mk, size: 3);
  final apis = <MovaApi>[];
  final srcs = [
    _s('vod.mp4?i=A', 'A'),
    _s('ad.mp4?i=B', 'B'),
    _s('vod.mp4?i=C', 'C'),
    _s('ad.mp4?i=D', 'D'),
  ];
  for (final s in srcs) {
    await pool.bind(0, s, autoPlay: true);
    maxCount = math.max(maxCount, pool.engineCount);
    apis.add(pool.slotFor(0)!.api);
    _log(id, 'run$run bind(0,${s.title}) engineCount=${pool.engineCount} created=${_trs.length - before}');
  }
  await pool.bind(1, _s('vod.mp4?i=E', 'E'));
  maxCount = math.max(maxCount, pool.engineCount);
  await pool.focus(0);
  await _wait(3000);
  final mine = _trs.sublist(before);
  final playing = mine.where((t) => t.api.state.playing).length;
  final moving = mine.where((t) => t.progAt > _now() - 1500).length;
  final reused = apis.every((a) => identical(a, apis.first));
  _log(id, 'run$run created=${mine.length} maxEngineCount=$maxCount playing=$playing movingProgress=$moving sameEngineReusedForIdx0=$reused');
  _result(id, run, mine.length <= 2 && maxCount <= 3 && playing == 1 && moving == 1, 'created=${mine.length} maxCount=$maxCount playing=$playing moving=$moving reused=$reused');
  await pool.dispose();
  await _wait(1500);
  _log(id, 'run$run after pool.dispose undisposed=${mine.where((t) => t.disposedAt == null).length}');
}

// ---------------------------------------------------------------------------
// V7 内核 open 竞态（#1）
// ---------------------------------------------------------------------------

/// V7：先用本机直播 FLV 触发"实时源缓冲限制"（切源时需异步还原），再相隔 [gapMs]
/// 连续 open(A)、open(B)，读 mpv 的 `path` 属性看最终加载的是谁。
Future<void> _v7(int run, int gapMs) async {
  const id = 'V7';
  final player = Player();
  final k = MovaMpvKernel(player: player, audioOnly: true);
  final native = player.platform as NativePlayer;
  await k.open(_u('live.flv?gop=50&audio=1'));
  await _wait(6000);
  final back0 = await native.getProperty('demuxer-max-back-bytes');
  final a = _u('ad.mp4?m=A');
  final b = _u('vod.mp4?m=B');
  final t0 = _now();
  final fa = k.open(a).catchError((Object e) => _log(id, 'open(A) threw $e'));
  if (gapMs > 0) await _wait(gapMs);
  final fb = k.open(b).catchError((Object e) => _log(id, 'open(B) threw $e'));
  await Future.wait([fa, fb]);
  final tOpen = _now() - t0;
  await _wait(4000);
  final path = await native.getProperty('path');
  final back1 = await native.getProperty('demuxer-max-back-bytes');
  final dur = await native.getProperty('duration');
  final isB = path.contains('m=B');
  _log(id, 'run$run gap=${gapMs}ms backBytesBeforeRace=$back0 afterRace=$back1 bothOpenCallsDone=+${tOpen}ms');
  _result(id, run, isB, 'gap=${gapMs}ms finalPath=${path.contains('m=A') ? 'A(错)' : isB ? 'B' : path} duration=$dur');
  await k.dispose();
}

// ---------------------------------------------------------------------------
// V8 dispose 复位方向（#16）
// ---------------------------------------------------------------------------

/// V8：进入全屏/强制横屏后 pop 页面（State.dispose 里 unawaited 销毁引擎）。
///
/// 外部用 adb 采样方向与系统栏；本函数只打标记并记录 Dart 侧窗口尺寸。
Future<void> _v8(String variant) async {
  const id = 'V8';
  final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    final v = ui.PlatformDispatcher.instance.views.first;
    _log(id, 'win ${v.physicalSize.width.toInt()}x${v.physicalSize.height.toInt()} padTop=${v.padding.top.toInt()} padBottom=${v.padding.bottom.toInt()}');
  });
  _log(id, 'MARK page_push variant=$variant');
  await _nav.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => _V8Page(variant)),
  );
  _log(id, 'MARK popped');
  await _wait(10000);
  _log(id, 'MARK end');
  timer.cancel();
}

/// V8 的播放页：进入全屏（可选强制横屏）6 秒后自行 pop。
class _V8Page extends StatefulWidget {
  const _V8Page(this.variant);

  /// landscape（强制横屏 + 全屏）或 fullscreen（仅全屏）。
  final String variant;
  @override
  State<_V8Page> createState() => _V8PageState();
}

class _V8PageState extends State<_V8Page> {
  late final MovaEngine engine = createMovaEngine(audioOnly: true);

  @override
  void initState() {
    super.initState();
    unawaited(_go());
  }

  Future<void> _go() async {
    await engine.open(_s('vod.mp4', 'v8'));
    await engine.setFullscreen(true);
    if (widget.variant == 'landscape') await engine.setOrientation(MovaOrientation.landscape);
    final s = engine.state;
    _log('V8', 'MARK entered fullscreen=${s.fullscreen} orientation=${s.orientation.name}');
    await _wait(6000);
    _log('V8', 'MARK popping');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(engine.dispose());
    _log('V8', 'MARK dispose() called (unawaited)');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('V8')));
}

// ---------------------------------------------------------------------------
// V9 PiP 退出状态（#15，只调研不修）
// ---------------------------------------------------------------------------

/// V9：enterPip() 后由外部 adb 把应用拉回前台（退出 PiP），记录 state.pip。
Future<void> _v9() async {
  _log('V9', 'MARK page_push');
  await _nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const _V9Page()));
  _log('V9', 'MARK popped');
}

/// V9 的播放页：带真实渲染面（MovaPlayer）以便系统 PiP 有画面。
class _V9Page extends StatefulWidget {
  const _V9Page();
  @override
  State<_V9Page> createState() => _V9PageState();
}

class _V9PageState extends State<_V9Page> with WidgetsBindingObserver {
  late final MovaEngine engine = createMovaEngine();
  Timer? _t;
  StreamSubscription<MovaEvent>? _es;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _es = engine.events.listen((e) {
      if (e is MovaPipChange) _log('V9', 'event MovaPipChange(${e.value})');
    });
    unawaited(_go());
  }

  /// 打一行当前状态。
  void _snap(String why) {
    final v = ui.PlatformDispatcher.instance.views.first;
    _log('V9', 'snap $why state.pip=${engine.state.pip} playing=${engine.state.playing} win=${v.physicalSize.width.toInt()}x${v.physicalSize.height.toInt()}');
  }

  Future<void> _go() async {
    await engine.open(_s('vod.mp4', 'v9'));
    await _until(() => engine.state.playing && engine.state.width > 0, const Duration(seconds: 20));
    _snap('before enterPip');
    _log('V9', 'pipSupported=${engine.state.pipSupported}');
    final ok = await engine.enterPip();
    _log('V9', 'MARK enterPip returned $ok');
    _t = Timer.periodic(const Duration(milliseconds: 1000), (_) => _snap('tick'));
    await _wait(30000);
    _log('V9', 'MARK end');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => _log('V9', 'lifecycle ${s.name}');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t?.cancel();
    unawaited(_es?.cancel());
    unawaited(engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: MovaPlayer(api: engine));
}
