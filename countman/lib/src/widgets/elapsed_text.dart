import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/types.dart' show DurationFormatter, CountdownFormat, TimeParts;
import 'package:countman/src/elapsed/plugin.dart';
import 'package:countman/src/elapsed/types.dart';
import 'providers.dart';

/// Displays an open-ended elapsed-time counter — a stopwatch, not a
/// countdown. Starts at zero the moment it's mounted and counts up
/// indefinitely until removed or [ElapsedController.cancel]led.
///
/// Reuses [CountdownFormat]'s duration formatters ([DurationFormatter]) —
/// `hms`/`ms`/`msTenths`/`auto` are pure `Duration -> String` functions with
/// no assumption about counting direction, so the same formatters that
/// render "remaining" for a countdown render "elapsed" here unchanged.
///
/// ```dart
/// ElapsedText() // 00:00, 00:01, 00:02, ...
/// ElapsedText(formatter: CountdownFormat.hms)
/// ```
///
/// ## Imperative control (pause / resume / reset)
/// ```dart
/// final _ctrl = ElapsedController();
/// ElapsedText(controller: _ctrl);
/// _ctrl.pause();
/// _ctrl.resume();
/// _ctrl.reset();
/// ```
class ElapsedText extends StatefulWidget {
  const ElapsedText({
    super.key,
    this.formatter = CountdownFormat.auto,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.strutStyle,
    this.textScaler,
    this.locale,
    this.textWidthBasis,
    this.semanticsLabel,
    this.plugin,
    this.controller,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Converts elapsed [Duration] to a display string.
  final DurationFormatter formatter;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Forwarded to the underlying [Text]. See [Text] for semantics.
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final StrutStyle? strutStyle;
  final TextScaler? textScaler;
  final Locale? locale;
  final TextWidthBasis? textWidthBasis;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the per-second changing digits.
  final String? semanticsLabel;

  /// Optional [Elapsed] group. Defaults to [defaultElapsed].
  final Elapsed? plugin;

  /// Optional controller for pause / resume / reset.
  final ElapsedController? controller;

  /// When elapsed time first reaches or exceeds this, [onThreshold] fires
  /// once. null (default) disables the check.
  final Duration? threshold;

  /// Called once when elapsed time crosses [threshold].
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  TimeParts _parts = TimeParts.of(Duration.zero);
  final ValueNotifier<int> _rev = ValueNotifier(0);
  ElapsedHandle? _handle;
  // Plugin inherited from the nearest ElapsedProvider (null if none).
  Elapsed? _scopePlugin;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopePlugin = CountmanScope.maybeOf<Elapsed>(context)?.plugin;
    // Start on first resolve, or re-anchor if the inherited group changed.
    if (!_initialized || scopePlugin != _scopePlugin) {
      _initialized = true;
      _scopePlugin = scopePlugin;
      _start();
    }
  }

  void _start() {
    _handle?.cancel();
    _handle = (widget.plugin ?? _scopePlugin ?? defaultElapsed).add(ElapsedOptions(
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
      },
      threshold: widget.threshold,
      onThreshold: widget.onThreshold,
      onReady: widget.onReady,
      onStart: widget.onStart,
      onCancel: widget.onCancel,
      onPause: widget.onPause,
      onResume: widget.onResume,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(ElapsedText old) {
    super.didUpdateWidget(old);
    // A changed plugin or controller must re-anchor the task and re-attach,
    // mirroring the countdown display widgets.
    if (widget.plugin != old.plugin || widget.controller != old.controller) {
      old.controller?.detach();
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _rev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effStyle =
        widget.style ?? CountmanScope.maybeOf<Elapsed>(context)?.textStyle;
    return ValueListenableBuilder<int>(
      valueListenable: _rev,
      builder: (_, __, ___) => Text(widget.formatter(_parts),
          style: effStyle,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          softWrap: widget.softWrap,
          strutStyle: widget.strutStyle,
          textScaler: widget.textScaler,
          locale: widget.locale,
          textWidthBasis: widget.textWidthBasis,
          semanticsLabel: widget.semanticsLabel),
    );
  }
}
