import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'sample_code.dart';

/// 倒计时页面，合并原先的全家速览与重复变体。
class CountdownPage extends StatefulWidget {
  /// 创建倒计时页面。
  const CountdownPage({super.key});

  /// 创建控制状态。
  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

/// 持有倒计时控制器与稳定的绝对截止时间。
class _CountdownPageState extends State<CountdownPage> {
  /// 可暂停和重启的控制器。
  final CountdownController _controller = CountdownController();

  /// 绝对截止时间，不因语言切换重新计算。
  final DateTime _deadline = DateTime.now().add(demoDuration);

  /// 只解析一次的模板格式化器。
  final DurationFormatter _formatter = CountdownFormat.template('{mm}:{ss}');

  /// 是否由用户暂停。
  bool _paused = false;

  /// 交替暂停和继续。
  void _toggle() => setState(() {
    _paused = !_paused;
    _paused ? _controller.pause() : _controller.resume();
  });

  /// 重播倒计时。
  void _restart() => setState(() {
    _paused = false;
    _controller.restart();
  });

  /// 释放控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建控制、进度与绝对时间示例。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Countdown', '倒计时'),
    description: tr(
      context,
      'Pause a relative timer or count down to an absolute deadline. Completion follows real time.',
      '暂停相对时长倒计时，或使用绝对截止时间。完成事件按真实时间触发。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Time, your way', '选择时间语义'),
        code: combineSampleCode([
          'countdown',
          'countdown-progress',
          'deadline',
        ]),
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Pause & resume', '暂停与继续'),
                description: tr(
                  context,
                  'Relative durations use the monotonic clock. Ceil keeps the last second visible.',
                  '相对时长使用单调时钟；ceil 在最后一整秒显示 1。',
                ),
                child: Column(
                  children: [
                    countdownSample(_controller),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _toggle,
                          child: Text(
                            _paused
                                ? DemoLabels.resume(context)
                                : DemoLabels.pause(context),
                          ),
                        ),
                        TextButton(
                          onPressed: _restart,
                          child: Text(DemoLabels.restart(context)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Progress denominator', '进度分母'),
                description: tr(
                  context,
                  '40 seconds left in a two-minute window: total controls the denominator.',
                  '两分钟时段还剩 40 秒：total 指定进度分母。',
                ),
                child: countdownProgressSample(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Absolute deadline', '绝对截止时间'),
                description: tr(
                  context,
                  'DateTime uses the wall clock. Templates are parsed once.',
                  'DateTime 使用墙钟；模板只需解析一次。',
                ),
                child: deadlineSample(_deadline, _formatter),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'to accepts Duration, DateTime, epoch milliseconds or an ISO string. After pause/resume or reset, the task continues on the monotonic clock.',
          'to 接受 Duration、DateTime、毫秒时间戳或 ISO 字符串。暂停后继续或重置后，任务使用单调时钟。',
        ),
      ),
    ],
  );
}
