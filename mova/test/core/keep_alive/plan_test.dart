import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';
import 'package:mova/src/core/keep_alive/plan.dart';

const _present = MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'flv');
const _absent = MovaKeepAliveMedia(audio: MovaAudioPresence.absent, format: 'flv');

/// Runs [decideKeepAliveEntry] with the "everything is fine" defaults, overriding
/// only what a case cares about.
///
/// 以"一切正常"的默认值调用 [decideKeepAliveEntry]，只覆盖用例关心的项。
MovaKeepAliveEntry _entry({
  MovaKeepAlivePhase phase = MovaKeepAlivePhase.off,
  bool intent = true,
  bool exempt = false,
  MovaStreamType type = MovaStreamType.live,
  bool recovering = false,
  bool kernelCapable = true,
  MovaKeepAliveMedia? media = _present,
  MovaKeepAliveConfig config = const MovaKeepAliveConfig(),
}) =>
    decideKeepAliveEntry(
      phase: phase,
      intent: intent,
      exempt: exempt,
      type: type,
      recovering: recovering,
      kernelCapable: kernelCapable,
      media: media,
      config: config,
    );

MovaKeepAliveWake _wake({
  MovaKeepAlivePhase phase = MovaKeepAlivePhase.fallback,
  bool intent = true,
  MovaStreamType type = MovaStreamType.live,
  MovaKeepAliveReason? cause,
  Duration pausedFor = Duration.zero,
}) =>
    decideKeepAliveWake(
      phase: phase,
      intent: intent,
      type: type,
      cause: cause,
      pausedFor: pausedFor,
      config: const MovaKeepAliveConfig(),
    );

void main() {
  group('decideKeepAliveEntry', () {
    test('holding / fallback skip as already', () {
      for (final p in [MovaKeepAlivePhase.holding, MovaKeepAlivePhase.fallback]) {
        final e = _entry(phase: p);
        expect(e.kind, MovaKeepAliveEntryKind.skip);
        expect(e.reason, MovaKeepAliveReason.already);
      }
    });

    test('exempt skips', () {
      final e = _entry(exempt: true);
      expect(e.kind, MovaKeepAliveEntryKind.skip);
      expect(e.reason, MovaKeepAliveReason.exempt);
    });

    test('no play intent skips as notPlaying', () {
      final e = _entry(intent: false);
      expect(e.kind, MovaKeepAliveEntryKind.skip);
      expect(e.reason, MovaKeepAliveReason.notPlaying);
    });

    test('VOD falls back as vod', () {
      final e = _entry(type: MovaStreamType.vod);
      expect(e.kind, MovaKeepAliveEntryKind.fallback);
      expect(e.reason, MovaKeepAliveReason.vod);
    });

    test('a pending recovery falls back as failed, before capability/media checks', () {
      final e = _entry(recovering: true, kernelCapable: false, media: null);
      expect(e.kind, MovaKeepAliveEntryKind.fallback);
      expect(e.reason, MovaKeepAliveReason.failed);
    });

    test('a kernel without the capability falls back as unsupported', () {
      final e = _entry(kernelCapable: false);
      expect(e.kind, MovaKeepAliveEntryKind.fallback);
      expect(e.reason, MovaKeepAliveReason.unsupported);
    });

    test('unreadable media falls back as mediaUnknown', () {
      final e = _entry(media: null);
      expect(e.kind, MovaKeepAliveEntryKind.fallback);
      expect(e.reason, MovaKeepAliveReason.mediaUnknown);
    });

    test('audio present on flv holds muted', () {
      final e = _entry();
      expect(e.kind, MovaKeepAliveEntryKind.hold);
      expect(e.mode, MovaKeepAliveMode.muted);
      expect(e.reason, MovaKeepAliveReason.requested);
    });

    test('no audio holds decodeOnly by default', () {
      final e = _entry(media: _absent);
      expect(e.kind, MovaKeepAliveEntryKind.hold);
      expect(e.mode, MovaKeepAliveMode.decodeOnly);
    });

    test('no audio with silentStreams pause falls back as silentStream', () {
      final e = _entry(
        media: _absent,
        config: const MovaKeepAliveConfig(silentStreams: MovaSilentKeepAlive.pause),
      );
      expect(e.kind, MovaKeepAliveEntryKind.fallback);
      expect(e.reason, MovaKeepAliveReason.silentStream);
    });

    test('hls pauses by default, is held with allowHls, and an unknown format counts as mediaUnknown', () {
      const hls = MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'hls');
      expect(_entry(media: hls).reason, MovaKeepAliveReason.hls);
      expect(_entry(media: hls, config: const MovaKeepAliveConfig(allowHls: true)).mode, MovaKeepAliveMode.muted);
      const noFormat = MovaKeepAliveMedia(audio: MovaAudioPresence.present);
      expect(_entry(media: noFormat).reason, MovaKeepAliveReason.mediaUnknown);
    });

    test('resuming is decided like off', () {
      final e = _entry(phase: MovaKeepAlivePhase.resuming);
      expect(e.kind, MovaKeepAliveEntryKind.hold);
      expect(e.mode, MovaKeepAliveMode.muted);
    });
  });

  group('decideKeepAliveWake', () {
    test('off and resuming need nothing', () {
      expect(_wake(phase: MovaKeepAlivePhase.off), MovaKeepAliveWake.none);
      expect(_wake(phase: MovaKeepAlivePhase.resuming), MovaKeepAliveWake.none);
    });

    test('holding restores', () {
      expect(_wake(phase: MovaKeepAlivePhase.holding), MovaKeepAliveWake.restore);
    });

    test('a fallback nobody wants playing settles, whatever the cause or type', () {
      for (final t in MovaStreamType.values) {
        for (final c in [MovaKeepAliveReason.failed, MovaKeepAliveReason.maxDuration, MovaKeepAliveReason.vod]) {
          expect(_wake(intent: false, type: t, cause: c), MovaKeepAliveWake.settle);
        }
      }
    });

    test('a VOD fallback just plays', () {
      expect(_wake(type: MovaStreamType.vod, cause: MovaKeepAliveReason.vod), MovaKeepAliveWake.resumePlay);
    });

    test('a live fallback after failure or end reopens', () {
      expect(_wake(cause: MovaKeepAliveReason.failed), MovaKeepAliveWake.reopen);
      expect(_wake(cause: MovaKeepAliveReason.ended), MovaKeepAliveWake.reopen);
    });

    test('a live fallback goes back to the edge after maxDuration or a long pause', () {
      expect(_wake(cause: MovaKeepAliveReason.maxDuration), MovaKeepAliveWake.reloadEdge);
      expect(
        _wake(cause: MovaKeepAliveReason.reloaded, pausedFor: const Duration(seconds: 3)),
        MovaKeepAliveWake.reloadEdge,
      );
    });

    test('a short live fallback just plays', () {
      expect(
        _wake(cause: MovaKeepAliveReason.mediaUnknown, pausedFor: const Duration(seconds: 1)),
        MovaKeepAliveWake.resumePlay,
      );
      expect(
        _wake(cause: MovaKeepAliveReason.reloaded, pausedFor: const Duration(milliseconds: 2999)),
        MovaKeepAliveWake.resumePlay,
      );
    });
  });
}
