// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'auto_kit.dart';

class Cp2NativePending implements Exception {
  const Cp2NativePending();
  @override
  String toString() => 'native properties not ready';
}

typedef Cp2Script = Future<void> Function(Cp2Harness h);

void cp2Main(String scene, Cp2Script script, {bool automatic = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(
    MaterialApp(
      home: Cp2Page(
        scene: scene,
        script: script,
        automatic: automatic || kAutoRun || coverageRunsOverride != null,
      ),
    ),
  );
}

/// Independent pages share only recording, mounting and native readback.
class Cp2Page extends StatefulWidget {
  const Cp2Page({
    super.key,
    required this.scene,
    required this.script,
    required this.automatic,
  });
  final String scene;
  final Cp2Script script;
  final bool automatic;
  @override
  State<Cp2Page> createState() => Cp2Harness();
}

class Cp2Harness extends State<Cp2Page> with WidgetsBindingObserver {
  final kernelReleases = <Future<void> Function()>[];
  final nativePlayers = <MovaApi, Player>{};
  bool guarded = false;
  final clock = Stopwatch()..start();
  final records = <Map<String, Object?>>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final acks = <String>{};
  final positions = <MovaApi, Duration>{};
  Duration position(MovaApi a) => positions[a] ?? Duration.zero;
  final videoKey = GlobalKey();
  HttpServer? server;
  MovaApi? api;
  bool rawVideo = false;
  bool backgroundPause = true;
  Axis? outerAxis;
  PageController? pages;
  int pageIndex = 0;
  bool running = false;
  bool completed = false;
  int get runs => autoRuns();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 18083);
      server!.listen((request) async {
        if (request.uri.path == '/snapshot' && api != null) {
          final sample=await native();
          request.response.headers.contentType=ContentType.json;
          request.response.write(jsonEncode(sample));
          await request.response.close();
          return;
        }
        if (request.uri.path == '/ack') {
          final id = request.uri.queryParameters['id']!;
          hostData[id] =
              jsonDecode(request.uri.queryParameters['data'] ?? '{}')
                  as Map<String, dynamic>;
          acks.add(id);
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'scene': widget.scene,
            'completed': completed,
            'records': records,
          }),
        );
        await request.response.close();
      });
      mark('SERVER', {'port': 18083});
      if (widget.automatic) unawaited(start());
    });
  }

  Map<String, Object?> snapshot([MovaApi? a]) {
    final s = (a ?? api)!.state;
    return {
      'positionMs': position(a ?? api!).inMilliseconds,
      'durationMs': s.duration.inMilliseconds,
      'playing': s.playing,
      'intent': s.playbackIntent,
      'buffering': s.buffering,
      'rendered': s.rendered,
      'renderEpoch': s.renderEpoch,
      'sourceIndex': s.sourceIndex,
      'fullscreen': s.fullscreen,
      'pip': s.pip,
      'mini': s.mini,
      'keepAlivePhase': s.keepAlivePhase.name,
      'fit': s.fit.name,
      'zoom': s.zoom,
      'locked': s.locked,
      'size': '${s.width}x${s.height}',
      'error': s.error?.toString(),
      'quality': s.currentQuality?.label,
      'volume': s.volume,
      'brightness': s.brightness,
      'rate': s.rate,
      'timeshiftBehindMs': s.timeshiftBehind?.inMilliseconds,
      'windowMs': s.seekableWindow.inMilliseconds,
    };
  }

  void mark(String kind, Map<String, Object?> values) {
    final r = <String, Object?>{
      ...values,
      // Envelope identity must never be overwritten by event payloads.
      'kind': kind,
      'us': clock.elapsedMicroseconds,
      'scene': widget.scene,
    };
    records.add(r);
    print('[MOVA-CP2] ${jsonEncode(r)}');
  }

  void check(
    String id,
    Map<String, Object?> numbers, {
    bool? pass,
    String? missing,
  }) {
    mark('CHECK', {
      'id': 'CP2.${widget.scene}.$id',
      'pass': missing == null ? pass : null,
      'status': missing != null || pass == null
          ? 'BLOCKED'
          : pass
          ? 'PASS'
          : 'FAIL',
      'missing': missing,
      'numbers': numbers,
      'deviceStatus': '未上机',
    });
  }

  final cleanup = <Future<void> Function()>[];
  final sourceUris = <MovaApi, String>{};
  Timer? posterWatch;
  Widget? poster;
  Widget? customSurface;
  final posterKey = GlobalKey();
  final hostData = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> control(
    String action, [
    Map<String, Object?> args = const {},
  ]) async {
    final client = HttpClient();
    try {
      final uri = Uri.http('127.0.0.1:18194', '/control', {
        'action': action,
        ...args.map((k, v) => MapEntry(k, '$v')),
      });
      final req = await client.getUrl(uri);
      final data =
          jsonDecode(await utf8.decoder.bind(await req.close()).join())
              as Map<String, dynamic>;
      mark('FIXTURE', {'action': action, 'data': data});
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> frame() async {
    await WidgetsBinding.instance.endOfFrame;
  }

  void refresh() => setState(() {});
  List<Map<String, Object?>> events(String name, int begin) =>
      records.skip(begin).where((r) => r['event'] == name).toList();
  List<Element> elements() {
    final out = <Element>[];
    void visit(Element e) {
      out.add(e);
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return out;
  }

  bool errorVisible() => elements().any(
    (e) =>
        e.widget is Text &&
        (e.widget as Text).data == api?.options.strings.playbackError,
  );
  double? posterOpacity() {
    final ctx = posterKey.currentContext;
    if (ctx == null) return null;
    double? value;
    ctx.visitAncestorElements((e) {
      if (e.widget is AnimatedOpacity) {
        value = (e.widget as AnimatedOpacity).opacity;
        return false;
      }
      return true;
    });
    return value;
  }

  Future<void> hostSample(String id, String action) async {
    await host(id, action);
  }

  Future<T> call<T>(
    String method,
    Object? args,
    Future<T> Function() action,
  ) async {
    mark('CALL', {
      'method': method,
      'args': args,
      'state': api == null ? null : snapshot(),
    });
    try {
      final result = await action();
      mark('RET', {
        'method': method,
        'result': '$result',
        'state': api == null ? null : snapshot(),
      });
      return result;
    } catch (e, st) {
      mark('RET', {'method': method, 'exception': '$e', 'stack': '$st'});
      rethrow;
    }
  }

  void observe(MovaApi a) {
    final controller = a.renderHandle;
    if (controller is VideoController) {
      subscriptions.add(
        controller.player.stream.log.listen((log) {
          if (log.level == 'error') {
            mark('KERNEL_LOG', {
              'prefix': log.prefix,
              'level': log.level,
              'text': log.text,
            });
          }
        }),
      );
    }
    subscriptions.add(
      a.progress.listen((p) {
        positions[a] = p.position;
      }),
    );
    subscriptions.add(
      a.events.listen((e) {
        final payload = switch (e) {
          MovaSourceChange() => {'uri': e.source.uri},
          MovaSeek() => {'target': e.target.inMilliseconds},
          MovaSeeked() => {'position': e.position.inMilliseconds},
          MovaBufferChange() => {'buffering': e.buffering},
          MovaDurationChange() => {'duration': e.duration.inMilliseconds},
          MovaFirstFrame() => {
            'sinceOpen': e.sinceOpen.inMilliseconds,
            'signal': e.signal.name,
          },
          MovaSizeChange() => {'width': e.width, 'height': e.height},
          MovaVolumeChange() => {'value': e.value},
          MovaBrightChange() => {'value': e.value},
          MovaRateChange() => {'value': e.value},
          MovaFitChange() => {'fit': e.fit.name},
          MovaZoomChange() => {'zoom': e.zoom},
          MovaLockChange() => {'value': e.value},
          MovaFullScreenChange() => {'value': e.value},
          MovaOrientationChange() => {'orientation': e.orientation.name},
          MovaMiniChange() => {'mini': e.mini},
          MovaPipChange() => {'value': e.value},
          MovaQualityListChange() => {
            'qualities': e.qualities.map((q) => '${q.label}:${q.uri}').toList(),
          },
          MovaQualityChange() => {'quality': e.quality.label},
          MovaAbrDownShift() => {'from': e.from.label, 'to': e.to.label},
          MovaCutoverChange() => {'phase': e.phase.name},
          MovaPreviewBlock() => {'reason': e.reason.name},
          MovaSttBlock() => {'reason': e.reason.name},
          MovaErrorEvent() => {
            'error': '${e.error}',
            'fatal': e.fatal,
            'code': e.code,
          },
          MovaPlayFailure() => {
            'kind': e.fail.kind.name,
            'action': '${e.action}',
            'attempt': e.fail.attempt,
            'isLive': e.fail.isLive,
            'sourceIndex': e.fail.sourceIndex,
          },
          MovaRecovered() => {'attempts': e.attempts},
          MovaFailover() => {'from': e.from, 'to': e.to, 'uri': e.uri},
          MovaTimeShiftChange() => {'behind': e.behind.inMilliseconds},
          MovaKeepAliveChange() => {
            'phase': e.phase.name,
            'reason': e.reason.name,
            'mode': '${e.mode}',
          },
          MovaKeepAliveResume() => {
            'elapsed': e.elapsed.inMilliseconds,
            'signal': '${e.signal}',
          },
          _ => <String, Object?>{},
        };
        if (e is MovaSourceChange) sourceUris[a] = e.source.uri;
        mark('EVENT', {
          'uriAtEvent': sourceUris[a],
          'event': e.runtimeType.toString(),
          'payload': payload,
          'state': snapshot(a),
          if (e is MovaFirstFrame) 'sinceOpenUs': e.sinceOpen.inMicroseconds,
          if (e is MovaFirstFrame) 'signal': e.signal.name,
          if (e is MovaSourceChange) 'uri': e.source.uri,
        });
      }),
    );
    subscriptions.add(
      a.states.listen((s) => mark('STATE', {'state': snapshot(a)})),
    );
  }

  MovaSource source(
    String name, {
    bool slow = false,
    bool live = false,
  }) => MovaSource(
    live
        ? 'http://127.0.0.1:18192/live.m3u8?t=${DateTime.now().microsecondsSinceEpoch}'
        : 'http://127.0.0.1:18190/$name.mp4?t=${DateTime.now().microsecondsSinceEpoch}${slow ? '&slow=1' : ''}',
    type: live ? MovaStreamType.live : MovaStreamType.vod,
    title: name,
  );

  Future<void> mount(
    MovaApi a, {
    bool raw = false,
    bool pause = true,
    Axis? axis,
  }) async {
    api = a;
    rawVideo = raw;
    backgroundPause = pause;
    outerAxis = axis;
    pages?.dispose();
    pages = axis == null ? null : PageController();
    pageIndex = 0;
    observe(a);
    if (poster != null) {
      posterWatch?.cancel();
      double? previous;
      posterWatch = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final value = posterOpacity();
        if (value != previous && value != null) {
          mark('POSTER', {'opacity': value, 'uri': sourceUris[a]});
          previous = value;
        }
      });
    }
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    mark('MOUNT', {
      'rawVideo': raw,
      'pauseUponEnteringBackgroundMode': pause,
      'axis': axis?.name,
    });
  }

  /// Inspect the actual mounted surface, rather than the requested config.
  bool hasMountedGuard(MovaApi target) {
    var found = false;
    void visit(Element element) {
      final widget = element.widget;
      if (element.mounted && widget is MovaAutoPause &&
          identical(widget.api, target)) {
        found = true;
      }
      element.visitChildren(visit);
    }
    videoKey.currentContext?.visitChildElements(visit);
    return found;
  }

  Future<void> until(
    FutureOr<bool> Function() condition, {
    int seconds = 30,
  }) async {
    final deadline = clock.elapsedMilliseconds + seconds * 1000;
    while (true) {
      var ready = false;
      try {
        ready = await condition();
      } on Cp2NativePending {
        ready = false;
      }
      if (ready) {
        return;
      }
      if (clock.elapsedMilliseconds > deadline) {
        throw TimeoutException('CP2 condition; scene=${widget.scene}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<Map<String, Object?>> native() async {
    final deadline = clock.elapsedMilliseconds + 10000;
    while (true) {
      final active = api is MovaCutoverEngine
          ? (api as MovaCutoverEngine).active
          : api!;
      final epoch = api!.state.renderEpoch;
      final owner = nativePlayers[active] ?? (active.renderHandle as VideoController).player;
      final player = owner.platform as NativePlayer;
      final values = await Future.wait(
        [
          'path',
          'time-pos',
          'pause',
          'duration',
          'vid',
          'mute',
          'seeking',
          'audio-codec-name',
          'volume',
        ].map(player.getProperty),
      );
      final stable =
          api is! MovaCutoverEngine ||
          identical((api as MovaCutoverEngine).active, active);
      if (stable && epoch == api!.state.renderEpoch &&
          values[0].isNotEmpty &&
          double.tryParse(values[1]) != null) {
        final r = <String, Object?>{
          'path': values[0],
          'timePosMs': (double.parse(values[1]) * 1000).round(),
          'pause': values[2],
          'duration': values[3],
          'vid': values[4],
          'mute': values[5],
          'seeking': values[6],
          'audioCodec': values[7],
          'nativeVolume': values[8],
          'engine': identityHashCode(active),
          'epochAtRead': epoch,
          'state': snapshot(),
        };
        mark('NATIVE', r);
        return r;
      }
      mark('NATIVE_PENDING', {'properties': values, 'activeStable': stable});
      if (clock.elapsedMilliseconds >= deadline) {
        throw TimeoutException('native path/time-pos unavailable');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> waitPosition(int ms) async =>
      until(() async => (await native())['timePosMs'] as int >= ms);

  Future<void> host(String id, String action) async {
    final box = videoKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    mark('HOST', {
      'id': id,
      'action': action,
      if (box != null && origin != null)
        'rect': {
          'x': origin.dx * dpr,
          'y': origin.dy * dpr,
          'w': box.size.width * dpr,
          'h': box.size.height * dpr,
        },
    });
    await until(() => acks.contains(id), seconds: 60);
    mark('HOST_ACK', {'id': id});
  }

  Future<void> release({bool disposeEngine = true}) async {
    if (api == null) return;
    posterWatch?.cancel();
    posterWatch = null;
    for (final dispose in cleanup) {
      await dispose();
    }
    cleanup.clear();
    // Keep the real surface mounted until disposal completes.
    if (disposeEngine) {
      await call(
        'dispose',
        null,
        () => api!.dispose(),
      ).timeout(const Duration(seconds: 15));
    }
    // Includes active, warming and already-retired cutover kernels. Do not
    // clear bookkeeping or start the next iteration before native release.
    await Future.wait(kernelReleases.map((release) => release()))
        .timeout(const Duration(seconds: 30));
    mark('RELEASE_DRAINED', {'kernels': kernelReleases.length});
    kernelReleases.clear();
    for (final s in subscriptions) {
      await s.cancel();
    }
    subscriptions.clear();
    api = null;
    customSurface = null;
    guarded = false;
    nativePlayers.clear();
    if (mounted) {
      setState(() {});
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> start() async {
    if (running) return;
    running = true;
    setState(() {});
    mark('BEGIN', {'runs': runs});
    try {
      await widget.script(this);
    } catch (e, st) {
      mark('ERROR', {'kindDetail': 'HARNESS', 'error': '$e', 'stack': '$st'});
      check('harness', {}, missing: '$e');
    } finally {
      try {
        await release();
      } catch (e, st) {
        mark('ERROR', {'kindDetail': 'HARNESS', 'error': '$e', 'stack': '$st'});
      }
      completed = true;
      mark('END', {'completed': true});
      print('CP2 AUTORUN DONE ${widget.scene}');
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    mark('LIFECYCLE', {
      'value': state.name,
      'state': api == null ? null : snapshot(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = api;
    Widget surface =
        customSurface ??
        (a == null
            ? const Center(child: Text('等待场景'))
            : rawVideo
            ? Video(
                controller: a.renderHandle as VideoController,
                pauseUponEnteringBackgroundMode: backgroundPause,
                resumeUponEnteringForegroundMode: false,
              )
            : MovaPlayer(api: a, poster: poster));
    if (guarded && a != null) {
      surface = MovaAutoPause(api: a, child: surface);
    }
    if (outerAxis != null) {
      surface = PageView(
        controller: pages,
        scrollDirection: outerAxis!,
        onPageChanged: (v) {
          pageIndex = v;
          mark('PAGE', {'index': v});
        },
        children: [
          surface,
          const ColoredBox(
            color: Colors.indigo,
            child: Center(child: Text('Page 2')),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('CP2 ${widget.scene}')),
      body: Column(
        children: [
          SizedBox(key: videoKey, height: 300, child: surface),
          Text(
            completed
                ? '完成：${records.where((r) => r['kind'] == 'CHECK').length} CHECK'
                : '独立验证页；原始记录 HTTP :18083',
          ),
          if (!running)
            ElevatedButton(onPressed: start, child: const Text('运行验证')),
          const Expanded(
            child: SingleChildScrollView(child: Text('未上机；CP2 记录产品判据与原生证据。')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(server?.close(force: true));
    pages?.dispose();
    super.dispose();
  }
}
