import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'pomodoro_plugin.dart';
import 'sample_code.dart';

/// 进阶页面，隔离休眠观察、限帧、隐藏静音与自定义插件。
class AdvancedPage extends StatefulWidget {
  /// 创建进阶页面。
  const AdvancedPage({super.key});

  /// 创建调度演示状态。
  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

/// 管理调度观测与全局设置，离开页面恢复原设置。
class _AdvancedPageState extends State<AdvancedPage> {
  /// 进入页面前的全局限帧配置。
  final double? _previousFps = Countman.fps;

  /// 进入页面前的隐藏静音配置。
  final bool _previousMute = Countman.muteWhenHidden;

  /// 被动观测插件，不请求连续帧。
  final WakeProbePlugin _probe = WakeProbePlugin();

  /// 本页面累计观察到的 Flutter 帧数。
  int _frames = 0;

  /// 秒级文本收到的更新数。
  int _seconds = 0;

  /// 快速对照收到的更新数。
  int _precise = 0;

  /// 最近读取的观测快照。
  String _snapshot = '';

  /// 是否启用精细计时对照。
  bool _continuous = false;

  /// 限帧动画的重播代次。
  int _generation = 0;

  /// 是否运行限帧动画，默认关闭避免污染休眠观察。
  bool _animate = false;

  /// 隐藏示例当前是否可见。
  bool _visible = true;

  /// 隐藏示例的重建代次。
  int _hiddenGeneration = 0;

  /// 隐藏示例收到的显示更新数。
  int _hiddenTicks = 0;

  /// 隐藏示例完成次数。
  int _completions = 0;

  /// 当前限帧选择，零表示跟随 vsync。
  double _fps = Countman.fps ?? 0;

  /// 初始化被动观测，使用一次性帧回调且不主动请求新帧。
  @override
  void initState() {
    super.initState();
    Countman.use(_probe);
    SchedulerBinding.instance.addPostFrameCallback(_observe);
  }

  /// 被动重挂帧回调，读取次数不会成为连续帧来源。
  void _observe(Duration timestamp) {
    if (!mounted) return;
    _frames++;
    SchedulerBinding.instance.addPostFrameCallback(_observe);
  }

  /// 读取数据的操作本身会产生一帧，页面明确说明此限制。
  void _read() => setState(
    () => _snapshot =
        '${tr(context, 'Flutter frames', 'Flutter 帧')}: $_frames · '
        '${tr(context, 'Scheduler wakes', '调度唤醒')}: ${_probe.wakes}\n'
        '${tr(context, 'Second updates', '秒级更新')}: $_seconds · '
        '${tr(context, 'Precise updates', '精细更新')}: $_precise',
  );

  /// 切换全局限帧并重播限帧示例。
  void _setFps(double? value) => setState(() {
    _fps = value ?? 0;
    setDemoFps(_fps == 0 ? null : _fps);
    _animate = true;
    _generation++;
  });

  /// 重挂隐藏示例，使 muteWhenHidden 在依赖解析时生效。
  void _setMute(bool value) => setState(() {
    Countman.muteWhenHidden = value;
    _hiddenGeneration++;
    _hiddenTicks = 0;
    _completions = 0;
  });

  /// 记录隐藏示例的完成事件，完成不会因隐藏而丢失。
  void _completed() {
    if (mounted) setState(() => _completions++);
  }

  /// 离开时恢复全局设置并注销观测插件。
  @override
  void dispose() {
    Countman.unuse(_probe);
    Countman.fps = _previousFps;
    Countman.muteWhenHidden = _previousMute;
    super.dispose();
  }

  /// 构建调度、限帧与隐藏行为三个分区。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Advanced', '进阶能力'),
    description: tr(
      context,
      'Observe sleeping, cap display updates and hide a running timer. These are behavior demos, not benchmarks.',
      '观察休眠、限制显示更新，并隐藏运行中的计时器。这些是行为演示，不是性能基准。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Wake only when needed', '按需唤醒'),
        code: sampleCode['probe'],
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Second-level timer', '秒级计时器'),
                description: tr(
                  context,
                  'Read twice a few seconds apart. Leave the precise comparison off to observe sleeping.',
                  '间隔几秒读取两次；关闭精细对照，观察休眠。',
                ),
                child: Column(
                  children: [
                    TextCountdown(
                      to: const Duration(hours: 1),
                      style: demoTextStyle,
                      onTick: (_) => _seconds++,
                    ),
                    FilledButton(
                      onPressed: _read,
                      child: Text(tr(context, 'Read counts', '读取计数')),
                    ),
                    if (_snapshot.isNotEmpty)
                      Text(
                        _snapshot,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Precise comparison', '精细更新对照'),
                description: tr(
                  context,
                  'Enable subsecond updates to request frames more often. Other active demos also affect counts.',
                  '开启亚秒更新会更频繁地请求帧；其他活跃演示也影响计数。',
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr(context, 'Enable comparison', '开启对照')),
                      value: _continuous,
                      onChanged: (value) => setState(() => _continuous = value),
                    ),
                    if (_continuous)
                      TextElapsed(
                        plugin: defaultElapsedMs,
                        formatter: CountdownFormat.msTenths,
                        style: demoTextStyle,
                        onTick: (_) => _precise++,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Frame counts cover this whole app. Reading, navigating and theme changes add frames. The observer never requests frames; this is not an FPS score. Stop other animated examples when comparing.',
          '帧数覆盖整个应用；读取、导航和主题切换也会增加帧。观察器不请求帧，这不是 FPS 评分。对比时请关闭其他动画示例。',
        ),
      ),
      DemoSection(
        title: tr(context, 'Display fps & hidden widgets', '显示限帧与隐藏组件'),
        code: combineSampleCode(['fps', 'hidden']),
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: 'Countman.fps',
                description: tr(
                  context,
                  'Instance > plugin > global. Completion and thresholds keep their timing.',
                  '实例 > 插件 > 全局；完成与阈值事件不因显示限帧延后。',
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: DropdownButton<double>(
                        value: _fps,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(
                              tr(context, 'Follow vsync', '跟随 vsync'),
                            ),
                          ),
                          for (final fps in const <double>[5, 15, 30])
                            DropdownMenuItem(
                              value: fps,
                              child: Text('${fps.toInt()} fps'),
                            ),
                        ],
                        onChanged: _setFps,
                      ),
                    ),
                    if (_animate)
                      TextCounter(
                        key: ValueKey(_generation),
                        to: 10000,
                        duration: demoShortDuration,
                        style: const TextCounterStyle(
                          textStyle: demoNumberStyle,
                        ),
                      ),
                    TextButton(
                      onPressed: () => _setFps(_fps),
                      child: Text(tr(context, 'Replay animation', '重播动画')),
                    ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'TickerMode',
                description: tr(
                  context,
                  'Hide for 8 seconds. Muting stops display callbacks; completion still fires. Show to catch up.',
                  '隐藏八秒：静音阻止显示回调，完成仍触发；显示后立即追上。',
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('muteWhenHidden'),
                      value: Countman.muteWhenHidden,
                      onChanged: _setMute,
                    ),
                    KeyedSubtree(
                      key: ValueKey(_hiddenGeneration),
                      child: hiddenSample(
                        _visible,
                        () => _hiddenTicks++,
                        _completed,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _visible = !_visible),
                      child: Text(
                        _visible
                            ? tr(context, 'Hide timer', '隐藏计时器')
                            : tr(context, 'Show timer', '显示计时器'),
                      ),
                    ),
                    Text(
                      '${DemoLabels.updates(context)}: $_hiddenTicks · ${tr(context, 'Completions', '完成')}: $_completions',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Custom plugin · pomodoro', '自定义插件 · 番茄钟'),
        subtitle: tr(
          context,
          'tick returns int: idle (-1), nextFrame (0), or positive microseconds. TaskQueuePlugin obtains its delay from nextWake.',
          'tick 返回 int：idle（-1）、nextFrame（0）或正微秒数。TaskQueuePlugin 通过 nextWake 获取等待时长。',
        ),
        code: sampleCode['pomodoro'],
        child: const DemoGrid(children: [DemoGridItem(child: _PomodoroDemo())]),
      ),
    ],
  );
}

/// 短时番茄钟演示，用户点击后才启动，避免干扰休眠观察。
class _PomodoroDemo extends StatefulWidget {
  /// 创建番茄钟卡片。
  const _PomodoroDemo();

  /// 创建插件状态。
  @override
  State<_PomodoroDemo> createState() => _PomodoroDemoState();
}

/// 管理自定义插件实例与当前快照。
class _PomodoroDemoState extends State<_PomodoroDemo> {
  /// 稳定且唯一的插件实例。
  final PomodoroPlugin _plugin = PomodoroPlugin(name: 'demo-pomodoro');

  /// 当前控制句柄。
  PomodoroHandle? _handle;

  /// 当前任务快照。
  PomodoroSnapshot? _snapshot;

  /// 注册插件但不主动启动任务。
  @override
  void initState() {
    super.initState();
    Countman.use(_plugin);
  }

  /// 启动专注和休息各两轮的短演示。
  void _start() {
    if (_handle != null) {
      _handle!.restart();
      return;
    }
    _handle = _plugin.start(
      phases: const [
        PomodoroPhase('focus', Duration(seconds: 10)),
        PomodoroPhase('rest', Duration(seconds: 5)),
      ],
      rounds: 2,
      onChange: (value) {
        if (mounted) setState(() => _snapshot = value);
      },
    );
  }

  /// 注销插件与它拥有的任务。
  @override
  void dispose() {
    Countman.unuse(_plugin);
    super.dispose();
  }

  /// 构建双语阶段与更新计数。
  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final phase = snapshot?.phase.label == 'rest'
        ? tr(context, 'Rest', '休息')
        : tr(context, 'Focus', '专注');
    return DemoCard(
      title: tr(context, 'Pomodoro', '番茄钟'),
      description: tr(
        context,
        '10s focus, 5s rest, twice. The plugin sleeps between second boundaries.',
        '专注十秒、休息五秒，重复两轮；插件在秒边界之间休眠。',
      ),
      child: Column(
        children: [
          Text(
            snapshot == null
                ? tr(context, 'Ready', '准备就绪')
                : snapshot.finished
                ? DemoLabels.completed(context)
                : '$phase · ${snapshot.remainingSeconds} s',
            style: demoNumberStyle,
          ),
          if (snapshot != null)
            Text('${DemoLabels.updates(context)}: ${snapshot.updates}'),
          Wrap(
            children: [
              TextButton(
                onPressed: _start,
                child: Text(tr(context, 'Start / restart', '开始 / 重播')),
              ),
              if (_handle != null)
                TextButton(
                  onPressed: () => setState(() {
                    _handle!.isPaused ? _handle!.resume() : _handle!.pause();
                  }),
                  child: Text(
                    _handle!.isPaused
                        ? DemoLabels.resume(context)
                        : DemoLabels.pause(context),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
