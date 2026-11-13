// ignore_for_file: implementation_imports
import 'dart:async';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'cp2_harness.dart';

// Cutover retires old players with unawaited(dispose()). Keep the actual
// native release Future so the fixture can drain every player before looping.
class Cp2OwnedKernel extends MovaMpvKernel {
  Cp2OwnedKernel({required super.player, required super.audioOnly})
    : super(lazyVideo: true, observeNativeEvents: true);
  Future<void>? _release;
  @override
  Future<void> dispose() => _release ??= super.dispose();
}

Mova cp2Mova(Cp2Harness h, {MovaOpts options = const MovaOpts(), bool audioOnly = false, IMovaReporter? reporter}) {
  final player = Player();
  final kernel = Cp2OwnedKernel(player: player, audioOnly: audioOnly);
  h.kernelReleases.add(() async {
    await kernel.dispose();
    h.mark('KERNEL_RELEASE', {'player': identityHashCode(player)});
  });
  final mova = createMova(options: options, audioOnly: audioOnly, preciseFirstFrame: true, ownsKernel: true,
    reporter: reporter, kernel: kernel);
  h.nativePlayers[mova] = player;
  h.cleanup.add(mova.progress.listen((p)=>h.mark('MOVA_PROGRESS',{'mova':identityHashCode(mova),'positionMs':p.position.inMilliseconds,'bufferMs':p.buffer.inMilliseconds})).cancel);
  return mova;
}
MovaSource cp2Source(String name, {bool hls = false, bool live = false}) => MovaSource(
  'http://127.0.0.1:18190/${live ? 'live/index.m3u8' : hls ? '$name/index.m3u8' : '$name.mp4'}?t=${DateTime.now().microsecondsSinceEpoch}',
  type: live ? MovaStreamType.live : MovaStreamType.vod);

void cp2AdEvent(Cp2Harness h, MovaAdEvent e) => h.mark('AD', {
  'event': 'MovaAdEvent', 'type': e.type.name, 'adKind': e.adBreak.kind.name,
  'uri': e.adBreak.source.uri, 'error': e.error?.toString(), 'state': h.snapshot()});

MovaCutover cp2Cutover(Cp2Harness h, MovaOpts opts) => MovaCutover(
  movaFactory: () => cp2Mova(h, options: opts));
const cp2CutoverOpts = MovaCutoverOpts(enabled: true, minWarmDuration: Duration.zero,
  trigger: MovaEagerWarm());

/// Samples belong to the actual active player, with a stable epoch and path.
Future<Map<String, Object?>> cp2At(Cp2Harness h, String uri) async {
  await h.until(() async => (await h.native())['path'] == uri && h.api!.state.rendered);
  return h.native();
}

/// Samples throughout the background window come from the HTTP host, not suspended Dart timers.
Future<List<Map<String, dynamic>>> cp2Background(Cp2Harness h, String id, int seconds) async {
  await h.host(id, 'background:$seconds');
  return (h.hostData[id]!['samples'] as List).cast<Map<String, dynamic>>();
}
