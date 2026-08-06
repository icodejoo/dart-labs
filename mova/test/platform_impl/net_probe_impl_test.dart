import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/platform_impl/net_probe_impl.dart';

void main() {
  test('wifi, ethernet and vpn allow heavy traffic', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.wifi]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.ethernet]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.vpn]), isTrue);
  });

  test('a mobile-only connection blocks heavy traffic', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.mobile]), isFalse);
  });

  test('mobile alongside wifi still allows heavy traffic', () {
    expect(
      ConnectivityNetProbe.allowsHeavy([ConnectivityResult.mobile, ConnectivityResult.wifi]),
      isTrue,
    );
  });

  test('unknown, none and empty results allow rather than false-block desktop', () {
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.other]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy([ConnectivityResult.none]), isTrue);
    expect(ConnectivityNetProbe.allowsHeavy(const <ConnectivityResult>[]), isTrue);
  });
}
