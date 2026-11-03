import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import '../main_coverage_api.dart' as c;

const ids = ['CONTRACT.defaults', 'CONTRACT.probe.true', 'CONTRACT.probe.false',
  'CONTRACT.error.nonterminal', 'CONTRACT.error.terminal', 'CONTRACT.rejectedOpen',
  'CONTRACT.replay.retry', 'CONTRACT.replay.edge'];

void emit(String id, Map<String, Object?> values, bool? pass) => c.mark('CHECK', {
  'id': id, 'origin': 'public-testing-contract', 'numbers': values, 'pass': pass});

Object? read(Object object, String key) {
  try {
    final dynamic value = object;
    return switch (key) {
      'probeVariants' => value.probeVariants,
      'manageAuto' => value.manageAuto,
      'fatal' => value.fatal,
      _ => null,
    };
  } on NoSuchMethodError { return null; }
}

Future<void> drain() async {
  for (var i = 0; i < 60; i++) { await Future<void>.value(); }
}

class Fetch implements MovaHttpFetch {
  final requests = <String>[];
  @override
  Future<Uint8List?> get(Uri uri) async {
    requests.add('$uri');
    return Uint8List.fromList(utf8.encode('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100000\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=900000\nhigh.m3u8\n'));
  }
  @override
  Future<void> close() async {}
}

class Kernel extends MovaTestKernel {
  Kernel() : super(nativeRestartAvailable: true);
  final output = StreamController<MovaLogLine>.broadcast();
  final opens = <Map<String, Object?>>[];
  @override
  Stream<MovaLogLine> get logs => output.stream;
  @override
  Future<void> open(String uri, {bool play = true}) async {
    await super.open(uri, play: play);
    opens.add({'uri': uri, 'play': play, 'options': stagedSourceOptions.isEmpty ? <String,String>{} : Map.of(stagedSourceOptions.last)});
  }
  void land() { emitDuration(const Duration(seconds: 100)); emitSize(640, 360); emitRestart(); emitBuffering(false); }
  @override
  Future<void> dispose() async { await output.close(); await super.dispose(); }
}

class PendingHook extends MovaHook {
  final playEntered = Completer<void>(), seekEntered = Completer<void>();
  final playRelease = Completer<bool>(), seekRelease = Completer<Duration?>();
  @override
  Future<bool> beforeOpen(MovaSource source) async => !source.uri.contains('rejected');
  @override
  Future<bool> beforePlay() { playEntered.complete(); return playRelease.future; }
  @override
  Future<Duration?> beforeSeek(Duration target) { seekEntered.complete(); return seekRelease.future; }
}

Future<void> run() async {
  final defaults = const MovaAbrConfig();
  final probe = read(defaults, 'probeVariants'), auto = read(defaults, 'manageAuto');
  if (probe == null || auto == null) {
    // This detached S00 snapshot predates A1. Absence is not a successful
    // comparison, nor a product failure against the newer implementation.
    for (final id in ids) { emit(id, {'probeVariants': probe, 'manageAuto': auto, 'apiUnavailable': true}, null); }
    return;
  }
  emit('CONTRACT.defaults', {'probeVariants': probe, 'manageAuto': auto}, probe == true && auto == false);
  for (final enabled in [true, false]) {
    final abr = Function.apply(MovaAbrConfig.new, [], {#probeVariants: enabled}) as MovaAbrConfig;
    final fetch = Fetch(), kernel = Kernel();
    final a = MovaEngine(kernel: kernel, fetcher: fetch, options: MovaOpts(abr: abr));
    try {
      await a.open(const MovaSource('https://s00e.invalid/master.m3u8'));
      kernel.land(); await drain();
      final autoRequests = fetch.requests.length, autoQualities = a.state.qualities.length;
      await a.loadQualities(); await drain();
      emit('CONTRACT.probe.$enabled', {'autoRequests': autoRequests, 'autoQualities': autoQualities,
        'explicitQualities': a.state.qualities.length, 'requests': List.of(fetch.requests)},
        (enabled ? autoRequests > 0 && autoQualities > 0 : autoRequests == 0 && autoQualities == 0) && a.state.qualities.isNotEmpty);
    } finally { await a.dispose(); }
  }
  await errors(); await rejected(); await replay();
}

Future<void> errors() async {
  final k = Kernel(); final a = MovaEngine(kernel: k);
  final events = <MovaErrorEvent>[];
  final sub = a.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(events.add);
  try {
    await a.open(const MovaSource('s00e://errors')); k.land(); await drain();
    k.output.add(const MovaLogLine(prefix: 'vd', level: 'error', text: 'S00E recoverable decoder diagnostic'));
    k.emitError('S00E recoverable decoder diagnostic'); await drain();
    final fatals = events.map((v) => read(v, 'fatal')).toList();
    emit('CONTRACT.error.nonterminal', {'stateError': a.state.error?.toString(), 'fatal': fatals, 'count': events.length},
      fatals.isEmpty || fatals.contains(null) ? null : a.state.error == null && fatals.every((v) => v == false));
    k.emitEndFile(MovaEndFileReason.error); await drain();
    emit('CONTRACT.error.terminal', {'stateError': a.state.error?.toString(), 'hasError': a.state.error != null}, a.state.error != null);
  } finally { await sub.cancel(); await a.dispose(); }
}

Future<void> rejected() async {
  final hook = PendingHook(), k = Kernel();
  final a = MovaEngine(kernel: k, interceptors: [hook]);
  try {
    await a.open(const MovaSource('s00e://accepted'), autoPlay: false); k.land(); await drain();
    final play = a.play(), seek = a.seek(const Duration(seconds: 12));
    await Future.wait([hook.playEntered.future, hook.seekEntered.future]);
    final accepted = await a.open(const MovaSource('s00e://rejected'));
    hook.playRelease.complete(true); hook.seekRelease.complete(const Duration(seconds: 12));
    await Future.wait([play, seek]); await drain();
    emit('CONTRACT.rejectedOpen', {'accepted': accepted, 'uri': k.lastUri,
      'playCalls': k.calls.where((v) => v == 'play').length, 'seekCalls': k.calls.where((v) => v == 'seek').length,
      'seekTarget': k.lastSeek?.inMilliseconds}, !accepted && k.calls.contains('play') && k.lastSeek == const Duration(seconds: 12));
  } finally { await a.dispose(); }
}

Future<void> replay() async {
  for (final live in [false, true]) {
    final k = Kernel(); final fetch = Fetch();
    final a = MovaEngine(kernel: k, fetcher: fetch, options: const MovaOpts(
      live: MovaLiveConfig(backToLive: MovaBackToLive.reopen),
      recovery: MovaRecoveryConfig(enabled: true, policy: MovaRetryThenFailover(retryDelay: Duration.zero))));
    try {
      await a.open(MovaSource('https://s00e.invalid/master.m3u8',
        type: live ? MovaStreamType.live : MovaStreamType.vod,
        mpvOptions: const {'http-header-fields': 'X-S00E: effective', 'network-timeout': '7'}));
      k.land(); await a.loadQualities(); await drain();
      await a.switchQuality(a.state.qualities.where((v) => !v.isAuto).first); k.land(); await drain();
      final before = Map<String, Object?>.of(k.opens.last);
      if (live) { await a.backToLiveEdge(); }
      else {
        final count = k.opens.length;
        k.emitEndFile(MovaEndFileReason.error);
        await c.until(() => k.opens.length > count);
      }
      final after = Map<String, Object?>.of(k.opens.last);
      emit('CONTRACT.replay.${live ? 'edge' : 'retry'}', {'before': before, 'after': after, 'opens': k.opens},
        jsonEncode(before) == jsonEncode(after));
    } finally { await a.dispose(); }
  }
}
