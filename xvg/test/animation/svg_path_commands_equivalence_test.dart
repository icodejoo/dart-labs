import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_path_data.dart';
import 'package:xml/xml.dart';

import 'legacy_path_data_oracle.dart';

/// Reproducible fuzz seed. / 可复现的随机种子。
const _seed = 20261105;

/// Boundary inputs including legacy tolerance. / 包含旧容错行为的边角输入。
const _edges = <String>[
  '',
  ' , \n',
  '0 1M2 3',
  'Z',
  'ZZz',
  'Z1 2M4 5',
  'L10 20',
  'h5v6',
  'q2 3 4 5t6 7',
  'c1 2 3 4 5 6s7 8 9 10',
  'a5 8 30 01-2 4',
  'M10 20z l3 4h5v6',
  'M10 20L30 40z1 2M5 6',
  'M1 2M3 4z m5 6 7 8',
  'M1 2 3 4 5 6',
  'm1 2 3 4 5 6',
  'M1 2L3 4 5',
  'M0 0C1 2 3 4 5 6S7 8 9 10s1 2 3 4',
  'M0 0Q1 2 3 4T5 6t7 8S9 10 11 12',
  'M0 0C1 2 3 4 5 6L1 2S3 4 5 6Q7 8 9 10zT3 4',
  'M0 0A10 10 0 0110 10 5 5 30 11-5 5z',
  'M2 3A-5 -8 30 -2 3 10 12',
  'M2 3A0 0 0 0110 12',
  'M2 3A5 8 30 01 2 3',
  'M2 3A5 8 30 01 10',
  'M.5.5L+1e1-2E-1',
  'M0 0L-',
  'M1e L2 2',
  'M. 5',
  'M--5 5',
  'M0 0e',
  'L+',
  'M0 0X2 3',
  'M0 0L1e 2 3 4',
  'M-0 -0L0 -0H-0V-0C-0 -0 -0 -0 -0 -0S-0 -0 -0 -0',
  'M0 0Q-0 -0 -0 -0T-0 -0A-0 -0 -0 -0 -0 -0 -0z',
  'M0 0L1e39 -1e39',
  'M0 0L1e999 0',
];

/// Captures all observed doubles as bytes, including signed zero/NaN bits.
/// 按字节记录观测值，保留负零及 NaN 位模式。
Uint8List _geometryBits(ui.Path path) {
  final values = <double>[];
  final bounds = path.getBounds();
  values.addAll([bounds.left, bounds.top, bounds.right, bounds.bottom]);
  final metrics = path.computeMetrics().toList();
  values.add(metrics.length.toDouble());
  for (final metric in metrics) {
    values.addAll([
      metric.contourIndex.toDouble(),
      metric.isClosed ? 1.0 : 0.0,
      metric.length,
    ]);
    for (final fraction in const [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0]) {
      final tangent = metric.getTangentForOffset(metric.length * fraction);
      values.add(tangent == null ? 0.0 : 1.0);
      if (tangent != null) {
        values.addAll([
          tangent.position.dx,
          tangent.position.dy,
          tangent.vector.dx,
          tangent.vector.dy,
          tangent.angle,
        ]);
      }
    }
  }
  return Float64List.fromList(values).buffer.asUint8List();
}

/// Compares the complete observable geometry with the frozen parser.
/// 与冻结解析器比较完整的可观测几何数据。
void _expectLegacy(String d) {
  expect(
    _geometryBits(parseSvgPathData(d)),
    orderedEquals(_geometryBits(legacyParseSvgPathData(d))),
    reason: d,
  );
}

/// Generates valid, repeated and truncated commands. / 生成有效、重复及截断命令。
Iterable<String> _randomPaths() sync* {
  final random = Random(_seed);
  const commands = 'MmLlHhVvCcSsQqTtAaZz';
  const arities = [2, 2, 2, 2, 1, 1, 1, 1, 6, 6, 4, 4, 4, 4, 2, 2, 7, 7, 0, 0];
  for (var n = 0; n < 1000; n++) {
    final text = StringBuffer();
    for (var k = 0; k < 16; k++) {
      final index = random.nextInt(commands.length);
      text.write(commands[index]);
      final count = arities[index] * (1 + random.nextInt(3));
      for (var j = 0; j < count; j++) {
        text.write(' ');
        if (index ~/ 2 == 8 && (j % 7 == 3 || j % 7 == 4)) {
          text.write(random.nextInt(2));
        } else {
          text.write((random.nextInt(2001) - 1000) / 8);
        }
      }
    }
    final d = text.toString();
    yield d;
    yield d.substring(0, random.nextInt(d.length + 1));
  }
  const alphabet = '${commands}0123456789.,- +eEX?';
  for (var n = 0; n < 2000; n++) {
    yield String.fromCharCodes(
      List.generate(
        random.nextInt(100),
        (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ),
    );
  }
}

/// Times parse + build after warmup, taking seven interleaved minima.
/// 预热后交错测量解析及构建，取七轮最小值。
void _benchmark() {
  final d =
      'M0 0${List.filled(800, 'l1 2q3 4 5 6t7 8c1 2 3 4 5 6s7 8 9 10a5 8 30 01 10 12z').join()}';
  const iterations = 30;
  const rounds = 7;
  final old = <int>[];
  final current = <int>[];
  var sink = 0.0;

  /// Measures one batch. / 测量一个批次。
  int measure(ui.Path Function(String) parse) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      sink += parse(d).getBounds().right;
    }
    return watch.elapsedMicroseconds;
  }

  for (var i = 0; i < 3; i++) {
    measure(legacyParseSvgPathData);
    measure(parseSvgPathData);
  }
  for (var i = 0; i < rounds; i++) {
    if (i.isEven) {
      old.add(measure(legacyParseSvgPathData));
      current.add(measure(parseSvgPathData));
    } else {
      current.add(measure(parseSvgPathData));
      old.add(measure(legacyParseSvgPathData));
    }
  }
  final a = old.reduce(min) / iterations;
  final b = current.reduce(min) / iterations;
  // Keep this diagnostic opt-in; timing is not a CI assertion.
  // 按需输出诊断数据，不把耗时作为 CI 断言。
  // ignore: avoid_print
  print(
    'path benchmark: chars=${d.length}, old=$a us, new=$b us, ratio=${b / a}, sink=$sink',
  );
}

void main() {
  test('legacy geometry is bit-identical for boundary inputs', () {
    for (final d in _edges) {
      _expectLegacy(d);
    }
    // Every truncation of every command, before and after an existing segment.
    // 在空路径和已有路径之后，逐字符截断所有命令。
    const groups = [
      'M1 2',
      'l3 4',
      'H5',
      'v6',
      'C1 2 3 4 5 6',
      's1 2 3 4',
      'Q1 2 3 4',
      't5 6',
      'A5 8 30 01 10 12',
      'Z',
    ];
    for (final group in groups) {
      for (var end = 0; end <= group.length; end++) {
        final fragment = group.substring(0, end);
        _expectLegacy(fragment);
        _expectLegacy('M10 20L30 40$fragment');
      }
    }
  });

  test('legacy geometry is bit-identical for seeded random inputs', () {
    for (final d in _randomPaths()) {
      _expectLegacy(d);
    }
  });

  final corpus = Platform.environment['XVG_CSS_SAMPLES'];
  test(
    'legacy geometry is bit-identical for every corpus d attribute',
    () {
      final files = Directory(corpus!)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.svg'))
          .toList();
      expect(files, hasLength(55));
      var count = 0;
      for (final file in files) {
        final document = XmlDocument.parse(file.readAsStringSync());
        for (final element in document.descendants.whereType<XmlElement>()) {
          final d = element.getAttribute('d');
          if (d == null) continue;
          _expectLegacy(d);
          count++;
        }
      }
      expect(count, greaterThan(0));
      // ignore: avoid_print
      print('corpus path attributes compared: $count');
    },
    skip: corpus == null
        ? 'Set XVG_CSS_SAMPLES to the external corpus.'
        : false,
  );

  test(
    'parse + build min-of-seven benchmark',
    _benchmark,
    skip: Platform.environment['XVG_PATH_BENCH'] != '1',
  );
}
