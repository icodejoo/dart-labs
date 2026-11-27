import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart';

/// 每个 SVG 使用同一逻辑视口，分别以三组缩放和偏移渲染。
const _viewport = 56;

/// RGBA 样本的栅格边长，给放大后的图形留出透明边缘。
const _side = 96;

/// 每个像素的 RGBA 通道数。
const _channels = 4;

/// CSS Masking §2 将裁剪施加于分组合成结果，HEAD 则逐笔累积边缘覆盖率。
/// 该 HEAD 对照只接受栅格舍入级别的变化，沿用 2 个 8 位色阶的上限。
/// https://www.w3.org/TR/css-masking-1/#module-interactions
const _maxChannelDifference = 2;

/// 每个样本的容许差异仅限少量边缘像素。
const _maxChangedFraction = .005;

/// 非边缘像素只允许合成路径不同带来的 1 色阶舍入差。
const _maxInteriorDifference = 1;

/// 裁剪包住多笔透明度层的样本：HEAD 在层内逐笔裁剪、边缘覆盖率被重复累积，
/// 新实现按规范裁剪合成结果，边缘与 HEAD 必然不同，只核对非边缘像素；
/// 边缘的正确性由上方"重叠不透明绘制只覆盖一次"的独立用例保证。
const _groupClipSemanticsChanged = {'同组裁剪加透明度和半透明重叠', '两笔透明度层内嵌一笔透明度层'};

/// HEAD ef45b2a5 的逐路径裁剪基线，压缩存储预乘 RGBA。
const _baseline = 'test/fixtures/rust_clip_ef45b2a5.rgba.gz';

/// 样本以整数和非整数倍率、像素对齐和亚像素位置绘制。
const _transforms = [(1.0, 0.0, 0.0), (0.8, 0.25, 0.75), (1.5, 0.5, 0.125)];

/// 手绘场景和各场景须有内容的探针，用于校验基线确实画出了被测元素。
const _samples = <String, (String, int, int)>{
  '嵌套裁剪、未裁剪路径和相邻兄弟': (
    '''
    <defs>
      <clipPath id="outer"><circle cx="24" cy="24" r="21"/></clipPath>
      <clipPath id="inner"><path d="M3 10H44L32 42H12Z"/></clipPath>
      <clipPath id="sibling"><rect x="43" y="5" width="7" height="17"/></clipPath>
    </defs>
    <g clip-path="url(#outer)">
      <g clip-path="url(#inner)">
        <rect x="2" y="2" width="26" height="46" fill="#b32366"/>
        <rect x="28" y="2" width="24" height="46" fill="#148387"/>
      </g>
      <rect x="16" y="39" width="22" height="12" fill="#826022"/>
    </g>
    <g clip-path="url(#sibling)"><rect x="40" width="16" height="25" fill="#2566c8"/></g>
    <rect x="4" y="47" width="10" height="6" fill="#1b6c3a"/>
    ''',
    46,
    10,
  ),
  '同组裁剪加透明度和半透明重叠': (
    '''
    <defs><clipPath id="clip"><circle cx="27" cy="25" r="19"/></clipPath></defs>
    <g clip-path="url(#clip)" opacity=".65">
      <rect width="37" height="51" fill="#ad2839" fill-opacity=".7"/>
      <rect x="17" y="2" width="34" height="48" fill="#2243b6" fill-opacity=".6"/>
    </g>
    <rect x="42" y="45" width="10" height="8" fill="#f9c328"/>
    ''',
    28,
    24,
  ),
  '裁剪、最近遮罩和遮罩子列表': (
    '''
    <defs>
      <clipPath id="clip"><circle cx="28" cy="26" r="21"/></clipPath>
      <clipPath id="nested"><rect x="2" y="2" width="5" height="6"/></clipPath>
      <mask id="outer" maskUnits="userSpaceOnUse" x="0" y="0" width="56" height="56">
        <rect width="50" height="54" fill="white" fill-opacity=".3"/>
      </mask>
      <mask id="inner" maskUnits="userSpaceOnUse" x="0" y="0" width="56" height="56">
        <g clip-path="url(#nested)" opacity=".75">
          <rect x="13" y="7" width="29" height="42" fill="white"/>
        </g>
      </mask>
    </defs>
    <g clip-path="url(#clip)" mask="url(#outer)">
      <rect x="3" y="2" width="19" height="48" fill="#b7335c"/>
      <g mask="url(#inner)"><rect x="23" width="32" height="53" fill="#39bf83"/></g>
    </g>
    ''',
    32,
    25,
  ),
  '裁剪和最近的模糊': (
    '''
    <defs>
      <clipPath id="clip"><path d="M8 9L48 13L38 46L13 43Z"/></clipPath>
      <filter id="outer" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="3"/>
      </filter>
      <filter id="inner" x="-100%" y="-100%" width="300%" height="300%">
        <feGaussianBlur stdDeviation="1.4"/>
      </filter>
    </defs>
    <g clip-path="url(#clip)" filter="url(#outer)">
      <rect x="5" y="4" width="20" height="36" fill="#254fae"/>
      <g filter="url(#inner)"><rect x="28" y="20" width="23" height="29" fill="#a64f27"/></g>
    </g>
    ''',
    35,
    30,
  ),
  '图片与几何共享裁剪': (
    '''
    <defs><clipPath id="clip"><circle cx="28" cy="27" r="18"/></clipPath></defs>
    <g clip-path="url(#clip)">
      <image x="5" y="3" width="45" height="48" preserveAspectRatio="none" href="data:image/png;base64,IMAGE_DATA"/>
      <path d="M23 11H39V30H23Z" fill="#8039b2" fill-opacity=".6"/>
    </g>
    ''',
    16,
    25,
  ),
  'clipPath 自身引用另一个裁剪区域': (
    '''
    <defs>
      <clipPath id="limit"><rect x="16" y="7" width="35" height="29"/></clipPath>
      <clipPath id="outer" clip-path="url(#limit)">
        <circle cx="25" cy="26" r="18"/>
      </clipPath>
    </defs>
    <g clip-path="url(#outer)">
      <rect width="56" height="26" fill="#e27731"/>
      <rect y="26" width="56" height="30" fill="#297aa8"/>
    </g>
    ''',
    30,
    20,
  ),
  '包围盒、变换与奇偶规则': (
    '''
    <defs>
      <clipPath id="ring" clipPathUnits="objectBoundingBox"
          transform="translate(.09 .04)">
        <path clip-rule="evenodd" d="M0 0H1V1H0Z M.24 .22H.61V.66H.24Z"/>
      </clipPath>
    </defs>
    <g transform="translate(6 2) rotate(12 20 20)">
      <g clip-path="url(#ring)">
        <rect x="4" y="5" width="40" height="18" fill="#e27731"/>
        <rect x="4" y="23" width="40" height="22" fill="#297aa8"/>
      </g>
    </g>
    ''',
    18,
    14,
  ),
  '圆形与矩形裁剪下的单笔透明度层': (
    '''
    <defs>
      <clipPath id="circle"><circle cx="15" cy="23" r="12"/></clipPath>
      <clipPath id="rect"><rect x="32.5" y="7.3" width="16.5" height="27.8"/></clipPath>
      <linearGradient id="paint">
        <stop stop-color="#167ac3" stop-opacity=".45"/>
        <stop offset="1" stop-color="#fa7209" stop-opacity=".9"/>
      </linearGradient>
    </defs>
    <g clip-path="url(#circle)">
      <rect x="1.1" y="13.2" width="28.4" height="22.4" fill="url(#paint)" opacity=".65"/>
    </g>
    <g clip-path="url(#rect)" opacity=".55">
      <path d="M29 4L53 17L44 43L29 37Z" fill="#9d7254" fill-opacity=".66"/>
    </g>
    ''',
    42,
    23,
  ),
  '两笔透明度层内嵌一笔透明度层': (
    '''
    <defs><clipPath id="clip"><circle cx="28" cy="26" r="20"/></clipPath></defs>
    <g clip-path="url(#clip)">
      <g opacity=".57">
        <rect width="44" height="54" fill="#a14c28" fill-opacity=".7"/>
        <rect x="15.5" y="4" width="38" height="47" fill="#4d33bf" opacity=".64"/>
      </g>
    </g>
    ''',
    30,
    18,
  ),
  '裁剪场景维持无透明度层的图片绘制顺序': (
    '''
    <defs><clipPath id="clip"><circle cx="26" cy="24" r="19"/></clipPath></defs>
    <g clip-path="url(#clip)">
      <rect x="13" y="12" width="21" height="24" fill="#bb3311" fill-opacity=".7"/>
      <image x="5" y="3" width="45" height="48" preserveAspectRatio="none" href="data:image/png;base64,IMAGE_DATA"/>
    </g>
    ''',
    24,
    22,
  ),
};

/// 生成固定的青色 2×2 PNG，覆盖真实图片解码与绘制。
Future<String> _makeImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff249db5), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return base64Encode(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 通过真实 FFI 录制，再按指定的场景变换读取预乘 RGBA。
Future<Uint8List> _render(
  String svg,
  (double, double, double) transform,
) async {
  final info = await RustXvgPictureCache.instance.getOrRenderAsync(svg);
  final recorder = ui.PictureRecorder();
  final (scale, x, y) = transform;
  ui.Canvas(recorder)
    ..translate(x, y)
    ..scale(scale)
    ..drawPicture(info.picture);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_side, _side);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 用基线四邻域的 RGBA 跳变识别像素是否贴近边缘。
bool _atEdge(List<int> baseline, int start, int offset) {
  final pixel = offset ~/ _channels;
  final x = pixel % _side;
  final y = pixel ~/ _side;
  for (final neighbor in [
    if (x > 0) pixel - 1,
    if (x < _side - 1) pixel + 1,
    if (y > 0) pixel - _side,
    if (y < _side - 1) pixel + _side,
  ]) {
    for (var channel = 0; channel < _channels; channel++) {
      final delta =
          (baseline[start + offset + channel] -
                  baseline[start + neighbor * _channels + channel])
              .abs();
      if (delta > _maxChannelDifference) return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  tearDownAll(RustXvgPictureCache.instance.clear);

  test(
    'group clipping covers composited overlapping opaque draws once',
    () async {
      const width = 48;
      const top = '<rect width="$width" height="$width" fill="#2649bc"/>';
      const bottom = '<rect width="$width" height="$width" fill="#c95437"/>';

      /// 让上层矩形完全遮挡下层，圆形裁剪边缘穿过两笔的重叠区域。
      String scene(String content) =>
          '''
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$width">
  <defs><clipPath id="c"><circle cx="24" cy="24" r="17.25"/></clipPath></defs>
  <g clip-path="url(#c)" opacity=".5">$content</g>
</svg>
''';

      final single = await _render(scene(top), _transforms.first);
      final overlap = await _render(scene('$bottom$top'), _transforms.first);
      final alpha = [
        for (var i = _channels - 1; i < single.length; i += _channels)
          single[i],
      ];
      const halfAlpha = 128;
      expect(alpha, contains(halfAlpha));
      expect(alpha.any((value) => value > 0 && value < halfAlpha), isTrue);
      expect(overlap, orderedEquals(single));
    },
  );

  test('static clip replay matches HEAD RGBA at three transforms', () async {
    final baseline = gzip.decode(File(_baseline).readAsBytesSync());
    final png = await _makeImage();
    var maxDifference = 0;
    var changedPixels = 0;
    var offset = 0;
    final failures = <String>[];
    expect(
      baseline,
      hasLength(
        _samples.length * _transforms.length * _side * _side * _channels,
      ),
    );
    for (final entry in _samples.entries) {
      final (content, probeX, probeY) = entry.value;
      final svg =
          '<svg xmlns="http://www.w3.org/2000/svg" width="$_viewport" height="$_viewport">'
          '${content.replaceAll('IMAGE_DATA', png)}</svg>';
      for (final transform in _transforms) {
        final rgba = await _render(svg, transform);
        final (scale, x, y) = transform;
        final probe =
            ((probeY * scale + y).floor() * _side +
                (probeX * scale + x).floor()) *
            _channels;
        expect(rgba[probe + _channels - 1], greaterThan(0), reason: entry.key);
        var sampleMaximum = 0;
        var sampleChanged = 0;
        var interiorChanged = 0;
        var interiorMaximum = 0;
        for (var i = 0; i < rgba.length; i += _channels) {
          var pixelDifference = 0;
          for (var channel = 0; channel < _channels; channel++) {
            final difference =
                (rgba[i + channel] - baseline[offset + i + channel]).abs();
            if (difference > pixelDifference) pixelDifference = difference;
          }
          if (pixelDifference > sampleMaximum) sampleMaximum = pixelDifference;
          if (pixelDifference != 0) {
            sampleChanged++;
            if (!_atEdge(baseline, offset, i)) {
              interiorChanged++;
              if (pixelDifference > interiorMaximum) {
                interiorMaximum = pixelDifference;
              }
            }
          }
        }
        final reason =
            '${entry.key} $transform：$sampleChanged 像素（$interiorChanged 个非边缘，'
            '最大 $interiorMaximum），最大通道差 $sampleMaximum';
        // ignore: avoid_print
        print(reason);
        final edgesMayDiffer = _groupClipSemanticsChanged.contains(entry.key);
        if (interiorMaximum > _maxInteriorDifference ||
            (!edgesMayDiffer &&
                (sampleMaximum > _maxChannelDifference ||
                    sampleChanged / (_side * _side) > _maxChangedFraction))) {
          failures.add(reason);
        }
        if (sampleMaximum > maxDifference) maxDifference = sampleMaximum;
        changedPixels += sampleChanged;
        offset += rgba.length;
      }
    }
    // ignore: avoid_print
    print(
      'HEAD RGBA: $changedPixels changed pixels, maximum channel delta $maxDifference',
    );
    expect(failures, isEmpty);
    expect(
      _samples.keys,
      containsAll(_groupClipSemanticsChanged),
      reason: '放宽边缘的样本名必须与样本表一致',
    );
  });
}
