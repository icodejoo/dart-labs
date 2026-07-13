// "增删改" tab: 9 self-contained mutation-method cards.
//
// "增删改" Tab：9 张自带 corpus 实例的增删改方法卡片。
import 'package:flutter/material.dart';

import '../widgets/demo_card.dart';
import 'mutation_cards.dart';

class MutationTab extends StatelessWidget {
  const MutationTab({super.key});
  @override
  Widget build(BuildContext context) => const DemoGrid(children: [
        AddCard(id: '3.1'),
        AddAllCard(id: '3.2'),
        AddKeyCard(id: '3.3'),
        UpdateCard(id: '3.4'),
        RemoveAtCard(id: '3.5'),
        RemoveWhereCard(id: '3.6'),
        RefreshCard(id: '3.7'),
        ClearCard(id: '3.8'),
        DisposeCard(id: '3.9'),
      ]);
}
