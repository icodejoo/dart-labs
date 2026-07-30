import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvideo/fvideo.dart';
import 'package:fvideo/src/controls/gesture_layer.dart';

/// Pumps a full-window gesture detector wired to recording callbacks.
///
/// Filling the whole 800×600 test view keeps global drag coordinates equal
/// to the widget's local coordinates, so left/right halves are addressable.
///
/// 挂载一个铺满测试视窗的手势识别器，回调用于录制。
///
/// 铺满 800×600 视窗可让全局拖动坐标等于组件本地坐标，从而能定位左/右半屏。
Future<_Recorder> _pump(
  WidgetTester tester, {
  bool isLive = false,
  double startVolume = 50,
  double startBrightness = 0.5,
}) async {
  final rec = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: FvideoGestureDetector(
        config: const FvideoGestureConfig(),
        isLive: isLive,
        volumeGetter: () => startVolume,
        brightnessGetter: () => startBrightness,
        onVolume: (v) => rec.volume = v,
        onBrightness: (b) => rec.brightness = b,
        onSeekPreview: (s) => rec.seekPreview = s,
        onSeekCommit: (s) => rec.seekCommit = s,
        onZoomUpdate: (s) => rec.zoom = s,
        onZoomEnd: () => rec.zoomEnded = true,
        onDoubleTapSeek: (d) => rec.doubleTap = d,
      ),
    ),
  );
  return rec;
}

/// Collects the last value emitted per intent for assertions.
///
/// 收集每种意图最后发出的值，供断言使用。
class _Recorder {
  double? volume;
  double? brightness;
  double? seekPreview;
  double? seekCommit;
  double? zoom;
  bool zoomEnded = false;
  Duration? doubleTap;
}

void main() {
  testWidgets('left vertical drag raises volume, not brightness', (tester) async {
    final rec = await _pump(tester);
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(rec.volume, isNotNull);
    expect(rec.volume, greaterThan(50));
    expect(rec.brightness, isNull);
  });

  testWidgets('right vertical drag raises brightness, not volume', (tester) async {
    final rec = await _pump(tester);
    await tester.dragFrom(const Offset(600, 300), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(rec.brightness, isNotNull);
    expect(rec.brightness, greaterThan(0.5));
    expect(rec.volume, isNull);
  });

  testWidgets('horizontal drag commits a forward seek (~90s full width)', (tester) async {
    final rec = await _pump(tester);
    // +240px over an 800px width ⇒ roughly +240/800*90 ≈ 27s (minus touch slop).
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(rec.seekCommit, isNotNull);
    expect(rec.seekCommit, greaterThan(0));
    expect(rec.seekCommit, closeTo(24, 6));
  });

  testWidgets('horizontal drag is ignored for live streams', (tester) async {
    final rec = await _pump(tester, isLive: true);
    await tester.dragFrom(const Offset(400, 300), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(rec.seekCommit, isNull);
    expect(rec.seekPreview, isNull);
  });
}
