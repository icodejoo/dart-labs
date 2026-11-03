// ignore_for_file: implementation_imports
// 未上机。只通过真实 mpv sub-add 错误及真实 404 触发错误。
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mova/mova.dart';
import 'cp1_harness.dart';
import 'package:mova/src/core/kernel/mpv_event_pump.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

Future<void> runErrclass(Cp1Harness h) async {
  for (final kind in ['nonfatal', 'fatal', 'poster']) {
    for (var run = 0; run < h.runs; run++) {
      final a = createMovaEngine(); // poster must enable restart itself.
      if (kind == 'poster') {
        h.poster = ColoredBox(key: h.posterKey, color: Colors.orange);
      }
      await h.mount(a);
      final begin = h.records.length;
      if (kind == 'fatal') {
        final native =
            (a.renderHandle as VideoController).player.platform as NativePlayer;
        final pump = MovaMpvEventPump(
          createFfiMpvEventBackend(
            native,
            await native.handle,
            pollInDebug: true,
          ),
          name: 'cp1_error_$run',
          onRestart: () {},
          onEndFile: (reason) => h.mark('END_FILE', {'reason': reason}),
        );
        await pump.start(Future<void>.value());
        h.cleanup.add(pump.dispose);
        try {
          await a.open(
            MovaSource(
              'http://127.0.0.1:18194/missing.mp4?t=${DateTime.now().microsecondsSinceEpoch}',
            ),
          );
        } catch (e) {
          h.mark('OPEN_ERROR', {'error': '$e'});
        }
        await h.until(() => a.state.error != null);
        await h.frame();
        final errors = h.events('MovaErrorEvent', begin);
        final endFile = h.records
            .skip(begin)
            .where((r) => r['kind'] == 'END_FILE' && r['reason'] == 4)
            .toList();
        final terminal = errors.any(
          (r) => (r['payload'] as Map)['fatal'] == true,
        );
        h.check(
          'fatal.$run',
          {
            'endFile': endFile,
            'errors': errors,
            'state': h.snapshot(),
            'overlay': h.errorVisible(),
            'text': a.options.strings.playbackError,
            'spinnerCount': h
                .elements()
                .where((e) => e.widget is CircularProgressIndicator)
                .length,
          },
          pass:
              terminal &&
              endFile.isNotEmpty &&
              a.state.error != null &&
              !a.state.buffering &&
              h.errorVisible() &&
              h.elements().every((e) => e.widget is! CircularProgressIndicator),
        );
      } else {
        await a.open(h.source('a'));
        await h.until(() => a.state.rendered);
        await h.frame();
        if (kind == 'nonfatal') {
          final before = await h.native();
          final native =
              (a.renderHandle as VideoController).player.platform
                  as NativePlayer;
          try {
            await native.command([
              'sub-add',
              'http://127.0.0.1:18194/bad.srt',
              'select',
            ]);
          } catch (e) {
            h.mark('SUB_ERROR', {'error': '$e'});
          }
          var observed = true;
          try {
            await h.until(
              () => h
                  .events('MovaErrorEvent', begin)
                  .any((r) => (r['payload'] as Map)['fatal'] == false),
              seconds: 8,
            );
          } catch (_) {
            observed = false;
          }
          await h.frame();
          final after = await h.native();
          h.check(
            'nonfatal.$run',
            {
              'before': before,
              'after': after,
              'errors': h.events('MovaErrorEvent', begin),
              'state': h.snapshot(),
              'overlay': h.errorVisible(),
            },
            pass:
                observed &&
                a.state.error == null &&
                !h.errorVisible() &&
                (after['timePosMs'] as int) > (before['timePosMs'] as int),
            missing: observed ? null : '夹具未产生非终结 mpv error 日志，不能判产品',
          );
        } else {
          final frames = h.events('MovaFirstFrame', begin);
          final opacity = h.posterOpacity();
          final hidden = h.records
              .skip(begin)
              .where((r) => r['kind'] == 'POSTER' && r['opacity'] == 0)
              .toList();
          if (hidden.isEmpty) {
            await h.until(
              () => h.records
                  .skip(begin)
                  .any((r) => r['kind'] == 'POSTER' && r['opacity'] == 0),
            );
          }
          final samples = h.records
              .skip(begin)
              .where((r) => r['kind'] == 'POSTER')
              .toList();
          final observedUs =
              samples.firstWhere((r) => r['opacity'] == 0)['us'] as int;
          h.check(
            'poster.$run',
            {
              'frames': frames,
              'posterHiddenObservedUs': observedUs,
              'opacity': opacity,
              'posterSamples': samples,
              'native': await h.native(),
            },
            pass:
                frames.isNotEmpty &&
                frames.first['signal'] == 'restart' &&
                opacity == 0 &&
                observedUs >= (frames.first['us'] as int),
            missing: opacity == null ? '未找到真实 poster AnimatedOpacity' : null,
          );
        }
      }
      await h.release();
      h.poster = null;
    }
  }
}
