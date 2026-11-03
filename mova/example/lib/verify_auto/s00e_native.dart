import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import '../main_coverage_api.dart' as c;
import 's00d_native.dart' as n;
import 's00e_trace.dart';

final pending = <String, Completer<Map<String, Object?>>>{};
int sequence = 0;
void acknowledge(String token, String? sample) {
  final waiter = pending[token];
  if (waiter == null || waiter.isCompleted || sample == null) return;
  waiter.complete(Map<String, Object?>.from(jsonDecode(sample) as Map));
}

Future<Map<String, Object?>> host(String phase) async {
  final token = '$phase-${sequence++}';
  final waiter = Completer<Map<String, Object?>>(); pending[token] = waiter;
  c.mark('S00E_HOST_REQUEST', {'token': token, 'phase': phase});
  try { return await waiter.future.timeout(const Duration(seconds: 30)); }
  on TimeoutException { return {}; }
  finally { pending.remove(token); }
}

void check(String id, Map<String, Object?> numbers, bool? pass) =>
    c.mark('CHECK', {'id': id, 'origin': 's00e-native', 'numbers': numbers, 'pass': pass});

Future<void> drag(Offset start, Offset delta) async {
  final id = sequence++ + 30000;
  final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
  GestureBinding.instance.handlePointerEvent(PointerDownEvent(pointer: id, position: start, viewId: view.viewId));
  var previous = start;
  for (var i = 1; i <= 8; i++) {
    final position = start + delta * (i / 8);
    GestureBinding.instance.handlePointerEvent(PointerMoveEvent(pointer: id,
      position: position, delta: position - previous, viewId: view.viewId));
    previous = position;
    await WidgetsBinding.instance.endOfFrame;
  }
  GestureBinding.instance.handlePointerEvent(PointerUpEvent(pointer: id, position: previous, viewId: view.viewId));
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> locks() async {
  final a = createMovaEngine();
  try {
    await n.mount(a); await a.open(c.source()); await c.until(() => a.state.rendered);
    final player = n.elements((w) => w is MovaPlayer).single.findRenderObject() as RenderBox;
    for (final locked in [false, true, false]) {
      await a.setLocked(locked); await a.setVolume(30); await a.setBrightness(.3);
      await WidgetsBinding.instance.endOfFrame;
      final before = await host('lock-$locked-before');
      await drag(player.localToGlobal(Offset(player.size.width * .2, player.size.height * .7)),
        Offset(0, -player.size.height * .3));
      await drag(player.localToGlobal(Offset(player.size.width * .8, player.size.height * .7)),
        Offset(0, -player.size.height * .3));
      final after = await host('lock-$locked-after');
      final known = ['brightness', 'appBrightness', 'volume'].every((k) => before[k] is num && after[k] is num);
      check('A13.native.$locked', {'before': before, 'after': after, 'locked': a.state.locked},
        !known ? null : locked
          ? before['brightness'] == after['brightness'] && before['appBrightness'] == after['appBrightness'] && before['volume'] == after['volume']
          : before['brightness'] == after['brightness'] && (after['appBrightness'] as num) > (before['appBrightness'] as num) && (after['volume'] as num) > (before['volume'] as num));
    }
  } finally { await n.release(a); }
}

Future<void> lateFiles() async {
  final a = createMovaEngine(preciseFirstFrame: true);
  final events = <MovaEvent>[];
  final sub = a.events.listen(events.add);
  try {
    final native = await n.mount(a);
    for (var iteration = 0; iteration < 12; iteration++) {
      final old = c.source('s00e-missing-$iteration.mp4');
      // First establish a real old-file failure. An immediate second open
      // before the old request reached mpv would be a vacuous isolation test.
      final oldStart = events.length;
      try { await a.open(old); } on Object { /* Retain events below. */ }
      await c.until(() => events.skip(oldStart).whereType<MovaErrorEvent>().isNotEmpty ||
        events.skip(oldStart).whereType<MovaPlayFailure>().isNotEmpty);
      final oldFailures = events.skip(oldStart).where((e) => e is MovaErrorEvent || e is MovaPlayFailure).length;
      final boundary = events.length;
      final fresh = c.source();
      final accepted = await a.open(fresh);
      await c.until(() => a.state.rendered && a.state.playing);
      final positions = <String>[];
      final states = <Map<String, Object?>>[];
      for (var i = 0; i < 10; i++) {
        positions.add(await native.getProperty('time-pos'));
        states.add({'error': a.state.error?.toString(), 'playing': a.state.playing,
          'epoch': a.state.renderEpoch, 'path': await native.getProperty('path')});
        await WidgetsBinding.instance.endOfFrame;
      }
      final failures = events.skip(boundary).whereType<MovaPlayFailure>().map((e) => e.fail.kind.name).toList();
      check('N12.native.isolation', {'iteration': iteration, 'oldUri': old.uri, 'freshUri': fresh.uri,
        'accepted': accepted, 'oldFailures': oldFailures, 'paths': states.map((s) => s['path']).toList(),
        'errors': states.map((s) => s['error']).toList(), 'playing': states.map((s) => s['playing']).toList(),
        'failures': failures, 'positions': positions, 'sampleCount': states.length},
        accepted && states.every((s) => s['error'] == null && s['playing'] == true && s['path'] == fresh.uri) && failures.isEmpty);
    }
  } finally { await sub.cancel(); await n.release(a); }
}

Future<void> lazyVideo() async {
  for (final audio in [true, false]) {
    final start = videoCalls.length;
    final a = createMovaEngine(audioOnly: audio);
    // Never read renderHandle before this snapshot: reading it is the
    // attachment request and would invalidate the lazy-allocation experiment.
    await a.open(c.source(), autoPlay: false);
    final beforeMount = videoCalls.skip(start).where((r) => r['method'] == 'VideoOutputManager.Create').length;
    c.screen.value = a; await WidgetsBinding.instance.endOfFrame; await WidgetsBinding.instance.endOfFrame;
    if (!audio) { await c.until(() => videoCalls.skip(start).any((r) => r['replied'] == true)); }
    final mounted = videoCalls.skip(start).where((r) => r['method'] == 'VideoOutputManager.Create').length;
    await n.release(a);
    final calls = videoCalls.skip(start).toList();
    final released = calls.where((r) => r['method'] == 'VideoOutputManager.Dispose' && r['replied'] == true).length;
    check('N13.video.$audio', {'beforeMount': beforeMount, 'mounted': mounted, 'released': released,
      'calls': calls, 'binding': WidgetsBinding.instance.runtimeType.toString()},
      WidgetsBinding.instance is! S00eBinding ? null : beforeMount == 0 && mounted == (audio ? 0 : 1) && released == mounted);
  }
}

Future<void> seekTrace() async {
  final a = createMovaEngine(preciseFirstFrame: true);
  final logs = <Map<String, Object?>>[];
  StreamSubscription<PlayerLog>? sub;
  try {
    final native = await n.mount(a);
    final video = a.renderHandle as VideoController;
    sub = video.player.stream.log.listen((v) => logs.add({'prefix': v.prefix, 'level': v.level, 'text': v.text}));
    // The media_kit subscription may filter trace messages. In that case
    // commandTrace stays empty and this CHECK deliberately remains BLOCKED.
    await native.setProperty('msg-level', 'all=trace');
    await a.open(c.source('master.m3u8'), autoPlay: false);
    await c.until(() => a.state.rendered);
    logs.clear();
    final samples = <Map<String, Object?>>[];
    await a.seek(const Duration(seconds: 12));
    for (var i = 0; i < 120; i++) {
      samples.add({'seeking': await native.getProperty('seeking'), 'position': await native.getProperty('time-pos')});
      await WidgetsBinding.instance.endOfFrame;
    }
    final trace = logs.where((r) => RegExp(r'Run command: seek\b').hasMatch('${r['text']}')).toList();
    final positions = samples.map((s) => double.tryParse('${s['position']}')).toList();
    check('A7.native.trace', {'commandTrace': trace, 'callCount': trace.length, 'samples': samples,
      'finalPosition': positions.last, 'target': 12, 'maxCalls': 3}, trace.isEmpty || positions.last == null
        ? null : trace.length <= 3 && (positions.last! - 12).abs() <= .5);
  } finally { await sub?.cancel(); await n.release(a); }
}

Future<void> run() async {
  for (final work in [locks, lateFiles, lazyVideo, seekTrace]) {
    try { await work(); }
    on Object catch (error, stack) { c.mark('S00E_SCRIPT_ERROR', {'error': '$error', 'stack': '$stack'}); }
  }
  c.mark('S00E_PLATFORM', {'platform': Platform.operatingSystem});
}
