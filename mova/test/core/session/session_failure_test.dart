import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';
import '../ads_open_failure_test.dart' show RecordingAdPolicy;
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, pre, sessionFor;
import 'playlist_session_test.dart' show fixture;

const giveUp = MovaPlayFailure(
  MovaPlayFail(
    kind: MovaPlayFailKind.nativeEndError,
    sourceIndex: 0,
    uri: 'https://host/pre.mp4',
    sourceCount: 1,
    attempt: 1,
    streak: 1,
    error: 'give up',
  ),
  MovaRecoveryAction.giveUp,
);

class TerminalOpenApi extends FakeMovaApi {
  TerminalOpenApi() : super(options: const MovaOpts(recovery: MovaRecoveryConfig(enabled: true)));
  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    final accepted = await super.open(source, autoPlay: autoPlay);
    pushEvent(MovaPlayFailure(MovaPlayFail(
      kind: MovaPlayFailKind.openThrew, sourceIndex: 0, uri: source.uri,
      sourceCount: 1, attempt: 1, streak: 1, error: 'initial failure',
    ), MovaRecoveryAction.giveUp));
    pushEvent(MovaErrorEvent.classified('duplicate', fatal: true, source: source));
    await settleOperations();
    return accepted;
  }
}

void main() {
  test('落地窗口 giveUp 在 open 正常返回前到达仍结算正片失败', () async {
    final api = TerminalOpenApi();
    final session = sessionFor(api);
    final errors = <Object>[];
    final failures = <MovaNodeFail>[];
    session.contentError.listen(errors.add);
    session.events.listen((e) { if (e is MovaNodeFail) failures.add(e); });
    expect(await session.load(a), MovaLoadOutcome.failed);
    await settleOperations();
    expect(errors, hasLength(1));
    expect(failures.single.verdict, MovaNodeFailVerdict.failItem);
    expect(session.cursor.phase, MovaSessionPhase.idle);
  });

  test('落地窗口真实引擎首次加载 giveUp 正常返回仍结算正片失败', () async {
    final kernel = FakeKernel()..openError = StateError('initial load');
    final api = createMovaEngine(
      kernel: kernel, brightness: MovaFallbackBrightnessPort(),
      pip: MovaNoopPipPort(), orientation: MovaNoopOrientationPort(),
      options: const MovaOpts(
        controls: MovaCtrlsConfig(autoHide: false),
        abr: MovaAbrConfig(probeVariants: false),
        recovery: MovaRecoveryConfig(enabled: true, policy: MovaRetryThenFailover(maxRetries: 0)),
      ),
    );
    final session = MovaSession(api);
    addTearDown(() async { await session.dispose(); await api.dispose(); });
    final errors = <Object>[];
    final failures = <MovaNodeFail>[];
    session.contentError.listen(errors.add);
    session.events.listen((e) { if (e is MovaNodeFail) failures.add(e); });
    expect(await session.load(a), MovaLoadOutcome.accepted);
    await settleOperations();
    expect(errors, hasLength(1));
    expect(failures.single.verdict, MovaNodeFailVerdict.failItem);
    expect(session.cursor.phase, MovaSessionPhase.idle);
  });

  test('同一广告错误与超时及迟到 open 抛出只裁决一次', () {
    fakeAsync((clock) {
      final policy = RecordingAdPolicy();
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(
            enabled: true,
            breaks: const [pre],
            failPolicy: policy,
          ),
        ),
      );
      final session = MovaSession(api);
      final events = <MovaSessionEvent>[];
      session.events.listen(events.add);
      unawaited(session.load(a));
      clock.flushMicrotasks();
      Timer(
        const Duration(seconds: 8),
        () => api.pushEvent(const MovaErrorEvent('late')),
      );
      clock.elapse(const Duration(seconds: 8));
      clock.flushMicrotasks();
      expect(
        events.whereType<MovaNodeFail>().where(
          (e) => e.node.kind == MovaNodeKind.pre,
        ),
        hasLength(1),
      );
      expect(policy.failures, hasLength(1));
      // open 尚未完成时可同时到错误并在放行后抛出；加载期限尚未武装。
      final gate = Completer<void>();
      api.openGate = gate;
      api.openThrows = StateError('open');
      api.openThrowsFor = pre.source.uri;
      unawaited(session.load(b));
      clock.flushMicrotasks();
      api.pushEvent(const MovaErrorEvent('player'));
      clock.flushMicrotasks();
      gate.complete();
      clock.flushMicrotasks();
      expect(policy.failures, hasLength(2));
      expect(
        events.whereType<MovaNodeFail>().where(
          (e) => e.node.kind == MovaNodeKind.pre,
        ),
        hasLength(2),
      );
      unawaited(session.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });
  test('恢复开时广告诊断不失败，giveUp 仅裁决一次', () async {
    final policy = RecordingAdPolicy();
    final api = FakeMovaApi(
      options: MovaOpts(
        recovery: const MovaRecoveryConfig(enabled: true),
        ads: MovaAdConfig(
          enabled: true,
          breaks: const [pre],
          failPolicy: policy,
        ),
      ),
    );
    final session = sessionFor(api);
    final failures = <MovaNodeFail>[];
    session.events.listen((e) {
      if (e is MovaNodeFail) failures.add(e);
    });
    await session.load(a);
    api.pushEvent(const MovaErrorEvent.classified('diagnostic', fatal: false));
    await settleOperations();
    expect(policy.failures, isEmpty);
    api.pushEvent(giveUp);
    api.pushEvent(const MovaErrorEvent('terminal duplicate'));
    await settleOperations();
    expect(policy.failures, hasLength(1));
    expect(
      failures.where((e) => e.node.kind == MovaNodeKind.pre),
      hasLength(1),
    );
  });
  test('恢复开时广告加载超时由会话裁决并续播正片', () {
    fakeAsync((clock) {
      final api = FakeMovaApi(
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(enabled: true),
          ads: MovaAdConfig(enabled: true, breaks: [pre]),
        ),
      );
      final session = MovaSession(api);
      final failures = <MovaNodeFail>[];
      session.events.listen((e) {
        if (e is MovaNodeFail) failures.add(e);
      });
      unawaited(session.load(a));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 8));
      clock.flushMicrotasks();
      expect(failures.single.verdict, MovaNodeFailVerdict.skipNode);
      expect(api.source, a);
      expect(session.cursor.phase, MovaSessionPhase.content);
      unawaited(session.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });
  test('正片终结错误发失败与 contentError 后 idle，不发 contentEnded', () async {
    for (final recovery in [false, true]) {
      final api = FakeMovaApi(
        options: MovaOpts(recovery: MovaRecoveryConfig(enabled: recovery)),
      );
      final session = sessionFor(api);
      final errors = <Object>[];
      final failures = <MovaNodeFail>[];
      var ended = 0;
      session.contentError.listen(errors.add);
      session.contentEnded.listen((_) => ended++);
      session.events.listen((e) {
        if (e is MovaNodeFail) failures.add(e);
      });
      await session.load(a);
      api.pushEvent(const MovaErrorEvent('terminal'));
      await settleOperations();
      if (recovery) {
        expect(errors, isEmpty);
        expect(session.cursor.phase, MovaSessionPhase.content);
        api.pushEvent(giveUp);
        await settleOperations();
      }
      expect(errors, hasLength(1));
      expect(failures.single.verdict, MovaNodeFailVerdict.failItem);
      expect(session.cursor.phase, MovaSessionPhase.idle);
      expect(ended, 0);
    }
  });
  test('播放列表正片失败默认不自动下一集', () async {
    final f = fixture();
    final failures = <MovaNodeFail>[];
    f.ads.session.events.listen((e) {
      if (e is MovaNodeFail) failures.add(e);
    });
    await f.playlist.jumpTo(1);
    f.api.pushEvent(const MovaErrorEvent('terminal'));
    await settleOperations();
    expect(failures.single.node.item, 1);
    expect(f.ads.session.cursor.phase, MovaSessionPhase.idle);
    expect(f.playlist.currentIndex, 1);
    expect(f.api.openedUris, [b.uri]);
  });
  test('被拒与被取代不发节点失败，open 抛出与解析错误发失败', () async {
    final api = FakeMovaApi();
    final session = sessionFor(api);
    final failures = <MovaNodeFail>[];
    session.events.listen((e) {
      if (e is MovaNodeFail) failures.add(e);
    });
    api.acceptOpens = false;
    expect(await session.load(a), MovaLoadOutcome.rejected);
    api.acceptOpens = true;
    final gate = Completer<void>();
    api.openGate = gate;
    final old = session.load(a);
    await settleOperations();
    api.openGate = null;
    await session.load(b);
    gate.complete();
    expect(await old, MovaLoadOutcome.superseded);
    await settleOperations();
    expect(failures, isEmpty);
    api.openThrows = StateError('open');
    expect(await session.load(a), MovaLoadOutcome.failed);
    api.openThrows = null;
    expect(
      await session.loadDeferred(() async => throw StateError('resolve')),
      MovaLoadOutcome.failed,
    );
    await settleOperations();
    expect(failures, hasLength(2));
  });
}
