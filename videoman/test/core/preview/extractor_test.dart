import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/preview/extractor.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';

/// A [VmFrameExtractor] returning canned bytes and recording its arguments.
///
/// 返回预置字节并记录调用参数的 [VmFrameExtractor]。
class _FakeExtractor implements VmFrameExtractor {
  /// Bytes returned by [extract]; null makes extraction "fail".
  ///
  /// [extract] 返回的字节；为 null 表示抽帧"失败"。
  Uint8List? result = Uint8List.fromList([42]);

  /// Ordered method names invoked on this fake.
  ///
  /// 在该替身上被调用的方法名有序列表。
  final List<String> calls = <String>[];

  /// The `uri` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `uri`。
  String? lastUri;

  /// The `at` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `at`。
  Duration? lastAt;

  /// The `width` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `width`。
  int? lastWidth;

  /// The `hwdec` of the most recent [extract] call.
  ///
  /// 最近一次 [extract] 调用的 `hwdec`。
  bool? lastHwdec;

  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async {
    calls.add('extract');
    lastUri = uri;
    lastAt = at;
    lastWidth = width;
    lastHwdec = hwdec;
    return result;
  }

  @override
  Future<void> release() async => calls.add('release');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  const src = VmSource('https://host/a.mp4');

  test('the source reports a stable name for diagnostics', () {
    expect(VmExtractorThumbSource(extractor: _FakeExtractor()).name, 'extract');
  });

  test('thumbAt forwards uri, bucket, width and hwdec to the extractor', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e, width: 320, hwdec: true);
    final t = await s.thumbAt(src, const Duration(seconds: 30));
    expect(e.lastUri, 'https://host/a.mp4');
    expect(e.lastAt, const Duration(seconds: 30));
    expect(e.lastWidth, 320);
    expect(e.lastHwdec, isTrue);
    expect(t!.at, const Duration(seconds: 30));
    expect(t.bytes, [42]);
    expect(t.crop, isNull, reason: 'an extracted frame is always the whole image');
    await s.dispose();
  });

  test('defaults are 160px and software decoding', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e);
    await s.thumbAt(src, Duration.zero);
    expect(e.lastWidth, 160);
    expect(e.lastHwdec, isFalse);
    await s.dispose();
  });

  test('a failed extraction yields null and is retried on the next scrub', () async {
    final e = _FakeExtractor()..result = null;
    final s = VmExtractorThumbSource(extractor: e);
    expect(await s.thumbAt(src, Duration.zero), isNull);
    e.result = Uint8List.fromList([7]);
    expect((await s.thumbAt(src, Duration.zero))!.bytes, [7]);
    await s.dispose();
  });

  test('reset releases the extractor without disposing it', () async {
    final e = _FakeExtractor();
    final s = VmExtractorThumbSource(extractor: e);
    await s.reset();
    expect(e.calls, ['release']);
    await s.dispose();
    expect(e.calls, ['release', 'dispose']);
  });

  test('currentPlatformKind reports one of the known kinds', () {
    expect(VmPlatformKind.values, contains(currentPlatformKind()));
  });
}
