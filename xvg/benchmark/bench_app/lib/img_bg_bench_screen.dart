// Persistent foreground/background probe for animated SVG ImageProviders.
// Compare MODE=provider (default) with MODE=widget using the same four SVGs.
// This page never exits itself; lifecycle observation never pauses playback.
// SVG ImageProvider 前后台常驻探针：默认 provider，与 widget 模式共用四份 SVG。
// 页面不自动退出；生命周期观察代码不主动暂停动画。
//
// Android reproduction, run by the device operator from benchmark/bench_app.
// Android 复现命令，由真机操作者在 benchmark/bench_app 目录执行：
//   flutter build apk --profile --target-platform android-arm64 --dart-define=LIB=img_bg --dart-define=MODE=provider
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
// In another terminal, correlate IMGBG lifecycle/heartbeat lines with CPU.
// 另开终端，用 IMGBG 生命周期和心跳日志对照 CPU：
//   adb -s 7NQBB23606003715 logcat -s flutter:I
//
// External PowerShell CPU sampler; warm up in the foreground before sampling.
// /proc/<pid>/stat fields 14/15 are utime/stime; CLK_TCK=100 ticks/second.
// Strip through the final ')' first: comm may contain spaces. The remaining
// fields start at field 3, so indexes 11/12 select fields 14/15.
// 外部 PowerShell CPU 采样脚本，先在前台预热；第 14/15 字段是 utime/stime，
// CLK_TCK=100。先去掉最后一个 ')' 及之前内容，避免进程名的空格干扰；剩余从
// 第 3 字段开始，因此下标 11/12 对应第 14/15 字段。
//   $deviceSerial = '7NQBB23606003715'
//   $packageName = 'com.example.bench_app'
//   $appPid = [int](& adb -s $deviceSerial shell pidof -s $packageName)
//   function Read-CpuTicks {
//     $rawStat = (& adb -s $deviceSerial shell run-as $packageName cat "/proc/$appPid/stat") -join ' '
//     if ($LASTEXITCODE -ne 0) { throw $rawStat }
//     $fields = $rawStat.Substring($rawStat.LastIndexOf(')') + 2).Trim() -split '\s+'
//     return ([long]$fields[11] + [long]$fields[12])
//   }
//   function Measure-Cpu([string]$phase) {
//     $ticksBefore = Read-CpuTicks
//     $watch = [Diagnostics.Stopwatch]::StartNew()
//     Start-Sleep -Seconds 20
//     $ticksAfter = Read-CpuTicks
//     $watch.Stop()
//     $cpuSeconds = ($ticksAfter - $ticksBefore) / 100.0
//     $cpuPercent = 100.0 * $cpuSeconds / $watch.Elapsed.TotalSeconds
//     "phase=$phase pid=$appPid cpu_s=$cpuSeconds cpu_pct=$cpuPercent"
//   }
//   Start-Sleep -Seconds 5
//   Measure-Cpu 'foreground'
//   adb -s $deviceSerial shell input keyevent KEYCODE_HOME
//   Start-Sleep -Seconds 5
//   Measure-Cpu 'background'
//   adb -s $deviceSerial shell am start -n com.example.bench_app/.MainActivity
//   Start-Sleep -Seconds 5
//   Measure-Cpu 'foreground-return'
// Verify pidof still matches $appPid throughout; discard runs if restarted.
// If permitted, plain `adb shell cat /proc/<pid>/stat` can replace run-as.
// CPU% is relative to one core. Heartbeats add small overhead; completed-frame
// counts are not toImage counts, so use CPU deltas as the independent signal.
// Repeat with MODE=widget after rebuilding/installing, using a fresh process.
// 全程确认 pidof 仍等于 $appPid；进程重启则丢弃该轮。若权限允许，可用普通
// adb shell cat 代替 run-as。CPU 百分比以单核为基准；心跳有少量开销，完成帧数
// 不等于 toImage 次数，须结合 CPU 增量判断。改为 MODE=widget 重新构建安装，
// 使用新进程重复上述步骤。

// Log directly for logcat collection. / 直接打印，供 logcat 采集。
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:xvg/xvg.dart';

const _providerMode = 'provider';
const _widgetMode = 'widget';
const _mode = String.fromEnvironment('MODE', defaultValue: _providerMode);
const _logPrefix = 'IMGBG';
const _heartbeatInterval = Duration(milliseconds: 2000);
const _tileSize = 192.0;
const _columns = 2;
const _tileCount = _columns * _columns;
const _gap = 12.0;
const _padding = 16.0;
const _gridSize = _tileSize * _columns + _gap;

// Continuous asymmetric rotation, translation and color interpolation ensure
// every playback sample changes; nested groups avoid transform replacement.
// 非对称图形持续旋转、平移及颜色插值，保证播放采样持续变化；嵌套分组避免变换覆盖。
const _animatedSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <defs>
    <linearGradient id="backdrop" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#10243a"/>
      <stop offset="1" stop-color="#284b63"/>
    </linearGradient>
  </defs>
  <rect width="192" height="192" rx="18" fill="url(#backdrop)"/>
  <g fill="none" stroke="#7393ad" stroke-width="2">
    <circle cx="96" cy="96" r="78"/>
    <circle cx="96" cy="96" r="56"/>
    <path d="M16 96H176M96 16V176M40 40L152 152M40 152L152 40"/>
  </g>
  <g>
    <animateTransform attributeName="transform" type="rotate"
      from="0 96 96" to="360 96 96" dur="4s" repeatCount="indefinite"/>
    <path d="M96 28C142 28 164 64 152 108L122 94C130 64 116 50 96 50Z"
      fill="#38bdf8">
      <animate attributeName="fill" values="#38bdf8;#fb7185;#facc15;#38bdf8"
        dur="6s" repeatCount="indefinite"/>
    </path>
    <rect x="58" y="103" width="30" height="46" rx="6" fill="#a78bfa"/>
    <circle cx="132" cy="120" r="13" fill="#f8fafc"/>
    <path d="M52 70L72 52L80 84Z" fill="#34d399"/>
  </g>
  <g>
    <animateTransform attributeName="transform" type="translate"
      values="-22 0;22 0;-22 0" dur="3s" repeatCount="indefinite"/>
    <circle cx="96" cy="96" r="12" fill="#f97316" stroke="#ffffff" stroke-width="3">
      <animate attributeName="fill" values="#f97316;#22d3ee;#f97316"
        dur="2s" repeatCount="indefinite"/>
    </circle>
  </g>
</svg>
''';

/// Stays mounted for externally controlled lifecycle measurements.
/// 保持挂载，由外部操作者控制生命周期测量。
class ImgBgBenchScreen extends StatefulWidget {
  const ImgBgBenchScreen({super.key});

  @override
  State<ImgBgBenchScreen> createState() => _ImgBgBenchScreenState();
}

class _ImgBgBenchScreenState extends State<ImgBgBenchScreen>
    with WidgetsBindingObserver {
  final _watch = Stopwatch();
  AppLifecycleState? _lifecycle;
  late final Timer _heartbeat;
  int _framesDrawn = 0;

  String get _lifecycleLabel => _lifecycle?.name ?? 'unknown';

  @override
  void initState() {
    super.initState();
    if (_mode != _providerMode && _mode != _widgetMode) {
      throw ArgumentError.value(_mode, 'MODE', 'Use provider or widget');
    }
    _watch.start();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _logLifecycle();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      // Never request a frame from the probe. / 探针本身不请求新帧。
      print(
        '$_logPrefix heartbeat mode=$_mode frames=$_framesDrawn '
        'lifecycle=$_lifecycleLabel',
      );
    });
  }

  void _onTimings(List<FrameTiming> timings) {
    _framesDrawn += timings.length;
  }

  void _logLifecycle() {
    print(
      '$_logPrefix lifecycle=$_lifecycleLabel t=${_watch.elapsedMilliseconds}',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _lifecycle = state);
    _logLifecycle();
  }

  @override
  void dispose() {
    _heartbeat.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _watch.stop();
    super.dispose();
  }

  Widget _buildTile(int index) {
    if (_mode == _widgetMode) {
      return const XvgAnimated.string(
        _animatedSvg,
        width: _tileSize,
        height: _tileSize,
      );
    }
    // Identical providers intentionally share Flutter's normal ImageCache key.
    // 相同 provider 有意沿用 Flutter 的正常 ImageCache 键共享行为。
    return const Image(
      image: StringXvg(_animatedSvg, width: _tileSize, height: _tileSize),
      width: _tileSize,
      height: _tileSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$_logPrefix / $_mode')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Column(
            children: [
              Text('AppLifecycleState: $_lifecycleLabel'),
              const Text('常驻页面，请手动切换前后台 / Switch apps manually'),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox.square(
                      dimension: _gridSize,
                      child: GridView.count(
                        crossAxisCount: _columns,
                        mainAxisSpacing: _gap,
                        crossAxisSpacing: _gap,
                        padding: EdgeInsets.zero,
                        physics: const NeverScrollableScrollPhysics(),
                        children: List.generate(_tileCount, _buildTile),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
