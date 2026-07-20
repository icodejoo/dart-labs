/// 监听系统"减弱动态效果"偏好，命中时全局禁用动画。
///
/// 移植自 `src/panel/ux/reduced-motion.ts`。TS 版本监听浏览器
/// `prefers-reduced-motion` media query；Flutter 用 `MediaQuery.disableAnimations`
/// 读取同一个系统级无障碍偏好。没有关闭开关是刻意设计——无障碍不是可选项。
library;

import 'package:flutter/widgets.dart';

/// 读取当前系统是否偏好减弱动态效果。
///
/// 用法：在 widget 的 `build()` 里调用（依赖 `MediaQuery`，会在偏好变化时
/// 自动触发 rebuild），据此把 `RoadPanel.animDurationMs` 置 0。
///
/// ```dart
/// final reduced = prefersReducedMotion(context);
/// RoadPanel(..., animDurationMs: reduced ? 0 : 280);
/// ```
bool prefersReducedMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;
