// ignore_for_file: avoid_print, implementation_imports, depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/platform_impl/thumb_dir_impl.dart';
import 'package:mova/stt.dart';

const _phase = int.fromEnvironment('PHASE', defaultValue: 1);
const _host = String.fromEnvironment(
  'RFV_HOST',
  defaultValue: 'http://127.0.0.1:18764',
);

/// Native directory timestamps, using the Android ABI's time_t.
///
/// 使用 Android ABI 的 time_t 表示原生目录时间。
final class _Utime extends Struct {
  @Long()
  external int access;
  @Long()
  external int modified;
}

/// Starts the independent release acceptance page.
///
/// 启动独立的 release 验收页面。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MaterialApp(home: _ReviewPage()));
}

/// Displays actual filesystem and extraction results.
///
/// 展示真实文件系统和抽取结果。
class _ReviewPage extends StatefulWidget {
  const _ReviewPage();
  @override
  State<_ReviewPage> createState() => _ReviewState();
}

/// Runs after the page is mounted; phase one deliberately keeps its lease.
///
/// 页面挂载后执行；阶段一刻意保留租约。
class _ReviewState extends State<_ReviewPage> {
  final _lines = <String>[];
  final _held = <MovaTempThumbDirProvider>[];
  int _cycle = 0;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// Emits one complete logcat record and updates the page.
  ///
  /// 输出完整 logcat 记录并更新页面。
  void _log(String text) {
    final line = 'RFV cycle=$_cycle phase=$_phase $text';
    print(line);
    if (mounted) setState(() => _lines.add(line));
  }

  /// Records a release-safe assertion using observed values.
  ///
  /// 用实际观测值记录 release 下仍执行的断言。
  void _check(String name, bool pass, String values) {
    if (!pass) _failures++;
    _log('${pass ? 'PASS' : 'FAIL'} $name $values');
  }

  /// Lists every `mova_*` directory, sorted for direct comparison.
  ///
  /// 列出全部 `mova_*` 目录并排序，便于直接对比。
  Future<List<String>> _movas(Directory root) async {
    final names = <String>[];
    await for (final entry in root.list(followLinks: false)) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory && name.startsWith('mova_')) names.add(name);
    }
    return names..sort();
  }

  /// Resolves the production provider without filesystem or lock injection.
  ///
  /// 使用生产 provider，不注入文件系统或锁替身。
  Future<String> _resolve() {
    final provider = MovaTempThumbDirProvider();
    _held.add(provider);
    return provider.resolve();
  }

  /// Fetches run metadata from the host; cache busting identifies each request.
  ///
  /// 从主机获取轮次信息；唯一查询参数防止命中缓存。
  Future<Map<String, dynamic>> _control() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse(
          '$_host/control.json?t=${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      final response = await request.close();
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Persists identity before an external force-stop, without disposal.
  ///
  /// 在外部 force-stop 前保存身份，不调用 dispose。
  Future<void> _phaseOne() async {
    var path = await _resolve();
    // Discard reserved fixture names left by an interrupted earlier harness.
    // 清理之前脚本中断时留下的专用夹具目录名。
    while (path.endsWith('/mova_old') || path.endsWith('/mova_fresh')) {
      await _held.removeLast().dispose();
      await Directory(path).delete(recursive: true);
      path = await _resolve();
    }
    final root = Directory(path).parent;
    final token = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await File('$path/marker.txt').writeAsString(token, flush: true);
    final names = await _movas(root);
    await File('${root.path}/rfv_state.json').writeAsString(
      jsonEncode({
        'cycle': _cycle,
        'path': path,
        'token': token,
        'names': names,
      }),
      flush: true,
    );
    _check(
      'V1_PREPARE',
      await File('$path/.lease').exists(),
      'A=$path token=$token count=${names.length} movas=${jsonEncode(names)} disposed=false',
    );
    _log('READY_FORCE_STOP');
  }

  /// Checks adoption, same-process isolation, and real legacy directory ages.
  ///
  /// 验证收养、同进程隔离及真实遗留目录年龄。
  Future<void> _phaseTwo() async {
    final a = await _resolve();
    final root = Directory(a).parent;
    final stateFile = File('${root.path}/rfv_state.json');
    final state =
        jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
    final marker = File('$a/marker.txt');
    final token = await marker.exists()
        ? await marker.readAsString()
        : '<missing>';
    final names = await _movas(root);
    final before = (state['names'] as List).length;
    _check(
      'V1_ADOPT',
      state['cycle'] == _cycle && a == state['path'] && token == state['token'],
      'A=$a expected=${state['path']} token=$token expectedToken=${state['token']}',
    );
    _check(
      'V1_COUNT',
      names.length == before,
      'before=$before after=${names.length} movas=${jsonEncode(names)}',
    );
    final b = await _resolve();
    final aExists = await marker.exists();
    final tokenIntact =
        aExists && await marker.readAsString() == state['token'];
    final secondNames = await _movas(root);
    _check(
      'V1_SECOND',
      a != b && tokenIntact && secondNames.length == names.length + 1,
      'A=$a B=$b AExists=$aExists tokenIntact=$tokenIntact count=${secondNames.length} movas=${jsonEncode(secondNames)}',
    );
    final old = await Directory('${root.path}/mova_old').create();
    final fresh = await Directory('${root.path}/mova_fresh').create();
    final now = DateTime.now();
    // File.setLastModified invokes the real filesystem timestamp operation.
    // File.setLastModified 调用真实文件系统修改时间操作。
    await _setDirectoryModified(old, now.subtract(const Duration(days: 8)));
    await _setDirectoryModified(fresh, now);
    final ageSeconds = now.difference((await old.stat()).modified).inSeconds;
    _check(
      'V1_LEGACY_SETUP',
      ageSeconds >= 8 * 86400 - 2 &&
          !await File('${old.path}/.lease').exists() &&
          !await File('${fresh.path}/.lease').exists(),
      'old=${old.path} ageSeconds=$ageSeconds fresh=${fresh.path} oldLease=false freshLease=false',
    );
    String? c;
    try {
      c = await _resolve();
      final oldExists = await old.exists();
      final freshExists = await fresh.exists();
      final finalNames = await _movas(root);
      _check(
        'V1_PRUNE',
        !oldExists &&
            freshExists &&
            c == fresh.path &&
            await marker.exists() &&
            await Directory(b).exists(),
        'C=$c oldExists=$oldExists freshExists=$freshExists count=${finalNames.length} movas=${jsonEncode(finalNames)}',
      );
    } finally {
      for (final provider in _held) {
        await provider.dispose();
      }
      _held.clear();
      // Remove only paths used by this run, after every lease is released.
      // 全部租约释放后，仅删除本轮使用的目录。
      for (final path in {a, b, ?c, old.path, fresh.path}) {
        final dir = Directory(path);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
      if (await stateFile.exists()) await stateFile.delete();
      _log('V1_CLEANUP remaining=${jsonEncode(await _movas(root))}');
    }
    if (_cycle == 1) await _audio();
    _log('DONE failures=$_failures');
  }

  /// Uses File.setLastModified, with real utime fallback for Android EISDIR.
  ///
  /// 使用 File.setLastModified；Android 拒绝目录时回退到真实 utime。
  Future<void> _setDirectoryModified(Directory directory, DateTime time) async {
    try {
      await File(directory.path).setLastModified(time);
      return;
    } on FileSystemException catch (error) {
      if (!Platform.isAndroid || error.osError?.errorCode != 21) rethrow;
      _log(
        'FIXTURE_MTIME_FALLBACK path=${directory.path} error=${jsonEncode('$error')}',
      );
    }
    final stamp = File('${directory.path}/rfv_mtime.tmp');
    await stamp.writeAsString('');
    await stamp.setLastModified(time);
    final observed = (await stamp.stat()).modified;
    await stamp.delete();
    final path = directory.path.toNativeUtf8();
    final times = calloc<_Utime>();
    try {
      times.ref.access = observed.millisecondsSinceEpoch ~/ 1000;
      times.ref.modified = observed.millisecondsSinceEpoch ~/ 1000;
      final utime = DynamicLibrary.open('libc.so')
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<_Utime>),
            int Function(Pointer<Utf8>, Pointer<_Utime>)
          >('utime');
      final result = utime(path, times);
      if (result != 0) {
        throw FileSystemException(
          'libc.utime returned $result',
          directory.path,
        );
      }
      _log(
        'FIXTURE_MTIME path=${directory.path} method=File.setLastModified(stamp)+libc.utime(directory) actual=${(await directory.stat()).modified.toIso8601String()}',
      );
    } finally {
      calloc.free(path);
      calloc.free(times);
    }
  }

  /// Parses RIFF chunks and derives duration from actual PCM bytes.
  ///
  /// 解析 RIFF 块，从真实 PCM 字节数计算时长。
  Map<String, Object> _wav(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int at) => ascii.decode(bytes.sublist(at, at + 4));
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not RIFF/WAVE');
    }
    int? channels, rate, bits, blockAlign, format, payload;
    for (var at = 12; at + 8 <= bytes.length;) {
      final size = data.getUint32(at + 4, Endian.little);
      final start = at + 8;
      if (start + size > bytes.length) {
        throw FormatException(
          'Truncated ${tag(at)} chunk size=$size available=${bytes.length - start}',
        );
      }
      if (tag(at) == 'fmt ' && size >= 16) {
        format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        rate = data.getUint32(start + 4, Endian.little);
        blockAlign = data.getUint16(start + 12, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
      }
      if (tag(at) == 'data') payload = size;
      at = start + size + (size & 1);
    }
    if (channels == null ||
        rate == null ||
        bits == null ||
        blockAlign == null ||
        payload == null ||
        rate == 0 ||
        blockAlign == 0) {
      throw const FormatException('Missing WAV format/data');
    }
    return {
      'channels': channels,
      'sampleRate': rate,
      'bitsPerSample': bits,
      'format': format!,
      'dataBytes': payload,
      'seconds': payload / blockAlign / rate,
      'fileBytes': bytes.length,
    };
  }

  /// Exercises the unmodified default extractor three times per source.
  ///
  /// 对每个源运行三次未修改的默认抽取器。
  Future<void> _audio() async {
    var needsDiagnostic = false;
    for (final source in ['stereo44100', 'mono48000']) {
      for (var run = 1; run <= 3; run++) {
        final uri =
            '$_host/$source.wav?cycle=$_cycle&run=$run&t=${DateTime.now().microsecondsSinceEpoch}';
        final extractor = MovaAudioExtractor();
        String? path;
        _log('V2_BEGIN source=$source run=$run uri=$uri extractor=default');
        try {
          // This guard bounds the harness, never supplies a success verdict.
          // 此超时仅限制验收脚本，绝不提供成功判据。
          path = await extractor
              .extractWav(uri)
              .timeout(const Duration(seconds: 25));
          if (path == null) {
            needsDiagnostic = true;
            _check(
              'V2_WAV',
              false,
              'source=$source run=$run result=null channels=unavailable sampleRate=unavailable bitsPerSample=unavailable seconds=unavailable',
            );
          } else {
            final header = _wav(await File(path).readAsBytes());
            final seconds = header['seconds']! as double;
            _check(
              'V2_WAV',
              header['sampleRate'] == 16000 &&
                  header['channels'] == 1 &&
                  (seconds - 8).abs() < 0.5,
              'source=$source run=$run path=$path ${header.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
            );
          }
        } on Object catch (e, st) {
          needsDiagnostic = true;
          _check(
            'V2_WAV',
            false,
            'source=$source run=$run error=${jsonEncode('$e')} stack=${jsonEncode('$st')}',
          );
        } finally {
          await extractor.dispose();
          if (path != null && await File(path).exists()) {
            await File(path).delete();
          }
        }
      }
    }
    if (needsDiagnostic) await _diagnose();
  }

  /// Repeats production property calls separately to expose swallowed errors.
  ///
  /// 独立重放生产属性调用，暴露被默认抽取器吞掉的错误。
  Future<void> _diagnose() async {
    final player = Player();
    final sub = player.stream.log.listen(
      (entry) => _log(
        'V2_DIAG_LOG prefix=${entry.prefix} level=${entry.level} text=${jsonEncode(entry.text)}',
      ),
    );
    final errors = player.stream.error.listen(
      (error) => _log('V2_DIAG_ERROR text=${jsonEncode(error)}'),
    );
    try {
      final native = player.platform as NativePlayer;
      for (final entry in {
        'vid': 'no',
        'ao': 'pcm',
        'ao-pcm-file': '/dev/null',
        'audio-samplerate': '16000',
        'audio-channels': 'mono',
        'untimed': 'yes',
      }.entries) {
        try {
          await native
              .setProperty(entry.key, entry.value)
              .timeout(const Duration(seconds: 5));
          final actual = await native.getProperty(entry.key);
          _log(
            'V2_DIAG_PROPERTY name=${entry.key} returned=true actual=${jsonEncode(actual)}',
          );
          final name = entry.key.toNativeUtf8();
          final value = entry.value.toNativeUtf8();
          try {
            final code = native.mpv.mpv_set_property_string(
              native.ctx,
              name.cast(),
              value.cast(),
            );
            final error = native.mpv
                .mpv_error_string(code)
                .cast<Utf8>()
                .toDartString();
            _log(
              'V2_DIAG_NATIVE name=${entry.key} code=$code error=${jsonEncode(error)}',
            );
          } finally {
            calloc.free(name);
            calloc.free(value);
          }
        } on Object catch (e, st) {
          _log(
            'V2_DIAG_EXCEPTION name=${entry.key} error=${jsonEncode('$e')} stack=${jsonEncode('$st')}',
          );
          break;
        }
      }
    } finally {
      await player.dispose();
      await sub.cancel();
      await errors.cancel();
    }
  }

  /// Runs the requested compile-time phase and reports uncaught failures.
  ///
  /// 运行编译期指定阶段，报告未处理失败。
  Future<void> _run() async {
    try {
      _cycle = (await _control())['cycle'] as int;
      _log('START release=$kReleaseMode');
      if (_phase == 1) {
        await _phaseOne();
      } else {
        await _phaseTwo();
      }
    } on Object catch (e, st) {
      _check(
        'HARNESS',
        false,
        'error=${jsonEncode('$e')} stack=${jsonEncode('$st')}',
      );
      _log('DONE failures=$_failures');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review fixes · real device verification'),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(_lines.join('\n\n')),
    ),
  );
}
