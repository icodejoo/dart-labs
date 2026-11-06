// 真实语料回归：解析 benchmark 自带的 399 个 Iconify 动画图标，断言
// `fill-opacity` 动画、`d` 路径变形、`<set>` 三类内容都被解析出来、数量对得上，
// 不会再被静默丢掉。

// 语料在 benchmark/bench_app 里，不是依赖包，只能用相对路径导入。
// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';

import '../../benchmark/bench_app/lib/anim_icons_real.dart';
import 'node_test_utils.dart';
import 'pixel_test_utils.dart';

/// 语料里图标总数。
const int _iconCount = 399;

// Official line-md@1.2.16 + eos-icons@1.2.4 counts pin corpus coverage, while
// per-icon comparisons below independently check that parsing loses no tracks.
// 官方 line-md@1.2.16 + eos-icons@1.2.4 统计固定语料覆盖范围；下方逐图标
// 独立比较源码与解析结果，保证动画轨道没有被丢弃。
/// 语料统计（对照源码得到）：作用于 `d` 的 `<animate>` 个数。
const int _animateD = 188;

/// 作用于 `d` 的 `<set>` 个数。
const int _setD = 32;

/// 作用于 `opacity` 的 `<set>` 个数。
const int _setOpacity = 104;

/// No fill-opacity sets in the official corpus; keep checking for their return.
/// 官方语料没有 fill-opacity set；保留统计以检测后续语料变化。
const int _setFillOpacity = 0;

/// 作用于 `fill-opacity` 的 `<animate>` 个数。
const int _animateFillOpacity = 180;

/// 含 `d` 动画（animate 或 set）的图标数。
const int _iconsWithD = 93;

/// 含 `fill-opacity` 动画（animate 或 set）的图标数。
const int _iconsWithFillOpacity = 140;

/// 匹配某标签作用于某属性的整条开标签。
RegExp _tagOn(String tag, String attribute) =>
    RegExp('<$tag\\b[^>]*attributeName="$attribute"');

final RegExp _animateOnD = _tagOn('animate', 'd');
final RegExp _setOnD = _tagOn('set', 'd');
final RegExp _animateOnFillOpacity = _tagOn('animate', 'fill-opacity');
final RegExp _setOnFillOpacity = _tagOn('set', 'fill-opacity');
final RegExp _animateOnOpacity = _tagOn('animate', 'opacity');
final RegExp _setOnOpacity = _tagOn('set', 'opacity');

int _count(RegExp pattern, String source) => pattern.allMatches(source).length;

/// 全部语料解析一次，各用例共用，不重复解析 399 份文档。
final List<SvgDocument> _docs = [
  for (final source in animIconsReal) parseAnimatedSvgDocument(source),
];

/// 一份文档里各类动画的解析结果数量。
class _Tally {
  /// 统计主树，以及 clipPath / mask 定义里的动画。
  _Tally(SvgDocument doc) {
    for (final root in [
      doc.root,
      ...doc.clipPaths.values,
      ...doc.masks.values,
    ]) {
      for (final node in walkNodes(root)) {
        for (final a in node.pathAnimations) {
          path++;
          if (a.morph != null) morphable++;
        }
        for (final a in node.animations) {
          if (a.attributeName == 'fill-opacity') fillOpacity++;
          if (a.attributeName == 'opacity') opacity++;
        }
      }
    }
  }

  /// 路径（`d`）动画条数。
  int path = 0;

  /// 其中形状兼容、真正会插值的条数。
  int morphable = 0;

  /// `fill-opacity` 数值动画条数。
  int fillOpacity = 0;

  /// `opacity` 数值动画条数。
  int opacity = 0;
}

void main() {
  test('语料规模符合预期', () {
    expect(animIconsReal, hasLength(_iconCount));
  });

  test('源码统计与常量一致（防语料被改动后静默失效）', () {
    final all = animIconsReal.join('\n');
    expect(_count(_animateOnD, all), _animateD);
    expect(_count(_setOnD, all), _setD);
    expect(_count(_setOnOpacity, all), _setOpacity);
    expect(_count(_setOnFillOpacity, all), _setFillOpacity);
    expect(_count(_animateOnFillOpacity, all), _animateFillOpacity);
    expect(
      animIconsReal.where(
        (s) => _animateOnD.hasMatch(s) || _setOnD.hasMatch(s),
      ),
      hasLength(_iconsWithD),
    );
    expect(
      animIconsReal.where(
        (s) =>
            _animateOnFillOpacity.hasMatch(s) || _setOnFillOpacity.hasMatch(s),
      ),
      hasLength(_iconsWithFillOpacity),
    );
  });

  test('逐图标：d / fill-opacity / opacity 动画数量与源码一致', () {
    var morphable = 0;
    for (var i = 0; i < animIconsReal.length; i++) {
      final source = animIconsReal[i];
      final tally = _Tally(_docs[i]);
      final expectedPath =
          _count(_animateOnD, source) + _count(_setOnD, source);
      final expectedFill =
          _count(_animateOnFillOpacity, source) +
          _count(_setOnFillOpacity, source);
      final expectedOpacity =
          _count(_animateOnOpacity, source) + _count(_setOnOpacity, source);

      // `<use>` 会把目标子树连同动画再解析一遍，所以带 `<use>` 的图标只要求
      // 不少于源码出现次数；其余图标必须严格相等。
      final matcher = source.contains('<use')
          ? (int n) => greaterThanOrEqualTo(n)
          : (int n) => equals(n);
      expect(tally.path, matcher(expectedPath), reason: 'icon #$i: d');
      expect(
        tally.fillOpacity,
        matcher(expectedFill),
        reason: 'icon #$i: fill-opacity',
      );
      expect(
        tally.opacity,
        matcher(expectedOpacity),
        reason: 'icon #$i: opacity',
      );
      if (!source.contains('<use')) morphable += tally.morphable;
    }
    // animate d 里至少有一部分能规范化为兼容形状（真正会插值）；set 恒为单帧。
    expect(morphable, greaterThan(0));
    expect(morphable, lessThanOrEqualTo(_animateD));
  });

  test('语料里 <set> 的属性分布与官方语料一致', () {
    final all = animIconsReal.join('\n');
    // The official corpus has only d/opacity sets. Check every set's attribute,
    // so a new property cannot hide behind an unchanged aggregate count.
    // 官方语料的 set 仅作用于 d/opacity；逐个检查属性分布，避免总数不变时
    // 新增属性被漏检。fill-opacity 仍由上方源码统计显式检查为零。
    final counts = <String?, int>{};
    for (final tag in RegExp(r'<set\b[^>]*>').allMatches(all)) {
      final attribute = RegExp(r'attributeName="([^"]+)"')
          .firstMatch(tag[0]!)
          ?.group(1);
      counts.update(attribute, (n) => n + 1, ifAbsent: () => 1);
    }
    expect(counts, {'d': _setD, 'opacity': _setOpacity});
  });

  test('含 d / set 的图标在多个时刻都能完整执行绘制逻辑（不抛异常）', () {
    const times = [
      Duration.zero,
      Duration(milliseconds: 300),
      Duration(milliseconds: 1200),
      Duration(seconds: 8),
    ];
    var painted = 0;
    for (var i = 0; i < animIconsReal.length; i++) {
      final source = animIconsReal[i];
      if (!_animateOnD.hasMatch(source) &&
          !_setOnD.hasMatch(source) &&
          !source.contains('<set')) {
        continue;
      }
      for (final time in times) {
        paintAt(_docs[i], time);
      }
      painted++;
    }
    expect(painted, greaterThan(40));
  });
}
