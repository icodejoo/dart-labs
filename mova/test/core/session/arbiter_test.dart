import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/arbiter.dart';
import 'session_test.dart' show pre;

MovaNodeFailure failure({
  bool content = false,
  bool fatal = true,
  bool giveUp = false,
  MovaAdFailKind kind = MovaAdFailKind.playerError,
}) => MovaNodeFailure(
  node: MovaNodeId(0, content ? MovaNodeKind.content : MovaNodeKind.pre, 0),
  kind: kind,
  attempt: 1,
  fatal: fatal,
  giveUp: giveUp,
  adBreak: content ? null : pre,
);

void main() {
  test('广告非终结失败恢复时忽略，关闭恢复时交广告策略', () {
    final f = failure(fatal: false);
    expect(
      movaArbitrate(f, ads: const MovaAdOpts(), movaRecovering: true),
      MovaNodeFailVerdict.ignore,
    );
    expect(
      movaArbitrate(f, ads: const MovaAdOpts(), movaRecovering: false),
      MovaNodeFailVerdict.skipNode,
    );
  });
  test('广告加载超时不等待播放器，重试和放弃 pod 均交宿主', () {
    final f = failure(fatal: false, kind: MovaAdFailKind.loadTimeout);
    expect(
      movaArbitrate(
        f,
        ads: const MovaAdOpts(failPolicy: MovaAdRetrySkip(maxRetries: 1)),
        movaRecovering: true,
      ),
      MovaNodeFailVerdict.retryNode,
    );
    expect(
      movaArbitrate(
        f,
        ads: const MovaAdOpts(failPolicy: MovaAdAbandonPod()),
        movaRecovering: true,
      ),
      MovaNodeFailVerdict.abandonPod,
    );
  });
  test('正片恢复中等待播放器 giveUp', () {
    expect(
      movaArbitrate(
        failure(content: true),
        ads: const MovaAdOpts(),
        movaRecovering: true,
      ),
      MovaNodeFailVerdict.ignore,
    );
    expect(
      movaArbitrate(
        failure(content: true, giveUp: true),
        ads: const MovaAdOpts(),
        movaRecovering: true,
      ),
      MovaNodeFailVerdict.failItem,
    );
  });
  test('正片终结错误仅在恢复关闭时失败，诊断不失败', () {
    expect(
      movaArbitrate(
        failure(content: true),
        ads: const MovaAdOpts(),
        movaRecovering: false,
      ),
      MovaNodeFailVerdict.failItem,
    );
    expect(
      movaArbitrate(
        failure(content: true, fatal: false),
        ads: const MovaAdOpts(),
        movaRecovering: false,
      ),
      MovaNodeFailVerdict.ignore,
    );
  });
}
