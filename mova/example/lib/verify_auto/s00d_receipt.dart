import 'dart:async';
import 'package:mova/mova.dart';

typedef ReceiptSink = void Function(String, Map<String, Object?>);

/// Independent state/event subscriptions deliberately expose H77 ordering.
/// Never infer the implementation from an old engine hash.
class ReceiptAudit {
  ReceiptAudit(this.api, this.sink) {
    latest = values(api.state);
    stateSub = api.states.listen((s) {
      latest = values(s);
    });
    progressSub = api.progress.listen((p) {
      positionMs = p.position.inMilliseconds;
    });
    eventSub = api.events.listen(receive);
  }
  final MovaApi api;
  final ReceiptSink sink;
  late Map<String, Object?> latest;
  int positionMs = 0;
  late final StreamSubscription<MovaState> stateSub;
  late final StreamSubscription<MovaProg> progressSub;
  late final StreamSubscription<MovaEvent> eventSub;

  static Map<String, Object?> values(MovaState s) => {
    'duration': s.duration.inMilliseconds,
    'buffering': s.buffering,
    'playing': s.playing,
    'width': s.width,
    'height': s.height,
    'volume': s.volume,
    'brightness': s.brightness,
    'rate': s.rate,
    'fit': s.fit.name,
    'zoom': s.zoom,
    'locked': s.locked,
    'fullscreen': s.fullscreen,
    'orientation': s.orientation.name,
    'pip': s.pip,
    'mini': s.mini,
    'rendered': s.rendered,
    'sourceIndex': s.sourceIndex,
    'intent': s.playbackIntent,
    'keepAlive': s.keepAlivePhase.name,
    'renderEpoch': s.renderEpoch,
    'quality': s.currentQuality == null ? null : quality(s.currentQuality!),
    'qualities': s.qualities.map(quality).toList(),
    'completed': s.completed,
    'pipSupported': s.pipSupported,
    'type': s.type.name,
    'liveSeekable': s.liveSeekable,
    'seekableWindow': s.seekableWindow.inMilliseconds,
    'timeshiftBehind': s.timeshiftBehind?.inMilliseconds,
    'error': s.error?.toString(),
    'title': s.sourceTitle,
  };

  static Map<String, Object?> quality(MovaQuality q) => {
    'label': q.label,
    'uri': q.uri,
    'bandwidth': q.bandwidth,
    'width': q.width,
    'height': q.height,
    'isAuto': q.isAuto,
  };

  void receive(MovaEvent e) {
    final expected = Map<String, Object?>.of(latest);
    // Override only fields actually asserted by this event's public contract.
    expected.addAll(switch (e) {
      MovaSourceChange() => {
        'title': e.source.title,
        'type': e.source.type.name,
        'sourceIndex': 0,
      },
      MovaDone() => {'completed': true},
      MovaErrorEvent() => {'error': e.error.toString()},
      MovaTimeShiftChange() => {'timeshiftBehind': e.behind.inMilliseconds},
      MovaDurationChange() => {'duration': e.duration.inMilliseconds},
      MovaBufferChange() => {'buffering': e.buffering},
      MovaPlay() => {'playing': true},
      MovaPause() => {'playing': false},
      MovaSizeChange() => {'width': e.width, 'height': e.height},
      MovaVolumeChange() => {'volume': e.value},
      MovaBrightChange() => {'brightness': e.value},
      MovaRateChange() => {'rate': e.value},
      MovaFitChange() => {'fit': e.fit.name},
      MovaZoomChange() => {'zoom': e.zoom},
      MovaLockChange() => {'locked': e.value},
      MovaFullScreenChange() => {'fullscreen': e.value},
      MovaOrientationChange() => {'orientation': e.orientation.name},
      MovaPipChange() => {'pip': e.value},
      MovaMiniChange() => {'mini': e.mini},
      MovaFirstFrame() => {'rendered': true},
      MovaFailover() => {'sourceIndex': e.to},
      MovaKeepAliveChange() => {'keepAlive': e.phase.name},
      MovaQualityChange() => {'quality': quality(e.quality)},
      MovaQualityListChange() => {
        'qualities': e.qualities.map(quality).toList(),
      },
      _ => <String, Object?>{},
    });
    final actual = values(api.state);
    // Progress is a separate public stream (MovaState has no position).
    // Seeked's public payload is compared against its last received progress,
    // never a process-global position belonging to a different engine.
    if (e is MovaSeeked) {
      expected['position'] = e.position.inMilliseconds;
      actual['position'] = positionMs;
    } else {
      expected['position'] = positionMs;
      actual['position'] = positionMs;
    }
    final differences = expected.keys
        .where((k) => !_equal(expected[k], actual[k]))
        .toList();
    sink('CHECK', {
      'id': 'A2.${api is MovaCutoverEngine ? 'cutover' : 'engine'}.receipt',
      'pass': differences.isEmpty,
      'origin': 'public-api-receipt',
      'engine': identityHashCode(api),
      'event': e.runtimeType.toString(),
      'expected': expected,
      'actual': actual,
      'differences': differences,
      'numbers': {'fields': actual.length},
    });
  }

  static bool _equal(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => _equal(a[i], b[i])).every((v) => v);
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    return a == b;
  }

  Future<void> dispose() async {
    await eventSub.cancel();
    await stateSub.cancel();
    await progressSub.cancel();
  }
}
