import 'package:flutter/widgets.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/slot.dart';

/// 白色背景，避免不同主题影响亮度剖面。
const Color kShadowBackground = Color(0xFFFFFFFF);

/// 用于扫描线隔离的标准格子边长。
const double kShadowCellSize = 64;

/// 每个样本的面板大小；阴影外扩仍在面板内。
const Size kShadowPanelSize = Size(180, 220);

/// 标准阴影模糊量，分别解释为设备或逻辑像素。
const double _blur = 16;

/// 标准阴影偏移；只让纵向偏移，水平扫描线对称。
const double _offset = 6;

/// 放大组的 CTM 倍率。
const double _scale = 1.5;

/// 九宫格标准样本的行列数。
const int _gridSide = 3;

/// 真实九宫格样本的元数据键。
const String kShadowGridPanel = 'grid_3x3';

/// 真实老虎机样本的元数据键。
const String kShadowSlotPanel = 'slot';

/// 标准格子的实心背景。
const LuckyFill _fill = LuckyFill.color(Color(0xFF4488CC));

/// 全部样本及其画布缩放，键同时用于截图 ROI。
const Map<String, double> kShadowPanels = {
  'device_1': 1,
  'logical_1': 1,
  'device_1_5': _scale,
  'logical_1_5': _scale,
  kShadowGridPanel: 1,
  kShadowSlotPanel: 1,
};

/// 返回同一阴影配置，仅 [space] 决定 sigma 的空间语义。
LuckyCellStyle _style(LuckyShadowBlurSpace space) => LuckyCellStyle(
    background: _fill,
    shadow: LuckyShadow(
        offsetY: _offset,
        blur: _blur,
        color: const Color(0xB3000000),
        blurSpace: space));

/// 使用公开玩法入口构造无动画、无字体的阴影对照图。
///
/// 四个孤立格子用于半径扫描，另附真实九宫格和老虎机阴影配置。
class ShadowScene extends StatelessWidget {
  /// 创建确定性的对照场景；例如 `runApp(const ShadowScene())`。
  const ShadowScene({super.key});

  /// 返回 [name] 对应的静态玩法，不使用私有 renderer 或核心补丁。
  Widget _sample(String name) {
    final space = name.startsWith('device')
        ? LuckyShadowBlurSpace.device
        : LuckyShadowBlurSpace.logical;
    final style = _style(space);
    if (name == kShadowSlotPanel) {
      return LuckySlotMachine(
          config: SlotConfig(
              prizes: const [SlotPrize(), SlotPrize(), SlotPrize()],
              reels: const [SlotReel()],
              style: SlotStyle(cell: style)));
    }
    final nine = name == kShadowGridPanel;
    return LuckyGrid(
        config: GridConfig(
            rows: nine ? _gridSide : 1,
            cols: nine ? _gridSide : 1,
            prizes: [
              for (var y = 0; y < (nine ? _gridSide : 1); y++)
                for (var x = 0; x < (nine ? _gridSide : 1); x++)
                  GridPrize(x: x, y: y),
            ],
            style: GridStyle(cell: style),
            activeStyle: style));
  }

  /// 固定逻辑尺寸，所有后端共享同一 CTM 与 DPR。
  @override
  Widget build(BuildContext context) => WidgetsApp(
      color: kShadowBackground,
      builder: (context, _) => ColoredBox(
          color: kShadowBackground,
          child: Center(
              child: Wrap(
                  children: kShadowPanels.entries
                      .map((entry) => SizedBox.fromSize(
                          key: ValueKey(entry.key),
                          size: kShadowPanelSize,
                          child: Center(
                              child: Transform.scale(
                                  scale: entry.value,
                                  child: SizedBox.square(
                                      dimension: kShadowCellSize,
                                      child: _sample(entry.key))))))
                      .toList()))));
}
