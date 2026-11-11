# luckdraw 文档索引

## DEVFIN 最新设备证据

DEVFIN（2026-11-11）本次仅单台 vivo V2417 / Android 16：grid_steady：失败；slot_raster：失败；lots_shaking：不确定；lotto_draw：失败。冷push首帧增量wheel/grid/slot为38.087/10.520/0.245ms，新标定增量预算41.896/11.572/0.270ms；wheel/grid未达原4ms估算目标。CPU五项目各五次均0有效，不能提供可信百分比；wheel/grid冷帧主机汇总仅2/5、1/5成功，数值来自原始driver响应，失败标记保留。真机采集链路未通过，不把已标定写成达到设计目标。

见[第四轮度量说明](METRIC_FIX_REPORT.md#第四轮真机收尾复测)、[本次原始结果](../tool/bench/results/pending/REPORT.md)及[发布检查清单](RELEASE_CHECKLIST.md)。下文第三轮/MET2表保留历史口径，不能作为本次CPU已完成的证明。

> 状态：已按落地事实对齐（第三轮，2026-11-10）。0.1.0候选，尚未发布到pub.dev；本地全量门禁及真机事实见 [发布检查清单](RELEASE_CHECKLIST.md)，性能未完全通过。
> 本目录提供设计依据；D1–D8及F2/DIAG3统一决定优先，落地期决定见ARCHITECTURE §18 ADR-17–35；MET度量修正按主会话决定落地。其它冲突保守继续并留证，不自行改变架构（D8）。

## 文档一览

| 文档 | 内容 | 主要读者 |
| --- | --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 架构、分层与导出、插件 SPI、状态机、时间与停止语义、范围、追加玩法；§18 含落地期决定，§20 保留 B1/B2 与 N1–N16 已拍板记录；§17 区分假包实验、工具夹具和本包产物验证 | 所有人；评审先读 §0、§18、§20 |
| [FIDELITY.md](FIDELITY.md) | 上游行为对照：数值移植规则、文件/函数/配置项/默认值逐条映射、算法 Dart 写法（标上游行号）、绘制与逐帧伪代码、有意改进（IMP）/有意偏离（DEV）/不支持（N/A）/上游疑点（U）清单 | 落地者"照着翻译" |
| [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md) | 代码落地指导：守则与禁止事项、最终目录树、编码规范、坑清单、依赖图与并发波次、M0–M5 共 35 张任务卡（目标/前置/文件/中文注释的代码骨架/算法要点/上游位置/**测试名**/验收编号/DoD） | Sonnet / Codex 落地 |
| [TEST_STRATEGY.md](TEST_STRATEGY.md) | 测试分层、覆盖率 100% 门禁与豁免登记、验收矩阵结构与校验规则、**首版验收矩阵草稿**（249 个编号 → 真实测试名）、1:1 对照工具、真机性能基准、摇树验证、集成测试规矩、CI | 落地者、评审 |
| [UPSTREAM_ISSUES.md](UPSTREAM_ISSUES.md) | 上游 lucky-canvas issue 调研（只读输入，不修改） | 设计参考 |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | 0.1.0 发布预演、全量本地门禁实测、发布包清单与需外部条件的检查 | 维护者、发布者 |
| [MIN_VERSION_REPORT.md](MIN_VERSION_REPORT.md) | Flutter3.24.5/Dart3.5.4本地analyze零诊断、非golden951通过，另记golden差异 | 兼容性评审 |
| [DEVICE_REPORT.md](DEVICE_REPORT.md) | vivo V2417安卓集成33/33、原始11场景基准与阴影对照；保留未通过项 | 设备验收 |
| [PERF_REPORT.md](PERF_REPORT.md) | 默认auto缓存修复、三轮帧时原值与双峰限制 | 性能评审 |
| [AB_REPORT.md](AB_REPORT.md) | 亮度/看护与Skia/Impeller对照的历史记录；当前高档解释见METRIC_FIX_REPORT | 性能评审 |
| [EXAMPLE_STYLE_AUDIT.md](EXAMPLE_STYLE_AUDIT.md) | 45张自渲染截图约1.26MB；风格方向审计，没有上游演示真实截图 | 示例评审 |
| [OFFICIAL_PARITY_REPORT.md](OFFICIAL_PARITY_REPORT.md) | 官方示例站基础/完整示例 76 项 1:1 复刻与逐项对照（真机截图），发现的 luckdraw 差异（老虎机无奖品不画外框、负基础格宽） | 验收、修差异 |
| [E1_E2_DEVICE_REPORT.md](E1_E2_DEVICE_REPORT.md) | 真机实验：九宫格高亮帧节奏（60Hz，30 次/秒换格，无丢帧）与纹理成本断崖（52→104 MiB 光栅耗时 ×2.8） | 性能决策 |
| [audit/README.md](audit/README.md) | 自定义能力盘点（核心层 + 各玩法 + 分层/纹理化专项）原文与取舍 | 开放能力、排期 |
| [FIN重算报告](../tool/bench/results/fin/REPORT.md) | 全场景RSS预热/稳态拆分、UI预算与完整失败对比 | 发布评审 |
| [METRIC_FIX_REPORT.md](METRIC_FIX_REPORT.md) | 当前性能口径：背压证据、130窗口分布、分类规则、11场景重算、首版标定与首帧待标定；替代历史高档解释 | 性能与发布评审 |
| [PERF_ROOTCAUSE_REPORT.md](PERF_ROOTCAUSE_REPORT.md) | PEND：16个未污染窗口逐帧关联、尖峰完整清单、UI/Raster事件归因与普通帧对照；库内根因无法判定，真机复测待执行 | 性能与发布评审 |

## 阅读顺序

1. **评审 / 查决定**：ARCHITECTURE §0（一页结论）→ §20（已拍板）→ §18（ADR，含落地期记录）→ §14、§21（范围与追加玩法）。
2. **落地前**：ARCHITECTURE §3–§11 → IMPLEMENTATION_GUIDE §0–§4 → TEST_STRATEGY §1–§5。
3. **做某张任务卡时**：IMPLEMENTATION_GUIDE 对应卡 → 卡里引用的 FIDELITY 小节（逐行对照上游）→ TEST_STRATEGY 中该卡测试所在的矩阵行。
4. **改上游相关行为时**：先查 FIDELITY §8（IMP/DEV/U 清单），再查 ARCHITECTURE §12（issue 规避）。

## 编号约定

| 前缀 | 含义 | 定义位置 |
| --- | --- | --- |
| `R1`–`R7` | 需求：R1 扩展性、R2 性能、R3 API、R4 测试门禁、R5 文档、R6 摇树、R7 用户追加玩法 | TEST_STRATEGY §5.3 |
| `SM-E01`…`SM-E26` | 状态机迁移边 | ARCHITECTURE §9.2 |
| `ISS-<issue号>` | 上游 issue 规避项（`ISS-120HZ` 为高刷屏） | ARCHITECTURE §12 |
| `FID-L/U/W/G/S…` | 上游对照条目（基类/工具/转盘/九宫格/老虎机） | FIDELITY §3–§7 |
| `IMP-*` / `DEV-*` / `U-*` | 有意改进 / 有意偏离 / 上游疑点 | FIDELITY §8 |
| `IMP-R1`…`IMP-R12` | import 依赖与摇树静态规则 | ARCHITECTURE §4.3 |
| `ADR-*` | 架构决策 | ARCHITECTURE §18 |
| `T0.1`…`T5.10` | 任务卡 | IMPLEMENTATION_GUIDE §5–§10 |
| `COV-*` | 覆盖率豁免 | `test/ACCEPTANCE.md`（落地后） |

## 维护约定

- IMPLEMENTATION_GUIDE 任务卡里的测试名逐字保留；TEST_STRATEGY §5.3 为设计编号追踪索引，实际完整登记及追加回归以 `test/ACCEPTANCE.md` 为准。正式门禁使用 `tool/check_acceptance.dart --from-json <运行日志>`，静态模式仅作快速检查。改名须同步代码、矩阵及两份清单。
- 新增公共符号时同步改 ARCHITECTURE §16 导出清单与 CHANGELOG。
- 架构决策变更要在 ARCHITECTURE §18 追加 ADR，并写明"推翻了哪条既有决定"。
- 落地期矩阵写「已落地」（D6），不等于所有门禁、平台或人工验收通过；T4.8 统一最终状态。历史测试名与实际语义有差异时保留名称并在对应小节说明，协调改名须同步代码、矩阵和两份测试清单。

## 第三轮对齐与验证边界

F1/F2、DIAG3、三玩法parity的契约继续有效；本轮把MIN/APK/DEV/PERF/AB与示例审计证据写回正文。默认auto与RSS口径记录为ADR-32～34，严格上游与parity保持picture。两份README12个Dart块未变，新增八张浅色示例截图及诚实性能说明；图片用raw绝对地址，须在仓库发布后才能供pub.dev远程加载。

MIN本地Flutter3.24.5/Dart3.5.4 analyze零诊断、非golden951通过；Web/APK各十探针真实构建零泄漏、预算已回填，APK CI已重新启用（五探针），远程结果未验。Windows与安卓集成各33/33；FIN全量本地门禁结果见发布清单。

MET2（2026-11-10）纯离线复算：**帧交付完整（全部130个窗口约60fps，59.829927–60.176516，无真实丢帧，按timeline交付口径）；偶发窗口的Raster时间被vsync背压污染且与绘制内容无关（参照方块同样出现）；按真机实测标定了首版回归预算。** 不是性能全部达标：1项满足有效目标（memory，RSS沿用FIN口径）、5场景已标定但未达最初设计目标、3场景失败、1场景不确定、1首帧信息项。首帧与进程级CPU待下次真机会话标定；性能结论基于单台设备vivo V2417（Android 16）三轮数据，不是跨设备保证。PERF五场景与DEV其余场景沿用MET/FIN身份，并非同一APK全量重测。现有timeline不等于独立面板呈现测量；污染窗口无法测量纯绘制成本。

| 场景 | 未污染/总窗口 | UI均值 ms | Raster均值/P90 ms | 结论 |
| --- | --- | --- | --- | --- |
| wheel_steady | 2/3 | 0.9365 | 5.0996/6.7480 | 已按实测标定（未达最初设计目标） |
| wheel_first_frame | 不适用 | — | —/— | 信息项，待标定 |
| grid_steady | 3/3 | 1.0243 | 5.4998/6.5570 | 失败 |
| slot_steady | 2/3 | 1.3576 | 3.4481/3.9580 | 已按实测标定（未达最初设计目标） |
| slot_raster | 3/3 | 1.0641 | 2.7681/3.1630 | 失败 |
| lever_steady | 3/3 | 1.3999 | 3.7137/4.2170 | 已按实测标定（未达最初设计目标） |
| capsule_mixing | 3/3 | 1.6541 | 3.8083/4.3140 | 已按实测标定（未达最初设计目标） |
| number_wheel_spin | 2/3 | 1.1357 | 2.9759/3.3465 | 已按实测标定（未达最初设计目标） |
| lots_shaking | 2/3 | 1.3782 | 3.8951/4.8300 | 不确定，需补跑 |
| lotto_draw | 2/3 | 2.2188 | 4.8241/5.4880 | 失败 |
| memory_cycles | 不适用 | — | —/— | 满足设计目标 |

| 未达最初设计目标的场景 | 指标与差距（实测中位数/最初目标−1） |
| --- | --- |
| wheel_steady | Raster均值 +1.99% |
| grid_steady | UI均值 +70.72%、UI P90 +18.67%、Raster均值 +37.49% |
| slot_steady | UI均值 +35.76% |
| slot_raster | UI均值 +6.41% |
| lever_steady | UI均值 +39.99%、UI P90 +4.80% |
| capsule_mixing | UI均值 +10.27% |
| number_wheel_spin | UI均值 +13.57% |
| lots_shaking | UI均值 +37.82%、UI P90 +1.20% |
| lotto_draw | UI均值 +47.92%、UI P90 +10.75% |

硬门禁（每未污染窗口合计P99≤12ms、UI P99≤4ms）使grid/slot_raster/lotto失败，合计最大12.231/16.905/12.229ms；lotto UI最大4.386ms。lots的Raster稳定性仍不确定，需补跑。成本比例稳定性改绝对极差0.01；低于0.5ms的时间用0.15ms，其余相对30%。首版预算及每指标结果见[MET2报告](../tool/bench/results/met2/REPORT.md)，当前政策见[度量修正报告第二轮](METRIC_FIX_REPORT.md)。

Skia/Impeller阴影半径差1–2物理像素、扫描线峰值差20.8–23.8/255，登记为已知后端差异；主会话决定不按后端改sigma，原因见ARCHITECTURE §8。老虎机阴影被裁剪、缺少可观察样本，未量化。

仍未完成：Linux golden和远程CI、最低版本golden差异闭环、MET2三项帧余量硬失败和一项不确定闭环、进程级CPU实测、空白页冷首帧三轮基线与增量预算、老虎机可观察阴影样本、上游演示逐像素对齐、layout/record细分与解码字节诊断、真实pub.dev发布（需用户授权）。示例截图只说明风格方向，未拿到上游演示真实截图。

矩阵历史行按批次证据保留，本批只追加FIN-01～06并标「已落地」，不把历史未通过状态静默改成已通过。设计正文采用当前批准值，历史报告保持原样；如AB早期归因措辞超出证据，以AB2与本轮保守结论为准。

## 变更记录

| 日期 | 变更 |
| --- | --- |
| 2026-11-10 | REL：0.1.0 候选元数据、英文发布日志、中英文 README 状态、发布包排除规则及发布预演；新增发布检查清单，最低版本报告保留生成中链接 |
| 2026-11-10 | B17b 第二轮：F1/F2契约与ADR-26–31，最终parity分层、真实Web摇树及Windows33/33；两份README共12个Dart块临时工程分析0 issue；保留真机/Linux/min-sdk/APK/发布待验边界 |
| 2026-11-10 | B17a 第一轮落地事实对齐：D1–D8 与 ADR-17–25；正文修正各批冲突和骨架；保留验收编号及历史测试名，区分已落地与待落地验证；脚本只读核验引用 |
| 2026-11-10 | 首版设计稿：上游三玩法移植 + 扩展架构 + 测试门禁；设计过程中按用户追加需求加入摇树要求（R6）、上游 issue 规避（ARCHITECTURE §12–§13）、以及拉霸机、扭蛋机、数字转盘（外缘数字刻度 + 小球）、抽签、大乐透五种玩法（ARCHITECTURE §21、IMPLEMENTATION_GUIDE M5） |
| 2026-11-10 | FIN第三轮：auto/RSS/UI预算、MIN/APK/DEV/PERF/AB、八张README截图、发布清单与全量门禁；性能未完全通过，真实发布未做 |
| 2026-11-10 | MET：离线背压污染分类与交付/成本分离，130窗口分布、11场景4通过/6失败/首帧信息，4项首版标定；不按后端调整阴影sigma |
| 2026-11-10 | MET2：比例/小耗时绝对稳定性、28项实测冻结预算、12/4ms硬门禁；1有效目标满足/5已标定未达设计/3失败/1不确定/1首帧信息，14项原设计差距全部列示；新增10回归、全量1070通过、100%覆盖率、发布预演0 warnings |

## INSTR 第五轮入口

INSTR（2026-11-11，副本候选实现）：wheel/grid带打点冷首帧中位数38.412→27.075ms、24.214→12.993ms，精确文字宽度缓存将首帧TextPainter.layout次数276→63、128→22；随机/多语言/emoji/lineClamp等价。减DEVFIN历史空白2.883ms后的增量24.192/10.110ms，新预算26.612/11.121ms，仍未达到原4ms目标，三轮波动大。CPU采用/proc累计节拍差，UI与平台合并标为UI+platform；wheel完整链路仅2/5，不能给三轮中位数；其余场景逐轮数值和有效性见本轮报告，lotto仅搅拌阶段。库改动以补丁交付，未覆盖并行共享lib，待主会话合并。

[原始数据和全部门禁](../tool/bench/results/pending2/REPORT.md)；[逐事件归因](../tool/bench/results/pending2/attribution.json)。前面DEVFIN/MET2条目保留其历史身份。


## STEADY 第六轮入口

STEADY（2026-11-11）仅单台 vivo V2417 / Android16：四场景带luckdraw打点，slot/grid/lots各3/3，lotto4/5（2个污染、1个安装后VM连接超时，未污染2）。轮前后核对未锁，窗口内无额外adb轮询。按引擎帧号配对并校验SDK数组，trace尖峰与FrameTiming P99独立，12ms/4ms和MET2规则均未放宽。

slot/grid尖峰主要在框架编码/提交；lotto结算重复准备已定位，但复用painter候选三轮没有稳定净收益，已回滚。lots本轮三轮稳定且通过，不能解释历史不稳定。wheel /proc CPU已补齐3/3；仅标定，不外推跨设备。

[稳态逐帧归因](PERF_ROOTCAUSE_REPORT.md#稳态尖峰归因带打点steady-第六轮)、[完整原始报告](../tool/bench/results/steady/REPORT.md)。原始时间线无损gzip归档，记录原文与压缩文件SHA-256；候选优化已回滚，真实lib无本批变更。
