# 自定义能力盘点索引

目标：库只提供能力，UI/动效/性能策略由使用者自定。以下 7 份报告按同一张检查清单（缓动、布局常量、绘制、时间/物理阈值、行为策略、状态可见性、事件、导出面、数据驱动）盘点"写死、用户改不了"的点。

| 报告 | 范围 |
| --- | --- |
| [core.md](core.md) | 核心层：运动、缓存、文字、图片、层、手势、语义 |
| [wheel.md](wheel.md) / [grid.md](grid.md) / [slot.md](slot.md) | 转盘 / 九宫格 / 老虎机与拉霸机 |
| [capsule_number.md](capsule_number.md) / [lots_lotto.md](lots_lotto.md) | 扭蛋机与数字转盘 / 抽签与大乐透 |
| [planes.md](planes.md) | 分层与纹理化（plane）可行性与设计；E3 实测后决定暂不实现，见 ../E1_E2_DEVICE_REPORT.md |

已决定的取舍：不按清单全做，而是"有需求才开放"；已落地的有抽签自定义 API、老虎机空配置修复、LuckyConformance、缓存失效告警、九宫格高亮封顶与 reduceMotion、共享纹理预算。
