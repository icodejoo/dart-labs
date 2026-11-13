import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/svg_image_provider.dart';

/// Deterministic sampling fixtures. / 确定性采样夹具。
const _interval = Duration(milliseconds: 100);

/// Suspended-frame gap. / 停帧间隔。
const _longPause = Duration(seconds: 5);

/// Finite animation end. / 有限动画结束时刻。
const _end = Duration(milliseconds: 300);

/// Looping animation fixture. / 循环动画夹具。
const _loop =
    '<svg width="4" height="4"><rect width="4" height="4">'
    '<animate attributeName="opacity" values="0;1" dur="10s" '
    'repeatCount="indefinite"/></rect></svg>';

/// Finite animation fixture. / 有限动画夹具。
const _finite =
    '<svg width="4" height="4"><rect width="4" height="4">'
    '<animate attributeName="opacity" values="0;1" dur="0.3s" '
    'fill="freeze"/></rect></svg>';

/// A provider observer holding an explicit cache-like keepAlive handle.
/// 持有显式缓存式 keepAlive 句柄的 provider 观察器。
class _Observation {
  /// Starts observing a source with a predictable frame interval.
  /// 用可预测的帧间隔开始观察源。
  _Observation(String source) {
    final provider = StringXvg(
      source,
      width: 4,
      height: 4,
      animationFrameRate: 10,
    );
    completer = provider.loadImage(
      provider,
      (buffer, {getTargetSize}) => throw StateError('SVG must bypass codec'),
    );
    handle = completer.keepAlive();
    listener = ImageStreamListener((info, _) {
      delivered++;
      info.dispose();
    });
    attach();
  }

  /// Stream under test. / 被测图像流。
  late final ImageStreamCompleter completer;

  /// Handle retaining the decoder during listener pauses. / 暂停监听时保留解码器。
  late final ImageStreamCompleterHandle handle;

  /// One reusable listener. / 可复用的唯一监听者。
  late final ImageStreamListener listener;

  /// Number of published images received. / 已收到的发布图像数量。
  int delivered = 0;

  /// Whether the observer currently listens. / 观察器当前是否监听。
  bool attached = false;

  /// Reattaches the display consumer. / 重新挂载显示消费者。
  void attach() {
    attached = true;
    completer.addListener(listener);
  }

  /// Pauses the display consumer without discarding the stream.
  /// 暂停显示消费者但不丢弃图像流。
  void detach() {
    if (!attached) return;
    attached = false;
    completer.removeListener(listener);
  }

  /// Releases display and cache ownership. / 释放显示与缓存所有权。
  void dispose() {
    detach();
    handle.dispose();
  }
}

/// Creates a reusable image without invoking animation rendering.
/// 创建可复用图像，避免调用动画渲染。
Future<ui.Image> _templateImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}

/// Exercises SVG scheduling with the binding's virtual frame clock.
/// 使用 binding 的虚拟帧时钟验证 SVG 调度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugSvgRasterize = null;
    timeDilation = 1;
  });

  testWidgets('无动画的文字源走 Dart，只交付一帧且重新监听不会恢复调度', (tester) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    final texts = <String?>[];
    debugSvgRasterize = (painter, width, height, filter) async {
      final animated = painter as AnimatedSvgPainter;
      samples.add(animated.time);
      texts.add(animated.root.children.single.textContent);
      return template.clone();
    };
    final observation = _Observation(
      '<svg width="4" height="4"><text x="0" y="3" font-size="3">I</text></svg>',
    );
    try {
      await tester.pump();
      expect(samples, [Duration.zero]);
      expect(texts, ['I']);
      expect(observation.delivered, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(_longPause);
      expect(samples, [Duration.zero]);
      observation.detach();
      observation.attach();
      await tester.pump(_longPause);
      expect(samples, [Duration.zero]);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      observation.dispose();
      template.dispose();
    }
  });

  testWidgets('finite animation publishes the terminal frame once then stops', (
    tester,
  ) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    debugSvgRasterize = (painter, _, _, _) async {
      samples.add((painter as AnimatedSvgPainter).time);
      return template.clone();
    };
    final observation = _Observation(_finite);
    try {
      await tester.pump();
      for (var tick = 0; tick < 8; tick++) {
        await tester.pump(_interval);
      }
      expect(samples, [Duration.zero, _interval, _interval * 2, _end]);
      expect(observation.delivered, 4);
      final stopped = observation.delivered;
      await tester.pump(_longPause);
      expect(observation.delivered, stopped);
      observation.detach();
      observation.attach();
      await tester.pump(_longPause);
      expect(samples.length, 4);
      expect(observation.delivered, stopped + 1);
    } finally {
      observation.dispose();
      template.dispose();
    }
  });

  testWidgets('timeDilation delays SVG timer and preserves virtual speed', (
    tester,
  ) async {
    timeDilation = 2;
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    debugSvgRasterize = (painter, _, _, _) async {
      samples.add((painter as AnimatedSvgPainter).time);
      return template.clone();
    };
    final observation = _Observation(_loop);
    try {
      await tester.pump();
      expect(samples, [Duration.zero]);
      await tester.pump(_interval);
      expect(samples.length, 1);
      await tester.pump(_interval);
      expect(samples.last, _interval);
      await tester.pump(_interval * 2);
      expect(samples.last, _interval * 2);
    } finally {
      observation.dispose();
      template.dispose();
      timeDilation = 1;
    }
  });

  testWidgets('long frame gaps advance only one animation interval', (
    tester,
  ) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    debugSvgRasterize = (painter, _, _, _) async {
      samples.add((painter as AnimatedSvgPainter).time);
      return template.clone();
    };
    final observation = _Observation(_loop);
    try {
      await tester.pump();
      await tester.pump(_interval);
      await tester.pump(_interval);
      final before = samples.last;
      await tester.pump(_longPause);
      expect(samples.last - before, _interval);
      await tester.pump(_interval);
      expect(samples.last - before, _interval * 2);
    } finally {
      observation.dispose();
      template.dispose();
    }
  });

  testWidgets('suspended application frames cause no SVG raster work', (
    tester,
  ) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    debugSvgRasterize = (painter, _, _, _) async {
      samples.add((painter as AnimatedSvgPainter).time);
      return template.clone();
    };
    final observation = _Observation(_loop);
    try {
      await tester.pump();
      await tester.pump(_interval);
      final before = samples.last;
      final rendered = samples.length;
      tester.binding.handleAppLifecycleStateChanged(
        ui.AppLifecycleState.paused,
      );
      await tester.pump(_longPause);
      expect(samples.length, rendered);
      tester.binding.handleAppLifecycleStateChanged(
        ui.AppLifecycleState.resumed,
      );
      await tester.pump();
      expect(samples.last - before, _interval);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(
        ui.AppLifecycleState.resumed,
      );
      observation.dispose();
      template.dispose();
    }
  });

  testWidgets('two listener pauses resume from retained virtual progress', (
    tester,
  ) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    debugSvgRasterize = (painter, _, _, _) async {
      samples.add((painter as AnimatedSvgPainter).time);
      return template.clone();
    };
    final observation = _Observation(_loop);
    try {
      await tester.pump();
      await tester.pump(_interval);
      for (var pause = 0; pause < 2; pause++) {
        final before = samples.last;
        observation.detach();
        final rendered = samples.length;
        await tester.pump(_longPause);
        expect(samples.length, rendered);
        observation.attach();
        await tester.pump();
        expect(samples.last, before);
        await tester.pump(_interval);
        expect(samples.last - before, _interval);
      }
    } finally {
      observation.dispose();
      template.dispose();
    }
  });

  testWidgets('terminal frame abandoned during pause is rendered on resume', (
    tester,
  ) async {
    final template = (await tester.runAsync(_templateImage))!;
    final samples = <Duration>[];
    final gate = Completer<ui.Image>();
    var blocked = false;
    debugSvgRasterize = (painter, _, _, _) {
      final time = (painter as AnimatedSvgPainter).time;
      samples.add(time);
      if (time == _end && !blocked) {
        blocked = true;
        return gate.future;
      }
      return Future<ui.Image>.value(template.clone());
    };
    final observation = _Observation(_finite);
    try {
      await tester.pump();
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(_interval);
      }
      expect(blocked, isTrue);
      expect(observation.delivered, 3);
      observation.detach();
      observation.attach();
      gate.complete(template.clone());
      await tester.pump();
      for (var tick = 0; tick < 4; tick++) {
        await tester.pump(_interval);
      }
      expect(samples.where((time) => time == _end).length, 2);
      final delivered = observation.delivered;
      expect(delivered, greaterThan(4));
      await tester.pump(_longPause);
      expect(observation.delivered, delivered);
    } finally {
      observation.dispose();
      template.dispose();
    }
  });
}
