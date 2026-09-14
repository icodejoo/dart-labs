// Tests for ColdMountFrameBudget and its wiring into SvgxStatic: the
// time-budget gate added so mounting many never-before-cached SVGs in one
// frame spills the overflow into later frames instead of overloading the
// first one. See `lib/src/cold_mount_budget.dart`'s class doc for the design
// rationale (time budget, not item count).
//
// ColdMountFrameBudget 及其接入 SvgxStatic 的测试：为避免一帧内挂载大量从未
// 缓存过的 SVG 把这一帧撑爆而加入的时间预算闸门，超出部分会溢出到后续帧。
// 设计理由（用时间预算而非固定个数）见 `lib/src/cold_mount_budget.dart` 的
// 类文档。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/cold_mount_budget.dart';
import 'package:svgx/svgx.dart';

String _svg(int seed) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <path d="M4 4 L20 4 L20 20 Z" fill="#123456"/>
  <!--seed$seed-->
</svg>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var rustAvailable = true;
  setUpAll(() async {
    try {
      await RustLib.init();
    } catch (_) {
      rustAvailable = false;
    }
  });

  setUp(() {
    ColdMountFrameBudget.instance.debugReset();
    RustSvgxPictureCache.instance.clear();
  });
  tearDown(() {
    ColdMountFrameBudget.instance.debugReset();
    RustSvgxPictureCache.instance.clear();
  });

  group('ColdMountFrameBudget (pure unit)', () {
    test('hasRoom is true before anything runs', () {
      expect(ColdMountFrameBudget.instance.hasRoom, isTrue);
    });

    test('runNow charges elapsed time; enough of it exhausts room', () {
      final budget = ColdMountFrameBudget.instance;
      // Simulate a single render that alone exceeds the whole per-frame
      // budget (8ms) — a busy-wait, since Stopwatch measures wall time.
      // 模拟一次单独就超过整帧预算(8ms)的渲染——用忙等，因为 Stopwatch 测的是
      // 墙钟时间。
      budget.runNow(() {
        final sw = Stopwatch()..start();
        while (sw.elapsedMilliseconds < 9) {}
        return null;
      });
      expect(budget.hasRoom, isFalse);
    });

    test(
      'runDeferred does not complete synchronously when budget is exhausted',
      () {
        final budget = ColdMountFrameBudget.instance;
        budget.runNow(() {
          final sw = Stopwatch()..start();
          while (sw.elapsedMilliseconds < 9) {}
          return null;
        });
        expect(budget.hasRoom, isFalse);

        var completed = false;
        budget.runDeferred(() => completed = true);
        // No frame has been pumped yet — must still be pending.
        // 还没有帧被推进——此时必须仍处于等待状态。
        expect(completed, isFalse);
      },
    );

    testWidgets('runDeferred resolves once a frame runs and resets budget', (
      tester,
    ) async {
      final budget = ColdMountFrameBudget.instance;
      budget.runNow(() {
        final sw = Stopwatch()..start();
        while (sw.elapsedMilliseconds < 9) {}
        return null;
      });
      expect(budget.hasRoom, isFalse);

      final future = budget.runDeferred(() => 'done');
      String? result;
      future.then((v) => result = v);

      expect(result, isNull);
      await tester.pump();
      expect(result, 'done');
      // Budget resets for the new frame, and running the deferred work itself
      // charges a (tiny) amount, but should leave room again.
      // 预算随新帧重置；执行推迟的工作本身会计入一点点耗时，但应当仍有余量。
      expect(budget.hasRoom, isTrue);
    });
  });

  group('SvgxStatic + ColdMountFrameBudget (widget)', () {
    testWidgets('a handful of cold icons still paint in the first frame', (
      tester,
    ) async {
      if (!rustAvailable) return;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (var i = 0; i < 3; i++) SvgxStatic(_svg(i), width: 24, height: 24),
            ],
          ),
        ),
      );
      // No extra pump: the common case (well under the 8ms budget) must
      // render synchronously in the same frame as mount, unchanged from
      // before this feature existed.
      // 不额外 pump：寻常情况（远低于 8ms 预算）必须与挂载同一帧内同步渲染，
      // 与本功能加入前的行为一致。
      expect(RustSvgxPictureCache.instance.length, 3);
    });

    testWidgets(
      'many cold icons in one frame: overflow still all paint, just possibly a frame later',
      (tester) async {
        if (!rustAvailable) return;
        const count = 60;
        await tester.pumpWidget(
          MaterialApp(
            home: Wrap(
              children: [
                for (var i = 0; i < count; i++)
                  SvgxStatic(_svg(i), width: 24, height: 24),
              ],
            ),
          ),
        );
        // Whatever didn't fit under the first frame's budget is deferred;
        // pumpAndSettle drains every subsequent frame until nothing is left
        // pending.
        // 第一帧预算没装下的部分会被推迟；pumpAndSettle 会持续推进后续帧直到
        // 没有任何待处理项。
        await tester.pumpAndSettle();
        expect(RustSvgxPictureCache.instance.length, count);
      },
    );
  });
}
