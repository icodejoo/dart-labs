import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/preview/net_probe.dart';

/// The default [MovaNetProbe]: treats wifi/ethernet/vpn as unmetered and a
/// mobile-only connection as metered.
///
/// Anything else — `none`, `other`, an empty result list, or a platform the
/// plugin cannot classify — is allowed, so desktops are never false-blocked
/// (DESIGN §11: "未知一律放行；桌面视为允许").
///
/// 默认的 [MovaNetProbe]：把 wifi/以太网/VPN 视为不计流量，把仅蜂窝的连接视为
/// 计流量。
///
/// 其余情况——`none`、`other`、空结果列表，或插件无法分类的平台——一律放行，
/// 避免误伤桌面端（DESIGN §11：「未知一律放行；桌面视为允许」）。
class ConnectivityNetProbe implements MovaNetProbe {
  /// Creates a probe over [connectivity], defaulting to a new `Connectivity()`.
  ///
  /// 基于 [connectivity] 创建探针；省略时新建一个 `Connectivity()`。
  ///
  /// - [connectivity]: injectable connectivity_plus facade / 可注入的
  ///   connectivity_plus 门面
  ConnectivityNetProbe({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// The connectivity_plus facade this probe reads from.
  ///
  /// 该探针读取的 connectivity_plus 门面。
  final Connectivity _connectivity;

  /// Classifies a connectivity_plus result list as unmetered (true) or
  /// metered (false).
  ///
  /// 把 connectivity_plus 的结果列表分类为不计流量（true）或计流量（false）。
  ///
  /// - [results]: the reported active connection types / 上报的当前连接类型
  ///
  /// Returns whether heavy traffic is acceptable.
  ///
  /// 返回是否可以接受重量级流量。
  static bool allowsHeavy(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet) ||
        results.contains(ConnectivityResult.vpn)) {
      return true;
    }
    if (results.contains(ConnectivityResult.mobile)) return false;
    return true;
  }

  @override
  Future<bool> allowHeavy() async => allowsHeavy(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.map(allowsHeavy);

  @override
  Future<void> dispose() async {}
}
