import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/timeline.dart';

/// 构造可区分身份的排期广告位。
MovaAdBreak ad(MovaAdBreakKind kind, int seconds) => MovaAdBreak(
  kind: kind,
  source: MovaSource('https://test/$kind/$seconds'),
  offset: Duration(seconds: seconds),
);

void main() {
  test('movaDueMidRoll 取最早到期且未播的中插', () {
    final a = ad(MovaAdBreakKind.mid, 30), b = ad(MovaAdBreakKind.mid, 60);
    expect(movaDueMidRoll([a, b], const Duration(seconds: 65), {a}), same(b));
    expect(movaDueMidRoll([a, b], const Duration(seconds: 20), {}), isNull);
  });
  test('movaNextPodMid 只串同一插入点', () {
    final a = ad(MovaAdBreakKind.mid, 30),
        b = ad(MovaAdBreakKind.mid, 30),
        c = ad(MovaAdBreakKind.mid, 90);
    expect(
      movaNextPodMid([a, b, c], {a}, const Duration(seconds: 31)),
      same(b),
    );
    expect(
      movaNextPodMid([a, b, c], {a, b}, const Duration(seconds: 31)),
      isNull,
    );
  });
  test('movaFirstOfKind 跳过已播', () {
    final a = ad(MovaAdBreakKind.pre, 0), b = ad(MovaAdBreakKind.pre, 0);
    expect(movaFirstOfKind([a, b], {a}, MovaAdBreakKind.pre), same(b));
  });
  test('movaPodMembers 中插只取同点、前后贴片取全部同类', () {
    final a = ad(MovaAdBreakKind.mid, 30),
        b = ad(MovaAdBreakKind.mid, 30),
        c = ad(MovaAdBreakKind.mid, 90);
    final pre = ad(MovaAdBreakKind.pre, 0), pre2 = ad(MovaAdBreakKind.pre, 0);
    final post = ad(MovaAdBreakKind.post, 0),
        post2 = ad(MovaAdBreakKind.post, 0);
    final all = [a, b, c, pre, pre2, post, post2];
    expect(movaPodMembers(all, a, const Duration(seconds: 31)), [a, b]);
    expect(movaPodMembers(all, pre, Duration.zero), [pre, pre2]);
    expect(movaPodMembers(all, post, Duration.zero), [post, post2]);
  });
  test('movaFirstWhere 无匹配返回 null', () {
    expect(movaFirstWhere([1, 2], (n) => n > 2), isNull);
    expect(movaFirstWhere([1, 2], (n) => n > 1), 2);
  });
}
