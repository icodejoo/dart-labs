import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// 0.4.0 无缝切换：中插续播点误差的**定向**真机验证。
///
/// 与 `main_seamless_swap_verify.dart` 组2 的区别（后者测出 2210ms 偏差，怀疑
/// 是探针自身的测量错误）：
/// 1. 一次插播里有**两次** renderEpoch 跳变（正片→广告、广告→正片）。旧探针的
///    Completer 在第一次（正片→广告）就已完成，skip 之后 `await` 立刻返回，
///    读到的其实还是**广告引擎**的 position。本探针按 skip 之后的那一次跳变计。
/// 2. 续播目标不是"调用 playAdNow 那一刻的正片位置"——mid 默认 waitForReady，
///    广告预热期间正片仍在播（pending 阶段），控制器刻意把续播点跟到"广告真正
///    接管那一刻"。所以目标应取**第一次 epoch 跳变前最后一个正片 position**。
///
/// 跑法：`flutter run -t lib/main_resume_accuracy_verify.dart -d <id> --release`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _Page()));
}

MovaSource _content() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '正片',
    );

MovaSource _adSource() => MovaSource(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '广告',
    );

class _Page extends StatefulWidget {
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final List<String> _log = [];
  bool _done = false;
  final Stopwatch _clock = Stopwatch()..start();

  void _mark(String s) {
    final line = '[${_clock.elapsedMilliseconds}ms] $s';
    // ignore: avoid_print
    print('RESUME_PROBE $line');
    if (mounted) setState(() => _log.add(line));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdController(engine, swap: engine);

    Duration? latestPos;
    int epoch = engine.state.renderEpoch;
    // 每次 epoch 跳变前最后一个 position（即"被换下那台引擎"的最终位置）。
    final List<Duration?> posBeforeBump = [];
    final List<int> bumpAtMs = [];
    Completer<void>? awaitingBump;

    final progSub = engine.progress.listen((p) => latestPos = p.position);
    final stateSub = engine.states.listen((s) {
      if (s.renderEpoch == epoch) return;
      epoch = s.renderEpoch;
      posBeforeBump.add(latestPos);
      bumpAtMs.add(_clock.elapsedMilliseconds);
      _mark('renderEpoch -> $epoch（跳变前最后 position=$latestPos）');
      // 换指后先把 latestPos 清空，确保之后读到的一定是新引擎报出来的。
      latestPos = null;
      final c = awaitingBump;
      if (c != null && !c.isCompleted) c.complete();
    });
    final phaseSub = engine.swapPhases.listen((p) => _mark('swapPhase=$p'));
    final adSub = ctrl.changes.listen(
        (_) => _mark('adPhase: showingAd=${ctrl.isShowingAd} pending=${ctrl.isAdPending}'));

    await ctrl.load(_content());
    await _waitPlaying(engine);
    _mark('正片播放中，等待 4s');
    await Future<void>.delayed(const Duration(seconds: 4));
    _mark('playAdNow 之前 position=$latestPos（注意：这不是续播目标，见文件头注释）');

    // 广告接管（第 1 次 epoch 跳变）。
    awaitingBump = Completer<void>();
    await ctrl.playAdNow(MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: _adSource(),
      skippableAfter: Duration.zero,
    ));
    await awaitingBump.future.timeout(const Duration(seconds: 20), onTimeout: () {
      _mark('广告接管的 epoch 跳变 20s 内未发生');
    });
    final target = posBeforeBump.isNotEmpty ? posBeforeBump.first : null;
    _mark('广告已接管，续播目标（接管前最后一个正片 position）=$target');

    // 让广告真播一会儿，给正片影子引擎预热窗口。
    await Future<void>.delayed(const Duration(seconds: 4));
    _mark('广告播放 4s（广告自身 position=$latestPos），现在 skip');

    awaitingBump = Completer<void>();
    final skipAt = _clock.elapsedMilliseconds;
    ctrl.skip();
    await awaitingBump.future.timeout(const Duration(seconds: 15), onTimeout: () {
      _mark('skip 后的 epoch 跳变 15s 内未发生（说明走了非无缝回落路径）');
    });
    final bumped = bumpAtMs.length >= 2;
    final swapMs = bumped ? bumpAtMs[1] - skipAt : -1;

    // 等新引擎报出第一个 progress（throttle 200ms，最多再等 2s）。
    final firstAfter = await _firstProgressAfter(engine, const Duration(seconds: 3));
    final readAt = _clock.elapsedMilliseconds;
    _mark('切换落地后正片第一个 position=$firstAfter（距 skip ${readAt - skipAt}ms）');

    String verdict;
    if (target == null || firstAfter == null) {
      verdict = '结论：读数缺失（target=$target, actual=$firstAfter），无法给出误差。';
    } else {
      final raw = firstAfter.inMilliseconds - target.inMilliseconds;
      final elapsed = readAt - skipAt;
      verdict = '结论：续播目标=${target.inMilliseconds}ms，切换后实测=${firstAfter.inMilliseconds}ms，'
          '原始差=${raw}ms；切换耗时=${swapMs}ms，读数距 skip=${elapsed}ms（这段时间正片已在播，'
          '故扣除后净误差≈${raw - elapsed}ms）。epoch 跳变次数=${bumpAtMs.length}';
    }
    _mark('=== $verdict ===');

    await progSub.cancel();
    await stateSub.cancel();
    await phaseSub.cancel();
    await adSub.cancel();
    await ctrl.dispose();
    await engine.dispose();
    if (mounted) setState(() => _done = true);
  }

  /// 等待引擎报出下一个 progress（切换后第一个）。
  Future<Duration?> _firstProgressAfter(MovaSwapEngine engine, Duration limit) {
    final c = Completer<Duration?>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (!c.isCompleted) c.complete(p.position);
      unawaited(sub.cancel());
    });
    return c.future.timeout(limit, onTimeout: () {
      unawaited(sub.cancel());
      return null;
    });
  }

  Future<void> _waitPlaying(MovaSwapEngine engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero && !engine.state.buffering) {
        unawaited(sub.cancel());
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.timeout(const Duration(seconds: 25), onTimeout: () {
      unawaited(sub.cancel());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Text(
              (_done ? '=== DONE ===\n' : '') + _log.join('\n'),
              style: const TextStyle(
                  color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
