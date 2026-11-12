import 'more_grid_demos.dart';
import 'more_wheel_slot_demos.dart';
import 'official_demo.dart';

/// 官方「完整示例」15 张卡片，按官方卡片顺序（refAsset more_01…more_15）排列。
final List<OfficialDemo> moreDemos = [
  ...moreWheelSlotDemos,
  ...moreGridDemos,
]..sort((a, b) => a.refAsset.compareTo(b.refAsset));
