import '../style/style.dart';

import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/model/danmaku.dart';
import '../../core/events/events.dart';
import '../../core/options/danmaku_config.dart';
import '../../core/state/progress.dart';
import '../scope/plugin.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// bilibili-style scrolling-danmaku overlay; renders nothing when
/// [MovaDanmakuConfig.enabled] is off or [MovaDanmakuConfig.items] is empty.
///
/// Display-only (see [MovaDanmakuConfig]'s doc comment): comments spawn as
/// playback position crosses their [MovaDanmakuItem.time] and scroll right to
/// left over [MovaDanmakuConfig.crossDuration], each assigned a horizontal
/// track round-robin to reduce overlap.
///
/// bilibili 风格滚动弹幕叠加层；[MovaDanmakuConfig.enabled] 关闭或
/// [MovaDanmakuConfig.items] 为空时不渲染任何内容。
///
/// 仅做展示（见 [MovaDanmakuConfig] 的文档注释）：播放位置跨过弹幕的
/// [MovaDanmakuItem.time] 时生成一条弹幕，在 [MovaDanmakuConfig.crossDuration]
/// 内从右向左滚动划过，按轮询方式分配横向轨道以减少重叠。
class MovaDanmakuTrackComponent extends MovaComponent {
  /// Creates the danmaku-track component.
  ///
  /// 创建弹幕轨道组件。
  MovaDanmakuTrackComponent();

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'danmakuTrack';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.overlay;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final config = MovaPlayerStyle.danmakuOf(context)
        .applyTo(movaLegacyOptionsOf(context).danmaku);
    if (!config.enabled || config.items.isEmpty) return const SizedBox.shrink();
    return _DanmakuTrack(api: api, config: config);
  }
}

/// Stateful widget spawning/retiring individual [_DanmakuBullet]s as
/// playback position crosses each [MovaDanmakuItem.time].
///
/// 依据播放位置跨过每条 [MovaDanmakuItem.time] 来生成/回收单条
/// [_DanmakuBullet] 的有状态 widget。
class _DanmakuTrack extends StatefulWidget {
  /// Creates the internal danmaku track widget.
  ///
  /// 创建内部弹幕轨道 widget。
  const _DanmakuTrack({required this.api, required this.config});

  /// The capability surface this track follows for playback position.
  ///
  /// 该轨道跟随播放位置所使用的能力面。
  final MovaApi api;

  /// The danmaku configuration in effect.
  ///
  /// 当前生效的弹幕配置。
  final MovaDanmakuConfig config;

  @override
  State<_DanmakuTrack> createState() => _DanmakuTrackState();
}

/// State for [_DanmakuTrack]; owns the currently-visible bullets and the
/// last-seen playback position used to detect newly-crossed [MovaDanmakuItem]s.
///
/// [_DanmakuTrack] 的状态；持有当前可见的弹幕，以及用于检测新跨过的
/// [MovaDanmakuItem] 的最近播放位置。
class _DanmakuTrackState extends State<_DanmakuTrack>
    with MovaPlugin<_DanmakuTrack> {
  /// Currently-visible bullets, each keyed by a stable [Key] for removal.
  ///
  /// 当前可见的弹幕，各自带一个用于移除的稳定 [Key]。
  final List<_Spawned> _active = <_Spawned>[];

  /// Playback position as of the previous [MovaProg] tick.
  ///
  /// 上一次 [MovaProg] tick 时的播放位置。
  Duration _lastPosition = Duration.zero;

  /// Round-robin cursor over [MovaDanmakuConfig.trackCount] horizontal tracks.
  ///
  /// 在 [MovaDanmakuConfig.trackCount] 条横向轨道间轮询的游标。
  int _nextTrack = 0;

  /// [MovaDanmakuConfig.items] sorted ascending by time, so [_onProgress] can
  /// spawn newly-crossed comments from a monotonic cursor instead of rescanning
  /// the whole (potentially thousands-strong) list on every progress tick.
  ///
  /// 按时间升序排好的 [MovaDanmakuConfig.items]，使 [_onProgress] 能从单调游标
  /// 生成新跨过的弹幕，而非每个进度 tick 都重扫整张（可能成千上万条的）表。
  late List<MovaDanmakuItem> _sorted;

  /// Index into [_sorted] of the first not-yet-crossed comment; kept equal to
  /// "first item with time > [_lastPosition]" across forward ticks (the while
  /// loop) and backward seeks ([_firstAfter]).
  ///
  /// [_sorted] 中第一条尚未跨过的弹幕下标；在前进 tick（while 循环）与后跳
  /// seek（[_firstAfter]）之间始终保持等于"首个 time > [_lastPosition] 的条目"。
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _resort();
    bind(api.progress, _onProgress);
    bind(api.states, (_) => setState(() {}));
    bind(api.events, _onEvent);
  }

  @override
  void didUpdateWidget(_DanmakuTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sort only when the host actually swapped the item list; positions
    // arrive far more often than the list changes.
    //
    // 仅在宿主真的换了弹幕列表时才重排；位置更新远比列表变化频繁。
    if (!identical(widget.config.items, oldWidget.config.items)) _resort();
  }

  /// Rebuilds [_sorted] from the current config and repositions [_cursor] to
  /// the first item past [_lastPosition].
  ///
  /// 依当前配置重建 [_sorted]，并把 [_cursor] 重定位到 [_lastPosition] 之后的第一条。
  void _resort() {
    _sorted = [...widget.config.items]
      ..sort((a, b) => a.time.compareTo(b.time));
    _cursor = _firstAfter(_lastPosition);
  }

  /// Returns the index of the first item in [_sorted] whose time is strictly
  /// greater than [t] (upper bound); `_sorted.length` if none.
  ///
  /// 返回 [_sorted] 中首个 time 严格大于 [t] 的条目下标（上界）；没有则返回
  /// `_sorted.length`。
  ///
  /// - [t]: the position to bound against / 用于定界的位置
  int _firstAfter(Duration t) {
    var lo = 0;
    var hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid].time <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 换源或显式 seek 时清屏，直接把游标移到目标之后。
  void _onEvent(MovaEvent event) {
    if (event is MovaSeek) {
      _moveTo(event.target);
    } else if (event is MovaSourceChange) {
      _moveTo(Duration.zero);
    }
  }

  /// 二分定位 [position] 并清除旧时间轴上的活动弹幕。
  void _moveTo(Duration position) {
    _cursor = _firstAfter(position);
    _lastPosition = position;
    setState(_active.clear);
  }

  /// 正常进度仅生成有空位的弹幕；大幅跳转只移动游标，不遍历跳过区间。
  void _onProgress(MovaProg p) {
    final position = p.position;
    if (position < _lastPosition ||
        position - _lastPosition > const Duration(seconds: 10)) {
      _moveTo(position);
      return;
    }
    final end = _firstAfter(position);
    final limit = widget.config.trackCount * 2;
    while (_cursor < end && _active.length < limit) {
      _spawn(_sorted[_cursor++]);
    }
    _cursor = end;
    _lastPosition = position;
  }

  /// Adds [item] to [_active] on a round-robin track.
  ///
  /// 把 [item] 以轮询方式分配到某条轨道并加入 [_active]。
  void _spawn(MovaDanmakuItem item) {
    final track = _nextTrack % widget.config.trackCount;
    _nextTrack++;
    setState(
      () => _active.add(_Spawned(key: UniqueKey(), item: item, track: track)),
    );
  }

  /// Removes the bullet keyed by [key] once its scroll animation finishes.
  ///
  /// 某条弹幕滚动动画结束后，按 [key] 将其从 [_active] 移除。
  void _retire(Key key) {
    if (!mounted) return;
    setState(() => _active.removeWhere((s) => s.key == key));
  }

  @override
  Widget build(BuildContext context) {
    final theme = MovaPlayerStyle.themeOf(context);
    return IgnorePointer(
      child: Opacity(
        opacity: widget.config.opacity,
        child: Stack(
          children: [
            for (final spawned in _active)
              _DanmakuBullet(
                key: spawned.key,
                text: spawned.item.text,
                color: spawned.item.color ?? theme.textColor,
                track: spawned.track,
                config: widget.config,
                playing: widget.api.state.playing,
                rate: widget.api.state.rate,
                onFinished: () => _retire(spawned.key),
              ),
          ],
        ),
      ),
    );
  }
}

/// A currently-visible danmaku bullet: its source [item], the assigned
/// [track], and a stable [key] for removal.
///
/// 一条当前可见的弹幕：其来源 [item]、分配到的 [track]，以及用于移除的
/// 稳定 [key]。
class _Spawned {
  /// Creates a spawned-bullet record.
  ///
  /// 创建一条已生成弹幕的记录。
  const _Spawned({required this.key, required this.item, required this.track});

  /// Stable key identifying this bullet for removal.
  ///
  /// 标识该弹幕、用于移除的稳定 key。
  final Key key;

  /// The comment being rendered.
  ///
  /// 正在渲染的弹幕内容。
  final MovaDanmakuItem item;

  /// The horizontal track this bullet scrolls along.
  ///
  /// 该弹幕滚动所在的横向轨道。
  final int track;
}

/// A single scrolling comment; animates from just off the right edge to just
/// off the left edge over [_DanmakuBulletConfig.crossDuration], then calls
/// [onFinished] so its owner can drop it.
///
/// 单条滚动弹幕；在 [_DanmakuBulletConfig.crossDuration] 内从刚超出右边缘
/// 滚动到刚超出左边缘，结束后调用 [onFinished] 供持有方移除。
class _DanmakuBullet extends StatefulWidget {
  /// Creates a scrolling bullet.
  ///
  /// 创建一条滚动弹幕。
  const _DanmakuBullet({
    super.key,
    required this.text,
    required this.color,
    required this.track,
    required this.config,
    required this.onFinished,
    required this.playing,
    required this.rate,
  });

  /// The comment text.
  ///
  /// 弹幕文案。
  final String text;

  /// ARGB text color.
  ///
  /// 文字的 ARGB 颜色。
  final int color;

  /// The horizontal track this bullet renders on.
  ///
  /// 该弹幕渲染所在的横向轨道。
  final int track;

  /// The danmaku configuration in effect.
  ///
  /// 当前生效的弹幕配置。
  final MovaDanmakuConfig config;

  /// Called once the scroll animation completes.
  ///
  /// 滚动动画结束时调用。
  final VoidCallback onFinished;

  /// 当前是否播放，暂停时停止动画时钟。
  final bool playing;

  /// 当前播放倍速，决定弹幕划过速度。
  final double rate;

  /// 创建独立的可暂停动画状态。
  @override
  State<_DanmakuBullet> createState() => _DanmakuBulletState();
}

/// 单条弹幕的动画状态，暂停/倍速更新均保留当前进度。
class _DanmakuBulletState extends State<_DanmakuBullet>
    with SingleTickerProviderStateMixin {
  /// 当前划过比例；仅持有本条弹幕的时钟。
  late final AnimationController _controller;

  /// 初始化动画，并在完成时通知轨道回收。
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_onStatus);
    _syncAnimation();
  }

  /// 动画完成后回收弹幕。
  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onFinished();
  }

  /// 播放态或倍速变化时更新动画。
  @override
  void didUpdateWidget(_DanmakuBullet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.rate != widget.rate ||
        oldWidget.config.crossDuration != widget.config.crossDuration) {
      _syncAnimation();
    }
  }

  /// 暂停保持当前位置，恢复时用当前倍速走完剩余比例。
  void _syncAnimation() {
    _controller.stop();
    final rate = widget.rate > 0 ? widget.rate : 1.0;
    final micros = (widget.config.crossDuration.inMicroseconds / rate).round();
    _controller.duration = Duration(microseconds: micros < 1 ? 1 : micros);
    if (widget.playing && !_controller.isCompleted) _controller.forward();
  }

  /// 离场释放动画时钟。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按动画比例从右向左移动文案。
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.config.trackHeight * widget.track,
      left: 0,
      right: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(width * (1 - 2 * _controller.value), 0),
              child: child,
            ),
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Color(widget.color),
                fontSize: widget.config.fontSize,
              ),
            ),
          );
        },
      ),
    );
  }
}
