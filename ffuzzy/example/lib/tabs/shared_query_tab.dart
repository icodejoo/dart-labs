// Generic tab shell: one shared query box drives a grid of demo cards that
// each call a different FuzzyCorpus method with that same query.
//
// 通用 Tab 骨架：一个共享查询框驱动一组卡片，每张卡调用不同的 FuzzyCorpus
// 方法，但用的是同一个查询。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../demo_data.dart';
import '../widgets/demo_card.dart';

/// Builds a card's result widget from the shared [corpus] and current [query].
///
/// 用共享的 [corpus] 和当前 [query] 构建卡片的结果部件。
typedef QueryCardBuilder = Widget Function(
    FuzzyCorpus<String> corpus, String query);

class QuerySpec {
  const QuerySpec(this.title, this.code, this.builder, {this.note});
  final String title;
  final String code;
  final QueryCardBuilder builder;

  /// Optional short caveat shown on the card (see [DemoCard.note]).
  ///
  /// 卡片上展示的可选简短提示（见 [DemoCard.note]）。
  final String? note;
}

class SharedQueryTab extends StatefulWidget {
  const SharedQueryTab({super.key, required this.tabId, required this.specs});

  /// This tab's number in the showcase (used as the `tab` half of each
  /// card's `tab.card` id).
  ///
  /// 该 Tab 在展示页里的编号（作为每张卡 `tab.card` id 里的 tab 部分）。
  final int tabId;
  final List<QuerySpec> specs;

  @override
  State<SharedQueryTab> createState() => _SharedQueryTabState();
}

class _SharedQueryTabState extends State<SharedQueryTab> {
  late final FuzzyCorpus<String> _corpus;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _corpus = FuzzyCorpus.strings(demoItems, matchPaths: true);
  }

  @override
  void dispose() {
    _corpus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Shared query (all cards below use this)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DemoGrid(
            children: [
              for (var i = 0; i < widget.specs.length; i++)
                DemoCard(
                  id: '${widget.tabId}.${i + 1}',
                  title: widget.specs[i].title,
                  code: widget.specs[i].code,
                  note: widget.specs[i].note,
                  child: widget.specs[i].builder(_corpus, _query),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
