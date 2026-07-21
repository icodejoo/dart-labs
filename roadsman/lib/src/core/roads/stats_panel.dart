/// Stats panel plugin: banker/player/tie counts and percentages, longest-streak status.
///
/// Ported from `src/core/roads/stats-panel.ts`.
library;

import '../types.dart';

/// Stats panel plugin.
class StatsPanelPlugin extends RoadPlugin<StatsData> {
  @override
  String get id => 'statsPanel';

  @override
  RoadKind get kind => RoadKind.summary;

  @override
  List<String> get dependsOn => const ['bigRoad'];

  @override
  StatsData derive(RoadContext ctx) {
    final results = ctx.results;
    final bigRoad = ctx.get<BigRoadData>('bigRoad');

    var banker = 0, player = 0, tie = 0, bankerPair = 0, playerPair = 0, natural = 0;
    for (final r in results) {
      if (r.winner == 'B') {
        banker++;
      } else if (r.winner == 'P') {
        player++;
      } else {
        tie++;
      }
      if (r.bankerPair) bankerPair++;
      if (r.playerPair) playerPair++;
      if (r.natural == true) natural++;
    }

    final total = results.length;
    double pct(int n) => total == 0 ? 0 : (n / total * 1000).round() / 10;

    var longestBankerStreak = 0;
    var longestPlayerStreak = 0;
    for (var i = 0; i < bigRoad.columns.length; i++) {
      BigRoadCell? cell;
      for (final c in bigRoad.cells) {
        if (c.col == i && c.row == 0) {
          cell = c;
          break;
        }
      }
      if (cell == null) continue;
      if (cell.winner == 'B') {
        longestBankerStreak = longestBankerStreak > bigRoad.columns[i] ? longestBankerStreak : bigRoad.columns[i];
      } else {
        longestPlayerStreak = longestPlayerStreak > bigRoad.columns[i] ? longestPlayerStreak : bigRoad.columns[i];
      }
    }

    CurrentStreak? currentStreak;
    if (bigRoad.columns.isNotEmpty) {
      final lastCol = bigRoad.columns.length - 1;
      BigRoadCell? lastCell;
      for (final c in bigRoad.cells) {
        if (c.col == lastCol && c.row == 0) {
          lastCell = c;
          break;
        }
      }
      if (lastCell != null) {
        currentStreak = CurrentStreak(winner: lastCell.winner, length: bigRoad.columns[lastCol]);
      }
    }

    return StatsData(
      total: total,
      banker: banker,
      player: player,
      tie: tie,
      bankerPair: bankerPair,
      playerPair: playerPair,
      natural: natural,
      bankerPct: pct(banker),
      playerPct: pct(player),
      tiePct: pct(tie),
      longestBankerStreak: longestBankerStreak,
      longestPlayerStreak: longestPlayerStreak,
      currentStreak: currentStreak,
    );
  }
}

/// Singleton instance of [StatsPanelPlugin].
final statsPanelPlugin = StatsPanelPlugin();
