import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/shared_animation_clock.dart';
import 'package:xvg/src/cold_mount_budget.dart';
import 'package:xvg/src/svg_source_loader.dart';
import 'package:xvg/xvg.dart';

/// Identified animation fixture. / 具名动画样例。
const _pulseId = 'pulse';

/// Finite identified timeline. / 有限具名时间线。
const _source =
    '<svg width="24" height="24"><rect width="24" height="24">'
    '<animate id="$_pulseId" attributeName="opacity" values="0;1" '
    'begin="250ms" dur="250ms" repeatCount="2"/>'
    '<animate attributeName="x" from="0" to="12" dur="2s" fill="freeze"/>'
    '</rect></svg>';

/// Static fixture. / 静态样例。
const _static =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
    '<rect width="24" height="24"/></svg>';

/// Invalid static/animated fixtures. / 非法静态与动画样例。
const _brokenStatic = '<svg><rect>';
const _brokenAnimated = '<svg><animate>';

/// Invalid static source routed through async image parsing. / 走异步图片解析的非法静态源。
const _brokenImage = '<svg><image href="data:image/png;base64,broken">';

/// Shared span and test step. / 共用映射时长与步长。
const _span = Duration(seconds: 2);
const _step = Duration(milliseconds: 500);

/// Stable loader identity and fallback label. / 稳定加载标识与替代内容标签。
const _name = 'forwarding.svg';
const _url = 'http://xvg.test/forwarding.svg';
const _fallback = 'handled failure';
const _missingPath = 'test/.xvg-forwarding-nonexistent.svg';

/// Five public source entry points. / 五种公开源入口。
enum _Entry {
  /// Markup input. / 源文本输入。
  string,

  /// Bundled asset. / 资源输入。
  asset,

  /// HTTP input. / 网络输入。
  network,

  /// File input. / 文件输入。
  file,

  /// UTF-8 byte input. / UTF-8 字节输入。
  memory,
}

/// Configured failure handling. / 配置的失败处理方式。
enum _FailureHandling {
  /// Both callbacks. / 两种回调。
  both,

  /// Replacement only. / 仅替代内容。
  builder,

  /// Notification only. / 仅错误通知。
  callback,

  /// Default propagation. / 默认传播。
  none,
}

/// Controlled asset text load. / 可控 asset 文本加载。
class _Bundle extends CachingAssetBundle {
  /// Uses one externally completed load. / 使用外部完成的加载。
  _Bundle(this.future);

  /// Pending or completed source. / 待完成或已完成的源。
  final Future<String> future;

  /// Returns controlled text. / 返回可控文本。
  @override
  Future<String> loadString(String key, {bool cache = true}) => future;

  /// Unused binary asset route. / 未使用的二进制资源入口。
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

/// Deterministic file text input. / 确定性的文件文本输入。
class _File extends Fake implements File {
  /// Stores source text. / 保存源文本。
  _File(this.source);

  /// File contents. / 文件内容。
  final String source;

  /// Stable file cache identity. / 稳定文件缓存标识。
  @override
  String get path => _name;

  /// Resolves text without external IO. / 无外部 IO 地解析文本。
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async => source;
}

/// One-shot HTTP response stream. / 一次性 HTTP 响应流。
class _Response extends Stream<List<int>> implements HttpClientResponse {
  /// Stores text and status. / 保存文本与状态。
  _Response(this.source, this.statusCode);

  /// Response text. / 响应文本。
  final String source;

  /// HTTP status. / HTTP 状态。
  @override
  final int statusCode;

  /// Streams UTF-8 text. / 流式提供 UTF-8 文本。
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(source)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  /// Rejects unused HTTP operations. / 拒绝未使用的 HTTP 操作。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controlled request. / 可控请求。
class _Request extends Fake implements HttpClientRequest {
  /// Wraps a response. / 包装响应。
  _Request(this.response);

  /// Response returned by close. / close 返回的响应。
  final HttpClientResponse response;

  /// Completes the request. / 完成请求。
  @override
  Future<HttpClientResponse> close() async => response;
}

/// Controlled HTTP transport. / 可控 HTTP 传输。
class _Client extends Fake implements HttpClient {
  /// Uses fixture source and status. / 使用样例源与状态。
  _Client(this.source, [this.status = HttpStatus.ok]);

  /// Response source. / 响应源。
  final String source;

  /// Response status. / 响应状态。
  final int status;

  /// Opens a deterministic request. / 打开确定性请求。
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(_Response(source, status));

  /// No persistent transport resources. / 无持久传输资源。
  @override
  void close({bool force = false}) {}
}

/// Tracks external animation value listeners. / 统计外部动画值监听者。
class _TrackedController extends AnimationController {
  /// Creates an externally driven test controller. / 创建外部驱动测试控制器。
  _TrackedController({required super.vsync});

  /// Currently attached value listeners. / 当前挂载的值监听者。
  final listeners = <VoidCallback>{};

  /// Registers a value listener. / 注册值监听者。
  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    super.addListener(listener);
  }

  /// Removes a value listener. / 移除值监听者。
  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
    super.removeListener(listener);
  }
}

/// Constructs each entry with the same public options. / 使用相同公开参数构建各入口。
Widget _make(
  _Entry entry, {
  String source = _source,
  _Bundle? bundle,
  XvgAnimationController? controller,
  Animation<double>? animation,
  Duration? animationSpan,
  bool autoplay = true,
  double playbackRate = 1,
  double? maxFps,
  ValueChanged<XvgAnimationInfo>? onLoaded,
  void Function(Object, StackTrace)? onError,
  ImageErrorWidgetBuilder? errorBuilder,
  ValueChanged<XvgAnimationEvent>? onEvent,
  VoidCallback? onAnimationStart,
  VoidCallback? onAnimationComplete,
  ValueChanged<int>? onAnimationLoop,
  XvgTheme? theme,
  XvgAnimationQuality? quality,
  ColorFilter? colorFilter,
  XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
}) => switch (entry) {
  _Entry.string => Xvg.string(
    source,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
    theme: theme,
    quality: quality,
    colorFilter: colorFilter,
    pixelSnap: pixelSnap,
  ),
  _Entry.asset => Xvg.asset(
    _name,
    bundle: bundle ?? _Bundle(Future.value(source)),
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
    theme: theme,
    quality: quality,
    colorFilter: colorFilter,
    pixelSnap: pixelSnap,
  ),
  _Entry.network => Xvg.network(
    _url,
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
    theme: theme,
    quality: quality,
    colorFilter: colorFilter,
    pixelSnap: pixelSnap,
  ),
  _Entry.file => Xvg.file(
    _File(source),
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
    theme: theme,
    quality: quality,
    colorFilter: colorFilter,
    pixelSnap: pixelSnap,
  ),
  _Entry.memory => Xvg.memory(
    Uint8List.fromList(utf8.encode(source)),
    controller: controller,
    animation: animation,
    animationSpan: animationSpan,
    autoplay: autoplay,
    playbackRate: playbackRate,
    maxFps: maxFps,
    onLoaded: onLoaded,
    onError: onError,
    errorBuilder: errorBuilder,
    onEvent: onEvent,
    onAnimationStart: onAnimationStart,
    onAnimationComplete: onAnimationComplete,
    onAnimationLoop: onAnimationLoop,
    theme: theme,
    quality: quality,
    colorFilter: colorFilter,
    pixelSnap: pixelSnap,
  ),
};

/// Supplies direction and loose constraints. / 提供方向与宽松约束。
Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

/// Reads the mounted animation clock. / 读取已挂载动画时钟。
Duration _time(WidgetTester tester) =>
    (tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
            as AnimatedSvgPainter)
        .clock
        .value;

/// Covers forwarding, failure policy and pending-load lifetime.
/// 覆盖参数转发、失败策略与待加载生命周期。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Xvg.ensureInitialized);
  tearDown(() {
    SvgSourceLoader.instance.clear();
    XvgDocumentCache.instance.clear();
    ColdMountFrameBudget.instance.debugReset();
    expect(SharedAnimationClock.instance.subscriberCount, 0);
  });

  for (final entry in _Entry.values) {
    testWidgets('${entry.name}: pixelSnap reaches both renderers', (
      tester,
    ) async {
      for (final animated in [false, true]) {
        final source = animated
            ? _source
            : '<svg width="24" height="24"><path d="M0 0H24V24Z"/></svg>';
        for (final mode in XvgPixelSnap.values) {
          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              _host(
                _make(entry, source: source, pixelSnap: mode, autoplay: false),
              ),
            );
            await tester.pump();
            await tester.pump();
            final actual = animated
                ? tester.widget<XvgAnimated>(find.byType(XvgAnimated)).pixelSnap
                : tester.widget<XvgStatic>(find.byType(XvgStatic)).pixelSnap;
            expect(actual, mode);
            await tester.pumpWidget(const SizedBox());
            SvgSourceLoader.instance.clear();
          }, createHttpClient: (_) => _Client(source));
        }
      }
    });

    testWidgets('${entry.name}: controller, callbacks and options', (
      tester,
    ) async {
      final controller = XvgAnimationController();
      final events = <XvgAnimationEvent>[];
      final loaded = <XvgAnimationInfo>[];
      var starts = 0;
      var completes = 0;
      const theme = XvgTheme(currentColor: Color(0xff123456));
      const quality = XvgAnimationQuality.exact;
      const filter = ColorFilter.mode(Color(0xff123456), BlendMode.srcIn);
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          _host(
            _make(
              entry,
              controller: controller,
              onLoaded: loaded.add,
              onEvent: events.add,
              onAnimationStart: () => starts++,
              onAnimationComplete: () => completes++,
              maxFps: 30,
              theme: theme,
              quality: quality,
              colorFilter: filter,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(loaded, hasLength(1));
        expect(controller.info, loaded.single);
        final child = tester.widget<XvgAnimated>(find.byType(XvgAnimated));
        expect(child.controller, same(controller));
        expect(child.maxFps, 30);
        expect(child.theme, theme);
        expect(child.quality, same(quality));
        expect(find.byType(ColorFiltered), findsOneWidget);
        controller.pause();
        controller.seek(_step);
        await tester.pump();
        expect(_time(tester), _step);
        controller.stop();
        controller.play();
        await tester.pump();
        await tester.pump(_step);
        await tester.pump(_span);
        await tester.pump(_step);
        expect(starts, greaterThan(0));
        expect(completes, 1);
        expect(
          events.whereType<XvgAnimationElementBegin>().map((e) => e.id),
          contains(_pulseId),
        );
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => _Client(_source));
      controller.dispose();
    });

    testWidgets('${entry.name}: Flutter animation, span and element events', (
      tester,
    ) async {
      final driver = _TrackedController(vsync: tester);
      final events = <XvgAnimationEvent>[];
      final loaded = <XvgAnimationInfo>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          _host(
            _make(
              entry,
              animation: driver,
              animationSpan: _span,
              onLoaded: loaded.add,
              onEvent: events.add,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(loaded, hasLength(1));
        expect(SharedAnimationClock.instance.subscriberCount, 0);
        driver.value = 0.5;
        await tester.pump();
        expect(_time(tester), const Duration(seconds: 1));
        expect(
          events.whereType<XvgAnimationElementBegin>().map((e) => e.id),
          contains(_pulseId),
        );
        expect(events.whereType<XvgAnimationStarted>(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => _Client(_source));
      expect(driver.isAnimating, false);
      driver.dispose();
    });

    testWidgets('${entry.name}: static ignores animation controls', (
      tester,
    ) async {
      final controller = XvgAnimationController();
      var loaded = 0;
      var events = 0;
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          _host(
            _make(
              entry,
              source: _static,
              controller: controller,
              onLoaded: (_) => loaded++,
              onEvent: (_) => events++,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(XvgStatic), findsOneWidget);
        expect(loaded, 0);
        expect(events, 0);
        expect(controller.info, isNull);
        expect(SharedAnimationClock.instance.subscriberCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => _Client(_static));
      controller.dispose();
    });

    testWidgets('${entry.name}: implicit options and legacy loop callback', (
      tester,
    ) async {
      final source = _source.replaceFirst(
        'repeatCount="2"',
        'repeatCount="indefinite"',
      );
      final loops = <int>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          _host(
            _make(
              entry,
              source: source,
              autoplay: false,
              playbackRate: 2,
              onAnimationLoop: loops.add,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(_step);
        expect(_time(tester), Duration.zero);
        final child = tester.widget<XvgAnimated>(find.byType(XvgAnimated));
        expect(child.autoplay, false);
        expect(child.playbackRate, 2);
        await tester.pumpWidget(
          _host(
            _make(
              entry,
              source: source,
              playbackRate: 2,
              onAnimationLoop: loops.add,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(_step);
        expect(_time(tester), const Duration(seconds: 1));
        await tester.pump(_span);
        expect(loops, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => _Client(source));
    });

    test('${entry.name}: asserts before source load', () {
      final controller = XvgAnimationController();
      const animation = AlwaysStoppedAnimation(0.0);
      expect(
        () => _make(entry, controller: controller, animation: animation),
        throwsAssertionError,
      );
      expect(() => _make(entry, maxFps: 0), throwsAssertionError);
      expect(
        () => _make(entry, playbackRate: double.nan),
        throwsAssertionError,
      );
      expect(
        () => _make(entry, controller: controller, playbackRate: 2),
        throwsAssertionError,
      );
      expect(
        () => _make(entry, animation: animation, autoplay: false),
        throwsAssertionError,
      );
      expect(
        () => _make(entry, animation: animation, playbackRate: 2),
        throwsAssertionError,
      );
      controller.dispose();
    });
  }

  for (final source in [_brokenStatic, _brokenImage, _brokenAnimated]) {
    testWidgets('parse failure has shared handlers: $source', (tester) async {
      final errors = <Object>[];
      Widget build() => _host(
        Xvg.string(
          source,
          onError: (error, stack) => errors.add(error),
          errorBuilder: (context, error, stack) => const Text(_fallback),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pump();
      expect(find.text(_fallback), findsOneWidget);
      expect(errors, hasLength(1));
      await tester.pumpWidget(build());
      await tester.pump();
      expect(errors, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'static external animation is ignored and callback-only errors recover',
    (tester) async {
      final driver = _TrackedController(vsync: tester);
      final errors = <Object>[];
      Widget build(String source) => _host(
        Xvg.string(
          source,
          animation: driver,
          onError: (error, stack) => errors.add(error),
        ),
      );
      await tester.pumpWidget(build(_static));
      expect(driver.listeners, isEmpty);
      await tester.pumpWidget(build(_brokenStatic));
      await tester.pump();
      expect(errors, hasLength(1));
      expect(find.byType(ErrorWidget), findsNothing);
      await tester.pumpWidget(build(_static));
      await tester.pumpWidget(build(_brokenStatic));
      await tester.pump();
      expect(errors, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      driver.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in [_Entry.asset, _Entry.network, _Entry.file]) {
    for (final handlers in _FailureHandling.values) {
      testWidgets('${kind.name} load failure: ${handlers.name}', (
        tester,
      ) async {
        final errors = <Object>[];
        final stacks = <StackTrace>[];
        final hasCallback =
            handlers == _FailureHandling.both ||
            handlers == _FailureHandling.callback;
        final hasBuilder =
            handlers == _FailureHandling.both ||
            handlers == _FailureHandling.builder;

        /// Captures one asynchronous failure. / 捕获一次异步失败。
        void onError(Object error, StackTrace stack) {
          errors.add(error);
          stacks.add(stack);
        }

        Object? replacementError;
        StackTrace? replacementStack;

        /// Builds replacement content. / 构建替代内容。
        Widget fallback(BuildContext context, Object error, StackTrace? stack) {
          replacementError = error;
          replacementStack = stack;
          return const Text(_fallback);
        }

        final failure = Completer<String>();
        final bundle = _Bundle(failure.future);
        final widget = switch (kind) {
          _Entry.asset => Xvg.asset(
            _name,
            bundle: bundle,
            onError: hasCallback ? onError : null,
            errorBuilder: hasBuilder ? fallback : null,
          ),
          _Entry.network => Xvg.network(
            _url,
            onError: hasCallback ? onError : null,
            errorBuilder: hasBuilder ? fallback : null,
          ),
          _ => Xvg.file(
            File(_missingPath),
            onError: hasCallback ? onError : null,
            errorBuilder: hasBuilder ? fallback : null,
          ),
        };
        await HttpOverrides.runZoned(() async {
          if (kind == _Entry.file) {
            await tester.runAsync(() async {
              await tester.pumpWidget(_host(widget));
              await SvgSourceLoader.instance
                  .file(File(_missingPath))
                  .then<void>((_) {}, onError: (Object _, StackTrace _) {});
            });
          } else {
            await tester.pumpWidget(_host(widget));
            if (kind == _Entry.asset) {
              failure.completeError(StateError(_fallback), StackTrace.current);
            }
          }
          await tester.pump();
          await tester.pump();
          expect(errors, hasLength(hasCallback ? 1 : 0));
          if (hasCallback) expect(stacks.single.toString(), isNotEmpty);
          if (hasBuilder) {
            expect(replacementError, isNotNull);
            expect(replacementStack, isNotNull);
            if (hasCallback) {
              expect(replacementError, same(errors.single));
              expect(replacementStack, same(stacks.single));
            }
          }
          expect(
            find.text(_fallback),
            hasBuilder ? findsOneWidget : findsNothing,
          );
          if (handlers == _FailureHandling.none) {
            expect(tester.takeException(), isNotNull);
            expect(find.byType(ErrorWidget), findsOneWidget);
          } else {
            expect(tester.takeException(), isNull);
            expect(find.byType(ErrorWidget), findsNothing);
          }
          await tester.pumpWidget(const SizedBox());
        }, createHttpClient: (_) => _Client('', HttpStatus.notFound));
      });
    }
  }

  testWidgets('unhandled loads reach the ambient ErrorWidget builder', (
    tester,
  ) async {
    final previousBuilder = ErrorWidget.builder;
    final failure = StateError(_fallback);
    final gate = Completer<String>();
    Object? received;
    ErrorWidget.builder = (details) {
      received = details.exception;
      return const Text(_fallback);
    };
    try {
      await tester.pumpWidget(
        _host(Xvg.asset(_name, bundle: _Bundle(gate.future))),
      );
      gate.completeError(failure, StackTrace.current);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), same(failure));
      expect(received, same(failure));
      expect(find.text(_fallback), findsOneWidget);
    } finally {
      ErrorWidget.builder = previousBuilder;
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final finish in [false, true]) {
    testWidgets('pending load parameter swaps; finish=$finish', (tester) async {
      final gate = Completer<String>();
      final bundle = _Bundle(gate.future);
      final a = XvgAnimationController();
      final b = XvgAnimationController();
      final driver = _TrackedController(vsync: tester);
      var loaded = 0;
      await tester.pumpWidget(
        _host(_make(_Entry.asset, bundle: bundle, controller: a)),
      );
      await tester.pumpWidget(
        _host(_make(_Entry.asset, bundle: bundle, animation: driver)),
      );
      await tester.pumpWidget(
        _host(
          _make(
            _Entry.asset,
            bundle: bundle,
            controller: b,
            onLoaded: (_) => loaded++,
          ),
        ),
      );
      expect(a.info, isNull);
      expect(b.info, isNull);
      expect(driver.listeners, isEmpty);
      expect(SharedAnimationClock.instance.subscriberCount, 0);
      if (!finish) await tester.pumpWidget(const SizedBox());
      gate.complete(_source);
      await tester.pump();
      await tester.pump();
      expect(loaded, finish ? 1 : 0);
      if (finish) {
        expect(b.info, isNotNull);
        expect(a.info, isNull);
        expect(SharedAnimationClock.instance.subscriberCount, 1);
        await tester.pumpWidget(
          _host(
            _make(
              _Entry.asset,
              bundle: bundle,
              animation: driver,
              animationSpan: _span,
            ),
          ),
        );
        expect(SharedAnimationClock.instance.subscriberCount, 0);
        expect(driver.listeners, hasLength(1));
      }
      await tester.pumpWidget(const SizedBox());
      expect(driver.listeners, isEmpty);
      a.dispose();
      b.dispose();
      driver.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
