import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/testing.dart';

/// Verifies disposal independently of subscriber delivery.
///
/// 验证销毁不依赖订阅者的事件交付。
void main() {
  for (final cancel in [false, true]) {
    test(
      'dispose closes all streams with paused playing subscriber (cancel: $cancel) / 暂停订阅不阻塞全部流关闭',
      () {
        fakeAsync((clock) {
          final kernel = MovaTestKernel();
          final streams = <Stream<Object?>>[
            kernel.playing,
            kernel.buffering,
            kernel.completed,
            kernel.position,
            kernel.duration,
            kernel.buffer,
            kernel.size,
            kernel.error,
            kernel.stalling,
            kernel.logs,
            kernel.playbackRestarts,
            kernel.endFiles,
          ];
          final done = <int>[];
          final subscriptions = [
            for (var i = 0; i < streams.length; i++)
              streams[i].listen((_) {}, onDone: () => done.add(i)),
          ];
          subscriptions.first.pause();
          var disposed = false;
          kernel.dispose().then((_) => disposed = true);
          clock.flushMicrotasks();
          expect(disposed, isTrue);
          expect(
            done,
            orderedEquals(List.generate(streams.length - 1, (i) => i + 1)),
          );
          if (cancel) {
            subscriptions.first.cancel();
          } else {
            subscriptions.first.resume();
          }
          clock.flushMicrotasks();
          expect(done.contains(0), !cancel);
          kernel.dispose();
          clock.flushMicrotasks();
          expect(kernel.calls.where((call) => call == 'dispose'), hasLength(1));
          for (final subscription in subscriptions) {
            subscription.cancel();
          }
        });
      },
    );
  }
}
