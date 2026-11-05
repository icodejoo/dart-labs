// 组 opacity 的 saveLayer 成本基准：统计动画页 spinner 与含 opacity 的真实图标
// 录制时产生的 saveLayer 次数（宿主 JIT 录制，不做 GPU 光栅化计时）。
// Host JIT recording benchmark for the existing animation-screen spinner and
// real icons containing opacity (including fill/stroke opacity). Run from
// benchmark/bench_app with prebuilt/windows/x64 on PATH. No GPU raster timing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bench_app/anim_icons_real.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/svgx.dart' show RustLib;

void main() {
  setUpAll(RustLib.init);
  test(
    'saveLayer counts on real icons and SVGator CSS (exact masks)',
    () async {
      final css = Platform.environment['SVGX_CSS_SAMPLES'];
      final corpora = <String, List<String>>{
        'all icons': animIconsReal,
        if (css != null)
          'SVGator CSS': [
            for (final file in Directory(css).listSync().whereType<File>())
              if (file.path.endsWith('.svg')) file.readAsStringSync(),
          ],
      };
      for (final entry in corpora.entries) {
        var layers = 0;
        var draws = 0;
        for (final source in entry.value) {
          final d = parseAnimatedSvgDocument(source);
          final clock = ValueNotifier(Duration.zero);
          final painter = AnimatedSvgPainter(
            root: d.root,
            intrinsicSize: Size(d.width, d.height),
            clock: clock,
            theme: const SvgxTheme(),
            fit: BoxFit.contain,
            alignment: Alignment.center,
            gradients: d.gradients,
            clipPaths: d.clipPaths,
            masks: d.masks,
          );
          for (final ms in [0, 333, 777, 1501, 2503]) {
            clock.value = Duration(milliseconds: ms);
            final canvas = _CountingCanvas();
            painter.paint(canvas, const Size(32, 32));
            layers += canvas.layers;
            draws += canvas.draws;
          }
          clock.dispose();
        }
        debugPrint(
          '${entry.key}: docs=${entry.value.length}, frames=5, '
          'saveLayer=$layers, draws=$draws',
        );
      }
    },
  );

  test('opacity corpus recording benchmark', () async {
    final source = File('lib/anim_bench_screen.dart').readAsStringSync();
    final spinner = RegExp(
      r"const String _kSpinnerSvg =([\s\S]*?);\s*\n\s*///",
      multiLine: true,
    ).firstMatch(source)!.group(1)!;
    final svg = RegExp("'([^']*)'")
        .allMatches(spinner)
        .map((m) => m.group(1)!)
        .join();
    for (final entry in {
      'spinner': [svg],
      'opacity corpus': animIconsReal
          .where((s) => s.contains('opacity'))
          .toList(),
    }.entries) {
      final docs = entry.value.map(parseAnimatedSvgDocument).toList();
      final clock = ValueNotifier(Duration.zero);
      final painters = docs
          .map(
            (d) => AnimatedSvgPainter(
              root: d.root,
              intrinsicSize: Size(d.width, d.height),
              clock: clock,
              theme: const SvgxTheme(),
              fit: BoxFit.contain,
              alignment: Alignment.center,
              gradients: d.gradients,
              clipPaths: d.clipPaths,
              masks: d.masks,
            ),
          )
          .toList();
      void run(int frames) {
        for (var f = 0; f < frames; f++) {
          clock.value = Duration(microseconds: f * 16667);
          for (final p in painters) {
            final r = ui.PictureRecorder();
            p.paint(ui.Canvas(r), const Size(32, 32));
            r.endRecording().dispose();
          }
        }
      }

      final frames = docs.length == 1 ? 10000 : 120;
      run(frames);
      final times = <int>[];
      for (var i = 0; i < 7; i++) {
        final w = Stopwatch()..start();
        run(frames);
        w.stop();
        times.add(w.elapsedMicroseconds);
      }
      times.sort();
      debugPrint(
        '${entry.key}: docs=${docs.length}, median=${times[3] / frames / docs.length} us/document/frame',
      );
      clock.dispose();
    }
  });
}

class _CountingCanvas implements ui.Canvas {
  int layers = 0;
  int draws = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #saveLayer) layers++;
    if (invocation.memberName.toString().contains('draw')) draws++;
    return null;
  }
}
