// Repeatable micro-benchmark harness for the Rust parsing path. Test-only
// (`#[cfg(test)]` in lib.rs), so nothing here reaches the shipped cdylib.
//
// Deliberately dependency-free (no criterion): adding a dev-dependency that
// needs to link the crate as an `rlib` would force `crate-type = [..., "rlib"]`
// on the library, and rustc refuses LTO for rlib targets — which would silently
// disable the `lto = true` the size work depends on. Plain `std::time::Instant`
// plus a counting global allocator is enough for the "before vs after" deltas
// this harness exists to produce.
//
// Run with (release codegen == shipped codegen, per Cargo's profile-selection
// table `cargo test --release` uses the `release` profile):
//   cargo test --release -- --ignored --nocapture --test-threads=1
//
// Rust 侧解析路径的可重复微基准。仅测试期编译（lib.rs 里 `#[cfg(test)]`），
// 不会进入发布的 cdylib。
//
// 刻意零依赖（不用 criterion）：引入需要把本 crate 当 `rlib` 链接的 dev
// 依赖，就得给 library 加 `crate-type = [..., "rlib"]`，而 rustc 对 rlib 目标
// 拒绝做 LTO——那会悄悄关掉体积优化赖以生效的 `lto = true`。用
// `std::time::Instant` 加一个计数用全局分配器，足够产出本harness要的前后对比。

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;

use crate::api::svg::{parse_svg, scene_from_tree};

/// Wraps the system allocator to count allocations while [COUNTING] is on.
///
/// Gated by a relaxed flag rather than always-on so the timing pass is not
/// perturbed by the counters; the allocation pass turns it on.
///
/// 包裹系统分配器，在 [COUNTING] 打开时统计分配次数。
///
/// 用一个 relaxed 标志位门控而非始终开启，避免计数器干扰计时那一趟；
/// 统计分配的那一趟再打开。
struct CountingAlloc;

static COUNTING: AtomicBool = AtomicBool::new(false);
static ALLOCS: AtomicU64 = AtomicU64::new(0);
static ALLOC_BYTES: AtomicU64 = AtomicU64::new(0);

unsafe impl GlobalAlloc for CountingAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if COUNTING.load(Ordering::Relaxed) {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
            ALLOC_BYTES.fetch_add(layout.size() as u64, Ordering::Relaxed);
        }
        System.alloc(layout)
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout)
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if COUNTING.load(Ordering::Relaxed) {
            ALLOCS.fetch_add(1, Ordering::Relaxed);
            ALLOC_BYTES.fetch_add(new_size as u64, Ordering::Relaxed);
        }
        System.realloc(ptr, layout, new_size)
    }
}

#[global_allocator]
static GLOBAL: CountingAlloc = CountingAlloc;

/// Number of full passes over a corpus per measured run.
/// 每次测量对整个语料跑几遍。
const PASSES: usize = 20;
/// Warmup passes discarded before measuring. / 测量前丢弃的预热遍数。
const WARMUP: usize = 3;

/// Loads the 1000 real Iconify `Mdi` icon sources the Dart benchmark app uses,
/// straight out of its generated Dart list — the same corpus the numbers in
/// `docs/performance-benchmarks.md` were taken on, not a synthetic stand-in.
///
/// 直接从 Dart 基准应用生成的列表里读出它用的 1000 个真实 Iconify `Mdi` 图标源
/// ——与 `docs/performance-benchmarks.md` 里数据同一套语料，不是合成替代品。
fn mdi_corpus() -> Vec<String> {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../benchmark/bench_app/lib/mdi_icons_1000.dart"
    );
    let src = std::fs::read_to_string(path).expect("mdi_icons_1000.dart must be readable");
    src.lines()
        .filter_map(|l| {
            let l = l.trim();
            let inner = l.strip_prefix('\'')?.strip_suffix("',")?;
            inner.starts_with("<svg").then(|| inner.to_string())
        })
        .collect()
}

/// Feature-heavy sources: gradient, clipPath, mask, pattern and blur, i.e. the
/// branches the plain icon corpus never touches.
///
/// 重特效语料：渐变、clipPath、mask、pattern、模糊——纯图标语料碰不到的分支。
fn effects_corpus() -> Vec<String> {
    const GRADIENT: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <linearGradient id="g"><stop offset="0" stop-color="#f00"/><stop offset="0.5" stop-color="#0f0"/><stop offset="1" stop-color="#00f"/></linearGradient>
            <radialGradient id="r"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
        </defs>
        <rect x="0" y="0" width="50" height="100" fill="url(#g)"/>
        <circle cx="70" cy="50" r="25" fill="url(#r)" stroke="url(#g)" stroke-width="3"/>
    </svg>"##;
    const CLIP_MASK: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <clipPath id="c"><circle cx="50" cy="50" r="30"/></clipPath>
            <mask id="m"><rect x="0" y="0" width="60" height="100" fill="#fff"/><circle cx="80" cy="20" r="15" fill="#888"/></mask>
        </defs>
        <g clip-path="url(#c)" mask="url(#m)">
            <rect x="0" y="0" width="100" height="100" fill="#00f"/>
            <rect x="10" y="10" width="30" height="30" fill="#0f0"/>
            <path d="M5 95 L45 55 L95 95 Z" fill="#f00"/>
        </g>
    </svg>"##;
    const PATTERN_BLUR: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <pattern id="p" patternUnits="userSpaceOnUse" width="10" height="10"><rect width="5" height="5" fill="#f00"/><circle cx="7" cy="7" r="2" fill="#00f"/></pattern>
            <filter id="b"><feGaussianBlur stdDeviation="2.5"/></filter>
        </defs>
        <rect x="0" y="0" width="100" height="100" fill="url(#p)"/>
        <g filter="url(#b)"><path d="M10 10 C40 0 60 100 90 90 L90 10 Z" fill="#0a0"/></g>
    </svg>"##;
    vec![
        GRADIENT.to_string(),
        CLIP_MASK.to_string(),
        PATTERN_BLUR.to_string(),
    ]
}

/// A single big multi-contour path, to isolate the per-point geometry cost from
/// the per-document XML/tree cost.
///
/// 单个大型多段路径，把"每点几何成本"从"每文档 XML/树成本"里剥离出来。
fn big_path_corpus() -> Vec<String> {
    let mut d = String::from("M0 0");
    for i in 0..2000 {
        let f = i as f32;
        d.push_str(&format!(
            " C{} {} {} {} {} {}",
            f,
            f * 0.5,
            f * 1.5,
            f,
            f * 2.0,
            f * 0.25
        ));
    }
    d.push('Z');
    // Fill only, no stroke: a stroke on a 2000-cubic self-intersecting path
    // makes usvg compute a stroke bounding box (tiny-skia path stroker), which
    // costs ~17ms and would swamp the geometry cost this corpus isolates.
    //
    // 只填充不描边：给 2000 段三次贝塞尔的自相交路径加描边，会让 usvg 去算
    // 描边包围盒（tiny-skia 描边器），单次约 17ms，会把本语料想隔离的几何
    // 成本完全盖掉。
    vec![format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4000\" height=\"4000\" viewBox=\"0 0 4000 4000\"><g transform=\"rotate(13 5 5) scale(1.5)\"><path d=\"{d}\" fill=\"#f80\"/></g></svg>"
    )]
}

/// Per-parse latency percentiles in microseconds. / 单次解析延迟分位数（微秒）。
struct Stats {
    n: usize,
    avg: f64,
    p50: f64,
    p90: f64,
    p99: f64,
    max: f64,
}

impl std::fmt::Display for Stats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "n={} avg={:.3}us p50={:.3}us p90={:.3}us p99={:.3}us max={:.3}us",
            self.n, self.avg, self.p50, self.p90, self.p99, self.max
        )
    }
}

fn stats(mut samples: Vec<f64>) -> Stats {
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = samples.len();
    let pick = |q: f64| samples[((n as f64 * q) as usize).min(n - 1)];
    Stats {
        n,
        avg: samples.iter().sum::<f64>() / n as f64,
        p50: pick(0.50),
        p90: pick(0.90),
        p99: pick(0.99),
        max: samples[n - 1],
    }
}

/// Times `parse_svg` over `corpus`, [PASSES] times, one sample per parse.
/// 对 `corpus` 跑 [PASSES] 遍 `parse_svg` 计时，每次解析一个样本。
fn time_corpus(corpus: &[String], current_color: Option<u32>) -> Stats {
    for _ in 0..WARMUP {
        for s in corpus {
            let _ = std::hint::black_box(parse_svg(s.clone(), current_color).map(|s| s.paths.len()));
        }
    }
    let mut samples = Vec::with_capacity(corpus.len() * PASSES);
    for _ in 0..PASSES {
        for s in corpus {
            // `s.clone()` mirrors the FFI boundary, which always hands
            // `parse_svg` a freshly owned String; excluded from the timed
            // window so only parsing is measured.
            //
            // `s.clone()` 复现 FFI 边界——那里总是给 `parse_svg` 一个新拥有的
            // String；克隆放在计时窗口之外，只测解析本身。
            let owned = s.clone();
            let t = Instant::now();
            let out = parse_svg(owned, current_color);
            let dt = t.elapsed();
            let _ = std::hint::black_box(out.map(|s| s.paths.len()));
            samples.push(dt.as_nanos() as f64 / 1000.0);
        }
    }
    stats(samples)
}

/// Times only the usvg-tree → [crate::api::svg::SvgScene] conversion, with the
/// usvg parse hoisted out — i.e. exactly the code in `src/api/svg.rs` that is
/// ours to optimize.
///
/// 只给 usvg 树 → [crate::api::svg::SvgScene] 的转换计时，usvg 解析提到循环外
/// ——也就是 `src/api/svg.rs` 里真正属于我们、可优化的那部分代码。
fn time_convert(corpus: &[String]) -> Stats {
    let opt = usvg::Options::default();
    let trees: Vec<usvg::Tree> = corpus
        .iter()
        .filter_map(|s| usvg::Tree::from_str(s, &opt).ok())
        .collect();
    for _ in 0..WARMUP {
        for t in &trees {
            std::hint::black_box(scene_from_tree(t).paths.len());
        }
    }
    let mut samples = Vec::with_capacity(trees.len() * PASSES);
    for _ in 0..PASSES {
        for tree in &trees {
            let t = Instant::now();
            let scene = scene_from_tree(tree);
            let dt = t.elapsed();
            std::hint::black_box(scene.paths.len());
            samples.push(dt.as_nanos() as f64 / 1000.0);
        }
    }
    stats(samples)
}

/// Allocation count / bytes per parse, averaged over one pass of `corpus`.
/// 每次解析的分配次数/字节数，对 `corpus` 跑一遍求平均。
fn alloc_corpus(corpus: &[String], current_color: Option<u32>) -> (f64, f64) {
    // Pre-clone so the Strings the loop feeds in are not counted.
    // 预先克隆，使循环喂进去的 String 不被计入。
    let owned: Vec<String> = corpus.to_vec();
    ALLOCS.store(0, Ordering::Relaxed);
    ALLOC_BYTES.store(0, Ordering::Relaxed);
    COUNTING.store(true, Ordering::Relaxed);
    for s in &owned {
        let scene = parse_svg(s.clone(), current_color);
        let _ = std::hint::black_box(scene.map(|s| s.paths.len()));
    }
    COUNTING.store(false, Ordering::Relaxed);
    let n = owned.len() as f64;
    // Subtract the one `s.clone()` per iteration that the loop itself does.
    // 扣掉循环自身每轮那一次 `s.clone()`。
    (
        (ALLOCS.load(Ordering::Relaxed) as f64 / n) - 1.0,
        ALLOC_BYTES.load(Ordering::Relaxed) as f64 / n,
    )
}

fn report(label: &str, corpus: &[String], current_color: Option<u32>) {
    let t = time_corpus(corpus, current_color);
    let (allocs, bytes) = alloc_corpus(corpus, current_color);
    println!("[{label}] {t} allocs/parse={allocs:.1} alloc_bytes/parse={bytes:.0}");
    println!("[{label}/convert-only] {}", time_convert(corpus));
    let (xml, tree) = time_usvg_phases(corpus);
    println!("[{label}/usvg-xml-only] {xml}");
    println!("[{label}/usvg-tree-only] {tree}");
}

/// Splits usvg's cost into "roxmltree XML parse" and "XML → usvg::Tree", to see
/// which upstream phase dominates before deciding whether anything upstream is
/// even worth attacking.
///
/// 把 usvg 的成本拆成"roxmltree XML 解析"与"XML → usvg::Tree"两段，先看清
/// 上游哪一段占主导，再决定上游值不值得动。
fn time_usvg_phases(corpus: &[String]) -> (Stats, Stats) {
    let opt = usvg::Options::default();
    let mut xml = Vec::with_capacity(corpus.len() * PASSES);
    let mut tree = Vec::with_capacity(corpus.len() * PASSES);
    for pass in 0..(PASSES + WARMUP) {
        for s in corpus {
            let t0 = Instant::now();
            let doc = usvg::roxmltree::Document::parse(s).expect("valid xml");
            let d0 = t0.elapsed();
            let t1 = Instant::now();
            let parsed = usvg::Tree::from_xmltree(&doc, &opt);
            let d1 = t1.elapsed();
            std::hint::black_box(parsed.map(|t| t.root().children().len()).unwrap_or(0));
            if pass >= WARMUP {
                xml.push(d0.as_nanos() as f64 / 1000.0);
                tree.push(d1.as_nanos() as f64 / 1000.0);
            }
        }
    }
    (stats(xml), stats(tree))
}

/// FNV-1a over every verb byte and every point's raw `f32` bits across a
/// corpus, so a geometry change can be shown to be **bit-identical** rather
/// than merely "tests still pass". Compare the printed value before and after.
///
/// 对整个语料的每个 verb 字节与每个点的 `f32` 原始位做 FNV-1a，使几何改动能被
/// 证明为**逐位一致**，而不只是"测试还过"。对比改动前后打印的值即可。
fn fingerprint(corpus: &[String], current_color: Option<u32>) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    let mut eat = |b: u8| {
        h ^= b as u64;
        h = h.wrapping_mul(0x100_0000_01b3);
    };
    let mut eat_f32 = |v: f32, eat: &mut dyn FnMut(u8)| {
        for b in v.to_bits().to_le_bytes() {
            eat(b);
        }
    };
    let mut walk = |paths: &[crate::api::svg::SvgPath], eat: &mut dyn FnMut(u8)| {
        for p in paths {
            for &v in &p.verbs {
                eat(v);
            }
            for &c in &p.points {
                for b in c.to_bits().to_le_bytes() {
                    eat(b);
                }
            }
        }
    };
    for s in corpus {
        let scene = parse_svg(s.clone(), current_color).expect("corpus must parse");
        eat_f32(scene.width, &mut eat);
        eat_f32(scene.height, &mut eat);
        walk(&scene.paths, &mut eat);
        for p in &scene.paths {
            if let Some(e) = &p.effects {
                for c in &e.clips {
                    for &v in &c.verbs {
                        eat(v);
                    }
                    for &x in &c.points {
                        for b in x.to_bits().to_le_bytes() {
                            eat(b);
                        }
                    }
                }
                if let Some(m) = &e.mask {
                    walk(&m.paths, &mut eat);
                }
                if let Some(pat) = &e.fill_pattern {
                    walk(&pat.paths, &mut eat);
                }
            }
        }
    }
    h
}

#[test]
#[ignore = "output fingerprint, run explicitly with --ignored"]
fn bench_output_fingerprint() {
    let mdi = mdi_corpus();
    println!("[fingerprint/mdi1000] {:#018x}", fingerprint(&mdi, None));
    println!(
        "[fingerprint/mdi1000+cc] {:#018x}",
        fingerprint(&mdi, Some(0xFFFF7A00))
    );
    println!(
        "[fingerprint/effects] {:#018x}",
        fingerprint(&effects_corpus(), None)
    );
    println!(
        "[fingerprint/bigpath] {:#018x}",
        fingerprint(&big_path_corpus(), None)
    );
}

#[test]
#[ignore = "benchmark, run explicitly with --ignored"]
fn bench_parse_svg() {
    let mdi = mdi_corpus();
    assert_eq!(mdi.len(), 1000, "expected the full 1000-icon corpus");
    println!("--- svgx rust parse benchmark (passes={PASSES}, warmup={WARMUP}) ---");
    report("mdi1000/no-current-color", &mdi, None);
    report("mdi1000/current-color", &mdi, Some(0xFFFF7A00));
    report("effects", &effects_corpus(), None);
    report("bigpath2000cubics", &big_path_corpus(), None);
}
