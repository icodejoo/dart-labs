import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import '../main_coverage_api.dart' as c;

/// Public API fault injection. These observations prove core contracts only;
/// they never stand in for native decoding, windows, or FFI observations.
Future<void> run() async {
  for (final entry in <String, Future<void> Function()>{
    'openThrow': openThrow,
    'intent': intent,
    'mini': mini,
    'ui': ui,
    'source': source,
    'firstFrame': firstFrame,
    'previewBlock': previewBlock,
    'prefetch': prefetch,
    'heartbeatOff': heartbeatOff,
    'previewRaces': previewRaces,
  }.entries) {
    try {
      await entry.value();
    } catch (error, stack) {
      c.mark('S00C_SCRIPT_ERROR', {'case': entry.key, 'error': '$error', 'stack': '$stack'});
    }
  }
}

class PendingThumbSource implements IMovaThumbSource {
  final entered = Completer<void>();
  final result = Completer<MovaThumb?>();
  int calls = 0;
  @override
  String get name => 's00c-controlled-late-result';
  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) {
    calls++;
    if (!entered.isCompleted) entered.complete();
    return result.future;
  }
  @override
  Future<void> reset() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> previewRaces() async {
  for (final switchSource in [false, true]) {
    final source = PendingThumbSource();
    final service = MovaPreviewService(opts: const MovaPreviewOpts(enabled: true,
      network: MovaPreviewNet.always, debounce: Duration.zero), cache: MovaMemoryThumbCache(),
      probe: MovaAlwaysAllowNetProbe(), sources: [source]);
    final published = <MovaThumb?>[];
    final sub = service.thumbs.listen(published.add);
    try {
      service.attach(const MovaSource('s00c://old-preview'));
      service.requestAt(const Duration(seconds: 2));
      await source.entered.future.timeout(const Duration(seconds: 5));
      if (switchSource) {
        service.attach(const MovaSource('s00c://new-preview'));
      } else {
        service.cancel();
      }
      source.result.complete(MovaThumb(at: const Duration(seconds: 2), bytes: Uint8List.fromList([1, 2, 3])));
      // All remaining dependencies use the synchronous memory cache. A new
      // event-loop turn drains their microtasks; elapsed time is not measured.
      await Future<void>.delayed(Duration.zero);
      final nonNull = published.whereType<MovaThumb>().length;
      measured(switchSource ? 'A30.staleResult' : 'A30.cancelResult',
        source.calls == 1 && service.current == null && nonNull == 0,
        {'sourceCalls': source.calls, 'currentNull': service.current == null,
         'latePublished': nonNull, 'switchSource': switchSource});
    } finally {
      await service.dispose();
      await sub.cancel();
    }
  }
}

Future<void> prefetch() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <String?>[];
  final done = Completer<void>();
  final subscription = server.listen((request) async {
    requests.add(request.headers.value(HttpHeaders.rangeHeader));
    request.response.add(List<int>.filled(65, 1));
    await request.response.close();
    if (!done.isCompleted) done.complete();
  });
  try {
    await const MovaNetworkWarmFeedPrefetcher(rangeBytes: 64).prime(
      MovaSource('http://127.0.0.1:${server.port}/next.mp4'));
    await done.future.timeout(const Duration(seconds: 5));
    measured('A29.rangeWarm', requests.length == 1 && requests.single == 'bytes=0-64',
      {'requestCount': requests.length, 'range': requests.single}, origin: 'loopback-http');
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

Future<void> heartbeatOff() async {
  final timers = <int>[];
  final reports = <MovaReportEvent>[];
  await runZoned(() async {
    final api = Mova(kernel: MovaTestKernel(), reporter: MovaCallbackReporter(reports.add));
    try {
      await api.open(const MovaSource('s00c://heartbeat-off'));
      await api.dispose();
    } finally {
      await api.dispose();
    }
  }, zoneSpecification: ZoneSpecification(createPeriodicTimer: (self, parent, zone, duration, callback) {
    timers.add(duration.inMicroseconds);
    return parent.createPeriodicTimer(zone, duration, callback);
  }));
  measured('C13.defaultHeartbeat', timers.isEmpty,
    {'periodicTimers': timers.length, 'periodsUs': timers,
     'heartbeatUs': const MovaReportOpts().heartbeat?.inMicroseconds});
}

void measured(String id, bool pass, Map<String, Object?> numbers, {String origin = 'public-testing-kernel'}) =>
    c.mark('CHECK', {'id': id, 'pass': pass, 'origin': origin,
      'numbers': numbers});

Future<void> openThrow() async {
  final failure = StateError('s00c kernel open fault');
  final kernel = MovaTestKernel()..openError = failure;
  final api = Mova(kernel: kernel);
  c.observe(api);
  Object? caught;
  try {
    await api.open(const MovaSource('s00c://open-fault'));
  } catch (error) {
    caught = error;
  } finally {
    measured('A5.openThrows', identical(caught, failure) && kernel.calls.contains('open'),
      {'sameError': identical(caught, failure), 'openCalls': kernel.calls.where((v) => v == 'open').length,
       'recoveryEnabled': api.options.recovery.enabled});
    await api.dispose();
  }
}

Future<void> intent() async {
  final kernel = MovaTestKernel();
  final api = Mova(kernel: kernel);
  c.observe(api);
  try {
    await api.open(const MovaSource('s00c://intent'), autoPlay: false);
    await api.play();
    measured('A6.intentIndependent', api.state.playbackIntent && !api.state.playing,
      {'intent': api.state.playbackIntent, 'playing': api.state.playing, 'calls': List.of(kernel.calls)});
    kernel.calls.clear();
    await api.playOrPause();
    measured('A6.branchPlay', kernel.calls.length == 1 && kernel.calls.single == 'play',
      {'calls': List.of(kernel.calls), 'playing': api.state.playing});
    kernel.emitPlaying(true);
    await c.until(() => api.state.playing);
    kernel.calls.clear();
    await api.playOrPause();
    measured('A6.branchPause', kernel.calls.length == 1 && kernel.calls.single == 'pause',
      {'calls': List.of(kernel.calls), 'playing': api.state.playing});
  } finally {
    await api.dispose();
  }
}

Future<void> mini() async {
  for (final cutover in [false, true]) {
    final kernels = <MovaTestKernel>[];
    Mova factory() {
      final kernel = MovaTestKernel();
      kernels.add(kernel);
      return Mova(kernel: kernel);
    }
    final IMovaApi api = cutover ? MovaCutover(movaFactory: factory) : factory();
    final seen = <MovaEvent>[];
    final sub = api.events.listen(seen.add);
    c.observe(api);
    try {
      await api.open(const MovaSource('s00c://mini'));
      final before = c.snapshot(api);
      final handle = api.renderHandle;
      await api.setMini(true);
      await api.setMini(true);
      await c.settle();
      final entered = api.state.mini;
      final changes = seen.whereType<MovaMiniChange>().length;
      measured('A15.miniStable', entered && changes == 1 &&
          api.state.renderEpoch == before['epoch'] && identical(api.renderHandle, handle) &&
          api.state.orient.name == before['orient'] && api.state.pip == before['pip'] &&
          api.state.volume == before['volume'],
        {'cutover': cutover, 'entered': entered, 'changes': changes,
         'before': before, 'after': c.snapshot(api), 'sameHandle': identical(api.renderHandle, handle)});
      await api.setMini(false);
      await c.settle();
      measured('A15.exit', !api.state.mini && seen.whereType<MovaMiniChange>().length == 2,
        {'cutover': cutover, 'mini': api.state.mini, 'changes': seen.whereType<MovaMiniChange>().length});
    } finally {
      await sub.cancel();
      await api.dispose();
    }
  }
}

Future<void> ui() async {
  final api = Mova(kernel: MovaTestKernel(), options: const MovaOpts(
    controls: MovaCtrlsOpts(autoHideDelay: Duration(milliseconds: 100))));
  final states = <MovaUiState>[];
  final sub = api.uiStates.listen(states.add);
  try {
    api.showControls(sticky: true);
    await c.settle(250); // Scheduling only: the assertions use state/stream observations.
    measured('A21.sticky', api.uiState.controlsVisible,
      {'visible': api.uiState.controlsVisible, 'samples': states.length});
    api.showControls();
    await c.until(() => !api.uiState.controlsVisible);
    measured('A21.autoHide', !api.uiState.controlsVisible && states.any((s) => s.controlsVisible),
      {'visible': api.uiState.controlsVisible, 'sawVisible': states.any((s) => s.controlsVisible)});
    api.showHud(MovaHud.seek, text: 's00c');
    api.setDragging(true, previewAt: const Duration(seconds: 7));
    await c.settle();
    measured('A21.dragging', api.uiState.dragging && api.uiState.previewAt?.inSeconds == 7 &&
      api.uiState.hud == MovaHud.seek && api.uiState.hudText == 's00c',
      {'dragging': api.uiState.dragging, 'previewAt': api.uiState.previewAt?.inMilliseconds,
       'hud': api.uiState.hud.name, 'text': api.uiState.hudText});
    api.setDragging(false);
    await c.until(() => api.uiState.hud == MovaHud.none);
    measured('A21.hudCleared', api.uiState.hudText == null && !api.uiState.dragging,
      {'hud': api.uiState.hud.name, 'text': api.uiState.hudText, 'dragging': api.uiState.dragging});
  } finally {
    await sub.cancel();
    await api.dispose();
  }
}

Future<void> source() async {
  const a = MovaSource('s00c://source', mpvOptions: {'http-header-fields': 'X-S00c: a'}, alternatives: ['s00c://backup']);
  const same = MovaSource('s00c://source', mpvOptions: {'http-header-fields': 'X-S00c: a'}, alternatives: ['s00c://backup']);
  const headers = MovaSource('s00c://source', mpvOptions: {'http-header-fields': 'X-S00c: b'}, alternatives: ['s00c://backup']);
  const alternatives = MovaSource('s00c://source', mpvOptions: {'http-header-fields': 'X-S00c: a'}, alternatives: ['s00c://other']);
  measured('C17.sameAs', a.sameAs(same) && !a.sameAs(headers) && !a.sameAs(alternatives),
    {'same': a.sameAs(same), 'changedHeaders': a.sameAs(headers), 'changedAlternatives': a.sameAs(alternatives)});
}

Future<void> firstFrame() async {
  final kernel = MovaTestKernel(nativeRestartAvailable: true);
  final api = Mova(kernel: kernel);
  final events = <MovaEvent>[];
  final sub = api.events.listen(events.add);
  c.observe(api);
  try {
    await api.open(const MovaSource('s00c://first'));
    kernel.emitSize(640, 360);
    kernel.emitRestart();
    await c.until(() => api.state.rendered);
    await api.open(const MovaSource('s00c://second'), autoPlay: false);
    measured('N12.openReset', !api.state.rendered && api.state.width == 0 && api.state.height == 0,
      {'rendered': api.state.rendered, 'width': api.state.width, 'height': api.state.height,
       'firstFrames': events.whereType<MovaFirstFrame>().length});
    // A fresh RESTART lands the new attempt, including a paused open.
    // This does not claim to identify a stale native client's RESTART.
    kernel.emitRestart();
    await c.settle();
    measured('N12.freshRestart', api.state.rendered && events.whereType<MovaFirstFrame>().length == 2,
      {'rendered': api.state.rendered, 'firstFrames': events.whereType<MovaFirstFrame>().length});
  } finally {
    await sub.cancel();
    await api.dispose();
  }
}

Future<void> previewBlock() async {
  final api = Mova(kernel: MovaTestKernel(), options: const MovaOpts(
    preview: MovaPreviewOpts(enabled: true, network: MovaPreviewNet.never)));
  final events = <MovaPreviewBlock>[];
  final sub = api.events.where((e) => e is MovaPreviewBlock).cast<MovaPreviewBlock>().listen(events.add);
  c.observe(api);
  try {
    await api.open(const MovaSource('https://s00c.invalid/video.mp4'));
    api.preview.requestAt(const Duration(seconds: 2));
    await c.until(() => events.isNotEmpty);
    measured('E.MovaPreviewBlock.network', events.last.reason == MovaPreviewBlockReason.network,
      {'reason': events.last.reason.name, 'count': events.length});
  } finally {
    await sub.cancel();
    await api.dispose();
  }
}
