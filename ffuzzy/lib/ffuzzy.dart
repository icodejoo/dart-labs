/// ffuzzy — fast fuzzy search for Flutter, powered by a compact C engine (native)
/// or its WASM build (web).
///
/// **Native (Android/iOS/macOS/Linux/Windows)**: backed by the C engine via
/// dart:ffi. All five search modes, multi-threading, async isolate filtering,
/// hit highlighting, and Unicode (CJK + pinyin).
///
/// Web 各搜索模式均使用 WASM，支持别名键、归一化和高亮。
/// 启动时调用 `await ffuzzyInit(webUrl: ...)` 初始化引擎。
///
/// ```dart
/// // Web-safe app entry point:
/// void main() async {
///   // no-op on native; on web loads WASM from CDN or local asset:
///   await ffuzzyInit(webUrl: 'https://cdn.../ffz.mjs');
///   // or: await ffuzzyInit(webAssetsUrl: '/assets/ffz.mjs');
///   runApp(const MyApp());
/// }
///
/// // Then use FuzzyCorpus identically on all platforms:
/// final corpus = FuzzyCorpus<File>(files, stringOf: (f) => f.path);
/// for (final h in corpus.fuzzy('src', limit: 50, highlight: true)) {
///   final u16 = fuzzyCodepointToUtf16(h.raw.path, h.indices);
///   print('${h.raw.path}  score=${h.score}  $u16');
/// }
/// corpus.dispose();
/// ```
library;

export 'src/ffuzzy_ffi.dart' if (dart.library.js_interop) 'src/ffuzzy_web.dart';
