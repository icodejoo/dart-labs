import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/svg_source_loader.dart';
import 'package:xvg/src/svg_source_sniffer.dart';

/// Valid SVG text for transport checks. / 传输检查使用的有效 SVG 文本。
const _svgSource = '<svg xmlns="http://www.w3.org/2000/svg"/>';

/// SVG response MIME type. / SVG 响应类型。
const _svgContentType = 'image/svg+xml';

/// Request header used to check passthrough. / 验证透传的请求头。
const _headerName = 'x-xvg-test';

/// Request header value. / 请求头值。
const _headerValue = 'byte-loader';

/// Fake-clock timeout for abort checks. / 中止检查使用的虚拟时钟超时。
const _abortTimeout = Duration(milliseconds: 100);

/// URL used by request-cancellation fakes. / 请求取消替身使用的地址。
const _abortUrl = 'http://xvg-byte-loader.test/abort';

/// A binary bundle with an offset view and independent textual content.
/// 提供带偏移字节视图与独立文本内容的资源包。
class _ByteBundle extends CachingAssetBundle {
  /// Asset keys loaded as bytes. / 按字节加载过的资源键。
  final List<String> keys = [];

  /// Returns bytes from an offset view. / 返回带偏移的字节视图。
  @override
  Future<ByteData> load(String key) async {
    keys.add(key);
    final bytes = Uint8List.fromList([0, 1, 2, 3, 0]);
    return ByteData.sublistView(bytes, 1, 4);
  }

  /// Returns independent source text. / 返回独立源文本。
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      _svgSource;
}

/// Restores real networking inside test binding override scopes.
/// 在测试绑定的覆盖作用域内恢复真实网络。
class _RealHttpOverrides extends HttpOverrides {}

/// Client that records closure while exposing a controlled pending request.
/// 暴露受控待完成请求并记录关闭的客户端。
class _AbortClient extends Fake implements HttpClient {
  /// Uses [opening] for connection completion. / 用 [opening] 控制连接完成。
  _AbortClient(this.opening);

  /// Connection result. / 连接结果。
  final Future<HttpClientRequest> opening;

  /// Whether the shared client was closed. / 共享客户端是否已关闭。
  bool closed = false;

  /// HTTP decompression setting. / HTTP 解压设置。
  @override
  bool autoUncompress = true;

  /// Returns the controlled request. / 返回受控请求。
  @override
  Future<HttpClientRequest> getUrl(Uri url) => opening;

  /// Records whole-client closure. / 记录整个客户端关闭。
  @override
  void close({bool force = false}) => closed = true;
}

/// Request with observable abort and a controlled response-header future.
/// 可观测中止并使用受控响应头 Future 的请求。
class _AbortRequest extends Fake implements HttpClientRequest {
  /// Uses [response] for headers and invokes [onAbort] when canceled.
  /// 用 [response] 控制响应头，取消时调用 [onAbort]。
  _AbortRequest(this.response, {this.onAbort});

  /// Response-header result. / 响应头结果。
  final Future<HttpClientResponse> response;

  /// Optional body cleanup. / 可选响应体清理。
  final void Function()? onAbort;

  /// Number of abort calls. / 中止调用次数。
  int aborts = 0;

  /// Error supplied on abort. / 中止时传入的错误。
  Object? abortError;

  /// Returns the controlled headers. / 返回受控响应头。
  @override
  Future<HttpClientResponse> close() => response;

  /// Records cancellation and releases the fake body stream.
  /// 记录取消并释放替身响应体流。
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts++;
    abortError = exception;
    onAbort?.call();
  }
}

/// Response backed by a controllable body stream. / 由可控响应体流支持的响应。
class _AbortResponse extends Fake implements HttpClientResponse {
  /// Wraps [body]. / 包装 [body]。
  _AbortResponse(this.body);

  /// Body stream used by consolidate. / consolidate 使用的响应体流。
  final Stream<List<int>> body;

  /// Successful response status. / 成功响应状态。
  @override
  int get statusCode => HttpStatus.ok;

  /// Unknown body length. / 未知响应体长度。
  @override
  int get contentLength => -1;

  /// Body is sent without transport compression. / 无传输压缩的响应体。
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  /// Subscribes to the controlled body stream. / 订阅受控响应体流。
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

/// Verifies byte entry points without changing textual behavior.
/// 验证字节入口且不改变文本行为。
void main() {
  tearDown(SvgSourceLoader.instance.clear);
  test(
    'asset bytes preserve offset/package and do not pollute text cache',
    () async {
      final loader = SvgSourceLoader.instance;
      final bundle = _ByteBundle();
      final bytes = await loader.assetBytes(
        'source',
        bundle: bundle,
        package: 'pkg',
      );
      expect(bytes, [1, 2, 3]);
      expect(bundle.keys, ['packages/pkg/source']);
      expect(
        await loader.asset('source', bundle: bundle, package: 'pkg'),
        _svgSource,
      );
    },
  );
  test(
    'file bytes do not UTF-8 decode and do not use the text cache',
    () async {
      final build = await Directory('build').create(recursive: true);
      final directory = await build.createTemp('xvg-source-bytes-');
      final file = File('${directory.path}/source');
      try {
        await file.writeAsString(_svgSource);
        expect(await SvgSourceLoader.instance.file(file), _svgSource);
        final bytes = Uint8List.fromList([0xff, 0xd8, 0xff]);
        await file.writeAsBytes(bytes);
        expect(await SvgSourceLoader.instance.fileBytes(file), bytes);
        expect(await SvgSourceLoader.instance.file(file), _svgSource);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'HTTP gzip is decompressed, raw svgz stays compressed, headers/progress pass',
    () => HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final compressed = gzip.encode(utf8.encode(_svgSource));
      final receivedHeaders = <String?>[];
      final progress = <(int, int?)>[];
      server.listen((request) async {
        receivedHeaders.add(request.headers.value(_headerName));
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          _svgContentType,
        );
        request.response.contentLength = compressed.length;
        if (request.uri.path == '/transport') {
          request.response.headers.set(
            HttpHeaders.contentEncodingHeader,
            'gzip',
          );
        }
        request.response.add(compressed);
        await request.response.close();
      });
      try {
        final base = 'http://127.0.0.1:${server.port}';
        final transport = await SvgSourceLoader.instance.networkBytes(
          '$base/transport',
          headers: {_headerName: _headerValue},
          onBytesReceived: (loaded, total) => progress.add((loaded, total)),
        );
        expect(utf8.decode(transport.bytes), _svgSource);
        expect(transport.contentType, _svgContentType);
        expect(
          isSvgSource(transport.bytes, contentType: transport.contentType),
          isTrue,
        );
        expect(progress.last, (compressed.length, compressed.length));
        final raw = await SvgSourceLoader.instance.networkBytes('$base/raw');
        expect(raw.bytes, compressed);
        expect(isSvgSource(raw.bytes, contentType: raw.contentType), isFalse);
        expect(receivedHeaders, [_headerValue, null]);
      } finally {
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient),
  );
  test(
    'byte body phase uses the configured timeout',
    () => HttpOverrides.runZoned(() async {
      final oldTimeout = SvgSourceLoader.networkTimeout;
      SvgSourceLoader.networkTimeout = const Duration(milliseconds: 100);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write(_svgSource);
        await request.response.flush();
      });
      try {
        await expectLater(
          SvgSourceLoader.instance.networkBytes(
            'http://127.0.0.1:${server.port}/',
          ),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        SvgSourceLoader.networkTimeout = oldTimeout;
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient),
  );
  test(
    'non-200 byte loads keep the native network error type',
    () => HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
      try {
        await expectLater(
          SvgSourceLoader.instance.networkBytes(
            'http://127.0.0.1:${server.port}/',
          ),
          throwsA(
            isA<NetworkImageLoadException>().having(
              (error) => error.statusCode,
              'status code',
              HttpStatus.notFound,
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    }, createHttpClient: _RealHttpOverrides().createHttpClient),
  );
  for (final phase in ['connection', 'headers', 'body']) {
    testWidgets('byte $phase timeout aborts only its request', (tester) async {
      final oldTimeout = SvgSourceLoader.networkTimeout;
      SvgSourceLoader.networkTimeout = _abortTimeout;
      final opening = Completer<HttpClientRequest>();
      final headers = Completer<HttpClientResponse>();
      final body = StreamController<List<int>>();
      final request = _AbortRequest(
        headers.future,
        onAbort: () => unawaited(body.close()),
      );
      final client = _AbortClient(opening.future);
      if (phase != 'connection') opening.complete(request);
      if (phase == 'body') headers.complete(_AbortResponse(body.stream));
      try {
        await HttpOverrides.runZoned(() async {
          Object? error;
          SvgSourceLoader.instance
              .networkBytes(_abortUrl)
              .then(
                (_) {},
                onError: (Object value, StackTrace stack) {
                  error = value;
                },
              );
          await tester.pump();
          expect(client.autoUncompress, isFalse);
          await tester.pump(_abortTimeout);
          expect(error, isA<TimeoutException>());
          if (phase == 'connection') {
            expect(request.aborts, 0);
            opening.complete(request);
            await tester.pump();
          } else {
            expect(identical(request.abortError, error), isTrue);
          }
          expect(request.aborts, 1);
          expect(client.closed, isFalse);
          expect(body.hasListener, isFalse);
        }, createHttpClient: (_) => client);
      } finally {
        SvgSourceLoader.networkTimeout = oldTimeout;
      }
    });
  }
}
