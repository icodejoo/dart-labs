import '../ad/fail.dart';
import '../model/ad.dart';
import '../options/ad_config.dart';
import 'timeline.dart';

/// 节点失败裁决；示例：`event.verdict == MovaNodeFailVerdict.failItem`。
enum MovaNodeFailVerdict {
  /// 重试当前节点。
  retryNode,

  /// 跳过当前广告。
  skipNode,

  /// 放弃同一插入点的广告 pod。
  abandonPod,

  /// 结束当前条目，等待宿主处理。
  failItem,

  /// 保留当前播放或交给引擎恢复。
  ignore,
}

/// 包内失败描述；广告策略还需要原始广告对象，不以节点身份代替素材。
class MovaNodeFailure {
  const MovaNodeFailure({
    required this.node,
    required this.kind,
    required this.attempt,
    required this.fatal,
    this.giveUp = false,
    this.error,
    this.adBreak,
  });
  final MovaNodeId node;
  final MovaAdFailKind kind;
  final int attempt;
  final bool fatal;
  final bool giveUp;
  final Object? error;
  final MovaAdBreak? adBreak;
}

/// 纯裁决：广告策略只调用一次，正片恢复期间由引擎负责。
MovaNodeFailVerdict movaArbitrate(
  MovaNodeFailure f, {
  required MovaAdConfig ads,
  required bool engineRecovering,
}) {
  if (f.node.kind == MovaNodeKind.content) {
    if (engineRecovering && !f.giveUp) return MovaNodeFailVerdict.ignore;
    return f.fatal || f.giveUp
        ? MovaNodeFailVerdict.failItem
        : MovaNodeFailVerdict.ignore;
  }
  if (engineRecovering &&
      !f.fatal &&
      !f.giveUp &&
      f.kind == MovaAdFailKind.playerError) {
    return MovaNodeFailVerdict.ignore;
  }
  return switch (ads.effectiveFailPolicy.onFailure(
    MovaAdFail(
      adBreak: f.adBreak!,
      kind: f.kind,
      attempt: f.attempt,
      error: f.error,
    ),
  )) {
    MovaAdFailAction.retry => MovaNodeFailVerdict.retryNode,
    MovaAdFailAction.skipBreak => MovaNodeFailVerdict.skipNode,
    MovaAdFailAction.abandonPod => MovaNodeFailVerdict.abandonPod,
  };
}
