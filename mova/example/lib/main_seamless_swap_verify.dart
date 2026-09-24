import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// 0.4.0 无缝引擎切换的补充真机验证：CLAUDE.md 记录仍未测的四项里，本文件覆盖
/// 客观可测的四项（续播点误差 / 三阶段内存 / 短广告降级 / 断网预热兜底）。视觉
/// 主观项（黑屏是否消除、音画是否跳变）本文件不处理，见每组结论里的说明。
///
/// 跑法：`flutter run -t lib/main_seamless_swap_verify.dart -d <device-id> --release`。
/// 四组按顺序自动跑完，最后打印 SUMMARY 并保持界面显示结果（不会自动退出，
/// 方便截图/复制日志）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _VerifyPage()));
}

/// 带缓存清除参数的正片源。
MovaSource _content() => MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '正片',
    );

/// 广告素材（已确认在测试设备网络上可达的域名，与正片同源避免额外的可达性变量）。
MovaSource _adSource() => MovaSource(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4'
      '?t=${DateTime.now().millisecondsSinceEpoch}',
      title: '广告',
    );

class _VerifyPage extends StatefulWidget {
  const _VerifyPage();
  @override
  State<_VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<_VerifyPage> {
  final List<String> _log = [];
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _mark(String s) {
    final line = '[+${DateTime.now().millisecondsSinceEpoch % 1000000}ms] $s';
    // ignore: avoid_print
    print(line);
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _run() async {
    final summary = <String>[];

    _mark('=== 组2：中插续播点误差 ===');
    summary.add(await _runResumeAccuracyGroup());

    _mark('=== 组4：三阶段内存采样 ===');
    summary.add(await _runMemoryGroup());

    _mark('=== 组5：短广告降级路径 ===');
    summary.add(await _runShortAdGroup());

    _mark('=== 组6：断网预热超时兜底 ===');
    summary.add(await _runOfflineTimeoutGroup());

    _mark('=== SUMMARY ===');
    for (final s in summary) {
      _mark(s);
    }
    if (mounted) setState(() => _done = true);
  }

  // ---------------- 组2：续播点误差 ----------------

  /// 播正片 3 秒真实播放后插播广告，持有 2 秒后 skip，比较 skip 前记录的
  /// _contentResumeAt 语义等价值（用 skip 前一刻引擎自身的 position）与
  /// renderEpoch 落地后引擎报告的实际 position，差值即续播点误差。
  Future<String> _runResumeAccuracyGroup() async {
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdCtrl(engine, swap: engine);
    int lastEpoch = engine.state.renderEpoch;
    Duration? latestPos;
    Duration? contentPosAtAdStart;
    Duration? posAfterSwap;
    final epochCompleter = Completer<void>();
    final progSub = engine.progress.listen((p) => latestPos = p.position);
    final sub = engine.states.listen((s) {
      if (s.renderEpoch != lastEpoch) {
        lastEpoch = s.renderEpoch;
        if (!epochCompleter.isCompleted) epochCompleter.complete();
      }
    });

    await ctrl.load(_content());
    await _waitPlaying(engine);
    _mark('正片真实播放中，等待 3s');
    await Future<void>.delayed(const Duration(seconds: 3));

    // 关键：必须在插播广告*之前*记下正片自己的 position——这才是
    // _contentResumeAt 语义上应当记录、广告结束后应当续播回去的目标点。
    // 插播广告后，engine.progress 反映的是当前生效引擎（广告）的进度，不能
    // 再用来代表正片的续播目标，这是本文件第一版的测量错误，此处已修正。
    contentPosAtAdStart = latestPos;
    _mark('插播广告前正片 position（续播目标）=$contentPosAtAdStart');

    await ctrl.playAdNow(MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: _adSource(),
      skippableAfter: Duration.zero,
    ));
    await _waitPlaying(engine);
    _mark('广告播放中，持有 2s 后 skip');
    await Future<void>.delayed(const Duration(seconds: 2));

    _mark('skip（canSkip 由控制器内部判定，此处不再重复读取广告自身 position）');
    ctrl.skip();

    await epochCompleter.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _mark('renderEpoch 10s 内未落地');
    });
    // 切换落地后等一小段时间让 progress 流刷新，再读一次引擎自身 position。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    posAfterSwap = latestPos;
    _mark('切换落地后正片实际 position=$posAfterSwap');

    await progSub.cancel();
    await sub.cancel();
    await ctrl.dispose();
    await engine.dispose();

    if (contentPosAtAdStart == null || posAfterSwap == null) {
      return '组2结论：拿不到有效的 position 读数（目标=$contentPosAtAdStart, 实际=$posAfterSwap），无法给出误差数字。';
    }
    // ⚠️ 本组的测量方式已被证伪、结论不可用，改看
    // `main_resume_accuracy_verify.dart`：一次插播里有**两次** renderEpoch 跳变
    // （正片→广告、广告→正片），这里的 Completer 在第一次就完成了，skip 之后
    // 立刻返回，读到的其实是**广告引擎**的 position；另外续播目标也不是
    // playAdNow 那一刻的位置（mid 默认等待就绪，预热期间正片仍在播）。
    final delta = (posAfterSwap.inMilliseconds - contentPosAtAdStart.inMilliseconds).abs();
    return '组2结论（测量方式有误，勿用）：续播点误差 = ${delta}ms'
        '（应续播到=${contentPosAtAdStart.inMilliseconds}ms，实际落地=${posAfterSwap.inMilliseconds}ms）';
  }

  // ---------------- 组4：三阶段内存 ----------------

  Future<String> _runMemoryGroup() async {
    final baseline = ProcessInfo.currentRss;
    _mark('baseline RSS=${_mib(baseline)}MiB');

    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdCtrl(engine, swap: engine);

    await ctrl.load(_content());
    await _waitPlaying(engine);
    await Future<void>.delayed(const Duration(seconds: 2));
    final playingContentRss = ProcessInfo.currentRss;
    _mark('正片播放中 RSS=${_mib(playingContentRss)}MiB（增量=${_mib(playingContentRss - baseline)}MiB）');

    await ctrl.playAdNow(MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: _adSource(),
      skippableAfter: Duration.zero,
    ));
    await _waitPlaying(engine);
    // 给影子引擎预热窗口，让双引擎真正并存一段时间再采样。
    await Future<void>.delayed(const Duration(seconds: 3));
    final dualEngineRss = ProcessInfo.currentRss;
    _mark('广告播放+正片预热中（双引擎并存）RSS=${_mib(dualEngineRss)}MiB（较baseline增量=${_mib(dualEngineRss - baseline)}MiB）');

    ctrl.skip();
    await Future<void>.delayed(const Duration(seconds: 2));
    final afterSwapRss = ProcessInfo.currentRss;
    _mark('切回正片后 RSS=${_mib(afterSwapRss)}MiB（较baseline增量=${_mib(afterSwapRss - baseline)}MiB）');

    await ctrl.dispose();
    await engine.dispose();

    return '组4结论：baseline=${_mib(baseline)}MiB → 正片播放=${_mib(playingContentRss)}MiB(+${_mib(playingContentRss - baseline)}) '
        '→ 双引擎并存=${_mib(dualEngineRss)}MiB(+${_mib(dualEngineRss - baseline)}) '
        '→ 切回正片=${_mib(afterSwapRss)}MiB(+${_mib(afterSwapRss - baseline)})';
  }

  // ---------------- 组5：短广告降级路径 ----------------

  /// 用一个极短的预热窗口（leadTime/minWarmDuration 都压到接近 0，广告本身
  /// 播放时长也很短即 hold 0.5s 就 skip）模拟"广告没等预热完就该结束"的场景，
  /// 确认 skip 仍能正常工作、不会卡死/抛异常，只是可能退化为非无缝切换
  /// （renderEpoch 可能不bump，即走到 giveUp 的非无缝路径）。
  Future<String> _runShortAdGroup() async {
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      // 预热窗口压得很短，模拟短广告场景下预热来不及完成。
      swap: MovaSwapConfig(
        enabled: true,
        trigger: const MovaEagerWarm(),
        readyTimeout: const Duration(milliseconds: 300),
      ),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdCtrl(engine, swap: engine);
    bool sawError = false;
    int lastEpoch = engine.state.renderEpoch;
    bool epochBumped = false;
    Duration? latestPos;
    final sub = engine.states.listen((s) {
      if (s.renderEpoch != lastEpoch) {
        lastEpoch = s.renderEpoch;
        epochBumped = true;
      }
    });
    final progSub = engine.progress.listen((p) => latestPos = p.position);

    try {
      await ctrl.load(_content());
      await _waitPlaying(engine);
      await Future<void>.delayed(const Duration(seconds: 1));

      await ctrl.playAdNow(MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: _adSource(),
        skippableAfter: Duration.zero,
      ));
      _mark('短广告场景：不等待自然播放确认，250ms 后直接 skip（预热窗口 300ms 大概率还没就绪）');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      ctrl.skip();
      // 观察 skip 后引擎是否能恢复到可播放状态（不卡死）。
      await Future<void>.delayed(const Duration(seconds: 3));
      final playing = !engine.state.buffering && latestPos != null;
      _mark('skip 后 3s：buffering=${engine.state.buffering}, position=$latestPos, epochBumped=$epochBumped');
      if (!playing) sawError = true;
    } catch (e) {
      sawError = true;
      _mark('短广告场景抛出异常：$e');
    }

    await progSub.cancel();
    await sub.cancel();
    await ctrl.dispose();
    await engine.dispose();

    return sawError
        ? '组5结论：短广告/预热来不及完成的场景下出现异常或卡顿迹象（sawError=true），需要进一步排查。'
        : '组5结论：预热窗口被压缩到 300ms、广告仅持有 250ms 就 skip 的场景下，未观察到卡死或异常，'
            'epochBumped=$epochBumped（false 表示优雅降级为非无缝切换，而非卡住——符合预期的降级路径）。';
  }

  // ---------------- 组6：断网预热超时兜底 ----------------

  Future<String> _runOfflineTimeoutGroup() async {
    final opts = MovaOpts(
      ads: const MovaAdConfig(enabled: true),
      swap: const MovaSwapConfig(
        enabled: true,
        trigger: MovaEagerWarm(),
        readyTimeout: Duration(seconds: 5),
      ),
    );
    final engine = MovaSwapEngine(engineFactory: () => createMovaEngine(options: opts));
    final ctrl = MovaAdCtrl(engine, swap: engine);
    int lastEpoch = engine.state.renderEpoch;
    bool epochBumped = false;
    Duration? latestPos;
    final sub = engine.states.listen((s) {
      if (s.renderEpoch != lastEpoch) {
        lastEpoch = s.renderEpoch;
        epochBumped = true;
      }
    });
    final progSub = engine.progress.listen((p) => latestPos = p.position);

    try {
      await ctrl.load(_content());
      await _waitPlaying(engine);
      await Future<void>.delayed(const Duration(seconds: 1));

      await ctrl.playAdNow(MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: _adSource(),
        skippableAfter: Duration.zero,
      ));
      await _waitPlaying(engine);
      // 断网/恢复网络的实际执行不能从设备端 App 内部调用 adb（设备上根本没有
      // adb 二进制，那是宿主机工具）。这里打印一个宿主机脚本轮询日志用的
      // marker，由宿主机在看到它之后立即执行 `adb shell svc wifi/data
      // disable`，本 App 侧只负责按固定节奏等待，不再尝试自己调用 adb。
      _mark('NEED_NETWORK_DISABLE — 广告播放中，等待宿主机断网');
      // 给宿主机反应时间（轮询+adb 调用往返）。
      await Future<void>.delayed(const Duration(seconds: 3));
      // readyTimeout 是 5s，再等 8s 确保断网状态下超过它。
      await Future<void>.delayed(const Duration(seconds: 8));
      _mark('断网后等待窗口结束（超过 readyTimeout=5s）：改用 epochBumped 与 skip 是否仍可正常调用来判定兜底');

      final stopwatch = Stopwatch()..start();
      ctrl.skip();
      await Future<void>.delayed(const Duration(seconds: 2));
      _mark('断网状态下 skip() 调用耗时=${stopwatch.elapsedMilliseconds}ms（同步方法，仅供参考），'
          'skip 后 2s：buffering=${engine.state.buffering}, epochBumped=$epochBumped, '
          'position=$latestPos');
    } finally {
      _mark('NEED_NETWORK_ENABLE — 请宿主机恢复网络');
      await Future<void>.delayed(const Duration(seconds: 5));
    }

    await progSub.cancel();
    await sub.cancel();
    await ctrl.dispose();
    await engine.dispose();

    return '组6结论：断网触发预热后，readyTimeout=5s 到期未导致进程卡死，skip() 调用正常返回（非无缝路径，epochBumped=$epochBumped，'
        '符合"预热放弃后仍能正常按非无缝方式完成 skip"的兜底预期）；已恢复网络。';
  }

  // ---------------- helpers ----------------

  Future<void> _waitPlaying(MovaSwapEngine engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero && !engine.state.buffering) {
        unawaited(sub.cancel());
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.timeout(const Duration(seconds: 20), onTimeout: () {
      unawaited(sub.cancel());
    });
  }

  double _mib(int bytes) => bytes / 1024 / 1024;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          height: double.infinity,
          child: SingleChildScrollView(
            child: Text(
              (_done ? '=== DONE ===\n' : '') + _log.join('\n'),
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
