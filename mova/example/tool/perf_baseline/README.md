Record real device data with coverage_perf.py --record-baseline. No synthetic baselines belong here.

Android: <serial>.json; Windows: windows-<hostname>.json. Files contain device/model/OS,
commit, source hash, sampling configuration and per-scenario steady summaries.
Compare only the same device, OS, sources and sampling configuration. Commit is
recorded for attribution and intentionally allowed to differ between builds.

Default warmup: 60s; regression: 20%. Leak gates require all three: R² >= .7,
positive fitted slope above limit, fitted total increase above noise floor.
PSS/RSS: >10 MiB/hour and >5 MiB; Native Heap: >5 MiB/hour and >2 MiB;
fd: >10/hour and >5; threads: >4/hour and >2. These are configurable detection
floors, not claimed universal product budgets; calibrate against repeated runs.
At least 10 steady samples spanning 120s are required. Baseline zero drop rate
allows zero drops (explicitly strict); missing counters block rather than pass.
gfxinfo measures Flutter UI jank, mpv counters measure video decode/presentation.
