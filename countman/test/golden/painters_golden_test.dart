@Tags(['golden'])
library;

import 'dart:io';

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';

// 各 painter 的像素回归（golden）。
//
// 默认不运行（dart_test.yaml 里 golden 标签带 skip）。
// 生成：flutter test --tags golden --run-skipped --update-goldens test/golden
// 比对：flutter test --tags golden --run-skipped test/golden
//
// 约定：逻辑像素 1:1（devicePixelRatio = 1）、固定画布尺寸、固定 ManualCountmanClock
// 时间点；文字统一使用 Flutter SDK 自带的 Roboto（从 SDK 缓存加载，不依赖系统字体）。
// golden 文件在 Windows 上生成，跨平台的抗锯齿像素会有细微差异，所以默认不跑。

/// golden 截图区域的 key。
const _shotKey = ValueKey<String>('golden-shot');

/// 把 [size] 设为画布物理尺寸，并返回包好白底与 RepaintBoundary 的页面。
Future<void> _pumpShot(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _shotKey,
        child: ColoredBox(
          color: Colors.white,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

/// 针对 [_shotKey] 截图并与 [name] 对应的 golden 比对。
Future<void> _expectGolden(String name) =>
    expectLater(find.byKey(_shotKey), matchesGoldenFile('goldens/$name.png'));

/// 所有 golden 统一使用的字体族。
const _font = 'Roboto';

/// AnimatedCounter 测试用的固定样式。
const _counterStyle = AnimatedCounterStyle(
  textStyle: TextStyle(fontFamily: _font, fontSize: 40, color: Colors.black),
);

/// 找到 Flutter SDK 根目录：优先环境变量，其次由测试进程路径反推。
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  final exe = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final cut = exe.indexOf('/bin/cache/');
  if (cut < 0) throw StateError('找不到 Flutter SDK 根目录，请设置 FLUTTER_ROOT');
  return exe.substring(0, cut);
}

/// 从 SDK 缓存加载 Roboto 的常规与粗体，保证 golden 里的数字有真实字形。
Future<void> _loadRoboto() async {
  final dir = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(_font);
  for (final file in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
    final bytes = await File('$dir/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// 固定时间点：每个用例使用独立的手动时钟，结束后销毁共享 ticker。
void main() {
  late ManualCountmanClock clock;

  setUpAll(_loadRoboto);
  setUp(() => clock = installManualClock());
  tearDown(Countman.destroy);

  group('CounterPainter（AnimatedCounter）', () {
    testWidgets('静止帧', (tester) async {
      await _pumpShot(
        tester,
        const Size(240, 100),
        const AnimatedCounter(value: 1234, style: _counterStyle),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // 等从初值滚动到 1234 静止
      await _expectGolden('counter_painter_rest');
    });

    testWidgets('过渡中一帧（1234 → 1299，进行 40%）', (tester) async {
      Widget build(int value) => AnimatedCounter(
            value: value,
            timeline: const CounterTimeline(
              duration: Duration(milliseconds: 1000),
              curve: Curves.linear,
            ),
            style: _counterStyle,
          );
      await _pumpShot(tester, const Size(240, 100), build(1234));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2)); // 先静止在 1234
      await _pumpShot(tester, const Size(240, 100), build(1299));
      await tester.pump(); // 首帧：渲染起点，不推进时间
      await tester.pump(const Duration(milliseconds: 400));
      await _expectGolden('counter_painter_transition');
    });
  });

  group('RingPainter / BarPainter', () {
    testWidgets('RingPainter：进度 65%、游标', (tester) async {
      await _pumpShot(
        tester,
        const Size(160, 160),
        const CustomPaint(
          size: Size(120, 120),
          painter: RingPainter(
            progress: 0.65,
            color: Color(0xFF26A69A),
            trackColor: Color(0x3326A69A),
            strokeWidth: 12,
            clockwise: true,
            showThumb: true,
          ),
        ),
      );
      await _expectGolden('ring_painter');
    });

    testWidgets('BarPainter：进度 40%、渐变与圆角', (tester) async {
      await _pumpShot(
        tester,
        const Size(260, 60),
        const CustomPaint(
          size: Size(220, 16),
          painter: BarPainter(
            progress: 0.4,
            color: Color(0xFF5C6BC0),
            trackColor: Color(0x335C6BC0),
            borderRadius: Radius.circular(8),
            gradient: LinearGradient(
              colors: [Color(0xFF5C6BC0), Color(0xFFEF5350)],
            ),
          ),
        ),
      );
      await _expectGolden('bar_painter');
    });
  });

  group('FlipCardPainter（CardCountdown）', () {
    /// 卡片倒计时：1 分 5 秒起，字体统一为 Roboto。
    final cardController = CountdownController();
    final card = CardCountdown(
      controller: cardController,
      to: Duration(minutes: 1, seconds: 5),
      style: CardCountdownStyle(
        textStyle: TextStyle(fontFamily: _font, fontSize: 44, color: Colors.white),
        labelStyle: TextStyle(fontFamily: _font, fontSize: 12, color: Colors.black54),
        separatorStyle: TextStyle(fontFamily: _font, fontSize: 36, color: Colors.black),
      ),
    );

    testWidgets('静止帧', (tester) async {
      await _pumpShot(tester, const Size(300, 160), card);
      await tester.pump();
      await _expectGolden('flip_card_rest');
    });

    testWidgets('翻牌过渡中一帧', (tester) async {
      await _pumpShot(tester, const Size(300, 160), card);
      await tester.pump();
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1)); // 秒位变化，翻牌开始
      cardController.pause(); // 固定同一秒的目标，单独推进共享翻牌任务。
      await tester.pump();
      clock.advance(const Duration(milliseconds: 225));
      await tester.pump(const Duration(milliseconds: 225));
      await _expectGolden('flip_card_transition');
    });
  });

  group('DialCountdown', () {
    testWidgets('剩余 42 秒', (tester) async {
      await _pumpShot(
        tester,
        const Size(220, 220),
        DialCountdown(
          to: const Duration(seconds: 42),
          style: const DialCountdownStyle(
            size: 180,
            ticks: DialTicksConfig(
              showLabels: true,
              labelStyle: TextStyle(fontFamily: _font, fontSize: 10, color: Colors.black54),
            ),
          ),
          builder: (context, parts) => Text(
            '${parts.seconds}',
            style: const TextStyle(fontFamily: _font, fontSize: 40, color: Colors.black),
          ),
        ),
      );
      await tester.pump();
      await _expectGolden('dial_countdown');
    });
  });
}
