import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/session_id.dart';

void main() {
  test('newMovaSessionId returns a non-empty string containing a separator', () {
    final id = newMovaSessionId();
    expect(id, isNotEmpty);
    expect(id.contains('-'), isTrue);
  });

  test('two consecutive calls never collide', () {
    expect(newMovaSessionId(), isNot(newMovaSessionId()));
  });

  test('MovaSessionIdFactory typedef accepts a plain no-arg function', () {
    String fixed() => 'x';
    final MovaSessionIdFactory factory = fixed;
    expect(factory(), 'x');
  });
}
