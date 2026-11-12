import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'sample_code.dart';

/// 正计时页面，展示控制器、圈速、起点与上限。
class ElapsedPage extends StatefulWidget {
  /// 创建正计时页面。
  const ElapsedPage({super.key});

  /// 创建正计时状态。
  @override
  State<ElapsedPage> createState() => _ElapsedPageState();
}

/// 保存圈速与稳定的墙钟起点。
class _ElapsedPageState extends State<ElapsedPage> {
  /// 高精度秒表控制器。
  final ElapsedController _controller = ElapsedController();

  /// 示例订单创建时间。
  final DateTime _since = DateTime.now().subtract(const Duration(minutes: 3));

  /// 是否暂停。
  bool _paused = false;

  /// 限时示例是否已完成。
  bool _done = false;

  /// 切换秒表暂停状态。
  void _toggle() => setState(() {
    _paused = !_paused;
    _paused ? _controller.pause() : _controller.resume();
  });

  /// 记录最近一次圈速。
  void _lap() => setState(() {
    _controller.lap();
  });

  /// 记录达到上限的状态。
  void _complete() {
    if (mounted) setState(() => _done = true);
  }

  /// 释放控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 构建正计时卡片网格。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Elapsed', '正计时'),
    description: tr(
      context,
      'A stopwatch with laps, a wall-clock start and a completion limit. Pausing excludes paused time.',
      '体验圈速、墙钟起点和时长上限；暂停时段不计入秒表。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Make time visible', '看见时间'),
        code: combineSampleCode(['elapsed', 'since', 'limit']),
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Stopwatch & laps', '秒表与圈速'),
                description: tr(
                  context,
                  'Tenths use defaultElapsedMs; capture a lap while running.',
                  '用 defaultElapsedMs 显示十分秒；运行时可记录圈速。',
                ),
                child: Column(
                  children: [
                    elapsedSample(_controller),
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
                          onPressed: _lap,
                          child: Text(tr(context, 'Lap', '圈速')),
                        ),
                      ],
                    ),
                    if (_controller.laps.isNotEmpty)
                      Text(
                        '${tr(context, 'Last lap', '最近圈速')}: ${_controller.laps.last.inMilliseconds} ms',
                      ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Elapsed since', '从起点计时'),
                description: tr(
                  context,
                  'An absolute start, three minutes before opening this page.',
                  '以进入页面前三分钟的绝对时刻为起点。',
                ),
                child: sinceSample(_since),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Completion limit', '时长上限'),
                description: tr(
                  context,
                  'Stops at eight seconds and delivers onComplete once.',
                  '八秒时停止，并触发一次 onComplete。',
                ),
                child: Column(
                  children: [
                    limitSample(_complete),
                    Text(
                      _done
                          ? DemoLabels.completed(context)
                          : tr(context, 'Running', '运行中'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
