import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/net_probe.dart';

/// A probe returning a fixed verdict, recording how often it was consulted.
///
/// 返回固定判定结果的探针，并记录被咨询了多少次。
class _FixedProbe implements MovaNetProbe {
  /// Creates a probe that always answers [verdict].
  ///
  /// 创建一个恒定回答 [verdict] 的探针。
  _FixedProbe(this.verdict);

  /// The verdict returned by [allowHeavy].
  ///
  /// [allowHeavy] 返回的判定结果。
  final bool verdict;

  /// How many times [allowHeavy] was called.
  ///
  /// [allowHeavy] 被调用的次数。
  int calls = 0;

  /// Backing controller for [changes].
  ///
  /// [changes] 的底层控制器。
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> allowHeavy() async {
    calls++;
    return verdict;
  }

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();
}

void main() {
  test('AlwaysAllowNetProbe permits heavy traffic and never errors', () async {
    final p = AlwaysAllowNetProbe();
    expect(await p.allowHeavy(), isTrue);
    expect(await p.changes.first, isTrue);
    await p.dispose();
  });

  test('the never policy blocks without consulting the probe', () async {
    final p = _FixedProbe(true);
    expect(await previewAllowedOn(MovaPrevNet.never, p), isFalse);
    expect(p.calls, 0);
    await p.dispose();
  });

  test('the always policy permits without consulting the probe', () async {
    final p = _FixedProbe(false);
    expect(await previewAllowedOn(MovaPrevNet.always, p), isTrue);
    expect(p.calls, 0);
    await p.dispose();
  });

  test('the wifiOnly policy defers to the probe', () async {
    final allow = _FixedProbe(true);
    final deny = _FixedProbe(false);
    expect(await previewAllowedOn(MovaPrevNet.wifiOnly, allow), isTrue);
    expect(await previewAllowedOn(MovaPrevNet.wifiOnly, deny), isFalse);
    expect(allow.calls, 1);
    expect(deny.calls, 1);
    await allow.dispose();
    await deny.dispose();
  });

  test('a throwing probe degrades to allowed rather than breaking playback', () async {
    expect(await previewAllowedOn(MovaPrevNet.wifiOnly, _ThrowingProbe()), isTrue);
  });
}

/// A probe whose [allowHeavy] always throws, standing in for a broken
/// connectivity plugin.
///
/// [allowHeavy] 恒抛异常的探针，用于模拟坏掉的连通性插件。
class _ThrowingProbe implements MovaNetProbe {
  @override
  Future<bool> allowHeavy() async => throw StateError('plugin missing');

  @override
  Stream<bool> get changes => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}
