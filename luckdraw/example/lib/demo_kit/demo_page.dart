import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'demo_app.dart';
import 'i18n.dart';

/// 统一的页面标题、简介与分区容器。
class DemoPage extends StatelessWidget {
  /// 创建可滚动的演示页面。
  const DemoPage({
    super.key,
    required this.title,
    required this.description,
    required this.sections,
  });

  /// 页面标题。
  final String title;

  /// 页面的一两句介绍。
  final String description;

  /// 页面分区列表。
  final List<Widget> sections;

  /// 构建居中且限制宽度的页面。
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DemoTokens.maxWidth),
            child: Padding(
              padding: const EdgeInsets.all(DemoTokens.padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: DemoTokens.tinyGap),
                  Text(description),
                  const SizedBox(height: DemoTokens.sectionGap),
                  for (final section in sections)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: DemoTokens.sectionGap),
                      child: section,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 带说明、演示和默认折叠代码的分区。
class DemoSection extends StatelessWidget {
  /// 创建演示分区；代码展开后占据整个分区宽度。
  const DemoSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.code,
  });

  /// 分区标题。
  final String title;

  /// 可选说明。
  final String? subtitle;

  /// 演示内容，通常使用 DemoGrid。
  final Widget child;

  /// 完整的可复制代码。
  final String? code;

  /// 构建分区标题、演示与代码。
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: DemoTokens.tinyGap),
            Text(subtitle!),
          ],
          const SizedBox(height: DemoTokens.gap),
          child,
          if (code != null) CodeBlock(code: code!),
        ],
      );
}

/// 网格单元；span 为零表示跨整行，正数为占据的列数。
class DemoGridItem {
  /// 创建一个网格单元。
  const DemoGridItem({required this.child, this.span = 1}) : assert(span >= 0);

  /// 单元内容。
  final Widget child;

  /// 列跨度，零为整行。
  final int span;
}

/// 根据实际可用宽度分列并将同一行卡片拉齐的响应式网格。
class DemoGrid extends StatelessWidget {
  /// 创建网格；大演示使用 span: 0。
  const DemoGrid({super.key, required this.children});

  /// 网格中的演示单元。
  final List<DemoGridItem> children;

  /// 计算手机、平板、桌面与超宽内容区域的列数。
  static int columnsFor(double width) => width < DemoTokens.tabletBreakpoint
      ? 1
      : width < DemoTokens.desktopBreakpoint
          ? 2
          : width < DemoTokens.wideBreakpoint
              ? 3
              : 4;

  /// 将单元按列跨度排列成等高行。
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = columnsFor(constraints.maxWidth);
          final rows = <List<DemoGridItem>>[];
          var row = <DemoGridItem>[];
          var used = 0;
          for (final item in children) {
            final span =
                item.span == 0 ? columns : math.min(item.span, columns);
            if (used + span > columns && row.isNotEmpty) {
              rows.add(row);
              row = [];
              used = 0;
            }
            row.add(item);
            used += span;
            if (used == columns) {
              rows.add(row);
              row = [];
              used = 0;
            }
          }
          if (row.isNotEmpty) rows.add(row);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: DemoTokens.gap),
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: rows[i].any((item) => item.span == 0)
                          ? double.infinity
                          : columns * DemoTokens.cardMaxWidth +
                              (columns - 1) * DemoTokens.gap,
                    ),
                    child: _EqualHeightRow(
                      columns: columns,
                      spans: [
                        for (final item in rows[i])
                          item.span == 0
                              ? columns
                              : math.min(item.span, columns),
                      ],
                      children: [for (final item in rows[i]) item.child],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      );
}

/// 通过真实布局测量同一行，避免 SwitchListTile 等控件的固有高度误差。
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  /// 创建一行等高单元。
  const _EqualHeightRow({
    required this.columns,
    required this.spans,
    required super.children,
  });

  /// 当前网格列数。
  final int columns;

  /// 每个子项所占的列数。
  final List<int> spans;

  /// 创建测量行的渲染对象。
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _EqualHeightRender(columns, spans);

  /// 更新响应式列数与跨度。
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _EqualHeightRender renderObject,
  ) {
    renderObject.configure(columns, spans);
  }
}

/// 保存网格单元绘制偏移与相邻节点。
class _GridParentData extends ContainerBoxParentData<RenderBox> {}

/// 两次真实布局让卡片在不裁切控件的情况下共享行高。
class _EqualHeightRender extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  /// 创建带列数与跨度的布局对象。
  _EqualHeightRender(this._columns, this._spans);

  /// 当前列数。
  int _columns;

  /// 每个单元占据的列数。
  List<int> _spans;

  /// 更新布局配置并请求重新测量。
  void configure(int columns, List<int> spans) {
    _columns = columns;
    _spans = spans;
    markNeedsLayout();
  }

  /// 为子项安装容器偏移数据。
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  /// 根据列跨度计算包含列间隙的准确宽度。
  double _width(int index) =>
      (constraints.maxWidth + DemoTokens.gap) / _columns * _spans[index] -
      DemoTokens.gap;

  /// 先测自然高度，再以最高单元为准对齐整行。
  @override
  void performLayout() {
    var height = 0.0;
    var child = firstChild;
    var index = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: _width(index)),
        parentUsesSize: true,
      );
      height = math.max(height, child.size.height);
      child = childAfter(child);
      index++;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
    child = firstChild;
    index = 0;
    var x = 0.0;
    while (child != null) {
      final width = _width(index);
      child.layout(
        BoxConstraints(minWidth: width, maxWidth: width, minHeight: height),
        parentUsesSize: true,
      );
      (child.parentData! as _GridParentData).offset = Offset(x, 0);
      x += width + DemoTokens.gap;
      child = childAfter(child);
      index++;
    }
  }

  /// 绘制一行中所有已定位子项。
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  /// 将点击交给相应卡片控件。
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// 紧凑演示卡片，截断说明可通过点击查看全文。
class DemoCard extends StatefulWidget {
  /// 创建卡片，标题保持单行，说明最多两行；默认带重播按钮。
  const DemoCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.replayable = true,
  });

  /// 一行标题。
  final String title;

  /// 两行以内的说明，点击可展开全文。
  final String description;

  /// 可交互的演示主体。
  final Widget child;

  /// 是否在标题右侧显示重播按钮；点击后重建 [child]，从头播放。
  final bool replayable;

  /// 创建重播代次状态。
  @override
  State<DemoCard> createState() => _DemoCardState();
}

/// 持有重播代次，每次重播让主体换新 Key 重新挂载。
class _DemoCardState extends State<DemoCard> {
  /// 当前重播代次。
  int _generation = 0;

  /// 重建主体，使其内部动画与计时从头开始。
  void _replay() => setState(() => _generation++);

  /// 显示完整的卡片说明。
  void _details(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.title),
          content: Text(widget.description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, 'Close', '关闭')),
            ),
          ],
        ),
      );

  /// 构建具有边框的紧凑卡片。
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DemoTokens.radius),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DemoTokens.gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _details(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: DemoTokens.cardHeaderHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: DemoTokens.tinyGap),
                            Text(
                              widget.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (widget.replayable)
                    IconButton(
                      onPressed: _replay,
                      tooltip: DemoLabels.replay(context),
                      icon: const Icon(Icons.replay_rounded, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: DemoTokens.smallGap),
              Center(
                child: KeyedSubtree(
                  key: ValueKey(_generation),
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 默认折叠且支持横向滚动与复制的代码块。
class CodeBlock extends StatelessWidget {
  /// 创建代码块，代码内容不参与翻译。
  const CodeBlock({super.key, required this.code});

  /// 可复制的原始代码。
  final String code;

  /// 复制代码并提供完成反馈。
  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Code copied', '代码已复制'))),
      );
    }
  }

  /// 构建全宽展开区域。
  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(tr(context, 'Show code', '显示代码')),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DemoTokens.gap),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(DemoTokens.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(tr(context, 'Copy code', '复制代码')),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: DemoTokens.fonts,
                      fontSize: DemoTokens.captionSize,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

/// 提示、警告与弃用信息的语义类型。
enum InfoNoteKind {
  /// 普通提示。
  tip,

  /// 需要留意的行为。
  warning,

  /// 已弃用的用法。
  deprecated,
}

/// 带类型标签的信息提示。
class InfoNote extends StatelessWidget {
  /// 创建信息提示。
  const InfoNote({super.key, required this.text, this.kind = InfoNoteKind.tip});

  /// 提示正文。
  final String text;

  /// 提示类型。
  final InfoNoteKind kind;

  /// 构建主题自适应的信息条。
  @override
  Widget build(BuildContext context) {
    final warning = kind != InfoNoteKind.tip;
    final scheme = Theme.of(context).colorScheme;
    final label = switch (kind) {
      InfoNoteKind.tip => tr(context, 'Tip', '提示'),
      InfoNoteKind.warning => tr(context, 'Warning', '注意'),
      InfoNoteKind.deprecated => tr(context, 'Deprecated', '已弃用'),
    };
    return Container(
      padding: const EdgeInsets.all(DemoTokens.gap),
      decoration: BoxDecoration(
        color: warning ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(DemoTokens.radius),
      ),
      child: Text(
        '$label · $text',
        style: TextStyle(
          color: warning
              ? scheme.onTertiaryContainer
              : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
