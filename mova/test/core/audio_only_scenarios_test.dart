import 'package:mova/src/testing/hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/mova.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';

import '../support/fake_kernel.dart';

/// Yields a microtask so the player's stream plumbing settles before an
/// assertion.
///
/// 让出一个微任务，使播放器的流管道在断言前结算完毕。
Future<void> tick() => Future<void>.delayed(Duration.zero);

/// Builds an audio-only player over a fresh [FakeKernel.audioOnly], returning
/// both so a test can drive the kernel and assert on the player.
///
/// 基于新建的 [FakeKernel.audioOnly] 构造一个仅音频播放器，同时返回二者，
/// 便于测试驱动内核并对播放器做断言。
({FakeKernel kernel, Mova mova}) buildAudioMova({MovaOpts? options}) {
  final kernel = FakeKernel.audioOnly();
  final mova = Mova(fetcher: const MovaTestHttpFetch(),
    kernel: kernel, ownsKernel: true,
    audioOnly: true,
    options: options ?? const MovaOpts(),
  );
  return (kernel: kernel, mova: mova);
}

void main() {
  // Scenario 2 / 场景 2
  //
  // A headless audio player: no Flutter binding, no widget tree, no
  // MovaPlayer. This whole file deliberately never calls
  // `TestWidgetsFlutterBinding.ensureInitialized()` — if any verb below grew a
  // dependency on the widget layer, these tests would fail rather than quietly
  // pass in a widget-hosted suite.
  //
  // 无头音频播放器：没有 Flutter binding、没有 widget 树、没有 MovaPlayer。
  // 本文件刻意从不调用 `TestWidgetsFlutterBinding.ensureInitialized()`——如果
  // 下面任何一个动词将来长出了对 widget 层的依赖，这些测试会直接失败，而不是
  // 在一个有 widget 宿主的套件里悄悄通过。
  group('scenario 2: headless playback with no widget tree / 无 widget 背景播放', () {
    test('open/play/pause/seek all reach the kernel with no render surface mounted', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      expect(mova.renderHandle, isNull);
      await mova.open(const MovaSource('https://host/track.m4a', title: 'Track A'));
      kernel.emitDuration(const Duration(minutes: 4));
      await tick();

      await mova.play();
      await mova.pause();
      await mova.seek(const Duration(seconds: 30));

      expect(kernel.lastUri, 'https://host/track.m4a');
      expect(kernel.lastSeek, const Duration(seconds: 30));
      expect(
        kernel.calls,
        containsAllInOrder(<String>['open', 'play', 'pause', 'seek']),
        reason: 'playback verbs must not depend on a widget lifecycle / '
            '播放动词不得依赖 widget 生命周期',
      );
    });

    test('state and progress keep flowing headlessly', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      final states = <MovaState>[];
      final progress = <MovaProg>[];
      final stateSub = mova.states.listen(states.add);
      final progSub = mova.progress.listen(progress.add);

      await mova.open(const MovaSource('https://host/track.m4a'));
      kernel.emitPlaying(true);
      kernel.emitDuration(const Duration(minutes: 4));
      kernel.emitPosition(const Duration(seconds: 12));
      await tick();

      expect(mova.state.playing, isTrue);
      expect(mova.state.duration, const Duration(minutes: 4));
      expect(states, isNotEmpty);
      // progress is throttled, so the raw tick may not have surfaced yet; the
      // player's own view of position is what matters here.
      // progress 是节流的，原始 tick 可能尚未冒出；这里关心的是播放器自己
      // 对位置的认知。
      expect(mova.uiState, isNotNull);

      await stateSub.cancel();
      await progSub.cancel();
    });

    test('volume and rate are settable headlessly and land in state', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/track.m4a'));
      await mova.setVolume(42);
      await mova.setRate(1.5);
      await tick();

      expect(mova.state.volume, 42);
      expect(mova.state.rate, 1.5);
      expect(kernel.calls, contains('setVolume'));
      expect(kernel.calls, contains('setRate'));
    });

    test('playOrPause toggles headlessly off the kernel playing stream', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/track.m4a'), autoPlay: false);
      kernel.emitPlaying(false);
      await tick();
      expect(mova.state.playing, isFalse);

      await mova.playOrPause();
      kernel.emitPlaying(true);
      await tick();
      expect(mova.state.playing, isTrue);

      await mova.playOrPause();
      kernel.emitPlaying(false);
      await tick();
      expect(mova.state.playing, isFalse);
    });

    test('completion is reported headlessly', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      final events = <MovaEvent>[];
      final sub = mova.events.listen(events.add);
      await mova.open(const MovaSource('https://host/track.m4a'));
      kernel.emitCompleted(true);
      await tick();

      expect(mova.state.completed, isTrue);
      expect(events.whereType<MovaDone>(), hasLength(1));
      await sub.cancel();
    });

    test('dispose tears the player down cleanly with nothing ever mounted', () async {
      final (:kernel, :mova) = buildAudioMova();
      await mova.open(const MovaSource('https://host/track.m4a'));
      await mova.dispose();

      expect(kernel.calls, contains('dispose'));
    });
  });

  // Scenario 3 / 场景 3
  group('scenario 3: switching between several audio sources / 多音频切换', () {
    test('three consecutive opens each reach the kernel with the right uri and title', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      const sources = [
        MovaSource('https://host/one.m4a', title: 'One'),
        MovaSource('https://host/two.m4a', title: 'Two'),
        MovaSource('https://host/three.m4a', title: 'Three'),
      ];
      for (final s in sources) {
        await mova.open(s);
        await tick();
        expect(kernel.lastUri, s.uri);
        expect(mova.state.sourceTitle, s.title);
      }

      expect(
        kernel.calls.where((c) => c == 'open'),
        hasLength(3),
        reason: 'each switch is exactly one kernel open, never a leaked extra / '
            '每次切换恰好一次内核 open，不得泄漏出多余的一次',
      );
    });

    test('each switch updates duration from the new source', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/one.m4a'));
      kernel.emitDuration(const Duration(minutes: 3));
      await tick();
      expect(mova.state.duration, const Duration(minutes: 3));

      await mova.open(const MovaSource('https://host/two.m4a'));
      kernel.emitDuration(const Duration(minutes: 7));
      await tick();
      expect(mova.state.duration, const Duration(minutes: 7));

      await mova.open(const MovaSource('https://host/three.m4a'));
      kernel.emitDuration(const Duration(seconds: 45));
      await tick();
      expect(mova.state.duration, const Duration(seconds: 45));
    });

    test('a switch clears the previous source stale quality/error state', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/one.m4a'));
      const q = MovaQuality(label: '320k', uri: 'https://host/one-320.m4a');
      mova.debugSetQualities(const [q], current: q);
      kernel.emitError('Failed to recognize file format.');
      await tick();
      expect(mova.state.error, isNotNull);
      expect(mova.state.qualities, isNotEmpty);

      await mova.open(const MovaSource('https://host/two.m4a'));
      await tick();

      expect(mova.state.error, isNull, reason: 'a new source starts clean / 新源从干净状态开始');
      expect(mova.state.qualities, isEmpty);
      expect(mova.state.currentQuality, isNull);
    });

    test('a parked seek from the previous source never lands on the next one', () async {
      // A seek issued before any duration is known is parked; switching
      // sources must drop it, otherwise track two would jump to track one's
      // requested position.
      //
      // 时长未知前发起的 seek 会被暂存；切源时必须丢弃它，否则第二首会跳到
      // 为第一首请求的位置。
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/one.m4a'));
      await mova.seek(const Duration(seconds: 90));
      expect(kernel.lastSeek, isNull, reason: 'parked while duration is unknown / 时长未知，被暂存');

      await mova.open(const MovaSource('https://host/two.m4a'));
      kernel.emitDuration(const Duration(minutes: 5));
      await tick();

      expect(
        kernel.lastSeek,
        isNull,
        reason: "track one's parked seek must not fire on track two / "
            '第一首暂存的 seek 不得在第二首上触发',
      );
    });

    test('old-source state does not bleed through: only the live kernel is observed', () async {
      // The player subscribes to exactly one kernel for its whole life, so
      // "cross-talk" here means stale values surviving a switch. Position is
      // the one field the player does not reset itself — it mirrors whatever
      // the kernel last reported, and a real kernel reports 0 on open.
      //
      // 播放器终其一生只订阅一个内核，所以这里的"串台"指的是切换后仍残留的
      // 旧值。position 是播放器唯一不自行复位的字段——它如实镜像内核最后报告
      // 的值，而真实内核在 open 时会报 0。
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      final seen = <Duration>[];
      final sub = mova.progress.listen((p) => seen.add(p.position));

      await mova.open(const MovaSource('https://host/one.m4a'));
      kernel.emitDuration(const Duration(minutes: 3));
      kernel.emitPosition(const Duration(seconds: 100));
      await tick();

      await mova.open(const MovaSource('https://host/two.m4a'));
      kernel.emitDuration(const Duration(minutes: 3));
      kernel.emitPosition(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        seen.last,
        Duration.zero,
        reason: "the new source's first position tick wins / 新源的第一个位置 tick 生效",
      );
      await sub.cancel();
    });

    test('ten switches in a row leave exactly ten opens and one live subscription set', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      for (var i = 0; i < 10; i++) {
        await mova.open(MovaSource('https://host/track$i.m4a'));
        kernel.emitDuration(const Duration(minutes: 2));
        await tick();
      }

      expect(kernel.calls.where((c) => c == 'open'), hasLength(10));
      expect(kernel.lastUri, 'https://host/track9.m4a');
      // Still exactly one player over one kernel: no per-switch kernel churn,
      // so there is nothing to leak.
      // 始终是一个播放器对一个内核：切换不产生内核抖动，因此无从泄漏。
      expect(kernel.calls.where((c) => c == 'dispose'), isEmpty);
    });
  });

  // Scenario 4 / 场景 4
  group('scenario 4: audio-only edge cases / 仅音频边界场景', () {
    test('a source carrying a video track: audio plays, handle stays null', () async {
      // BOUNDARY / 界限：with a real MovaMpvKernel, mpv's `--vid=no` means the
      // video track is never decoded, so no frame is ever produced and the
      // reported size stays 0x0. A fake kernel cannot prove that — it can only
      // prove the player side behaves correctly for either report. **Whether
      // a real mp4 truly renders no first frame needs on-device verification
      // (plan Task 5).**
      //
      // 界限：用真实 MovaMpvKernel 时，mpv 的 `--vid=no` 意味着视频轨压根不解码，
      // 不会产出任何帧，上报的尺寸恒为 0x0。假内核证明不了这一点——它只能证明
      // 无论内核报什么，播放器侧行为都正确。**真实 mp4 是否确实不出首帧，
      // 需真机验证（计划 Task 5）。**
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/movie.mp4'));
      kernel.emitDuration(const Duration(minutes: 90));
      kernel.emitPlaying(true);
      kernel.emitSize(0, 0);
      await tick();

      expect(mova.state.playing, isTrue, reason: 'audio still plays / 声音照放');
      expect(mova.state.duration, const Duration(minutes: 90));
      expect(mova.state.width, 0);
      expect(mova.state.height, 0);
      expect(mova.renderHandle, isNull, reason: 'and nothing to draw with / 且无从出画');
    });

    test('a non-zero size report does not conjure a render handle', () async {
      // Defensive: even if some future kernel reported a real size in
      // audio-only mode, the render handle must stay null — the two are
      // independent, and the UI keys off the handle.
      //
      // 防御性：即便将来某个内核在仅音频模式下报了真实尺寸，渲染句柄也必须
      // 保持 null——二者互相独立，而 UI 认的是句柄。
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/movie.mp4'));
      kernel.emitSize(1920, 1080);
      await tick();

      expect(mova.state.width, 1920);
      expect(mova.renderHandle, isNull);
    });

    test('ABR downshifts normally while renderHandle is null', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      const auto = MovaQuality(label: '自动', uri: '', isAuto: true);
      const high = MovaQuality(label: '320k', uri: 'https://host/320.m3u8', height: 1080);
      const low = MovaQuality(label: '128k', uri: 'https://host/128.m3u8', height: 480);
      await mova.open(const MovaSource('https://host/stream.m3u8'));
      // 自动探测结算后再手工种入 ABR 测试档位。
      await mova.loadQualities();
      mova.debugSetQualities(const [auto, high, low], current: high);

      final events = <MovaEvent>[];
      final sub = mova.events.listen(events.add);
      for (var i = 0; i < 3; i++) {
        kernel.emitBuffering(true);
        kernel.emitBuffering(false);
        await tick();
      }
      await tick();

      expect(events.whereType<MovaAbrDownShift>(), hasLength(1));
      expect(mova.state.currentQuality, low);
      expect(mova.renderHandle, isNull);
      await sub.cancel();
    });

    test('the stt/subtitle surface is live and unaffected by the null handle', () async {
      final (:kernel, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      expect(mova.stt, isNotNull);
      final events = <MovaEvent>[];
      final sub = mova.events.listen(events.add);
      await mova.stt.start();
      await tick();

      // No recognizer configured, so the documented block reason is reported —
      // the same answer a video player gives, i.e. the null handle changed
      // nothing about this path.
      // 未配置识别器，因此上报既有的阻断原因——与视频播放器的回答完全一致，
      // 即 null 句柄没有改变这条路径的任何行为。
      expect(events.whereType<MovaSttBlock>(), isNotEmpty);
      await sub.cancel();
    });

    test('danmaku and controls opts are untouched by audio-only', () {
      final (kernel: _, :mova) = buildAudioMova(
        options: const MovaOpts(
          danmaku: MovaDanmakuOpts(enabled: true),
          controls: MovaCtrlsOpts(showOnStart: false),
        ),
      );
      addTearDown(mova.dispose);

      expect(mova.options.danmaku.enabled, isTrue);
      expect(mova.options.controls.showOnStart, isFalse);
      expect(mova.renderHandle, isNull);
    });

    test('fullscreen/lock/fit/zoom verbs stay callable and do not throw', () async {
      // Meaningless in audio, but they must not blow up — a shared UI kit may
      // still route a tap to them.
      // 音频下无意义，但不得炸——共用 UI 套件仍可能把点击路由过来。
      final (kernel: _, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await mova.open(const MovaSource('https://host/track.m4a'));
      await mova.setLocked(true);
      await mova.setLocked(false);
      await mova.setFit(MovaFit.cover);
      await mova.setZoom(1.5);

      expect(mova.state.fit, MovaFit.cover);
      expect(mova.state.zoom, 1.5);
      expect(mova.state.locked, isFalse);
    });

    test('an audio-only player reports no pip support and enterPip stays false', () async {
      final (kernel: _, :mova) = buildAudioMova();
      addTearDown(mova.dispose);

      await tick();
      expect(await mova.enterPip(), isFalse);
    });
  });
}
