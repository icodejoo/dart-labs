import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import '../main_coverage_api.dart' as c;

// Real default wiring only. Every VideoController belongs to the MovaPlayer
// actually on c.screen. No hidden repeatedly-created texture controllers.
Future<NativePlayer> mount(MovaApi a) async {
  c.widgetMode.value = false;
  c.screen.value = a;
  c.observe(a);
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
  return (a.renderHandle as VideoController).player.platform as NativePlayer;
}

void check(String id, Map<String, Object?> numbers, bool? pass) =>
    c.mark('CHECK', {
      'id': id,
      'numbers': numbers,
      'pass': pass,
      'origin': 'native-mounted-player',
    });
Future<List<String>?> clients(NativePlayer n) async {
  final raw = await n.getProperty('client-list');
  c.mark('S00D_NATIVE_CLIENTS', {'raw': raw});
  try {
    final list = jsonDecode(raw);
    if (list is List &&
        list.isNotEmpty &&
        list.every((v) => v is String && v.isNotEmpty)) {
      return list.cast<String>();
    }
  } on FormatException {
    /* Try mpv's plain string-list representation below. */
  }
  final names = raw.split(RegExp(r'[,\r\n]+')).map((v) => v.trim()).toList();
  if (names.isNotEmpty &&
      names.every((v) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(v))) {
    return names;
  }

  return null;
}

Future<void> release(MovaApi a) async {
  await a.dispose();
  c.screen.value = null;
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> run() async {
  for (final variant in ['off', 'recovery', 'precise', 'reporterOff', 'qoe']) {
    final reports = <MovaReportEvent>[];
    final events = <MovaEvent>[];
    final recovery = variant == 'recovery';
    final reporter = variant == 'reporterOff' || variant == 'qoe';
    final a = createMovaEngine(
      preciseFirstFrame: variant == 'precise',
      options: MovaOpts(
        report: MovaReportConfig(qoe: variant == 'qoe'),
        recovery: MovaRecoveryConfig(
          enabled: recovery,
          policy: const MovaRetryThenFailover(maxRetries: 0),
        ),
      ),
      reporter: reporter
          ? MovaCallbackReporter((r) {
              reports.add(r);
              c.mark('S00D_NATIVE_REPORT', {
                'variant': variant,
                'name': r.name.value,
                'params': r.params,
                'sessionId': r.sessionId,
              });
            })
          : null,
    );
    final sub = a.events.listen(events.add);
    try {
      final native = await mount(a);
      final initialNames = await clients(native);
      check('N13.beforeOpen.$variant', {'clients': initialNames,
        'count': initialNames?.where((v) => v.startsWith('mova_qoe_')).length},
        initialNames == null ? null : !initialNames.any((v) => v.startsWith('mova_qoe_')));
      await a.open(c.source(), autoPlay: false);
      await c.until(() => a.state.rendered);
      final names = await clients(native);
      final count = names?.where((v) => v.startsWith('mova_qoe_')).length;
      // A14: first open lazily starts the shared terminal-failure observer.
      const expected = 1;
      check('N13.clients.$variant', {
        'clients': names,
        'count': count,
        'expectedCount': expected,
        'renderHandleType': a.renderHandle.runtimeType.toString(),
      }, count == null ? null : count == expected);
      final signals = events
          .whereType<MovaFirstFrame>()
          .map((e) => e.signal.name)
          .toList();
      check(
        'N5.restart.$variant',
        {
          'signals': signals,
          'restartCount': signals.where((s) => s == 'restart').length,
          'expectedRestart': variant == 'precise' || variant == 'qoe',
        },
        signals.isEmpty
            ? null
            : (variant == 'precise' || variant == 'qoe')
            ? signals.every((s) => s == 'restart')
            : !signals.contains('restart'),
      );
      if (variant == 'qoe') {
        final frames = reports
            .where((r) => r.name == MovaReportName.firstFrame)
            .toList();
        check(
          'F7.nativeFirstFrame',
          {
            'reports': frames.map((r) => r.params).toList(),
            'count': frames.length,
            'signal': frames.isEmpty ? null : frames.last.params['signal'],
            'ttffMs': frames.isEmpty ? null : frames.last.params['ttffMs'],
          },
          frames.isEmpty
              ? null
              : frames.length == 1 &&
                    frames.single.params['signal'] == 'restart',
        );
        final sample = <String, String>{};
        for (final key in [
          'video-bitrate',
          'cache-speed',
          'frame-drop-count',
          'decoder-frame-drop-count',
          'hwdec-current',
          'demuxer-via-network',
          'file-format',
        ]) {
          sample[key] = await native.getProperty(key);
        }
        check(
          'F7.nativeSample',
          {
            'properties': sample,
            'fieldCount': sample.length,
            'numericCount': sample.values
                .where((v) => num.tryParse(v) != null)
                .length,
          },
          sample['file-format']!.isEmpty
              ? null
              : sample['hwdec-current']!.isNotEmpty,
        );
      }
      // One local HTTP identity with observed request headers. A normal media
      // response is proxied from the established source server, byte-for-byte.
      if (variant == 'off') {
        await headers(a, native);
        await fitProperties(a);
        await snapshotGuard(a, native);
      }
      if (recovery) {
        await a.open(c.source('s00d-guaranteed-missing.mp4'));
        await c.until(() => events.whereType<MovaPlayFailure>().isNotEmpty);
        final failures = events.whereType<MovaPlayFailure>().toList();
        check('N5.endFile', {
          'kinds': failures.map((e) => e.fail.kind.name).toList(),
          'nativeEndErrors': failures
              .where((e) => e.fail.kind == MovaPlayFailKind.nativeEndError)
              .length,
        }, failures.any((e) => e.fail.kind == MovaPlayFailKind.nativeEndError));
      }
    } finally {
      await sub.cancel();
      await release(a);
    }
    // Reopen is forbidden after disposal; never query a destroyed mpv handle.
    final accepted = await a.open(c.source());
    check('F14.disposed.$variant', {'openAfterDispose': accepted}, !accepted);
  }
}

Future<void> headers(MovaApi a, NativePlayer n) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final observed = <String?>[];
  final client = HttpClient();
  final listener = server.listen((request) async {
    observed.add(request.headers.value('x-s00d'));
    final proxy = await client.getUrl(Uri.parse(c.source().uri));
    final range = request.headers.value('range');
    if (range != null) {
      proxy.headers.set('range', range);
    }
    final response = await proxy.close();
    request.response.statusCode = response.statusCode;
    response.headers.forEach((k, v) {
      request.response.headers.set(k, v);
    });
    await request.response.addStream(response);
    await request.response.close();
  });
  try {
    for (final header in ['one', 'two']) {
      observed.clear();
      await a.open(
        MovaSource(
          'http://127.0.0.1:${server.port}/media.mp4',
          mpvOptions: {
            'http-header-fields': 'X-S00D: $header',
            'demuxer-lavf-o': 'probesize=32768',
          },
        ),
        autoPlay: false,
      );
      await c.until(() => observed.isNotEmpty && a.state.rendered);
      final raw = await n.getProperty('http-header-fields');
      final lavf = await n.getProperty('demuxer-lavf-o');
      check(
        'C17.headers.$header',
        {
          'requests': List.of(observed),
          'nativeHeaders': raw,
          'expectedHeader': header,
          'lavf': lavf,
          'requestCount': observed.length,
        },
        observed.isNotEmpty &&
            observed.every((v) => v == header) &&
            raw.contains('X-S00D: $header') &&
            lavf.contains('probesize') &&
            lavf.contains('protocol_whitelist'),
      );
    }
  } finally {
    await listener.cancel();
    await server.close(force: true);
    client.close(force: true);
  }
}

List<Element> elements(bool Function(Widget) match) {
  final found = <Element>[];
  void visit(Element e) {
    if (match(e.widget)) {
      found.add(e);
    }
    e.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) {
    visit(root);
  }
  return found;
}

Future<void> fitProperties(MovaApi a) async {
  for (final fit in MovaFit.values) {
    await a.setFit(fit);
    await WidgetsBinding.instance.endOfFrame;
    final videos = elements((w) => w is Video);
    if (videos.length != 1) {
      check('A11.render.${fit.name}', {'videoCount': videos.length}, null);
      continue;
    }
    final element = videos.single;
    final video = element.widget as Video;
    final box = element.findRenderObject() as RenderBox;
    final mapped = applyBoxFit(
      video.fit,
      Size(a.state.width.toDouble(), a.state.height.toDouble()),
      box.size,
    );
    final expected = switch (fit) {
      MovaFit.contain => BoxFit.contain,
      MovaFit.cover => BoxFit.cover,
      MovaFit.fill => BoxFit.fill,
    };
    check(
      'A11.render.${fit.name}',
      {
        'videoCount': videos.length,
        'widgetFit': video.fit.name,
        'stateFit': a.state.fit.name,
        'videoWidth': a.state.width,
        'videoHeight': a.state.height,
        'viewportWidth': box.size.width,
        'viewportHeight': box.size.height,
        'sourceWidth': mapped.source.width,
        'sourceHeight': mapped.source.height,
        'destinationWidth': mapped.destination.width,
        'destinationHeight': mapped.destination.height,
      },
      a.state.width == 0 || a.state.height == 0
          ? null
          : video.fit == expected && a.state.fit == fit,
    );
  }
}

Future<void> snapshotGuard(MovaApi a, NativePlayer native) async {
  final guards = elements(
    (w) => w.runtimeType.toString() == 'MovaSnapshotGuard',
  );
  final flags = guards
      .map((e) => (e.widget as dynamic).enabled as bool)
      .toList();
  final videos = elements((w) => w is Video);
  if (guards.length != 1 || videos.length != 1) {
    check('N21.guard.${Platform.operatingSystem}', {
      'guardCount': guards.length,
      'videoCount': videos.length,
    }, null);
    return;
  }
  final nav = Navigator.of(videos.single);
  final epoch = a.state.renderEpoch;
  final path = await native.getProperty('path');
  var roundTrips = 0;
  for (var i = 0; i < 20; i++) {
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: ColoredBox(color: Colors.indigo)),
    );
    final popped = nav.push<void>(route);
    await c.until(() => route.animation?.status == AnimationStatus.completed);
    nav.pop();
    await popped;
    await c.until(
      () =>
          route.animation?.status == AnimationStatus.dismissed ||
          route.animation == null,
    );
    await WidgetsBinding.instance.endOfFrame;
    roundTrips++;
  }
  check(
    'N21.guard.${Platform.operatingSystem}',
    {
      'guardCount': guards.length,
      'videoCount': videos.length,
      'flags': flags,
      'roundTrips': roundTrips,
      'epochBefore': epoch,
      'epochAfter': a.state.renderEpoch,
      'pathBefore': path,
      'pathAfter': await native.getProperty('path'),
    },
    flags.single == Platform.isWindows &&
        roundTrips == 20 &&
        a.state.renderEpoch == epoch &&
        await native.getProperty('path') == path,
  );
}
