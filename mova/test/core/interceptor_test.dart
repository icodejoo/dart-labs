import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

import '../support/fake_kernel.dart';

/// The address every engine-level case opens.
///
/// 引擎层用例统一打开的地址。
const _uri = 'https://host/a.m3u8';

/// A hook that records every error and optionally throws from `onError`.
///
/// 记录所有错误、并可选地在 `onError` 里抛异常的钩子。
class _ErrorHook extends MovaHook {
  /// Creates the hook; [throwing] makes its `onError` blow up after recording.
  ///
  /// 创建钩子；[throwing] 为真时 `onError` 记录后抛异常。
  _ErrorHook({this.throwing = false});

  /// Whether `onError` throws.
  ///
  /// `onError` 是否抛异常。
  final bool throwing;

  /// Errors received so far.
  ///
  /// 目前收到的错误。
  final List<Object> errors = <Object>[];

  @override
  void onError(Object error, StackTrace stack) {
    errors.add(error);
    if (throwing) throw StateError('hook bug');
  }
}

/// A hook that vetoes (or not) `beforePlay` and records that it was asked.
///
/// 对 `beforePlay` 否决（或放行）并记录自己被问过的钩子。
class _PlayHook extends MovaHook {
  /// Creates the hook with its [answer].
  ///
  /// 以 [answer] 创建钩子。
  _PlayHook(this.answer);

  /// What `beforePlay` returns.
  ///
  /// `beforePlay` 的返回值。
  final bool answer;

  /// How many times `beforePlay` ran.
  ///
  /// `beforePlay` 被调用的次数。
  int asked = 0;

  @override
  Future<bool> beforePlay() async {
    asked++;
    return answer;
  }
}

/// A hook whose async `before*` methods throw.
///
/// `before*` 异步方法会抛异常的钩子。
class _ThrowingBeforeHook extends MovaHook {
  @override
  Future<bool> beforeOpen(MovaSource source) async => throw StateError('open hook bug');

  @override
  Future<bool> beforePlay() async => throw StateError('play hook bug');

  @override
  Future<Duration?> beforeSeek(Duration target) async => throw StateError('seek hook bug');
}

class _DenyOpen extends MovaHook {
  @override
  Future<bool> beforeOpen(MovaSource s) async => false;
}

class _ClampSeek extends MovaHook {
  @override
  Future<Duration?> beforeSeek(Duration t) async =>
      t > const Duration(seconds: 10) ? const Duration(seconds: 10) : t;
}

class _CancelSeek extends MovaHook {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

/// Test-only interceptor that records whether it was invoked, via [onReached].
///
/// Used to prove that a preceding interceptor returning `null` from
/// `beforeSeek` actually stops the chain, rather than merely asserting an
/// untouched flag.
///
/// 仅用于测试的拦截器，通过 [onReached] 记录自身是否被调用过。
///
/// 用于证明前一个拦截器的 `beforeSeek` 返回 `null` 确实会终止链条的继续执行，
/// 而不是仅仅断言一个从未被改动过的标志位。
class _ReachedSeek extends MovaHook {
  /// Creates the interceptor, invoking [onReached] if [beforeSeek] runs.
  ///
  /// 创建该拦截器；若 [beforeSeek] 被执行，则调用 [onReached]。
  _ReachedSeek(this.onReached);

  /// Callback invoked when [beforeSeek] actually runs.
  ///
  /// [beforeSeek] 实际被执行时调用的回调。
  final void Function() onReached;

  @override
  Future<Duration?> beforeSeek(Duration t) async {
    onReached();
    return t;
  }
}

void main() {
  test('empty chain allows everything', () async {
    final c = MovaHookChain(const []);
    expect(await c.beforeOpen(const MovaSource('u')), isTrue);
    expect(await c.beforePlay(), isTrue);
    expect(await c.beforeSeek(const Duration(seconds: 3)), const Duration(seconds: 3));
  });

  test('a denying interceptor short-circuits beforeOpen', () async {
    final c = MovaHookChain([_DenyOpen()]);
    expect(await c.beforeOpen(const MovaSource('u')), isFalse);
  });

  test('beforeSeek rewrites are threaded through the chain', () async {
    final c = MovaHookChain([_ClampSeek()]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), const Duration(seconds: 10));
  });

  test('a null from beforeSeek cancels and stops the chain', () async {
    var reached = false;
    final c = MovaHookChain([
      _CancelSeek(),
      _ReachedSeek(() => reached = true),
    ]);
    expect(await c.beforeSeek(const Duration(seconds: 30)), isNull);
    expect(reached, isFalse);
  });

  group('MovaHookChain.beforePlay', () {
    test('all true lets playback through and asks every hook', () async {
      final a = _PlayHook(true);
      final b = _PlayHook(true);
      expect(await MovaHookChain([a, b]).beforePlay(), isTrue);
      expect((a.asked, b.asked), (1, 1));
    });

    test('the first false vetoes and the later hooks are never asked', () async {
      final a = _PlayHook(false);
      final b = _PlayHook(true);
      expect(await MovaHookChain([a, b]).beforePlay(), isFalse);
      expect((a.asked, b.asked), (1, 0));
    });

    test('a veto later in the chain still vetoes after earlier approvals', () async {
      final a = _PlayHook(true);
      final b = _PlayHook(false);
      expect(await MovaHookChain([a, b]).beforePlay(), isFalse);
      expect((a.asked, b.asked), (1, 1));
    });
  });

  group('MovaHookChain.onError', () {
    test('every hook is told the error and the stack', () {
      final a = _ErrorHook();
      final b = _ErrorHook();
      final stack = StackTrace.current;
      MovaHookChain([a, b]).onError('boom', stack);
      expect(a.errors, ['boom']);
      expect(b.errors, ['boom']);
    });

    test('a throwing hook does not stop the ones after it', () {
      final bad = _ErrorHook(throwing: true);
      final good = _ErrorHook();
      expect(() => MovaHookChain([bad, good]).onError('boom', StackTrace.current), returnsNormally);
      expect(bad.errors, ['boom']);
      expect(good.errors, ['boom']);
    });
  });

  group('engine → hooks.onError', () {
    test('a kernel error reaches every hook, throwing one included, and still lands in state', () async {
      final k = FakeKernel();
      final bad = _ErrorHook(throwing: true);
      final good = _ErrorHook();
      final e = MovaEngine(kernel: k, interceptors: [bad, good]);
      k.emitError('boom');
      await Future<void>.delayed(Duration.zero);
      expect(bad.errors, ['boom']);
      expect(good.errors, ['boom']);
      expect(e.state.error, 'boom');
      await e.dispose();
    });

    test('exhausted recovery tells the hooks with a MovaGiveUpError', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final hook = _ErrorHook();
        final e = MovaEngine(
          kernel: k,
          interceptors: [hook],
          options: const MovaOpts(
            recovery: MovaRecoveryConfig(
              enabled: true,
              startTimeout: Duration(seconds: 10),
              stallTimeout: Duration(seconds: 10),
            ),
            controls: MovaCtrlsConfig(autoHide: false),
          ),
        );
        e.open(const MovaSource(_uri));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 25));
        async.flushMicrotasks();
        expect(hook.errors.whereType<MovaGiveUpError>(), hasLength(1));
        expect(e.state.error, isA<MovaGiveUpError>());
      });
    });
  });

  group('engine ← a hook that throws from before*', () {
    // Current contract: the host's exception surfaces to the caller of the verb
    // (it is not swallowed the way onError failures are), and the engine stays
    // usable for the next call.
    //
    // 现行契约：宿主钩子的异常会冒给该动词的调用方（不像 onError 那样被吞），
    // 引擎对下一次调用仍可用。
    test('beforePlay: play() throws to the caller and playbackIntent stays unchanged', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k, interceptors: [_ThrowingBeforeHook()]);
      final before = e.state.playbackIntent;
      await expectLater(e.play(), throwsA(isA<StateError>()));
      expect(e.state.playbackIntent, before);
      expect(k.calls, isNot(contains('play')));
      await e.dispose();
    });

    test('beforeSeek: seek() throws to the caller and nothing reaches the kernel', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k, interceptors: [_ThrowingBeforeHook()]);
      await expectLater(e.seek(const Duration(seconds: 5)), throwsA(isA<StateError>()));
      expect(k.calls, isNot(contains('seek')));
      await e.dispose();
    });

    test('beforeOpen: open() throws to the caller and no source is loaded', () async {
      final k = FakeKernel();
      final e = MovaEngine(kernel: k, interceptors: [_ThrowingBeforeHook()]);
      await expectLater(e.open(const MovaSource(_uri)), throwsA(isA<StateError>()));
      expect(k.openedUris, isEmpty);
      await e.dispose();
    });
  });
}
