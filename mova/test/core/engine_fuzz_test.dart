import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/rate.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/state/ui_state.dart';

import '../support/fake_kernel.dart';

/// Seeds replayed on every run; fixed so a failure is reproducible by number.
///
/// 每次都回放的固定种子；失败时凭编号即可复现。
const _seeds = <int>[1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597];

/// Random actions per seed.
///
/// 每个种子的随机动作数。
const _stepsPerSeed = 150;

/// Actions fired after `dispose()` to check the post-dispose contract.
///
/// `dispose()` 之后追加的动作数，用来检查销毁后的契约。
const _stepsAfterDispose = 25;

/// Sources the fuzzer rotates through (two VOD, one live).
///
/// 模糊测试轮换使用的源（两个点播、一个直播）。
const _sources = <MovaSource>[
  MovaSource('https://host/a.mp4'),
  MovaSource('https://host/b.m3u8'),
  MovaSource('https://host/live.m3u8', type: MovaStreamType.live),
];

/// A small ladder seeded into `state.qualities` so `switchQuality` has targets.
///
/// 注入 `state.qualities` 的小型档位表，让 `switchQuality` 有目标可选。
const _ladder = <MovaQuality>[
  MovaQuality(label: '自动', uri: '', isAuto: true),
  MovaQuality(label: '720p', uri: 'https://host/720.m3u8', height: 720),
  MovaQuality(label: '360p', uri: 'https://host/360.m3u8', height: 360),
];

/// Hostile numeric inputs mixed into every numeric verb.
///
/// 混入各数值类动词的恶意输入。
const _wild = <double>[
  double.nan,
  double.infinity,
  double.negativeInfinity,
  -1e9,
  -1,
  0,
  0.1,
  1,
  3.7,
  50,
  101,
  1e9,
];

/// Mirrors what the engine promises to hold, updated alongside each action.
///
/// 随每个动作同步更新的镜像，记录引擎承诺保持的取值。
class _Mirror {
  bool playing = false;
  bool locked = false;
  bool fullscreen = false;
  MovaFit fit = MovaFit.contain;
  MovaOrientation orientation = MovaOrientation.auto;
  bool mini = false;
}

/// One fuzz run's findings: the action trail plus whatever went wrong.
///
/// 一次模糊运行的结果：动作轨迹加上出现的问题。
class _Run {
  final List<String> trail = <String>[];
  final List<String> problems = <String>[];

  /// Uncaught async errors (zone) plus invariant violations, with the seed and
  /// the full action sequence so the failure can be replayed by hand.
  ///
  /// 未捕获的异步错误（zone）与不变量违例，附带种子和完整动作序列，便于手动复现。
  String report(int seed) =>
      'seed=$seed\nproblems:\n  ${problems.join('\n  ')}\nactions (${trail.length}):\n  ${trail.join('\n  ')}';
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// Runs one seeded random session against a fresh engine and returns what it saw.
///
/// 用一个新引擎跑一次带种子的随机会话，返回观察结果。
Future<_Run> _runSeed(int seed, {int steps = _stepsPerSeed}) async {
  final run = _Run();
  final rnd = Random(seed);
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await _session(rnd, run, steps);
      } catch (e, st) {
        run.problems.add('session threw: $e\n$st');
      } finally {
        done.complete();
      }
    },
    (e, st) => run.problems.add('uncaught async error: $e\n$st'),
  );
  await done.future;
  // Give any stray async error a last chance to surface in the zone.
  // 给游离的异步错误最后一次在 zone 里冒出来的机会。
  await Future<void>.delayed(const Duration(milliseconds: 5));
  return run;
}

Future<void> _session(Random rnd, _Run run, int steps) async {
  final k = FakeKernel();
  final e = MovaEngine(kernel: k);
  final m = _Mirror();
  final events = <MovaEvent>[];
  var eventsDone = false;
  e.events.listen(events.add, onDone: () => eventsDone = true);

  double pick() => _wild[rnd.nextInt(_wild.length)];
  Duration secs(int max) => Duration(seconds: rnd.nextInt(max * 2) - max);

  /// Runs action number [n], appending its name to the trail first.
  ///
  /// 执行第 [n] 号动作，并先把动作名写进轨迹。
  Future<void> act(int n) async {
    switch (n) {
      case 0:
        final s = _sources[rnd.nextInt(_sources.length)];
        final play = rnd.nextBool();
        run.trail.add('open(${s.uri}, autoPlay: $play)');
        await e.open(s, autoPlay: play);
      case 1:
        run.trail.add('play()');
        await e.play();
      case 2:
        run.trail.add('pause()');
        await e.pause();
      case 3:
        run.trail.add('playOrPause()');
        await e.playOrPause();
      case 4:
        final d = secs(900);
        run.trail.add('seek($d)');
        await e.seek(d);
      case 5:
        final d = secs(120);
        run.trail.add('seekBy($d)');
        await e.seekBy(d);
      case 6:
        final v = pick();
        run.trail.add('setRate($v)');
        await e.setRate(v);
      case 7:
        final v = pick();
        run.trail.add('setVolume($v)');
        await e.setVolume(v);
      case 8:
        final v = pick();
        run.trail.add('setBrightness($v)');
        await e.setBrightness(v);
      case 9:
        final f = MovaFit.values[rnd.nextInt(MovaFit.values.length)];
        run.trail.add('setFit($f)');
        await e.setFit(f);
        m.fit = f;
      case 10:
        final v = pick();
        run.trail.add('setZoom($v)');
        await e.setZoom(v);
      case 11:
        final v = rnd.nextBool();
        run.trail.add('setLocked($v)');
        await e.setLocked(v);
        m.locked = v;
      case 12:
        final v = rnd.nextBool();
        run.trail.add('setFullscreen($v)');
        await e.setFullscreen(v);
        m.fullscreen = v;
      case 13:
        final v = rnd.nextBool();
        run.trail.add('setMini($v)');
        final wasMini = m.mini;
        await e.setMini(v);
        m.mini = v;
        // Only a real transition into mini leaves fullscreen; a repeated
        // setMini(true) is an idempotent no-op.
        // 只有真正切入小窗才会退出全屏；重复的 setMini(true) 是幂等空操作。
        if (v && !wasMini) m.fullscreen = false;
      case 14:
        final o = MovaOrientation.values[rnd.nextInt(MovaOrientation.values.length)];
        run.trail.add('setOrientation($o)');
        await e.setOrientation(o);
        m.orientation = o;
      case 15:
        run.trail.add('debugSetQualities(ladder)');
        e.debugSetQualities(_ladder, current: _ladder.first);
      case 16:
        final q = _ladder[rnd.nextInt(_ladder.length)];
        run.trail.add('switchQuality(${q.label})');
        await e.switchQuality(q);
      case 17:
        run.trail.add('reload()');
        await e.reload();
      case 18:
        run.trail.add('showControls()');
        e.showControls(sticky: rnd.nextBool());
      case 19:
        run.trail.add('hideControls()');
        e.hideControls();
      case 20:
        run.trail.add('showHud()');
        e.showHud(MovaHud.values[rnd.nextInt(MovaHud.values.length)], text: rnd.nextBool() ? 'x' : null);
      case 21:
        final v = rnd.nextBool();
        run.trail.add('kernel.emitPlaying($v)');
        k.emitPlaying(v);
        m.playing = v;
      case 22:
        final d = Duration(seconds: rnd.nextInt(600));
        run.trail.add('kernel.emitDuration($d)');
        k.emitDuration(d);
      case 23:
        final d = Duration(seconds: rnd.nextInt(600));
        run.trail.add('kernel.emitPosition($d)');
        k.emitPosition(d);
      case 24:
        final v = rnd.nextBool();
        run.trail.add('kernel.emitBuffering($v)');
        k.emitBuffering(v);
      case 25:
        final v = rnd.nextBool();
        run.trail.add('kernel.emitCompleted($v)');
        k.emitCompleted(v);
      case 26:
        final w = 160 * (1 + rnd.nextInt(12));
        run.trail.add('kernel.emitSize($w, ${w ~/ 16 * 9})');
        k.emitSize(w, w ~/ 16 * 9);
      case 27:
        run.trail.add('kernel.emitError(boom)');
        k.emitError('boom');
      default:
        run.trail.add('backToLiveEdge()');
        await e.backToLiveEdge();
    }
  }

  /// Checks what must hold after any action sequence.
  ///
  /// 检查任意动作序列之后都必须成立的性质。
  void check(String after) {
    final s = e.state;
    void bad(String what) => run.problems.add('after $after: $what');
    if (s.volume.isNaN || s.volume < 0 || s.volume > 100) bad('volume ${s.volume} outside 0..100');
    if (s.brightness.isNaN || s.brightness < 0 || s.brightness > 1) bad('brightness ${s.brightness} outside 0..1');
    if (s.zoom.isNaN || s.zoom < 1) bad('zoom ${s.zoom} below 1');
    if (s.rate.isNaN || s.rate < kMovaMinRate || s.rate > kMovaMaxRate) bad('rate ${s.rate} outside the rate range');
    if (s.playing != m.playing) bad('state.playing=${s.playing}, last kernel report was ${m.playing}');
    if (s.locked != m.locked) bad('state.locked=${s.locked}, expected ${m.locked}');
    if (s.fit != m.fit) bad('state.fit=${s.fit}, expected ${m.fit}');
    if (s.orientation != m.orientation) bad('state.orientation=${s.orientation}, expected ${m.orientation}');
    if (s.mini != m.mini) bad('state.mini=${s.mini}, expected ${m.mini}');
    if (s.fullscreen != m.fullscreen) bad('state.fullscreen=${s.fullscreen}, expected ${m.fullscreen}');
    if (s.duration.isNegative) bad('duration ${s.duration} is negative');
    if (s.width < 0 || s.height < 0) bad('size ${s.width}x${s.height} is negative');
  }

  /// Every numeric event payload must honour the same bounds as state.
  ///
  /// 所有数值型事件的载荷都要遵守与 state 相同的边界。
  void checkEvents() {
    for (final ev in events) {
      if (ev is MovaVolumeChange && (ev.value.isNaN || ev.value < 0 || ev.value > 100)) {
        run.problems.add('MovaVolumeChange(${ev.value}) outside 0..100');
      }
      if (ev is MovaBrightChange && (ev.value.isNaN || ev.value < 0 || ev.value > 1)) {
        run.problems.add('MovaBrightChange(${ev.value}) outside 0..1');
      }
      if (ev is MovaZoomChange && (ev.zoom.isNaN || ev.zoom < 1)) {
        run.problems.add('MovaZoomChange(${ev.zoom}) below 1');
      }
      if (ev is MovaRateChange && (ev.value.isNaN || ev.value < kMovaMinRate || ev.value > kMovaMaxRate)) {
        run.problems.add('MovaRateChange(${ev.value}) outside the rate range');
      }
    }
  }

  const actionCount = 29;
  for (var i = 0; i < steps; i++) {
    final n = rnd.nextInt(actionCount);
    await act(n);
    await _flush();
    check(run.trail.last);
  }
  checkEvents();

  // Tear down the way a host must: leave mini first (dispose asserts on it).
  // 按宿主应有的方式收尾：先退出小窗（dispose 对此有断言）。
  run.trail.add('setMini(false)');
  await e.setMini(false);
  run.trail.add('dispose()');
  final doneStates = Completer<void>();
  final doneUi = Completer<void>();
  e.states.listen((_) {}, onDone: doneStates.complete);
  e.uiStates.listen((_) {}, onDone: doneUi.complete);
  await e.dispose();
  await _flush();
  if (!eventsDone) run.problems.add('events stream still open after dispose()');
  if (!doneStates.isCompleted) run.problems.add('states stream still open after dispose()');
  if (!doneUi.isCompleted) run.problems.add('uiStates stream still open after dispose()');

  // After dispose: any verb must be harmless and silent.
  // 销毁之后：任何动词都必须无害且静默。
  final eventsBefore = events.length;
  for (var i = 0; i < _stepsAfterDispose; i++) {
    final n = rnd.nextInt(actionCount);
    // The kernel's own emitters are closed with it; only host verbs are fair game.
    // 内核自己的推送口随内核一起关闭了；只有宿主动词才属于合理调用。
    if (n >= 21 && n <= 27) continue;
    await act(n);
  }
  await _flush();
  if (events.length != eventsBefore) {
    run.problems.add('${events.length - eventsBefore} event(s) emitted after dispose()');
  }
}

void main() {
  group('engine fuzz (fixed seeds, FakeKernel)', () {
    for (final seed in _seeds) {
      test('seed $seed: invariants hold, no uncaught error, dispose is final', () async {
        final run = await _runSeed(seed);
        if (run.problems.isNotEmpty) {
          // Printed in full so the failing seed and action trail can be replayed.
          // 完整打印，便于复现失败的种子与动作轨迹。
          // ignore: avoid_print
          print(run.report(seed));
        }
        expect(run.problems, isEmpty, reason: run.report(seed));
      });
    }

    test('hammering: 100 rapid seeks, source swaps and fullscreen toggles settle consistently', () async {
      final problems = <String>[];
      final done = Completer<void>();
      final k = FakeKernel();
      final e = MovaEngine(kernel: k);
      runZonedGuarded(
        () async {
          try {
            await e.open(_sources[0]);
            k.emitDuration(const Duration(minutes: 30));
            await _flush();
            var fullscreen = false;
            for (var i = 0; i < 100; i++) {
              // Fire without awaiting: a host tapping faster than the engine settles.
              // 不等待就连发：宿主点得比引擎落定更快。
              unawaited(e.seek(Duration(seconds: i * 7 % 1800)));
              unawaited(e.open(_sources[i % 2], autoPlay: i.isEven));
              fullscreen = !fullscreen;
              unawaited(e.setFullscreen(fullscreen));
              if (i % 10 == 0) await _flush();
            }
            await _flush();
            await _flush();
            // Last writer wins on the verbs that have no async hook in between.
            // 中间没有异步钩子的动词，后写者胜。
            if (e.state.fullscreen != fullscreen) {
              problems.add('fullscreen=${e.state.fullscreen}, last toggle was $fullscreen');
            }
            if (k.lastUri != _sources[1].uri) {
              problems.add('kernel ended on ${k.lastUri}, last open was ${_sources[1].uri}');
            }
          } catch (err, st) {
            problems.add('threw: $err\n$st');
          } finally {
            done.complete();
          }
        },
        (err, st) => problems.add('uncaught async error: $err\n$st'),
      );
      await done.future;
      await e.dispose();
      expect(problems, isEmpty);
    });
  });
}
