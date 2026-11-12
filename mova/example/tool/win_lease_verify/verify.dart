import 'dart:async';
import 'dart:convert';
import 'dart:io';

const deadline = Duration(seconds: 40);
late Directory repository;
late Directory evidence;
late Directory temporary;
late File report;
final workers = <Worker>[];
final results = <Map<String, Object?>>[];

/// Persists each observation immediately, including failures.
///
/// 立即落盘每条观测，包含失败证据。
void log(String line) {
  report.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  stdout.writeln(line);
}

/// Rejects an invariant without relying on debug-mode asserts.
///
/// 不依赖调试断言，显式拒绝不满足的不变量。
void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Gets the final directory component on Windows or POSIX.
///
/// 读取 Windows 或 POSIX 路径的最后一个目录名。
String nameOf(String path) =>
    Directory(path).uri.pathSegments.where((s) => s.isNotEmpty).last;

/// Creates a canonical root so oracle paths use the same Windows spelling.
///
/// 创建规范根目录，确保判据与生产代码使用一致的 Windows 路径表示。
Future<Directory> makeRoot(String relative) async {
  final root = await Directory(
    '${temporary.path}/$relative/cache',
  ).create(recursive: true);
  return Directory(await root.resolveSymbolicLinks());
}

/// Saves owned process receipts before temporary source deletion.
///
/// 删除临时源码前保存自有进程的退出凭据。
void manifest() {
  File('${evidence.path}/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'controllerPid': pid,
      'temporary': temporary.path,
      'workers': workers
          .map(
            (w) => {
              'id': w.id,
              'launcherPid': w.process.pid,
              'vmPid': w.vmPid,
              'exit': w.exit,
              'forceKilled': w.forceKilled,
            },
          )
          .toList(),
    }),
    flush: true,
  );
}

/// Owns one console process and an event mailbox backed by raw logs.
///
/// 管理一个控制台进程及由原始日志支撑的事件收件箱。
class Worker {
  final String id;
  final Process process;
  final events = <Map<String, dynamic>>[];
  Completer<void> changed = Completer<void>();
  late Future<void> drained;
  int? exit;
  int? vmPid;
  bool forceKilled = false;
  Map<String, dynamic>? ready;
  Future<void> commandQueue = Future<void>.value();

  /// Connects independent stdout/stderr drains before awaiting any event.
  ///
  /// 等待事件前接通独立的 stdout/stderr 读取流。
  Worker(this.id, this.process) {
    final output = File('${evidence.path}/$id.stdout.ndjson');
    final errors = File('${evidence.path}/$id.stderr.txt');
    final outDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          output.writeAsStringSync(
            '$line\n',
            mode: FileMode.append,
            flush: true,
          );
          try {
            final event = jsonDecode(line) as Map<String, dynamic>;
            events.add(event);
            vmPid = event['pid'] as int;
            if (event['event'] == 'READY') ready = event;
            log('EVENT $line');
          } catch (error) {
            events.add({
              'event': 'ERROR',
              'error': 'Invalid protocol: $error: $line',
            });
          }
          pulse();
        });
    final errDone = process.stderr.transform(utf8.decoder).forEach((chunk) {
      errors.writeAsStringSync(chunk, mode: FileMode.append, flush: true);
      log('STDERR ${jsonEncode({'id': id, 'text': chunk})}');
    });
    final exited = process.exitCode.then((code) {
      exit = code;
      log(
        'EXIT ${jsonEncode({'id': id, 'launcherPid': process.pid, 'vmPid': vmPid, 'code': code})}',
      );
      manifest();
      pulse();
    });
    drained = Future.wait([outDone, errDone, exited]).then((_) {});
  }

  /// Wakes mailbox waiters without dropping already recorded events.
  ///
  /// 唤醒收件箱等待者，历史事件保持可读。
  void pulse() {
    final previous = changed;
    changed = Completer<void>();
    previous.complete();
  }

  /// Waits for an actual event, treating errors/exits as immediate failures.
  ///
  /// 等待真实事件，错误或提前退出立即失败。
  Future<Map<String, dynamic>> event(String type, {String? request}) async {
    return (() async {
      while (true) {
        final errors = events.where((e) => e['event'] == 'ERROR');
        if (errors.isNotEmpty) throw StateError('$id: ${errors.first}');
        final matches = events.where(
          (e) =>
              e['event'] == type &&
              (request == null || e['request'] == request),
        );
        if (matches.isNotEmpty) return matches.first;
        if (exit != null) throw StateError('$id exited=$exit before $type');
        await changed.future;
      }
    })().timeout(
      deadline,
      onTimeout: () => throw TimeoutException('$id waiting $type'),
    );
  }

  /// Sends a flushed command through the process stdin pipe.
  ///
  /// 通过进程 stdin 管道发送并刷新命令。
  Future<void> send(String command, {String? request}) {
    final sent = commandQueue.then((_) async {
      process.stdin.writeln(
        jsonEncode({'command': command, 'request': request}),
      );
      await process.stdin.flush();
    });
    commandQueue = sent.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return sent;
  }

  /// Requires a live owner to re-read its own unforgeable token.
  ///
  /// 要求存活的持有进程重新读取自身唯一标记。
  Future<void> check(String request) async {
    require(exit == null, '$id must still be alive');
    await send('check', request: request);
    await event('CHECKED', request: request);
  }

  /// Disposes explicitly and requires an error-free OS exit.
  ///
  /// 显式释放租约，并要求操作系统确认正常退出。
  Future<void> stop() async {
    if (exit != null) {
      require(exit == 0, '$id unexpectedly exited=$exit');
      return;
    }
    await send('stop');
    await event('RELEASED');
    await drained.timeout(deadline);
    require(exit == 0, '$id stop exit=$exit');
  }

  /// Uses taskkill /F on exactly our launcher tree, without dispose.
  ///
  /// 对自己的启动进程树执行 taskkill /F，不调用 dispose。
  Future<void> kill() async {
    forceKilled = true;
    final killed = await Process.run(
      '${Platform.environment['SystemRoot']}\\System32\\taskkill.exe',
      ['/F', '/T', '/PID', '${process.pid}'],
      runInShell: false,
    ).timeout(deadline);
    log(
      'TASKKILL ${jsonEncode({'id': id, 'launcherPid': process.pid, 'vmPid': vmPid, 'exit': killed.exitCode, 'stdout': killed.stdout, 'stderr': killed.stderr})}',
    );
    require(killed.exitCode == 0, '$id taskkill failed');
    await drained.timeout(deadline);
    require(exit != null && exit != 0, '$id must have a killed OS exit');
    require(
      !events.any((e) => e['event'] == 'RELEASED'),
      '$id disposed before kill',
    );
    manifest();
  }
}

/// Starts a pure Dart worker with pipes and no shell/window.
///
/// 使用管道、无 shell/窗口方式启动纯 Dart 子进程。
Future<Worker> start(
  String id,
  Directory root, {
  bool gate = false,
  String? probeAfterKill,
}) async {
  await root.create(recursive: true);
  final config = jsonEncode({
    'id': id,
    'root': root.path,
    'gate': gate,
    'probeAfterKill': probeAfterKill,
  });
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', '${temporary.path}/worker.dart', config],
    workingDirectory: temporary.path,
    runInShell: false,
    mode: ProcessStartMode.normal,
  );
  final worker = Worker(id, process);
  workers.add(worker);
  manifest();
  log(
    'START ${jsonEncode({'id': id, 'launcherPid': process.pid, 'root': root.path})}',
  );
  await worker.event('ARMED');
  return worker;
}

/// Acquires a real OS lease from the independent controller process.
///
/// 在独立的控制进程中尝试获取真实操作系统租约。
Future<bool> leaseProbe(String directory) async {
  final handle = await File('$directory/.lease').open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.exclusive);
    return true;
  } on FileSystemException catch (error) {
    log(
      'LOCK_DENIED ${jsonEncode({'pid': pid, 'directory': directory, 'error': '$error'})}',
    );
    return false;
  } finally {
    await handle.close();
  }
}

/// Checks directory and marker contents while its process retains ownership.
///
/// 在进程仍持有租约时检查目录及标记内容。
Future<void> intact(Worker worker) async {
  final ready = worker.ready!;
  require(worker.exit == null, '${worker.id} must be alive');
  require(
    await Directory(ready['directory'] as String).exists(),
    '${worker.id} directory deleted',
  );
  final read = await File(
    '${ready['directory']}/${ready['marker']}',
  ).readAsString();
  require(read == ready['token'], '${worker.id} token differs');
  log(
    'TOKEN_OK ${jsonEncode({'pid': worker.vmPid, 'directory': ready['directory'], 'token': read})}',
  );
}

/// Lists actual engine directories, ignoring the root scan lock file.
///
/// 列出真实 engine 目录，忽略根目录扫描锁文件。
Future<List<Directory>> engines(Directory root) async =>
    (await root.list(followLinks: false).toList())
        .whereType<Directory>()
        .where((d) => nameOf(d.path).startsWith('engine_'))
        .toList();

/// Queues all resolvers behind a real root lock using event barriers.
///
/// 通过事件屏障将所有解析进程排在真实根锁之后。
Future<void> compete(List<Worker> participants, Directory root) async {
  final gate = await File('${root.path}/.scan').open(mode: FileMode.append);
  await gate.lock(FileLock.exclusive);
  try {
    await Future.wait(participants.map((w) => w.send('go')));
    await Future.wait(
      participants.map((w) async {
        final probe = await w.event('GATE_PROBE');
        require(probe['acquired'] == false, '${w.id} did not contend on .scan');
        await w.event('RESOLVE_BEGIN');
      }),
    );
    log(
      'GATE_RELEASE ${jsonEncode({'pid': pid, 'root': root.path, 'contenders': participants.map((w) => w.vmPid).toList()})}',
    );
  } finally {
    await gate.close();
  }
  // Observe each completion separately so A can be checked during S4 below.
  // 下方 S4 单独观察每次完成，在其间检查 A。
}

/// Records one scenario result, retaining diagnostics and continuing repeats.
///
/// 记录单场景结果，保留诊断并继续独立重复验证。
Future<void> runCase(
  String scenario,
  int iteration,
  List<Worker> owned,
  Map<String, Object?> detail,
  Future<void> Function() action,
) async {
  var status = 'PASS';
  try {
    await action();
  } catch (error, stack) {
    status = 'FAIL';
    detail['error'] = '$error';
    log('FAILURE $scenario/$iteration $error\n$stack');
    File(
      '${evidence.path}/$scenario-$iteration.failure.txt',
    ).writeAsStringSync('$error\n$stack', flush: true);
  }
  final result = <String, Object?>{
    'scenario': scenario,
    'iteration': iteration,
    'status': status,
    'pid': pid,
    'pids': owned.map((w) => w.vmPid ?? w.process.pid).toList(),
    'directories': owned
        .where((w) => w.ready != null)
        .map((w) => nameOf(w.ready!['directory'] as String))
        .toList(),
    ...detail,
  };
  results.add(result);
  log('WRFV ${jsonEncode(result)}');
}

/// Runs linked mutual exclusion and force-kill recovery scenarios.
///
/// 运行串联的互斥与强杀回收场景。
Future<void> mutualAndRecovery(int iteration) async {
  final root = await makeRoot('S1_S2_$iteration');
  final owned = <Worker>[];
  Worker? a;
  Worker? b;
  await runCase('S1', iteration, owned, {}, () async {
    a = await start('r${iteration}_A', root);
    owned.add(a!);
    await a!.send('go');
    final da = await a!.event('READY');
    require(
      !await leaseProbe(da['directory'] as String),
      'A lease not exclusive',
    );
    b = await start('r${iteration}_B', root);
    owned.add(b!);
    await b!.send('go');
    final db = await b!.event('READY');
    require(da['directory'] != db['directory'], 'B adopted live A directory');
    require(
      (await engines(root)).length == 2,
      'S1 expected two live directories',
    );
    await Future.wait(owned.map(intact));
    await Future.wait(owned.map((w) => w.check('S1-final')));
    require(
      !await leaseProbe(da['directory'] as String),
      'A lease lost after B scan',
    );
  });
  final detail = <String, Object?>{};
  await runCase('S2', iteration, owned, detail, () async {
    require(
      a?.ready != null && b?.ready != null,
      'S1 readiness prerequisite missing',
    );
    final da = a!.ready!['directory'] as String;
    await b!.stop();
    await a!.check('S2-before-force-kill');
    await a!.kill();
    final candidates = await engines(root);
    require(
      candidates.length == 2,
      'Expected two orphans after A kill/B dispose',
    );
    final mtimes = <String, int>{};
    for (final d in candidates) {
      mtimes[d.path] = (await d.stat()).modified.microsecondsSinceEpoch;
    }
    final latest = mtimes.values.reduce((a, b) => a > b ? a : b);
    final expected = mtimes.keys.where((p) => mtimes[p] == latest).toList();
    detail['orphanMtimeUs'] = mtimes;
    detail['expectedNewest'] = expected.map(nameOf).toList();
    log(
      'ORPHANS ${jsonEncode({'iteration': iteration, 'mtimes': mtimes, 'expected': expected})}',
    );
    final c = await start('r${iteration}_C', root, probeAfterKill: da);
    owned.add(c);
    await c.send('go');
    final proof = await c.event('DEAD_OWNER_PROBE');
    require(proof['acquired'] == true, 'C could not acquire killed A lease');
    final dc = await c.event('READY');
    final adopted = dc['directory'] as String;
    require(
      expected.contains(adopted),
      'C did not adopt newest actual-mtime orphan',
    );
    final previous = adopted == da ? a! : b!;
    final original = await File(
      '$adopted/${previous.ready!['marker']}',
    ).readAsString();
    require(
      original == previous.ready!['token'],
      'Adopted cache token damaged',
    );
    final remaining = await engines(root);
    require(
      remaining.length == 1 && remaining.single.path == adopted,
      'Expected one adopted orphan and other orphan deleted',
    );
    for (final path in mtimes.keys.where((p) => p != adopted)) {
      require(
        !await Directory(path).exists(),
        'Windows orphan deletion failed',
      );
    }
    await intact(c);
    await c.check('S2-final');
    require(!await leaseProbe(adopted), 'C must retain OS lease');
    detail['cAcquiredKilledLease'] = true;
    detail['adopted'] = nameOf(adopted);
    detail['remainingCount'] = remaining.length;
    detail['deleted'] = mtimes.keys
        .where((p) => p != adopted)
        .map(nameOf)
        .toList();
    await c.stop();
  });
  await cleanupWorkers(owned);
}

/// Exercises four independent simultaneous resolvers with live token checks.
///
/// 用存活进程标记检查四个独立并发解析者。
Future<void> fourWay(int iteration) async {
  final root = await makeRoot('S3_$iteration');
  final owned = <Worker>[];
  await runCase('S3', iteration, owned, {}, () async {
    owned.addAll(
      await Future.wait(
        List.generate(4, (i) => start('s3_${iteration}_$i', root, gate: true)),
      ),
    );
    await compete(owned, root);
    await Future.wait(owned.map((w) => w.event('READY')));
    require(
      owned.map((w) => w.vmPid).toSet().length == 4,
      'Need four distinct OS PIDs',
    );
    require(
      owned.map((w) => w.ready!['directory']).toSet().length == 4,
      'Concurrent workers shared a directory',
    );
    require(
      (await engines(root)).length == 4,
      'Expected four retained directories',
    );
    await Future.wait(owned.map(intact));
    await Future.wait(owned.map((w) => w.check('S3-all-live')));
    await Future.wait(owned.map((w) => w.stop()));
  });
  await cleanupWorkers(owned);
}

/// Contends two scans against one held directory and one legacy orphan.
///
/// 两个扫描者竞争一个在用目录与一个遗留无主目录。
Future<void> deletionRace(int iteration) async {
  final root = await makeRoot('S4_$iteration');
  final owned = <Worker>[];
  final detail = <String, Object?>{};
  await runCase('S4', iteration, owned, detail, () async {
    final a = await start('s4_${iteration}_A', root);
    owned.add(a);
    await a.send('go');
    final held = (await a.event('READY'))['directory'] as String;
    final orphanFixture = await Directory(
      '${root.path}/engine_legacy_orphan',
    ).create();
    final orphan = Directory(await orphanFixture.resolveSymbolicLinks());
    final orphanToken =
        'legacy:$pid:$iteration:${DateTime.now().microsecondsSinceEpoch}';
    await File(
      '${orphan.path}/legacy.token',
    ).writeAsString(orphanToken, flush: true);
    require(
      !await File('${orphan.path}/.lease').exists(),
      'Fixture must have no lease',
    );
    require(
      (await engines(root)).length == 2,
      'S4 fixture requires exactly two directories',
    );
    final heldDeletes = <String>[];
    Object? watchError;
    final watch = root
        .watch(
          events: FileSystemEvent.delete | FileSystemEvent.move,
          recursive: true,
        )
        .listen(
          (event) {
            log(
              'FS_EVENT ${jsonEncode({'type': event.type, 'path': event.path})}',
            );
            final path = event.path.replaceAll('\\', '/').toLowerCase();
            final prefix = held.replaceAll('\\', '/').toLowerCase();
            if (path == prefix || path.startsWith('$prefix/')) {
              heldDeletes.add(event.path);
            }
          },
          onError: (Object error) {
            watchError = error;
          },
        );
    try {
      final scanners = await Future.wait(
        List.generate(
          2,
          (i) => start('s4_${iteration}_scan$i', root, gate: true),
        ),
      );
      owned.addAll(scanners);
      await compete(scanners, root);
      await Future.wait(
        scanners.map((w) async {
          await w.event('READY');
          await intact(a);
          await a.check('S4-after-${w.id}');
        }),
      );
      require(
        owned.map((w) => w.ready!['directory']).toSet().length == 3,
        'S4 shared directory or adopted held A',
      );
      final adopters = scanners
          .where((w) => w.ready!['directory'] == orphan.path)
          .toList();
      final exists = await orphan.exists();
      require(
        !exists || adopters.length == 1,
        'Orphan neither removed nor uniquely adopted',
      );
      if (exists) {
        require(
          await File('${orphan.path}/legacy.token').readAsString() ==
              orphanToken,
          'Adopted legacy token changed',
        );
      }
      require(
        (await engines(root)).length == 3,
        'S4 unexpected directory count',
      );
      await Future.wait(owned.map(intact));
      await Future.wait(owned.map((w) => w.check('S4-final')));
      require(
        !await leaseProbe(held),
        'Held A lease lost during concurrent scans',
      );
      require(
        heldDeletes.isEmpty,
        'Held directory deletion/move observed: $heldDeletes',
      );
      require(watchError == null, 'Filesystem watcher failed: $watchError');
      detail['orphan'] = nameOf(orphan.path);
      detail['orphanOutcome'] = exists ? 'adopted-exactly-once' : 'deleted';
      detail['adopterPids'] = adopters.map((w) => w.vmPid).toList();
      detail['heldDeleteEvents'] = heldDeletes;
      detail['remainingCount'] = (await engines(root)).length;
      await Future.wait(owned.map((w) => w.stop()));
    } finally {
      await watch.cancel();
    }
  });
  await cleanupWorkers(owned);
}

/// Reaps only our children, even when a scenario failed halfway through.
///
/// 即使场景中途失败，也仅回收自己创建的子进程。
Future<void> cleanupWorkers(List<Worker> owned) async {
  for (final worker in owned) {
    if (worker.exit == null) {
      try {
        await worker.stop().timeout(const Duration(seconds: 8));
      } catch (error) {
        log('CLEANUP_FORCE ${worker.id} $error');
        if (worker.exit == null) await worker.kill();
      }
    }
    await worker.drained.timeout(deadline);
  }
}

/// Builds an audited pure-Dart import adapter, preserving the full class body.
///
/// 构建可审计的纯 Dart 导入适配层，保留完整类正文。
Future<void> prepare() async {
  final source = await File(
    '${repository.path}/lib/src/platform_impl/thumb_dir_impl.dart',
  ).readAsString();
  var mirror = source;
  final replacements = <String, String>{
    "import 'package:meta/meta.dart';": "import 'annotation_stub.dart';",
    "import 'package:path_provider/path_provider.dart';":
        "import 'temporary_stub.dart';",
    "import '../core/preview/dir_lease.dart';":
        "import '${repository.uri.resolve('lib/src/core/preview/dir_lease.dart')}';",
    "import '../core/preview/dir_provider.dart';":
        "import '${repository.uri.resolve('lib/src/core/preview/dir_provider.dart')}';",
  };
  for (final replacement in replacements.entries) {
    require(
      replacement.key.allMatches(mirror).length == 1,
      'Unexpected import layout',
    );
    mirror = mirror.replaceFirst(replacement.key, replacement.value);
  }
  final bodyOffset = source.indexOf('/// A temporary thumbnail directory');
  require(bodyOffset > 0, 'Missing class body boundary');
  require(
    source.substring(bodyOffset) ==
        mirror.substring(mirror.indexOf('/// A temporary thumbnail directory')),
    'Production class body must be identical',
  );
  // The reverse comparison also guards against modifications outside the body.
  // 逆向比较也防止正文之外出现非白名单改动。
  var reversed = mirror;
  for (final replacement in replacements.entries) {
    reversed = reversed.replaceFirst(replacement.value, replacement.key);
  }
  require(reversed == source, 'Unexpected non-import adapter changes');
  await File('${temporary.path}/lease_under_test.dart').writeAsString(mirror);
  await File(
    '${temporary.path}/annotation_stub.dart',
  ).writeAsString('const visibleForTesting = Object();\n');
  await File('${temporary.path}/temporary_stub.dart').writeAsString(
    "import 'dart:io';\nFuture<Directory> getTemporaryDirectory() => throw UnsupportedError('path_provider excluded; use forTesting');\n",
  );
  await File('${temporary.path}/worker.dart').writeAsString(
    await File(
      '${repository.path}/example/tool/win_lease_verify/worker.dart.template',
    ).readAsString(),
  );
  await File(
    '${evidence.path}/source-import-adapter.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(replacements));
  // Keep auditable generated sources in evidence, even on failure.
  // 即使失败也在证据中保留可审计的生成源码。
  for (final file in [
    'lease_under_test.dart',
    'annotation_stub.dart',
    'temporary_stub.dart',
    'worker.dart',
  ]) {
    await File('${temporary.path}/$file').copy('${evidence.path}/$file.txt');
  }
  log(
    'SOURCE_FIDELITY class_body_identical=true reverse_import_transform_identical=true lock_modified_now_injections=false',
  );
}

/// Runs all twelve results and always verifies dedicated temporary cleanup.
///
/// 运行全部十二项结果，并始终验证专用临时目录清理。
Future<void> main(List<String> arguments) async {
  repository = Directory(arguments[0]).absolute;
  evidence = Directory(arguments[1]).absolute;
  report = File(arguments[2]).absolute;
  require(Platform.isWindows, 'Windows is required');
  temporary = await Directory.systemTemp.createTemp('mova_wrfv_');
  manifest();
  var fatal = false;
  try {
    log(
      '\nWINDOWS CROSS-PROCESS LEASE VERIFICATION ${DateTime.now().toIso8601String()}',
    );
    log(
      'REPRO powershell -NoProfile -ExecutionPolicy Bypass -File example/tool/win_lease_verify/verify.ps1',
    );
    log(
      'ENV ${jsonEncode({'pid': pid, 'os': Platform.operatingSystemVersion, 'dart': Platform.version, 'executable': Platform.resolvedExecutable, 'repository': repository.path, 'temporary': temporary.path, 'evidence': evidence.path})}',
    );
    log(
      await File(
        '${repository.path}/example/tool/win_lease_verify/measurement.txt',
      ).readAsString(),
    );
    log(
      'COVERAGE LIMIT: unchanged production class body via four-import adapter; actual core interfaces imported; path_provider/Flutter integration excluded. No media imports or playback.',
    );
    await prepare();
    for (var iteration = 1; iteration <= 3; iteration++) {
      await mutualAndRecovery(iteration);
    }
    for (var iteration = 1; iteration <= 3; iteration++) {
      await fourWay(iteration);
    }
    for (var iteration = 1; iteration <= 3; iteration++) {
      await deletionRace(iteration);
    }
  } catch (error, stack) {
    fatal = true;
    log('FATAL $error\n$stack');
  } finally {
    try {
      await cleanupWorkers(workers);
      require(
        workers.every((w) => w.exit != null),
        'An owned process is still running',
      );
      final resolved = await temporary.resolveSymbolicLinks();
      final systemTemp = await Directory.systemTemp.resolveSymbolicLinks();
      require(
        Directory(resolved).parent.path.toLowerCase() ==
                systemTemp.toLowerCase() &&
            nameOf(resolved).startsWith('mova_wrfv_'),
        'Unsafe recursive cleanup path: $resolved',
      );
      log('CLEANUP_TARGET_VERIFIED $resolved');
      await Directory(resolved).delete(recursive: true);
      require(
        !await temporary.exists(),
        'Dedicated temporary directory remains',
      );
      log(
        'CLEANUP all_owned_worker_exits_observed=true temporary_deleted=true',
      );
    } catch (error, stack) {
      fatal = true;
      log('CLEANUP_FAILURE $error\n$stack');
    }
    manifest();
    File('${evidence.path}/results.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(results),
      flush: true,
    );
    for (final scenario in ['S1', 'S2', 'S3', 'S4']) {
      final matching = results.where((r) => r['scenario'] == scenario).toList();
      log(
        'SUMMARY $scenario PASS=${matching.where((r) => r['status'] == 'PASS').length} FAIL=${matching.where((r) => r['status'] == 'FAIL').length} total=${matching.length}',
      );
    }
    final passed = results.where((r) => r['status'] == 'PASS').length;
    log(
      'FINAL_RESULT PASS=$passed FAIL=${results.length - passed} total=${results.length} fatal=$fatal',
    );
    exitCode = !fatal && results.length == 12 && passed == 12 ? 0 : 1;
  }
}
