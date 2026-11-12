import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

/// 默认的测试墙钟起点；与历史测试使用的日期保持一致。
final DateTime kTestWallStart = DateTime(2024, 1, 1, 12);

/// 安装一个 [ManualCountmanClock] 作为 [CountmanClock.system]，并在测试结束时恢复。
///
/// 只能在 `setUp` 或测试体内调用。推进时间用 `clock.advance(...)`，
/// 模拟用户改系统时间用 `clock.jumpWall(...)`，模拟深睡用 `clock.suspend(...)`。
/// 例如 `final clock = installManualClock();`。
ManualCountmanClock installManualClock({DateTime? wallTime}) {
  final original = CountmanClock.system;
  final clock = ManualCountmanClock(wallTime: wallTime ?? kTestWallStart);
  CountmanClock.system = clock;
  addTearDown(() => CountmanClock.system = original);
  return clock;
}
