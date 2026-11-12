import 'dart:ui' show Color;

import 'length.dart';

/// 参考帧时长（毫秒），用于把上游每帧速度换算为 60Hz 时间速度。
const double kLuckyReferenceFrameMs = 1000 / 60;

/// 几何平分、直径与二次缓动公式中的二分系数。
const double kLuckyHalfDivisor = 2;

/// 对半取值的系数，用于路径分段、比例折半等。
const double kLuckyHalf = 0.5;

/// 上游 FPS 初值（wheel.ts:42）。
const double kLuckyInitialFps = 16.6;

/// 有效时间轴单帧最大推进量的默认值。
const Duration kLuckyDefaultMaxFrameDelta = Duration(milliseconds: 100);

/// 停止求解的最大迭代次数。
const int kLuckyMaxSolverIterations = 100000;

/// 位图缓存单边最大像素的默认值。
const int kLuckyDefaultMaxRasterSide = 4096;

/// 实验性（可能调整）：共享位图预算默认 32 MiB；E2 中 52 MiB 内平稳、104 MiB 掉帧。
const int kLuckyDefaultMaxRasterBytes = 32 * 1024 * 1024;

/// 实验性（可能调整）：名义 RGBA 每像素字节数，不包含引擎和驱动附加内存。
const int kLuckyRgbaBytesPerPixel = 4;

/// 上游 splitText 使用的省略号。
const String kLuckyEllipsis = '...';

/// 正上方指针的角度（度）。
const double kLuckyPointerDeg = -90;

/// 九宫格速度除数（grid.ts:153）。
const double kLuckyGridSpeedDivisor = 40;

/// 九宫格加速起点速度（grid.ts:592）。
const double kLuckyGridAccelerationBase = 0.1;

/// 上游默认速度（每参考帧）。
const double kLuckyDefaultSpeed = 20;

/// 上游默认加速时长。
const Duration kLuckyDefaultAccelerationTime = Duration(milliseconds: 2500);

/// 上游默认减速时长。
const Duration kLuckyDefaultDecelerationTime = kLuckyDefaultAccelerationTime;

/// 默认待机慢转速度（与 speed 同单位）。
const double kLuckyDefaultIdleSpinSpeed = 2;

/// 透明背景，仍被视为有背景（FID-U12）。
const Color kLuckyTransparent = Color(0x00000000);

/// 上游默认文字颜色，也用于渐变画笔的不透明基色。
const Color kLuckyDefaultFontColor = Color(0xFF000000);

/// 上游默认字号（逻辑像素）。
const double kLuckyDefaultFontSize = 18;

/// 上游默认文字长度限制。
const LuckyLength kLuckyDefaultLengthLimit = LuckyLength.percent(90);

/// 九宫格默认激活背景。
const Color kLuckyGridActiveBackground = Color(0xFFFFCE98);

/// 九宫格默认格子间距（逻辑像素）。
const double kLuckyGridDefaultGutter = 5;

/// 九宫格默认圆角（逻辑像素）。
const double kLuckyGridDefaultBorderRadius = 20;

/// 上游老虎机默认列间距（逻辑像素）。
const double kLuckySlotDefaultColSpacing = kLuckyGridDefaultGutter;

/// 百分数的比例基准。
const double kLuckyPercentScale = 100;

/// 一个完整圆周的角度数。
const double kLuckyFullTurnDeg = 360;

/// 半圆的角度数。
const double kLuckyHalfTurnDeg = 180;

/// 直角的角度数。
const double kLuckyQuarterTurnDeg = 90;

/// 上游渐变几何的扇区宽度（度）。
const double kLuckyGradientSectorDeg = 45;

/// 八位颜色分量的最大值。
const int kLuckyMaxAlpha8 = 255;

/// 上游 Canvas 模糊半径到 sigma 的除数（DEV-03）。
const double kLuckyShadowSigmaDivisor = 2;
