# Runs an already-installed profile APK of the LIB=anim_fps benchmark on a real
# Android device N times, scraping each run's report out of logcat, and prints
# the min/median/max distribution per metric.
#
# Why logcat rather than a file: on Android the benchmark's `emitReport` `print`
# lands in logcat under the `flutter` tag, and `SVGX_MICRO_OUT` cannot be set
# for an activity launched via `am start`. Why a distribution rather than one
# number: this phase is the noisiest in the suite (see tool/run_anim_fps.ps1),
# so a single sample cannot support a claim.
#
# 在真机上把已安装好的 LIB=anim_fps 基准 profile APK 跑 N 次，从 logcat 抓取每次
# 运行的报告，并逐指标打印 min/median/max 分布。
#
# 为什么用 logcat 而不是文件：Android 上基准 `emitReport` 的 `print` 会落到
# logcat 的 `flutter` tag，而经 `am start` 启动的 activity 无法设置
# `SVGX_MICRO_OUT`。为什么要分布而非单个数字：本阶段是整套基准里噪声最大的
# （见 tool/run_anim_fps.ps1），单次采样无法支撑结论。
#
# Usage:
#   fvm flutter build apk --profile --dart-define=LIB=anim_fps --dart-define=ITEMS=1000 --dart-define=AUTOEXIT=1
#   adb install -r build/app/outputs/flutter-apk/app-profile.apk
#   pwsh tool/run_android_anim_fps.ps1 -Runs 5 -Label baseline

param(
  [int]$Runs = 5,
  [string]$Serial = "7NQBB23606003715",
  [string]$Package = "com.example.bench_app",
  [string]$Label = "run"
)

$activity = "$Package/.MainActivity"
$all = @()

for ($i = 1; $i -le $Runs; $i++) {
  & adb -s $Serial shell am force-stop $Package | Out-Null
  & adb -s $Serial logcat -c
  & adb -s $Serial shell am start -n $activity | Out-Null

  # Poll logcat for the report terminator instead of sleeping a fixed amount:
  # the run length varies with device thermal state.
  #
  # 轮询 logcat 等报告结束标记，而不是固定 sleep：运行时长随设备温度状态变化。
  $deadline = (Get-Date).AddSeconds(180)
  $text = ""
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $text = (& adb -s $Serial logcat -d -s flutter:I) -join "`n"
    if ($text -match 'END ANIM FPS BENCH REPORT') { break }
  }
  if ($text -notmatch 'END ANIM FPS BENCH REPORT') {
    Write-Host "run $i TIMED OUT (no report)"
    continue
  }
  $all += $text
  $fpsLine = ($text -split "`n" | Where-Object { $_ -match 'real_fps=' }) -join " "
  Write-Host "run $i : $fpsLine"
}

& adb -s $Serial shell am force-stop $Package | Out-Null

function Show-Metric($name, $values) {
  if ($values.Count -eq 0) { return }
  $sorted = $values | Sort-Object
  $median = $sorted[[int]($sorted.Count / 2)]
  Write-Host ("{0,-12} min={1,8:N3} median={2,8:N3} max={3,8:N3}  n={4}" -f `
      $name, $sorted[0], $median, $sorted[-1], $sorted.Count)
}

$fps = @(); $build = @(); $raster = @(); $over83 = @(); $peak = @()
foreach ($line in ($all -join "`n") -split "`n") {
  if ($line -match 'real_fps=([\d.]+)') { $fps += [double]$Matches[1] }
  if ($line -match 'build\s*:\s*avg=([\d.]+)ms') { $build += [double]$Matches[1] }
  if ($line -match 'raster:\s*avg=([\d.]+)ms') { $raster += [double]$Matches[1] }
  if ($line -match 'framesOver8\.3ms=(\d+)') { $over83 += [double]$Matches[1] }
  if ($line -match 'rss_peak_mb=([\d.]+)') { $peak += [double]$Matches[1] }
}

Write-Host ""
Write-Host "=== ANDROID ANIM FPS [$Label] OVER $Runs RUNS ==="
Show-Metric "real_fps" $fps
Show-Metric "build_avg" $build
Show-Metric "raster_avg" $raster
Show-Metric "over8.3ms" $over83
Show-Metric "rss_peak_mb" $peak
Write-Host "=== END ==="
