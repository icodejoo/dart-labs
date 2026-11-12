import 'package:flutter_test/flutter_test.dart';
import 'package:mova_example/verify_auto/cp2_criteria.dart';

Map<String, dynamic> sample(
  int ms, {
  bool playing = true,
  bool intent = true,
}) => {
  'path': 'http://fixture/audio.mp4?t=123',
  'timePosMs': ms,
  'pause': playing ? 'no' : 'yes',
  'mute': 'no',
  'audioCodec': 'aac',
  'nativeVolume': '100',
  'state': {'playing': playing, 'intent': intent},
};
void main() {
  test(
    'slot clock uses first frame and observed edges, including command lag',
    () {
      final rows = <Map<String, Object?>>[
        {
          'kind': 'AD',
          'event': 'MovaAdEvent',
          'uri': 'ad',
          'type': 'started',
          'us': 0,
        },
        {
          'kind': 'EVENT',
          'event': 'MovaFirstFrame',
          'uriAtEvent': 'ad',
          'us': 100000,
          'state': {'playing': true},
        },
        {'kind': 'CALL', 'us': 1100000, 'name': 'pause'},
        {
          'kind': 'STATE',
          'us': 1620000,
          'state': {'playing': false},
        },
        {'kind': 'CALL', 'us': 11620000, 'name': 'play'},
        {
          'kind': 'STATE',
          'us': 12060000,
          'state': {'playing': true},
        },
        {
          'kind': 'AD',
          'event': 'MovaAdEvent',
          'uri': 'ad',
          'type': 'completed',
          'us': 16540000,
        },
      ];
      expect(cp2SlotActiveUs(rows, 'ad'), 6000000);
      expect(cp2SlotActiveUs(rows, 'ad', untilUs: 2000000), 1520000);
      expect(cp2SlotActiveUs(rows, 'ad', untilUs: 12000000), 1520000);
      for (final index in [1, 3, 5, 6]) {
        expect(cp2SlotActiveUs([...rows]..removeAt(index), 'ad'), isNull);
      }
      expect(cp2SlotActiveUs(rows, 'other'), isNull);
      expect(
        cp2SlotActiveUs([rows[0], rows[1], ...rows.skip(1)], 'ad'),
        isNull,
      );
    },
  );
  test('ad lifecycle requires exact per-source natural sequence', () {
    Map<String, Object?> row(String t) => {
      'event': 'MovaAdEvent',
      'kind': 'AD',
      'adKind': 'mid',
      'uri': 'ad',
      'type': t,
    };
    final rows = ['pending', 'started', 'completed'].map(row).toList();
    expect(cp2AdLifecycle(rows, 'ad', kind: 'mid', pending: true), isTrue);
    expect(cp2AdLifecycle(rows, 'ad', kind: 'mid', pending: false), isFalse);
    expect(
      cp2AdLifecycle(rows.reversed, 'ad', kind: 'mid', pending: true),
      isFalse,
    );
    expect(
      cp2AdLifecycle(
        [...rows, row('failed')],
        'ad',
        kind: 'mid',
        pending: true,
      ),
      isFalse,
    );
    expect(
      cp2AdLifecycle(
        [...rows, row('completed')],
        'ad',
        kind: 'mid',
        pending: true,
      ),
      isFalse,
    );
    expect(cp2AdLifecycle(rows, 'other', kind: 'mid', pending: true), isFalse);
    expect(cp2AdLifecycle(rows, 'ad', kind: 'pre', pending: true), isFalse);
    expect(
      cp2AdLifecycle(rows.skip(1), 'ad', kind: 'mid', pending: false),
      isTrue,
    );
  });
  test('ad completion uses callback identity and scheduled URI', () {
    final rows = <Map<String, Object?>>[
      {'kind': 'pre', 'event': 'MovaAdEvent', 'uri': 'ad', 'type': 'started'},
      {'kind': 'pre', 'event': 'MovaAdEvent', 'uri': 'ad', 'type': 'completed'},
      {
        'kind': 'AD',
        'event': 'MovaAdEvent',
        'uri': 'other',
        'type': 'completed',
      },
      {'kind': 'EVENT', 'uri': 'ad', 'type': 'completed'},
    ];
    expect(cp2AdRecords(rows, 'ad', type: 'completed').length, 1);
    expect(cp2AdRecords(rows, 'ad', type: 'pending'), isEmpty);
  });
  test('audio requires native advance, audible track and preserved intent', () {
    expect(cp2AudioSamples([sample(1000), sample(2000)], intent: true), isTrue);
    expect(
      cp2AudioSamples([sample(1000), sample(1000)], intent: true),
      isFalse,
    );
    expect(
      cp2AudioSamples([
        sample(1000),
        sample(2000, intent: false),
      ], intent: true),
      isFalse,
    );
  });
  test('missing native fields and single snapshots cannot pass', () {
    expect(cp2AudioSamples([], intent: true), isFalse);
    expect(cp2AudioSamples([sample(1000)], intent: true), isFalse);
    for (final key in [
      'path',
      'timePosMs',
      'pause',
      'state',
      'audioCodec',
      'nativeVolume',
    ]) {
      final broken = sample(2000)..remove(key);
      expect(
        cp2AudioSamples([sample(1000), broken], intent: true),
        isFalse,
        reason: key,
      );
    }
  });
  test('mute, zero volume, missing track and source changes are rejected', () {
    for (final entry in {
      'mute': 'yes',
      'nativeVolume': '0',
      'audioCodec': 'no',
      'path': 'other',
    }.entries) {
      final broken = sample(2000)..[entry.key] = entry.value;
      expect(
        cp2AudioSamples([sample(1000), broken], intent: true),
        isFalse,
        reason: entry.key,
      );
    }
  });
  test('paused native samples require frozen position and paused state', () {
    expect(
      cp2PausedSamples([
        sample(1000, playing: false),
        sample(1100, playing: false),
      ]),
      isTrue,
    );
    expect(
      cp2PausedSamples([
        sample(1000, playing: false),
        sample(1400, playing: false),
      ]),
      isFalse,
    );
    expect(
      cp2PausedSamples([sample(1000, playing: false), sample(1000)]),
      isFalse,
    );
    expect(
      cp2PausedSamples([
        sample(1000, playing: false),
        sample(1100, playing: false),
      ], path: 'wrong'),
      isFalse,
    );
  });
  test('paused excursion cannot hide behind matching first and last', () {
    expect(
      cp2PausedSamples([
        sample(1000, playing: false),
        sample(3000, playing: false),
        sample(1000, playing: false),
      ]),
      isFalse,
    );
    expect(cp2PausedSamples([], toleranceMs: 300), isFalse);
  });
}
