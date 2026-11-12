import 'dart:io';

import 'codec.dart';

/// 固定的 npm 参照版本。
const String kParityUpstream = 'lucky-canvas@1.7.26';

/// 首次从 npm 官方 registry 下载并核验的压缩包摘要。
const String kParityTarballSha256 =
    'd3bcd87eba14ddf88896b6872db5a9196f95e1e94df7da87069d671ddfecd670';

/// 架构文档指定的上游参照提交。
const String kParityReferenceCommit =
    '7a8c0bbcb992a297b390e3a2ebaa1a3385c1f2f9';

/// 确定性伪时钟的帧间隔，单位毫秒。
const int kParityFrameMs = 16;

/// TEST_STRATEGY §6.2 的完整用例集合。
const List<String> kParityCaseIds = [
  'w01',
  'w02',
  'w03',
  'w04',
  'w05',
  'w06',
  'g01',
  'g02',
  'g03',
  'g04',
  'g05',
  's01',
  's02',
  's03',
  's04',
  's05',
];

/// 生成物所在的包内目录。
const String _baselinePath = 'test/parity/baselines';

/// 生成器与配置所在的包内目录。
const String _toolPath = 'tool/parity';

/// 清单文件名称。
const String _manifestName = 'MANIFEST.json';

/// 每个用例的数值记录文件名。
const String _framesName = 'frames.json';

/// 单个外部进程的超时上限。
const Duration _processTimeout = Duration(minutes: 2);

/// Roboto 在 Flutter SDK 中的相对位置。
const String _fontPath =
    'bin/cache/artifacts/material_fonts/roboto-regular.ttf';

/// 将 [value] 当作 JSON 对象读取；类型不符抛出 [FormatException]。
Map<String, Object?> parityObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw const FormatException('Expected JSON object');
}

/// 从 Chrome 的 [dom] 提取 harness 结果；缺失、执行错误或无效 JSON 均失败。
Map<String, Object?> parseHarnessDom(String dom) {
  final match = RegExp(r'<pre id="out">([\s\S]*?)</pre>').firstMatch(dom);
  if (match == null) throw const FormatException('Missing harness output');
  // 必须单次反转义，避免把 JSON 中原本的 &lt; 再次转义为 <。
  final source = match[1]!.replaceAllMapped(
    RegExp(r'&(?:amp|lt|gt|quot|#39);'),
    (m) => const {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
    }[m[0]]!,
  );
  final result = parityObject(decodeParityJson(source));
  if (result.containsKey('error')) {
    throw FormatException(
      'Harness failed: ${result['error']}\n${result['stack']}',
    );
  }
  return result;
}

/// 检查 [spec] 的 [result] 是否完整、确定且位于上游安全区间。
///
/// 返回全部可定位错误；转盘和九宫格必须单调，老虎机保留原始跳零与负余数。
List<String> validateParityFrames(
  Map<String, Object?> spec,
  Map<String, Object?> result,
) {
  final errors = <String>[];
  final id = spec['id'];
  final game = spec['game'];
  final frames = result['frames'];
  if (result['id'] != id ||
      result['game'] != game ||
      result['frameMs'] != kParityFrameMs ||
      frames is! List<Object?> ||
      frames.length != spec['frames']) {
    return ['$id: invalid frame identity/count/timebase'];
  }
  double? previous;
  for (var i = 0; i < frames.length; i++) {
    final state = parityObject(frames[i]);
    if (state['frame'] != i ||
        state['timeMs'] != i * kParityFrameMs ||
        state['step'] is! int ||
        (state['step']! as int) < 0 ||
        (state['step']! as int) > 3) {
      errors.add('$id: invalid frame/time/step at $i');
    }
    if (game == 'slot') {
      final scroll = state['scroll'];
      final slots = parityObject(spec['config'])['slots']! as List<Object?>;
      if (scroll is! List<Object?> ||
          scroll.length != slots.length ||
          scroll.any((v) => v is! num || !v.isFinite)) {
        errors.add('$id: invalid scroll at $i');
      }
    } else {
      final value = state[game == 'wheel' ? 'rotateDeg' : 'currIndex'];
      if (value is! num ||
          !value.isFinite ||
          (previous != null && value < previous)) {
        errors.add('$id: non-monotonic/non-finite value at $i');
      } else {
        previous = value.toDouble();
      }
    }
  }
  final settled = result['settledFrame'];
  if (settled is! int ||
      settled < 1 ||
      settled >= frames.length ||
      parityObject(frames[settled])['step'] != 0 ||
      frames.skip(settled).any((f) => parityObject(f)['step'] != 0)) {
    errors.add('$id: incomplete settled state');
  }
  final events = result['events'];
  final script = spec['script']! as List<Object?>;
  final cancelled = script.any((a) => parityObject(a)['index'] == -1);
  final expectedEnds = cancelled && game == 'slot' ? 0 : 1;
  if (events is! List<Object?> || events.length != expectedEnds) {
    errors.add('$id: unexpected end callback count');
  }
  final keyframes = result['keyframes'];
  if (keyframes is! Map<String, Object?>) {
    errors.add('$id: invalid keyframes object');
    return errors;
  }
  final expectedKeys =
      (spec['keyframes']! as List<Object?>).map((k) => '$k').toSet();
  if (keyframes.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(keyframes.keys.toSet()).isNotEmpty) {
    errors.add('$id: incomplete keyframes');
  }
  return errors;
}

/// 比较清单 [manifest] 与当前用例 [caseHashes]、产物 [artifactHashes] 的摘要。
///
/// 返回遗漏、篡改或版本错误；不运行 Chrome，不联网，适用于 CI。
List<String> parityManifestErrors({
  required Map<String, Object?> manifest,
  required Map<String, String> caseHashes,
  required Map<String, String> artifactHashes,
}) {
  final errors = <String>[];
  if (manifest['upstream'] != kParityUpstream ||
      manifest['referenceCommit'] != kParityReferenceCommit ||
      manifest['tarballSha256'] != kParityTarballSha256 ||
      manifest['frameMs'] != kParityFrameMs) {
    errors.add('MANIFEST upstream/reference/tarball/timebase mismatch');
  }
  if (manifest['chrome'] is! String ||
      (manifest['chrome']! as String).isEmpty ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${manifest['fontSha256']}') ||
      DateTime.tryParse('${manifest['generatedAt']}') == null) {
    errors.add('MANIFEST missing provenance');
  }
  for (final item in [
    (name: 'cases', actual: caseHashes),
    (name: 'artifacts', actual: artifactHashes),
  ]) {
    final expected = parityObject(manifest[item.name]);
    for (final key in {...expected.keys, ...item.actual.keys}) {
      if (expected[key] != item.actual[key] || !item.actual.containsKey(key)) {
        errors.add('${item.name}: missing or changed $key');
      }
    }
  }
  return errors;
}

/// 使用 [executable] 和 [arguments] 执行受超时约束的命令；失败抛出异常。
Future<String> _run(
  String executable,
  List<String> arguments, {
  String? directory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
  );
  final output = process.stdout.toList();
  final error = process.stderr.toList();
  int code;
  try {
    code = await process.exitCode.timeout(_processTimeout);
  } catch (_) {
    // 只结束本次启动的 PID 及其子进程，绝不按镜像名结束用户浏览器。
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      process.kill(ProcessSignal.sigkill);
    }
    await process.exitCode;
    rethrow;
  }
  final stdoutText = String.fromCharCodes((await output).expand((b) => b));
  final stderrText = String.fromCharCodes((await error).expand((b) => b));
  if (code != 0) {
    throw ProcessException(executable, arguments, stderrText, code);
  }
  return stdoutText;
}

/// 使用系统命令求 [file] 的 SHA-256，不引入加密依赖。
Future<String> _sha256(File file) async {
  final output = Platform.isWindows
      ? await _run('certutil', ['-hashfile', file.absolute.path, 'SHA256'])
      : await _run('sha256sum', [file.absolute.path]);
  final match = RegExp(r'\b[a-fA-F0-9]{64}\b').firstMatch(output);
  if (match == null) throw StateError('Missing SHA-256: ${file.path}');
  return match[0]!.toLowerCase();
}

/// 查找显式路径、环境变量或本机安装的 Chrome。
Future<String> _chrome(String? explicit) async {
  final candidates = <String?>[
    explicit,
    Platform.environment['CHROME_PATH'],
    if (Platform.isWindows) ...[
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
      '${Platform.environment['LOCALAPPDATA']}/Google/Chrome/Application/chrome.exe',
    ],
  ];
  if (explicit == null && Platform.environment['CHROME_PATH'] == null) {
    try {
      final located = await _run(Platform.isWindows ? 'where.exe' : 'which', [
        Platform.isWindows ? 'chrome.exe' : 'google-chrome',
      ]);
      candidates.addAll(located.trim().split(RegExp(r'[\r\n]+')));
    } on ProcessException {
      /* 常见路径仍然可用。 */
    }
  }
  for (final path in candidates) {
    if (path != null && File(path).existsSync()) {
      return File(path).absolute.path;
    }
    if (path != null &&
        (path == explicit || path == Platform.environment['CHROME_PATH'])) {
      throw FileSystemException('Chrome not found', path);
    }
  }
  throw StateError('Chrome not found; use --chrome=path or CHROME_PATH');
}

/// 从 SDK 参数、环境变量或 Dart 可执行文件向上查找测试字体。
File _font(String? explicit) {
  if (explicit != null) return File(explicit);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) return File('$root/$_fontPath');
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final file = File('${directory.path}/$_fontPath');
    if (file.existsSync()) return file;
    directory = directory.parent;
  }
  throw const FileSystemException(
    'Roboto missing; use --font=path or FLUTTER_ROOT',
  );
}

/// 读取并核对用例集合，返回按规范顺序排列的配置。
Map<String, Map<String, Object?>> _cases(Directory root) {
  final directory = Directory('${root.path}/$_toolPath/cases');
  final ids = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.uri.pathSegments.last.replaceFirst('.json', ''))
      .toSet();
  if (ids.length != kParityCaseIds.length || !ids.containsAll(kParityCaseIds)) {
    throw StateError('Expected exactly ${kParityCaseIds.length} parity cases');
  }
  return {
    for (final id in kParityCaseIds)
      id: parityObject(
        decodeParityJson(File('${directory.path}/$id.json').readAsStringSync()),
      ),
  };
}

/// 返回配置要求的全部相对产物路径。
List<String> _artifacts(String id, Map<String, Object?> spec) => [
      '$id/$_framesName',
      for (final frame in spec['keyframes']! as List<Object?>)
        '$id/kf_$frame.png',
    ];

/// 只校验用例、版本、基线完整性和摘要；不需要浏览器、字体或网络。
Future<void> _verify(Directory root) async {
  final cases = _cases(root);
  final baseline = '${root.path}/$_baselinePath';
  final manifest = parityObject(
    decodeParityJson(File('$baseline/$_manifestName').readAsStringSync()),
  );
  final hashes = <String, String>{};
  final artifacts = <String, String>{};
  final errors = <String>[];
  for (final entry in cases.entries) {
    hashes[entry.key] = await _sha256(
      File('${root.path}/$_toolPath/cases/${entry.key}.json'),
    );
    for (final path in _artifacts(entry.key, entry.value)) {
      final file = File('$baseline/$path');
      if (!file.existsSync()) {
        errors.add('Missing baseline $path');
        continue;
      }
      artifacts[path] = await _sha256(file);
      if (path.endsWith('.png') &&
          !hasParityPngSignature(file.readAsBytesSync())) {
        errors.add('Invalid PNG $path');
      }
    }
    final frames = File('$baseline/${entry.key}/$_framesName');
    if (frames.existsSync()) {
      errors.addAll(
        validateParityFrames(
          entry.value,
          parityObject(decodeParityJson(frames.readAsStringSync())),
        ),
      );
    }
  }
  errors.addAll(
    parityManifestErrors(
      manifest: manifest,
      caseHashes: hashes,
      artifactHashes: artifacts,
    ),
  );
  if (errors.isNotEmpty) throw StateError(errors.join('\n'));
  stdout.writeln(
    'PASS: parity manifest ${cases.length} cases, ${artifacts.length} artifacts; hashes and frames verified',
  );
}

/// 下载、核验并解包 npm 产物到隔离缓存。
Future<File> _upstream(Directory cache) async {
  final archive = File('${cache.path}/lucky-canvas-1.7.26.tgz');
  if (!archive.existsSync()) {
    for (final registry in ['registry.npmjs.org', 'registry.npmmirror.com']) {
      try {
        await _run(
          'curl.exe'.replaceFirst('.exe', Platform.isWindows ? '.exe' : ''),
          [
            '-fL',
            '--max-time',
            '60',
            'https://$registry/lucky-canvas/-/lucky-canvas-1.7.26.tgz',
            '-o',
            archive.path,
          ],
        );
        break;
      } on ProcessException {
        if (registry == 'registry.npmmirror.com') rethrow;
      }
    }
  }
  final hash = await _sha256(archive);
  if (hash != kParityTarballSha256) {
    throw StateError('Tarball SHA-256 mismatch: $hash');
  }
  // Windows 自带 tar 避免 Git tar 把盘符中的冒号识别为远程地址。
  final tar = Platform.isWindows
      ? '${Platform.environment['SystemRoot']}/System32/tar.exe'
      : 'tar';
  await _run(
      tar,
      [
        '-xzf',
        archive.uri.pathSegments.last,
      ],
      directory: cache.path);
  return File('${cache.path}/package/dist/index.umd.js');
}

/// 串行运行 Chrome，先在缓存生成完整数据，全部通过后写入包目录。
Future<void> _generate(Directory root, Map<String, String> options) async {
  final cases = _cases(root);
  final chrome = await _chrome(options['chrome']);
  final font = _font(options['font']);
  final cache = Directory('${Directory.systemTemp.path}/luckdraw_parity')
    ..createSync(recursive: true);
  final upstream = await _upstream(cache);
  final run = cache.createTempSync('run_');
  try {
    upstream.copySync('${run.path}/index.umd.js');
    font.copySync('${run.path}/roboto-regular.ttf');
    File(
      '${root.path}/$_toolPath/harness/harness.js',
    ).copySync('${run.path}/harness.js');
    final template = File(
      '${root.path}/$_toolPath/harness/index.html',
    ).readAsStringSync();
    final chromeVersion = Platform.isWindows
        ? (await _run('powershell.exe', [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            "(Get-Item -LiteralPath '${chrome.replaceAll("'", "''")}').VersionInfo.ProductVersion",
          ]))
            .trim()
        : (await _run(chrome, ['--version'])).trim();
    final caseHashes = <String, String>{};
    final artifactHashes = <String, String>{};
    for (final entry in cases.entries) {
      final id = entry.key;
      final spec = entry.value;
      if (spec['id'] != id) throw StateError('Case id mismatch: $id');
      final page = File('${run.path}/index.html')
        ..writeAsStringSync(
          template.replaceFirst(
            '__CASE_JSON__',
            encodeParityJson(spec).replaceAll('<', r'\u003c'),
          ),
        );
      final dom = await _run(chrome, [
        '--headless=new',
        '--disable-gpu',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-background-networking',
        '--disable-extensions',
        '--force-device-scale-factor=1',
        '--allow-file-access-from-files',
        '--user-data-dir=${run.path}/chrome-profile',
        '--virtual-time-budget=120000',
        '--dump-dom',
        page.uri.toString(),
      ]);
      final result = parseHarnessDom(dom);
      final errors = validateParityFrames(spec, result);
      if (errors.isNotEmpty) throw StateError(errors.join('\n'));
      final directory = Directory('${run.path}/baselines/$id')
        ..createSync(recursive: true);
      final keyframes = parityObject(result['keyframes']);
      for (final keyframe in keyframes.entries) {
        final data = parityObject(keyframe.value);
        final filename = 'kf_${keyframe.key}.png';
        File(
          '${directory.path}/$filename',
        ).writeAsBytesSync(decodeParityPng(data.remove('png')! as String));
        data['file'] = filename;
      }
      File(
        '${directory.path}/$_framesName',
      ).writeAsStringSync('${encodeParityJson(result)}\n');
      caseHashes[id] = await _sha256(
        File('${root.path}/$_toolPath/cases/$id.json'),
      );
      for (final path in _artifacts(id, spec)) {
        artifactHashes[path] = await _sha256(
          File('${run.path}/baselines/$path'),
        );
      }
      stdout.writeln(
        'PASS: $id ${spec['frames']} frames, ${keyframes.length} PNGs, settled=${result['settledFrame']}',
      );
    }
    final manifest = <String, Object?>{
      'upstream': kParityUpstream,
      'tarballSha256': kParityTarballSha256,
      'referenceCommit': kParityReferenceCommit,
      'chrome': chromeVersion,
      'fontSha256': await _sha256(font),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'frameMs': kParityFrameMs,
      'cases': caseHashes,
      'artifacts': artifactHashes,
    };
    // 清单最后落盘，任何中途失败都会使已有清单校验失败，而不会伪报完整。
    for (final path in artifactHashes.keys) {
      final target = File('${root.path}/$_baselinePath/$path');
      target.parent.createSync(recursive: true);
      File('${run.path}/baselines/$path').copySync(target.path);
    }
    File(
      '${root.path}/$_baselinePath/$_manifestName',
    ).writeAsStringSync('${encodeParityJson(manifest)}\n');
  } finally {
    // 只清理由 createTempSync 返回的本次运行目录，保留 npm 压缩包缓存。
    run.deleteSync(recursive: true);
  }
  await _verify(root);
}

/// 生成或离线核验基线；支持 `--chrome=…`、`--font=…`、`--root=…`。
///
/// `dart run tool/parity/generate.dart --verify-manifest` 不启动 Chrome；错误返回退出码 1。
Future<void> main(List<String> arguments) async {
  try {
    final options = <String, String>{};
    var verify = false;
    for (final argument in arguments) {
      if (argument == '--verify-manifest') {
        verify = true;
        continue;
      }
      final match = RegExp(r'^--(chrome|font|root)=(.+)$').firstMatch(argument);
      if (match == null) throw ArgumentError('Unknown option: $argument');
      options[match[1]!] = match[2]!;
    }
    final root = Directory(options['root'] ?? Directory.current.path).absolute;
    if (verify) {
      await _verify(root);
    } else {
      await _generate(root, options);
    }
  } catch (error) {
    stderr.writeln('FAIL: $error');
    exitCode = 1;
  }
}
