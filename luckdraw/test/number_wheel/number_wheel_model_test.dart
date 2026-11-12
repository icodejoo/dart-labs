import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/number_wheel.dart';

import '../support/number_wheel_fixtures.dart';

/// 不可变配置的值语义与副本契约。
void main() {
  test('number wheel models > copies preserve value equality and hash codes',
      () {
    final c = numberWheelFixture.copyWith();
    expect(c, numberWheelFixture);
    expect(c.hashCode, numberWheelFixture.hashCode);
    final p = c.pockets[1];
    expect(p.copyWith(), p);
    expect(p.copyWith().hashCode, p.hashCode);
    expect(
        p.copyWith(
            number: 99,
            label: 'custom',
            fill: kNumberWheelDefaultPalette.first,
            weight: 2,
            disabled: true),
        isNot(p));
    final o = c.options;
    expect(o.copyWith(), o);
    expect(o.copyWith().hashCode, o.hashCode);
    expect(o.copyWith(offsetDegree: 10), isNot(o));
    final s = c.style;
    expect(s.copyWith(), s);
    expect(s.copyWith().hashCode, s.hashCode);
    expect(s.copyWith(fontFamily: 'Roboto', fontSize: 20), isNot(s));
    expect(c.copyWith(pockets: []), isNot(c));
    expect(
        c.copyWith(
            style: s.copyWith(fontSize: 30),
            options: o.copyWith(discSpeedRatio: 0.5)),
        isNot(c));
    expect(c == Object(), isFalse);
    expect(p == Object(), isFalse);
    expect(o == Object(), isFalse);
    expect(s == Object(), isFalse);
  });
}
