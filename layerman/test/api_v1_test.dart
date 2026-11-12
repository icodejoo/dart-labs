import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

const _home = '/home';
const _profile = '/profile';
const _pattern = 'home';

/// 验证公共桶文件导出的类型化路由契约。
void main() {
  test('精确匹配接受相同路径', () {
    expect(const RouteMatcher.exact(_home).matches(_home), isTrue);
  });

  test('精确匹配拒绝前缀、空值和非字符串', () {
    const matcher = RouteMatcher.exact(_home);
    for (final route in [
      '$_home/child',
      null,
      1,
      [_home]
    ]) {
      expect(matcher.matches(route), isFalse);
    }
  });

  test('候选列表匹配接受任一成员', () {
    const matcher = RouteMatcher.anyOf([_home, _profile]);
    expect(matcher.matches(_home), isTrue);
    expect(matcher.matches(_profile), isTrue);
  });

  test('候选列表拒绝非成员、非字符串及空列表', () {
    const matcher = RouteMatcher.anyOf([_home]);
    for (final route in [
      _profile,
      null,
      1,
      [_home]
    ]) {
      expect(matcher.matches(route), isFalse);
    }
    expect(const RouteMatcher.anyOf([]).matches(_home), isFalse);
  });

  test('正则匹配使用 hasMatch 接受路径子串', () {
    final matcher = RouteMatcher.regex(RegExp(_pattern));
    expect(matcher.matches(_home), isTrue);
    expect(matcher.matches('$_home/child'), isTrue);
  });

  test('正则匹配拒绝不匹配路径、空值和非字符串', () {
    final matcher = RouteMatcher.regex(RegExp(_pattern));
    for (final route in [
      _profile,
      null,
      1,
      [_home]
    ]) {
      expect(matcher.matches(route), isFalse);
    }
  });
}
