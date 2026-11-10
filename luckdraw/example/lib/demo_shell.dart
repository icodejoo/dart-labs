import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luckdraw/luckdraw.dart';

import 'theme/demo_theme.dart';
import 'theme/prize_art.dart';

/// 统一示例画布边长。
const double demoSide = 300;

/// 纵向玩法的画布高度。
const double demoTall = 400;

/// 示例运动参数，覆盖加速、匀速和减速。
const LuckyMotionOptions demoMotion = LuckyMotionOptions(
  accelerationTime: Duration(milliseconds: 400),
  decelerationTime: Duration(milliseconds: 800),
);

/// 模拟服务端已返回的目标下标。
const int demoTarget = 1;

/// 服务端返回按钮定位键。
const Key serverKey = ValueKey('server-result');

/// 外部开始按钮定位键。
const Key startKey = ValueKey('start');

/// 奖品结果文本定位键。
const Key resultKey = ValueKey('result');

/// 所有演示页共用的控制面板。
class DemoShell extends StatelessWidget {
  /// 以 [title]、[game]、[phase] 和 [result] 展示本局；
  /// [start] 开始，[serverResult] 模拟服务端返回；例如 `DemoShell(...)`。
  const DemoShell(
      {super.key,
      required this.title,
      required this.game,
      required this.phase,
      required this.result,
      required this.start,
      required this.serverResult,
      this.reset});

  /// 页面标题。
  final String title;

  /// 玩法组件。
  final Widget game;

  /// 只读阶段通知。
  final ValueListenable<LuckyPhase> phase;

  /// 结算结果文本。
  final String result;

  /// 请求开始的业务操作。
  final VoidCallback start;

  /// 请求停止的业务操作。
  final VoidCallback serverResult;

  /// 恢复初始状态；为空时不显示重置按钮。
  final VoidCallback? reset;

  /// 布局在窄屏和小窗口下允许滚动。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (description, icon) = demoDescription(title);
    final wheel =
        title == '转盘' || title == 'compat 迁移' || title == 'Widget 叠加层';
    final hasResult = result.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (reset != null)
          IconButton(
              tooltip: '重置',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: reset),
        const SizedBox(width: DemoSpace.sm),
      ]),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            DemoSpace.xl, DemoSpace.sm, DemoSpace.xl, DemoSpace.xl),
        child: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(DemoSpace.sm),
                  decoration: BoxDecoration(
                      color: scheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(DemoSpace.md)),
                  child: Icon(icon, color: scheme.primary, size: 22)),
              const SizedBox(width: DemoSpace.md),
              Expanded(
                  child: Text(description,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant))),
            ]),
            const SizedBox(height: DemoSpace.lg),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: theme.brightness == Brightness.dark
                        ? [DemoPalette.nightCard, const Color(0xFF303454)]
                        : [const Color(0xFFEFEEFF), const Color(0xFFE5EAFF)]),
                borderRadius: BorderRadius.circular(DemoSpace.stageRadius),
                border: Border.all(color: scheme.primary.withAlpha(25)),
              ),
              child: CustomPaint(
                foregroundPainter: DemoStagePainter(wheel: wheel),
                child: Padding(
                  padding: const EdgeInsets.all(DemoSpace.lg),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: demoSide),
                      child: Center(child: game)),
                ),
              ),
            ),
            const SizedBox(height: DemoSpace.lg),
            DemoCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  ValueListenableBuilder<LuckyPhase>(
                    valueListenable: phase,
                    builder: (_, value, child) => Row(children: [
                      Container(
                          width: DemoSpace.sm,
                          height: DemoSpace.sm,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: value == LuckyPhase.settled
                                  ? DemoPalette.mint
                                  : scheme.primary)),
                      const SizedBox(width: DemoSpace.sm),
                      Expanded(
                          child: Text('阶段：${value.name}',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant))),
                      Text('GOOD LUCK',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary, letterSpacing: 1.5)),
                    ]),
                  ),
                  const SizedBox(height: DemoSpace.md),
                  Row(children: [
                    Expanded(
                        child: FilledButton.icon(
                            key: startKey,
                            onPressed: start,
                            icon:
                                const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('开始'))),
                    const SizedBox(width: DemoSpace.sm),
                    Expanded(
                        child: OutlinedButton(
                            key: serverKey,
                            onPressed: serverResult,
                            child: const Text('服务端返回'))),
                  ]),
                  const SizedBox(height: DemoSpace.sm),
                  Text('先开始，再模拟服务端返回；也可点击玩法中的开始区域。',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant, height: 1.5)),
                ])),
            const SizedBox(height: DemoSpace.md),
            Semantics(
                liveRegion: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(DemoSpace.radius),
                  onTap: hasResult
                      ? () => showDemoResult(context, result.trim())
                      : null,
                  child: DemoCard(
                      child: Row(children: [
                    Icon(
                        hasResult
                            ? Icons.celebration_rounded
                            : Icons.card_giftcard_rounded,
                        color: scheme.primary),
                    const SizedBox(width: DemoSpace.md),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(hasResult ? '本次好运' : '下一份惊喜，等你开启',
                              style: theme.textTheme.labelLarge),
                          Text(result,
                              key: resultKey,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: scheme.primary)),
                        ])),
                    if (hasResult) const Icon(Icons.expand_less_rounded),
                  ])),
                )),
          ]),
        )),
      )),
    );
  }
}
