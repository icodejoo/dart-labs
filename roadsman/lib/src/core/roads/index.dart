/// Registry of built-in road plugins.
///
/// Ported from `src/core/roads/index.ts`.
library;

import '../types.dart';
import 'bead_plate.dart';
import 'big_eye_boy.dart';
import 'big_road.dart';
import 'big_road_merged_dots.dart';
import 'cockroach_road.dart';
import 'compact_road_sheet.dart';
import 'derived_trio.dart';
import 'natural_road.dart';
import 'pair_road.dart';
import 'small_road.dart';
import 'stats_panel.dart';
import 'streak_highlight.dart';

/// Synchronous registry of all built-in road plugins, indexed by plugin id.
///
/// ```dart
/// final plugin = roadRegistry['beadPlate'];
/// ```
final Map<String, RoadPlugin> roadRegistry = {
  'beadPlate': beadPlatePlugin,
  'bigRoad': bigRoadPlugin,
  'bigEyeBoy': bigEyeBoyPlugin,
  'smallRoad': smallRoadPlugin,
  'cockroachRoad': cockroachRoadPlugin,
  'pairRoad': pairRoadPlugin,
  'naturalRoad': naturalRoadPlugin,
  'derivedTrio': derivedTrioPlugin,
  'compactRoadSheet': compactRoadSheetPlugin,
  'bigRoadMergedDots': bigRoadMergedDotsPlugin,
  'streakHighlight': streakHighlightPlugin,
  'statsPanel': statsPanelPlugin,
};
