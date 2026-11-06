import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart' show RustLib;
import 'package:xvg/src/animation/smil_animation.dart';

import 'pixel_test_utils.dart';

const _dashoffset = 'stroke-dashoffset';
const _opacity = 'opacity';
const _fillOpacity = 'fill-opacity';
const _strokeOpacity = 'stroke-opacity';
const _strokeWidth = 'stroke-width';
const _basePath = 'M10 20L30 20';
const _targetPath = 'M10 20L50 20';
const _before = Duration(milliseconds: 200);
const _middle = Duration(milliseconds: 600);
const _after = Duration(seconds: 1);
const _black = 0xff000000;
const _red = 0xffff0000;
const _blue = 0xff0000ff;
const _white = 0xffffffff;
const _radius = 'r';
const _centerY = 'cy';
const _fill = 'fill';
const _stroke = 'stroke';
const _pathAttribute = 'd';
const _x2 = 'x2';
const _fx = 'fx';
const _offset = 'offset';
const _stopOpacity = 'stop-opacity';
const _invalid = 'bad';
const _numericTarget = '7';
const _numericBase = '15';
const _skewTarget = '30';
const _parentOpacity = 'opacity="0.2"';
const _radiusAttribute = 'r="8"';
const _cyAttribute = 'cy="30"';
const _redFillAttribute = 'fill="red"';
const _whiteTarget = 'to="#ffffff"';
const _start = Duration(milliseconds: 400);
const _tolerance = 1e-9;
const _opaqueAlpha = 200;

/// Shared timing keeps the assertions focused on value resolution.
/// 共用时序，让断言聚焦基础值解析。
String _animate(
  String attribute, {
  String value = 'to="0"',
  bool freeze = true,
}) =>
    '<animate attributeName="$attribute" $value begin="0.4s" dur="0.4s" '
    '${freeze ? 'fill="freeze"' : ''}/>';

void main() {
  setUpAll(() async => RustLib.init());

  final numericCases = <(String, String, String, double)>[
    (_dashoffset, 'stroke-dashoffset="24"', '', 24),
    (_dashoffset, '', 'stroke-dashoffset="18"', 18),
    (_dashoffset, '', '', 0),
    (
      _dashoffset,
      'stroke-dashoffset="24" style="stroke-dashoffset:12px"',
      '',
      12,
    ),
    (_dashoffset, '', 'style="stroke-dashoffset:16px"', 16),
    (_strokeWidth, '', 'stroke-width="3px"', 3),
    (_strokeWidth, '', '', 1),
    (_fillOpacity, 'fill-opacity="0.2"', '', 0.2),
    (_fillOpacity, '', 'fill-opacity="0.4"', 0.4),
    (_fillOpacity, '', '', 1),
    (_strokeOpacity, '', 'stroke-opacity="0.3"', 0.3),
    (_strokeOpacity, '', '', 1),
    (_opacity, 'opacity="0.6"', _parentOpacity, 0.6),
    (_opacity, '', _parentOpacity, 1),
    (_opacity, '', '', 1),
    (_radius, _radiusAttribute, '', 8),
    (_radius, '', _radiusAttribute, 0),
    (_centerY, _cyAttribute, '', 30),
    (_centerY, '', _cyAttribute, 0),
    ('cx', '', '', 0),
    ('x', '', '', 0),
    ('y', '', '', 0),
    ('width', '', '', 0),
    ('height', '', '', 0),
    (_fillOpacity, 'fill-opacity="2"', '', 1),
    (_dashoffset, 'stroke-dashoffset="invalid"', 'stroke-dashoffset="9"', 9),
  ];
  for (var i = 0; i < numericCases.length; i++) {
    final (attribute, own, ancestor, base) = numericCases[i];
    test('numeric to-only $i: $attribute resolves base and timing', () {
      final document = parsePixelDoc(
        '<g $ancestor><circle $own>${_animate(attribute)}</circle></g>',
      );
      final animation = document.timelines.single as SmilAnimation;
      expect(animation.values, [base, 0]);
      expect(animation.begin, _start);
      expect(animation.fillFreeze, isTrue);
      expect(animation.sample(_before), isNull);
      expect(animation.sample(_before) ?? base, base);
      expect(animation.sample(_middle), closeTo(base / 2, _tolerance));
      expect(animation.sample(_after), 0);
    });
  }

  test('nearest ancestor and CSS cascade supply the static base', () {
    final document = parsePixelDoc('''
      <style>g { stroke-dashoffset: 22 } .target { stroke-dashoffset: 14 }</style>
      <g stroke-dashoffset="30"><g style="stroke-dashoffset:18">
        <path class="target" stroke-dashoffset="26" d="$_basePath">
          ${_animate(_dashoffset)}
        </path>
        <path d="$_basePath">${_animate(_dashoffset)}</path>
      </g></g>
    ''');
    expect(document.timelines.cast<SmilAnimation>().map((a) => a.values), [
      [14, 0],
      [18, 0],
    ]);
  });

  test('use instances inherit their own wrapper base', () {
    final document = parsePixelDoc('''
      <defs><path id="shape" d="$_basePath">${_animate(_dashoffset)}</path></defs>
      <use href="#shape" stroke-dashoffset="12"/>
      <use href="#shape" stroke-dashoffset="20"/>
    ''');
    expect(document.timelines.cast<SmilAnimation>().map((a) => a.values), [
      [12, 0],
      [20, 0],
    ]);
  });

  test('rect radius shorthand and text defaults follow the painter', () {
    final document = parsePixelDoc('''
      <rect ry="4">${_animate('rx')}</rect>
      <text>${_animate('font-size')}</text>
    ''');
    expect(document.timelines.cast<SmilAnimation>().map((a) => a.values), [
      [4, 0],
      [16, 0],
    ]);
  });

  test('remove returns numeric control to the static base', () {
    final document = parsePixelDoc(
      '<path stroke-dashoffset="24" d="$_basePath">'
      '${_animate(_dashoffset, freeze: false)}</path>',
    );
    final animation = document.timelines.single as SmilAnimation;
    expect(animation.sample(_middle), 12);
    expect(animation.sample(_after), isNull);
    expect(animation.sample(_after) ?? 24, 24);
  });

  test('path to-only uses own d and keeps morph timing', () {
    final document = parsePixelDoc(
      '<path d="$_basePath">${_animate(_pathAttribute, value: 'to="$_targetPath"')}</path>',
    );
    final animation = document.timelines.single as SmilPathAnimation;
    expect(animation.frames, [_basePath, _targetPath]);
    expect(animation.interpolates, isTrue);
    expect(animation.sample(_before), isNull);
    expect(animation.sample(_middle), 0.5);
    expect(animation.sample(_after), 1);
    expect(animation.morph!.frames.first, [10, 20, 30, 20]);
    expect(animation.morph!.frames.last, [10, 20, 50, 20]);
  });

  test('path without own d is dropped even when an ancestor declares d', () {
    final document = parsePixelDoc(
      '<g d="$_basePath"><path>'
      '${_animate(_pathAttribute, value: 'to="$_targetPath"')}</path></g>',
    );
    expect(document.timelines, isEmpty);
  });

  final colors = <(String, String, String, int?)>[
    (_fill, '', '', _black),
    (_fill, _redFillAttribute, '', _red),
    (_fill, '', 'fill="blue"', _blue),
    (_fill, 'fill="blue" style="fill:red"', '', _red),
    (_stroke, '', 'style="stroke:blue"', _blue),
    (_stroke, '', '', null),
    (_fill, 'fill="none"', _redFillAttribute, null),
    (_stroke, 'stroke="currentColor"', '', null),
    (_fill, 'fill="url(#paint)"', '', null),
  ];
  for (var i = 0; i < colors.length; i++) {
    final (attribute, own, ancestor, base) = colors[i];
    test(
      'color to-only $i resolves literal paints or drops unresolved ones',
      () {
        final document = parsePixelDoc(
          '<g $ancestor><path $own d="$_basePath">'
          '${_animate(attribute, value: _whiteTarget)}</path></g>',
        );
        if (base == null) {
          expect(document.timelines, isEmpty);
        } else {
          final animation = document.timelines.single as SmilColorAnimation;
          expect(animation.values, [base, _white]);
          expect(animation.sample(_before), isNull);
          expect(animation.sample(_after), _white);
        }
      },
    );
  }

  for (final (type, target, base) in <(String, String, List<double>)>[
    ('translate', '10 20', [0, 0, 0]),
    ('scale', '3 5', [1, 1, 0]),
    ('rotate', '90 10 20', [0, 0, 0]),
    ('skewX', _skewTarget, [0, 0, 0]),
    ('skewY', _skewTarget, [0, 0, 0]),
  ]) {
    test('transform to-only $type approximates base with identity', () {
      final document = parsePixelDoc(
        '<g transform="translate(8 9)"><animateTransform type="$type" '
        'to="$target" dur="1s" fill="freeze"/></g>',
      );
      final animation = document.timelines.single as SmilTransformAnimation;
      expect(animation.values.first, base);
      final middle = animation.sample(const Duration(milliseconds: 500))!;
      for (var i = 0; i < base.length; i++) {
        expect(middle[i], (base[i] + animation.values.last[i]) / 2);
      }
    });
  }

  test('values and from/to retain precedence in all changed channels', () {
    for (final specification in [
      'values="3;7" from="9" to="11"',
      'from="3" to="7"',
    ]) {
      final document = parsePixelDoc(
        '<circle r="15">${_animate(_radius, value: specification)}</circle>',
      );
      expect((document.timelines.single as SmilAnimation).values, [3, 7]);
    }
    expect(
      parseSmilValues(
        values: _invalid,
        from: '3',
        to: _numericTarget,
        underlying: _numericBase,
      ),
      isNull,
    );
    expect(
      parseSmilValues(
        from: _invalid,
        to: _numericTarget,
        underlying: _numericBase,
      ),
      isNull,
    );
    expect(
      parseSmilPathValues(
        from: _basePath,
        to: _targetPath,
        underlying: _invalid,
      ),
      [_basePath, _targetPath],
    );
  });

  test(
    'syncbase and element identities remain attached to to-only timelines',
    () {
      final document = parsePixelDoc('''
      <circle r="8">
        <animate id="first" attributeName="r" to="4" dur="0.4s"/>
        <animate id="second" attributeName="r" to="0" begin="first.end" dur="0.4s"/>
      </circle>
    ''');
      final animations = document.timelines.cast<SmilAnimation>().toList();
      expect(animations.map((a) => a.elementId), ['first', 'second']);
      expect(animations.last.values, [8, 0]);
      expect(animations.last.begin, _start);
      expect(animations.last.sample(_middle), closeTo(4, _tolerance));
    },
  );

  test('legacy colour/path/transform keyframes override static bases', () {
    for (final useValues in [true, false]) {
      final colorSpec = useValues
          ? 'values="#ff0000;#0000ff" from="#ffffff" to="#000000"'
          : 'from="#ff0000" to="#0000ff"';
      final pathSpec = useValues
          ? 'values="$_basePath;$_targetPath" from="M0 0" to="M1 1"'
          : 'from="$_basePath" to="$_targetPath"';
      final transformSpec = useValues
          ? 'values="2 4;6 8" from="20 40" to="60 80"'
          : 'from="2 4" to="6 8"';
      final document = parsePixelDoc('''
        <path d="M90 90" fill="#ffffff">
          ${_animate(_fill, value: colorSpec)}
          ${_animate(_pathAttribute, value: pathSpec)}
          <animateTransform type="translate" $transformSpec dur="1s"/>
        </path>
      ''');
      expect(document.timelines.whereType<SmilColorAnimation>().single.values, [
        _red,
        _blue,
      ]);
      expect(document.timelines.whereType<SmilPathAnimation>().single.frames, [
        _basePath,
        _targetPath,
      ]);
      expect(
        document.timelines.whereType<SmilTransformAnimation>().single.values,
        [
          [2, 4, 0],
          [6, 8, 0],
        ],
      );
    }
  });

  test(
    'gradient and stop to-only bases keep existing defaults and href values',
    () {
      final document = parsePixelDoc('''
      <defs>
        <linearGradient id="template" x2="75%"><stop/></linearGradient>
        <linearGradient id="linear" href="#template">
          ${_animate(_x2)}
        </linearGradient>
        <radialGradient id="radial" cx="30%">
          ${_animate(_fx)}
          ${_animate(_radius)}
          <stop offset="25%" stop-opacity="0.6">
            ${_animate(_offset)}
            ${_animate(_stopOpacity)}
            ${_animate('stop-color', value: _whiteTarget)}
          </stop>
        </radialGradient>
      </defs>
    ''');
      final numeric = document.timelines.whereType<SmilAnimation>().toList();
      final starts = {for (final a in numeric) a.attributeName: a.values.first};
      expect(starts, {
        _x2: 0.75,
        _fx: 0.3,
        _radius: 0.5,
        _offset: 0.25,
        _stopOpacity: 0.6,
      });
      expect(document.timelines.whereType<SmilColorAnimation>().single.values, [
        _black,
        _white,
      ]);
    },
  );

  test('by-only and from/by stay unsupported', () {
    final document = parsePixelDoc('''
      <circle r="8">
        <animate attributeName="r" by="2" dur="1s"/>
        <animate attributeName="r" from="1" by="2" dur="1s"/>
        <animateTransform type="translate" by="2 3" dur="1s"/>
      </circle>
    ''');
    expect(document.timelines, isEmpty);
  });

  for (final freeze in [true, false]) {
    test(
      'RGBA delayed second stroke ${freeze ? 'freezes visible' : 'returns hidden'}',
      () async {
        final document = parsePixelDoc('''
        <g fill="none" stroke="#000000" stroke-width="4" stroke-dasharray="60">
          <path d="M20 25H80"><animate attributeName="stroke-dashoffset"
            values="60;0" dur="0.4s" fill="freeze"/></path>
          <path d="M20 75H80" stroke-dashoffset="60">
            ${_animate(_dashoffset, freeze: freeze)}
          </path>
        </g>
      ''');
        final before = await renderAt(document, _before);
        final middle = await renderAt(document, _middle);
        final after = await renderAt(document, _after);
        expect(alphaAt(before, 30, 75), 0);
        expect(alphaAt(before, 30, 25), greaterThan(_opaqueAlpha));
        expect(alphaAt(middle, 30, 75), greaterThan(_opaqueAlpha));
        expect(alphaAt(middle, 70, 75), 0);
        expect(alphaAt(after, 30, 75), freeze ? greaterThan(_opaqueAlpha) : 0);
        expect(alphaAt(after, 70, 75), freeze ? greaterThan(_opaqueAlpha) : 0);
      },
    );
  }
}
