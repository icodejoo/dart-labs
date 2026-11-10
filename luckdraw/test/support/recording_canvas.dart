import 'package:flutter_test/flutter_test.dart';

/// 对 Flutter 录制画布提供调用计数及平衡断言。
extension LuckyRecordingCanvasAssertions on TestRecordingCanvas {
  /// 返回 [method] 的调用次数，如 `canvas.countCalls(#drawPicture)`。
  int countCalls(Symbol method) => invocations
      .where((record) => record.invocation.memberName == method)
      .length;

  /// 断言没有离屏 saveLayer，且 save 与 restore 在每个前缀都平衡。
  void expectBalancedWithoutSaveLayer() {
    expect(countCalls(#saveLayer), 0, reason: '绘制不得调用 saveLayer');
    var depth = 0;
    for (final record in invocations) {
      if (record.invocation.memberName == #save) depth++;
      if (record.invocation.memberName == #restore) depth--;
      expect(depth, greaterThanOrEqualTo(0), reason: 'restore 不得早于 save');
    }
    expect(depth, 0, reason: 'save/restore 必须平衡');
  }
}
