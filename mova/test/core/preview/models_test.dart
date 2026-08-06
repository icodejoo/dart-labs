import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/models.dart';

/// Builds a cue spanning `[from, to)` seconds pointing at `sprite.jpg`.
///
/// 构造一条覆盖 `[from, to)` 秒、指向 `sprite.jpg` 的 cue。
MovaThumbCue _cue(int from, int to, {MovaThumbCrop? crop}) => MovaThumbCue(
      start: Duration(seconds: from),
      end: Duration(seconds: to),
      image: Uri.parse('https://host/sprite.jpg'),
      crop: crop,
    );

void main() {
  test('MovaThumbCrop compares by value', () {
    expect(
      const MovaThumbCrop(x: 0, y: 0, w: 160, h: 90),
      const MovaThumbCrop(x: 0, y: 0, w: 160, h: 90),
    );
    expect(
      const MovaThumbCrop(x: 1, y: 0, w: 160, h: 90),
      isNot(const MovaThumbCrop(x: 0, y: 0, w: 160, h: 90)),
    );
  });

  test('MovaThumb carries its bucket position, bytes and optional crop', () {
    final t = MovaThumb(
      at: const Duration(seconds: 10),
      bytes: Uint8List.fromList([1, 2, 3]),
      crop: const MovaThumbCrop(x: 160, y: 0, w: 160, h: 90),
    );
    expect(t.at, const Duration(seconds: 10));
    expect(t.bytes, [1, 2, 3]);
    expect(t.crop!.x, 160);
  });

  test('MovaThumbIndex.cueAt finds the covering cue', () {
    final idx = MovaThumbIndex([_cue(0, 10), _cue(10, 20), _cue(20, 30)]);
    expect(idx.cueAt(const Duration(seconds: 0)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 9)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 10)), idx.cues[1]);
    expect(idx.cueAt(const Duration(seconds: 29, milliseconds: 999)), idx.cues[2]);
  });

  test('MovaThumbIndex.cueAt clamps below the first and above the last cue', () {
    final idx = MovaThumbIndex([_cue(5, 10), _cue(10, 20)]);
    expect(idx.cueAt(const Duration(seconds: 1)), idx.cues[0]);
    expect(idx.cueAt(const Duration(seconds: 999)), idx.cues[1]);
  });

  test('MovaThumbIndex.cueAt on an empty index returns null', () {
    const idx = MovaThumbIndex(<MovaThumbCue>[]);
    expect(idx.isEmpty, isTrue);
    expect(idx.cueAt(const Duration(seconds: 3)), isNull);
  });

  test('MovaThumbIndex.cueAt is a binary search over a large index', () {
    final cues = [for (var i = 0; i < 5000; i++) _cue(i * 10, i * 10 + 10)];
    final idx = MovaThumbIndex(cues);
    expect(idx.cueAt(const Duration(seconds: 49995)), cues[4999]);
    expect(idx.cueAt(const Duration(seconds: 25000)), cues[2500]);
  });
}
