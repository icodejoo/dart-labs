// "静态构造" tab: the 3 static factory constructors.
//
// "静态构造" Tab：3 个静态工厂构造方法。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../demo_data.dart';
import '../widgets/demo_card.dart';

class StaticTab extends StatelessWidget {
  const StaticTab({super.key});
  @override
  Widget build(BuildContext context) => const DemoGrid(children: [
        _StringsCard(),
        _ByKeyCard(),
        _ByKeysCard(),
      ]);
}

class _StringsCard extends StatefulWidget {
  const _StringsCard();
  @override
  State<_StringsCard> createState() => _StringsCardState();
}

class _StringsCardState extends State<_StringsCard> {
  late final _corpus = FuzzyCorpus.strings(demoItems, matchPaths: true);
  var _q = 'main';
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: '4.1',
        title: 'strings',
        code: "FuzzyCorpus.strings(items)",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(isDense: true, hintText: 'query'),
              controller: TextEditingController(text: _q),
              onChanged: (v) => setState(() => _q = v),
            ),
            ResultList([for (final h in _corpus.fuzzy(_q, limit: 5)) h.raw]),
          ],
        ),
      );
}

class _ByKeyCard extends StatefulWidget {
  const _ByKeyCard();
  @override
  State<_ByKeyCard> createState() => _ByKeyCardState();
}

class _ByKeyCardState extends State<_ByKeyCard> {
  late final _corpus = FuzzyCorpus.byKey(demoContacts, 'name');
  var _q = 'alice';
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: '4.2',
        title: 'byKey',
        code: "FuzzyCorpus.byKey(contacts, 'name')",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(isDense: true, hintText: 'query'),
              controller: TextEditingController(text: _q),
              onChanged: (v) => setState(() => _q = v),
            ),
            ResultList([for (final h in _corpus.fuzzy(_q, limit: 5)) h.raw['name'] as String]),
          ],
        ),
      );
}

class _ByKeysCard extends StatefulWidget {
  const _ByKeysCard();
  @override
  State<_ByKeysCard> createState() => _ByKeysCardState();
}

class _ByKeysCardState extends State<_ByKeysCard> {
  late final _fields = const ['name', 'email', 'company'];
  late final _corpus = FuzzyCorpus.byKeys(demoContacts, _fields);
  var _q = 'acme';
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: '4.3',
        title: 'byKeys',
        code: "FuzzyCorpus.byKeys(contacts,\n  ['name','email','company'])",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(isDense: true, hintText: 'query'),
              controller: TextEditingController(text: _q),
              onChanged: (v) => setState(() => _q = v),
            ),
            ResultList([
              for (final h in _corpus.fuzzy(_q, limit: 5))
                '${h.raw['name']} (via ${_fields[h.matchedKey]})',
            ]),
          ],
        ),
      );
}
