## 0.1.2

- Translated all remaining Chinese text to English project-wide: default theme labels (banker/player/tie/empty), built-in `GameSpec` labels for baccarat/dragon-tiger/roulette/sic-bo, bead-plate config field labels, deprecation message, `EmptyStateOverlay` default message, test descriptions, and example app strings. **This changes the shipped default display text** — callers who relied on the previous Chinese defaults should now configure labels explicitly via `Theme`/`GameSpec` overrides.
- Removed mentions of the TypeScript source project from the README introduction and `pubspec.yaml` description.
