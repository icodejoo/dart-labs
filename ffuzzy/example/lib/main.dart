// Minimal demo of the ffz fuzzy matcher: type in the box to filter a list,
// with matched characters highlighted (highlight: true → FuzzyHit.indices).
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: load the WASM engine from the published npm package.
  // On native this is a no-op, so it's safe to always call.
  // Load WASM engine from CDN (or swap for webAssetsUrl to use a local asset).
  await ffuzzyInit(
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.7.0/dist/ffz.mjs',
  );
  runApp(const FuzzyDemoApp());
}

const _items = <String>[
  'lib/src/widgets/scaffold.dart',
  'lib/src/material/app_bar.dart',
  'packages/ffz/lib/ffz.dart',
  'README.md',
  'CHANGELOG.md',
  '中文搜索引擎', // findable by pinyin via addKey below
  'café_menu.json',
  'src/main.rs',
];

class FuzzyDemoApp extends StatelessWidget {
  const FuzzyDemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ffuzzy demo',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const SearchPage(),
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final FuzzyCorpus<String> _corpus;
  List<FuzzyHit<String>> _hits = const [];
  int _searchGen = 0; // bumped per keystroke so only the latest result is shown

  @override
  void initState() {
    super.initState();
    // ffuzzyInit() has already completed by the time the app starts,
    // so constructing FuzzyCorpus here is safe on all platforms.
    _corpus = FuzzyCorpus.strings(_items, matchPaths: true);
    // Index the CJK item by host-computed pinyin/initials so latin typing finds it.
    _corpus.addKey('中文搜索引擎', [
      FuzzyKey.kind('zhongwensousuoyinqing', FuzzyKeyKind.pinyin),
      FuzzyKey.kind('zwssyq', FuzzyKeyKind.initials),
    ]);
    _search('');
  }

  Future<void> _search(String q) async {
    final gen = ++_searchGen;
    final hits = await _corpus.asyncFuzzy(q, limit: 50, highlight: true);
    if (!mounted || gen != _searchGen) return;
    setState(() => _hits = hits);
  }

  @override
  void dispose() {
    _corpus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ffuzzy demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              'Web WASM build',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText:
                    'Type to fuzzy-search  (try "src", "appbar", "中文", "zwssyq")',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
          ),
          if (_hits.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No matches',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemCount: _hits.length,
                itemBuilder: (context, i) {
                  final hit = _hits[i];
                  final text = hit.raw;
                  final positions = hit.matchedKey == 0
                      ? fuzzyCodepointToUtf16(text, hit.indices).toSet()
                      : const <int>{};
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.insert_drive_file, size: 18),
                    title: _Highlighted(text, positions),
                    trailing: Chip(
                      label: Text('${hit.score}'),
                      padding: EdgeInsets.zero,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    subtitle: hit.matchedKind == FuzzyKeyKind.original
                        ? null
                        : Text('via ${hit.matchedKind.name}'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Highlighted extends StatelessWidget {
  const _Highlighted(this.text, this.positions);
  final String text;
  final Set<int> positions;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final hi = base.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary);
    final spans = <TextSpan>[];
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      spans.add(TextSpan(
          text: String.fromCharCode(units[i]),
          style: positions.contains(i) ? hi : base));
    }
    return Text.rich(TextSpan(children: spans));
  }
}
