

## STEADY 第六轮入口

STEADY（2026-11-11）仅单台 vivo V2417 / Android16：四场景带luckdraw打点，slot/grid/lots各3/3，lotto4/5（2个污染、1个安装后VM连接超时，未污染2）。轮前后核对未锁，窗口内无额外adb轮询。按引擎帧号配对并校验SDK数组，trace尖峰与FrameTiming P99独立，12ms/4ms和MET2规则均未放宽。

slot/grid尖峰主要在框架编码/提交；lotto结算重复准备已定位，但复用painter候选三轮没有稳定净收益，已回滚。lots本轮三轮稳定且通过，不能解释历史不稳定。wheel /proc CPU已补齐3/3；仅标定，不外推跨设备。

[稳态逐帧归因](PERF_ROOTCAUSE_REPORT.md#稳态尖峰归因带打点steady-第六轮)、[完整原始报告](../tool/bench/results/steady/REPORT.md)。原始时间线无损gzip归档，记录原文与压缩文件SHA-256；候选优化已回滚，真实lib无本批变更。
