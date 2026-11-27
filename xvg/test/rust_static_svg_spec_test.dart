import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';

/// Raster size for the inline SVGs. / 内联 SVG 的栅格尺寸。
const _side = 64;

/// Reads pixels from a native static Picture. / 从原生静态 Picture 读取像素。
Future<ByteData> _pixels(String body, {String? viewport}) async {
  final info = RustXvgPictureCache.instance.getOrRender(
    '<svg xmlns="http://www.w3.org/2000/svg" width="$_side" height="$_side" '
    '${viewport ?? ''}>$body</svg>',
  );
  final image = await info.picture.toImage(_side, _side);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
  }
}

/// Compares premultiplied RGBA with a solid interior pixel. / 比对不在抗锯齿边缘的预乘 RGBA 像素。
void _expectPixel(ByteData pixels, int x, int y, int rgba) {
  expect(pixels.getUint32((y * _side + x) * 4), rgba, reason: '($x, $y)');
}

/// Transparent premultiplied RGBA. / 透明预乘 RGBA。
const _clear = 0x00000000;

/// Opaque red premultiplied RGBA. / 不透明红色预乘 RGBA。
const _red = 0xff0000ff;

/// Opaque blue premultiplied RGBA. / 不透明蓝色预乘 RGBA。
const _blue = 0x0000ffff;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  test('stroke scales down with the viewBox', () async {
    final pixels = await _pixels(
      '<path d="M32 256H480" stroke="red" stroke-width="32"/>',
      viewport: 'viewBox="0 0 512 512"',
    );
    _expectPixel(pixels, 25, 24, _clear);
    _expectPixel(pixels, 25, 31, _red);
  });

  test(
    'one em uses the SVG image font size before scaling its stroke',
    () async {
      final info = RustXvgPictureCache.instance.getOrRender('''
      <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em"
           viewBox="0 0 24 24">
        <path d="M4 12H20" stroke="red" stroke-width="6"/>
      </svg>
    ''');
      final image = await info.picture.toImage(_side, _side);
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        _expectPixel(pixels, 12, 7, _red);
        _expectPixel(pixels, 12, 5, _clear);
        expect(info.size, const ui.Size(16, 16));
      } finally {
        image.dispose();
      }
    },
  );

  test('stroke scales in both local axes before shear and rotation', () async {
    final pixels = await _pixels('''
      <g transform="translate(44 6) rotate(90) skewX(20) scale(2 4)">
        <path d="M2 4H18" stroke="red" stroke-width="2"/>
      </g>
      <g transform="translate(8 46) rotate(10) scale(3)">
        <path d="M0 0H12" stroke="blue" stroke-width="2"/>
      </g>
    ''');
    _expectPixel(pixels, 25, 30, _red);
    _expectPixel(pixels, 23, 30, _clear);
    _expectPixel(pixels, 20, 50, _blue);
  });

  test('stroke cap occupies the specified round and square ends', () async {
    final pixels = await _pixels('''
      <path d="M12 12H44" stroke="red" stroke-width="8" stroke-linecap="round"/>
      <path d="M12 28H44" stroke="blue" stroke-width="8" stroke-linecap="square"/>
    ''');
    _expectPixel(pixels, 9, 12, _red);
    _expectPixel(pixels, 8, 25, _blue);
    _expectPixel(pixels, 7, 28, _clear);
  });

  test('stroke joins honor bevel, round and the miter limit', () async {
    final pixels = await _pixels('''
      <path d="M6 44L12 12L18 44" fill="none" stroke="red" stroke-width="8"
            stroke-linejoin="bevel"/>
      <path d="M25 44L31 12L37 44" fill="none" stroke="red" stroke-width="8"
            stroke-linejoin="round"/>
      <path d="M44 44L50 12L56 44" fill="none" stroke="red" stroke-width="8"
            stroke-miterlimit="1"/>
    ''');
    _expectPixel(pixels, 12, 9, _clear);
    _expectPixel(pixels, 31, 9, _red);
    _expectPixel(pixels, 50, 9, _clear);
  });

  test('dash offset and gaps are measured before an unequal scale', () async {
    final pixels = await _pixels('''
      <path transform="scale(2 1)" d="M4 12H28" stroke="red" stroke-width="4"
            stroke-dasharray="6 4" stroke-dashoffset="2"/>
      <path d="M8 28H56V52H8Z" fill="blue" stroke="red" stroke-width="4"
            stroke-dasharray="8 8"/>
    ''');
    _expectPixel(pixels, 12, 12, _red);
    _expectPixel(pixels, 19, 12, _clear);
    _expectPixel(pixels, 28, 12, _red);
    _expectPixel(pixels, 20, 28, _blue);
    _expectPixel(pixels, 20, 40, _blue);
  });

  test('zero-length round dashes render as separate dots', () async {
    final pixels = await _pixels('''
      <path d="M4 12H60" stroke="red" stroke-width="6"
            stroke-dasharray="0 8" stroke-linecap="round"/>
    ''');
    _expectPixel(pixels, 4, 12, _red);
    _expectPixel(pixels, 8, 12, _clear);
    _expectPixel(pixels, 12, 12, _red);
  });

  test('diagonal bbox and skewed gradients use their inverse affine', () async {
    final pixels = await _pixels('''
      <defs>
        <linearGradient id="bbox" x2="1" y2="1">
          <stop stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient>
        <linearGradient id="skew" gradientUnits="userSpaceOnUse"
                        x2="48" gradientTransform="matrix(1 0 1 1 -32 0)">
          <stop stop-color="black"/><stop offset="1" stop-color="white"/>
        </linearGradient>
      </defs>
      <rect width="48" height="16" fill="url(#bbox)"/>
      <rect y="32" width="48" height="24" fill="url(#skew)"/>
    ''');
    // Pixel centers give t = (12.5/48 + 12.5/16)/2 and (30.5-14.5)/48.
    expect(pixels.getUint8((12 * _side + 12) * 4), closeTo(133, 1));
    expect(pixels.getUint8((46 * _side + 30) * 4), closeTo(85, 1));
  });

  test(
    'hidden and collapsed leaves are skipped with visible child override',
    () async {
      final pixels = await _pixels('''
      <g visibility="hidden">
        <rect width="16" height="16" fill="red"/>
        <rect x="20" width="16" height="16" fill="blue" visibility="visible"/>
      </g>
      <rect x="40" width="16" height="16" fill="red" visibility="collapse"/>
    ''');
      _expectPixel(pixels, 8, 8, _clear);
      _expectPixel(pixels, 28, 8, _blue);
      _expectPixel(pixels, 48, 8, _clear);
    },
  );

  test(
    'multiply uses the clipped backdrop and isolation stops blending',
    () async {
      final pixels = await _pixels('''
      <defs><clipPath id="clip"><rect width="48" height="24"/></clipPath></defs>
      <rect width="64" height="64" fill="red"/>
      <rect width="60" height="40" fill="cyan" opacity=".5"
            clip-path="url(#clip)" style="mix-blend-mode:multiply"/>
      <g clip-path="url(#clip)">
        <rect x="32" width="28" height="24" fill="cyan" style="mix-blend-mode:multiply"/>
      </g>
      <g style="isolation:isolate">
        <rect y="32" width="48" height="24" fill="cyan" style="mix-blend-mode:multiply"/>
      </g>
    ''');
      // Edge and Flutter round half opacity in opposite directions.
      final pixel = pixels.getUint32((12 * _side + 24) * 4);
      expect(pixel >> 24, closeTo(127, 1));
      expect(pixel & 0x00ffffff, 0x000000ff);
      _expectPixel(pixels, 40, 12, 0x00ffffff);
      _expectPixel(pixels, 54, 12, _red);
      _expectPixel(pixels, 24, 36, 0x00ffffff);
    },
  );

  test('Gaussian blur is clipped to default and explicit filter regions', () async {
    const body = '''
      <defs>
        <filter id="default"><feGaussianBlur stdDeviation="4"/></filter>
        <filter id="explicit" filterUnits="userSpaceOnUse"
                x="36" y="18" width="12" height="14">
          <feGaussianBlur stdDeviation="4"/>
        </filter>
      </defs>
      <rect x="12" y="20" width="16" height="16" fill="red" filter="url(#default)"/>
      <rect x="36" y="20" width="16" height="16" fill="blue" filter="url(#explicit)"/>
    ''';
    final pixels = await _pixels(body);
    _expectPixel(pixels, 9, 27, _clear);
    _expectPixel(pixels, 49, 27, _clear);
    expect(pixels.getUint8((27 * _side + 12) * 4 + 3), greaterThan(100));
    expect(pixels.getUint8((27 * _side + 46) * 4 + 3), greaterThan(100));
    final bounds = RustXvgPictureCache.instance
        .getOrRender(
          '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">$body</svg>',
        )
        .contentBounds!;
    expect(bounds.left, closeTo(10.4, .001));
    expect(bounds.right, closeTo(48, .001));
    expect(bounds.bottom, closeTo(37.6, .001));
  });

  test('a CSS blur has no SVG filter region', () async {
    final pixels = await _pixels('''
      <rect x="28" y="24" width="8" height="16" fill="red" style="filter:blur(10px)"/>
    ''');
    expect(pixels.getUint8((32 * _side + 20) * 4 + 3), greaterThan(10));
  });

  test('bbox tile size does not scale user-space pattern content', () async {
    final pixels = await _pixels('''
      <defs><pattern id="tile" width=".5" height=".5">
        <rect width="5" height="6" fill="red"/>
      </pattern></defs>
      <rect x="12" y="16" width="24" height="32" fill="url(#tile)"/>
    ''');
    _expectPixel(pixels, 14, 18, _red);
    _expectPixel(pixels, 19, 18, _clear);
    _expectPixel(pixels, 26, 34, _red);
  });

  test(
    'bbox pattern content applies its bbox scale and child transform',
    () async {
      final pixels = await _pixels('''
      <defs><pattern id="tile" width=".5" height=".5" patternContentUnits="objectBoundingBox">
        <g transform="translate(.125 .125)"><rect width=".25" height=".25" fill="red"/></g>
      </pattern></defs>
      <rect x="12" y="16" width="24" height="32" fill="url(#tile)"/>
    ''');
      _expectPixel(pixels, 16, 22, _red);
      _expectPixel(pixels, 13, 18, _clear);
      _expectPixel(pixels, 28, 38, _red);
    },
  );

  test('pattern viewBox maps into its nonsquare bbox tile', () async {
    final pixels = await _pixels('''
      <defs><pattern id="tile" width=".5" height=".5" viewBox="0 0 8 8"
                     patternContentUnits="objectBoundingBox">
        <rect width="4" height="4" fill="blue"/>
      </pattern></defs>
      <rect x="12" y="16" width="24" height="32" fill="url(#tile)"/>
    ''');
    _expectPixel(pixels, 14, 20, _blue);
    _expectPixel(pixels, 14, 16, _clear);
    _expectPixel(pixels, 26, 36, _blue);
  });
}
