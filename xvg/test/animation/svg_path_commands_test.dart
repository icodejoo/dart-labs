import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_path_commands.dart';
import 'package:xvg/src/animation/svg_path_morph.dart';

/// Shared prefix for truncation cases. / 截断用例共用的完整前缀。
const _prefix = 'M10 20L30 40';

/// Keeps signed zero visible in assertions. / 让断言区分负零。
Uint8List _bits(List<double> values) =>
    Float64List.fromList(values).buffer.asUint8List();

void main() {
  test('normalizes every command while retaining endpoint arcs', () {
    final data = parseSvgPathCommands(
      'm10 20 1 2h3v4q1 2 3 4t5 6c1 2 3 4 5 6s7 8 9 10'
      'a5 8 30 01 10 12zl2 3',
    );
    expect(data.verbs, [
      PathVerb.move,
      PathVerb.line,
      PathVerb.line,
      PathVerb.line,
      PathVerb.quad,
      PathVerb.quad,
      PathVerb.cubic,
      PathVerb.cubic,
      PathVerb.arc,
      PathVerb.close,
      PathVerb.line,
    ]);
    expect(data.coords, [
      10,
      20,
      11,
      22,
      14,
      22,
      14,
      26,
      15,
      28,
      17,
      30,
      19,
      32,
      22,
      36,
      23,
      38,
      25,
      40,
      27,
      42,
      29,
      44,
      34,
      50,
      36,
      52,
      5,
      8,
      30,
      0,
      1,
      46,
      64,
      12,
      23,
    ]);
  });

  test(
    'empty input, leading bare numbers and close retain legacy semantics',
    () {
      for (final d in ['', ' ,\n', '1 2M3 4']) {
        final data = parseSvgPathCommands(d);
        expect(data.verbs, isEmpty);
        expect(data.coords, isEmpty);
      }
      final data = parseSvgPathCommands('l5 6zh2');
      expect(data.verbs, [PathVerb.line, PathVerb.close, PathVerb.line]);
      expect(data.coords, [5, 6, 2, 0]);
      expect(parseSvgPathCommands('Z').verbs, [PathVerb.close]);
    },
  );

  test('partial commands leave no verb or coordinate fragments', () {
    final prefix = parseSvgPathCommands(_prefix);
    for (final tail in [
      'M1',
      'L2',
      'H',
      'V',
      'C1 2 3 4 5',
      'S1 2 3',
      'Q1 2 3',
      'T1',
      'A5 8 30 01 10',
      'z1 2M3 4',
    ]) {
      final data = parseSvgPathCommands('$_prefix$tail');
      if (tail.startsWith('z')) {
        expect(data.verbs, [...prefix.verbs, PathVerb.close]);
      } else {
        expect(data.verbs, prefix.verbs);
      }
      expect(data.coords, prefix.coords);
    }
  });

  test('absolute signed zero and raw nonboolean arc flags are preserved', () {
    final zero = parseSvgPathCommands('M-0 -0L-0 -0');
    expect(zero.coords.buffer.asUint8List(), _bits([-0.0, -0.0, -0.0, -0.0]));
    final arc = parseSvgPathCommands('A5 8 30 -2 3 10 12');
    expect(arc.verbs, [PathVerb.arc]);
    expect(arc.coords, [5, 8, 30, -2, 3, 10, 12]);
  });

  test('smooth reflection resets after unrelated commands and close', () {
    final data = parseSvgPathCommands('M1 2Q3 4 5 6L7 8T9 10zS2 3 4 5');
    expect(data.coords, [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      7,
      8,
      9,
      10,
      1,
      2,
      2,
      3,
      4,
      5,
    ]);
  });

  test('typed buffers are read-only including their buffer views', () {
    final data = parseSvgPathCommands(_prefix);
    expect(data.verbs, isA<Uint8List>());
    expect(data.coords, isA<Float64List>());
    expect(() => data.verbs[0] = PathVerb.close, throwsUnsupportedError);
    expect(() => data.coords[0] = 0, throwsUnsupportedError);
    expect(
      () => data.coords.buffer.asUint8List()[0] = 0,
      throwsUnsupportedError,
    );
  });

  test(
    'pure data can be parsed in and returned from a background isolate',
    () async {
      final data = await Isolate.run(() => parseSvgPathCommands(_prefix));
      expect(data.verbs, [PathVerb.move, PathVerb.line]);
      expect(data.coords, [10, 20, 30, 40]);
    },
  );

  test('morph keeps its distinct rejection and signed-zero normalization', () {
    const signedZero = 'M-0 -0L-0 -0';
    final morph = buildPathMorphData([signedZero, signedZero])!;
    expect(
      morph.frames.first.buffer.asUint8List(),
      _bits([0.0, 0.0, 0.0, 0.0]),
    );
    for (final d in ['', '$_prefix L1', '${_prefix}z1 2']) {
      expect(buildPathMorphData([d, d]), isNull);
    }
    expect(parseSvgPathCommands('$_prefix L1').verbs, [
      PathVerb.move,
      PathVerb.line,
    ]);
  });
}
