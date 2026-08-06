/// When scrub-preview thumbnails are allowed to use the network.
///
/// 何时允许拖动预览缩略图走网络。
enum MovaPrevNet {
  /// Only on connections considered unmetered; the default.
  ///
  /// 仅在被视为不计流量的连接上启用；默认值。
  wifiOnly,

  /// On any connection.
  ///
  /// 任意连接下都启用。
  always,

  /// Never — disables networked thumbnail sources entirely.
  ///
  /// 永不启用——完全关闭需要联网的缩略图来源。
  never,
}

/// Reports whether the current connection is suitable for bandwidth-heavy,
/// non-essential traffic such as sprite sheets and frame extraction.
///
/// 判断当前连接是否适合承载雪碧图、抽帧这类"非必要且吃带宽"的流量。
abstract class MovaNetProbe {
  /// Whether heavy, optional traffic is currently acceptable.
  ///
  /// 当前是否可以接受重量级的可选流量。
  ///
  /// Returns true when heavy traffic is allowed.
  ///
  /// 允许重量级流量时返回 true。
  Future<bool> allowHeavy();

  /// Emits a new verdict whenever connectivity changes.
  ///
  /// 连通性变化时推送新的判定结果。
  Stream<bool> get changes;

  /// Releases any listeners this probe holds.
  ///
  /// 释放该探针持有的监听。
  Future<void> dispose();
}

/// A [MovaNetProbe] that always permits heavy traffic.
///
/// The core-layer default so a host that never wires a real probe still gets
/// working previews; the plugin-backed probe lives in
/// `lib/src/platform_impl/net_probe_impl.dart`.
///
/// 恒定允许重量级流量的 [MovaNetProbe]。
///
/// 作为 core 层默认值，让未接入真实探针的宿主也能用上预览；基于插件的探针放在
/// `lib/src/platform_impl/net_probe_impl.dart`。
class AlwaysAllowNetProbe implements MovaNetProbe {
  @override
  Future<bool> allowHeavy() async => true;

  @override
  Stream<bool> get changes => Stream<bool>.value(true);

  @override
  Future<void> dispose() async {}
}

/// Resolves [policy] against [probe] into a single allow/deny answer.
///
/// A probe that throws is treated as "allowed": a broken connectivity plugin
/// must degrade to a working preview, not silently disable the feature.
///
/// 把 [policy] 与 [probe] 归结为一个允许/拒绝的答案。
///
/// 探针抛异常时按"允许"处理：连通性插件坏掉只能导致预览照常工作，而不能悄悄
/// 把功能关掉。
///
/// - [policy]: the configured network policy / 配置的网络策略
/// - [probe]: the connectivity probe to consult under [MovaPrevNet.wifiOnly] /
///   在 [MovaPrevNet.wifiOnly] 下要咨询的连通性探针
///
/// Returns whether networked preview sources may run.
///
/// 返回是否允许运行需要联网的预览来源。
Future<bool> previewAllowedOn(MovaPrevNet policy, MovaNetProbe probe) async {
  switch (policy) {
    case MovaPrevNet.never:
      return false;
    case MovaPrevNet.always:
      return true;
    case MovaPrevNet.wifiOnly:
      try {
        return await probe.allowHeavy();
      } on Object {
        return true;
      }
  }
}
