import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/snapshot_guard.dart';

import '../support/fake_api.dart';

/// Counts how a [SnapshotWidget] painted its child: as a snapshot or the normal way.
///
/// 统计 [SnapshotWidget] 是怎么画子树的：快照还是正常绘制。
class _CountingPainter extends SnapshotPainter {
  int snapshots = 0;
  int normal = 0;

  @override
  void paint(PaintingContext context, ui.Offset offset, ui.Size size, PaintingContextCallback painter) {
    normal++;
    painter(context, offset);
  }

  @override
  void paintSnapshot(PaintingContext context, ui.Offset offset, ui.Size size, ui.Image image, ui.Size sourceSize, double pixelRatio) {
    snapshots++;
  }

  @override
  bool shouldRepaint(covariant SnapshotPainter oldPainter) => true;
}

/// Pumps [child] inside a permissive [SnapshotWidget] that is allowed to snapshot.
///
/// 把 [child] 放进一个允许快照的宽松 [SnapshotWidget] 里渲染。
Future<_CountingPainter> _pumpSnapshotted(WidgetTester t, Widget child) async {
  final painter = _CountingPainter();
  final controller = SnapshotController(allowSnapshotting: true);
  addTearDown(controller.dispose);
  await t.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SnapshotWidget(
        mode: SnapshotMode.permissive,
        controller: controller,
        painter: painter,
        child: SizedBox(width: 120, height: 80, child: child),
      ),
    ),
  );
  return painter;
}

void main() {
  group('MovaSnapshotGuard', () {
    testWidgets('baseline: without the guard a permissive SnapshotWidget snapshots the child', (t) async {
      final p = await _pumpSnapshotted(t, const ColoredBox(color: Color(0xFF112233)));
      expect(p.snapshots, greaterThan(0));
      expect(p.normal, 0);
    });

    testWidgets('enabled: the snapshot is refused and painting falls back to the normal path', (t) async {
      final p = await _pumpSnapshotted(
        t,
        const MovaSnapshotGuard(enabled: true, child: ColoredBox(color: Color(0xFF112233))),
      );
      expect(p.snapshots, 0);
      expect(p.normal, greaterThan(0));
    });

    testWidgets('disabled: pass-through, snapshots as before', (t) async {
      final p = await _pumpSnapshotted(
        t,
        const MovaSnapshotGuard(enabled: false, child: ColoredBox(color: Color(0xFF112233))),
      );
      expect(p.snapshots, greaterThan(0));
      expect(p.normal, 0);
    });

    testWidgets('enabled forces compositing and the same render object reacts to the toggle', (t) async {
      await t.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MovaSnapshotGuard(enabled: true, child: SizedBox(width: 10, height: 10)),
        ),
      );
      final ro = t.renderObject<RenderMovaSnapshotGuard>(find.byType(MovaSnapshotGuard));
      expect(ro.alwaysNeedsCompositing, isTrue);
      await t.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MovaSnapshotGuard(enabled: false, child: SizedBox(width: 10, height: 10)),
        ),
      );
      // The same render object is reused and reacts to the toggle.
      expect(t.renderObject<RenderMovaSnapshotGuard>(find.byType(MovaSnapshotGuard)), same(ro));
      expect(ro.enabled, isFalse);
      expect(ro.alwaysNeedsCompositing, isFalse);
    });
  });

  group('MovaPlayer surface', () {
    /// Finds the guard the player's render surface builds.
    ///
    /// 找到播放器渲染面构建的守卫。
    Finder surfaceGuard() => find.byType(MovaSnapshotGuard);

    testWidgets('movaSnapshotGuardNeeded is true only on Windows', (t) async {
      for (final p in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = p;
        expect(movaSnapshotGuardNeeded(), p == TargetPlatform.windows, reason: '$p');
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on Windows the surface opts out of snapshots (the HE V10 crash path)', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final api = FakeMovaApi();
      await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api)));
      await t.pump();
      expect(t.widget<MovaSnapshotGuard>(surfaceGuard()).enabled, isTrue);
      debugDefaultTargetPlatformOverride = null;
      await api.dispose();
    });

    testWidgets('on Windows a permissive SnapshotWidget around the player falls back instead of snapshotting', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final api = FakeMovaApi();
      final painter = _CountingPainter();
      final controller = SnapshotController(allowSnapshotting: true);
      addTearDown(controller.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: SnapshotWidget(
            mode: SnapshotMode.permissive,
            controller: controller,
            painter: painter,
            child: MovaPlayer(api: api),
          ),
        ),
      );
      await t.pump();
      expect(painter.snapshots, 0);
      expect(painter.normal, greaterThan(0));
      debugDefaultTargetPlatformOverride = null;
      await api.dispose();
    });

    testWidgets('on other platforms the surface behaves as before (guard off, snapshots allowed)', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final api = FakeMovaApi();
      final painter = _CountingPainter();
      final controller = SnapshotController(allowSnapshotting: true);
      addTearDown(controller.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: SnapshotWidget(
            mode: SnapshotMode.permissive,
            controller: controller,
            painter: painter,
            child: MovaPlayer(api: api),
          ),
        ),
      );
      await t.pump();
      expect(t.widget<MovaSnapshotGuard>(surfaceGuard()).enabled, isFalse);
      expect(painter.snapshots, greaterThan(0));
      debugDefaultTargetPlatformOverride = null;
      await api.dispose();
    });
  });
}
