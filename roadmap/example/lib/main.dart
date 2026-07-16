import 'dart:convert';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/services.dart' show rootBundle;
import 'package:roadmap/roadmap.dart';

void main() {
  runApp(const RoadmapDemoApp());
}

/// roadmap 包的 Flutter demo，功能对齐 casino/apps/baccarat-roadmap 的
/// `example/main.ts`：切换游戏类型、勾选显示哪些路、手工加一局、回放、问路、
/// UX 开关。不追求逐像素复刻网页版布局，追求功能对等。
class RoadmapDemoApp extends StatelessWidget {
  const RoadmapDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'roadmap demo',
    theme: ThemeData.dark(useMaterial3: true),
    home: const RoadmapDemoPage(),
  );
}

const _allRoadIds = [
  'beadPlate',
  'bigRoad',
  'bigEyeBoy',
  'smallRoad',
  'cockroachRoad',
  'pairRoad',
  'naturalRoad',
  'derivedTrio',
  'compactRoadSheet',
  'statsPanel',
];

const _roadLabels = {
  'beadPlate': '珠盘路',
  'bigRoad': '大路',
  'bigEyeBoy': '大眼仔',
  'smallRoad': '小路',
  'cockroachRoad': '曱甴路',
  'pairRoad': '对子路',
  'naturalRoad': '例牌路',
  'derivedTrio': '三合一',
  'compactRoadSheet': '紧凑路纸',
  'statsPanel': '统计面板',
};

/// 百家乐专属的路（切到其他游戏类型时隐藏，对应 example/main.ts 的做法）。
const _baccaratOnlyRoads = {'pairRoad', 'naturalRoad'};

class RoadmapDemoPage extends StatefulWidget {
  const RoadmapDemoPage({super.key});

  @override
  State<RoadmapDemoPage> createState() => _RoadmapDemoPageState();
}

class _RoadmapDemoPageState extends State<RoadmapDemoPage> {
  List<Shoe> _shoes = [];
  bool _loading = true;

  GameSpec _currentSpec = baccaratSpec;
  String _currentShoeId = '';
  final Set<String> _enabledRoads = {
    'beadPlate',
    'bigRoad',
    'bigEyeBoy',
    'smallRoad',
    'cockroachRoad',
    'pairRoad',
    'naturalRoad',
    'statsPanel',
  };

  late RoadmapStore _store;
  Replayer? _replayer;
  List<RawResult> _replayScript = [];
  Engine? _engine;
  ComputeOutput? _output;

  /// 问路：none / B / P。
  String _predictMode = 'none';

  bool _pulseEnabled = true;
  bool _celebrationEnabled = true;
  bool _hapticsEnabled = false;

  /// 最近一次 store 变更的类型，决定要不要给 RoadPanel 播插入动画/自动跟随尾部
  /// ——只有真正的"加一局"（UpdateKind.append）才应该动画+跟随，切靴局/切游戏
  /// 类型这类全量刷新（UpdateKind.full）应该直达终态，不该把用户正在看的历史
  /// 位置拽走。
  RoadUpdateKind _lastEventKind = RoadUpdateKind.setResults;

  @override
  void initState() {
    super.initState();
    _store = createStore(
      onOutOfSync: (expected, actual) =>
          debugPrint('roadmap demo: out of sync，期望局号 $expected，实际 $actual'),
    );
    _store.subscribe((event) {
      _lastEventKind = switch (event.kind) {
        UpdateKind.append => RoadUpdateKind.append,
        UpdateKind.patch => RoadUpdateKind.patch,
        UpdateKind.full => RoadUpdateKind.setResults,
      };
      setState(_recompute);
    });
    _loadMock();
  }

  Future<void> _loadMock() async {
    final raw = await rootBundle.loadString('assets/mock.json');
    final list = jsonDecode(raw) as List;
    final shoes = list.map((e) => Shoe.fromJson(e as Map<String, dynamic>)).toList();
    setState(() {
      _shoes = shoes;
      _loading = false;
    });
    if (shoes.isNotEmpty) _loadShoe(shoes.first.shoeId);
  }

  void _rebuildEngine() {
    _engine = createEngine(_enabledRoads.toList(), spec: _currentSpec);
  }

  void _recompute() {
    _engine ??= createEngine(_enabledRoads.toList(), spec: _currentSpec);
    final cfg = LayoutConfig(cellSize: 18, rows: 6, theme: resolveTheme());
    _output = _engine!.compute(_store.getResults(), cfg);
  }

  void _loadShoe(String shoeId) {
    final shoe = _shoes.firstWhere((s) => s.shoeId == shoeId);
    _currentShoeId = shoeId;
    _replayScript = shoe.results;
    _replayer?.stop();
    _replayer = createReplayer(_replayScript, _store);
    _rebuildEngine();
    setState(() => _store.setResults(shoe.results));
  }

  void _onGameTypeChanged(GameSpec spec) {
    setState(() {
      _currentSpec = spec;
      _enabledRoads.removeWhere((id) => _baccaratOnlyRoads.contains(id) && spec.id != 'baccarat');
      _rebuildEngine();
      _store.setResults(const []);
      _replayer?.stop();
      if (spec.id == 'baccarat' && _shoes.isNotEmpty) {
        _loadShoe(_shoes.first.shoeId);
      }
    });
  }

  void _appendOneRound() {
    final results = _store.getResults();
    final next = results.isNotEmpty ? results.last.no + 1 : 1;
    final winner = _currentSpec.outcomes[next % _currentSpec.outcomes.length].code;
    _store.append(RawResult(no: next, winner: winner, bankerPair: false, playerPair: false));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final output = _output;
    final theme = resolveTheme();

    return Scaffold(
      appBar: AppBar(title: const Text('roadmap demo — 百家乐/龙虎/骰宝路子图')),
      body: Column(
        children: [
          _buildControlBar(),
          const Divider(height: 1),
          Expanded(
            child: output == null
                ? const Center(child: Text('等待开局'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final id in _enabledRoads)
                          if (output.layouts.containsKey(id))
                            _buildRoadCard(id, output, theme)
                          else if (id == 'statsPanel' && output.data['statsPanel'] != null)
                            _buildStatsCard(output.data['statsPanel'] as StatsData),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<GameSpec>(
            value: _currentSpec,
            items: [baccaratSpec, dragonTigerSpec, sicboSpec]
                .map((s) => DropdownMenuItem(value: s, child: Text('游戏：${s.label}')))
                .toList(),
            onChanged: (s) => s != null ? _onGameTypeChanged(s) : null,
          ),
          if (_currentSpec.id == 'baccarat')
            DropdownButton<String>(
              value: _currentShoeId.isEmpty ? null : _currentShoeId,
              hint: const Text('靴局'),
              items: _shoes.map((s) => DropdownMenuItem(value: s.shoeId, child: Text(s.shoeId))).toList(),
              onChanged: (id) => id != null ? _loadShoe(id) : null,
            ),
          ..._allRoadIds
              .where((id) => _currentSpec.id == 'baccarat' || !_baccaratOnlyRoads.contains(id))
              .map(
                (id) => FilterChip(
                  label: Text(_roadLabels[id] ?? id),
                  selected: _enabledRoads.contains(id),
                  onSelected: (sel) => setState(() {
                    sel ? _enabledRoads.add(id) : _enabledRoads.remove(id);
                    _rebuildEngine();
                    _recompute();
                  }),
                ),
              ),
          ElevatedButton(onPressed: _appendOneRound, child: const Text('加一局')),
          if (_replayer != null) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: '回放',
              onPressed: () => setState(() => _replayer!.play()),
            ),
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: '暂停',
              onPressed: () => setState(() => _replayer!.pause()),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '停止（恢复整靴）',
              onPressed: () => setState(() => _replayer!.stop()),
            ),
          ],
          if (_currentSpec.id != 'sicbo')
            DropdownButton<String>(
              value: _predictMode,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('不问路')),
                DropdownMenuItem(value: 'B', child: Text('问庄')),
                DropdownMenuItem(value: 'P', child: Text('问闲')),
              ],
              onChanged: (v) => setState(() => _predictMode = v ?? 'none'),
            ),
          FilterChip(
            label: const Text('呼吸高亮'),
            selected: _pulseEnabled,
            onSelected: (v) => setState(() => _pulseEnabled = v),
          ),
          FilterChip(
            label: const Text('长龙庆祝'),
            selected: _celebrationEnabled,
            onSelected: (v) => setState(() => _celebrationEnabled = v),
          ),
          FilterChip(
            label: const Text('触觉反馈'),
            selected: _hapticsEnabled,
            onSelected: (v) => setState(() => _hapticsEnabled = v),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadCard(String id, ComputeOutput output, Theme theme) {
    final layout = output.layouts[id]!;
    final prediction = _predictMode == 'none' ? null : output.predictions[id];
    final ghost = _buildGhostDecoration(id, prediction);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_roadLabels[id] ?? id, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            RoadPanel(
              key: ValueKey(id),
              cells: layout.cells,
              decorations: [...(layout.decorations ?? const []), ...ghost],
              contentWidth: layout.contentWidth,
              contentHeight: layout.contentHeight,
              grid: layout.grid,
              theme: theme,
              panelWidth: 360,
              panelHeight: layout.contentHeight.clamp(60, 260),
              eventType: _lastEventKind,
              followTail: _lastEventKind == RoadUpdateKind.append ? FollowTail.ease : FollowTail.none,
              pulseEnabled: _pulseEnabled,
            ),
          ],
        ),
      ),
    );
  }

  /// 问路 ghost：假设下一局开庄/开闲，衍生路会不会多长出一格、落什么颜色，
  /// 用半透明提示点画在对应路的末尾。
  List<DrawCommand> _buildGhostDecoration(String id, PredictionForRoad? prediction) {
    if (prediction == null) return const [];
    if (!const ['bigEyeBoy', 'smallRoad', 'cockroachRoad'].contains(id)) return const [];
    final color = _predictMode == 'B' ? prediction.ifBanker : prediction.ifPlayer;
    if (color == null) return const [];
    final argb = color == DerivedColor.red ? 0xFFE53935 : 0xFF1E88E5;
    return [DotCommand(x: 9, y: 9, r: 6, fill: argb, alpha: 0.5)];
  }

  Widget _buildStatsCard(StatsData stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('统计面板', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('总局数：${stats.total}'),
            Text('庄：${stats.banker}（${stats.bankerPct}%）'),
            Text('闲：${stats.player}（${stats.playerPct}%）'),
            Text('和：${stats.tie}（${stats.tiePct}%）'),
            Text('最长连庄：${stats.longestBankerStreak}'),
            Text('最长连闲：${stats.longestPlayerStreak}'),
            if (stats.currentStreak != null)
              Text('当前连状态：${stats.currentStreak!.winner} × ${stats.currentStreak!.length}'),
          ],
        ),
      ),
    );
  }
}
