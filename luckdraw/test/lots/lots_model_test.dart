import 'package:flutter_test/flutter_test.dart';

import '../support/lots_fixtures.dart';

/// 抽签配置的值语义与不可变副本契约。
void main() {
  test('lots models > copies preserve value equality and hash codes', () {
    final c = lotsFixture.copyWith();
    expect(c, lotsFixture);
    expect(c.hashCode, lotsFixture.hashCode);
    final stick = c.sticks[1];
    expect(stick.copyWith(), stick);
    expect(stick.copyWith().hashCode, stick.hashCode);
    expect(
        stick.copyWith(
            label: 'other',
            texts: [],
            images: [],
            fill: c.style.stickFill,
            weight: 2,
            disabled: true,
            painter: (_, __) {}),
        isNot(stick));
    final o = c.options;
    expect(o.copyWith(), o);
    expect(o.copyWith().hashCode, o.hashCode);
    expect(o.copyWith(revealOnSettle: false, maxShakeDeg: 5, visibleSticks: 2),
        isNot(o));
    final s = c.style;
    expect(s.copyWith(), s);
    expect(s.copyWith().hashCode, s.hashCode);
    expect(s.copyWith(fontFamily: 'Roboto', fontSize: 20), isNot(s));
    expect(c.copyWith(sticks: []), isNot(c));
    expect(
        c.copyWith(
            style: s.copyWith(fontSize: 30),
            options: o.copyWith(visibleSticks: 1)),
        isNot(c));
    expect(c == Object(), isFalse);
    expect(stick == Object(), isFalse);
    expect(o == Object(), isFalse);
    expect(s == Object(), isFalse);
  });
}
