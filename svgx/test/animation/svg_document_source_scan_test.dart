import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';

import 'async_parse_test_utils.dart';

/// Frozen pre-change regex and count oracle. / 冻结修改前的正则及计数参照。
final _legacyImageElement = RegExp(r'<(?:[^<>\s/:]+:)?image(?=[\s/>])');
const _lessThan = 0x3c;
const _asciiUpperA = 0x41;
const _asciiUpperZ = 0x5a;
const _asciiLowerA = 0x61;
const _asciiLowerZ = 0x7a;
const _seed = 20261105;
const _randomCases = 10000;
const _bmpLimit = 0x10000;
const _longRun = 20000;
const _hexRadix = 16;
const _lessThanText = '<';
const _imageName = 'image';
const _openImage = '<$_imageName';
const _imageElement = '$_openImage>';
const _prefixedImage = '<svg:$_imageName/>';
const _multiplePrefixImage = '<a:b:image>';
const _uppercaseImage = '<IMAGE>';
const _spacedImage = '< image>';
const _xlinkHref = '<xlink:href>';
const _samplesVariable = 'SVGX_CSS_SAMPLES';

int _legacyTagCount(String source) {
  final units = source.codeUnits;
  var count = 0;
  for (var i = 0; i + 1 < units.length; i++) {
    if (units[i] != _lessThan) continue;
    final next = units[i + 1];
    if ((next >= _asciiUpperA && next <= _asciiUpperZ) ||
        (next >= _asciiLowerA && next <= _asciiLowerZ)) {
      count++;
    }
  }
  return count;
}

/// Check full legacy counts even for images; only the new scan may stop early.
/// 即使含图片也校验公开旧入口的完整计数；仅新扫描允许提前结束。
void _expectLegacy(String source, {String? label}) {
  final scan = scanSourceForWorker(source);
  final reason = label ?? source;
  expect(
    scan.hasImageElement,
    _legacyImageElement.hasMatch(source),
    reason: reason,
  );
  final count = _legacyTagCount(source);
  expect(estimateDocumentParseNodeCount(source), count, reason: reason);
  if (!scan.hasImageElement) {
    expect(scan.tagCount, count, reason: reason);
  }
}

/// Read Dart literal bodies, joining adjacent literals and decoding escapes.
/// Interpolations remain source text; runtime-built SVGs are also checked below.
/// 读取 Dart 字符串体，合并相邻字面量并解码转义；插值保留源码形式，
/// 下方另行校验运行时构造的 SVG，外部素材始终只读。
Iterable<String> _dartStrings(String source) sync* {
  final tokens = RegExp(
    r"""//[^\r\n]*|/\*[\s\S]*?\*/|(r)?([']{3}[\s\S]*?[']{3}|["]{3}[\s\S]*?["]{3}|'(?:\\[\s\S]|[^'\\\r\n])*'|"(?:\\[\s\S]|[^"\\\r\n])*")""",
  );
  final escapes = RegExp(
    r'\\(u\{[\da-fA-F]+\}|u[\da-fA-F]{4}|x[\da-fA-F]{2}|[\s\S])',
  );
  const simpleEscapes = {
    'n': '\n',
    'r': '\r',
    't': '\t',
    'b': '\b',
    'f': '\f',
    'v': '\v',
  };
  var previousEnd = 0;
  var joined = StringBuffer();
  for (final token in tokens.allMatches(source)) {
    final quoted = token.group(2);
    if (quoted == null) continue;
    if (source.substring(previousEnd, token.start).trim().isNotEmpty) {
      if (joined.isNotEmpty) yield joined.toString();
      joined = StringBuffer();
    }
    final width = quoted.startsWith("'''") || quoted.startsWith('"""') ? 3 : 1;
    var body = quoted.substring(width, quoted.length - width);
    if (token.group(1) == null) {
      body = body.replaceAllMapped(escapes, (match) {
        final escape = match.group(1)!;
        if (escape.startsWith('u{')) {
          return String.fromCharCode(
            int.parse(escape.substring(2, escape.length - 1), radix: _hexRadix),
          );
        }
        if (escape.length > 1 &&
            (escape.startsWith('u') || escape.startsWith('x'))) {
          return String.fromCharCode(
            int.parse(escape.substring(1), radix: _hexRadix),
          );
        }
        return simpleEscapes[escape] ?? escape;
      });
    }
    // Also test fragments, so an earlier image cannot hide a later mismatch.
    // 也逐片段校验，避免靠前的图片掩盖后续匹配差异。
    yield body;
    joined.write(body);
    previousEnd = token.end;
  }
  if (joined.isNotEmpty) yield joined.toString();
}

void main() {
  test('image boundaries preserve the old case-sensitive regex', () {
    const cases = <String, bool>{
      '': false,
      _lessThanText: false,
      _openImage: false,
      _imageElement: true,
      '$_openImage/': true,
      '$_openImage ': true,
      '$_openImage\t': true,
      '$_openImage\r\n': true,
      '$_openImage\v': true,
      '$_openImage\f': true,
      '$_openImage\u00a0': true,
      '$_openImage\u2003': true,
      '$_openImage\ufeff': true,
      '$_openImage\u0085>': false,
      '$_openImage\u180e>': false,
      '$_openImage\u200b>': false,
      '$_openImage\u0000>': false,
      '$_openImage!>': false,
      '$_openImage=>': false,
      '$_openImage">': false,
      '${_openImage}X>': false,
      '<images>': false,
      _uppercaseImage: false,
      '<Image>': false,
      _spacedImage: false,
      '<\timage>': false,
      '</image>': false,
      '<?image>': false,
      '<!image>': false,
      '<:image>': false,
      '<svg:image>': true,
      _prefixedImage: true,
      '<svg:image': false,
      '<SVG:image >': true,
      '<svg:IMAGE>': false,
      _multiplePrefixImage: false,
      '<a::image>': false,
      _xlinkHref: false,
      '<image:x>': false,
      '<image:image>': true,
      '<a:imageX>': false,
      '<a: image>': false,
      '<a :image>': false,
      '<a/:image>': false,
      '<a>:image>': false,
      '<1:image>': true,
      '<é:image>': true,
      '<中:image>': true,
      '<😀:image>': true,
      '<\ud800:image>': true,
      '<\u0000:image>': true,
      '<\u0085:image>': true,
      '<\u00a0:image>': false,
      '<!:image>': true,
      '<":image>': true,
      '<<image>': true,
      '<a:b:<image/>': true,
      '<a<svg:image/>': true,
      '<!-- <image/> -->': true,
      '<![CDATA[<svg:image/>]]>': true,
      '<svg href="<image/>">': true,
      '<imageX/><svg:imageX/><g/>': false,
    };
    for (final entry in cases.entries) {
      expect(
        scanSourceForWorker(entry.key).hasImageElement,
        entry.value,
        reason: entry.key,
      );
      _expectLegacy(entry.key);
      for (var end = 0; end <= entry.key.length; end++) {
        final prefix = entry.key.substring(0, end);
        _expectLegacy(prefix);
        _expectLegacy('<g/>$prefix<Y/>');
      }
    }
  });

  test('every BMP character agrees as image delimiter and prefix', () {
    for (var code = 0; code < _bmpLimit; code++) {
      final char = String.fromCharCode(code);
      final label = 'U+${code.toRadixString(_hexRadix)}';
      _expectLegacy('$_openImage$char>', label: '$label delimiter');
      _expectLegacy('<$char:$_imageName>', label: '$label prefix');
    }
  });

  test('fixed-seed random strings agree with both frozen oracles', () {
    final random = Random(_seed);
    const alphabet =
        '<<<<<imageIMAGEabcXYZ \t\n\r\v\f:://>>!?\'"=012'
        '\u0085\u00a0\u2003\u2028\u2029\ufeffé中😀';
    const injections = [
      _imageElement,
      _prefixedImage,
      _multiplePrefixImage,
      '<imageX>',
      _uppercaseImage,
      _spacedImage,
      _openImage,
      _xlinkHref,
      '<<image/>',
    ];
    for (var n = 0; n < _randomCases; n++) {
      final source = String.fromCharCodes(
        List.generate(
          random.nextInt(257),
          (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ),
      );
      _expectLegacy(source, label: 'seed=$_seed case=$n');
      final split = random.nextInt(source.length + 1);
      final injected =
          '${source.substring(0, split)}'
          '${injections[random.nextInt(injections.length)]}'
          '${source.substring(split)}';
      _expectLegacy(injected, label: 'seed=$_seed injected=$n');
      _expectLegacy(
        injected.substring(0, random.nextInt(injected.length + 1)),
        label: 'seed=$_seed truncated=$n',
      );
    }
  });

  test('long rejected names and repeated less-than signs preserve counts', () {
    final prefix = List.filled(_longRun, 'p').join();
    final starts = List.filled(_longRun, _lessThanText).join();
    for (final source in [
      starts,
      '$starts$prefix',
      '<$prefix:$_imageName>',
      '<$prefix:b:$_imageName><g/>',
      '<$prefix<g/><Y/>',
      '<$prefix $_imageName><Z/>',
    ]) {
      _expectLegacy(source);
    }
  });

  test('image return is early while the public estimate remains complete', () {
    const source = '<g/>$_imageElement<later/><later/>';
    final scan = scanSourceForWorker(source);
    expect(scan.hasImageElement, isTrue);
    expect(scan.tagCount, 2);
    expect(estimateDocumentParseNodeCount(source), 4);
    _expectLegacy(source);
  });

  test('repository test SVG strings and runtime fixtures agree', () {
    var count = 0;
    final files = Directory('test').listSync(recursive: true).whereType<File>();
    for (final file in files) {
      if (file.path.endsWith('.svg')) {
        _expectLegacy(file.readAsStringSync(), label: file.path);
        count++;
      } else if (file.path.endsWith('.dart')) {
        for (final source in _dartStrings(file.readAsStringSync())) {
          if (!source.contains(_lessThanText)) continue;
          _expectLegacy(source, label: '${file.path}: $source');
          count++;
        }
      }
    }
    for (final source in [
      smallAsyncSvg,
      largeAsyncSvg(),
      largeAsyncSvg(extra: _imageElement),
      largeAsyncSvg(extra: _prefixedImage),
      invalidLargeAsyncSvg(),
    ]) {
      _expectLegacy(source);
    }
    expect(count, greaterThan(100));
    // ignore: avoid_print
    print('Repository literal/fragment comparisons / 仓库字面量及片段对照: $count');
  });

  final corpus = Platform.environment[_samplesVariable];
  test(
    'every external SVG agrees without copying the corpus',
    () {
      final files = Directory(corpus!)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.svg'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        _expectLegacy(file.readAsStringSync(), label: file.path);
      }
      // ignore: avoid_print
      print(
        'Read-only external SVG comparisons / 只读外部 SVG 对照: ${files.length}',
      );
    },
    skip: corpus == null
        ? 'Set $_samplesVariable to the external corpus.'
        : false,
  );
}
