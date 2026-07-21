import 'dart:convert';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/services.dart' show rootBundle;
import 'package:roadsman/roadsman.dart';

void main() {
  runApp(const RoadmapDemoApp());
}

/// A Flutter demo for the roadsman package, matching the feature set of
/// `example/main.ts` in casino/apps/baccarat-roadmap: switching game type, toggling
/// which roads are shown, manually appending a round, replay, "what if" prediction,
/// and UX toggles. It doesn't aim to pixel-match the web layout, only functional parity.
class RoadmapDemoApp extends StatelessWidget {
  const RoadmapDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'roadsman demo',
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
  'beadPlate': 'Bead Plate',
  'bigRoad': 'Big Road',
  'bigEyeBoy': 'Big Eye Boy',
  'smallRoad': 'Small Road',
  'cockroachRoad': 'Cockroach Road',
  'pairRoad': 'Pair Road',
  'naturalRoad': 'Natural Road',
  'derivedTrio': 'Derived Trio',
  'compactRoadSheet': 'Compact Road Sheet',
  'statsPanel': 'Stats Panel',
};

/// Roads exclusive to baccarat (hidden when switching to other game types, matching
/// what example/main.ts does).
const _baccaratOnlyRoads = {'pairRoad', 'naturalRoad'};

/// Roads available for roulette: the derived-road plugins (big road/big eye boy etc.)
/// currently only understand baccarat's B/P semantics, so they're meaningless against
/// roulette's 37-number outcomes -- only the bead plate is enabled.
const _rouletteRoads = {'beadPlate'};

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

  /// "What if" prediction result: assuming the next round is a banker or player win,
  /// whether each of the three derived roads would gain an extra cell and what color it
  /// would be. This is a statistical prediction independent of the engine's `predict()`
  /// mechanism (`predictNextOutcome` in `core/predict.dart`) -- the big eye boy/small
  /// road/cockroach road plugins themselves don't implement `predict()` (matching the TS
  /// version, where "what if" prediction is a separate system outside the engine), so it
  /// can't be read from `ComputeOutput.predictions` and has to be computed separately.
  PredictResult? _prediction;

  /// "What if" mode: none / B / P.
  String _predictMode = 'none';

  /// The results reference from the last time predictNextOutcome ran (memoized by reference).
  List<RawResult>? _lastPredictedFor;

  /// Global theme (the demo doesn't support skinning, so it's resolved once and reused
  /// throughout, to avoid rebuilding the whole theme tree on every build).
  late final _theme = resolveTheme();

  /// Layout config (fixed, cached once) -- paired with the store's stable snapshot so that
  /// Engine.compute's by-reference memoization can hit directly when recomputing for
  /// UI-only changes (toggling a switch etc.), keeping the layout object the same instance.
  late final _cfg = LayoutConfig(cellSize: 18, rows: 6, theme: _theme);

  /// Memo of the merged decorations list (keyed by road id): if the input references
  /// haven't changed, reuse the same List instance, so a new list isn't built on every
  /// build that would defeat RoadPanel's "data unchanged" check.
  final Map<String, (RoadLayout, PredictionForRoad?, String, List<DrawCommand>)> _decoCache = {};

  bool _pulseEnabled = true;
  bool _celebrationEnabled = true;
  bool _hapticsEnabled = false;

  /// The kind of the most recent store change, which decides whether RoadPanel should
  /// play an insert animation / auto-follow the tail -- only a genuine "append one round"
  /// (UpdateKind.append) should animate and follow; a full refresh like switching shoes or
  /// game type (UpdateKind.full) should jump straight to the final state, without yanking
  /// the user away from the history position they're currently looking at.
  RoadUpdateKind _lastEventKind = RoadUpdateKind.setResults;

  @override
  void initState() {
    super.initState();
    _store = createStore(
      onOutOfSync: (expected, actual) =>
          debugPrint('roadsman demo: out of sync, expected round $expected, got $actual'),
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
    final results = _store.getResults();
    _output = _engine!.compute(results, _cfg);
    // predictNextOutcome only makes sense for baccarat's binary B/P outcome (recomputing
    // the big road assuming the next winner is 'B'/'P'); it isn't called when switched to
    // dragon tiger/sicbo, and _onGameTypeChanged also hides the corresponding dropdown then.
    // The prediction result is memoized by the results reference: a UI-only recompute
    // doesn't rerun predictNextOutcome, so the PredictionForRoad instance stays stable and
    // _decoCache's identical check can hit.
    if (_currentSpec.id != 'baccarat') {
      _prediction = null;
      _lastPredictedFor = null;
    } else if (!identical(results, _lastPredictedFor)) {
      _prediction = predictNextOutcome(results);
      _lastPredictedFor = results;
    }
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
      if (spec.id == 'roulette') _enabledRoads.retainWhere(_rouletteRoads.contains);
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
    final theme = _theme;

    return Scaffold(
      appBar: AppBar(title: const Text('roadsman demo — Baccarat/Dragon Tiger/Sic Bo road charts')),
      body: Column(
        children: [
          _buildControlBar(),
          const Divider(height: 1),
          Expanded(
            child: output == null
                ? const Center(child: Text('Waiting for a new shoe'))
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
            items: [baccaratSpec, dragonTigerSpec, sicboSpec, rouletteSpec]
                .map((s) => DropdownMenuItem(value: s, child: Text('Game: ${s.label}')))
                .toList(),
            onChanged: (s) => s != null ? _onGameTypeChanged(s) : null,
          ),
          if (_currentSpec.id == 'baccarat')
            DropdownButton<String>(
              value: _currentShoeId.isEmpty ? null : _currentShoeId,
              hint: const Text('Shoe'),
              items: _shoes.map((s) => DropdownMenuItem(value: s.shoeId, child: Text(s.shoeId))).toList(),
              onChanged: (id) => id != null ? _loadShoe(id) : null,
            ),
          ..._allRoadIds
              .where(
                (id) => _currentSpec.id == 'roulette'
                    ? _rouletteRoads.contains(id)
                    : _currentSpec.id == 'baccarat' || !_baccaratOnlyRoads.contains(id),
              )
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
          ElevatedButton(onPressed: _appendOneRound, child: const Text('Add a round')),
          if (_replayer != null) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Replay',
              onPressed: () => setState(() {
                // Loading a shoe already pushes the whole shoe's data into the store via
                // setResults so the user can see the full picture, but the replayer's
                // internal cursor starts from 0 -- calling play() without clearing the
                // store first would make each appended round number mismatch "the store's
                // last round + 1", so append silently fails (via the onOutOfSync callback)
                // and replay has no visible effect. Clearing and rebuilding is only needed
                // when starting fresh from idle (just loaded / previously stopped); resuming
                // from paused should just continue playing, not clear anything.
                if (_replayer!.state == ReplayState.idle) {
                  _store.setResults(const []);
                  _replayer = createReplayer(_replayScript, _store);
                }
                _replayer!.play();
              }),
            ),
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: 'Pause',
              onPressed: () => setState(() => _replayer!.pause()),
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: 'Stop (restore the full shoe)',
              onPressed: () => setState(() => _replayer!.stop()),
            ),
          ],
          if (_currentSpec.id != 'sicbo')
            DropdownButton<String>(
              value: _predictMode,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('No prediction')),
                DropdownMenuItem(value: 'B', child: Text('Ask Banker')),
                DropdownMenuItem(value: 'P', child: Text('Ask Player')),
              ],
              onChanged: (v) => setState(() => _predictMode = v ?? 'none'),
            ),
          FilterChip(
            label: const Text('Pulse highlight'),
            selected: _pulseEnabled,
            onSelected: (v) => setState(() => _pulseEnabled = v),
          ),
          FilterChip(
            label: const Text('Long-streak celebration'),
            selected: _celebrationEnabled,
            onSelected: (v) => setState(() => _celebrationEnabled = v),
          ),
          FilterChip(
            label: const Text('Haptic feedback'),
            selected: _hapticsEnabled,
            onSelected: (v) => setState(() => _hapticsEnabled = v),
          ),
        ],
      ),
    );
  }

  Widget _buildRoadCard(String id, ComputeOutput output, Theme theme) {
    final layout = output.layouts[id]!;
    final prediction = _predictMode == 'none' ? null : _predictionFor(id);
    final decorations = _mergedDecorations(id, layout, prediction);

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
              decorations: decorations,
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

  /// Gets the "what if" prediction result for a given road from [_prediction] (only
  /// meaningful for big eye boy/small road/cockroach road).
  PredictionForRoad? _predictionFor(String id) {
    final p = _prediction;
    if (p == null) return null;
    return switch (id) {
      'bigEyeBoy' => p.bigEyeBoy,
      'smallRoad' => p.smallRoad,
      'cockroachRoad' => p.cockroachRoad,
      _ => null,
    };
  }

  /// Merges layout.decorations with the "what if" ghost marker, memoized by
  /// (layout, prediction, predictMode) references: returns the same List instance when the
  /// inputs haven't changed, so RoadPanel can recognize the data as unchanged.
  List<DrawCommand> _mergedDecorations(String id, RoadLayout layout, PredictionForRoad? prediction) {
    final cached = _decoCache[id];
    if (cached != null &&
        identical(cached.$1, layout) &&
        identical(cached.$2, prediction) &&
        cached.$3 == _predictMode) {
      return cached.$4;
    }
    final ghost = _buildGhostDecoration(prediction, layout);
    final merged = ghost.isEmpty
        ? (layout.decorations ?? const <DrawCommand>[])
        : [...(layout.decorations ?? const <DrawCommand>[]), ...ghost];
    _decoCache[id] = (layout, prediction, _predictMode, merged);
    return merged;
  }

  /// "What if" ghost marker: assuming the next round is a banker or player win, whether a
  /// derived road would gain an extra cell and what color it would be, drawn as a
  /// semi-transparent dot at the end of that road's current content (right next to the
  /// last cell, same row).
  List<DrawCommand> _buildGhostDecoration(PredictionForRoad? prediction, RoadLayout layout) {
    if (prediction == null) return const [];
    final color = _predictMode == 'B' ? prediction.ifBanker : prediction.ifPlayer;
    if (color == null) return const [];
    // Color follows the theme palette instead of being hardcoded (keeps the ghost dot
    // consistent with the road chart when the theme changes)
    final argb = color == DerivedColor.red ? _theme.palette.red : _theme.palette.blue;
    if (layout.cells.isEmpty) {
      return [DotCommand(x: 9, y: 9, r: 6, fill: argb, alpha: 0.5)];
    }
    final last = layout.cells.last;
    final cx = last.x + last.w * 1.5;
    final cy = last.y + last.h / 2;
    return [DotCommand(x: cx, y: cy, r: last.w * 0.3, fill: argb, alpha: 0.5)];
  }

  Widget _buildStatsCard(StatsData stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Stats Panel', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Total rounds: ${stats.total}'),
            Text('Banker: ${stats.banker} (${stats.bankerPct}%)'),
            Text('Player: ${stats.player} (${stats.playerPct}%)'),
            Text('Tie: ${stats.tie} (${stats.tiePct}%)'),
            Text('Longest banker streak: ${stats.longestBankerStreak}'),
            Text('Longest player streak: ${stats.longestPlayerStreak}'),
            if (stats.currentStreak != null)
              Text('Current streak: ${stats.currentStreak!.winner} × ${stats.currentStreak!.length}'),
          ],
        ),
      ),
    );
  }
}
