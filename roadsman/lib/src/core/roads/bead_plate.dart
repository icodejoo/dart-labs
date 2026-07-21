/// Bead plate road plugin: fills each round's result into cells in sequence (serpentine layout).
///
/// Entirely driven by [GameSpec], with no game-specific hardcoding:
/// - Circle color: `colorForToken` (outcome's paletteKey → theme color, can be overridden by
///   `theme.palette.outcomes[code]`)
/// - Text: `labelForToken` (outcome label, can be overridden by `theme.labels.outcomes[code]`)
/// - Points mode: `OutcomeDef.beadTextField` specifies which numeric field to read from that round's extras
/// - Badges: dot-shaped markers in `spec.markers` are drawn at their corner position
///
/// This is why baccarat/dragon-tiger/sic-bo/roulette bead roads all share this one plugin —
/// the differences are entirely in the spec and theme.
///
/// Ported from `src/core/roads/bead-plate.ts`.
library;

import '../game_spec.dart';
import '../grid_layout.dart';
import '../stream.dart';
import '../types.dart';

/// Text mode for the bead plate road's in-circle text.
/// - `label`: shows the result text (outcome label), the default behavior.
/// - `points`: shows the numeric value pointed to by `OutcomeDef.beadTextField` (e.g. baccarat
///   winning side's point total, sic-bo total, roulette number); falls back to label when the field is missing.
enum BeadTextMode { label, points }

/// Bead plate road plugin: fills each round's result into cells in sequence (serpentine layout).
class BeadPlatePlugin extends RoadPlugin<List<RawResult>> {
  @override
  String get id => 'beadPlate';

  @override
  RoadKind get kind => RoadKind.grid;

  @override
  Map<String, ConfigField> get configSchema => const {
    'textMode': ConfigField(
      type: ConfigFieldType.select,
      label: '圆内文字',
      defaultValue: 'label',
      options: [
        ConfigFieldOption(value: 'label', label: '结果文字'),
        ConfigFieldOption(value: 'points', label: '点数'),
      ],
    ),
  };

  @override
  List<RawResult> derive(RoadContext ctx) => ctx.results;

  @override
  RoadLayout layout(List<RawResult> data, LayoutConfig cfg, RoadContext ctx) {
    final cellSize = cfg.cellSize;
    final rows = cfg.rows;
    final theme = cfg.theme;
    final palette = theme.palette;
    final fonts = theme.fonts;
    final spec = ctx.spec;
    final cells = <LayoutCell>[];

    // Reads the bead-plate-specific textMode config, defaulting to label. Config path: theme.roads['beadPlate'].textMode
    final textModeRaw = theme.roads['beadPlate']?.get<String>('textMode', 'label') ?? 'label';
    final textMode = textModeRaw == 'points' ? BeadTextMode.points : BeadTextMode.label;

    // outcome code → definition lookup table (used for beadTextField), cached per spec instance.
    final outcomeByCode = outcomeIndexOf(spec);

    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      final g = toGenericResult(r);
      final p = placeSequential(i, rows);
      final px = cellToPixel(p.physCol, p.physRow, cellSize);
      final fill = colorForToken(spec, 'main', g.outcome, theme);
      final label = labelForToken(spec, g.outcome, theme);

      String badgeText = label;
      if (textMode == BeadTextMode.points) {
        // beadTextField is declared by the spec (e.g. baccarat B→bankerTotal, sic-bo→total);
        // falls back to label when the field is missing.
        final field = outcomeByCode[g.outcome]?.beadTextField;
        final value = field == null ? null : g.extras?[field];
        if (value != null) badgeText = '$value';
      }

      final radius = cellSize * 0.42;
      final commands = <DrawCommand>[
        CircleCommand(x: px.x, y: px.y, r: radius, fill: fill),
        BadgeCommand(
          x: px.x,
          y: px.y,
          text: badgeText,
          fill: palette.text,
          fontSize: (cellSize * fonts.sizeRatio).round().toDouble(),
        ),
      ];

      // Badges: dot-shaped markers declared by the spec (e.g. banker pair/player pair). innerDot
      // (the inner circle for a natural) is a big-road presentation convention; the bead plate
      // road doesn't draw it, to keep behavior consistent with the TS version.
      // Badge offset 0.36: offset + badge radius (0.12) must be ≤0.5, otherwise it pokes out of
      // this cell's bounds and gets partially covered by the next cell's circle drawn later
      // (same pitfall as big_road.dart).
      for (final m in spec.markers ?? const <MarkerDef>[]) {
        if (m.shape != MarkerShape.dot) continue;
        if (!(g.marks?[m.code] ?? false)) continue;
        final (sx, sy) = switch (m.position) {
          MarkerPosition.topLeft => (-1, -1),
          MarkerPosition.topRight => (1, -1),
          MarkerPosition.bottomLeft => (-1, 1),
          MarkerPosition.bottomRight => (1, 1),
        };
        final color = palette.outcomes?[m.code] ?? colorForPaletteKey(m.paletteKey, theme);
        commands.add(
          DotCommand(
            x: px.x + sx * cellSize * 0.36,
            y: px.y + sy * cellSize * 0.36,
            r: cellSize * 0.12,
            fill: color,
          ),
        );
      }

      cells.add(
        LayoutCell(
          key: '${r.no}',
          x: p.physCol * cellSize,
          y: p.physRow * cellSize,
          w: cellSize,
          h: cellSize,
          resultNo: r.no,
          commands: commands,
        ),
      );
    }

    final colCount = data.isEmpty ? 0 : ((data.length - 1) ~/ rows) + 1;
    return RoadLayout(cells: cells, contentWidth: colCount * cellSize, contentHeight: rows * cellSize);
  }
}

/// Singleton instance of [BeadPlatePlugin].
final beadPlatePlugin = BeadPlatePlugin();
