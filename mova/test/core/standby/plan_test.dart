import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/standby_kernel.dart';
import 'package:mova/src/core/standby/plan.dart';

const _present = MovaStandbyMedia(audio: MovaAudioPresence.present, format: 'flv');
const _absent = MovaStandbyMedia(audio: MovaAudioPresence.absent, format: 'flv');

/// Runs [decideStandbyEntry] with the "everything is fine" defaults, overriding
/// only what a case cares about.
///
/// 以"一切正常"的默认值调用 [decideStandbyEntry]，只覆盖用例关心的项。
MovaStandbyEntry _entry({
  MovaStandbyPhase phase = MovaStandbyPhase.off,
  bool intent = true,
  bool exempt = false,
  MovaStreamType type = MovaStreamType.live,
  bool recovering = false,
  bool kernelCapable = true,
  MovaStandbyMedia? media = _present,
  MovaStandbyConfig config = const MovaStandbyConfig(),
}) =>
    decideStandbyEntry(
      phase: phase,
      intent: intent,
      exempt: exempt,
      type: type,
      recovering: recovering,
      kernelCapable: kernelCapable,
      media: media,
      config: config,
    );

MovaStandbyWake _wake({
  MovaStandbyPhase phase = MovaStandbyPhase.fallback,
  bool intent = true,
  MovaStreamType type = MovaStreamType.live,
  MovaStandbyReason? cause,
  Duration pausedFor = Duration.zero,
}) =>
    decideStandbyWake(
      phase: phase,
      intent: intent,
      type: type,
      cause: cause,
      pausedFor: pausedFor,
      config: const MovaStandbyConfig(),
    );

void main() {
  group('decideStandbyEntry', () {
    test('holding / fallback skip as already', () {
      for (final p in [MovaStandbyPhase.holding, MovaStandbyPhase.fallback]) {
        final e = _entry(phase: p);
        expect(e.kind, MovaStandbyEntryKind.skip);
        expect(e.reason, MovaStandbyReason.already);
      }
    });

    test('exempt skips', () {
      final e = _entry(exempt: true);
      expect(e.kind, MovaStandbyEntryKind.skip);
      expect(e.reason, MovaStandbyReason.exempt);
    });

    test('no play intent skips as notPlaying', () {
      final e = _entry(intent: false);
      expect(e.kind, MovaStandbyEntryKind.skip);
      expect(e.reason, MovaStandbyReason.notPlaying);
    });

    test('VOD falls back as vod', () {
      final e = _entry(type: MovaStreamType.vod);
      expect(e.kind, MovaStandbyEntryKind.fallback);
      expect(e.reason, MovaStandbyReason.vod);
    });

    test('a pending recovery falls back as failed, before capability/media checks', () {
      final e = _entry(recovering: true, kernelCapable: false, media: null);
      expect(e.kind, MovaStandbyEntryKind.fallback);
      expect(e.reason, MovaStandbyReason.failed);
    });

    test('a kernel without the capability falls back as unsupported', () {
      final e = _entry(kernelCapable: false);
      expect(e.kind, MovaStandbyEntryKind.fallback);
      expect(e.reason, MovaStandbyReason.unsupported);
    });

    test('unreadable media falls back as mediaUnknown', () {
      final e = _entry(media: null);
      expect(e.kind, MovaStandbyEntryKind.fallback);
      expect(e.reason, MovaStandbyReason.mediaUnknown);
    });

    test('audio present on flv holds muted', () {
      final e = _entry();
      expect(e.kind, MovaStandbyEntryKind.hold);
      expect(e.mode, MovaStandbyMode.muted);
      expect(e.reason, MovaStandbyReason.requested);
    });

    test('no audio holds decodeOnly by default', () {
      final e = _entry(media: _absent);
      expect(e.kind, MovaStandbyEntryKind.hold);
      expect(e.mode, MovaStandbyMode.decodeOnly);
    });

    test('no audio with silentStreams pause falls back as silentStream', () {
      final e = _entry(
        media: _absent,
        config: const MovaStandbyConfig(silentStreams: MovaSilentStandby.pause),
      );
      expect(e.kind, MovaStandbyEntryKind.fallback);
      expect(e.reason, MovaStandbyReason.silentStream);
    });

    test('hls pauses by default, is held with allowHls, and an unknown format counts as mediaUnknown', () {
      const hls = MovaStandbyMedia(audio: MovaAudioPresence.present, format: 'hls');
      expect(_entry(media: hls).reason, MovaStandbyReason.hls);
      expect(_entry(media: hls, config: const MovaStandbyConfig(allowHls: true)).mode, MovaStandbyMode.muted);
      const noFormat = MovaStandbyMedia(audio: MovaAudioPresence.present);
      expect(_entry(media: noFormat).reason, MovaStandbyReason.mediaUnknown);
    });

    test('resuming is decided like off', () {
      final e = _entry(phase: MovaStandbyPhase.resuming);
      expect(e.kind, MovaStandbyEntryKind.hold);
      expect(e.mode, MovaStandbyMode.muted);
    });
  });

  group('decideStandbyWake', () {
    test('off and resuming need nothing', () {
      expect(_wake(phase: MovaStandbyPhase.off), MovaStandbyWake.none);
      expect(_wake(phase: MovaStandbyPhase.resuming), MovaStandbyWake.none);
    });

    test('holding restores', () {
      expect(_wake(phase: MovaStandbyPhase.holding), MovaStandbyWake.restore);
    });

    test('a fallback nobody wants playing settles, whatever the cause or type', () {
      for (final t in MovaStreamType.values) {
        for (final c in [MovaStandbyReason.failed, MovaStandbyReason.maxDuration, MovaStandbyReason.vod]) {
          expect(_wake(intent: false, type: t, cause: c), MovaStandbyWake.settle);
        }
      }
    });

    test('a VOD fallback just plays', () {
      expect(_wake(type: MovaStreamType.vod, cause: MovaStandbyReason.vod), MovaStandbyWake.resumePlay);
    });

    test('a live fallback after failure or end reopens', () {
      expect(_wake(cause: MovaStandbyReason.failed), MovaStandbyWake.reopen);
      expect(_wake(cause: MovaStandbyReason.ended), MovaStandbyWake.reopen);
    });

    test('a live fallback goes back to the edge after maxDuration or a long pause', () {
      expect(_wake(cause: MovaStandbyReason.maxDuration), MovaStandbyWake.reloadEdge);
      expect(
        _wake(cause: MovaStandbyReason.reloaded, pausedFor: const Duration(seconds: 3)),
        MovaStandbyWake.reloadEdge,
      );
    });

    test('a short live fallback just plays', () {
      expect(
        _wake(cause: MovaStandbyReason.mediaUnknown, pausedFor: const Duration(seconds: 1)),
        MovaStandbyWake.resumePlay,
      );
      expect(
        _wake(cause: MovaStandbyReason.reloaded, pausedFor: const Duration(milliseconds: 2999)),
        MovaStandbyWake.resumePlay,
      );
    });
  });
}
