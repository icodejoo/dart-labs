import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/preview_config.dart';
import 'package:mova/src/core/preview/cache.dart';
import 'package:mova/src/core/preview/disk_cache.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/service.dart';
import 'package:mova/src/core/preview/two_level_cache.dart';
import 'package:mova/src/platform_impl/thumb_dir_impl.dart';

/// Verifies leasing, orphan selection and cache-driven disposal without sleeps.
///
/// 不用睡眠验证租约、无主目录选择以及由缓存驱动的释放。
void main() {
  late Directory temporary;
  late Directory root;
  late DateTime now;
  late Map<String, DateTime> modified;
  late List<MovaTempThumbDirProvider> providers;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mova_lease_test_');
    root = await Directory('${temporary.path}/mova_thumbs').create();
    now = DateTime.now();
    modified = {};
    providers = [];
  });

  tearDown(() async {
    for (final provider in providers) {
      await provider.dispose();
    }
    await temporary.delete(recursive: true);
  });

  /// Creates real directories with deterministic mtime observations.
  ///
  /// 创建真实目录，注入确定性的 mtime 观测值。
  Future<Directory> orphan(
    String name,
    Duration age, {
    bool lease = true,
  }) async {
    final directory = await Directory('${root.path}/$name').create();
    if (lease) await File('${directory.path}/.lease').writeAsString('');
    await File('${directory.path}/cached.thumb').writeAsBytes([1, 2, 3]);
    modified[name] = now.subtract(age);
    return directory;
  }

  /// Builds a provider using the per-test root, clock, mtimes and optional lock.
  ///
  /// 使用本用例的根目录、时钟、mtime 和可选锁构造 provider。
  MovaTempThumbDirProvider provider({
    Future<void> Function(RandomAccessFile)? lock,
    Future<Directory> Function()? temporaryDirectory,
  }) {
    final result = MovaTempThumbDirProvider.forTesting(
      temporaryDirectory: temporaryDirectory ?? () async => temporary,
      now: () => now,
      modified: (directory) async {
        final name = directory.uri.pathSegments.where((s) => s.isNotEmpty).last;
        return modified[name] ?? (await directory.stat()).modified;
      },
      lock: lock,
    );
    providers.add(result);
    return result;
  }

  test('(a) adopts newest orphan and removes other orphans', () async {
    final old = await orphan('engine_old', const Duration(days: 2));
    final newest = await orphan('engine_newest', const Duration(hours: 1));
    final middle = await orphan('engine_middle', const Duration(days: 1));
    final owner = provider();

    expect(await owner.resolve(), await newest.resolveSymbolicLinks());
    expect(await owner.resolve(), await newest.resolveSymbolicLinks());
    expect(await File('${newest.path}/cached.thumb').readAsBytes(), [1, 2, 3]);
    expect(await old.exists(), isFalse);
    expect(await middle.exists(), isFalse);
  });

  test(
    '(b) registry skips active directories before opening their lease',
    () async {
      final active = await orphan('engine_active', const Duration(days: 8));
      // First adopt it while still within the retention window.
      //
      // 先在保留期限内收养它。
      modified['engine_active'] = now;
      final owner = provider();
      final activePath = await owner.resolve();
      modified['engine_active'] = now.subtract(const Duration(days: 8));
      final idle = await orphan('engine_idle', const Duration(hours: 1));
      var locks = 0;
      final next = provider(
        lock: (handle) async {
          locks++;
          await handle.lock(FileLock.exclusive);
        },
      );

      expect(await next.resolve(), await idle.resolveSymbolicLinks());
      expect(locks, 1, reason: 'the active lease must never even be opened');
      expect(await active.exists(), isTrue);
      expect(await File('$activePath/cached.thumb').readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    '(c) removes all expired orphans and keeps exactly seven days',
    () async {
      final expired = await orphan('engine_expired', const Duration(days: 8));
      final justExpired = await orphan(
        'engine_just_expired',
        const Duration(days: 7, microseconds: 1),
      );
      final boundary = await orphan('engine_boundary', const Duration(days: 7));

      expect(await provider().resolve(), await boundary.resolveSymbolicLinks());
      expect(await expired.exists(), isFalse);
      expect(await justExpired.exists(), isFalse);
    },
  );

  test(
    '(c) creates a leased directory when every orphan has expired',
    () async {
      final expired = await orphan('engine_expired', const Duration(days: 8));
      final path = await provider().resolve();

      expect(await expired.exists(), isFalse);
      expect(path, isNot(expired.path));
      expect(await File('$path/.lease').exists(), isTrue);
    },
  );

  test(
    '(d) adopts newest legacy directory and removes other legacy orphans',
    () async {
      final old = await orphan(
        'engine_old',
        const Duration(days: 1),
        lease: false,
      );
      final recent = await orphan(
        'engine_recent',
        const Duration(hours: 1),
        lease: false,
      );
      final expired = await orphan(
        'engine_expired',
        const Duration(days: 8),
        lease: false,
      );

      expect(await provider().resolve(), await recent.resolveSymbolicLinks());
      expect(await File('${recent.path}/.lease').exists(), isTrue);
      expect(await File('${recent.path}/cached.thumb').exists(), isTrue);
      expect(await old.exists(), isFalse);
      expect(await expired.exists(), isFalse);
    },
  );

  test(
    'legacy expiry reads real directory mtime before creating lease',
    () async {
      final expired = await orphan(
        'engine_legacy',
        Duration.zero,
        lease: false,
      );
      final originalModified = (await expired.stat()).modified;
      final owner = MovaTempThumbDirProvider.forTesting(
        temporaryDirectory: () async => temporary,
        now: () => originalModified.add(const Duration(days: 8)),
      );
      providers.add(owner);

      await owner.resolve();
      expect(await expired.exists(), isFalse);
    },
  );

  test(
    '(e) concurrent providers resolve to different leased directories',
    () async {
      final idle = await orphan('engine_idle', Duration.zero);
      final first = provider();
      final second = provider();
      final paths = await Future.wait([first.resolve(), second.resolve()]);

      expect(paths.toSet(), hasLength(2));
      expect(paths, contains(await idle.resolveSymbolicLinks()));
      for (final path in paths) {
        expect(await Directory(path).exists(), isTrue);
        expect(await File('$path/.lease').exists(), isTrue);
      }
    },
  );

  test(
    'lock failure treats even an expired orphan as in use and closes handle',
    () async {
      final busy = await orphan('engine_busy', const Duration(days: 9));
      final idle = await orphan('engine_idle', const Duration(hours: 1));
      RandomAccessFile? failedHandle;
      final next = provider(
        lock: (handle) async {
          if (failedHandle == null) {
            // Identify the busy directory by a unique lease payload.
            //
            // 用唯一租约内容识别在用目录。
            await handle.setPosition(0);
            if (String.fromCharCodes(await handle.read(4)) == 'busy') {
              failedHandle = handle;
              throw FileSystemException('simulated lock contention');
            }
          }
          await handle.lock(FileLock.exclusive);
        },
      );
      await File('${busy.path}/.lease').writeAsString('busy');

      expect(await next.resolve(), await idle.resolveSymbolicLinks());
      expect(await busy.exists(), isTrue);
      expect(failedHandle, isNotNull);
      await expectLater(
        failedHandle!.length(),
        throwsA(isA<FileSystemException>()),
      );
      // Failure must also remove the temporary registry reservation.
      //
      // 加锁失败也必须移除临时注册预占。
      await next.dispose();
      now = now.add(const Duration(days: 10));
      await provider().resolve();
      expect(await busy.exists(), isFalse);
    },
  );

  test(
    'orphan deletion closes every acquired handle before recursive delete',
    () async {
      final expired = await orphan('engine_expired', const Duration(days: 8));
      final handles = <RandomAccessFile>[];
      final owner = provider(
        lock: (handle) async {
          handles.add(handle);
          await handle.lock(FileLock.exclusive);
        },
      );
      await owner.resolve();
      expect(await expired.exists(), isFalse);
      await owner.dispose();
      for (final handle in handles) {
        await expectLater(handle.length(), throwsA(isA<FileSystemException>()));
      }
    },
  );

  test('dispose releases OS lease and registry for cache reuse', () async {
    final first = provider();
    final path = await first.resolve();
    await File('$path/kept.thumb').writeAsBytes([4, 5]);
    await first.dispose();
    await first.dispose();

    expect(await provider().resolve(), path);
    expect(await File('$path/kept.thumb').readAsBytes(), [4, 5]);
    await expectLater(first.resolve(), throwsA(isA<FileSystemException>()));
  });

  test(
    'dispose waits for an in-flight resolve and does not leak its lease',
    () async {
      final entered = Completer<void>();
      final resume = Completer<Directory>();
      final first = provider(
        temporaryDirectory: () {
          entered.complete();
          return resume.future;
        },
      );
      final resolving = first.resolve();
      await entered.future;
      final closing = first.dispose();
      resume.complete(temporary);
      final path = await resolving;
      await closing;

      expect(await provider().resolve(), path);
    },
  );

  test('disposing an unused provider does not resolve a directory', () async {
    var calls = 0;
    final unused = provider(
      temporaryDirectory: () async {
        calls++;
        return temporary;
      },
    );
    await unused.dispose();
    expect(calls, 0);
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'failed initialization drains cleanly and does not block next scan',
    () async {
      final broken = provider(
        temporaryDirectory: () async {
          throw FileSystemException('unavailable temporary directory');
        },
      );
      await expectLater(broken.resolve(), throwsA(isA<FileSystemException>()));
      await broken.dispose();
      final path = await provider().resolve();
      expect(await File('$path/.lease').exists(), isTrue);
    },
  );

  test('scan leaves unrelated files and directories alone', () async {
    final unrelated = await Directory('${root.path}/other_cache').create();
    final file = await File('${root.path}/engine_file').writeAsString('keep');
    await provider().resolve();
    expect(await unrelated.exists(), isTrue);
    expect(await file.readAsString(), 'keep');
  });

  for (final clear in [false, true]) {
    test(
      'preview disposal releases disk lease with clearOnDispose=$clear',
      () async {
        final owner = provider();
        final disk = MovaDiskThumbCache(dir: owner);
        final cache = MovaTwoLevelCache(
          memory: MovaMemoryThumbCache(),
          disk: disk,
        );
        final service = MovaPreviewService(
          config: MovaPreviewConfig(clearOnDispose: clear),
          cache: cache,
          probe: MovaAlwaysAllowNetProbe(),
          sources: const [],
        );
        // Leave a write pending so disposal must drain it before releasing.
        //
        // 留下一次待完成写入，确保销毁先排空工作再释放租约。
        final writing = disk.write('kept', Uint8List.fromList([7, 8]));
        final originalPath = owner.resolve();
        await service.dispose();
        await writing;
        final next = provider();
        final nextDisk = MovaDiskThumbCache(dir: next);
        addTearDown(nextDisk.dispose);
        expect(await nextDisk.read('kept'), clear ? isNull : [7, 8]);
        expect(await next.resolve(), await originalPath);
      },
    );
  }
}
