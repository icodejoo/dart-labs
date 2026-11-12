import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/fetcher.dart';
import 'package:mova/src/core/stt/model_dir_provider.dart';
import 'package:mova/src/core/stt/model_provider.dart';
import 'package:mova/src/core/stt/model_spec.dart';

/// Records downloads without making network requests.
///
/// 记录下载，不发起网络请求。
class _Fetcher implements MovaHttpFetch {
  int calls = 0;

  /// Returns a small model fixture.
  ///
  /// 返回小型模型夹具。
  @override
  Future<Uint8List?> get(Uri url) async {
    calls++;
    return Uint8List.fromList([1, 2, 3]);
  }

  /// Releases the in-memory fixture.
  ///
  /// 释放内存夹具。
  @override
  Future<void> close() async {}
}

/// Verifies that model operations stay inside their cache directory.
///
/// 验证模型操作始终位于其缓存目录内。
void main() {
  late Directory sandbox;
  late Directory cache;
  late File sentinel;
  late _Fetcher fetcher;
  late MovaSttModelLoader loader;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('mova_model_path_');
    cache = await Directory('${sandbox.path}/cache').create();
    sentinel = await File('${sandbox.path}/keep.txt').writeAsString('keep');
    fetcher = _Fetcher();
    loader = MovaSttModelLoader(
      dir: MovaFixedSttModelDirProvider(cache.path),
      fetcher: fetcher,
    );
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  final invalidNames = [
    '',
    '.',
    '..',
    '../escape',
    r'..\escape',
    '/absolute',
    r'C:\absolute',
    'C:relative',
    'model/child',
    r'model\child',
    'model. ',
    'model.',
    '.. ',
    'model\u0000name',
    ' ',
  ];

  test(
    'D1 remove rejects unsafe model ids and preserves cache and parent',
    () async {
      for (final id in invalidNames) {
        await expectLater(
          loader.remove(id),
          throwsArgumentError,
          reason: 'id: $id',
        );
        expect(await cache.exists(), isTrue);
        expect(await sentinel.readAsString(), 'keep');
      }
    },
  );

  test('D1 ensure rejects unsafe model ids before downloading', () async {
    for (final id in invalidNames) {
      await expectLater(
        loader.ensure(MovaSttModelSpec(id: id, files: const [])),
        throwsArgumentError,
        reason: 'id: $id',
      );
    }
    expect(fetcher.calls, 0);
    expect(await cache.list().toList(), isEmpty);
    expect(await sentinel.readAsString(), 'keep');
  });

  test(
    'D1 ensure validates all filenames before any filesystem mutation',
    () async {
      for (final name in invalidNames) {
        await expectLater(
          loader.ensure(
            MovaSttModelSpec(
              id: 'valid',
              files: [
                MovaSttModelFile(
                  name: 'first.onnx',
                  url: Uri.parse('https://host/first'),
                ),
                MovaSttModelFile(
                  name: name,
                  url: Uri.parse('https://host/model'),
                ),
              ],
            ),
          ),
          throwsArgumentError,
          reason: 'name: $name',
        );
      }
      expect(fetcher.calls, 0);
      expect(await cache.list().toList(), isEmpty);
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test(
    'D1 valid models download, reuse cache and remove only their own directory',
    () async {
      final sibling = await Directory('${cache.path}/other-model').create();
      final siblingFile = await File(
        '${sibling.path}/keep.onnx',
      ).writeAsString('other model');
      final spec = MovaSttModelSpec(
        id: 'zipformer-v1',
        files: [
          MovaSttModelFile(
            name: 'encoder.int8.onnx',
            url: Uri.parse('https://host/model'),
          ),
        ],
      );
      final paths = await loader.ensure(spec);
      expect(await File(paths['encoder.int8.onnx']!).readAsBytes(), [1, 2, 3]);
      await loader.ensure(spec);
      expect(fetcher.calls, 1);
      await loader.remove(spec.id);
      expect(await Directory('${cache.path}/${spec.id}').exists(), isFalse);
      expect(await siblingFile.readAsString(), 'other model');
      expect(await sentinel.readAsString(), 'keep');
    },
  );
}
