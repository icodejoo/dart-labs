# roadsman — project rules

**Read the `/roadsman` skill first** (`.claude/skills/roadsman/SKILL.md`) before
changing code — architecture, the TS/Dart port mapping, and the verification
workflow all live there; this file only tracks project-level rules.

## 1. README has only one, English version

Do not maintain `README.zh-CN.md` or any other-language README. There is a
single `README.md`, written in English.

## 2. No Chinese anywhere in the project — comments, data, everything

All code comments (`//`, `/* */`, doc comments `///`) under `lib/`, `test/`,
and `example/` must be in English, with no Chinese. This also applies to
every other file in the project, including `pubspec.yaml`, `CHANGELOG.md`,
and this file — nothing checked in may contain Chinese text. There is no
carve-out for user-facing data/label fields (e.g. `OutcomeDef.label`,
`MarkerDef.label`, `LabelsTheme` defaults) — those must default to English
too. Callers who want localized text still configure it themselves via the
existing theme/label override mechanisms; only the shipped defaults must be
English.

## 3. No GitHub links in the published package

`pubspec.yaml` does not set `homepage`/`repository`/`issue_tracker`.
