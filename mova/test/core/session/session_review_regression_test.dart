import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';

import '../../support/fake_api.dart';
import '../cutover/cutover_operation_test.dart' show settleOperations;

const _content = MovaSource('https://host/content.mp4');
const _host = MovaSource('https://host/host.mp4');
const _pre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre.mp4'),
  duration: Duration(seconds: 2),
);

/// Covers host takeover, deferred intent and throwing ad callbacks.
///
/// 覆盖宿主抢源、延迟解析期间的播放意图和广告回调异常。
void main() {
  test('C5 started callback disposal prevents the ad open', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    late MovaSession session;
    Future<void>? disposing;
    session = MovaSession(
      api,
      ads: MovaAdOpts(
        enabled: true,
        breaks: [_pre],
        onAdEvent: (event) {
          if (event.type == MovaAdEventType.started) disposing = session.dispose();
        },
      ),
    );
    await session.load(_content);
    await disposing;
    expect(api.openCalls, 0);
  });

  for (final kind in ['pre', 'mid', 'content']) {
    test('C2 host takeover during $kind yields without reopening content', () {
      fakeAsync((clock) {
        final kernel = MovaTestKernel.scripted();
        final api = Mova(kernel: kernel);
        final session = MovaSession(
          api,
          ads: MovaAdOpts(enabled: true, breaks: kind == 'pre' ? [_pre] : []),
        );
        final events = <MovaSessionEvent>[];
        final ended = <void>[];
        session.events.listen(events.add);
        session.contentEnded.listen(ended.add);
        session.load(_content);
        clock.flushMicrotasks();
        if (kind == 'mid') {
          session.playAdNow(
            const MovaAdBreak(
              kind: MovaAdBreakKind.mid,
              source: MovaSource('https://host/mid.mp4'),
              duration: Duration(seconds: 2),
            ),
          );
          clock.flushMicrotasks();
        }
        expect(
          session.cursor.phase,
          kind == 'content' ? MovaSessionPhase.content : MovaSessionPhase.ad,
        );
        api.open(_host);
        clock.flushMicrotasks();
        final opens = kernel.calls.where((c) => c == 'open').length;
        expect(session.cursor.phase, MovaSessionPhase.idle);
        clock.elapse(const Duration(seconds: 5));
        kernel.emitCompleted(true);
        clock.flushMicrotasks();
        expect(kernel.lastUri, _host.uri);
        expect(kernel.calls.where((c) => c == 'open'), hasLength(opens));
        expect(
          events.whereType<MovaNodeEnd>().where(
            (e) => e.reason == MovaNodeEndReason.superseded,
          ),
          hasLength(1),
        );
        expect(events.whereType<MovaNodeFail>(), isEmpty);
        expect(ended, isEmpty);
        session.dispose();
        clock.flushMicrotasks();
        api.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test(
    'C2 takeover while deferred content resolves invalidates the resolver',
    () async {
      final kernel = MovaTestKernel.scripted();
      final api = Mova(kernel: kernel);
      final session = MovaSession(
        api,
        ads: const MovaAdOpts(enabled: true, breaks: [_pre]),
      );
      addTearDown(() async {
        await session.dispose();
        await api.dispose();
      });
      final resolved = Completer<MovaSource>();
      await session.loadDeferred(() => resolved.future);
      kernel.emitCompleted(true);
      await settleOperations();
      expect(session.cursor.phase, MovaSessionPhase.toContent);
      await api.open(_host);
      resolved.complete(_content);
      await settleOperations();
      expect(kernel.lastUri, _host.uri);
      expect(session.cursor.phase, MovaSessionPhase.idle);
    },
  );

  for (final play in [false, true]) {
    test(
      'C7 deferred content honors latest playback command play=$play',
      () async {
        final api = FakeMovaApi();
        final session = MovaSession(
          api,
          ads: const MovaAdOpts(enabled: true, breaks: [_pre]),
        );
        addTearDown(() async {
          await session.dispose();
          await api.dispose();
        });
        final resolved = Completer<MovaSource>();
        await session.loadDeferred(() => resolved.future);
        if (play) await api.pause();
        api.emitDone();
        await settleOperations();
        expect(session.cursor.phase, MovaSessionPhase.toContent);
        if (play) {
          await api.play();
        } else {
          await api.pause();
        }
        resolved.complete(_content);
        await settleOperations();
        expect(api.source, _content);
        expect(api.lastAutoPlay, play);
        expect(api.state.playbackIntent, play);
      },
    );
  }

  // Reports callback errors and stacks to the host zone while playback continues.
  //
  // 回调错误和堆栈交给宿主 Zone，广告串播与正片续播照常完成。
  test(
    'C8 throwing ad callbacks reach the host zone without blocking pod or content resume',
    () async {
      final reportedErrors = <Object>[];
      final reportedStacks = <StackTrace>[];
      final hostZone = runZonedGuarded(() => Zone.current, (error, stack) {
        reportedErrors.add(error);
        reportedStacks.add(stack);
      })!;
      final api = hostZone.run(() => FakeMovaApi());
      final seen = <MovaAdEventType>[];
      final callbackError = StateError('host callback');
      final callbackStack = StackTrace.current;
      final session = hostZone.run(
        () => MovaSession(
          api,
          ads: MovaAdOpts(
            enabled: true,
            breaks: const [
              _pre,
              MovaAdBreak(
                kind: MovaAdBreakKind.pre,
                source: MovaSource('https://host/pre2.mp4'),
              ),
            ],
            onAdEvent: (event) {
              seen.add(event.type);
              Error.throwWithStackTrace(callbackError, callbackStack);
            },
          ),
        ),
      );
      addTearDown(() async {
        await session.dispose();
        await api.dispose();
      });
      final errors = <Object>[];
      session.contentError.listen(errors.add);
      expect(
        await hostZone.run(() => session.load(_content)),
        MovaLoadOutcome.accepted,
      );
      hostZone.run(api.emitDone);
      await settleOperations();
      expect(api.source?.uri, 'https://host/pre2.mp4');
      hostZone.run(api.emitDone);
      await settleOperations();
      expect(api.source, _content);
      expect(session.cursor.phase, MovaSessionPhase.content);
      expect(api.state.playbackIntent, isTrue);
      expect(seen.where((e) => e == MovaAdEventType.completed), hasLength(2));
      expect(seen.where((e) => e == MovaAdEventType.started), hasLength(2));
      expect(reportedErrors, hasLength(seen.length));
      expect(reportedErrors, everyElement(same(callbackError)));
      expect(reportedStacks, hasLength(seen.length));
      expect(reportedStacks, everyElement(same(callbackStack)));
      expect(errors, isEmpty);
      expect(api.state.error, isNull);
    },
  );
}
