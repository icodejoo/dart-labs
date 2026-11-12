import 'dart:typed_data';

import '../../core/game/frame.dart';

/// 跨帧复用的摇奖快照；坐标相对各容器圆心。
final class LottoFrame extends LuckyFrame {
  /// 创建空帧，配置后分配固定长度缓冲。
  LottoFrame();

  /// 累计搅拌角（度）。
  double swirlDeg = 0;

  /// 当前搅拌强度。
  double mix = 0;

  /// 已落槽球数。
  int drawnCount = 0;

  /// 各池球横坐标，与 mixer 共用缓冲。
  List<Float64List> x = const [];

  /// 各池球纵坐标，与 mixer 共用缓冲。
  List<Float64List> y = const [];

  /// 各池球自转角（弧度）。
  List<Float64List> angle = const [];

  /// 按开奖顺序排列的球飞行进度，未开始时为零。
  Float64List flight = Float64List(0);

  /// 每池每颗球当前的结果槽下标，未抽出为 -1。
  ///
  /// 物理模式下，被导引的球在起飞前就会被标记，以便绘制时置顶。
  List<Int32List> slotOf = const [];

  /// 物理模式下各池拨杆的当前角度，单位度；参数化轨迹为零。
  Float64List stirDeg = Float64List(0);

  /// 各池是否正在用物理模拟，一为是；为零（含超过球数上限的回退）的池不绘制拨杆。
  Uint8List physical = Uint8List(0);
}
