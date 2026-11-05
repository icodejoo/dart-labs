// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'support/fake_api.dart';
import 'package:mova/mova.dart';

void main() {
  test('C16 mini host accepts old and new names with identical object identity', () {
    final MovaMiniController mini = MovaMini();
    const child = SizedBox();
    final oldHost = MovaMiniHost(ctl: mini, child: child);
    final newHost = MovaMiniHost(mini: mini, child: child);
    expect(oldHost.mini, same(mini));
    expect(oldHost.ctl, same(newHost.mini));
    expect(newHost.ctl, same(mini));
    expect(oldHost.child, same(newHost.child));
    expect(() => MovaMiniHost(mini: mini, ctl: mini, child: child), throwsAssertionError);
    expect(() => MovaMiniHost(child: child), throwsAssertionError);
    mini.dispose();
  });

  test('C16 ad overlay legacy member and renamed types share the canonical factory', () async {
    MovaApi make() => FakeMovaApi();
    final MovaEngineFactory factory = make;
    final MovaSwapEngine api = MovaCutoverEngine(engineFactory: factory);
    final MovaAdController ads = MovaAds(api);
    final overlay = MovaAdOverlayComponent(ads);
    expect(overlay.ads, same(ads));
    expect(overlay.controller, same(overlay.ads));
    expect(overlay.name, 'adOverlay');
    expect(overlay.slot, MovaSlot.overlay);
    expect(api.active, isA<FakeMovaApi>());
    await ads.dispose();
    await api.dispose();
  });

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
