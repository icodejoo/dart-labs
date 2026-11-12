import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';
import 'package:xvg/src/svg_source_loader.dart';

/// Shared fixture names and payloads. / 共用的夹具名称和内容。
const _assetName = 'unknown-image';

/// Memory source label. / 内存源名称。
const _memoryKind = 'memory';

/// File source label. / 文件源名称。
const _fileKind = 'file';

/// Asset source label. / 资源源名称。
const _assetKind = 'asset';

/// Stable fake URL. / 固定伪 URL。
const _url = 'https://example.test/unknown-image';

/// SVG response type. / SVG 响应类型。
const _svgType = 'image/svg+xml';

/// PNG response type. / PNG 响应类型。
const _pngType = 'image/png';

/// Generic binary response type. / 通用二进制响应类型。
const _octetType = 'application/octet-stream';

/// Forwarded header name. / 透传请求头名称。
const _headerName = 'x-xvg-test';

/// Forwarded header value. / 透传请求头值。
const _headerValue = 'forwarded';

/// Generated PNG fill color. / 生成 PNG 的填充颜色。
const _red = Color(0xffff0000);

/// Maximum first-frame wait. / 首帧最长等待时间。
const _timeout = Duration(seconds: 5);

/// GIF frame-driving interval. / GIF 帧驱动间隔。
const _step = Duration(milliseconds: 120);

/// Static SVG fixture. / 静态 SVG 夹具。
const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="2">'
    '<rect width="4" height="2" fill="red"/></svg>';

/// Creates a PNG using the engine instead of a binary fixture. / 用引擎现场生成 PNG。
Future<Uint8List> _redPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 4, 2), Paint()..color = _red);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 2);
  picture.dispose();
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

/// Encodes red/blue GIF frames with clear, index, and end LZW codes.
/// 用清空、像素索引和结束 LZW 码构造红蓝双帧 GIF。
Uint8List _twoFrameGif() => Uint8List.fromList([
  ...ascii.encode('GIF89a'),
  1,
  0,
  1,
  0,
  0x80,
  0,
  0,
  255,
  0,
  0,
  0,
  0,
  255,
  0x21,
  0xff,
  11,
  ...ascii.encode('NETSCAPE2.0'),
  3,
  1,
  0,
  0,
  0,
  for (final pixelCode in [0x44, 0x4c]) ...[
    0x21,
    0xf9,
    4,
    4,
    10,
    0,
    0,
    0,
    0x2c,
    0,
    0,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
    2,
    2,
    pixelCode,
    1,
    0,
  ],
  0x3b,
]);

/// Provides in-memory assets through the real AssetXvg path.
/// 经真实 AssetXvg 路径提供内存资源。
class _BytesBundle extends CachingAssetBundle {
  /// Stores one generated asset. / 保存一个现场生成的资源。
  _BytesBundle(this.bytes);

  /// Original asset bytes. / 原始资源字节。
  final Uint8List bytes;

  /// Returns the bytes for the requested fixture. / 返回指定夹具的字节。
  @override
  Future<ByteData> load(String key) async {
    expect(key, _assetName);
    return ByteData.sublistView(bytes);
  }
}

/// Records request headers and exposes response content type.
/// 记录请求头并提供响应内容类型。
class _Headers extends Fake implements HttpHeaders {
  /// Creates optional content-type metadata. / 创建可选的内容类型元数据。
  _Headers([this.type]);

  /// Response content-type string. / 响应内容类型字符串。
  final String? type;

  /// Headers forwarded by the provider. / provider 透传的请求头。
  final Map<String, Object> values = {};

  /// Records each header addition. / 记录每次请求头写入。
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  /// Returns one content-type value. / 返回单个内容类型值。
  @override
  String? value(String name) =>
      name == HttpHeaders.contentTypeHeader ? type : null;

  /// Parses optional content type. / 解析可选的内容类型。
  @override
  ContentType? get contentType =>
      type == null ? null : ContentType.parse(type!);
}

/// A chunked HTTP response backed by supplied bytes. / 由给定字节组成的分块响应。
class _Response extends Fake implements HttpClientResponse {
  /// Configures status and content type. / 配置状态码和内容类型。
  _Response(this.bytes, String? type, this.statusCode)
    : headers = _Headers(type);

  /// Response body. / 响应体。
  final Uint8List bytes;

  /// Response status. / 响应状态码。
  @override
  final int statusCode;

  /// Response metadata. / 响应元数据。
  @override
  final HttpHeaders headers;

  /// Exact wire length. / 传输字节总长。
  @override
  int get contentLength => bytes.length;

  /// Fixtures use no HTTP compression. / 夹具不采用 HTTP 压缩。
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  /// Emits two chunks to exercise progress forwarding. / 发出两块以验证进度转发。
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([
        bytes.sublist(0, bytes.length ~/ 2),
        bytes.sublist(bytes.length ~/ 2),
      ]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  /// Consumes unsuccessful responses. / 消费失败响应。
  @override
  Future<E> drain<E>([E? futureValue]) =>
      Stream<List<int>>.value(bytes).drain<E>(futureValue);
}

/// An HTTP request returning a configured response. / 返回指定响应的 HTTP 请求。
class _Request extends Fake implements HttpClientRequest {
  /// Stores the response. / 保存响应。
  _Request(this.response);

  /// Response returned on close. / 关闭请求后返回的响应。
  _Response response;

  /// Recorded request headers. / 已记录的请求头。
  @override
  final _Headers headers = _Headers();

  /// Completes the request. / 完成请求。
  @override
  Future<HttpClientResponse> close() async => response;

  /// Accepts cancellation after a failed response. / 接受失败响应后的取消。
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

/// A reusable fake network client. / 可复用的伪网络客户端。
class _Client extends Fake implements HttpClient {
  /// Creates the recorded request. / 创建可记录的请求。
  _Client(_Response response) : request = _Request(response);

  /// Request returned for the fixture URL. / 夹具 URL 对应的请求。
  final _Request request;

  /// Whether automatic decompression is enabled. / 是否启用自动解压。
  @override
  bool autoUncompress = true;

  /// Resolves the one supported URL. / 解析唯一支持的 URL。
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    expect(url, Uri.parse(_url));
    return request;
  }

  /// Ends the fake client lifetime. / 结束伪客户端生命周期。
  @override
  void close({bool force = false}) {}
}

/// Installs a client for one isolated request context.
/// 为独立的请求上下文安装客户端。
class _Overrides extends HttpOverrides {
  /// Stores the client. / 保存客户端。
  _Overrides(this.client);

  /// Client supplied to HttpClient constructors. / HttpClient 构造器取得的客户端。
  final _Client client;

  /// Returns the configured fake client. / 返回指定伪客户端。
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

/// Tracks ownership while delegating GIF frame creation to the engine.
/// 将 GIF 帧创建交给引擎，同时追踪所有权。
class _TrackingCodec implements ui.Codec {
  /// Wraps a real engine codec. / 包装真实引擎 codec。
  _TrackingCodec(this.inner);

  /// Engine codec creating valid FrameInfo objects. / 创建有效 FrameInfo 的引擎 codec。
  final ui.Codec inner;

  /// Whether the owning completer released the codec. / 所属 completer 是否释放 codec。
  bool disposed = false;

  /// Native frame count. / 原生帧数。
  @override
  int get frameCount => inner.frameCount;

  /// Native loop count. / 原生循环次数。
  @override
  int get repetitionCount => inner.repetitionCount;

  /// Decodes a native frame. / 解码原生帧。
  @override
  Future<ui.FrameInfo> getNextFrame() => inner.getNextFrame();

  /// Verifies single disposal before releasing native state.
  /// 确认仅释放一次后释放原生状态。
  @override
  void dispose() {
    expect(disposed, isFalse);
    disposed = true;
    inner.dispose();
  }
}

/// Uses Flutter's decoder callback when loading a concrete provider.
/// 加载具体 provider 时使用 Flutter 的解码回调。
ImageStreamCompleter _load(ImageProvider<Object> provider) =>
    // White-box test of decoder forwarding. / 白盒验证解码回调透传。
    // ignore: invalid_use_of_protected_member
    provider.loadImage(
      provider,
      PaintingBinding.instance.instantiateImageCodecWithSize,
    );

/// Awaits and owns the first frame, removing the temporary listener.
/// 等待并持有首帧，然后移除临时监听者。
Future<ImageInfo> _firstFrame(ImageStreamCompleter completer) async {
  final result = Completer<ImageInfo>();
  final listener = ImageStreamListener(
    (info, _) {
      if (result.isCompleted) {
        info.dispose();
      } else {
        result.complete(info);
      }
    },
    onError: (Object error, StackTrace? stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  completer.addListener(listener);
  try {
    return await result.future.timeout(_timeout);
  } finally {
    completer.removeListener(listener);
  }
}

/// Checks an opaque red first pixel. / 检查首像素为不透明红色。
Future<void> _expectRed(ImageInfo info) async {
  final pixels = await info.image.toByteData();
  expect(pixels!.buffer.asUint8List().take(4), [255, 0, 0, 255]);
}

/// Covers generated bitmap fixtures and real SVG provider dispatch.
/// 覆盖现场生成位图和真实 SVG provider 分流。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  tearDown(() {
    SvgSourceLoader.instance.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  for (final kind in [_memoryKind, _fileKind, _assetKind]) {
    for (final bitmap in [true, false]) {
      testWidgets('$kind displays ${bitmap ? 'PNG' : 'SVG'} bytes and pixels', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final bytes = bitmap
              ? await _redPng()
              : Uint8List.fromList(utf8.encode(_svg));
          final build = await Directory('build').create(recursive: true);
          final directory = await build.createTemp('xvg-provider-');
          try {
            final file = await File('${directory.path}/$_assetName')
                .writeAsBytes(bytes);
            final ImageProvider<Object> provider = switch (kind) {
              _memoryKind => MemoryXvg(bytes, width: 4, height: 2),
              _fileKind => FileXvg(file, width: 4, height: 2),
              _ => AssetXvg(
                _assetName,
                bundle: _BytesBundle(bytes),
                width: 4,
                height: 2,
              ),
            };
            final info = await _firstFrame(_load(provider));
            try {
              expect(info.image.width / info.scale, 4);
              expect(info.image.height / info.scale, 2);
              await _expectRed(info);
            } finally {
              info.dispose();
            }
          } finally {
            await directory.delete(recursive: true);
          }
        });
      });
    }
  }

  for (final type in [_pngType, _svgType, null, _octetType]) {
    for (final bitmap in [true, false]) {
      testWidgets('network ${bitmap ? 'PNG' : 'SVG'} with content-type $type', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final bytes = bitmap
              ? await _redPng()
              : Uint8List.fromList(utf8.encode(_svg));
          final client = _Client(_Response(bytes, type, HttpStatus.ok));
          await HttpOverrides.runWithHttpOverrides(() async {
            const provider = NetworkXvg(
              _url,
              width: 4,
              height: 2,
              headers: {_headerName: _headerValue},
            );
            final completer = _load(provider);
            final chunks = <ImageChunkEvent>[];
            final progress = ImageStreamListener(
              (info, _) => info.dispose(),
              onChunk: chunks.add,
            );
            completer.addListener(progress);
            try {
              final info = await _firstFrame(completer);
              try {
                await _expectRed(info);
                expect(info.image.width / info.scale, 4);
              } finally {
                info.dispose();
              }
              expect(client.autoUncompress, isFalse);
              expect(client.request.headers.values[_headerName], _headerValue);
              expect(chunks, isNotEmpty);
              expect(chunks.last.cumulativeBytesLoaded, bytes.length);
              expect(chunks.last.expectedTotalBytes, bytes.length);
            } finally {
              completer.removeListener(progress);
            }
          }, _Overrides(client));
        });
      });
    }
  }

  testWidgets('network preserves non-200 error status and URI', (tester) async {
    await tester.runAsync(() async {
      final client = _Client(
        _Response(Uint8List(0), null, HttpStatus.notFound),
      );
      await HttpOverrides.runWithHttpOverrides(() async {
        await expectLater(
          _firstFrame(_load(const NetworkXvg(_url))),
          throwsA(
            isA<NetworkImageLoadException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  HttpStatus.notFound,
                )
                .having((error) => error.uri, 'uri', Uri.parse(_url)),
          ),
        );
      }, _Overrides(client));
    });
  });

  testWidgets('ResizeImage passes bitmap dimensions to Flutter decoder', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final client = _Client(
        _Response(await _redPng(), _pngType, HttpStatus.ok),
      );
      await HttpOverrides.runWithHttpOverrides(() async {
        final stream = ResizeImage(
          const NetworkXvg(_url),
          width: 2,
        ).resolve(ImageConfiguration.empty);
        final info = await _firstFrame(stream.completer!);
        try {
          expect(info.image.width, 2);
          expect(info.image.height, 1);
          await _expectRed(info);
        } finally {
          info.dispose();
        }
      }, _Overrides(client));
    });
  });

  testWidgets('bitmap ignores SVG-only colorFilter', (tester) async {
    await tester.runAsync(() async {
      final provider = MemoryXvg(
        await _redPng(),
        colorFilter: const ColorFilter.mode(Color(0xff0000ff), BlendMode.srcIn),
      );
      final info = await _firstFrame(_load(provider));
      try {
        await _expectRed(info);
      } finally {
        info.dispose();
      }
    });
  });

  for (final invalid in [
    <int>[],
    [0xff],
    [0x1f, 0x8b, 0, 0],
  ]) {
    testWidgets('unknown bytes $invalid preserve the native decoder error', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final provider = MemoryXvg(Uint8List.fromList(invalid));
        Object? nativeError;
        final completer = provider.loadImage(provider, (
          buffer, {
          getTargetSize,
        }) async {
          try {
            return await PaintingBinding.instance.instantiateImageCodecWithSize(
              buffer,
              getTargetSize: getTargetSize,
            );
          } catch (error) {
            nativeError = error;
            rethrow;
          }
        });
        await expectLater(
          _firstFrame(completer),
          throwsA(
            predicate<Object>(
              (error) =>
                  identical(error, nativeError) && error is! FormatException,
            ),
          ),
        );
      });
    });
  }

  testWidgets(
    'a failed cached network image can resolve successfully on retry',
    (tester) async {
      await tester.runAsync(() async {
        final client = _Client(
          _Response(Uint8List(0), null, HttpStatus.notFound),
        );
        await HttpOverrides.runWithHttpOverrides(() async {
          const provider = NetworkXvg(_url);
          final failed = provider.resolve(ImageConfiguration.empty);
          await expectLater(
            _firstFrame(failed.completer!),
            throwsA(isA<NetworkImageLoadException>()),
          );
          client.request.response = _Response(
            await _redPng(),
            _pngType,
            HttpStatus.ok,
          );
          final retried = provider.resolve(ImageConfiguration.empty);
          final info = await _firstFrame(retried.completer!);
          try {
            await _expectRed(info);
          } finally {
            info.dispose();
          }
        }, _Overrides(client));
      });
    },
  );

  testWidgets('ImageCache eviction releases the retained native GIF codec', (
    tester,
  ) async {
    final provider = MemoryXvg(_twoFrameGif());
    _TrackingCodec? codec;
    final completer = provider.loadImage(provider, (
      buffer, {
      getTargetSize,
    }) async {
      return codec = _TrackingCodec(
        await PaintingBinding.instance.instantiateImageCodecWithSize(
          buffer,
          getTargetSize: getTargetSize,
        ),
      );
    });
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(provider, () => completer);
    var delivered = 0;
    final listener = ImageStreamListener((info, _) {
      delivered++;
      info.dispose();
    });
    completer.addListener(listener);
    for (var tick = 0; tick < 4; tick++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(_step);
    }
    expect(delivered, greaterThan(0));
    completer.removeListener(listener);
    expect(codec, isNotNull);
    expect(codec!.disposed, isFalse);
    expect(cache.containsKey(provider), isTrue);
    expect(cache.evict(provider), isTrue);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(codec!.disposed, isTrue);
  });

  testWidgets('native GIF advances frames and survives keepAlive pause twice', (
    tester,
  ) async {
    final completer = _load(MemoryXvg(_twoFrameGif()));
    final keepAlive = completer.keepAlive();
    final colors = <List<int>>[];
    final listener = ImageStreamListener((info, _) {
      unawaited(
        info.image.toByteData().then((data) {
          colors.add(data!.buffer.asUint8List().take(4).toList());
          info.dispose();
        }),
      );
    });
    completer.addListener(listener);
    try {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(_step);
      }
      expect(colors, contains(equals([255, 0, 0, 255])));
      expect(colors, contains(equals([0, 0, 255, 255])));
      for (var pause = 0; pause < 2; pause++) {
        completer.removeListener(listener);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        final paused = colors.length;
        await tester.pump(const Duration(seconds: 3));
        expect(colors.length, paused);
        completer.addListener(listener);
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(_step);
        }
        expect(colors.length, greaterThan(paused));
      }
    } finally {
      completer.removeListener(listener);
      keepAlive.dispose();
    }
  });
}
