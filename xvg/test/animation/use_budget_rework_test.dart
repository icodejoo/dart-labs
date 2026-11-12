import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_dom.dart';

int _nodes(SvgNode n) => 1 + n.children.fold(0, (s, c) => s + _nodes(c));
int _animations(SvgNode n) =>
    n.animations.length + n.children.fold(0, (s, c) => s + _animations(c));

SvgDocument _bounded(String body) {
  final watch = Stopwatch()..start();
  final d = parseAnimatedSvgDocument(
    '<svg xmlns:xlink="http://www.w3.org/1999/xlink">$body</svg>',
  );
  watch.stop();
  expect(d.useExpansionTruncated, isTrue);
  expect(_nodes(d.root), lessThanOrEqualTo(100001));
  expect(watch.elapsedMilliseconds, lessThan(2000));
  return d;
}

void main() {
  test('href namespace collisions cannot bypass the use budget', () {
    final defs = StringBuffer('<defs><rect id="small"/><g id="g0"><rect/></g>');
    for (var i = 1; i <= 9; i++) {
      defs.write(
        '<g id="g$i">${List.filled(4, '<use href="#small" xlink:href="#g${i - 1}"/>').join()}</g>',
      );
    }
    _bounded('$defs</defs><use href="#small" xlink:href="#g9"/>');
  });

  test('xml:id collisions cannot bypass the use budget cycle estimate', () {
    String level(int k) => k == 0
        ? '<rect/>'
        : '<g id="a$k" xml:id="x$k">${List.filled(6, '<use href="#a$k"/>').join()}${level(k - 1)}</g>';
    _bounded('<defs>${level(7)}</defs><use href="#a7"/>');
  });

  test('animation elements share the use expansion budget', () {
    final animations = List.filled(
      50,
      '<animate attributeName="opacity" values="0;1" dur="1s"/>',
    ).join();
    final d = _bounded(
      '<defs><rect id="r">$animations</rect>'
      '<g id="g">${List.filled(100, '<use href="#r"/>').join()}</g></defs>'
      '${List.filled(20, '<use href="#g"/>').join()}',
    );
    expect(_nodes(d.root) + _animations(d.root), lessThanOrEqualTo(100001));
    // Every admitted outer instance remains whole: 100 animated rects.
    for (final instance in d.root.children) {
      expect(instance.children.single.children, hasLength(100));
      expect(_animations(instance), 5000);
    }
  });

  test('dangling use fan-out shares the use expansion budget', () {
    _bounded(
      '<defs><g id="y">${List.filled(2000, '<use href="#missing"/>').join()}</g>'
      '<g id="z">${List.filled(100, '<use href="#y"/>').join()}</g></defs>'
      '${List.filled(20, '<use href="#z"/>').join()}',
    );
  });

  test('dangling use units accumulate across admitted instances', () {
    final d = _bounded(
      '<defs><g id="g">${List.filled(2000, '<use href="#missing"/>').join()}</g></defs>'
      '${List.filled(50, '<use href="#g"/>').join()}',
    );
    expect(d.root.children, hasLength(49));
    expect(_nodes(d.root), 99);
  });

  test('unsupported child visits also consume expansion units', () {
    final d = _bounded(
      '<defs><g id="g">${List.filled(2000, '<unknown/>').join()}</g></defs>'
      '${List.filled(50, '<use href="#g"/>').join()}',
    );
    expect(d.root.children, hasLength(49));
    expect(_nodes(d.root), 99);
  });
}
