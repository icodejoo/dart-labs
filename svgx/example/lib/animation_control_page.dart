import 'package:flutter/material.dart';
import 'package:svgx/svgx.dart';

/// Finite original motion with identified element events. / 带元素事件的原创有限动画。
const _motionSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="280" height="80" viewBox="0 0 280 80">
  <path d="M20 40H260" stroke="#cbd5e1" stroke-width="4"/>
  <circle cx="20" cy="40" r="14" fill="#2563eb">
    <animate id="travel" attributeName="cx" from="20" to="260" dur="4s" fill="freeze"/>
    <animate id="beacon" attributeName="opacity" values="1;0.2;1" begin="0.25s" dur="0.5s" repeatCount="2"/>
  </circle>
</svg>
''';

/// Original orbiting square spinner. / 原创方块轨道 spinner。
const _spinnerSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <circle cx="32" cy="32" r="22" fill="none" stroke="#cbd5e1" stroke-width="3"/>
  <g>
    <rect x="27" y="5" width="10" height="10" rx="3" fill="#0d9488"/>
    <animateTransform id="orbit" attributeName="transform" type="rotate" from="0 32 32" to="360 32 32" dur="1s" repeatCount="indefinite"/>
  </g>
</svg>
''';

/// Finite document span in seconds. / 有限文档时长（秒）。
const _spanSeconds = 4.0;

/// Document mapping span. / 文档映射时长。
const _span = Duration(seconds: 4);

/// Duration-fitting target. / 时长适配目标。
const _fitTarget = Duration(seconds: 2);

/// Number of recent events retained. / 最近事件保留条数。
const _logLimit = 20;

/// Main artwork height. / 主动画高度。
const _motionHeight = 80.0;

/// Spinner edge length. / Spinner 边长。
const _spinnerSize = 64.0;

/// Space between controls. / 控件间距。
const _controlSpacing = 8.0;

/// Offered playback speeds. / 可选播放速率。
const _rates = [0.5, 1.0, 2.0, -1.0];

/// Demonstrates three playback modes through Svgx.string.
/// 通过 Svgx.string 演示三种播放模式。
class AnimationControlPage extends StatefulWidget {
  /// Creates the animation controls demo. / 创建动画控制演示页。
  const AnimationControlPage({super.key});

  /// Page title used by navigation. / 导航使用的页面标题。
  static const title = '动画控制';

  /// Main document seek slider. / 主文档进度滑块。
  static const progressKey = ValueKey('animation-progress');

  /// Event list for inspecting element callbacks. / 用于查看元素回调的事件列表。
  static const eventsKey = ValueKey('animation-events');

  /// Creates playback state. / 创建播放状态。
  @override
  State<AnimationControlPage> createState() => _AnimationControlPageState();
}

/// Owns both controllers and the bounded event log. / 管理两个控制器与有界日志。
class _AnimationControlPageState extends State<AnimationControlPage>
    with SingleTickerProviderStateMixin {
  /// Shared-clock controller for mode A. / A 模式共享时钟控制器。
  final _controller = SvgxAnimationController();

  /// Flutter driver for mode B. / B 模式 Flutter 驱动器。
  late final AnimationController _flutterController;

  /// Curved value mapped to document time. / 映射到文档时间的曲线值。
  late final CurvedAnimation _curved;

  /// Newest event first. / 最新事件在前。
  final _events = <String>[];

  /// Selected range behavior. / 选中的片段播放方式。
  SvgxRangeMode _mode = SvgxRangeMode.once;

  /// Selected start/end seconds. / 选中的起止秒数。
  RangeValues _range = const RangeValues(0, _spanSeconds);

  /// Initializes the Flutter animation adapter. / 初始化 Flutter 动画适配。
  @override
  void initState() {
    super.initState();
    _flutterController = AnimationController(vsync: this, duration: _span);
    _curved = CurvedAnimation(
      parent: _flutterController,
      curve: Curves.easeInOutCubic,
    );
  }

  /// Releases both playback modes. / 释放两种播放模式。
  @override
  void dispose() {
    _curved.dispose();
    _flutterController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Records readable playback and element events. / 记录可读的播放与元素事件。
  void _record(SvgxAnimationEvent event) {
    final label = switch (event) {
      SvgxAnimationElementBegin(:final id) => 'begin: $id',
      SvgxAnimationElementEnd(:final id) => 'end: $id',
      SvgxAnimationElementRepeat(:final id, :final iteration) =>
        'repeat: $id ($iteration)',
      SvgxAnimationLoaded() => 'loaded',
      SvgxAnimationStarted() => 'started',
      SvgxAnimationCompleted() => 'completed',
      SvgxAnimationLooped(:final iteration) => 'loop: $iteration',
      SvgxAnimationRangeLooped(:final iteration) => 'range loop: $iteration',
      SvgxAnimationError(:final error) => 'error: $error',
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, label);
        if (_events.length > _logLimit) _events.removeLast();
      });
    });
  }

  /// Applies an action and refreshes rate/status labels. / 执行操作并刷新速率与状态。
  void _act(VoidCallback action) {
    action();
    setState(() {});
  }

  /// Converts slider seconds to a seek position. / 将滑块秒数转换为定位时间。
  Duration _time(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  /// Builds controls, both explicit modes, and an implicit spinner.
  /// 构建控制面板、两种显式模式和隐式 spinner。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AnimationControlPage.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('A · SvgxAnimationController'),
            Svgx.string(
              _motionSvg,
              controller: _controller,
              height: _motionHeight,
              onLoaded: (_) => setState(() {}),
              onEvent: _record,
            ),
            Wrap(
              spacing: _controlSpacing,
              children: [
                for (final action in <String, VoidCallback>{
                  'play': _controller.play,
                  'pause': _controller.pause,
                  'stop': _controller.stop,
                  'reverse': _controller.reverse,
                }.entries)
                  OutlinedButton(
                    onPressed: () => _act(action.value),
                    child: Text(action.key),
                  ),
                DropdownButton<double>(
                  value: _rates.contains(_controller.playbackRate)
                      ? _controller.playbackRate
                      : null,
                  hint: Text('${_controller.playbackRate}x'),
                  items: [
                    for (final rate in _rates)
                      DropdownMenuItem(value: rate, child: Text('${rate}x')),
                  ],
                  onChanged: (rate) {
                    if (rate != null) {
                      _act(() => _controller.playbackRate = rate);
                    }
                  },
                ),
              ],
            ),
            ValueListenableBuilder<Duration>(
              valueListenable: _controller.time,
              builder: (context, time, _) => Column(
                children: [
                  Text(
                    '${(time.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s / ${_spanSeconds}s',
                  ),
                  Slider(
                    key: AnimationControlPage.progressKey,
                    max: _spanSeconds,
                    value:
                        (time.inMicroseconds / Duration.microsecondsPerSecond)
                            .clamp(0, _spanSeconds),
                    onChanged: (value) => _controller.seek(_time(value)),
                  ),
                ],
              ),
            ),
            Text(
              '片段 ${_range.start.toStringAsFixed(1)}s – ${_range.end.toStringAsFixed(1)}s',
            ),
            RangeSlider(
              max: _spanSeconds,
              divisions: 40,
              values: _range,
              onChanged: (value) => setState(() => _range = value),
            ),
            Wrap(
              spacing: _controlSpacing,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<SvgxRangeMode>(
                  value: _mode,
                  items: [
                    for (final mode in SvgxRangeMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.name)),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _mode = mode);
                  },
                ),
                OutlinedButton(
                  onPressed: _range.end <= _range.start
                      ? null
                      : () => _act(() {
                          _controller.setRange(
                            _time(_range.start),
                            _time(_range.end),
                            mode: _mode,
                          );
                          _controller.play();
                        }),
                  child: const Text('播放片段'),
                ),
                OutlinedButton(
                  onPressed: () => _act(_controller.clearRange),
                  child: const Text('清除片段'),
                ),
                OutlinedButton(
                  onPressed: _controller.info == null
                      ? null
                      : () => _act(() {
                          _controller.clearRange();
                          _controller.fitDuration(_fitTarget);
                          _controller.stop();
                          _controller.play();
                        }),
                  child: const Text('fitDuration · 2 秒播完'),
                ),
              ],
            ),
            const Divider(),
            const Text('B · AnimationController + CurvedAnimation'),
            Svgx.string(
              _motionSvg,
              animation: _curved,
              animationSpan: _span,
              height: _motionHeight,
            ),
            Wrap(
              spacing: _controlSpacing,
              children: [
                OutlinedButton(
                  onPressed: () => _flutterController.repeat(reverse: true),
                  child: const Text('B · 曲线往返'),
                ),
                OutlinedButton(
                  onPressed: _flutterController.stop,
                  child: const Text('B · 暂停'),
                ),
              ],
            ),
            const Divider(),
            const Text('隐式自动播放 · 原创循环 spinner'),
            const Center(
              child: Svgx.string(
                _spinnerSvg,
                width: _spinnerSize,
                height: _spinnerSize,
              ),
            ),
            const Text('事件日志 · 最近 $_logLimit 条（seek 不触发穿越事件）'),
            SizedBox(
              height: 150,
              child: ListView(
                key: AnimationControlPage.eventsKey,
                children: [for (final event in _events) Text(event)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
