# F baseline (relocated, not part of `lib/`)

This is `full_svg_flutter`'s `lib/` source (from
`E:\workspaces\bingo\packages\full_svg_flutter`), relocated here from
`lib/src/fvendor/` where it was previously (incorrectly) vendored and
exported by `fsvg.dart`.

Per `CLAUDE.md`, F's only legitimate role in this project is as a
performance/correctness **comparison baseline** for the future benchmark
work described in the "性能验收条件" section — it must never be part of the
shipped `lib/` tree or exported by `fsvg.dart`. This directory is not wired
into `pubspec.yaml`/any build target; it's parked here for that future
benchmark task to pick up.
