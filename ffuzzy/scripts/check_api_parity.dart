// API surface parity check — Dart side.
// Reads test/shared/api_surface.json and verifies that all required
// instance methods and static factories exist in the Dart source files.
//
//   dart run scripts/check_api_parity.dart
import 'dart:convert';
import 'dart:io';

void main() {
  // Resolve paths relative to this script's location so the script works
  // when run from any working directory (e.g. monorepo root via lefthook).
  final scriptDir = File(Platform.script.toFilePath()).parent.parent.path;
  final api = jsonDecode(
    File('$scriptDir/test/shared/api_surface.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  // Both platform files must implement the full public API.
  // ffuzzy_corpus.dart contains the base (public methods).
  // ffuzzy_ffi.dart and ffuzzy_web.dart implement the bridge.
  final sources = {
    'lib/src/ffuzzy_corpus.dart': File('$scriptDir/lib/src/ffuzzy_corpus.dart').readAsStringSync(),
    'lib/src/ffuzzy_ffi.dart':   File('$scriptDir/lib/src/ffuzzy_ffi.dart').readAsStringSync(),
    'lib/src/ffuzzy_web.dart':   File('$scriptDir/lib/src/ffuzzy_web.dart').readAsStringSync(),
  };
  final allSrc = sources.values.join('\n');

  final methods  = (api['corpus_instance_methods'] as List).cast<String>();
  final statics  = (api['corpus_static_methods']   as List).cast<String>();
  final dartOnly = (api['dart_only']               as List).cast<String>().toSet();

  final missing = <String>[];

  // Check instance methods (appear anywhere in the combined source)
  for (final name in [...methods, ...statics]) {
    // Match as a method/function identifier followed by ( or <
    final pattern = RegExp(r'\b' + RegExp.escape(name) + r'\s*[(<]');
    if (!pattern.hasMatch(allSrc)) {
      missing.add(name);
    }
  }

  // Check dart_only methods exist in native + web implementations
  for (final name in dartOnly) {
    final pattern = RegExp(r'\b' + RegExp.escape(name) + r'\s*[(<]');
    if (!pattern.hasMatch(allSrc)) {
      missing.add('$name [dart_only]');
    }
  }

  print('\n── API parity check (source: test/shared/api_surface.json) ──────');
  print('  Dart source files: ${sources.keys.map(basename).join(', ')}');

  if (missing.isEmpty) {
    print('  ✔  All required methods present in Dart source');
  } else {
    print('  ✖  Missing methods (${missing.length}):');
    for (final m in missing) { print('       $m'); }
  }
  print('─────────────────────────────────────────────────────────────────\n');

  if (missing.isNotEmpty) exit(1);
}

String basename(String path) => path.split(RegExp(r'[/\\]')).last;
