
### 7.9 STEADY：带打点稳态尖峰归因与补齐CPU

STEADY（2026-11-11）仅单台 vivo V2417 / Android16：四场景带luckdraw打点，slot/grid/lots各3/3，lotto4/5（2个污染、1个安装后VM连接超时，未污染2）。轮前后核对未锁，窗口内无额外adb轮询。按引擎帧号配对并校验SDK数组，trace尖峰与FrameTiming P99独立，12ms/4ms和MET2规则均未放宽。

slot/grid尖峰主要在框架编码/提交；lotto结算重复准备已定位，但复用painter候选三轮没有稳定净收益，已回滚。lots本轮三轮稳定且通过，不能解释历史不稳定。wheel /proc CPU已补齐3/3；仅标定，不外推跨设备。

原APK启用LUCKDRAW_TIMELINE=true与LUCKDRAW_STEADY_ENTRY=true，slot mount在独立entry_reference窗口捕获，不混进稳态或GC参照。按frame_number配对、核对SDK数组；每个尖峰保存luckdraw完整起止与框架包含耗时，区间并集避免重复计时。没有分配栈或GPU上传关联的内容明确无法判定。污染轮、启动超时、失败命令原样保留；最多5次启动，不选好轮替换旧记录。

最终四场景为grid/slot/lotto失败，lots本轮通过；CPU进程/UI+platform/Raster中位数39.291465%/14.930757%/18.299352%，无批准CPU阈值，仅标定。候选lotto准备复用三轮未获稳定净收益，已回滚，不更新冻结预算。所有结论仅针对本设备及本批数据。STEADY-01～09/12追加矩阵，10/11是已回滚实验测试，不纳入最终注册。

[完整报告](../tool/bench/results/steady/REPORT.md)、[逐帧证据](../tool/bench/results/steady/ATTRIBUTION.md)；工具入口run_steady_device_checks.ps1，离线analyze_steady.py。旧§7.5～7.8保留历史身份，CPU当前方法为/proc首尾两次累计差，不再把历史cpuinfo/top采样当当前方案。

