import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cacheman/cacheman.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:cacheman_example/get_storage_cache.dart';

/// 为持久化测试提供临时目录。
class _DocumentsDirectory extends PathProviderPlatform {
  /// 保存测试目录。
  _DocumentsDirectory(this.path);

  /// 文档目录路径。
  final String path;

  /// 返回测试专用路径。
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// 共用逻辑键。
const _key = 'entry';
/// 另一逻辑键。
const _other = 'other';
/// 共用字符串值。
const _value = 'value';
/// 原始异常断言字段。
const _causeLabel = 'cause';
/// 避免测试期间自动保存的延迟。
const _longDelay = Duration(seconds: 10);

/// 验证示例适配器的真实磁盘、通知及异常契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  var seq = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cacheman_adapter_');
    PathProviderPlatform.instance = _DocumentsDirectory(dir.path);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // get_storage retains Windows file handles; cleanup is best-effort.
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      /* 后端仍持有文件句柄。 */
    }
  });

  /// 创建独立容器名称。
  String name() => 'adapter_${seq++}';

  /// 初始化真实持久化适配器。
  Future<GetStorageCache> real(
    String name, [
    CachemanOptions options = const CachemanOptions(),
  ]) async {
    final cache = GetStorageCache(
      container: name,
      path: dir.path,
      options: options,
    );
    await cache.ensureInitialized();
    return cache;
  }

  test(
    'real initialization table replacement ignores stale single-key changes',
    () async {
      final id = name();
      await File('${dir.path}/$id.gs').writeAsString(
        jsonEncode({
          _key: defaultSerialize(CacheEntity(value: 1, createdAt: 1)),
        }),
      );
      final cache = GetStorageCache(container: id, path: dir.path);
      final values = <int?>[];
      final others = <int?>[];
      addTearDown(cache.watch<int>(_key, values.add, includeOwnWrites: true));
      addTearDown(cache.watch<int>(_other, others.add, includeOwnWrites: true));
      cache.box.writeInMemory(
        _other,
        defaultSerialize(CacheEntity(value: 2, createdAt: 1)),
      );
      expect(values, isEmpty);
      expect(others, [2]);
      await cache.ensureInitialized();
      expect(values, [null, 1]);
      expect(others, [2, null, null]);
    },
  );

  test(
    'real deferred writes flush to disk and deletes still save immediately',
    () async {
      final id = name();
      final cache = await real(
        id,
        const CachemanOptions(flushDelay: _longDelay),
      );
      final file = File('${dir.path}/$id.gs');
      cache.write(_key, _value);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(jsonDecode(await file.readAsString()), isEmpty);
      cache.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (jsonDecode(await file.readAsString()) as Map).containsKey(_key),
        isTrue,
      );
      cache.write(_other, _value);
      cache.remove(_key);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stored = jsonDecode(await file.readAsString()) as Map;
      expect(stored.containsKey(_key), isFalse);
      expect(stored.containsKey(_other), isTrue);
      cache.flush();
    },
  );

  test(
    'R4 real get_storage handler errors propagate unchanged through Zone',
    () async {
      final id = name();
      final failure = StateError('watch handler');
      final watcherErrors = <Object>[];
      final writerErrors = <Object>[];
      final zoneErrors = <Object>[];
      final watcher = await real(
        id,
        CachemanOptions(
          onError: (_, error) {
            watcherErrors.add(error);
            throw failure;
          },
        ),
      );
      final writer = await real(
        id,
        CachemanOptions(onError: (_, error) => writerErrors.add(error)),
      );
      final callbackFailure = StateError('watch callback');
      final stop = watcher.watch<int>(_key, (_) => throw callbackFailure);
      addTearDown(stop);
      final mutations = [
        () => writer.write(_key, _value),
        () => writer.remove(_key),
        writer.erase,
      ];
      for (var i = 0; i < mutations.length; i++) {
        runZonedGuarded<void>(() {
          expect(mutations[i], returnsNormally);
        }, (error, trace) => zoneErrors.add(error));
        await Future<void>.delayed(Duration.zero);
        expect(writerErrors, isEmpty);
        expect(zoneErrors, hasLength(i + 1));
        expect(zoneErrors.last, same(failure));
      }
      expect(watcherErrors, [
        isA<TypeMismatchError>(),
        isA<WatchError>().having(
          (e) => e.cause,
          _causeLabel,
          same(callbackFailure),
        ),
        isA<WatchError>().having(
          (e) => e.cause,
          _causeLabel,
          same(callbackFailure),
        ),
      ]);
    },
  );

  test(
    'lazy default initialization still loads the explicitly supplied path',
    () async {
      final root = await Directory.systemTemp.createTemp('cacheman_lazy_path_');
      final selected = await Directory('${root.path}/explicit').create();
      final fallback = await Directory('${root.path}/implicit').create();
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _DocumentsDirectory(fallback.path);
      try {
        final name = 'cacheman_lazy_${DateTime.now().microsecondsSinceEpoch}';
        final cache = GetStorageCache(container: name, path: selected.path);
        // Seed after facade construction: loading must wait until first backend access.
        // 在语义层构造后植入，确保首次访问后端才加载。
        await File('${selected.path}/$name.gs').writeAsString(
          jsonEncode({
            _key: defaultSerialize(CacheEntity(value: _value, createdAt: 1)),
          }),
        );
        await cache.ensureInitialized();
        expect(cache.read<String>(_key), _value);
        expect(File('${fallback.path}/$name.gs').existsSync(), isFalse);
        expect(cache.box, same(GetStorage(name)));
      } finally {
        PathProviderPlatform.instance = previous;
        // GetStorage retains Windows handles; cleanup is best-effort, as in existing tests.
        // GetStorage 保留 Windows 句柄，与现有测试一样只尽力清理。
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          /* retained file handle / 文件句柄仍被持有 */
        }
      }
    },
  );
}
