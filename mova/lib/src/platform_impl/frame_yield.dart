import 'package:flutter/scheduler.dart';

/// 等当前帧结束（若尚无待处理帧会主动调度一帧）。
///
/// 供 `MovaMpvKernel` 的 `mountYield` 使用：让同帧挂载的视频组件先创建渲染面，再开文件。
///
/// 返回：帧结束时完成的 Future。
///
/// 示例：`MovaMpvKernel(lazyVideo: true, mountYield: movaFrameYield)`
Future<void> movaFrameYield() => SchedulerBinding.instance.endOfFrame;
