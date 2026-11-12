# STEADY 第六轮：带打点稳态与 wheel CPU

仅 vivo V2417 / Android 16 / 10AE9K17UE0011S，2026-11-11，副本 C:/ldq/luckdraw。
开工同步真实仓库 lib/test/tool/docs/README，保留 build/results 和缓存；主包、bench pub get 后立即恢复分析配置。
首轮仅用 flutter drive --profile 构建，无独立 flutter build；Gradle workers=2、single-use、Windows 根证书库，构建34.1s，构建前空闲13595512KiB。
原始 APK SHA-256：BE8DC82D81FD89D5CA8E8289D1A930ED76795885404BAC03ADAB7CCBEBA7DC7C。

## 方法和打点

LUCKDRAW_TIMELINE=true；启用 luckdraw.{slot,grid,lotto,lots,wheel}.{layout,record,paint}，
luckdraw.text.layout/split/painter.layout、luckdraw.image.update、luckdraw.picture.record、luckdraw.raster.build/prepare/atlas。
稳态实际观测见 frames.json.events，缺事件不能推导分配或 GPU 成本为零。
LUCKDRAW_STEADY_ENTRY=true 只在 slot mount 增加独立 slot_raster_entry_reference trace；不混入五秒参照或 cruising 后的稳态窗口。
逐帧使用 analyze_frames.py 的 frame_number 配对并逐项核对 SDK UI/Raster数组。尖峰为 trace 同帧合计>12ms 或UI>4ms；硬门禁另用 FrameTiming P99。
包含事件不可相加；库并集按同线程区间并集计算；墙钟区间不能当 CPU。首5帧及每秒分桶只描述分布，不推断随机性/周期性。
GC 全区间、边界未配对帧、每个尖峰中的每次 luckdraw 事件及框架事件，见 [完整清单](ATTRIBUTION.md) 和 [frames.json](frames.json)。
所有失败和污染轮保留；未污染成本门禁与 MET2 的12ms/4ms、稳定性、GC/RSS阈值均未改变。

## A：四场景归因

| 场景 | 成功/启动/未污染 | 尖峰各轮（仅未污染） | 位置 | 事件累计ms / %同帧合计 | 结论三选一 |
| --- | --- | --- | --- | --- | --- |
| slot_raster | 3/3/3 | 0/2/2 | 2.566–2.583s、4.534–4.550s，成对；首5帧0 | paint 0.377/0.67%；Encode 43.418/77.47%；Submit 50.742/90.54% | 框架或设备（有证据：长区间在编码/提交，具体GPU/驱动/调度原因无法判定） |
| grid_steady | 3/3/3 | 0/2/2 | 2.867–2.884s、4.700–4.718s，成对；首5帧0 | paint 0.902/1.36%；Encode 52.004/78.58%；Submit 59.596/90.05%；CreateGlyphAtlas 0.119/0.18% | 框架或设备（有证据：编码/提交；不是已证明的设备缺陷） |
| lotto_draw | 4/5/2 | 10/9 | 0.134–4.434s，搅拌/开奖散布；含结算最后帧，首5帧0 | paint 38.181/19.90%；record 5.956/3.10%；Encode 55.164/28.75%；COMPOSITING 15.508/8.08% | 库内成本（已定位：结算重复准备；其它UI尖峰仍无法判定可避免性） |
| lots_shaking | 3/3/3 | 0/1/1 | 2.367s与3.583s的孤立UI尖峰，首5帧0 | paint 1.123/7.05%；COMPOSITING 4.597/28.86%；Encode 2.149/13.49% | 无法判定（历史Raster不稳定未重现；本轮UI长区间多在框架） |

普通帧 paint 均值slot/grid/lotto/lots分别0.123/0.210/1.107/0.372ms；尖峰对应均值0.094/0.226/2.010/0.562ms。
slot/grid 稳态没有玩法layout/record、文字layout/split或位图build调用；lotto没有每帧layout/文字整形，但结算阶段1次record包含50次缓存查询与47次raster准备。
这不等于每帧零分配：没有分配采样栈，来源/数量仍无法判定。

slot 入场三轮首次 atlas 位于 UI帧1，引擎帧802/797/799，调用0.388/0.285/0.473ms；随后图片就绪更新引发第2–3/4帧准备。
全部11次调用的帧号/耗时在完整清单：第一轮0.388/0.297/0.281ms，第二轮0.285/0.351/0.193/0.224ms，第三轮0.473/0.334/0.289/0.309ms。
这些是 UI isolate 上 SlotAtlas.prepare 同步区间，包含缓存检查和 toImageSync 发起；没有独立的GPU位图执行/上传子事件，实际上传耗时和线程无法判定，不能把同步准备耗时冒充完整GPU构建成本。
稳态没有atlas构建，四个slot尖峰均在窗口中段，故不搬动图集构建时机。

lots 三轮 Raster trace均值3.099/3.082/3.101ms；本轮稳定，不能由此解释历史41.69%/53.75%的极差。
其两个UI尖峰：paint0.649/0.474ms，UI4.058/5.089ms；后一帧COMPOSITING3.920ms。没有可避免的库内重复工作证据，不改lots。

lotto第2次在安装后未出现VM Service连接，五分钟终止自有进程树；不是CPU采样器错误，底层连接失败原因无法判定。
第1/3次成功但Raster P90≥15.5ms，被污染；第4/5次未污染。不得将这些失败或污染轮删掉后冒充前三轮全成功。

## C：wheel CPU

/proc stat累计节拍差 / CLK_TCK / 主机两次读取开始的单调间隔，单核100%，进程可超过100%；不裁剪、不补零。
窗口前重新取PID/探测权限；窗口内仅首尾各一次adb，实际时长包含首读/握手开销。UI/platform合并，不能分拆成纯Dart UI。

| 轮 | 进程% | UI+platform% | Raster% | 实际秒数 | 首/尾读取ms |
| --- | --- | --- | --- | --- | --- |
| 1 | 40.039608 | 15.014853 | 18.299352 | 6.393669 | 1381.079/1536.642 |
| 2 | 35.523078 | 12.675636 | 18.152762 | 6.390212 | 1375.282/1530.990 |
| 3 | 39.291465 | 14.930757 | 18.545571 | 6.362705 | 1336.095/1515.638 |
| 中位数 | 39.291465 | 14.930757 | 18.299352 | — | — |

3/3完整链路成功，同轮帧数477/477/475、fps59.992/60.088/60.076；原始线程stat/comm、PID、新建/退出线程与FrameTiming在各cpu目录和audit.json。
未重采其它四个玩法CPU。INSTR缺轮原因已核对原日志：第1/2次driver抛“缺少同轮GC参照”，第5次未连接采样器、四分钟超时并五分钟终止；第3/4次成功。
GC误要求已由INSTR response_writer的cpu_scene分支修复，本批复用它；没有发现新的累计节拍计算bug。
本批仅补成功结果 valid_cpu=true 元数据（失败降级已有false），并增加成功/坏快照回归，避免新编排把合法结果误判无效。

## B：候选修复与复测

结算帧267（引擎帧号见frames.json）UI11.485ms，其中luckdraw.lotto.record5.956ms占UI51.86%；底层Picture命中缓存，没有重新文字整形。
Lotto surface每次phase通知仍构造LottoPainter、47个LuckyCachedPicture及列表/回调，虽是低频路径，但在测量窗口最后一帧形成可避免尖峰。
副本候选仅复用低频输入未变的painter；阶段变化仍更新CustomPaint.willChange，钩子/监听器/布局等输入变化按需替换；公共API、运动公式、渲染顺序、picture/strictUpstream均不变。
新增两条widget回归验证全阶段至结算身份复用、结果不变，以及新hooks/listeners生效且旧通知不触发绘制。lotto目录测试已通过。
候选修复真机3/3成功且未污染，APK SHA-256见after/runs.json，第二次drive构建30.9s。
结算record确实由每轮1次变成0次；但场景没有稳定净收益，按用户要求已恢复原始lotto_canvas_renderer.dart，撤去仅本实验新增的两条身份测试及其矩阵行。
原库与parity/golden/公共API没有最终变更。候选补丁只作为[已拒绝实验](validation/steady_lotto_rejected.diff)留档，**不要当待合并修复应用**；C:/ldq/steady_lotto_rejected.diff同内容，没有新core_patch.diff。

| 指标（未污染） | 原始实现2窗口 | 候选3窗口 | 结论 |
| --- | --- | --- | --- |
| trace尖峰/帧数/比例 | 19/534/3.56% | 47/808/5.82% | 没有下降；轮数不同不只比较总数 |
| 合计P99各轮ms / 最大 | 9.620/9.169 / 9.620 | 9.098/9.788/10.593 / 10.593 | 均≤12，但候选最大更高 |
| UI P99各轮ms / 最大 | 4.725/4.226 / 4.725 | 4.120/4.565/3.376 / 4.565 | 仍有窗口>4，失败 |
| UI均值中位数ms / 极差比 | 2.233893 / 8.22% | 2.391984 / 36.05% | 候选均值更高且不稳定 |
| Raster均值中位数ms / 极差比 | 4.731389 / 1.49% | 4.839185 / 9.43% | 未观测净改善 |
| Raster P90中位数ms | 5.141 | 5.283 | 候选更高 |
| record次数 | 1/1 | 0/0/0 | 结构性工作消除不等于场景收益 |
| MET2最终状态 | FAIL | FAIL | 两者UI硬门禁失败；未放宽预算 |

候选阶段lotto目录36/36测试通过（包含两条新契约测试和已有golden）；最终已回滚，不能将该计数冒充最终新增测试数。
修复前后源代码、不同APK与单台设备波动均有边界；没有关闭打点APK对照，不把微小均值差异当严格因果结论。
未修改 budgets.json / budgets.status.json：没有保留且转为通过的库修复；lots本轮PASS单列证据，历史MET2冻结状态保留。

## 手机收尾与边界

设备最终实测见[device_final.json](device_final.json)：stay_on=2、brightness_mode=0、brightness=1；dumpsys display明确Display State=ON，Awake/未锁均true，adb reverse为空。
Android16 dumpsys power不再包含state=ON，第一次旧正则返回false是解析问题；已用display原文更正，未把它当灭屏事实。
正常卸载命令exit1/DELETE_FAILED_INTERNAL_ERROR；随后pm list packages与pm path均空，观察上已无bench包，不把卸载退出码写为0。
未改手机设置、未kill-server、未按java/node进程名批杀。窗口内除了CPU规定首尾采样无额外adb轮询；轮前后未锁不能独立排除窗口中间DIM。

## 文档冲突和建议

- INSTR历史报告称库补丁待合并，但本批同步的真实lib已经具有luckdraw打点；以本批源文件哈希和APK实际事件为准，不重放旧补丁。
- bench README历史段落仍称无layout/record调用、CPU辅助函数注释称固定五次；新增STEADY规程和本报告给出现行行为，函数注释改为由主机采样器定义次数，旧报告保留历史身份。
- 建议把record事件细分为prepare/cache-hit/actual-record，并在SlotAtlas的toImageSync发起与GPU上传之间增加可验证关联；当前包装事件不能证明实际GPU上传成本。
- 建议在后续基准保存显式结算帧标记与低频准备次数，避免以窗口尾边界推测结算帧；本批没有为补证据扩大启动次数。
- 路径协议未提供“本批拥有的lib路径”，又禁止覆盖并行玩法。候选只在副本实验、结果不稳定后回滚，真实库与其它玩法完全不覆盖；仅归档拒绝实验，不交待合并库补丁。
- D6：仅追加STEADY工具/真机证据，代码行标已落地，设备门禁状态按实测；D8保守保留无法判定项。D1–D5/D7与公共API、strictUpstream/picture、公式、MANIFEST和基线没有变更。



## 最终本机门禁

已回滚库候选后的最终实现：新增工具4条，四组覆盖全部145个测试文件，1112/1112通过、零失败跳过；工具单独227通过。实验阶段lotto36条仅为拒绝实验历史，不计作最终新增。

| 命令 | 实际输出摘要 |
| --- | --- |
| analyze | exit=0，7.254s；Analyzing luckdraw...                                            / No issues found! (ran in 5.3s) |
| bench_analyze | exit=0，5.333s；Analyzing bench...                                               / No issues found! (ran in 3.5s) |
| format | exit=0，2.045s；Formatted 361 files (0 changed) in 0.86 seconds. |
| format_check | exit=0，1.892s；Formatted 361 files (0 changed) in 0.85 seconds. |
| tools | exit=0，38.401s；227 passed; failed=0; skipped=0 |
| steady-a | exit=0，71.916s；554 passed; failed=0; skipped=0 |
| steady-b | exit=0，36.24s；130 passed; failed=0; skipped=0 |
| steady-c | exit=0，75.947s；405 passed; failed=0; skipped=0 |
| steady-d | exit=0，9.634s；23 passed; failed=0; skipped=0 |
| coverage | exit=0，1.52s；TOTAL: 6878/6878 (100.00%) / PASS: coverage >= 100.0% |
| imports | exit=0，1.916s；PASS: 145 lib files; IMP-R1…R12 / 依赖图与静态规则通过 |
| acceptance | exit=0，1.528s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| acceptance_json | exit=0，1.425s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| parity | exit=0，10.874s；PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified |
| publish | exit=0，4.507s； / Package has 0 warnings. |

LCOV独立使用coverage/steady-{a,b,c,d}.lcov，验证四组并集后合并coverage/steady.lcov；JSON仅平移ID/时间合并真实事件，--from-json校验通过。日志与执行元数据见tool/bench/results/steady/validation，逐组真实计数在test_summary.json。

真机A：slot/grid/lots各3/3；lotto4/5、未污染2；wheel CPU3/3。lotto候选复测3/3未污染，但无稳定净收益且UI P99仍失败，已回滚。原实现grid/slot/lotto仍失败，lots本轮通过，不放宽预算。原始时间线57份（含response）无损gzip校验后归档；拒绝实验diff只作历史，不应应用。

手机收尾：stay_on=2、亮度模式0、亮度1，dumpsys display为ON、Awake且未锁；reverse为空。卸载exit1/DELETE_FAILED_INTERNAL_ERROR，但pm list packages与pm path均空，实测无bench包。没有改手机设置或批杀java；自有进程末检在真实仓库复验后追加。

[STEADY完整报告](REPORT.md)，[逐帧归因](ATTRIBUTION.md)。副本完成所有本地门禁，真实库不覆盖，回拷仅工具/测试/文档且共享文件重读定点追加。


## STEADY 真实仓库回拷复验

真实仓库实际输出：format本批3个Dart文件0改动；flutter test test/tool --no-pub --concurrency=1 为227/227，39.389s，零失败/跳过；check_imports为145 lib文件PASS；check_acceptance为1564 references / 1137 registered tests全部映射PASS。源/共享14个路径及全部结果文件见tool/bench/results/steady/validation/copy_manifest.json；没有回拷lib，库哈希在副本已核对恢复同步基线。共享文档与矩阵均即时重读定点追加，无整文件覆盖他人增量。

最终实测2026-11-10T19:15:22.1344383Z：stay_on=2，brightness_mode=0，brightness=1，Display State=ON、Awake且未锁，reverse为空，包列表与pm path均空；卸载原退出1/DELETE_FAILED_INTERNAL_ERROR保留。进程末检仅剩接手前的两个其它工作区Sass Dart PID25880/22908；没有自有dart/flutter_tester/Gradle/Kotlin残留，无需结束进程。首尾git log均443589a3 / f0b64ae1，未add/commit/push。

最终库候选已回滚，无待合并core_patch.diff；steady_lotto_rejected.diff仅拒绝实验历史，不应应用。grid/slot/lotto性能仍失败、lots仅本轮三轮通过；CPU仅单台设备标定。
