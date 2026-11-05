import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mova/src/core/kernel/mpv_event_backend.dart';
import 'package:mova/src/core/kernel/mpv_event_pump.dart';
import '../../support/fake_mpv_event_backend.dart';

void main() {
  group('MovaMpvEventPump', () {
    late FakeMpvEventBackend backend;
    late int restartCount;
    late List<int> endFileReasons;

    setUp(() {
      backend = FakeMpvEventBackend();
      restartCount = 0;
      endFileReasons = [];
    });

    MovaMpvEventPump createPump({String name = 'mova_qoe_0'}) {
      return MovaMpvEventPump(
        backend,
        name: name,
        onRestart: () => restartCount++,
        onEndFile: (r) => endFileReasons.add(r),
      );
    }

    test('I0: 正常注册序列与 restrict 失败容错', () {
      fakeAsync((async) {
        final pump = createPump();
        backend.restrictFail = true; // 即使 restrict 失败也不影响后续步骤
        
        final readyCompleter = Completer<void>();
        pump.start(readyCompleter.future);
        async.flushMicrotasks();
        
        expect(backend.callLog, isEmpty);
        
        readyCompleter.complete();
        async.flushMicrotasks();
        
        expect(backend.callLog, [
          'createClient',
          'restrictEvents',
          'armWakeup',
        ]);
        expect(backend.createCount, 1);
      });
    });

    test('I2/I5: PLAYBACK_RESTART 与 END_FILE 路由', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();

        backend.events.addAll([
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 0),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 2),
        ]);

        backend.wake();
        
        expect(restartCount, 1);
        expect(endFileReasons, [0, 2]);
      });
    });

    test('I6: 一次 wake 排空多个事件，全同步不 await', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();

        backend.events.addAll([
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
        ]);

        backend.wake();
        
        expect(restartCount, 2);
        expect(backend.events, isEmpty);
      });
    });

    test('I1: ready 未完成时 dispose，不创建客户端', () {
      fakeAsync((async) {
        final pump = createPump();
        final readyCompleter = Completer<void>();
        
        pump.start(readyCompleter.future);
        async.flushMicrotasks();
        
        pump.dispose();
        
        readyCompleter.complete();
        async.flushMicrotasks();
        
        expect(backend.createCount, 0);
        expect(backend.destroyCount, 0);
        expect(backend.callLog, isNot(contains('createClient')));
      });
    });

    test('I11: 注册完成后 dispose，清理计数对齐', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        expect(backend.createCount, 1);
        pump.dispose();
        async.flushMicrotasks();
        
        expect(backend.destroyCount, 1);
      });
    });

    test('I3: 重复 dispose 幂等', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        final f1 = pump.dispose();
        final f2 = pump.dispose();
        final f3 = pump.dispose();
        
        expect(identical(f1, f2), isTrue);
        expect(identical(f2, f3), isTrue);
        
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);
      });
    });

    test('I3: 并发 Future.wait dispose 幂等', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        Future.wait([pump.dispose(), pump.dispose(), pump.dispose()]);
        async.flushMicrotasks();
        
        expect(backend.destroyCount, 1);
      });
    });

    test('I2: dispose 后 staleWake，零回调', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        pump.dispose();
        async.flushMicrotasks();
        
        final pollCountBefore = backend.callLog.where((c) => c == 'poll').length;
        
        backend.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        backend.staleWake();
        
        final pollCountAfter = backend.callLog.where((c) => c == 'poll').length;
        
        expect(pollCountAfter, pollCountBefore);
        expect(restartCount, 0);
      });
    });

    test('I4: 销毁顺序先注销通知再销毁句柄', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        pump.dispose();
        async.flushMicrotasks();
        
        final calls = backend.callLog;
        final armIdx = calls.indexOf('armWakeup');
        final destroyIdx = calls.indexOf('destroy');
        final unregisterIdx = calls.indexOf('注销通知');
        final killIdx = calls.indexOf('销毁句柄');
        
        expect(armIdx, lessThan(destroyIdx));
        expect(destroyIdx, lessThan(unregisterIdx));
        expect(unregisterIdx, lessThan(killIdx));
      });
    });

    test('I2/I6: 事件风暴中途 dispose', () {
      fakeAsync((async) {
        int localRestart = 0;
        late MovaMpvEventPump pump;
        pump = MovaMpvEventPump(
          backend,
          name: 'qoe_0',
          onRestart: () {
            localRestart++;
            if (localRestart == 5) {
              pump.dispose();
            }
          },
          onEndFile: (_) {},
        );
        pump.start(Future.value());
        async.flushMicrotasks();
        
        for (int i = 0; i < 1000; i++) {
          backend.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        }
        
        backend.wake();
        
        expect(localRestart, 5);
        expect(backend.events.length, 995);

        // dispose 后再 staleWake 一次，断言 poll 数不增
        final pollCountBefore = backend.callLog.where((c) => c == 'poll').length;
        backend.staleWake();
        final pollCountAfter = backend.callLog.where((c) => c == 'poll').length;
        expect(pollCountAfter, pollCountBefore);
      });
    });

    test('I7: 回调抛异常不打断排空', () {
      fakeAsync((async) {
        int callCount = 0;
        final pump = MovaMpvEventPump(
          backend,
          name: 'qoe_0',
          onRestart: () {
            callCount++;
            throw Exception('回调抛异常');
          },
          onEndFile: (_) {
            callCount++;
          },
        );
        pump.start(Future.value());
        async.flushMicrotasks();
        
        backend.events.addAll([
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 0),
        ]);
        
        backend.wake();
        expect(callCount, 2);
        
        pump.dispose();
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);
      });
    });

    test('poll 抛异常后停止重试，dispose 仍 destroy 恰好一次', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        backend.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        backend.pollThrow = Exception('poll error');
        
        backend.wake();
        
        final pollCountBefore = backend.callLog.where((c) => c == 'poll').length;
        backend.wake(); // 再次 wake
        final pollCountAfter = backend.callLog.where((c) => c == 'poll').length;
        expect(pollCountAfter, pollCountBefore, reason: '抛出异常后不应该再 poll');
        
        pump.dispose();
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);
      });
    });

    test('I8: createClient 返回 false 或 ready 抛错时 start 不抛异常且 destroyCount 均为 0', () {
      fakeAsync((async) {
        final pump1 = createPump(name: '1');
        final future1 = pump1.start(Future.error(Exception('ready error')));
        expectLater(future1, completes);
        async.flushMicrotasks();
        expect(backend.createCount, 0);
        expect(backend.destroyCount, 0);
        
        backend.createFail = true;
        final pump2 = createPump(name: '2');
        final future2 = pump2.start(Future.value());
        expectLater(future2, completes);
        async.flushMicrotasks();
        expect(backend.createCount, 0);
        expect(backend.destroyCount, 0);
      });
    });

    test('I10: SHUTDOWN 事件后停止排空但 dispose 仍 destroy', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        backend.events.addAll([
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
          const MovaRawEvent(MovaMpvEventBackend.eventShutdown),
          const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart),
        ]);
        
        backend.wake();
        
        expect(restartCount, 1);
        expect(backend.events.length, 1);
        
        pump.dispose();
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);
      });
    });

    test('I9: 多引擎并存', () {
      fakeAsync((async) {
        final backend1 = FakeMpvEventBackend();
        final backend2 = FakeMpvEventBackend();
        
        int r1 = 0, r2 = 0;
        final pump1 = MovaMpvEventPump(backend1, name: '1', onRestart: () => r1++, onEndFile: (_) {});
        final pump2 = MovaMpvEventPump(backend2, name: '2', onRestart: () => r2++, onEndFile: (_) {});
        
        pump1.start(Future.value());
        pump2.start(Future.value());
        async.flushMicrotasks();
        
        backend1.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        backend2.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        backend2.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        
        backend1.wake();
        backend2.wake();
        
        expect(r1, 1);
        expect(r2, 2);
        
        pump1.dispose();
        async.flushMicrotasks();
        
        backend2.events.add(const MovaRawEvent(MovaMpvEventBackend.eventPlaybackRestart));
        backend2.wake();
        
        expect(r1, 1);
        expect(r2, 3);
        
        expect(backend1.destroyCount, 1);
        expect(backend2.destroyCount, 0);
      });
    });

    test('I1/I5/I11: createClient 之后、restrictEvents 时 dispose', () {
      fakeAsync((async) {
        final pump = createPump();
        backend.onCreateClient = () {
          pump.dispose();
        };
        
        pump.start(Future.value());
        async.flushMicrotasks();
        
        expect(backend.createCount, 1);
        expect(backend.destroyCount, 1);
        expect(backend.callLog, isNot(contains('armWakeup')));
        
        backend.staleWake(); // 无 poll
        final pollCount = backend.callLog.where((c) => c == 'poll').length;
        expect(pollCount, 0);
      });
    });

    test('I1/I5/I11: restrictEvents 之后、armWakeup 前 dispose', () {
      fakeAsync((async) {
        final pump = createPump();
        backend.onRestrictEvents = () {
          pump.dispose();
        };
        
        pump.start(Future.value());
        async.flushMicrotasks();
        
        expect(backend.createCount, 1);
        expect(backend.destroyCount, 1);
        expect(backend.callLog, isNot(contains('armWakeup')));
        
        backend.staleWake(); // 无 poll
        final pollCount = backend.callLog.where((c) => c == 'poll').length;
        expect(pollCount, 0);
      });
    });

    test('restrictEvents 收到的集合恰为 SHUTDOWN, END_FILE, PLAYBACK_RESTART', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        expect(backend.lastRestrictedEvents, {
          MovaMpvEventBackend.eventShutdown,
          MovaMpvEventBackend.eventEndFile,
          MovaMpvEventBackend.eventPlaybackRestart,
        });
      });
    });

    test('END_FILE 各 reason (0/2/3/4/5) 都能带 reason 送达', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        backend.events.addAll([
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 0),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 2),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 3),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 4),
          const MovaRawEvent(MovaMpvEventBackend.eventEndFile, endFileReason: 5),
        ]);
        
        backend.wake();
        expect(endFileReasons, [0, 2, 3, 4, 5]);
      });
    });

    test('destroy 抛异常时 dispose 不抛，再次 dispose 不重复 destroy', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        async.flushMicrotasks();
        
        backend.destroyThrow = Exception('destroy error');
        
        final future1 = pump.dispose();
        expectLater(future1, completes);
        async.flushMicrotasks();
        
        expect(backend.destroyCount, 0); // 抛错不增加计数，但调用记录有
        expect(backend.callLog.where((c) => c == 'destroy').length, 1);
        
        final future2 = pump.dispose();
        expectLater(future2, completes);
        async.flushMicrotasks();
        
        expect(backend.callLog.where((c) => c == 'destroy').length, 1);
      });
    });

    test('start 重复调用幂等', () {
      fakeAsync((async) {
        final pump = createPump();
        pump.start(Future.value());
        pump.start(Future.value());
        async.flushMicrotasks();
        
        expect(backend.createCount, 1);
      });
    });

    test('createClient/restrictEvents/armWakeup 抛异常时 start 不抛，且 dispose 不挂起及不重复 destroy', () {
      fakeAsync((async) {
        // createClient throw
        final pump1 = createPump(name: '1');
        backend.createThrow = Exception('create error');
        expectLater(pump1.start(Future.value()), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 0);
        expectLater(pump1.dispose(), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 0);

        // restrictEvents throw
        backend.createThrow = null;
        backend.restrictThrow = Exception('restrict error');
        final pump2 = createPump(name: '2');
        expectLater(pump2.start(Future.value()), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);
        expectLater(pump2.dispose(), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 1);

        // armWakeup throw
        backend.restrictThrow = null;
        backend.armThrow = Exception('arm error');
        final pump3 = createPump(name: '3');
        expectLater(pump3.start(Future.value()), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 2);
        expectLater(pump3.dispose(), completes);
        async.flushMicrotasks();
        expect(backend.destroyCount, 2);
      });
    });

    test('ready 为永不完成的 Completer 时 dispose 不挂住', () {
      fakeAsync((async) {
        final pump = createPump();
        final readyCompleter = Completer<void>();
        
        pump.start(readyCompleter.future);
        async.flushMicrotasks();
        
        expectLater(pump.dispose(), completes);
        async.flushMicrotasks(); // 应该立即完成
        
        readyCompleter.complete();
        async.flushMicrotasks();
        
        expect(backend.createCount, 0);
        expect(backend.destroyCount, 0);
      });
    });

    test('在 armWakeup 内重入 pump.dispose()，state 不复活且 destroyCount == createCount', () {
      fakeAsync((async) {
        final pump = createPump();
        backend.onArmWakeup = () {
          pump.dispose();
        };

        pump.start(Future.value());
        async.flushMicrotasks();

        expect(backend.createCount, 1);
        expect(backend.destroyCount, 1);
        expect(backend.callLog, contains('armWakeup'));

        // 之后 wake 不应触发 poll
        backend.staleWake();
        final pollCount = backend.callLog.where((c) => c == 'poll').length;
        expect(pollCount, 0);
      });
    });
  });
}
