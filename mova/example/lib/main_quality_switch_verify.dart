import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// `switchQuality` 换档续播的真机验证探针。
///
/// 验证目标：换档在内核侧是一次 `open()`，紧随其后的续播 seek 若直接下发会被
/// mpv 丢弃、真机上还会把播放器卡死（见 `MovaEngine.open` 的注释）。修复后该
/// seek 走与 `seek()` 相同的寄存判据，应当做到：换档后从原播放位置续播、不从
/// 头开始、也不卡死。
///
/// 判据（刻意先播够 `_kSwitchAfter` 再换档，把三种结局拉开距离）：
/// - 续播成功：换档后很快（数秒内）出现 > 换档前位置的 position。
/// - 从头重播：要等约 `_kSwitchAfter` 那么久才爬回换档前的位置。
/// - 卡死：position 始终不动（且通常停在 0）。
///
/// 跑法：`flutter run -t lib/main_quality_switch_verify.dart -d <id> --release`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _Page()));
}

/// 多码率 HLS 主播放列表（`switchQuality` 只在 uri 含 `.m3u8` 时解析出档位）。
const String _kMaster = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

/// 换档前先播多久——够长才能把"续播"和"从头重播"在时间上区分开。
const Duration _kSwitchAfter = Duration(seconds: 15);

/// 换档后最多观察多久。
const Duration _kObserve = Duration(seconds: 30);

/// 判定"真的往前走了"的位移下限，滤掉乐观上报的目标值本身。
const Duration _kMoved = Duration(milliseconds: 1500);

class _Page extends StatefulWidget {
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final List<String> _log = [];
  bool _done = false;
  final Stopwatch _clock = Stopwatch()..start();

  /// 打一条带时间戳的日志（同时进 logcat 与屏幕）。
  void _mark(String s) {
    final line = '[${_clock.elapsedMilliseconds}ms] $s';
    // ignore: avoid_print
    print('QSWITCH_PROBE $line');
    if (mounted) setState(() => _log.add(line));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  /// 跑完整条验证流程并打印结论。
  Future<void> _run() async {
    // 刻意用默认配置（ABR 开着）：换档重载自身的缓冲一度会被 ABR 记成卡顿，
    // 在换档后约 0.5s 又自动触发一次 downshift、把寄存的续播 seek 冲掉。
    // `switchQuality` 里的 `_abrPolicy.reset()` 就是为这个加的，这里必须开着
    // ABR 才验得到。
    final engine = createMovaEngine();
    Duration? latestPos;
    final progSub = engine.progress.listen((p) => latestPos = p.position);
    final evSub = engine.events.listen((e) {
      if (e is MovaDurationChange) _mark('MovaDurationChange ${e.duration}');
      if (e is MovaQualityChange) _mark('MovaQualityChange ${e.quality.label}');
      if (e is MovaQualityListChange) _mark('MovaQualityListChange n=${e.qualities.length}');
      if (e is MovaErrorEvent) _mark('MovaErrorEvent ${e.error}');
      // MovaSeeked 是寄存的续播 seek 真正补发的唯一外部可见信号
      // （_applyParkedSeek 在下发后发这个事件）。
      if (e is MovaSeek) _mark('MovaSeek ${e.target}');
      if (e is MovaSeeked) _mark('MovaSeeked ${e.position}');
    });

    await engine.open(const MovaSource(_kMaster, title: '多码率 HLS'));
    await _waitPlaying(engine);
    _mark('起播成功，position=$latestPos duration=${engine.state.duration}');

    await engine.loadQualities();
    final qs = engine.state.qualities.where((q) => !q.isAuto).toList();
    _mark('档位解析：${qs.map((q) => '${q.label}(${q.height})').join(', ')}');
    if (qs.length < 2) {
      _mark('=== 结论：档位不足 2 个，无法验证换档 ===');
      await _teardown(engine, progSub, evSub);
      return;
    }
    final cur = engine.state.currentQuality;
    final target = qs.firstWhere((q) => q.uri != cur?.uri, orElse: () => qs.last);

    _mark('先播 ${_kSwitchAfter.inSeconds}s 再换档');
    await Future<void>.delayed(_kSwitchAfter);
    final posBefore = latestPos ?? Duration.zero;
    final tSwitch = _clock.elapsedMilliseconds;
    _mark('换档前 position=$posBefore，切到 ${target.label}（${target.uri}）');

    // 观察窗。判据分两件事，不能混为一谈：
    // ① 续播点对不对——看寄存的 seek 是否补发（MovaSeeked）以及此后 position
    //    有没有掉回 0 附近；
    // ② 播放是否真的继续——看 position 是否越过续播点继续前进。
    // 换档后 position 会先在续播点上停留数秒（新档位缓冲），这是正常的，不能
    // 拿"多久越过续播点"去反推是不是从头重播。
    Duration? firstMoved;
    int? tMoved;
    Duration? lowestAfter;
    final samples = <String>[];
    final watch = engine.progress.listen((p) {
      samples.add('${_clock.elapsedMilliseconds - tSwitch}ms=${p.position.inMilliseconds}ms');
      // 跳过换档瞬间那一两个尚属旧引擎的读数。
      if (_clock.elapsedMilliseconds - tSwitch > 300) {
        final lo = lowestAfter;
        if (lo == null || p.position < lo) lowestAfter = p.position;
      }
      if (firstMoved == null && p.position > posBefore + _kMoved) {
        firstMoved = p.position;
        tMoved = _clock.elapsedMilliseconds - tSwitch;
      }
    });

    await engine.switchQuality(target);
    _mark('switchQuality 返回（耗时 ${_clock.elapsedMilliseconds - tSwitch}ms）');

    final deadline = DateTime.now().add(_kObserve);
    while (firstMoved == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await watch.cancel();

    _mark('换档后 position 采样：${samples.take(40).join(' | ')}');

    final lo = lowestAfter;
    // 掉到"换档前位置 - 3s"以下就算回到了片头附近（真·从头重播会一路到 0）。
    final restarted = lo != null && lo + const Duration(seconds: 3) < posBefore;
    final String verdict;
    if (firstMoved == null) {
      verdict = '卡死或无进展：换档后 ${_kObserve.inSeconds}s 内 position 从未越过 '
          '${posBefore.inMilliseconds}ms（最后读数 ${latestPos?.inMilliseconds}ms，'
          '观察期最低 ${lo?.inMilliseconds}ms）';
    } else if (restarted) {
      verdict = '从头重播：换档前=${posBefore.inMilliseconds}ms，但换档后 position 曾'
          '跌到 ${lo.inMilliseconds}ms，续播点丢失';
    } else {
      verdict = '续播成功：换档前=${posBefore.inMilliseconds}ms，换档后 position 最低'
          '只到 ${lo?.inMilliseconds}ms（未回片头），并在 ${tMoved}ms 时越过换档前'
          '位置继续前进（读数 ${firstMoved!.inMilliseconds}ms）。'
          '停在续播点那几秒是新档位缓冲，属正常。';
    }
    _mark('=== 结论：$verdict ===');
    _mark('最终 currentQuality=${engine.state.currentQuality?.label} '
        'duration=${engine.state.duration} error=${engine.state.error}');

    await _teardown(engine, progSub, evSub);
  }

  /// 拆掉订阅并释放引擎（`dispose()` 挂住本身就是卡死的症状之一）。
  Future<void> _teardown(
    MovaApi engine,
    StreamSubscription<MovaProg> progSub,
    StreamSubscription<MovaEvent> evSub,
  ) async {
    await progSub.cancel();
    await evSub.cancel();
    final t = _clock.elapsedMilliseconds;
    await engine.dispose().timeout(const Duration(seconds: 8), onTimeout: () {
      _mark('!!! dispose() 8s 未返回——播放器已卡死');
    });
    _mark('dispose 完成，耗时 ${_clock.elapsedMilliseconds - t}ms');
    if (mounted) setState(() => _done = true);
  }

  /// 等到真正有播放进度为止。
  Future<void> _waitPlaying(MovaApi engine) {
    final completer = Completer<void>();
    late final StreamSubscription<MovaProg> sub;
    sub = engine.progress.listen((p) {
      if (p.position > Duration.zero && !engine.state.buffering) {
        unawaited(sub.cancel());
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
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
