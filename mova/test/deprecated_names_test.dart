// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('deprecated old names still resolve to the renamed types', () {
    test('type aliases are the same types as the new names', () {
      expect(const MovaSwapConfig(), const MovaCutoverConfig());
      expect(const MovaStandbyConfig(), const MovaKeepAliveConfig());
      expect(MovaStandbyPhase.holding, MovaKeepAlivePhase.holding);
      expect(MovaStandbyMode.muted, MovaKeepAliveMode.muted);
      // A value typed with the old alias is assignable where the new type is expected.
      // 用旧别名声明的值可以赋给新类型。
      const MovaStandbyPhase oldTyped = MovaKeepAlivePhase.off;
      const MovaKeepAlivePhase newTyped = oldTyped;
      expect(newTyped, MovaKeepAlivePhase.off);
    });

    test('old members forward to the new ones', () {
      const state = MovaState(keepAlivePhase: MovaKeepAlivePhase.holding);
      expect(state.standby, MovaKeepAlivePhase.holding);
      expect(const MovaOpts().standby, const MovaOpts().keepAlive);
      expect(const MovaOpts().swap, const MovaOpts().cutover);
      expect(MovaHiddenMode.standby, MovaHiddenMode.keepAlive);
    });
  });
}
