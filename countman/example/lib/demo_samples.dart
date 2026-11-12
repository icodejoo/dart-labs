import 'package:countman/countman.dart';
import 'package:flutter/material.dart';

/// 示例共用的数字排版。
const demoNumberStyle = TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// 示例共用的短动画时长。
const demoAnimation = Duration(seconds: 2);

/// 示例共用的倒计时时长。
const demoDuration = Duration(minutes: 2);

/// 示例共用的显示取整样式。
const demoTextStyle = CountmanTextStyle(textStyle: demoNumberStyle);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

// sample:counter
/// 展示文本、里程表和格式选项；目标值变化时重播。
Widget counterSample(double value) => AnimatedCounter(
  value: value,
  format: const CounterFormat(fractionDigits: 2, thousandSeparator: ','),
  timeline: const CounterTimeline(duration: demoAnimation),
  style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
);
// end-sample

// sample:text-counter
/// 展示文本计数与非弃用的样式对象。
Widget textCounterSample(double value) => TextCounter(
  from: 0,
  to: value,
  duration: demoAnimation,
  style: const TextCounterStyle(textStyle: demoNumberStyle),
);
// end-sample

// sample:odometer
/// 展示里程表的数字滚动。
Widget odometerSample(double value) => OdometerCounter(
  from: 0,
  to: value,
  duration: demoAnimation,
  style: const OdometerCounterStyle(numberTextStyle: demoNumberStyle),
);
// end-sample

// sample:counter-progress
/// 展示共享目标的环形与条形计数。
Widget counterProgressSample() => const Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    RingCounter(
      to: demoCounterGoal,
      duration: demoAnimation,
      style: RingStyle(size: 64),
    ),
    SizedBox(width: 12),
    Expanded(
      child: BarCounter(to: demoCounterGoal, duration: demoAnimation),
    ),
  ],
);
// end-sample

// sample:countdown
/// 展示倒计时控制器与向上取整。
Widget countdownSample(CountdownController controller) => TextCountdown(
  to: demoDuration,
  controller: controller,
  rounding: CountdownRounding.ceil,
  formatter: CountdownFormat.ms,
  style: demoTextStyle,
);
// end-sample

// sample:countdown-progress
/// 展示总时段作为进度分母。
Widget countdownProgressSample() => const Row(
  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
    RingCountdown(
      to: demoProgressRemaining,
      total: demoDuration,
      style: RingStyle(size: 64),
    ),
    SizedBox(width: 12),
    Expanded(
      child: BarCountdown(to: demoProgressRemaining, total: demoDuration),
    ),
  ],
);
// end-sample

// sample:deadline
/// 展示绝对截止时间与模板格式化器。
Widget deadlineSample(DateTime deadline, DurationFormatter formatter) =>
    TextCountdown(
      to: deadline,
      formatter: formatter,
      rounding: CountdownRounding.ceil,
      style: demoTextStyle,
    );
// end-sample

// sample:elapsed
/// 展示带暂停和圈速控制器的高精度正计时。
Widget elapsedSample(ElapsedController controller) => TextElapsed(
  controller: controller,
  plugin: defaultElapsedMs,
  formatter: CountdownFormat.msTenths,
  style: demoTextStyle,
);
// end-sample

// sample:since
/// 展示从墙钟时间起算的正计时。
Widget sinceSample(DateTime since) => TextElapsed(
  since: since,
  formatter: CountdownFormat.hms,
  style: demoTextStyle,
);
// end-sample

// sample:limit
/// 展示到达上限后停止的正计时。
Widget limitSample(VoidCallback onComplete) => TextElapsed(
  limit: demoShortDuration,
  formatter: CountdownFormat.ms,
  onComplete: onComplete,
  style: demoTextStyle,
);
// end-sample

// sample:card
/// 展示以样式对象选择过渡的卡片渲染器。
Widget cardSample(
  CountdownType transition,
  String minutes,
  String seconds,
  String label,
) => CardCountdown(
  to: demoDuration,
  showHours: false,
  labels: ['', minutes, seconds],
  semanticsLabel: label,
  style: CardCountdownStyle(
    transitionType: transition,
    cardWidth: 40,
    cardHeight: 52,
    textStyle: const TextStyle(fontSize: 26, color: Colors.white),
  ),
);
// end-sample

// sample:dial
/// 展示位图刻度表盘和当前时间的中心构建器。
Widget dialSample() => DialCountdown(
  to: demoDuration,
  style: const DialCountdownStyle(size: 112),
  builder: (context, parts) => Text(
    CountdownFormat.ms(parts),
    style: Theme.of(context).textTheme.titleMedium,
  ),
);
// end-sample

// sample:fps
/// 展示全局显示限帧；组件的 fps 可以覆盖全局设置。
void setDemoFps(double? fps) {
  Countman.fps = fps;
}
// end-sample

// sample:hidden
/// 展示隐藏时静音，恢复可见时立即追上真实时间。
Widget hiddenSample(
  bool visible,
  VoidCallback onTick,
  VoidCallback onComplete,
) => TickerMode(
  enabled: visible,
  child: Visibility(
    visible: visible,
    maintainState: true,
    child: TextCountdown(
      to: demoShortDuration,
      style: demoTextStyle,
      onTick: (_) => onTick(),
      onComplete: onComplete,
    ),
  ),
);
// end-sample

// sample:providers
/// 展示在同一个作用域里使用三个计时家族。
Widget providerSample() => const CountmanProvider(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextCounter(
        to: demoCounterGoal,
        style: TextCounterStyle(textStyle: demoNumberStyle),
      ),
      TextCountdown(to: demoDuration, style: demoTextStyle),
      TextElapsed(style: demoTextStyle),
    ],
  ),
);
// end-sample

// sample:theme
/// 展示通过主题扩展设置样式，组件样式仍拥有最高优先级。
Widget themeSample(BuildContext context) => Theme(
  data: Theme.of(context).copyWith(
    extensions: [
      CountmanTheme(
        textCountdownStyle: CountmanTextStyle(
          textStyle: demoNumberStyle.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ],
  ),
  child: const TextCountdown(to: demoDuration),
);
// end-sample

// sample:cache
/// 释放共享位图缓存，下次绘制按需重建，不清理字形缓存。
void clearDemoBitmapCaches() {
  DialCountdown.clearTickImageCache();
  FlipCardPainter.clearFaceImageCache();
}
// end-sample

// sample:probe
/// 被动统计共享调度器的唤醒，不影响其他插件的休眠提示。
class WakeProbePlugin implements CountmanPlugin {
  /// 创建只读观测插件。
  WakeProbePlugin();

  /// 当前累计唤醒次数。
  int wakes = 0;

  /// 唯一的诊断名称。
  @override
  String get name => 'demo-wake-probe';

  /// 不请求帧，只随其他插件被动执行。
  @override
  void onAttach(CountmanContext ctx) {}

  /// 返回 idle，不让本插件成为额外唤醒来源。
  @override
  int tick(Duration elapsed, Duration dt) {
    wakes++;
    return CountmanPlugin.idle;
  }

  /// 解绑后无需清理调度任务。
  @override
  void onDetach() {}

  /// 本插件没有持有原生资源。
  @override
  void dispose() {}
}
// end-sample
