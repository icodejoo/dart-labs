import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
// ignore: implementation_imports
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 本轮评审后续修复（V10-V14）的 Android 真机验证页。
///
/// 选组：启动时从 http://127.0.0.1:18082/group 取（adb reverse 到 PC 上的小服务），或编译期
/// `--dart-define=GROUP=v10`。组名：v10（全屏 swap，销毁继任者）、v10x（全屏 swap，退出全屏）、
/// v10c（对照：普通 dispose 会复位方向）、v11、v12、v13a、v13b、v14。
///
/// 日志行 `RFV2|毫秒时间戳|标签|内容`，用 `adb logcat -s flutter` 抓取；`SAMPLE` 行由 PC 侧
/// 脚本触发 dumpsys 采样。本页只用公开 API，可同时编译进修复前的 HEAD 基线。
const _kSrc = String.fromEnvironment('SRC', defaultValue: 'http://127.0.0.1:18080');

/// 每项重复次数。
const _kRuns = 3;

/// 启动参数里的组名。
String _group = const String.fromEnvironment('GROUP', defaultValue: 'v10');

/// 未捕获异常计数。
int _uncaught = 0;

/// 屏幕上回显的日志。
final ValueNotifier<List<String>> _screen = ValueNotifier<List<String>>(<String>[]);

/// 当前挂在界面上的引擎（null 即卸载渲染面）。
final ValueNotifier<MovaApi?> _api = ValueNotifier<MovaApi?>(null);

/// 自增序号，用于给 URL 加防缓存参数。
int _seq = 0;

/// 当前毫秒时间戳。
int _now() => DateTime.now().millisecondsSinceEpoch;

/// 打印一行带时间戳的日志。
void _log(String tag, String msg) {
  final line = 'RFV2|${_now()}|$tag|$msg';
  // ignore: avoid_print
  print(line);
  final l = _screen.value;
  _screen.value = [...l.length > 7 ? l.sublist(l.length - 7) : l, line];
}

/// 打印一条结论行。
void _result(String id, int run, bool pass, String detail) =>
    _log('RESULT', '$id|run$run|${pass ? 'PASS' : 'FAIL'}|$detail');

/// 构造带防缓存参数的本机源 URL。
String _u(String path) => '$_kSrc/$path${path.contains('?') ? '&' : '?'}t=${_now()}${_seq++}';

/// 构造带标题的本机源。
MovaSource _s(String path, String title) => MovaSource(_u(path), title: title);

/// 轮询等待条件成立（仅用于等待，度量取自事件戳）。
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

/// Dart 侧窗口快照：物理尺寸与系统栏内边距。
String _win() {
  final v = ui.PlatformDispatcher.instance.views.first;
  return '${v.physicalSize.width.toInt()}x${v.physicalSize.height.toInt()} padTop=${v.padding.top.toInt()} viewPadTop=${v.viewPadding.top.toInt()} viewPadBot=${v.viewPadding.bottom.toInt()}';
}

/// 当前窗口是否横向。
bool _landscape() {
  final v = ui.PlatformDispatcher.instance.views.first;
  return v.physicalSize.width > v.physicalSize.height;
}

/// 系统栏是否都被隐藏（沉浸）：顶部/底部 viewPadding 皆为 0。
bool _immersive() {
  final v = ui.PlatformDispatcher.instance.views.first;
  return v.viewPadding.top == 0 && v.viewPadding.bottom == 0;
}

/// 请 PC 侧脚本做一次 dumpsys 采样并停留 [hold] 毫秒，之后补一行 Dart 侧窗口。
Future<void> _sample(String tag, {int hold = 2200}) async {
  _log('SAMPLE', tag);
  await _wait(hold);
  _log('WIN', '$tag ${_win()}');
}

/// 验证用选项：swap 开启、readyTimeout 8s、立即预热。
MovaOpts _swapOpts({MovaAdConfig? ads}) => MovaOpts(
  swap: const MovaSwapConfig(enabled: true, readyTimeout: Duration(seconds: 8), trigger: MovaEagerWarm()),
  ads: ads ?? const MovaAdConfig(),
);

/// 创建并挂到界面的 swap 代理（引擎带真实 VideoController）。
MovaSwapEngine _mkProxy(MovaOpts o, {MovaApi Function()? factory}) {
  final p = MovaSwapEngine(engineFactory: factory ?? () => createMovaEngine(options: o));
  _api.value = p;
  return p;
}

/// 卸载渲染面并销毁引擎（先卸载再等一帧，再销毁）。
Future<void> _teardown(MovaApi p) async {
  _api.value = null;
  await _wait(150);
  await p.dispose();
}

/// 剩余的"强制 open 抛异常"次数。
int _throwBudget = 0;

/// 预算内对含 `throwme` 的地址让 open 抛 StateError，其余走真实 mpv 内核（带视频）。
class _ThrowKernel extends MovaMpvKernel {
  _ThrowKernel() : super(lazyVideo: true);

  @override
  Future<void> open(String uri, {bool play = true}) async {
    if (_throwBudget > 0 && uri.contains('throwme')) {
      _throwBudget--;
      throw StateError('forced shadow open failure');
    }
    return super.open(uri, play: play);
  }
}

/// 每次 pause() 额外延迟的毫秒数；V12b 用它拉长 swap 提交前旧引擎仍在 tick 的窗口。
int _pauseDelayMs = 0;

/// 按 [_pauseDelayMs] 延迟 pause 的内核（带视频，其余走真实 mpv）。
class _SlowPauseKernel extends MovaMpvKernel {
  _SlowPauseKernel() : super(lazyVideo: true);

  @override
  Future<void> pause() async {
    if (_pauseDelayMs > 0) await Future<void>.delayed(Duration(milliseconds: _pauseDelayMs));
    return super.pause();
  }
}

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
      runApp(const MaterialApp(home: _Home()));
    },
    (e, s) {
      _uncaught++;
      _log('UNCAUGHT', 'Zone $e\n$s');
    },
  );
}

/// 首页：渲染面 + 日志浮层，按组名跑验证。
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
    _log('START', 'group=$_group win=${_win()}');
    for (final g in _group == 'all' ? ['v10', 'v10x', 'v10c', 'v11', 'v12', 'v12b', 'v13a', 'v13b', 'v14'] : [_group]) {
      _log('GROUP', 'begin $g');
      try {
        switch (g) {
          case 'v10':
            for (var i = 1; i <= _kRuns; i++) {
              await _v10(i, exitFullscreen: false);
            }
          case 'v10x':
            for (var i = 1; i <= 2; i++) {
              await _v10(i, exitFullscreen: true);
            }
          case 'v10c':
            await _v10c();
          case 'v11':
            for (var i = 1; i <= _kRuns; i++) {
              await _v11(i);
            }
          case 'v12':
            for (var i = 1; i <= _kRuns; i++) {
              await _v12(i);
            }
          case 'v12b':
            for (var i = 1; i <= _kRuns; i++) {
              await _v12(i, slowPause: true);
            }
          case 'v13a':
            for (var i = 1; i <= _kRuns; i++) {
              await _v13(i, now: false);
            }
          case 'v13b':
            for (var i = 1; i <= _kRuns; i++) {
              await _v13(i, now: true);
            }
          case 'v14':
            for (var i = 1; i <= _kRuns; i++) {
              await _v14(i);
            }
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
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(
          child: ValueListenableBuilder<MovaApi?>(
            valueListenable: _api,
            builder: (_, a, _) => a == null ? const SizedBox.shrink() : MovaPlayer(api: a),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: _screen,
              builder: (_, l, _) => Text(l.join('\n'), style: const TextStyle(fontSize: 8, color: Colors.white70)),
            ),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// V10 全屏 swap 方向（MovaHandoffRetirable）
// ---------------------------------------------------------------------------

/// V10：全屏播放中 swapTo 另一条源。swap 提交后继任者应继承全屏、平台方向仍横屏、系统栏仍隐藏；
/// 之后 [exitFullscreen] 为 true 走 setFullscreen(false)，否则直接销毁继任者，方向应回到自动/竖屏。
Future<void> _v10(int run, {required bool exitFullscreen}) async {
  final id = exitFullscreen ? 'V10x' : 'V10';
  final proxy = _mkProxy(_swapOpts());
  var pos = Duration.zero;
  final sub = proxy.progress.listen((p) => pos = p.position);
  await proxy.open(_s('vod.mp4', 'A'));
  await _until(() => pos > const Duration(seconds: 1) && proxy.state.rendered, const Duration(seconds: 20));
  await proxy.setFullscreen(true);
  await _wait(1200);
  var st = proxy.state;
  _log(id, 'run$run before: fs=${st.fullscreen} ori=${st.orientation.name} video=${st.width}x${st.height} epoch=${st.renderEpoch} win=${_win()}');
  final fsBefore = _landscape() && _immersive();
  await _sample('${id}_run${run}_before_swap');
  final t0 = _now();
  final ok = await proxy.swapTo(_s('ad.mp4', 'B'));
  final t1 = _now();
  await _wait(1200);
  st = proxy.state;
  final landAfter = _landscape();
  final immAfter = _immersive();
  _log(id, 'run$run swapTo=$ok in ${t1 - t0}ms; successor fs=${st.fullscreen} ori=${st.orientation.name} title=${st.sourceTitle} epoch=${st.renderEpoch} landscape=$landAfter immersive=$immAfter');
  final succFs = st.fullscreen;
  await _sample('${id}_run${run}_after_swap');
  var portraitBack = false;
  var barsBack = false;
  if (exitFullscreen) {
    await proxy.setFullscreen(false);
    await _wait(1200);
    portraitBack = !_landscape();
    barsBack = !_immersive();
    _log(id, 'run$run after setFullscreen(false): fs=${proxy.state.fullscreen} landscape=${_landscape()} immersive=${_immersive()}');
    await _sample('${id}_run${run}_after_exit');
    await _teardown(proxy);
  } else {
    await _teardown(proxy);
    await _wait(1200);
    portraitBack = !_landscape();
    barsBack = !_immersive();
    _log(id, 'run$run after dispose: landscape=${_landscape()} immersive=${_immersive()}');
    await _sample('${id}_run${run}_after_dispose');
  }
  await sub.cancel();
  _result(id, run, fsBefore && ok && succFs && landAfter && immAfter && portraitBack && barsBack,
      'preFsLandscapeImmersive=$fsBefore swapTo=$ok successorFs=$succFs landscapeAfterSwap=$landAfter immersiveAfterSwap=$immAfter restoredPortrait=$portraitBack barsRestored=$barsBack');
}

/// V10c 对照：两台普通引擎，E1 全屏、E2 继承全屏后，**不打退役标记**地销毁 E1，
/// 观察平台方向被旧引擎 dispose 复位（这正是 MovaHandoffRetirable 要避免的）。
Future<void> _v10c() async {
  const id = 'V10c';
  for (var run = 1; run <= 2; run++) {
    final e1 = createMovaEngine();
    _api.value = e1;
    await e1.open(_s('vod.mp4', 'E1'));
    await _until(() => e1.state.rendered, const Duration(seconds: 20));
    await e1.setFullscreen(true);
    await _wait(1000);
    final e2 = createMovaEngine();
    await e2.open(_s('ad.mp4', 'E2'));
    await e2.setFullscreen(true);
    _api.value = e2;
    await _until(() => e2.state.rendered, const Duration(seconds: 20));
    await _wait(1000);
    final before = _landscape() && _immersive();
    _log(id, 'run$run before plain dispose of E1: landscape=${_landscape()} immersive=${_immersive()} e2.fs=${e2.state.fullscreen}');
    await _sample('${id}_run${run}_before');
    await e1.dispose();
    await _wait(1200);
    final reset = !_landscape() || !_immersive();
    _log(id, 'run$run after plain dispose of E1: landscape=${_landscape()} immersive=${_immersive()} e2.fs=${e2.state.fullscreen}');
    await _sample('${id}_run${run}_after_plain_dispose');
    _result(id, run, before && reset, 'baselineFsOk=$before platformResetByPlainDispose=$reset (PASS 表示"确认旧引擎普通 dispose 会复位", 即退役标记确有必要)');
    await _teardown(e2);
    await _wait(800);
  }
}

// ---------------------------------------------------------------------------
// V11 非全屏强制横屏 swap
// ---------------------------------------------------------------------------

/// V11：非全屏 + setOrientation(landscape) 后 swapTo；继任者 orientation 应为 landscape；
/// 销毁继任者后方向被复位（回竖屏）。
Future<void> _v11(int run) async {
  const id = 'V11';
  final proxy = _mkProxy(_swapOpts());
  var pos = Duration.zero;
  final sub = proxy.progress.listen((p) => pos = p.position);
  await proxy.open(_s('vod.mp4', 'A'));
  await _until(() => pos > const Duration(seconds: 1) && proxy.state.rendered, const Duration(seconds: 20));
  await proxy.setOrientation(MovaOrientation.landscape);
  await _wait(1200);
  _log(id, 'run$run before: fs=${proxy.state.fullscreen} ori=${proxy.state.orientation.name} landscape=${_landscape()} win=${_win()}');
  final landBefore = _landscape();
  await _sample('${id}_run${run}_before_swap');
  final ok = await proxy.swapTo(_s('ad.mp4', 'B'));
  await _wait(1200);
  final st = proxy.state;
  final landAfter = _landscape();
  _log(id, 'run$run swapTo=$ok successor ori=${st.orientation.name} fs=${st.fullscreen} title=${st.sourceTitle} landscape=$landAfter');
  await _sample('${id}_run${run}_after_swap');
  final succOri = st.orientation;
  await _teardown(proxy);
  await _wait(1200);
  final portraitBack = !_landscape();
  _log(id, 'run$run after dispose: landscape=${_landscape()}');
  await _sample('${id}_run${run}_after_dispose');
  await sub.cancel();
  _result(id, run, landBefore && ok && succOri == MovaOrientation.landscape && landAfter && portraitBack,
      'preLandscape=$landBefore swapTo=$ok successorOrientation=${succOri.name} landscapeAfterSwap=$landAfter restoredPortrait=$portraitBack');
}

// ---------------------------------------------------------------------------
// V12 广告首帧不误超时
// ---------------------------------------------------------------------------

/// V12：两条中插广告串成 pod（同 offset），第二条经 `swapTo` 走 swap（`_playAd` 的 oneShot 路径）。
/// loadTimeout 3s、durationFromFirstFrame、第二条广告位 6s。[slowPause] 为 true 时内核 pause 延迟 1.5s，
/// 拉长 swapTo 落定前旧引擎仍在 tick 的窗口。期望：不触发 failed；AD2 的 completed 距其 swap 提交
/// （第二次 renderEpoch 递增）约 6s；并统计 AD2 started 之后、其 epoch 落定之前到达的旧引擎 tick 数。
Future<void> _v12(int run, {bool slowPause = false}) async {
  final id = slowPause ? 'V12b' : 'V12';
  final at = <String, int>{};
  var failed = 0;
  final failKinds = <Object?>[];
  final brk1 = MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: _s('ad.mp4?p=1', 'AD1'),
    offset: const Duration(seconds: 3),
    duration: const Duration(seconds: 4),
    skippableAfter: const Duration(seconds: 2),
  );
  final brk2 = MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: _s('ad.mp4?p=2', 'AD2'),
    offset: const Duration(seconds: 3),
    duration: const Duration(seconds: 6),
    skippableAfter: const Duration(seconds: 2),
  );
  final opts = _swapOpts(
    ads: MovaAdConfig(
      enabled: true,
      breaks: [brk1, brk2],
      loadTimeout: const Duration(seconds: 3),
      onAdEvent: (e) {
        final k = '${e.type.name}:${e.adBreak.source.title}';
        at.putIfAbsent(k, _now);
        _log(id, 'run$run adEvent $k${e.error != null ? ' error=${e.error}' : ''}');
        if (e.type == MovaAdEventType.failed) {
          failed++;
          failKinds.add(e.error);
        }
      },
    ),
  );
  _pauseDelayMs = slowPause ? 1500 : 0;
  final proxy = slowPause
      ? _mkProxy(opts, factory: () => MovaEngine(kernel: _SlowPauseKernel(), options: opts))
      : _mkProxy(opts);
  final ctrl = MovaAdController(proxy, swap: proxy);
  final epochTimes = <int>[];
  var ticksInWindow = 0;
  var lastEpoch = proxy.state.renderEpoch;
  final poll = Timer.periodic(const Duration(milliseconds: 20), (_) {
    final e = proxy.state.renderEpoch;
    if (e != lastEpoch) {
      lastEpoch = e;
      epochTimes.add(_now());
    }
  });
  final phSub = proxy.swapPhases.listen((ph) => _log(id, 'run$run swapPhase=${ph.name}'));
  int? ad2Frame;
  final errSub = proxy.events.listen((e) {
    if (e is MovaErrorEvent) _log(id, 'run$run proxy MovaErrorEvent ${e.error}');
    if (e is MovaFirstFrame && at['started:AD2'] != null && ad2Frame == null) {
      ad2Frame = _now();
      _log(id, 'run$run AD2 MovaFirstFrame signal=${e.signal}');
    }
  });
  var lastSt = '';
  final stPoll = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final st = proxy.state;
    final cur = 'title=${st.sourceTitle} epoch=${st.renderEpoch} rendered=${st.rendered} playing=${st.playing} buffering=${st.buffering} phase=${proxy.swapPhase.name}';
    if (cur != lastSt) {
      lastSt = cur;
      _log(id, 'run$run st $cur');
    }
  });
  final psub = proxy.progress.listen((p) {
    if (at['started:AD2'] != null && !epochTimes.any((t) => t >= at['started:AD2']!)) ticksInWindow++;
  });
  await ctrl.load(_s('vod.mp4', 'C'));
  await _until(() => at['completed:AD2'] != null || failed > 0, const Duration(seconds: 50));
  await _wait(2500);
  poll.cancel();
  stPoll.cancel();
  await phSub.cancel();
  await errSub.cancel();
  await psub.cancel();
  final s2 = at['started:AD2'];
  final c2 = at['completed:AD2'];
  // AD2 的 swap 落定 = 其 started 之后的第一次 epoch 变化；全部 epoch 相对 AD2 started 的偏移也记录下来。
  final after = s2 == null ? <int>[] : epochTimes.where((t) => t >= s2).toList();
  final e2 = after.isEmpty ? 0 : after.first;
  final rel = s2 == null ? '[]' : epochTimes.map((t) => t - s2).toList().toString();
  // 槽位时长：AD2 自身首帧事件 -> AD2 completed（durationFromFirstFrame 下应约等于配置的 6s）。
  // 真换指时新引擎早已出画，不再发 MovaFirstFrame；此时以 epoch 落定作为起点。
  final slotStart = ad2Frame ?? (e2 != 0 ? e2 : null);
  final fromEpoch = slotStart != null && c2 != null ? c2 - slotStart : -1;
  final fromStart = s2 != null && c2 != null ? c2 - s2 : -1;
  final swapGap = s2 != null && e2 != 0 ? e2 - s2 : -1;
  _log(id, 'run$run epochs=${epochTimes.length} epochRelToAD2Started=$rel AD2 started->epochChange=${swapGap}ms started->completed=${fromStart}ms adFirstFrame->completed=${fromEpoch}ms oldTicksInWindow=$ticksInWindow failed=$failed($failKinds)');
  _result(id, run, failed == 0 && c2 != null && fromEpoch >= 5600 && fromEpoch <= 6700,
      'failed=$failed AD2completed=${c2 != null} adFirstFrame->completed=${fromEpoch}ms (cfg 6000) started->completed=${fromStart}ms started->epochChange=${swapGap}ms oldTicksBeforeEpoch=$ticksInWindow');
  _pauseDelayMs = 0;
  await ctrl.dispose();
  await _teardown(proxy);
}

// ---------------------------------------------------------------------------
// V13 倍速恢复
// ---------------------------------------------------------------------------

/// V13：正片倍速 → 广告 → 返回。[now] 为 false：正片 2x，走排期中插；true：刚改 1.5x
/// 紧接着 playAdNow。期望广告期间 rate==1，返回后恢复原倍速。
Future<void> _v13(int run, {required bool now}) async {
  final id = now ? 'V13b' : 'V13a';
  final want = now ? 1.5 : 2.0;
  final at = <MovaAdEventType, int>{};
  final brk = MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: _s('ad.mp4', 'AD'),
    offset: const Duration(seconds: 6),
    duration: Duration(seconds: now ? 4 : 5),
    skippableAfter: const Duration(seconds: 2),
  );
  final opts = _swapOpts(
    ads: MovaAdConfig(
      enabled: true,
      breaks: now ? const [] : [brk],
      onAdEvent: (e) {
        at.putIfAbsent(e.type, _now);
        _log(id, 'run$run adEvent ${e.type.name}');
      },
    ),
  );
  final proxy = _mkProxy(opts);
  final ctrl = MovaAdController(proxy, swap: proxy);
  var last = '';
  var pos13 = Duration.zero;
  final p13 = proxy.progress.listen((p) => pos13 = p.position);
  final adRates = <double>[];
  final poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
    final s = proxy.state;
    final cur = 'rate=${s.rate} title=${s.sourceTitle} epoch=${s.renderEpoch}';
    if (cur != last) {
      last = cur;
      _log(id, 'run$run state $cur');
    }
    if (s.sourceTitle == 'AD' && at[MovaAdEventType.completed] == null) adRates.add(s.rate);
  });
  await ctrl.load(_s('vod.mp4', 'C'));
  await _until(() => proxy.state.rendered && pos13 > Duration.zero, const Duration(seconds: 20));
  await _wait(now ? 2500 : 800);
  await proxy.setRate(want);
  _log(id, 'run$run setRate($want) -> state.rate=${proxy.state.rate}');
  if (now) unawaited(ctrl.playAdNow(brk));
  await _until(() => at[MovaAdEventType.completed] != null, const Duration(seconds: 40));
  final completedAt = at[MovaAdEventType.completed];
  await _until(() => proxy.state.sourceTitle == 'C' && proxy.state.rendered, const Duration(seconds: 15));
  await _wait(3000);
  poll.cancel();
  final back = proxy.state.rate;
  final adMax = adRates.isEmpty ? -1.0 : adRates.reduce((a, b) => a > b ? a : b);
  final adSettled = adRates.length > 8 ? adRates.sublist(adRates.length ~/ 3).every((r) => r == 1.0) : false;
  _log(id, 'run$run completedAt=$completedAt adRateSamples=${adRates.length} adMaxRate=$adMax adSettled1x=$adSettled backRate=$back title=${proxy.state.sourceTitle}');
  await p13.cancel();
  _result(id, run, adSettled && back == want, 'adRate settled1x=$adSettled (max seen ${adMax}x over ${adRates.length} samples) rateAfterReturn=$back want=$want');
  await ctrl.dispose();
  await _teardown(proxy);
}

// ---------------------------------------------------------------------------
// V14 预热失败不跳广告
// ---------------------------------------------------------------------------

/// V14：前贴片广告在播，正片在影子引擎里预热时 open 抛异常（预算 1 次）。
/// 期望广告不被判失败/跳过、播完 duration 后正常进正片，且广告期间主事件流没有 MovaErrorEvent。
Future<void> _v14(int run) async {
  const id = 'V14';
  final at = <MovaAdEventType, int>{};
  var failed = 0;
  var skipped = 0;
  var errorsDuringAd = 0;
  final brk = MovaAdBreak(
    kind: MovaAdBreakKind.pre,
    source: _s('ad.mp4', 'AD'),
    duration: const Duration(seconds: 8),
    skippableAfter: const Duration(seconds: 2),
  );
  final opts = _swapOpts(
    ads: MovaAdConfig(
      enabled: true,
      breaks: [brk],
      onAdEvent: (e) {
        at.putIfAbsent(e.type, _now);
        _log(id, 'run$run adEvent ${e.type.name}${e.error != null ? ' error=${e.error}' : ''}');
        if (e.type == MovaAdEventType.failed) failed++;
        if (e.type == MovaAdEventType.skipped) skipped++;
      },
    ),
  );
  _throwBudget = 0;
  final proxy = _mkProxy(opts, factory: () => MovaEngine(kernel: _ThrowKernel(), options: opts));
  final esub = proxy.events.listen((e) {
    if (e is MovaErrorEvent) {
      _log(id, 'run$run proxy MovaErrorEvent ${e.error}');
      if (at[MovaAdEventType.started] != null && at[MovaAdEventType.completed] == null) errorsDuringAd++;
    }
  });
  var pos = Duration.zero;
  final psub = proxy.progress.listen((p) => pos = p.position);
  _throwBudget = 1;
  final ctrl = MovaAdController(proxy, swap: proxy);
  await ctrl.load(MovaSource(_u('vod.mp4?throwme=1'), title: 'C'));
  await _until(() => at[MovaAdEventType.completed] != null || failed > 0 || skipped > 0, const Duration(seconds: 30));
  final adDone = _now();
  final budgetLeft = _throwBudget;
  final reachedContent = await _until(() => proxy.state.sourceTitle == 'C' && pos > Duration.zero, const Duration(seconds: 15));
  final started = at[MovaAdEventType.started];
  final completed = at[MovaAdEventType.completed];
  final adLen = started != null && completed != null ? completed - started : -1;
  _log(id, 'run$run started->completed=${adLen}ms failed=$failed skipped=$skipped errorEventsDuringAd=$errorsDuringAd shadowThrowFired=${budgetLeft == 0} contentPlaying=$reachedContent title=${proxy.state.sourceTitle} adDoneAt=$adDone');
  _result(id, run, failed == 0 && skipped == 0 && completed != null && errorsDuringAd == 0 && budgetLeft == 0 && reachedContent && adLen >= 7000,
      'failed=$failed skipped=$skipped adPlayed=${adLen}ms (cfg 8000) errorEventsDuringAd=$errorsDuringAd shadowOpenThrew=${budgetLeft == 0} contentReached=$reachedContent');
  _throwBudget = 0;
  await esub.cancel();
  await psub.cancel();
  await ctrl.dispose();
  await _teardown(proxy);
}
