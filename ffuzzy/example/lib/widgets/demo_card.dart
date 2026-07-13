// Reusable card: method name + a one-line Dart call snippet + live result.
//
// 可复用卡片：方法名 + 一行 Dart 调用代码片段 + 实时结果。
import 'package:flutter/material.dart';

class DemoCard extends StatelessWidget {
  const DemoCard({
    super.key,
    required this.id,
    required this.title,
    required this.code,
    required this.child,
    this.note,
  });

  /// Composite `tab.card` identifier, e.g. `'2.5'` for tab 2's 5th card.
  ///
  /// 组合 `tab.card` 标识，例如 `'2.5'` 表示 tab 2 的第 5 张卡。
  final String id;
  final String title;
  final String code;
  final Widget child;

  /// Optional short caveat shown under the code snippet (e.g. a gotcha worth
  /// flagging, such as an auto-scaled default).
  ///
  /// 可选的简短提示，展示在代码片段下方（比如值得提醒的坑，如某个自动缩放的
  /// 默认值）。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(id,
                      style: TextStyle(
                          fontSize: 10, color: theme.colorScheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                code,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note!,
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 6),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

/// A grid of [DemoCard]s, sized for a desktop window.
///
/// 一组 [DemoCard] 组成的网格布局，适配桌面窗口宽度。
class DemoGrid extends StatelessWidget {
  const DemoGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.15,
      children: children,
    );
  }
}

/// Renders a `List<FuzzyHit<String>>` (or raw `List<String>`) as a compact
/// bullet list, capped so a card never overflows.
///
/// 把 `List<FuzzyHit<String>>`（或裸 `List<String>`）渲染成紧凑的项目符号列表，
/// 限制条数避免卡片溢出。
class ResultList extends StatelessWidget {
  const ResultList(this.lines, {super.key, this.max = 5});
  final List<String> lines;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Text('(no hits)', style: TextStyle(color: Colors.grey));
    }
    final shown = lines.take(max).toList();
    final extra = lines.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in shown)
          Text('• $l', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (extra > 0)
          Text('… +$extra more', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
