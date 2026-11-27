// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust/frb_generated.dart';

import '../lib/mdi_icons_1000.dart';

/// Collects timings around the actual generated sync bridge. / 在实际生成的同步桥两侧采集时间。
class _WireTiming extends BaseHandler {
  /// Most recent SSE message length. / 最新 SSE 消息长度。
  int bytes = 0;

  /// Most recent native call duration, including FFI encoding. / 最新原生调用耗时，含 FFI 编码。
  int nativeUs = 0;

  /// Most recent native duration before rounding to microseconds. / 舍入到微秒前的最近一次原生耗时。
  double nativePreciseUs = 0;

  /// Most recent Dart decode duration. / 最新 Dart 解码耗时。
  int decodeUs = 0;

  /// Measures the original native call and codec without copying wire data. / 无拷贝测原生调用和原始解码器。
  @override
  S executeSync<S, E extends Object, W>(SyncTask<S, E, W> task) {
    final watch = Stopwatch()..start();
    final wire = task.callFfi();
    watch.stop();
    nativeUs = watch.elapsedMicroseconds;
    nativePreciseUs = watch.elapsedTicks * 1e6 / watch.frequency;
    try {
      bytes = wireSyncRust2DartSseAsUint8ListView(wire as WireSyncRust2DartSse)
          .lengthInBytes;
      watch.reset();
      watch.start();
      try {
        return task.codec.decodeWireSyncType(wire);
      } finally {
        decodeUs = watch.elapsedMicroseconds;
      }
    } finally {
      task.codec.freeWireSyncRust2Dart(
        wire,
        task.apiImpl.generalizedFrbRustBinding,
      );
    }
  }
}

/// Sums control-point boxes in units of the squared intrinsic long edge. / 累计各路径控制点包围盒面积，以固有长边的平方为单位。
double _pathBoxArea(SvgScene scene) {
  var area = 0.0;
  for (final path in scene.paths) {
    final points = path.points;
    if (points.isEmpty) continue;
    var left = points[0], right = left;
    var top = points[1], bottom = top;
    for (var i = 2; i < points.length; i += 2) {
      left = math.min(left, points[i]);
      right = math.max(right, points[i]);
      top = math.min(top, points[i + 1]);
      bottom = math.max(bottom, points[i + 1]);
    }
    area += (right - left) * (bottom - top);
  }
  final edge = math.max(scene.width, scene.height);
  return area / (edge * edge);
}

/// Parses one ordered corpus with an explicitly selected DLL. / 用指定 DLL 解析固定顺序的语料。
Future<void> main(List<String> args) async {
  final [dll, plan, output, ...options] = args;
  final quick = options.contains('--quick');
  final icons = options.contains('--mdi');
  final handler = _WireTiming();
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(dll),
    handler: handler,
  );
  for (var i = 0; i < 100; i++) {
    parseSvg(
      data: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24"/></svg>',
    );
  }
  if (icons) {
    // One fixed, seeded sample without replacement. / 用同一个固定种子无放回抽样一次。
    final indices = List.generate(mdiIcons1000.length, (index) => index)
      ..shuffle(math.Random(20261127));
    final rows = [
      for (final index in indices.take(50))
        {
          'id': 'mdi-$index',
          'paths': parseSvg(data: mdiIcons1000[index]).paths.length,
          'native_us': handler.nativePreciseUs,
          'bytes': handler.bytes,
        },
    ];
    File(output).writeAsStringSync(jsonEncode(rows));
    return;
  }
  final rows = (jsonDecode(File(plan).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final sink = File(output).openWrite();
  try {
    for (final row in rows) {
      final input = File(row['path'] as String).readAsBytesSync();
      final latin = latin1
          .decode(input.take(120).toList())
          .toLowerCase()
          .split('?>')
          .first
          .contains('iso-8859-1');
      final samples = <Map<String, Object?>>[];
      try {
        final source = latin ? latin1.decode(input) : utf8.decode(input);
        for (var run = 0; run < (quick ? 1 : 3); run++) {
          final scene = parseSvg(data: source);
          samples.add({
            'paths': scene.paths.length,
            if (quick) ...{
              'points': scene.paths.fold<int>(
                0,
                (sum, path) => sum + path.points.length ~/ 2,
              ),
              if (row['id'] == 'web-543' || row['id'] == 'web-481')
                'path_box_area': _pathBoxArea(scene),
            } else ...{
              'commands':
                  scene.displayList?.commands.length ??
                  scene.paths.length + scene.images.length,
              'wire_commands': scene.displayList?.commands.length ?? 0,
              'bytes': handler.bytes,
              'native_us': handler.nativeUs,
              'decode_us': handler.decodeUs,
            },
          });
        }
      } catch (error) {
        samples.add({'error': error.runtimeType.toString()});
      }
      sink.writeln(jsonEncode({'id': row['id'], 'samples': samples}));
    }
  } finally {
    await sink.close();
  }
}
