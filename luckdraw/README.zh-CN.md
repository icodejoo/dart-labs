# luckdraw

**[▶ 在线 Demo](https://icodejoo.github.io/dart-labs/luckdraw/)** — 八种玩法，浏览器直接试玩。

> 状态：0.1.1，已发布到 pub.dev。
>
> English: [README.md](./README.md)
>
> **非官方移植。** luckdraw 将 [lucky-canvas](https://github.com/buuing/lucky-canvas)
>（Apache-2.0）移植到 Flutter，与其作者无关联，也未获其背书。
> 上游署名见 [NOTICE](NOTICE)。

Flutter 抽奖工具包：大转盘、九宫格、老虎机、拉霸机、扭蛋机、数字转盘、抽签、大乐透，渲染核心可插拔。

**状态：0.1.1，已发布到 pub.dev。** 仓库门禁通过：analyze 0 issue、
1051 条测试通过（0 跳过）、`lib/` 行覆盖6792/6792=100%，格式、imports、
静态/运行 JSON 验收及 parity manifest 校验通过。Windows 与安卓集成各33/33；
本地 Flutter 3.24.5 / Dart 3.5.4 analyze 0 issue、非 golden 951 条通过；
Web/APK 摇树各十探针零泄漏。真机性能验收**未完全通过**；阴影对照保留差异与老虎机裁剪缺样本。
Linux golden、远程 CI 与真实发布仍未验证，详见
[发布检查清单](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/RELEASE_CHECKLIST.md)。
两份 README 的12个 Dart 块保留 REL/B17b 已在临时 Flutter 工程分析为0 issue的签名。

## 截图

以下为本项目的「示例工程渲染图」，不是上游演示截图，也不代表逐像素对齐。以浅色主题展示：

![首页示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/home-light.png)

![转盘示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/wheel-light.png)

![九宫格示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/grid-light.png)

![老虎机示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/slot-light.png)

![拉霸机示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/lever-light.png)

![扭蛋机示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/capsule-light.png)

![数字转盘示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/number_wheel-light.png)

![大乐透示例工程渲染图](https://raw.githubusercontent.com/icodejoo/dart-labs/main/luckdraw/docs/example_audit/after/lotto-light.png)

`docs/` 已从发布包排除，因此图片使用仓库 raw 绝对地址；需要对应文件已在仓库 `main`
分支可用，本轮尚未发布这些变更。本地原图位于 `docs/example_audit/after/`，
完整审计共45张 PNG，约1.26MB。

## 特性

当前实现包括：

- 不可变的类型化配置、Controller、结果回调和阶段通知。
- 指定奖品下标、按权重选奖、异步等待服务端结果。
- 默认 Canvas 2D 渲染，静态内容缓存为 `ui.Picture`，每帧只做变换与回放。
- 有效时间轴：暂停恢复、后台冻结、不同刷新率下保持转速一致。
- 玩法、渲染器、缓动、选奖策略独立，显式传入；无第三方运行时依赖。
- 独立的 lucky-canvas JSON 迁移层，可选严格对照预设。

拉霸机、扭蛋机、数字转盘、抽签、大乐透是新增设计，上游没有对应玩法可做对照。
动画默认采用确定性轨迹；扭蛋机与大乐透可选开启内置物理碰撞模式（`physics: LuckyPhysics()`），不引入第三方物理引擎；3D 渲染只预留扩展路径。

## 安装

首发后的预期依赖写法：

```yaml
dependencies:
  flutter:
    sdk: flutter
  luckdraw: ^0.1.0
```

首发前请以 pub.dev 的实际发布版本和可用状态为准；此片段不表示 `0.1.0` 现在已经可用。
当前清单声明 Dart `^3.5.0`、Flutter `>=3.24.0`。

## 快速开始

快速开始的每段示例可单独作为使用本地包的 Flutter 应用 `lib/main.dart`。
示例只用文字，无需图片资源或服务端，并自行释放 Controller。
先开始，再点「停止」，请求减速到第二个奖品（下标从零开始，目标为 `1`）。
停止请求被接受后仍需完成动画，结果由 `onEnd` 返回。

### 大转盘

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/wheel.dart';

void main() => runApp(const MaterialApp(
  home: Scaffold(body: Center(child: WheelDemo())),
));

class WheelDemo extends StatefulWidget {
  const WheelDemo({super.key});
  @override
  State<WheelDemo> createState() => _WheelDemoState();
}

class _WheelDemoState extends State<WheelDemo> {
  final _controller = WheelController();
  static const _config = WheelConfig(
    prizes: [
      WheelPrize(background: LuckyFill.color(Color(0xFFE9E8FE)),
        texts: [LuckyText('谢谢参与')], weight: 3),
      WheelPrize(background: LuckyFill.color(Color(0xFFB8C5F2)),
        texts: [LuckyText('礼品')], weight: 1),
    ],
    buttons: [
      WheelButton(radius: LuckyLength.percent(30), pointer: true,
        background: LuckyFill.color(Color(0xFF617DF2)),
        texts: [LuckyText('开始', top: LuckyLength.px(-10))]),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      LuckyWheel(config: _config, controller: _controller,
        width: 300, height: 300,
        onStart: () { _controller.play(); },
        onEnd: (result) => debugPrint('转盘：$result')),
      TextButton(onPressed: () { _controller.stop(1); },
        child: const Text('停止')),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 九宫格

`stop` 下标取自奖品列表顺序；`x`、`y` 决定格子位置。
下方八个奖品按顺时针围住中心按钮。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';

void main() => runApp(const MaterialApp(
  home: Scaffold(body: Center(child: GridDemo())),
));

class GridDemo extends StatefulWidget {
  const GridDemo({super.key});
  @override
  State<GridDemo> createState() => _GridDemoState();
}

class _GridDemoState extends State<GridDemo> {
  final _controller = GridController();
  static const _config = GridConfig(rows: 3, cols: 3,
    prizes: [
      GridPrize(x: 0, y: 0, texts: [LuckyText('A')]),
      GridPrize(x: 1, y: 0, texts: [LuckyText('B')]),
      GridPrize(x: 2, y: 0, texts: [LuckyText('C')]),
      GridPrize(x: 2, y: 1, texts: [LuckyText('D')]),
      GridPrize(x: 2, y: 2, texts: [LuckyText('E')]),
      GridPrize(x: 1, y: 2, texts: [LuckyText('F')]),
      GridPrize(x: 0, y: 2, texts: [LuckyText('G')]),
      GridPrize(x: 0, y: 1, texts: [LuckyText('H')]),
    ],
    buttons: [GridButton(x: 1, y: 1, texts: [LuckyText('开始')])],
    activeStyle: LuckyCellStyle(
      background: LuckyFill.color(Color(0xFFFFCE98))),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      LuckyGrid(config: _config, controller: _controller,
        width: 300, height: 300,
        onStart: () { _controller.play(); },
        onEnd: (result) => debugPrint('九宫格：$result')),
      TextButton(onPressed: () { _controller.stop(1); },
        child: const Text('停止')),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 老虎机

老虎机没有内置开始按钮，也没有 `onStart`，需要外部控件驱动。
`stop(1)` 让所有列停在奖品 `1`；`stopEach([0, 1, 2])` 可分别指定各列。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

void main() => runApp(const MaterialApp(
  home: Scaffold(body: Center(child: SlotDemo())),
));

class SlotDemo extends StatefulWidget {
  const SlotDemo({super.key});
  @override
  State<SlotDemo> createState() => _SlotDemoState();
}

class _SlotDemoState extends State<SlotDemo> {
  final _controller = SlotController();
  static const _config = SlotConfig(
    prizes: [
      SlotPrize(texts: [LuckyText('A')]),
      SlotPrize(texts: [LuckyText('B')]),
      SlotPrize(texts: [LuckyText('C')]),
    ],
    reels: [SlotReel(order: [0, 1, 2]), SlotReel(), SlotReel(direction: -1)],
    options: SlotOptions(mode: SlotMode.vertical, colSpacing: 5, cellAspectRatio: 0.8),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      LuckySlotMachine(config: _config, controller: _controller,
        width: 300, height: 180,
        onEnd: (result) => debugPrint('老虎机：$result')),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(onPressed: () { _controller.play(); },
          child: const Text('开始')),
        TextButton(onPressed: () { _controller.stop(1); },
          child: const Text('停止')),
      ]),
    ],
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 拉霸机

老虎机的拉杆版本：拖动拉杆开始，再用 `stopEach` 逐轴停下。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

/// 拉霸机；拖动拉杆开始，再由外部命令错峰停轮。
class LeverDemo extends StatefulWidget {
  /// 创建拉霸机示例。
  const LeverDemo({super.key});

  /// 创建状态。
  @override
  State<LeverDemo> createState() => _LeverDemoState();
}

class _LeverDemoState extends State<LeverDemo> {
  final _controller = SlotController();
  static const _config = SlotConfig(
    prizes: [
      SlotPrize(texts: [LuckyText('7')]),
      SlotPrize(texts: [LuckyText('BAR')]),
      SlotPrize(texts: [LuckyText('★')]),
    ],
    reels: [SlotReel(), SlotReel(), SlotReel()],
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyLeverSlotMachine(
            config: _config,
            controller: _controller,
            width: 300,
            height: 180,
            onPull: () => debugPrint('Lever pulled'),
            onEnd: (result) => debugPrint('Lever: ${result.indices}'),
          ),
          TextButton(
            // 拉杆触发 play 后，由服务端结果决定每个转轴停在哪个奖品。
            onPressed: () {
              _controller.stopEach([0, 0, 0]);
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 扭蛋机

点击旋钮开始，`stop(1)` 掉出第 1 个胶囊。`physics` 选项切换到内置碰撞模式，去掉即为确定性动画。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/capsule.dart';

/// 扭蛋机；点击旋钮开始，服务端结果到达后掉出指定胶囊。
class CapsuleDemo extends StatefulWidget {
  /// 创建扭蛋机示例。
  const CapsuleDemo({super.key});

  /// 创建状态。
  @override
  State<CapsuleDemo> createState() => _CapsuleDemoState();
}

class _CapsuleDemoState extends State<CapsuleDemo> {
  final _controller = CapsuleController();
  static const _config = CapsuleConfig(
    prizes: [
      CapsulePrize(
        topFill: LuckyFill.color(Color(0xFFFF8A65)),
        bottomFill: LuckyFill.color(Color(0xFFFFF3E0)),
        texts: [LuckyText('Gift')],
        weight: 1,
      ),
      CapsulePrize(
        topFill: LuckyFill.color(Color(0xFF64B5F6)),
        bottomFill: LuckyFill.color(Color(0xFFFFF3E0)),
        texts: [LuckyText('Grand')],
        weight: 1,
      ),
    ],
    // 打开碰撞模式：胶囊从顶部落下，与球壁、拨杆碰撞；删掉这行即为确定性动画。
    options: CapsuleOptions(physics: LuckyPhysics()),
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyCapsuleMachine(
            config: _config,
            controller: _controller,
            width: 300,
            height: 400,
            onStart: () {
              _controller.play();
            },
            onEnd: (result) => debugPrint('Capsule: ${result.index}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stop(1);
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 数字转盘

按号码而不是下标停下：`stopNumber(8)` 让球落进 8 号袋。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/number_wheel.dart';

/// 数字转盘；按号码而不是下标停下。
class NumberWheelDemo extends StatefulWidget {
  /// 创建数字转盘示例。
  const NumberWheelDemo({super.key});

  /// 创建状态。
  @override
  State<NumberWheelDemo> createState() => _NumberWheelDemoState();
}

class _NumberWheelDemoState extends State<NumberWheelDemo> {
  final _controller = NumberWheelController();
  // 0 到 12 共 13 个号码袋。
  static final _config = NumberWheelConfig.range(0, 12);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyNumberWheel(
            config: _config,
            controller: _controller,
            width: 300,
            height: 300,
            onStart: () {
              _controller.play();
            },
            onEnd: (result) => debugPrint('Number: ${result.prize?.number}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stopNumber(8);
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 抽签

摇签筒、出签、展开签文；`weight` 决定默认抽取概率，`stop(0)` 指定第 0 支签。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/lots.dart';

/// 抽签；摇签筒、出签、展开签文。
class LotsDemo extends StatefulWidget {
  /// 创建抽签示例。
  const LotsDemo({super.key});

  /// 创建状态。
  @override
  State<LotsDemo> createState() => _LotsDemoState();
}

class _LotsDemoState extends State<LotsDemo> {
  final _controller = LotsController();
  static const _config = LotsConfig(sticks: [
    LotsStick(label: 'Great luck', weight: 1),
    LotsStick(label: 'Good luck', weight: 2),
    LotsStick(label: 'Small luck', weight: 3),
  ]);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyLots(
            config: _config,
            controller: _controller,
            width: 300,
            height: 400,
            onStart: () {
              _controller.play();
            },
            onEnd: (result) => debugPrint('Lots: ${result.prize?.label}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stop(0);
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### 大乐透

`LottoConfig.superLotto` 是 5 + 2 预设。`stopWith(LottoDraw(...))` 套用服务端摇出的整组号码，`onBallDrawn` 逐球回调。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/lotto.dart';

/// 大乐透；多个号码池逐球摇出，可由服务端指定整组号码。
class LottoDemo extends StatefulWidget {
  /// 创建大乐透示例。
  const LottoDemo({super.key});

  /// 创建状态。
  @override
  State<LottoDemo> createState() => _LottoDemoState();
}

class _LottoDemoState extends State<LottoDemo> {
  final _controller = LottoController();
  // 5 + 2 的超级大乐透预设；options 里的 physics 打开碰撞模式。
  static final _config = LottoConfig.superLotto(
    options: const LottoOptions(physics: LuckyPhysics()),
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyLotto(
            config: _config,
            controller: _controller,
            width: 300,
            height: 400,
            onStart: () {
              _controller.play();
            },
            onBallDrawn: (pool, number) => debugPrint('Pool $pool: $number'),
            onEnd: (result) => debugPrint('Lotto: ${result.draw?.numbers}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stopWith(const LottoDraw([
                [7, 1, 18, 25, 35],
                [12, 3],
              ]));
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

## Controller

Controller 需先挂到玩法 Widget，或显式挂接无头时钟。
命令返回的布尔值表示是否接受请求。例如一局进行中再次 `play()` 返回 `false`；
加速期收到的停止请求会等到减速阶段处理。

| API | 用法 |
| --- | --- |
| `play()` | 从空闲、已结束或待机慢转开始一局。 |
| `stop(index)` | 指定从零开始的奖品下标，不走权重。 |
| `stop()` | 交给选奖器；默认是 `WeightedPrizePicker`。 |
| `pause()` / `resume()` | 冻结/恢复有效时间，不重置本局。 |
| `reset()` | 回到空闲，位置归零。 |
| `cancel()` | 作废本局；开始减速后忽略。 |
| `phase.value` / `phaseChanges` | 读取当前阶段 / 订阅惰性创建的广播流。 |
| `frameListenable` / `frame` | 监听动画帧；帧快照对象会复用，只读使用。 |
| `lastResult` | 读取上一局结果，也可用 Widget 的 `onEnd` 接收。 |

按概率抽奖时，先用 `play()` 开始新一局，再调用无参 `stop()`。
转盘示例的权重是 `3` 和 `1`，对应概率为 `3/4` 和 `1/4`。
空值、非正数、NaN 权重不参与选奖；没有有效权重时作废，不会自动均匀抽取。
默认也排除已禁用的奖品。九宫格和老虎机示例用指定下标，不需要权重。

等待服务端结果时，把下面方法放进上方 `_WheelDemoState`。
传入自己的请求函数，返回当前奖品列表的有效下标；请求结束前保持列表不变，避免并发请求。

```dart
Future<void> drawFromServer(Future<int> Function() requestIndex) async {
  if (!_controller.play()) return;
  try {
    final index = await requestIndex();
    if (!mounted) return;
    _controller.stop(index);
  } catch (_) {
    if (mounted) _controller.cancel();
    rethrow;
  }
}
```

也可用 `WheelController.playUntil(resolveIndex, minSpinDuration: ...)` 包装开始、
异步选奖和停止，返回 `Future<LuckyResult<WheelPrize>>`。
其 resolver 签名为 `FutureOr<int?> Function()`；老虎机则解析全部列的 `List<int>?`。

监听状态流时，把下面方法放进 `_WheelDemoState`，传入一个代表监听期限的 Future，
结束时取消订阅。也可用 Widget 的 `onPhaseChanged`，由 Widget 生命周期管理回调。

```dart
Future<void> observePhases(Future<void> untilDone) async {
  final subscription = _controller.phaseChanges.listen((phase) {
    debugPrint('阶段：$phase');
  });
  try {
    await untilDone;
  } finally {
    await subscription.cancel();
  }
}
```

## 按需引入

下列路径均以 `package:luckdraw/` 为前缀。玩法入口同时导出 `luckdraw.dart` 的核心用户 API；
核心入口本身不导出玩法 Widget。

| 入口 | 用途 |
| --- | --- |
| `wheel.dart` | `LuckyWheel`、转盘配置与 Controller。 |
| `grid.dart` | `LuckyGrid`、九宫格配置与 Controller。 |
| `slot.dart` | `LuckySlotMachine` 及拉霸变体 `LuckyLeverSlotMachine`。 |
| `capsule.dart` | `LuckyCapsuleMachine`、扭蛋配置与 Controller。 |
| `number_wheel.dart` | `LuckyNumberWheel`、号码格与 Controller。 |
| `lots.dart` | `LuckyLots`、签条与 Controller。 |
| `lotto.dart` | `LuckyLotto`、号码池、抽样与 Controller。 |
| `compat.dart` | JSON 转换与 CSS 解析，不重新导出玩法。 |
| `extend.dart` | 自定义玩法/渲染 SPI、时钟与核心用户 API，直接从 `src/core/` 导出。 |
| `testing.dart` | `ManualLuckyClock`、`SequenceRandom`、`LuckyFrameRecorder`。 |

设计上 core 不依赖玩法，玩法互不依赖，compat 只在显式引入时使用。
没有全局自动注册；可选注册表由调用方创建和维护。
Dart 按声明的可达性摇树，重新导出 core 不会保留所有核心类型。
[ARCHITECTURE §17](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/ARCHITECTURE.md#17-摇树设计需求-6) 记录了真实包全部十个探针的 Web 构建及
源码/符号检查通过，体积预算已按实测回填。APK 后端只解析已有体积报告，CI 作业停用，待补真实构建。

## 从 lucky-canvas 迁移

按玩法选择转换函数，没有通用 JSON 分派器：

| 转换函数 | 转换后的配置 |
| --- | --- |
| `wheelFromLuckyCanvasConfig` | 大转盘 |
| `gridFromLuckyCanvasConfig` | 九宫格 |
| `slotFromLuckyCanvasConfig` | 老虎机 |

```dart
import 'package:flutter/widgets.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

Widget migratedWheel(Map<String, Object?> json) {
  final converted = wheelFromLuckyCanvasConfig(json,
    options: LuckyCanvasCompatOptions.strictUpstream());
  for (final warning in converted.warnings) {
    debugPrint(warning.toString());
  }
  return LuckyWheel(config: converted.config,
    width: converted.width, height: converted.height,
    alignment: Alignment.topLeft);
}
```

JSON 未指定尺寸时，父容器需提供有界约束。
普通迁移可改用 `const LuckyCanvasCompatOptions(remBase: 16)`，采用默认行为。
CSS 字符串只在 compat 解析；类型化配置使用 `Color`、`LuckyFill` 和逻辑像素，
支持的字段可用 `LuckyLength.px/percent`。

1:1 对照基线来自 npm lucky-canvas `1.7.26`，由 SHA-256 锁定，源码参照见 [NOTICE](NOTICE)。
`strictUpstream()` 选择 `LuckyTimebase.frame` 和 `UpstreamStopSolver`；受控对照还需相同随机序列、字体与资源。
16例共6720帧数值经已记录映射全部精确相等，关键帧按 standard/text-heavy/edge-aa 分层容差通过，
具体上限见 [TEST_STRATEGY §6.5](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/TEST_STRATEGY.md#65-容差与已知差异)。
默认模式采用 `LuckyTimebase.time` 和 `MonotonicStopSolver`。有意差异主要包括：

- 防止停止倒转/零位移卡住，保护非法输入，限制后台恢复的时间跳变。
- 图片渐进显示、错误和回退回调，配置与尺寸受控更新。
- 文字按 Unicode 码点拆分；Flutter 的字体、抗锯齿、阴影存在平台差异。
- `onEnd` 在 settled 当帧触发，比上游早一帧；老虎机减速首帧保留起始滚动量。
- 老虎机只画可见窗口、按列裁剪，不拼超长离屏图。
- `stopEach` 长度错误时显式抛错；不移植 DOM/平台壳，不兼容原图片 formatter 的源码签名。

严格模式仍保留已记录的修复与偏离，不会复刻全部上游错误。
完整差异和对照排除项见 [FIDELITY §8](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/FIDELITY.md#8-偏离与疑点清单)，
规避方案的调研依据见 [UPSTREAM_ISSUES](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/UPSTREAM_ISSUES.md)。
新增玩法单独验收；大乐透预设为前区 35 选 5、后区 12 选 2，各池无放回抽样。
组件只负责动画展示，不涉及真实彩票业务。

## 扩展

通过 `extend.dart` 实现自定义 `LuckyGame`、`LuckyRenderer`，再显式传入。
渲染器读取布局与帧数据；`LuckyEasing` 和 `PrizePicker` 分别替换缓动与选奖策略。
默认后端使用 Canvas，自定义后端可以返回其它 Widget。
下面的示例只替换转盘的渲染器，玩法逻辑和 Controller 保持不变。

```dart
import 'package:flutter/material.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

/// 自定义渲染后端：不画 Canvas，只用 Text 显示当前指针指向的奖品下标。
final class IndexRenderer extends LuckyRenderer<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 创建渲染后端。
  const IndexRenderer();

  /// 读取布局和逐帧数据，返回任意 Widget。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
      Center(child: Text('pointer: ${data.frame.pointerIndex}'));
}

/// 把自定义渲染后端显式传给转盘；玩法逻辑和控制器保持不变。
Widget customWheel(WheelController controller, WheelConfig config) =>
    LuckyWheel(
      config: config,
      controller: controller,
      renderer: const IndexRenderer(),
    );
```

扩展契约见 [ARCHITECTURE §6](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/ARCHITECTURE.md#6-扩展机制需求-1需求-6-7)。

## 测试

`testing.dart` 提供 `ManualLuckyClock`（手动推进时间）、`SequenceRandom`（重放固定随机数）和
`LuckyFrameRecorder`（记录帧）。Controller 可以不挂 Widget 无头运行：

```dart
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

/// 无 Widget 的确定性测试；用手动时钟推进动画，用固定随机序列选奖。
///
/// 返回结算后的奖品下标；没有结果时为 null。
int? runHeadlessWheel() {
  final clock = ManualLuckyClock();
  final controller = WheelController(random: SequenceRandom([0.5]));
  controller.attachHeadless(
    clock: clock,
    config: const WheelConfig(prizes: [
      WheelPrize(texts: [LuckyText('A')]),
      WheelPrize(texts: [LuckyText('B')]),
      WheelPrize(texts: [LuckyText('C')]),
    ]),
  );
  controller.play();
  controller.stop(2);
  // 每帧 16ms；到达 settled 即停止推进。
  while (controller.phase != LuckyPhase.settled) {
    clock.advanceFrames(1);
  }
  final index = controller.lastResult!.index;
  controller.dispose();
  clock.dispose();
  return index;
}
```

## 性能

STEADY（2026-11-11），仅一台 vivo V2417：带打点复测后grid/slot/lotto仍失败，lots本轮三轮通过；wheel进程/UI+platform/Raster CPU中位数39.291%/14.931%/18.299%。lotto准备复用候选未显示稳定净收益，已回滚。见[STEADY报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/steady/REPORT.md)，下文INSTR/MET2保留历史身份。

INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。

见[INSTR第五轮报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending2/REPORT.md)。下文DEVFIN/MET2是历史记录；本批仅上述范围更新，未承诺性能全通过。

DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：grid_steady：失败；slot_raster：失败；lots_shaking：不确定；lotto_draw：失败。冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。

详见[本次报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/pending/REPORT.md)。全部持续动画窗口的交付结果与每轮硬门禁分别列出；CPU缺测与driver失败未隐去。

以下为MET2历史基线与规则，当前复测四项以DEVFIN为准；其余场景没有重跑。

新默认`LuckyCacheMode.auto`对支持的运动段使用受限位图、静止时矢量回放；严格上游对照保留picture。

MET2（2026-11-10）纯离线复算：**帧交付完整（全部130个窗口约60fps，59.829927–60.176516，无真实丢帧，按timeline交付口径）；偶发窗口的Raster时间被vsync背压污染且与绘制内容无关（参照方块同样出现）；按真机实测标定了首版回归预算。** 不是性能全部达标：1项满足有效目标（memory，RSS沿用FIN口径）、5场景已标定但未达最初设计目标、3场景失败、1场景不确定、1首帧信息项。首帧与进程级CPU待下次真机会话标定；性能结论基于单台设备vivo V2417（Android 16）三轮数据，不是跨设备保证。PERF五场景与DEV其余场景沿用MET/FIN身份，并非同一APK全量重测。现有timeline不等于独立面板呈现测量；污染窗口无法测量纯绘制成本。

回归结果：memory满足有效RSS目标；wheel、slot_steady、lever、capsule、number_wheel已按实测标定，但未达最初设计目标；grid、slot_raster、lotto因帧预算余量失败，lots因Raster不稳定而不确定。硬门禁每个未污染窗口合计P99≤12ms且UI P99≤4ms，实测超限分别为grid 12.231ms、slot_raster 16.905ms、lotto 12.229ms；lotto UI P99达4.386ms。

以下为未达最初设计目标的完整清单（首帧40.378ms仍为信息项）：

| 未达最初设计目标的场景 | 指标与差距（实测中位数/最初目标−1） |
| --- | --- |
| wheel_steady | Raster均值 +1.99% |
| grid_steady | UI均值 +70.72%、UI P90 +18.67%、Raster均值 +37.49% |
| slot_steady | UI均值 +35.76% |
| slot_raster | UI均值 +6.41% |
| lever_steady | UI均值 +39.99%、UI P90 +4.80% |
| capsule_mixing | UI均值 +10.27% |
| number_wheel_spin | UI均值 +13.57% |
| lots_shaking | UI均值 +37.82%、UI P90 +1.20% |
| lotto_draw | UI均值 +47.92%、UI P90 +10.75% |

比例稳定性使用绝对容差1个百分点，小耗时使用0.15ms，其余相对极差30%；正常回归仅比较冻结预算。RSS仍为五次循环、预热仅信息、后四次净增长≤1.5MiB。CPU忙占比仅由帧耗时推算，不是进程CPU实测。

见[第二轮度量修正报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/docs/METRIC_FIX_REPORT.md)与[MET2逐指标报告](https://github.com/icodejoo/dart-labs/blob/main/luckdraw/tool/bench/results/met2/REPORT.md)。

## 许可证

[Apache-2.0](LICENSE)。基于 Li Dong Qi（ldq）的 lucky-canvas，保留上游 2021 年版权署名；
luckdraw 版权为 2026 codejoo。上游声明须按 [NOTICE](NOTICE) 保留。
