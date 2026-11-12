/// 从实际运行源码生成；通过 python tool/sync_samples.py 更新。
const samplePrelude = r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;''';

/// 完整且与实际组件一致的代码示例。
const sampleCode = <String, String>{
  'counter': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示文本、里程表和格式选项；目标值变化时重播。
Widget counterSample(double value) => AnimatedCounter(
  value: value,
  format: const CounterFormat(fractionDigits: 2, thousandSeparator: ','),
  timeline: const CounterTimeline(duration: demoAnimation),
  style: const AnimatedCounterStyle(textStyle: demoNumberStyle),
);''',
  'text-counter': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示文本计数与非弃用的样式对象。
Widget textCounterSample(double value) => TextCounter(
  from: 0,
  to: value,
  duration: demoAnimation,
  style: const TextCounterStyle(textStyle: demoNumberStyle),
);''',
  'odometer': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示里程表的数字滚动。
Widget odometerSample(double value) => OdometerCounter(
  from: 0,
  to: value,
  duration: demoAnimation,
  style: const OdometerCounterStyle(numberTextStyle: demoNumberStyle),
);''',
  'counter-progress': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
);''',
  'countdown': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示倒计时控制器与向上取整。
Widget countdownSample(CountdownController controller) => TextCountdown(
  to: demoDuration,
  controller: controller,
  rounding: CountdownRounding.ceil,
  formatter: CountdownFormat.ms,
  style: demoTextStyle,
);''',
  'countdown-progress': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
);''',
  'deadline': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示绝对截止时间与模板格式化器。
Widget deadlineSample(DateTime deadline, DurationFormatter formatter) =>
    TextCountdown(
      to: deadline,
      formatter: formatter,
      rounding: CountdownRounding.ceil,
      style: demoTextStyle,
    );''',
  'elapsed': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示带暂停和圈速控制器的高精度正计时。
Widget elapsedSample(ElapsedController controller) => TextElapsed(
  controller: controller,
  plugin: defaultElapsedMs,
  formatter: CountdownFormat.msTenths,
  style: demoTextStyle,
);''',
  'since': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示从墙钟时间起算的正计时。
Widget sinceSample(DateTime since) => TextElapsed(
  since: since,
  formatter: CountdownFormat.hms,
  style: demoTextStyle,
);''',
  'limit': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示到达上限后停止的正计时。
Widget limitSample(VoidCallback onComplete) => TextElapsed(
  limit: demoShortDuration,
  formatter: CountdownFormat.ms,
  onComplete: onComplete,
  style: demoTextStyle,
);''',
  'card': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
);''',
  'dial': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示位图刻度表盘和当前时间的中心构建器。
Widget dialSample() => DialCountdown(
  to: demoDuration,
  style: const DialCountdownStyle(size: 112),
  builder: (context, parts) => Text(
    CountdownFormat.ms(parts),
    style: Theme.of(context).textTheme.titleMedium,
  ),
);''',
  'fps': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示全局显示限帧；组件的 fps 可以覆盖全局设置。
void setDemoFps(double? fps) {
  Countman.fps = fps;
}''',
  'hidden': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
);''',
  'providers': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 展示在同一个作用域里使用三个计时家族。
Widget providerSample() => const CountmanProvider(
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      TextCounter(
        to: demoCounterGoal,
        style: TextCounterStyle(textStyle: demoCompactNumberStyle),
      ),
      TextCountdown(to: demoDuration, style: demoCompactTextStyle),
      TextElapsed(style: demoCompactTextStyle),
    ],
  ),
);''',
  'theme': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
);''',
  'cache': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

/// 释放共享位图缓存，下次绘制按需重建，不清理字形缓存。
void clearDemoBitmapCaches() {
  DialCountdown.clearTickImageCache();
  FlipCardPainter.clearFaceImageCache();
}''',
  'probe': r'''import 'package:countman/countman.dart';
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

/// 并排展示多个家族时使用的紧凑数字样式。
const demoCompactNumberStyle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w600,
);

/// 并排计时组件共用的样式对象。
const demoCompactTextStyle = CountmanTextStyle(
  textStyle: demoCompactNumberStyle,
);

/// 示例共用的短时上限与隐藏计时时长。
const demoShortDuration = Duration(seconds: 8);

/// 进度演示共用的剩余时长。
const demoProgressRemaining = Duration(seconds: 40);

/// 进度示例共用的目标值。
const double demoCounterGoal = 100;

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
}''',
  'pomodoro': r'''import 'package:countman/countman.dart';
import 'package:flutter/foundation.dart';

/// 番茄钟的一个阶段（例如“专注”或“休息”）。
@immutable
class PomodoroPhase {
  /// 创建阶段；[label] 用于展示，[duration] 为该阶段时长。
  const PomodoroPhase(this.label, this.duration);

  /// 阶段名称，例如“专注”。
  final String label;

  /// 阶段时长。
  final Duration duration;
}

/// 某一时刻的番茄钟快照，由插件在显示秒变化或阶段切换时推送。
@immutable
class PomodoroSnapshot {
  /// 创建快照。
  const PomodoroSnapshot({
    required this.phase,
    required this.phaseNumber,
    required this.phaseCount,
    required this.remainingSeconds,
    required this.finished,
    required this.updates,
  });

  /// 当前阶段。
  final PomodoroPhase phase;

  /// 当前是整个流程里的第几个阶段（从 1 起）。
  final int phaseNumber;

  /// 整个流程一共有多少个阶段。
  final int phaseCount;

  /// 当前阶段剩余整秒数（向上取整，与倒计时习惯一致）。
  final int remainingSeconds;

  /// 整个流程是否已经结束。
  final bool finished;

  /// 插件到目前为止推送的更新次数，用来直观看到“按需唤醒、不逐帧运行”。
  final int updates;
}

/// 番茄钟任务：保存阶段序列与当前阶段的单调钟锚点。
class PomodoroTask extends CountmanTask {
  /// 创建任务；[phases] 为一轮的阶段序列，[rounds] 为重复轮数。
  PomodoroTask(
    super.id, {
    required this.phases,
    required this.rounds,
    required this.onChange,
  });

  /// 一轮内的阶段序列。
  final List<PomodoroPhase> phases;

  /// 重复轮数。
  final int rounds;

  /// 快照回调。
  final void Function(PomodoroSnapshot snapshot) onChange;

  /// 当前阶段在整个流程中的下标（0 起，范围 0 到 phases.length * rounds）。
  int index = 0;

  /// 当前阶段起点的单调钟微秒。
  int phaseStartMicros = 0;

  /// 暂停时冻结的剩余微秒；null 表示正在运行。
  int? frozenRemainingMicros;

  /// 上次推送时的显示秒，用于判断是否需要再次推送。
  int lastShownSeconds = -1;

  /// 上次推送时的阶段下标。
  int lastShownIndex = -1;

  /// 累计推送次数。
  int updates = 0;

  /// 整个流程的阶段总数。
  int get total => phases.length * rounds;

  /// 流程是否已经走完。
  bool get finished => index >= total;

  /// 下标对应的阶段（超出范围时取最后一个阶段）。
  PomodoroPhase phaseAt(int i) =>
      phases[(i < total ? i : total - 1) % phases.length];

  /// 是否由控制句柄暂停。
  @override
  bool get isPaused => frozenRemainingMicros != null;
}

/// 控制一个番茄钟任务的句柄，由 [PomodoroPlugin.start] 返回。
class PomodoroHandle {
  /// 创建绑定插件与任务的控制句柄。
  PomodoroHandle._(this._plugin, this._task);

  /// 拥有任务的插件。
  final PomodoroPlugin _plugin;

  /// 当前控制的任务，重播后可能替换。
  PomodoroTask _task;

  /// 暂停；已暂停或已结束时无操作。
  void pause() => _plugin._pause(_task);

  /// 继续；未暂停时无操作。
  void resume() => _plugin._resume(_task);

  /// 回到第一个阶段重新开始；流程已结束时会重新入队。
  void restart() => _task = _plugin._restart(_task);

  /// 当前是否处于暂停状态。
  bool get isPaused => _task.isPaused;
}

/// 自定义插件示例：用 [TaskQueuePlugin] 写一个番茄钟 / 间歇训练引擎。
///
/// 要点是 0.3.0 的 `tick` 新契约——每次只返回“距下次需要处理的微秒数”：
/// 一个 25 分钟的专注阶段，插件每秒只醒一次（甚至更久），其余时间调度器完全休眠，
/// 不再逐 vsync 出帧。基类 [TaskQueuePlugin] 负责任务表、并发安全和异常隔离，
/// 子类只实现 [renderInitial] / [step] / [nextWake] 三个钩子。
///
/// ```dart
/// final plugin = PomodoroPlugin();
/// Countman.use(plugin);
/// final handle = plugin.start(
///   phases: const [PomodoroPhase('专注', Duration(minutes: 25)), PomodoroPhase('休息', Duration(minutes: 5))],
///   rounds: 4,
///   onChange: (s) => debugPrint('${s.phase.label} ${s.remainingSeconds}s'),
/// );
/// ```
class PomodoroPlugin extends TaskQueuePlugin<PomodoroTask> {
  /// 创建插件；[name] 须唯一，[clockOverride] 为空时跟随 [CountmanClock.system]。
  PomodoroPlugin({String name = 'pomodoro', this.clockOverride}) : super(name);

  /// 显式指定的时钟（测试可注入 [ManualCountmanClock]）。
  final CountmanClock? clockOverride;

  /// 当前单调钟微秒；用单调钟，改系统时间不影响番茄钟。
  int get _now => (clockOverride ?? CountmanClock.system).monotonicMicros();

  /// 开始一个番茄钟并返回控制句柄。
  PomodoroHandle start({
    required List<PomodoroPhase> phases,
    int rounds = 1,
    required void Function(PomodoroSnapshot snapshot) onChange,
  }) {
    final task = PomodoroTask(
      nextId(),
      phases: phases,
      rounds: rounds,
      onChange: onChange,
    )..phaseStartMicros = _now;
    enqueue(task);
    return PomodoroHandle._(this, task);
  }

  /// 当前阶段剩余微秒。
  int _remainingOf(PomodoroTask task) {
    final frozen = task.frozenRemainingMicros;
    if (frozen != null) return frozen;
    return task.phaseAt(task.index).duration.inMicroseconds -
        (_now - task.phaseStartMicros);
  }

  /// 冻结任务当前剩余时间。
  void _pause(PomodoroTask task) {
    if (task.done || task.isPaused) return;
    task.frozenRemainingMicros = _remainingOf(task);
  }

  /// 从冻结的剩余时间恢复任务。
  void _resume(PomodoroTask task) {
    final frozen = task.frozenRemainingMicros;
    if (task.done || frozen == null) return;
    final duration = task.phaseAt(task.index).duration.inMicroseconds;
    task.phaseStartMicros = _now - (duration - frozen);
    task.frozenRemainingMicros = null;
    task.reanchor();
    ctx.requestFrame();
  }

  /// 重置已有任务，结束后则创建新任务。
  PomodoroTask _restart(PomodoroTask task) {
    if (task.done) {
      // 已结束的任务已被移出队列，重新建一个。
      final fresh = PomodoroTask(
        nextId(),
        phases: task.phases,
        rounds: task.rounds,
        onChange: task.onChange,
      )..phaseStartMicros = _now;
      enqueue(fresh);
      return fresh;
    }
    task
      ..index = 0
      ..phaseStartMicros = _now
      ..frozenRemainingMicros = null
      ..lastShownSeconds = -1
      ..lastShownIndex = -1
      ..reanchor();
    ctx.requestFrame();
    return task;
  }

  /// 推送快照；剩余秒向上取整。
  void _emit(PomodoroTask task) {
    final remaining = task.finished ? 0 : _remainingOf(task);
    final seconds = remaining <= 0
        ? 0
        : (remaining + (Duration.microsecondsPerSecond - 1)) ~/
              Duration.microsecondsPerSecond;
    task.lastShownSeconds = seconds;
    task.lastShownIndex = task.index;
    task.updates++;
    task.onChange(
      PomodoroSnapshot(
        phase: task.phaseAt(task.index),
        phaseNumber: task.index < task.total ? task.index + 1 : task.total,
        phaseCount: task.total,
        remainingSeconds: seconds,
        finished: task.finished,
        updates: task.updates,
      ),
    );
  }

  /// 首帧推送当前阶段。
  @override
  void renderInitial(PomodoroTask task) => _emit(task);

  /// 按单调钟推进阶段并仅在显示秒变化时通知。
  @override
  void step(PomodoroTask task, double dtMs) {
    // 阶段到点就顺延到下一个；起点按阶段时长累加，不累积误差。
    while (!task.finished && _remainingOf(task) <= 0) {
      task.phaseStartMicros += task.phaseAt(task.index).duration.inMicroseconds;
      task.index++;
    }
    if (task.finished) {
      _emit(task);
      task.done = true;
      return;
    }
    final seconds =
        (_remainingOf(task) + (Duration.microsecondsPerSecond - 1)) ~/
        Duration.microsecondsPerSecond;
    if (task.index != task.lastShownIndex || seconds != task.lastShownSeconds) {
      _emit(task);
    }
  }

  /// 新契约的核心：告诉调度器“多久之后再叫我”。
  /// 显示秒只在剩余降到整秒边界时才变，所以睡到下一个整秒边界即可。
  @override
  int nextWake(PomodoroTask task) {
    final remaining = _remainingOf(task);
    if (remaining <= 0) return CountmanPlugin.nextFrame;
    final untilNextSecond =
        remaining -
        ((remaining - 1) ~/ Duration.microsecondsPerSecond) *
            Duration.microsecondsPerSecond;
    // 距离更近的是“阶段结束”还是“下一个整秒”，两者都不会超过剩余时间。
    return untilNextSecond < 1 ? 1 : untilNextSecond;
  }
}
''',
};

/// 合并同一分区的示例，导入与共用常量只保留一份。
String combineSampleCode(List<String> ids) => '$samplePrelude\n\n${ids.map((id) => sampleCode[id]!.replaceFirst(samplePrelude, "").trim()).join("\n\n")}';
