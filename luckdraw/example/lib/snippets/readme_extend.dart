import 'package:flutter/material.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

/// 自定义渲染后端：不画 Canvas，只用 Text 显示当前指针指向的奖品下标。
final class IndexRenderer extends LuckyRenderer<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 创建渲染后端。
  const IndexRenderer();

  /// 读取布局和逐帧数据，返回任意 Widget。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
      Center(child: Text('pointer: ${data.frame.pointerIndex}'));
}

/// 把自定义渲染后端显式传给转盘；玩法逻辑和控制器保持不变。
Widget customWheel(WheelController controller, WheelConfig config) =>
    LuckyWheel(
      config: config,
      controller: controller,
      renderer: const IndexRenderer(),
    );
