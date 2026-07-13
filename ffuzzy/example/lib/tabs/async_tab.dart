// "Async镜像" tab: 17 shared-query async search mirrors + 3 self-contained
// async lifecycle cards (build/addAll/dispose) = 20 cards total.
//
// "Async镜像" Tab：17 张共享查询框的异步搜索镜像卡片 + 3 张自带状态的异步
// 生命周期卡片（build/addAll/dispose），共 20 张。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../demo_data.dart';
import '../widgets/demo_card.dart';
import 'async_lifecycle_cards.dart';
import 'async_specs.dart';

class AsyncTab extends StatefulWidget {
  const AsyncTab({super.key});
  @override
  State<AsyncTab> createState() => _AsyncTabState();
}

class _AsyncTabState extends State<AsyncTab> {
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
              labelText: 'Shared query (search-mirror cards below use this)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: DemoGrid(
            children: [
              for (var i = 0; i < asyncSearchSpecs.length; i++)
                DemoCard(
                  id: '5.${i + 1}',
                  title: asyncSearchSpecs[i].title,
                  code: asyncSearchSpecs[i].code,
                  child: asyncSearchSpecs[i].builder(_corpus, _query),
                ),
              const AsyncBuildCard(id: '5.18'),
              const AsyncAddAllCard(id: '5.19'),
              const AsyncDisposeCard(id: '5.20'),
            ],
          ),
        ),
      ],
    );
  }
}
