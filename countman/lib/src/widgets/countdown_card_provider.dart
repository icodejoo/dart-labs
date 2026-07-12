import 'package:flutter/widgets.dart';
import 'countdown_card_types.dart';

/// Shares default style/size/timing config across a subtree of
/// [CountdownCard]s, so a whole screen of cards doesn't need to repeat
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
/// [CountdownCardProvider]'s config rebuilds every [CountdownCard] in its
/// scope, the same as [Theme] or [DefaultTextStyle]. It's meant to be
/// configured once per screen — changing it on a hot path (every frame,
/// every tick) works but isn't what it's for.
///
/// ```dart
/// CountdownCardProvider(
///   cardColor: Colors.indigo,
///   textStyle: const TextStyle(fontSize: 32, color: Colors.white),
///   child: GridView(children: [for (final t in targets) CountdownCard(to: t)]),
/// )
/// ```
class CountdownCardProvider extends StatefulWidget {
  const CountdownCardProvider({
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

  /// Looks up the nearest ancestor [CountdownCardProvider], subscribing this
  /// context to it — the caller rebuilds whenever the provider's config
  /// changes. Returns null if there is no ancestor provider.
  static CountdownCardProviderData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CountdownCardScope>()?.data;

  @override
  State<CountdownCardProvider> createState() => _CountdownCardProviderState();
}

class _CountdownCardProviderState extends State<CountdownCardProvider> {
  // One cache per provider instance, stable across rebuilds (only recreated
  // if the provider widget itself is torn down and remounted).
  final _cache = <(String, TextStyle), TextPainter>{};

  @override
  void dispose() {
    for (final tp in _cache.values) {
      tp.dispose(); // release cached native paragraphs
    }
    _cache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CountdownCardScope(
        data: CountdownCardProviderData(
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
/// [CountdownCard]s by [CountdownCardProvider].
class CountdownCardProviderData {
  const CountdownCardProviderData({
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

  /// Shared glyph cache — see the class-level doc on [CountdownCardProvider]
  /// for which cards actually use it vs their own local cache.
  final Map<(String, TextStyle), TextPainter> cache;
}

class _CountdownCardScope extends InheritedWidget {
  const _CountdownCardScope({required this.data, required super.child});

  final CountdownCardProviderData data;

  @override
  bool updateShouldNotify(_CountdownCardScope oldWidget) =>
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
