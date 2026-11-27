import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
// ignore: implementation_imports
import 'package:xvg/src/rust/api/svg.dart';
// ignore: implementation_imports
import 'package:xvg/src/rust/frb_generated.dart';

import '../lib/raster_cache_auto_samples.dart';

/// 用 XML 声明识别语料里的 ISO-8859-1，其他文件保持 UTF-8。
({String source, bool latin1}) _readSvg(File file) {
  final bytes = file.readAsBytesSync();
  final header = latin1.decode(bytes.take(120).toList());
  final iso =
      header.startsWith('<?xml') &&
      header.split('?>').first.toLowerCase().contains('iso-8859-1');
  return (source: iso ? latin1.decode(bytes) : utf8.decode(bytes), latin1: iso);
}

/// 用显式 Windows DLL 解析主机清单中的每个静态 SVG。
Future<void> main(List<String> args) async {
  final [dllPath, input, output] = args;
  await RustLib.init(externalLibrary: ExternalLibrary.open(dllPath));
  final files = jsonDecode(File(input).readAsStringSync()) as List<dynamic>;
  final sink = File(output).openWrite();
  try {
    for (final row in files) {
      final entry = row as Map<String, dynamic>;
      final result = <String, Object?>{'id': entry['id']};
      final timer = Stopwatch()..start();
      try {
        final input = _readSvg(File(entry['path'] as String));
        if (input.latin1) result['source_encoding'] = 'iso-8859-1';
        final scene = parseSvg(data: input.source);
        result['features'] = autoR2Features(scene);
        result['status'] =
            (scene.paths.isEmpty && scene.images.isEmpty) ||
                scene.width <= 0 ||
                scene.height <= 0
            ? 'empty_scene'
            : 'ok';
      } catch (error) {
        result['status'] = autoR2Error(error);
        if (error is AnyhowException) {
          result['native_error'] = error.message;
        }
      }
      result['parse_and_scan_us'] = timer.elapsedMicroseconds;
      sink.writeln(jsonEncode(result));
      await sink.flush();
    }
  } finally {
    await sink.close();
  }
}
