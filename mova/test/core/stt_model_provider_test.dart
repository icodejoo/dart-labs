import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/fetcher.dart';
import 'package:mova/src/core/stt/model_dir_provider.dart';
import 'package:mova/src/core/stt/model_provider.dart';
import 'package:mova/src/core/stt/model_spec.dart';

class _FakeFetcher implements MovaHttpFetch {
  final Map<String, Uint8List?> responses;
  final List<Uri> requested = [];
  _FakeFetcher(this.responses);

  @override
  Future<Uint8List?> get(Uri url) async {
    requested.add(url);
    return responses[url.toString()];
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mova_stt_model_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  MovaSttModelSpec buildSpec() {
    return MovaSttModelSpec(
      id: 'zipformer-zh-en-2023-11-22',
      files: [
        MovaSttModelFile(
          name: 'encoder.onnx',
          url: Uri.parse('https://example.com/encoder.onnx'),
          sizeBytes: 3,
        ),
        MovaSttModelFile(
          name: 'tokens.txt',
          url: Uri.parse('https://example.com/tokens.txt'),
        ),
      ],
    );
  }

  test('downloads every missing file and resolves their local paths', () async {
    final fetcher = _FakeFetcher({
      'https://example.com/encoder.onnx': Uint8List.fromList([1, 2, 3]),
      'https://example.com/tokens.txt': Uint8List.fromList([4, 5]),
    });
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );

    final files = await downloader.ensure(buildSpec());

    expect(fetcher.requested, hasLength(2));
    expect(await File(files['encoder.onnx']!).readAsBytes(), [1, 2, 3]);
    expect(await File(files['tokens.txt']!).readAsBytes(), [4, 5]);
  });

  test('skips re-downloading a file whose cached size already matches', () async {
    final modelDir = Directory('${tempDir.path}${Platform.pathSeparator}zipformer-zh-en-2023-11-22');
    await modelDir.create(recursive: true);
    await File('${modelDir.path}${Platform.pathSeparator}encoder.onnx')
        .writeAsBytes([9, 9, 9]);

    final fetcher = _FakeFetcher({
      'https://example.com/tokens.txt': Uint8List.fromList([4, 5]),
    });
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );

    final files = await downloader.ensure(buildSpec());

    // encoder.onnx was never requested — its cached size already matched.
    //
    // encoder.onnx 从未被请求——其缓存文件大小已经匹配。
    expect(fetcher.requested, [Uri.parse('https://example.com/tokens.txt')]);
    expect(await File(files['encoder.onnx']!).readAsBytes(), [9, 9, 9]);
  });

  test('re-downloads a cached file whose size no longer matches', () async {
    final modelDir = Directory('${tempDir.path}${Platform.pathSeparator}zipformer-zh-en-2023-11-22');
    await modelDir.create(recursive: true);
    await File('${modelDir.path}${Platform.pathSeparator}encoder.onnx')
        .writeAsBytes([9, 9]); // wrong size (spec expects 3 bytes)

    final fetcher = _FakeFetcher({
      'https://example.com/encoder.onnx': Uint8List.fromList([1, 2, 3]),
      'https://example.com/tokens.txt': Uint8List.fromList([4, 5]),
    });
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );

    final files = await downloader.ensure(buildSpec());

    expect(fetcher.requested, hasLength(2));
    expect(await File(files['encoder.onnx']!).readAsBytes(), [1, 2, 3]);
  });

  test('emits one progress step per file in order', () async {
    final fetcher = _FakeFetcher({
      'https://example.com/encoder.onnx': Uint8List.fromList([1, 2, 3]),
      'https://example.com/tokens.txt': Uint8List.fromList([4, 5]),
    });
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );

    final steps = <MovaSttModelProg>[];
    final sub = downloader.progress.listen(steps.add);
    await downloader.ensure(buildSpec());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(steps.map((s) => s.fileName), ['encoder.onnx', 'tokens.txt']);
    expect(steps.last.completedFiles, 2);
    expect(steps.last.totalFiles, 2);
  });

  test('throws MovaSttModelLoadError when a file cannot be fetched', () async {
    final fetcher = _FakeFetcher({'https://example.com/encoder.onnx': null});
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );

    await expectLater(
      downloader.ensure(buildSpec()),
      throwsA(isA<MovaSttModelLoadError>()),
    );
  });

  test('remove deletes the model sub-directory', () async {
    final fetcher = _FakeFetcher({
      'https://example.com/encoder.onnx': Uint8List.fromList([1, 2, 3]),
      'https://example.com/tokens.txt': Uint8List.fromList([4, 5]),
    });
    final downloader = MovaSttModelLoader(
      dir: FixedSttModelDirProvider(tempDir.path),
      fetcher: fetcher,
    );
    await downloader.ensure(buildSpec());

    await downloader.remove('zipformer-zh-en-2023-11-22');

    expect(
      Directory('${tempDir.path}${Platform.pathSeparator}zipformer-zh-en-2023-11-22').existsSync(),
      isFalse,
    );
  });
}
