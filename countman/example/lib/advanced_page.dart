import 'package:countman/countman.dart';
import 'package:flutter/material.dart';

import 'pomodoro_plugin.dart';

/// 进阶演示页：CountmanTheme、倒计时模板与取整、进度分母 total、
/// 正计时的 since / limit / lap、OffsetClock 服务器校时，以及自定义插件。
class AdvancedPage extends StatefulWidget {
  /// 创建进阶演示页。
  const AdvancedPage({super.key});

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

/// 示例统一使用的等宽数字样式。
const _numberStyle = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// 模板格式化器只需在创建时解析一次，所以放在顶层复用。
final DurationFormatter _chineseTemplate =
    CountdownFormat.template('{d}天 {HH}:{mm}:{ss}');

/// 演示页的状态：持有需要长期存活的插件与固定时间点。
class _AdvancedPageState extends State<AdvancedPage> {
  /// 页面整体重播用的种子，改变后所有演示重新开始。
  int _seed = 0;

  /// 以本机时钟为准的插件。
  final Countdown _localPlugin = Countdown(name: 'advanced-local');

  /// 假设服务器时间比本机慢 45 秒，用 [OffsetClock] 校时的插件。
  final Countdown _serverPlugin = Countdown(
    name: 'advanced-server',
    clock: OffsetClock(CountmanClock.system, const Duration(seconds: -45)),
  );

  /// 同一个绝对截止时间，两个插件对它的剩余时间判断不同。
  late final DateTime _deadline = DateTime.now().add(const Duration(minutes: 2));

  /// “下单时间”，用于 Elapsed 的 since 演示。
  late final DateTime _orderedAt =
      DateTime.now().subtract(const Duration(minutes: 3, seconds: 20));

  @override
  void initState() {
    super.initState();
    Countman.use(_localPlugin);
    Countman.use(_serverPlugin);
  }

  @override
  void dispose() {
    // 按实例注销并销毁，下次进入页面重新创建同名实例不会冲突。
    Countman.unuse(_localPlugin);
    Countman.unuse(_serverPlugin);
    super.dispose();
  }

  /// 把整个页面的演示重新开始。
  void _restart() => setState(() => _seed++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('进阶'),
        actions: [
          IconButton(
            tooltip: '全部重播',
            icon: const Icon(Icons.replay_rounded),
            onPressed: _restart,
          ),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey(_seed),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'CountmanTheme',
              note: '通过 ThemeData.extensions 一次性给全部组件换默认样式；组件自己的 style 仍然优先。',
              children: [
                _Tile(
                  '默认样式',
                  RingCountdown(
                    to: const Duration(seconds: 45),
                    total: const Duration(seconds: 60),
                    center: TextCountdown(to: const Duration(seconds: 45)),
                  ),
                ),
                _Tile(
                  '套用主题',
                  Theme(
                    data: Theme.of(context).copyWith(
                      extensions: const [
                        CountmanTheme(
                          ringCountdownStyle: RingStyle(
                            size: 88,
                            strokeWidth: 10,
                            color: Color(0xFFEF6C00),
                            trackColor: Color(0x33EF6C00),
                          ),
                          textCountdownStyle: CountmanTextStyle(
                            textStyle: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFEF6C00),
                            ),
                          ),
                        ),
                      ],
                    ),
                    child: RingCountdown(
                      to: const Duration(seconds: 45),
                      total: const Duration(seconds: 60),
                      center: TextCountdown(to: const Duration(seconds: 45)),
                    ),
                  ),
                ),
              ],
            ),
            _Section(
              title: 'CountdownFormat.template',
              note: "模板创建时只解析一次；记号 {d} {HH} {mm} {ss} {SSS} 等，支持任意中文文本。",
              children: [
                _Tile(
                  "'{d}天 {HH}:{mm}:{ss}'",
                  TextCountdown(
                    to: const Duration(days: 2, hours: 3, minutes: 4, seconds: 5),
                    formatter: _chineseTemplate,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                  width: 240,
                ),
                _Tile(
                  "'还剩 {m} 分 {ss} 秒'",
                  TextCountdown(
                    to: const Duration(minutes: 7, seconds: 9),
                    formatter: CountdownFormat.template('还剩 {m} 分 {ss} 秒'),
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                  width: 240,
                ),
              ],
            ),
            _Section(
              title: 'rounding: CountdownRounding.ceil',
              note: '剩余 9.3 秒时：floor 显示 9，ceil 显示 10（最后一整秒显示 1，到 0 才完成）。',
              children: [
                _Tile(
                  'floor（默认）',
                  TextCountdown(
                    to: const Duration(seconds: 9, milliseconds: 300),
                    formatter: CountdownFormat.ms,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                ),
                _Tile(
                  'ceil',
                  TextCountdown(
                    to: const Duration(seconds: 9, milliseconds: 300),
                    rounding: CountdownRounding.ceil,
                    formatter: CountdownFormat.ms,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                ),
              ],
            ),
            _Section(
              title: 'total：进度分母',
              note: '剩余 20 秒、总时段 60 秒：进度环从 33% 起步，而不是 100%（比如拍卖整段时间里只剩最后一截）。',
              children: [
                _Tile(
                  'RingCountdown',
                  RingCountdown(
                    to: const Duration(seconds: 20),
                    total: const Duration(seconds: 60),
                    center: TextCountdown(to: const Duration(seconds: 20)),
                  ),
                ),
                _Tile(
                  'BarCountdown',
                  const BarCountdown(
                    to: Duration(seconds: 20),
                    total: Duration(seconds: 60),
                    style: BarStyle(width: 140),
                  ),
                  width: 170,
                ),
              ],
            ),
            _Section(
              title: 'Elapsed：since / limit / lap',
              note: 'since 以墙钟为起点（“下单已 3 分钟”）；limit 到上限发最后一次更新并结束；lap 记录圈速，暂停不计。',
              children: [
                _Tile(
                  'since：下单已…',
                  TextElapsed(
                    since: _orderedAt,
                    formatter: CountdownFormat.hms,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                ),
                _Tile('limit：8 秒后结束', const _LimitDemo()),
                const _Tile('lap：圈速', _LapDemo(), width: 240, height: 230),
              ],
            ),
            _Section(
              title: 'OffsetClock：服务器校时',
              note: '截止时间是同一个绝对时刻，假设服务器比本机慢 45 秒：'
                  '用 OffsetClock 的插件算出的剩余时间多出 45 秒，相对时长倒计时不受影响。',
              children: [
                _Tile(
                  '本机时钟',
                  TextCountdown(
                    to: _deadline,
                    plugin: _localPlugin,
                    formatter: CountdownFormat.ms,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                ),
                _Tile(
                  'OffsetClock(-45s)',
                  TextCountdown(
                    to: _deadline,
                    plugin: _serverPlugin,
                    formatter: CountdownFormat.ms,
                    style: const CountmanTextStyle(textStyle: _numberStyle),
                  ),
                ),
              ],
            ),
            _Section(
              title: '自定义插件：番茄钟',
              note: '继承 TaskQueuePlugin；tick 契约是“返回距下次处理的微秒数”。'
                  '专注 10 秒、休息 5 秒、两轮——更新次数远少于帧数，因为调度器在两次更新之间休眠。',
              children: const [
                _Tile('PomodoroPlugin', _PomodoroDemo(), width: 300, height: 220),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// limit 演示：到达上限后结束并回调 onComplete。
class _LimitDemo extends StatefulWidget {
  /// 创建演示。
  const _LimitDemo();

  @override
  State<_LimitDemo> createState() => _LimitDemoState();
}

/// [_LimitDemo] 的状态：记录是否已到上限。
class _LimitDemoState extends State<_LimitDemo> {
  /// 是否已触发 onComplete。
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextElapsed(
          limit: const Duration(seconds: 8),
          formatter: CountdownFormat.ms,
          style: const CountmanTextStyle(textStyle: _numberStyle),
          onComplete: () => setState(() => _done = true),
        ),
        const SizedBox(height: 4),
        Text(_done ? '已到上限' : '计时中…', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 圈速演示：用 ElapsedController 记录 lap。
class _LapDemo extends StatefulWidget {
  /// 创建演示。
  const _LapDemo();

  @override
  State<_LapDemo> createState() => _LapDemoState();
}

/// [_LapDemo] 的状态：持有控制器并刷新圈速列表。
class _LapDemoState extends State<_LapDemo> {
  /// 正计时控制器。
  final ElapsedController _controller = ElapsedController();

  /// 把时长格式化成 分:秒.十分秒。
  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final t = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:$s.$t';
  }

  @override
  Widget build(BuildContext context) {
    final laps = _controller.laps;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextElapsed(
          controller: _controller,
          plugin: defaultElapsedMs,
          formatter: CountdownFormat.msTenths,
          style: const CountmanTextStyle(textStyle: _numberStyle),
        ),
        Wrap(
          spacing: 6,
          children: [
            TextButton(onPressed: () => setState(_controller.lap), child: const Text('Lap')),
            TextButton(onPressed: _controller.pause, child: const Text('暂停')),
            TextButton(onPressed: _controller.resume, child: const Text('继续')),
            TextButton(onPressed: () => setState(_controller.reset), child: const Text('重置')),
          ],
        ),
        for (var i = 0; i < laps.length && i < 4; i++)
          Text('#${i + 1}  ${_format(laps[i])}', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 番茄钟演示：驱动自定义的 [PomodoroPlugin]。
class _PomodoroDemo extends StatefulWidget {
  /// 创建演示。
  const _PomodoroDemo();

  @override
  State<_PomodoroDemo> createState() => _PomodoroDemoState();
}

/// [_PomodoroDemo] 的状态：持有插件实例与句柄。
class _PomodoroDemoState extends State<_PomodoroDemo> {
  /// 演示用的短阶段：专注 10 秒、休息 5 秒。
  static const _phases = [
    PomodoroPhase('专注', Duration(seconds: 10)),
    PomodoroPhase('休息', Duration(seconds: 5)),
  ];

  /// 插件实例放在长生命周期的 State 里，避免重复创建时同名冲突。
  final PomodoroPlugin _plugin = PomodoroPlugin(name: 'advanced-pomodoro');

  /// 当前任务的控制句柄。
  late final PomodoroHandle _handle;

  /// 最近一次快照；首帧之前为空。
  PomodoroSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    Countman.use(_plugin);
    _handle = _plugin.start(
      phases: _phases,
      rounds: 2,
      onChange: (s) {
        if (mounted) setState(() => _snapshot = s);
      },
    );
  }

  @override
  void dispose() {
    Countman.unuse(_plugin);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s == null ? '准备中…' : (s.finished ? '全部完成' : '${s.phase.label} · ${s.remainingSeconds}s'),
          style: _numberStyle,
        ),
        const SizedBox(height: 4),
        Text(
          s == null ? '' : '阶段 ${s.phaseNumber}/${s.phaseCount} · 插件已处理 ${s.updates} 次更新',
          style: text.bodySmall,
        ),
        Wrap(
          spacing: 6,
          children: [
            TextButton(onPressed: _handle.pause, child: const Text('暂停')),
            TextButton(onPressed: _handle.resume, child: const Text('继续')),
            TextButton(onPressed: _handle.restart, child: const Text('重新开始')),
          ],
        ),
      ],
    );
  }
}

/// 一个演示分组：标题、说明和一排演示卡片。
class _Section extends StatelessWidget {
  /// 创建分组。
  const _Section({required this.title, required this.note, required this.children});

  /// 分组标题。
  final String title;

  /// 一句话说明。
  final String note;

  /// 分组内的演示项。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(note, style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: children),
        ],
      ),
    );
  }
}

/// 一个带标签的演示卡片。
class _Tile extends StatelessWidget {
  /// 创建卡片；[width] / [height] 为空时由内容撑开。
  const _Tile(this.label, this.child, {this.width = 150, this.height});

  /// 卡片标签。
  final String label;

  /// 演示内容。
  final Widget child;

  /// 卡片宽度。
  final double width;

  /// 卡片高度；为空时自适应。
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
