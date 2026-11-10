import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/parity/codec.dart';
import '../../tool/parity/generate.dart';

/// 自测中的有效 SHA-256 形状。
const String _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// 自测中的固定用例编号。
const String _id = 'w01';

/// 自测中的 PNG data URL 前缀。
const String _pngPrefix = 'data:image/png;base64,';

/// 返回最小合法的运动配置。
Map<String, Object?> _spec({String game = 'wheel'}) => {
      'id': _id,
      'game': game,
      'frames': 3,
      'config': {
        'slots': [<String, Object?>{}, <String, Object?>{}, <String, Object?>{}]
      },
      'script': [
        {'frame': 0, 'action': 'play'},
        {'frame': 1, 'action': 'stop', 'index': 2}
      ],
      'keyframes': [0, 'settled'],
    };

/// 返回三帧确定性基线；老虎机故意保留负值和跳零。
Map<String, Object?> _result({String game = 'wheel'}) => {
      'id': _id,
      'game': game,
      'frameMs': kParityFrameMs,
      'frames': [
        for (var i = 0; i < 3; i++)
          {
            'frame': i,
            'timeMs': i * kParityFrameMs,
            'step': i == 0 ? 1 : 0,
            'rotateDeg': i,
            'currIndex': i + 0.1,
            'scroll': [i == 0 ? -3 : 0, i, i],
          }
      ],
      'settledFrame': 1,
      'events': [
        {'frame': 2, 'resultIndex': 2}
      ],
      'keyframes': {
        '0': {'frame': 0},
        'settled': {'frame': 1}
      },
    };

/// 返回具有完整来源字段的最小清单。
Map<String, Object?> _manifest() => {
      'upstream': kParityUpstream,
      'referenceCommit': kParityReferenceCommit,
      'tarballSha256': kParityTarballSha256,
      'frameMs': kParityFrameMs,
      'fontSha256': _hash,
      'chrome': '142.0.0.0',
      'generatedAt': '2026-11-10T00:00:00Z',
      'cases': {_id: _hash},
      'artifacts': {'$_id/frames.json': _hash},
    };

/// 生成器自测；不启动浏览器、不联网、不依赖玩法 Dart 实现。
void main() {
  group('parity generate', () {
    test('JSON codec agrees with SDK for nested values and escapes', () {
      final value = <String, Object?>{
        'ascii': 'A "quote" \\ slash /\n\t\r\b\f',
        'unicode': '中文😀',
        'values': [
          null,
          true,
          false,
          -1,
          1.25,
          1e-10,
          {'nested': <Object?>[]}
        ],
      };
      expect(jsonDecode(encodeParityJson(value)), value);
      expect(decodeParityJson(jsonEncode(value)), value);
      expect(decodeParityJson(r'"\u4e2d\u6587\uD83D\uDE00"'), value['unicode']);
      expect(decodeParityJson(' \n [0,-0,2e3] \t'), [0, 0, 2000]);
    });

    test('JSON codec rejects malformed documents and unsupported values', () {
      for (final source in [
        '',
        'true false',
        '[1,]',
        '{"a":1,"a":2}',
        '{"a" 1}',
        '01',
        '1e999',
        '"\\x"',
        '"\\uZZZZ"',
        '"\n"',
        '"unfinished',
        '[',
        '{',
        '{1:2}',
        'undefined',
        '"\\'
      ]) {
        expect(() => decodeParityJson(source), throwsFormatException,
            reason: source);
      }
      expect(() => encodeParityJson(double.nan), throwsFormatException);
      expect(() => encodeParityJson(Object()), throwsFormatException);
      expect(() => encodeParityJson({1: true}), throwsFormatException);
    });

    test('extracts DOM JSON without double decoding HTML entities', () {
      const value = {'text': '<&lt;>"\''};
      final escaped = jsonEncode(value)
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
      expect(
          parseHarnessDom('<html><pre id="out">$escaped</pre></html>'), value);
    });

    test('rejects missing pending and failed harness output', () {
      expect(
          () => parseHarnessDom('<pre>missing</pre>'), throwsFormatException);
      expect(() => parseHarnessDom('<pre id="out">PENDING</pre>'),
          throwsFormatException);
      expect(
          () => parseHarnessDom('<pre id="out">{"error":"font missing"}</pre>'),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('font missing'))));
    });

    test('decodes PNG data URLs and rejects malformed payloads', () {
      for (var extra = 0; extra < 3; extra++) {
        final bytes = [...kParityPngSignature, ...List<int>.filled(extra, 255)];
        expect(decodeParityPng('$_pngPrefix${base64Encode(bytes)}'), bytes);
      }
      for (final value in [
        'data:text/plain;base64,AAAA',
        '$_pngPrefix@@@@',
        '${_pngPrefix}AA==',
        '${_pngPrefix}AAA',
        '${_pngPrefix}iVBORw0KGgp=',
        '${_pngPrefix}iVBORw0KGgo==='
      ]) {
        expect(() => decodeParityPng(value), throwsFormatException,
            reason: value);
      }
      expect(hasParityPngSignature([]), isFalse);
    });

    test('validates complete deterministic frame streams', () {
      expect(validateParityFrames(_spec(), _result()), isEmpty);
      expect(validateParityFrames(_spec(game: 'grid'), _result(game: 'grid')),
          isEmpty);
    });

    test('rejects backwards non-finite and incomplete frame streams', () {
      final backwards = _result();
      final frames = backwards['frames']! as List<Object?>;
      parityObject(frames[2])['rotateDeg'] = -1;
      expect(validateParityFrames(_spec(), backwards),
          contains(contains('non-monotonic')));
      parityObject(frames[2])['rotateDeg'] = double.infinity;
      expect(validateParityFrames(_spec(), backwards), isNotEmpty);
      final wrongTime = _result();
      parityObject((wrongTime['frames']! as List<Object?>)[1])['timeMs'] = 17;
      expect(validateParityFrames(_spec(), wrongTime),
          contains(contains('frame/time')));
      for (final change in <Map<String, Object?>>[
        {'id': 'other'},
        {'frameMs': 17},
        {'frames': []},
        {'settledFrame': null},
        {'events': []},
        {'keyframes': {}},
      ]) {
        expect(validateParityFrames(_spec(), {..._result(), ...change}),
            isNotEmpty);
      }
    });

    test('preserves raw slot wraparound and deceleration reset', () {
      expect(validateParityFrames(_spec(game: 'slot'), _result(game: 'slot')),
          isEmpty);
      final invalid = _result(game: 'slot');
      parityObject((invalid['frames']! as List<Object?>)[0])['scroll'] = [
        double.nan
      ];
      expect(validateParityFrames(_spec(game: 'slot'), invalid),
          contains(contains('invalid scroll')));
      final cancelled = _spec(game: 'slot');
      parityObject((cancelled['script']! as List<Object?>)[1])['index'] = -1;
      expect(
          validateParityFrames(
              cancelled, {..._result(game: 'slot'), 'events': []}),
          isEmpty);
    });

    test('rejects changed cases missing artifacts and wrong provenance', () {
      final manifest = _manifest();
      const cases = {_id: _hash};
      const artifacts = {'$_id/frames.json': _hash};
      expect(
          parityManifestErrors(
              manifest: manifest, caseHashes: cases, artifactHashes: artifacts),
          isEmpty);
      expect(
          parityManifestErrors(
              manifest: manifest,
              caseHashes: {_id: 'changed'},
              artifactHashes: {}),
          allOf(
              contains(contains('cases:')), contains(contains('artifacts:'))));
      for (final key in [
        'upstream',
        'referenceCommit',
        'tarballSha256',
        'frameMs',
        'chrome',
        'fontSha256',
        'generatedAt'
      ]) {
        expect(
            parityManifestErrors(
                manifest: {...manifest, key: null},
                caseHashes: cases,
                artifactHashes: artifacts),
            isNotEmpty,
            reason: key);
      }
      expect(
          parityManifestErrors(
              manifest: manifest,
              caseHashes: {...cases, 'extra': _hash},
              artifactHashes: artifacts),
          contains(contains('extra')));
    });

    test('all sixteen baseline cases contain complete frames and keyframe PNGs',
        () {
      final manifest = parityObject(decodeParityJson(
          File('test/parity/baselines/MANIFEST.json').readAsStringSync()));
      expect(parityObject(manifest['cases']).keys,
          unorderedEquals(kParityCaseIds));
      expect(parityObject(manifest['artifacts']), hasLength(96));
      for (final id in kParityCaseIds) {
        final spec = parityObject(decodeParityJson(
            File('tool/parity/cases/$id.json').readAsStringSync()));
        final baseline = 'test/parity/baselines/$id';
        final result = parityObject(
            decodeParityJson(File('$baseline/frames.json').readAsStringSync()));
        expect(validateParityFrames(spec, result), isEmpty, reason: id);
        final frames = result['frames']! as List<Object?>;
        expect(frames, hasLength(420));
        expect(parityObject(frames.first)['timeMs'], 0);
        for (final keyframe in parityObject(result['keyframes']).entries) {
          final metadata = parityObject(keyframe.value);
          expect(metadata['file'], 'kf_${keyframe.key}.png');
          final bytes = File('$baseline/${metadata['file']}').readAsBytesSync();
          expect(hasParityPngSignature(bytes), isTrue,
              reason: '$id ${keyframe.key}');
          // PNG IHDR 中的实际像素尺寸应等于逻辑尺寸乘 DPR。
          /// 从 IHDR 的 [start] 位置读取一个大端尺寸。
          int dimension(int start) =>
              bytes.sublist(start, start + 4).fold(0, (n, b) => (n << 8) | b);
          final size = parityObject(spec['size']);
          expect(
              dimension(16), (size['width']! as num) * (spec['dpr']! as num));
          expect(
              dimension(20), (size['height']! as num) * (spec['dpr']! as num));
        }
        final events = result['events']! as List<Object?>;
        if (id == 'w06') expect(parityObject(events.single)['result'], isEmpty);
        if (id == 's04') expect(parityObject(events.single)['result'], isNull);
        if (id == 's05') expect(events, isEmpty);
        if (id == 'w02') expect(result['randomConsumed'], 2);
        if (id != 'w06' && id != 's05') {
          expect(parityObject(events.single)['frame'],
              (result['settledFrame']! as int) + 1);
        }
      }
    });
  });
}
