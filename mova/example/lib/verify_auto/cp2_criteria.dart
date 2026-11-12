/// Pure reducers for real native readbacks. Missing samples never prove playback.
/// First-frame slot clock, frozen only by observed playing edges. The caller
/// scopes records to one iteration/source; commands and media time are not edges.
int? cp2SlotActiveUs(
  Iterable<Map<String, Object?>> records,
  String uri, {
  int? untilUs,
}) {
  final rows = records.toList();
  final frames = rows
      .where(
        (r) =>
            r['kind'] == 'EVENT' &&
            r['event'] == 'MovaFirstFrame' &&
            r['uriAtEvent'] == uri,
      )
      .toList();
  final completed = cp2AdRecords(rows, uri, type: 'completed').toList();
  if (frames.length != 1 || (untilUs == null && completed.length != 1)) {
    return null;
  }
  final frame = frames.single;
  final start = frame['us'];
  final end = untilUs ?? completed.single['us'];
  final initial = frame['state'];
  if (start is! int ||
      end is! int ||
      end < start ||
      initial is! Map ||
      initial['playing'] is! bool) {
    return null;
  }
  var playing = initial['playing'] as bool;
  var previous = start;
  var active = 0;
  var held = false;
  var resumed = false;
  for (final row in rows.skip(rows.indexOf(frame) + 1)) {
    final us = row['us'];
    if (us is! int || us < previous) return null;
    if (us > end) break;
    if (row['kind'] == 'EVENT' &&
        row['event'] == 'MovaFirstFrame' &&
        row['uriAtEvent'] != uri) {
      return null;
    }
    if (row['kind'] != 'STATE') continue;
    final state = row['state'];
    if (state is! Map || state['playing'] is! bool) return null;
    if (playing) active += us - previous;
    previous = us;
    if (playing && state['playing'] == false) held = true;
    if (held && !playing && state['playing'] == true) resumed = true;
    playing = state['playing'] as bool;
  }
  if (untilUs == null && (!held || !resumed)) return null;
  return active + (playing ? end - previous : 0);
}

bool cp2NativeSamples(List<Map<String, dynamic>> rows) =>
    rows.length >= 2 &&
    rows.every(
      (r) =>
          r['path'] is String &&
          (r['path'] as String).isNotEmpty &&
          r['timePosMs'] is int &&
          (r['pause'] == 'yes' || r['pause'] == 'no') &&
          r['state'] is Map,
    );

bool cp2PausedSamples(
  List<Map<String, dynamic>> rows, {
  String? path,
  int toleranceMs = 300,
}) =>
    cp2NativeSamples(rows) &&
    rows.every(
      (r) =>
          r['pause'] == 'yes' &&
          (r['state'] as Map)['playing'] == false &&
          (path == null || r['path'] == path),
    ) &&
    rows.map((r) => r['timePosMs'] as int).reduce((a, b) => a > b ? a : b) -
            rows
                .map((r) => r['timePosMs'] as int)
                .reduce((a, b) => a < b ? a : b) <=
        toleranceMs;

bool cp2AudioSamples(List<Map<String, dynamic>> rows, {required bool intent}) =>
    cp2NativeSamples(rows) &&
    rows.every(
      (r) =>
          r['path'] == rows.first['path'] &&
          r['pause'] == 'no' &&
          r['mute'] == 'no' &&
          r['audioCodec'] is String &&
          (r['audioCodec'] as String).isNotEmpty &&
          r['audioCodec'] != 'no' &&
          (double.tryParse('${r['nativeVolume']}') ?? 0) > 0 &&
          (r['state'] as Map)['playing'] == true &&
          (r['state'] as Map)['intent'] == intent,
    ) &&
    List.generate(
      rows.length - 1,
      (i) => (rows[i + 1]['timePosMs'] as int) > (rows[i]['timePosMs'] as int),
    ).every((v) => v);

/// Select the emitted ad callback by its event identity and scheduled source.
/// The legacy APK overwrote the envelope kind with pre/mid/post.
Iterable<Map<String, Object?>> cp2AdRecords(
  Iterable<Map<String, Object?>> records,
  String uri, {
  String? type,
}) => records.where(
  (r) =>
      r['event'] == 'MovaAdEvent' &&
      r['uri'] == uri &&
      (type == null || r['type'] == type),
);

/// Natural playback must complete exactly one exposure, with no failure/skip
/// or duplicate callback. Only a delayed/waiting mid-roll enters pending.
bool cp2AdLifecycle(
  Iterable<Map<String, Object?>> records,
  String uri, {
  required String kind,
  required bool pending,
}) {
  final rows = cp2AdRecords(records, uri).toList();
  final expected = pending
      ? ['pending', 'started', 'completed']
      : ['started', 'completed'];
  return rows.length == expected.length &&
      List.generate(
        expected.length,
        (i) =>
            rows[i]['type'] == expected[i] &&
            (rows[i]['adKind'] ?? rows[i]['kind']) == kind,
      ).every((v) => v);
}
