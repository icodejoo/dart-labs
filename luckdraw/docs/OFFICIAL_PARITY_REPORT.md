# 官方示例 1:1 复刻与对照报告

用 luckdraw 原生 API 复刻官方站（<https://100px.net/demo/>）的**基础示例**和**完整示例**，
并逐项与官方画面对照，检验移植成果。入口：example 首页 →「官方示例对照」。

## 范围与数量

| 分区 | 官方页面 | 数量 | 配置文件 |
| --- | --- | --- | --- |
| 大转盘 | `/demo/wheel.html` | 19 | `example/lib/official/wheel_demos.dart` |
| 九宫格 | `/demo/grid.html` | 25 | `example/lib/official/grid_demos.dart` |
| 老虎机 | `/demo/slot.html` | 17 | `example/lib/official/slot_demos.dart` |
| 完整示例 | `/demo/more.html` | 15 | `more_wheel_slot_demos.dart`（7）+ `more_grid_demos.dart`（8） |

共 76 项，顺序、标题与官方一致；每项左侧官方截图（`example/assets/official_ref/`），右侧 luckdraw 实时渲染。

## 配置来源（可复核）

- 基础示例：官方站 JS 分包里的 60 份 playground 源码，原文存于 `docs/official_cfg/basic_demos_js.txt`。
- 完整示例：官方站**已下线完整源码**（页面注明“完整代码暂时下掉”）。15 份配置取自官方页面上正在运行的
  Vue 组件实例的运行时快照（`docs/official_cfg/more_runtime_dump.json`，含最终 data、回调源码、外层 DOM），
  其中 5 份另有 Vue 源码可互相印证。因此完整示例同样是按官方实际配置翻译，不是凭截图猜的。
- 素材：来自官方 npm 包 `buuing@0.0.3`（`/static/imgs/X` ↔ 包内 `demo/X`），按内容哈希核对，
  运行时快照里的 132 张图 100% 对上包内文件。**素材声明为学习交流、勿商用**，见包根 `NOTICE`。

## 验证结果

| 验证 | 结果 |
| --- | --- |
| `flutter analyze --no-pub`（example） | 零告警 |
| `test/official_gallery_smoke_test.dart` | 76 项全部可构建、渲染、卸载，无异常 |
| `test/official_gallery_flow_test.dart` | 官方 JS 里“点击开始→延时停止→结算”的 26 项均在 10 秒内结算；其余 50 项（官方本就纯展示或只转不停）无结果，与官方一致 |
| Windows 真机引擎逐项截图对照 | 76 项并排对照见 `docs/official_parity/*.png`（左官方、右 luckdraw） |

对照结论：除下节列出的差异外，布局、配色、图片摆放、文字换行/截断/省略、圆角、缝隙、按钮与指针、
中奖高亮（含滑过替换图片）、十/十二/十六宫格、圆形宫格、合并格子、横向老虎机、列/行间距等均与官方一致。
官方截图是页面加载瞬间的画布首帧，个别示例（如完整示例 #6 抖音宫格的中间按钮、#10 雪球的背景图）
首帧里图片尚未画上，属于截图时机差异，不是 luckdraw 的差异。

重新截图（真机引擎，不抢焦点的小窗口）：

```powershell
$env:OFFICIAL_OUT = 'D:\out'
dart run tool/run_integration.dart --device=windows --repeat=1 --file=official_capture_test.dart
```

## 发现的差异（luckdraw 与官方不一致处）

| # | 现象 | 影响 | 示例里的处理 |
| --- | --- | --- | --- |
| 1 | **老虎机没有奖品时整块不绘制，连 blocks 外框也不画**。`SlotLayout.isEmpty` 含 `cells.isEmpty`，游戏视图遇空布局直接跳过绘制；官方没有 prizes 也会画出 blocks | 老虎机 #1「通过padding挤出边框」、#2「设置边框圆角」、#3「使用图片作为背景」三项在 luckdraw 里画布空白。转盘、九宫格同类示例都正常 | 配置与官方一致，保留空白以暴露差异；**建议修库**：让 blocks 不依赖奖品格绘制 |
| 2 | **不支持负的基础格宽**。官方圆形宫格用 `rows/cols: 60` + 默认 gutter 5，基础格宽为负，仍按 `x*(w+gutter)` 出图；luckdraw 判为空布局 | 圆形宫格（基础 #23、完整示例 #12 仿咸鱼）按官方原配置直接空白 | 两项都换算成等价的“无缝整数细网格（gutter=0、坐标/跨度×整数）”，公式写在代码注释里，画面与官方一致 |
| 3 | `GridButton` 不携带 JS 里每个按钮自己的 `callback` | 官方“设置多个抽奖按钮”各按钮触发不同回调 | 同位置叠层分别展示按钮提示 |
| 4 | `WheelPrize` 没有官方 JS 里随手挂的自定义 `title` 字段 | 仅转盘 #5 里用于调试，不影响绘制 | 用 `semanticsLabel` 保存编号 |

建议跟进的是第 1 项（真实缺陷，影响基础示例 3 项）；第 2 项是否要兼容负基础格宽，取决于对“与上游行为一致”的承诺强度。

## 目录

- `example/lib/official/`：`official_demo.dart`（模型与助手）、`official_stage.dart`（三种舞台）、`official_gallery_page.dart`（对照页）及 5 个示例配置文件
- `example/assets/imgs/`：官方素材（8 MB，勿商用）；`example/assets/official_ref/`：官方截图
- `example/test/official_gallery_{smoke,flow}_test.dart`、`example/integration_test/official_capture_test.dart`
- `docs/official_cfg/`：官方配置原文与运行时快照；`docs/official_parity/`：对照图
