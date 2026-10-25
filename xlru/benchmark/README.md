# LRU benchmarks

The benchmark compares (A) xlru, (B) a benchmark-only insertion-ordered
`LinkedHashMap` LRU, and (C) quiver `LruMap`. The baseline uses remove/reinsert
on a hit and removes `keys.first` when over capacity. Its non-null values allow
a single lookup on reads. No implementation has pins or listeners enabled.

Capacities: 100 and 10,000. Keys: preallocated int and String keys, drawn from
a pool of twice the capacity. Values: int. Scenarios:

- `read90`: 90% hit reads and 10% insertions that evict.
- `write`: 100% insertions that evict.
- `mixed`: 50% hit reads and 50% insertions that evict.

Reads pseudorandomly select among the most recently inserted half-capacity
keys; this guarantees hits while exercising promotion. Each trace has
`20 * capacity` operations and inserts a multiple of the key-pool size,
allowing repeated traces to remain in steady state. Hit assumptions are
checked over two repetitions in setup. String creation and trace generation
are excluded from timing; trace iteration, adapter dispatch, and a read checksum
are included equally. These are throughput microbenchmarks, not allocation,
latency-percentile, callback, miss-heavy, or heavily pinned workload
measurements. The `LinkedHashMap` baseline removes `keys.first`, which degrades
with size, so its ratios are only a sanity check; quiver is the meaningful
comparison.

Each case is warmed for at least 200 ms, then timed in 5 runs of at least
500 ms each (`BenchmarkBase.measureFor`); the median run is reported. An
exercise is one trace. CSV results report nanoseconds per cache operation
(lower is better), derived from microseconds per exercise. Each CSV contains 36
measurements: 3 implementations × 2 capacities × 2 key types × 3 scenarios.

Each runtime's benchmark process was run twice at high priority with its
affinity restricted to the CPU's performance cores (this machine mixes
performance and efficiency cores, and background load otherwise moves runs
between them); each CSV keeps the faster of the two results per case. The two
runs agreed within about 3% for xlru. Runtimes are still measured
sequentially, so differences of a few percent should not be interpreted as
significant.

JavaScript is measured at two dart2js levels: `-O4` is what Flutter web release
builds use, and `-O1` is the `dart compile js` default. WebAssembly uses
dart2wasm `-O2`, the Flutter web `--wasm` release default.

## Reproduce

From the package directory, create `build/`, then run:

```sh
dart run benchmark/lru_benchmark.dart
dart compile exe benchmark/lru_benchmark.dart -o build/lru_benchmark.exe
./build/lru_benchmark.exe
dart compile js benchmark/lru_benchmark.dart -O4 -o build/lru_benchmark.js
node build/lru_benchmark.js
dart compile js benchmark/lru_benchmark.dart -O1 -o build/lru_benchmark_o1.js
node build/lru_benchmark_o1.js
dart compile wasm benchmark/lru_benchmark.dart -O2 -o build/lru_benchmark.wasm
```

The executable suffix/path is platform-dependent. To run the WebAssembly build
under Node, load `build/lru_benchmark.mjs`, call its `compile` with the bytes of
`build/lru_benchmark.wasm`, then `instantiate({})` and `invokeMain()`. Pass
`-Dimpls=xlru` (or any comma-separated subset of `xlru,naive,quiver`) to any
compile or run command to benchmark fewer implementations. Raw results are in
`results-jit.csv`, `results-aot.csv`, `results-js.csv` (dart2js `-O4`),
`results-js-o1.csv`, and `results-wasm.csv`.

## Results

Windows 10 Pro x64, Intel Core i5-13500, Dart SDK 3.13.0, Node v24.11.0.
ns/op, lower is better; each cell is **A (xlru) / B (naive) / C (quiver)**.

### Dart VM

| Capacity | Key | Scenario | JIT A / B / C | AOT A / B / C |
| ---: | --- | --- | ---: | ---: |
| 100 | int | read90 | 9.29 / 39.85 / 20.10 | 20.34 / 42.18 / 26.70 |
| 100 | int | write | 17.48 / 83.48 / 48.57 | 27.25 / 94.93 / 49.80 |
| 100 | int | mixed | 14.62 / 53.07 / 32.61 | 25.67 / 60.03 / 39.30 |
| 100 | String | read90 | 13.51 / 55.10 / 29.83 | 21.39 / 48.90 / 28.68 |
| 100 | String | write | 18.67 / 98.64 / 60.31 | 25.59 / 108.09 / 56.63 |
| 100 | String | mixed | 16.46 / 66.95 / 38.30 | 26.86 / 67.61 / 43.16 |
| 10000 | int | read90 | 22.76 / 138.86 / 42.04 | 26.79 / 131.48 / 41.25 |
| 10000 | int | write | 38.87 / 5376.34 / 59.63 | 42.97 / 5242.72 / 69.92 |
| 10000 | int | mixed | 29.09 / 1505.13 / 50.94 | 34.77 / 1513.03 / 55.70 |
| 10000 | String | read90 | 27.15 / 163.05 / 53.59 | 29.31 / 147.62 / 54.90 |
| 10000 | String | write | 40.25 / 5449.19 / 95.16 | 43.95 / 5261.20 / 102.10 |
| 10000 | String | mixed | 33.63 / 1557.97 / 74.51 | 38.06 / 1560.73 / 79.36 |

### Web

| Capacity | Key | Scenario | JS `-O4` A / B / C | JS `-O1` A / B / C | Wasm `-O2` A / B / C |
| ---: | --- | --- | ---: | ---: | ---: |
| 100 | int | read90 | 13.32 / 56.60 / 19.04 | 28.14 / 66.15 / 116.17 | 24.58 / 49.92 / 60.71 |
| 100 | int | write | 28.33 / 70.13 / 129.83 | 77.96 / 106.05 / 287.50 | 30.70 / 106.66 / 138.12 |
| 100 | int | mixed | 29.08 / 64.75 / 46.00 | 65.79 / 100.95 / 203.67 | 30.21 / 68.15 / 94.09 |
| 100 | String | read90 | 30.58 / 93.17 / 32.25 | 49.49 / 109.17 / 138.50 | 26.91 / 55.99 / 62.67 |
| 100 | String | write | 40.05 / 79.46 / 154.00 | 80.49 / 117.90 / 291.00 | 30.22 / 118.10 / 139.71 |
| 100 | String | mixed | 39.76 / 92.17 / 60.77 | 69.49 / 118.42 / 215.25 | 32.03 / 77.46 / 95.04 |
| 10000 | int | read90 | 31.31 / 86.76 / 30.75 | 51.23 / 117.07 / 149.38 | 38.79 / 154.93 / 192.50 |
| 10000 | int | write | 52.64 / 73.29 / 132.11 | 90.71 / 104.80 / 290.00 | 50.86 / 5313.37 / 211.68 |
| 10000 | int | mixed | 42.46 / 73.14 / 81.88 | 70.47 / 142.92 / 229.58 | 48.34 / 1596.70 / 187.60 |
| 10000 | String | read90 | 46.79 / 277.50 / 89.63 | 61.43 / 293.33 / 225.00 | 45.75 / 182.79 / 216.82 |
| 10000 | String | write | 63.57 / 218.57 / 376.88 | 97.78 / 320.00 / 597.50 | 51.14 / 5379.42 / 267.79 |
| 10000 | String | mixed | 57.06 / 249.29 / 240.83 | 79.09 / 348.18 / 409.44 | 51.91 / 1638.86 / 210.96 |

Geometric mean of the 12 cases (time of the other implementation ÷ xlru time;
above 1 means xlru is faster):

| Runtime | vs naive | vs quiver |
| --- | ---: | ---: |
| JIT | 12.19 (12/12 faster) | 2.18 (12/12 faster) |
| AOT | 8.95 (12/12 faster) | 1.71 (12/12 faster) |
| JS `-O4` | 2.76 (12/12 faster) | 2.22 (11/12 faster) |
| JS `-O1` | 2.15 (12/12 faster) | 3.63 (12/12 faster) |
| Wasm `-O2` | 7.88 (12/12 faster) | 3.80 (12/12 faster) |

On the VM and under dart2wasm, the naive baseline degrades sharply at large
capacity because `keys.first` on the compact `LinkedHashMap` skips deleted
slots at the front of its storage. dart2js uses a different `LinkedHashMap`
that keeps its own linked list, so the naive baseline does not degrade under
dart2js, yet xlru is still faster than it in every case there.
