import 'dart:collection';
import 'package:flutter/widgets.dart';
import 'card_countdown_types.dart';

/// Shares default style/size/timing config across a subtree of
/// [CardCountdown]s, so a whole screen of cards doesn't need to repeat
/// `cardColor:`/`textStyle:`/`duration:` etc. on every instance.
///
/// For whichever of [textStyle], [labelStyle], [separatorStyle] a card
/// actually inherits (left unset on the card itself), cards in scope also
/// share a glyph-level [TextPainter] cache keyed by `(text, style)` — the
/// same digit/separator/label rendered by many cards is laid out once and
/// reused, not re-shaped on every card every frame. A card that overrides
/// one of these styles uses its own local cache for that style instead, so
/// per-card customizations never pollute the shared pool.
///
/// Uses the standard subscribing [InheritedWidget] lookup: changing a
/// [CardCountdownProvider]'s config rebuilds every [CardCountdown] in its
/// scope, the same as [Theme] or [DefaultTextStyle]. It's meant to be
/// configured once per screen — changing it on a hot path (every frame,
/// every tick) works but isn't what it's for.
///
/// ```dart
/// CardCountdownProvider(
///   cardColor: Colors.indigo,
///   textStyle: const TextStyle(fontSize: 32, color: Colors.white),
///   child: GridView(children: [for (final t in targets) CardCountdown(to: t)]),
/// )
/// ```
class CardCountdownProvider extends StatefulWidget {
  const CardCountdownProvider({
    super.key,
    required this.child,
    this.cardColor,
    this.textStyle,
    this.labelStyle,
    this.separatorStyle,
    this.duration,
    this.curve,
    this.cardWidth,
    this.cardHeight,
    this.digitGap,
    this.unitGap,
    this.transitionType,
    this.scaleEffect,
    this.scaleFactor,
    this.opacityEffect,
    this.perspective,
  });

  final Widget child;
  final Color? cardColor;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final TextStyle? separatorStyle;
  final Duration? duration;
  final Curve? curve;
  final double? cardWidth;
  final double? cardHeight;
  final double? digitGap;
  final double? unitGap;
  final CountdownType? transitionType;
  final SlideEffect? scaleEffect;
  final double? scaleFactor;
  final SlideEffect? opacityEffect;
  final double? perspective;

  /// Looks up the nearest ancestor [CardCountdownProvider], subscribing this
  /// context to it — the caller rebuilds whenever the provider's config
  /// changes. Returns null if there is no ancestor provider.
  static CardCountdownProviderData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardCountdownScope>()?.data;

  @override
  State<CardCountdownProvider> createState() => _CardCountdownProviderState();
}

class _CardCountdownProviderState extends State<CardCountdownProvider> {
  // One cache per provider instance, stable across rebuilds (only recreated
  // if the provider widget itself is torn down and remounted).
  final _cache = CardGlyphCache();

  /// Provider 样式变化后释放旧段落，避免反复换主题积累缓存。
  @override
  void didUpdateWidget(CardCountdownProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textStyle != widget.textStyle ||
        oldWidget.labelStyle != widget.labelStyle ||
        oldWidget.separatorStyle != widget.separatorStyle) {
      _cache.clear();
    }
  }

  @override
  void dispose() {
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CardCountdownScope(
        data: CardCountdownProviderData(
          cardColor: widget.cardColor,
          textStyle: widget.textStyle,
          labelStyle: widget.labelStyle,
          separatorStyle: widget.separatorStyle,
          duration: widget.duration,
          curve: widget.curve,
          cardWidth: widget.cardWidth,
          cardHeight: widget.cardHeight,
          digitGap: widget.digitGap,
          unitGap: widget.unitGap,
          transitionType: widget.transitionType,
          scaleEffect: widget.scaleEffect,
          scaleFactor: widget.scaleFactor,
          opacityEffect: widget.opacityEffect,
          perspective: widget.perspective,
          cache: _cache,
        ),
        child: widget.child,
      );
}

/// Resolved config + shared glyph cache exposed to descendant
/// [CardCountdown]s by [CardCountdownProvider].
class CardCountdownProviderData {
  const CardCountdownProviderData({
    required this.cardColor,
    required this.textStyle,
    required this.labelStyle,
    required this.separatorStyle,
    required this.duration,
    required this.curve,
    required this.cardWidth,
    required this.cardHeight,
    required this.digitGap,
    required this.unitGap,
    required this.transitionType,
    required this.scaleEffect,
    required this.scaleFactor,
    required this.opacityEffect,
    required this.perspective,
    required this.cache,
  });

  final Color? cardColor;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final TextStyle? separatorStyle;
  final Duration? duration;
  final Curve? curve;
  final double? cardWidth;
  final double? cardHeight;
  final double? digitGap;
  final double? unitGap;
  final CountdownType? transitionType;
  final SlideEffect? scaleEffect;
  final double? scaleFactor;
  final SlideEffect? opacityEffect;
  final double? perspective;

  /// Shared glyph cache — see the class-level doc on [CardCountdownProvider]
  /// for which cards actually use it vs their own local cache.
  final Map<(String, TextStyle), TextPainter> cache;
}

class _CardCountdownScope extends InheritedWidget {
  const _CardCountdownScope({required this.data, required super.child});

  final CardCountdownProviderData data;

  @override
  bool updateShouldNotify(_CardCountdownScope oldWidget) =>
      data.cardColor != oldWidget.data.cardColor ||
      data.textStyle != oldWidget.data.textStyle ||
      data.labelStyle != oldWidget.data.labelStyle ||
      data.separatorStyle != oldWidget.data.separatorStyle ||
      data.duration != oldWidget.data.duration ||
      data.curve != oldWidget.data.curve ||
      data.cardWidth != oldWidget.data.cardWidth ||
      data.cardHeight != oldWidget.data.cardHeight ||
      data.digitGap != oldWidget.data.digitGap ||
      data.unitGap != oldWidget.data.unitGap ||
      data.transitionType != oldWidget.data.transitionType ||
      data.scaleEffect != oldWidget.data.scaleEffect ||
      data.scaleFactor != oldWidget.data.scaleFactor ||
      data.opacityEffect != oldWidget.data.opacityEffect ||
      data.perspective != oldWidget.data.perspective;
}

/// 有界字形缓存，最多保留 512 个段落；删除、替换和清空均负责 dispose。
/// 使用与 Map 相同的接口，例如 `cache.putIfAbsent((text, style), create)`。
class CardGlyphCache extends MapBase<(String, TextStyle), TextPainter> {
  /// 缓存上限覆盖数字的 16 档透明度及标签和分隔符。
  static const int capacity = 512;
  /// 插入顺序也是最早可淘汰的顺序。
  final _entries = <(String, TextStyle), TextPainter>{};
  /// 返回已缓存段落，未命中时为 null。
  @override
  TextPainter? operator [] (Object? key) => _entries[key];
  /// 插入段落；替换和超出容量时释放旧段落。
  @override
  void operator []=((String, TextStyle) key, TextPainter value) {
    final old = _entries.remove(key);
    if (old != null && !identical(old, value)) old.dispose();
    if (_entries.length >= capacity) remove(_entries.keys.first);
    _entries[key] = value;
  }
  /// 当前缓存键，按插入顺序迭代。
  @override
  Iterable<(String, TextStyle)> get keys => _entries.keys;
  /// 清空并释放所有段落。
  @override
  void clear() {
    for (final painter in _entries.values) { painter.dispose(); }
    _entries.clear();
  }
  /// 移除时同步释放；返回已释放对象，仅供 Map 接口兼容，不应再次使用。
  @override
  TextPainter? remove(Object? key) {
    final painter = _entries.remove(key);
    painter?.dispose();
    return painter;
  }
}
