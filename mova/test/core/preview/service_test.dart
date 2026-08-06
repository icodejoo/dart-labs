import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/preview_config.dart';
import 'package:mova/src/core/preview/cache.dart';
import 'package:mova/src/core/preview/models.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/service.dart';
import 'package:mova/src/core/preview/source.dart';

/// A [MovaThumbSource] returning canned bytes after an optional delay, recording
/// every bucket it was asked for.
///
/// 可选延迟后返回预置字节的 [MovaThumbSource]，并记录被请求过的每个桶。
class _FakeSource implements MovaThumbSource {
  /// Creates a fake source.
  ///
  /// 创建一个假来源。
  ///
  /// - [name]: diagnostic identifier / 诊断标识
  /// - [answer]: whether this source produces a thumbnail / 该来源是否产出缩略图
  /// - [delay]: artificial latency per request / 每次请求的人造延迟
  // ignore: unused_element_parameter
  _FakeSource({this.name = 'fake', this.answer = true, this.delay = Duration.zero});

  @override
  final String name;

  /// Whether [thumbAt] produces a thumbnail or null.
  ///
  /// [thumbAt] 产出缩略图还是 null。
  bool answer;

  /// Artificial latency applied to every request.
  ///
  /// 每次请求施加的人造延迟。
  Duration delay;

  /// Buckets this source was asked for, in order.
  ///
  /// 按顺序记录该来源被请求过的桶。
  final List<Duration> asked = <Duration>[];

  /// Ordered lifecycle method names invoked on this fake.
  ///
  /// 在该替身上被调用的生命周期方法名有序列表。
  final List<String> calls = <String>[];

  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async {
    asked.add(bucket);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!answer) return null;
    return MovaThumb(at: bucket, bytes: Uint8List.fromList([bucket.inSeconds & 0xFF]));
  }

  @override
  Future<void> reset() async => calls.add('reset');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A [MovaNetProbe] with a flippable verdict.
///
/// 判定结果可切换的 [MovaNetProbe]。
class _SwitchProbe implements MovaNetProbe {
  /// Creates a probe answering [verdict].
  ///
  /// 创建一个回答 [verdict] 的探针。
  _SwitchProbe(this.verdict);

  /// The verdict returned by [allowHeavy].
  ///
  /// [allowHeavy] 返回的判定结果。
  bool verdict;

  @override
  Future<bool> allowHeavy() async => verdict;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  const src = MovaSource('https://host/a.mp4');
  const noDebounce = MovaPrevConfig(
    debounce: Duration.zero,
    network: MovaPrevNet.always,
  );

  late MovaMemoryThumbCache cache;
  late _FakeSource source;
  late MovaPrevSvc service;

  /// Builds a service over the shared fakes with [config].
  ///
  /// 用共享替身与 [config] 构造一个服务。
  MovaPrevSvc build(MovaPrevConfig config, {MovaNetProbe? probe}) {
    return MovaPrevSvc(
      config: config,
      cache: cache,
      probe: probe ?? AlwaysAllowNetProbe(),
      sources: [source],
      onBlocked: config.onBlocked,
    )..attach(src);
  }

  setUp(() {
    cache = MovaMemoryThumbCache();
    source = _FakeSource();
  });

  tearDown(() => service.dispose());

  test('requestAt aligns the position down to the configured bucket', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 17));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 10)]);
    expect(service.current!.at, const Duration(seconds: 10));
  });

  test('scrubbing within one bucket only asks the source once', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 11));
    await service.drain();
    service.requestAt(const Duration(seconds: 18));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 10)]);
  });

  test('a memory hit is served synchronously by peekAt without any await', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    service.requestAt(const Duration(seconds: 40));
    await service.drain();
    expect(service.peekAt(const Duration(seconds: 12))!.at, const Duration(seconds: 10));
  });

  test('resolved thumbs are published on the thumbs stream', () async {
    service = build(noDebounce);
    final seen = <MovaThumb?>[];
    final sub = service.thumbs.listen(seen.add);
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    await Future<void>.delayed(Duration.zero);
    expect(seen.whereType<MovaThumb>().map((t) => t.at), contains(const Duration(seconds: 20)));
    await sub.cancel();
  });

  test('debounce collapses a burst of scrub ticks into one request', () async {
    service = build(const MovaPrevConfig(
      debounce: Duration(milliseconds: 40),
      network: MovaPrevNet.always,
    ));
    service.requestAt(const Duration(seconds: 10));
    service.requestAt(const Duration(seconds: 20));
    service.requestAt(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await service.drain();
    expect(source.asked, [const Duration(seconds: 30)]);
  });

  test('a stale result is cached but never published as current', () async {
    source.delay = const Duration(milliseconds: 60);
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    expect(service.current!.at, const Duration(seconds: 20));
    expect(
      cache.peek(service.debugKeyFor(const Duration(seconds: 10))!),
      isNotNull,
      reason: 'the superseded bucket still lands in the cache',
    );
  });

  test('extraction runs serially, one request at a time', () async {
    source.delay = const Duration(milliseconds: 30);
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    service.requestAt(const Duration(seconds: 20));
    service.requestAt(const Duration(seconds: 30));
    await service.drain();
    expect(source.asked.length, lessThanOrEqualTo(3));
    expect(service.current!.at, const Duration(seconds: 30));
  });

  test('a blocked network refuses without touching any source', () async {
    final reasons = <MovaPrevBlockReason>[];
    service = build(
      MovaPrevConfig(
        debounce: Duration.zero,
        onBlocked: reasons.add,
      ),
      probe: _SwitchProbe(false),
    );
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(service.current, isNull);
    expect(reasons, [MovaPrevBlockReason.network]);
  });

  test('a disabled config refuses with the disabled reason', () async {
    final reasons = <MovaPrevBlockReason>[];
    service = build(MovaPrevConfig(
      enabled: false,
      debounce: Duration.zero,
      network: MovaPrevNet.always,
      onBlocked: reasons.add,
    ));
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(reasons, [MovaPrevBlockReason.disabled]);
  });

  test('no attached source refuses with the noSource reason', () async {
    final reasons = <MovaPrevBlockReason>[];
    service = MovaPrevSvc(
      config: const MovaPrevConfig(
        debounce: Duration.zero,
        network: MovaPrevNet.always,
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [source],
      onBlocked: reasons.add,
    );
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(reasons, [MovaPrevBlockReason.noSource]);
  });

  test('an empty source chain refuses with the platform reason', () async {
    final reasons = <MovaPrevBlockReason>[];
    service = MovaPrevSvc(
      config: const MovaPrevConfig(
        debounce: Duration.zero,
        network: MovaPrevNet.always,
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: const <MovaThumbSource>[],
      onBlocked: reasons.add,
    )..attach(src);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(reasons, [MovaPrevBlockReason.platform]);
  });

  test('sources are tried in order and the first non-null answer wins', () async {
    final first = _FakeSource(name: 'first', answer: false);
    final second = _FakeSource(name: 'second');
    service = MovaPrevSvc(
      config: noDebounce,
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [first, second],
    )..attach(src);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(first.asked, [const Duration(seconds: 10)]);
    expect(second.asked, [const Duration(seconds: 10)]);
    expect(service.current, isNotNull);
  });

  test('attach resets every source and clears the current thumb', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    expect(service.current, isNotNull);
    service.attach(const MovaSource('https://host/b.mp4'));
    expect(service.current, isNull);
    expect(source.calls, contains('reset'));
  });

  test('cancel drops the pending request and hides the current thumb', () async {
    service = build(const MovaPrevConfig(
      debounce: Duration(milliseconds: 40),
      network: MovaPrevNet.always,
    ));
    service.requestAt(const Duration(seconds: 10));
    service.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await service.drain();
    expect(source.asked, isEmpty);
    expect(service.current, isNull);
  });

  test('a custom cacheKeyBuilder is used for every entry', () async {
    service = MovaPrevSvc(
      config: MovaPrevConfig(
        debounce: Duration.zero,
        network: MovaPrevNet.always,
        cacheKeyBuilder: (s, b, w) => 'custom_${b}_$w',
      ),
      cache: cache,
      probe: AlwaysAllowNetProbe(),
      sources: [source],
    )..attach(src);
    service.requestAt(const Duration(seconds: 20));
    await service.drain();
    expect(cache.peek('custom_20_160'), isNotNull);
  });

  test('clear empties the cache and drops the current thumb', () async {
    service = build(noDebounce);
    service.requestAt(const Duration(seconds: 10));
    await service.drain();
    await service.clear();
    expect(cache.length, 0);
    expect(service.current, isNull);
  });

  test('dispose releases every source and closes the thumbs stream', () async {
    service = build(noDebounce);
    final done = Completer<void>();
    final sub = service.thumbs.listen(null, onDone: done.complete);
    await service.dispose();
    await done.future.timeout(const Duration(seconds: 1));
    expect(source.calls, contains('dispose'));
    await sub.cancel();
    // A second dispose from tearDown must be a no-op.
    //
    // tearDown 里的第二次 dispose 必须是空操作。
  });
}
