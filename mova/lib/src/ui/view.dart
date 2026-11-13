import 'style/style.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/guard/auto_pause.dart';
import '../core/model/fit.dart';
import '../core/model/source.dart';
import '../core/options/options.dart';
import '../platform_impl/wiring.dart';
import 'guard/auto_pause.dart';
import 'player.dart';
import 'ui_kits/default_ui_kit.dart';
import 'ui_kits/ui_kit.dart';

/// Builds a player for [MovaView] from the view's [MovaOpts].
///
/// 依据 [MovaView] 的 [MovaOpts] 构建播放器。
typedef MovaViewFactory = IMovaApi Function(MovaOpts options);

/// A declarative player: give it a [source] and it owns the whole player
/// lifecycle — created lazily on the first non-null source, reopened only
/// when the source really changes ([MovaSource.sameAs]), recreated when
/// [options] player sections change, paused when the source goes null, disposed with the
/// widget. The imperative API (`createMova` + `MovaPlayer`) is unchanged
/// and still the way to go when you need to hand a player around.
///
/// Do not hand a view-owned player to `MovaMini` to keep across routes: the
/// view disposes it when it unmounts.
///
/// 声明式播放器：给它一个 [source]，它就接管整个播放器生命周期——第一次拿到非空源
/// 时懒创建、只有源真正变了（[MovaSource.sameAs]）才重开、[options] 的播放器节变化时重建、
/// 源变为 null 时暂停、随组件销毁一并释放。命令式 API（`createMova` +
/// `MovaPlayer`）不变，需要把播放器传来传去时仍然用它。
///
/// 不要把由 view 持有的播放器交给 `MovaMini` 跨路由保留：view 卸载时会把它销毁。
///
/// Example / 示例:
/// ```dart
/// MovaView(
///   source: url == null ? null : MovaSource(url, type: MovaStreamType.live),
///   fit: MovaFit.cover,
///   poster: Image.network(cover, fit: BoxFit.cover),
///   uiKit: const MovaMinimalUiKit(),
/// )
/// ```
class MovaView extends StatefulWidget {
  /// Creates the view.
  ///
  /// 创建组件。
  ///
  /// - [source]: what to play; `null` shows only the poster / 要播放的源；`null` 时只显示封面
  /// - [autoPlay]: whether a newly opened source starts playing / 新打开的源是否立即播放
  /// - [fit]: declarative fill mode, see [MovaPlayer.fit] / 声明式填充模式，见 [MovaPlayer.fit]
  /// - [poster]: cover shown until the first frame, see [MovaPlayer.poster] / 首帧前的封面，见 [MovaPlayer.poster]
  /// - [posterFade]: poster fade-out duration / 封面淡出时长
  /// - [uiKit]: the UI kit to draw / 要绘制的 UI 套件
  /// - [options]: construction-time player options / 播放器构造期配置
  /// - [movaFactory]: custom player builder / 自定义播放器构建器
  /// - [autoLoadQualities]: probe HLS variants after each open / 每次打开后探测 HLS 档位
  /// - [onMova]: called with every player right after it is created / 每个播放器创建后立即回调
  /// - [onOpenError]: receives `open()` failures / 接收 `open()` 的失败
  /// - [autoPause]: pause while hidden, see [MovaAutoPause]; `null` = no guard / 隐藏时暂停，见 [MovaAutoPause]；`null` 表示不挂守卫
  /// - [routeObservers]: forwarded to [MovaAutoPause.routeObservers] / 透传给 [MovaAutoPause.routeObservers]
  const MovaView({
    super.key,
    required this.source,
    this.autoPlay = true,
    this.fit,
    this.poster,
    this.posterFade = const Duration(milliseconds: 300),
    this.style,
    this.uiKit = const MovaDefaultUiKit(),
    this.options = const MovaOpts(),
    this.movaFactory,
    this.autoLoadQualities = true,
    this.onMova,
    this.onOpenError,
    this.autoPause,
    this.routeObservers = const [],
  });

  /// What to play; `null` shows only the poster (or black).
  ///
  /// 要播放的源；`null` 时只显示封面（或黑底）。
  final MovaSource? source;

  /// Whether a newly opened source starts playing; changes apply to the next open only.
  ///
  /// 新打开的源是否立即播放；改动只影响下一次打开。
  final bool autoPlay;

  /// Declarative fill mode; see [MovaPlayer.fit].
  ///
  /// 声明式填充模式；见 [MovaPlayer.fit]。
  final MovaFit? fit;

  /// Cover shown until the first frame; see [MovaPlayer.poster].
  ///
  /// 首帧前显示的封面；见 [MovaPlayer.poster]。
  final Widget? poster;

  /// How long the poster takes to fade out.
  ///
  /// 封面淡出的时长。
  final Duration posterFade;

  /// The UI kit to draw.
  ///
  /// 要绘制的 UI 套件。
  final IMovaUiKit uiKit;

  /// 本视图的样式，原样传给 MovaPlayer；优先于主题扩展。
  final MovaPlayerStyle? style;

  /// Construction-time player options; changes to player sections recreate the player
  /// and reopen the source. Style sections update the current view.
  ///
  /// 播放器构造期配置；播放器节变化会重建并重开当前源，五个样式节变化只更新视图。
  final MovaOpts options;

  /// Builds the player; defaults to `createMova(options: o, preciseFirstFrame: poster != null)`,
  /// i.e. a poster turns on the native first-frame subscription. Changing it
  /// after mount has no effect.
  ///
  /// 构建播放器；默认是 `createMova(options: o, preciseFirstFrame: poster != null)`，
  /// 也就是有封面时会开原生首帧订阅。挂载后更换它不会生效。
  final MovaViewFactory? movaFactory;

  /// Whether to probe HLS quality variants after each successful open.
  ///
  /// 每次打开成功后是否探测 HLS 清晰度档位。
  /// 本 UI 入口仅在此值与 `api.options.abr.probeVariants` 都为 true 时探测；
  /// 播放器就绪后的自动探测由后者控制，显式 `api.loadQualities()` 不受两者影响。
  final bool autoLoadQualities;

  /// Called with each player right after it is created (and after a recreate),
  /// for hosts that need events or imperative calls.
  ///
  /// 每个播放器创建（及重建）后立即回调，供需要监听事件或命令式调用的宿主使用。
  final void Function(IMovaApi api)? onMova;

  /// Receives an `open()` failure; `null` reports it via `FlutterError.reportError`.
  ///
  /// 接收 `open()` 的失败；为 `null` 时经 `FlutterError.reportError` 上报。
  final void Function(Object error, StackTrace stack)? onOpenError;

  /// Pauses the player while the view is hidden (scrolled away, inactive tab,
  /// covered by a route, app in background) and resumes it afterwards; `null`
  /// (the default) mounts no guard. See [MovaAutoPause] for the limits.
  ///
  /// 视图被隐藏（滚走、非活跃 Tab、被路由盖住、应用进后台）时暂停播放器，之后恢复；
  /// `null`（默认）不挂守卫。局限见 [MovaAutoPause]。
  final MovaAutoPauseOpts? autoPause;

  /// Forwarded to [MovaAutoPause.routeObservers]; only used with [autoPause].
  ///
  /// 透传给 [MovaAutoPause.routeObservers]；仅与 [autoPause] 配合使用。
  final List<RouteObserver<ModalRoute<dynamic>>> routeObservers;

  @override
  State<MovaView> createState() => _MovaViewState();
}

/// State for [MovaView]: owns the player and the "what is currently opened"
/// bookkeeping.
///
/// [MovaView] 的状态：持有播放器，以及"当前打开的是哪个源"的簿记。
class _MovaViewState extends State<MovaView> {
  /// The player this view owns; created lazily.
  ///
  /// 本组件持有的播放器；懒创建。
  IMovaApi? _mova;

  /// The source last handed to [_mova], used to skip same-source reopens.
  ///
  /// 最近一次交给 [_mova] 的源，用来跳过同源重开。
  MovaSource? _opened;

  // Invalidates asynchronous load completion when the view changes source.
  //
  // 视图换源时让异步加载收尾失效。
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  int _optionsChangeStreak = 0;
  Duration? _optionsChangeFrame;
  bool _optionsFrameCheckScheduled = false;
  bool _optionsWarningShown = false;

  void _trackOptionsChanges(bool equal) {
    if (equal) {
      _optionsChangeStreak = 0;
      return;
    }
    final frame = WidgetsBinding.instance.currentFrameTimeStamp;
    if (_optionsChangeFrame != frame) {
      _optionsChangeFrame = frame;
      _optionsChangeStreak++;
    }
    if (_optionsChangeStreak >= 10 && !_optionsWarningShown) {
      _optionsWarningShown = true;
      debugPrint('MovaView 连续 10 帧 options 不等，反复重建播放器；请稳定配置或回调实例。');
    }
    if (!_optionsFrameCheckScheduled) {
      _optionsFrameCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback(_checkOptionsFrame);
    }
  }

  void _checkOptionsFrame(Duration frame) {
    if (!mounted || frame != _optionsChangeFrame) {
      _optionsChangeStreak = 0;
      _optionsFrameCheckScheduled = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(_checkOptionsFrame);
  }

  @override
  void didUpdateWidget(MovaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final equal = widget.options.movaSectionsEqual(oldWidget.options);
    assert(() {
      _trackOptionsChanges(equal);
      return true;
    }());
    if (_mova != null && !equal) {
      final dead = _mova!;
      _mova = null;
      _opened = null;
      unawaited(dead.dispose());
    }
    _sync();
  }

  /// Creates the player through the host's factory or the default wiring.
  ///
  /// 经宿主的工厂或默认接线创建播放器。
  IMovaApi _create() {
    final factory = widget.movaFactory;
    final mova = factory != null
        ? factory(widget.options)
        : createMova(
            options: widget.options,
            preciseFirstFrame: widget.poster != null,
          );
    widget.onMova?.call(mova);
    return mova;
  }

  /// Brings the player in line with [MovaView.source]: pause on null, open on
  /// a genuinely different source, nothing otherwise.
  ///
  /// 让播放器与 [MovaView.source] 保持一致：为空则暂停，真正换源则打开，否则不动。
  void _sync() {
    final src = widget.source;
    if (src == null) {
      _loadGen++;
      if (_opened != null) unawaited(_mova?.pause());
      _opened = null;
      return;
    }
    if (_opened != null && _opened!.sameAs(src)) return;
    final mova = _mova ??= _create();
    _opened = src;
    final gen = ++_loadGen;
    unawaited(
      mova
          .open(src, autoPlay: widget.autoPlay)
          .then((_) async {
            if (!mounted || gen != _loadGen || !identical(_mova, mova)) {
              if (mounted &&
                  identical(_mova, mova) &&
                  widget.source == null) {
                await mova.pause();
              }
              return;
            }
            if (widget.autoLoadQualities &&
                mova.options.abr.probeVariants &&
                identical(_mova, mova)) {
              return mova.loadQualities();
            }
          })
          .catchError((Object e, StackTrace s) {
            if (!mounted || gen != _loadGen || !identical(_mova, mova)) {
              return;
            }
            _reportOpenError(e, s);
          }),
    );
  }

  /// Routes an open failure to [MovaView.onOpenError], or to the Flutter error
  /// handler when none was given, so it never becomes an unhandled async error.
  ///
  /// 把打开失败交给 [MovaView.onOpenError]；没提供时交给 Flutter 的错误处理器，
  /// 避免变成未捕获的异步异常。
  void _reportOpenError(Object error, StackTrace stack) {
    final cb = widget.onOpenError;
    if (cb != null) {
      cb(error, stack);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'mova',
        context: ErrorDescription('while opening the source in MovaView'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mova = _mova;
    if (mova == null || widget.source == null) {
      return ColoredBox(
        color: const Color(0xFF000000),
        child: SizedBox.expand(child: widget.poster),
      );
    }
    final player = MovaStyleScope(
      legacy: widget.options,
      child: MovaPlayer(
        api: mova,
        style: widget.style,
        uiKit: widget.uiKit,
        fit: widget.fit,
        poster: widget.poster,
        posterFade: widget.posterFade,
        autoLoadQualities: false,
      ),
    );
    final guard = widget.autoPause;
    if (guard == null) return player;
    return MovaAutoPause(
      api: mova,
      opts: guard,
      routeObservers: widget.routeObservers,
      child: player,
    );
  }

  @override
  void dispose() {
    _loadGen++;
    final e = _mova;
    _mova = null;
    if (e != null) unawaited(e.dispose());
    super.dispose();
  }
}
