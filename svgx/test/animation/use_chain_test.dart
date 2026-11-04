import 'package:flutter_test/flutter_test.dart';

import 'pixel_test_utils.dart';

void main() {
  for (final target in [
    '<use id="b" href="#g"/>',
    '<symbol id="b"><use href="#g"/></symbol>',
  ]) {
    test('chained use draws $target', () async {
      final doc = parsePixelDoc(
        '<defs><g id="g"><rect width="50" height="50"/></g>$target<use id="a" href="#b" x="10"/></defs><use href="#a" x="10"/>',
      );
      final pixels = await renderAt(doc, Duration.zero);
      expect(alphaAt(pixels, 30, 25), 255);
      expect(alphaAt(pixels, 10, 25), 0);
    });
  }
  test('use target chains retain the depth limit', () async {
    final chain = [
      for (var i = 0; i < 11; i++) '<use id="u$i" href="#u${i + 1}"/>',
    ].join();
    final doc = parsePixelDoc(
      '<defs>$chain<rect id="u11" width="100" height="100"/></defs><use href="#u0"/>',
    );
    expect(alphaAt(await renderAt(doc, Duration.zero), 50, 50), 0);
  });
  test('use target chains cannot bypass whole-instance expansion budget', () {
    final defs = StringBuffer(
      '<defs><rect id="r" width="10" height="10"/><use id="u" href="#r"/>',
    );
    defs.write(
      '<g id="g">${List.filled(1000, '<use href="#u"/>').join()}</g></defs>',
    );
    final watch = Stopwatch()..start();
    final doc = parsePixelDoc(
      '$defs${List.filled(40, '<use href="#g"/>').join()}',
    );
    expect(doc.useExpansionTruncated, isTrue);
    // A whole outer instance costs 3002 nodes: 33 fit in the 100000 budget.
    expect(doc.root.children, hasLength(33));
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });
  test('chained use cycle terminates', () {
    final watch = Stopwatch()..start();
    final doc = parsePixelDoc(
      '<defs><use id="a" href="#b"/><use id="b" href="#a"/></defs><use href="#a"/>',
    );
    paintAt(doc, Duration.zero);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });
}
