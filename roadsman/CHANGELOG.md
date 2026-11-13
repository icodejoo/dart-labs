## 0.1.5

- Docs: pubspec `homepage` and `repository` now point to the package directory on the `main` branch.

## 0.1.4

- Docs only: rewrote README wording in plain language and added a Chinese README (README.zh-CN.md).

## 0.1.3

Metadata and docs only; no code changes.

- Added `homepage`, `repository` and `issue_tracker` to `pubspec.yaml`.
- Added dartdoc comments to public constructors.

## 0.1.2

- Translated all remaining Chinese text to English project-wide: default theme labels (banker/player/tie/empty), built-in `GameSpec` labels for baccarat/dragon-tiger/roulette/sic-bo, bead-plate config field labels, deprecation message, `EmptyStateOverlay` default message, test descriptions, and example app strings. **This changes the shipped default display text** — callers who relied on the previous Chinese defaults should now configure labels explicitly via `Theme`/`GameSpec` overrides.
- Removed mentions of the TypeScript source project from the README introduction and `pubspec.yaml` description.
