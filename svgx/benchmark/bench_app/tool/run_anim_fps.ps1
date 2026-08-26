# Runs the already-built LIB=anim_fps benchmark exe N times and reports the
# distribution of real_fps / build_avg / raster_avg across runs.
#
# The 1000-animated-icon phase is the noisiest thing in this suite (its
# raster_max alone has been observed between 85ms and 99ms on identical code),
# so a single sample cannot support any claim about it. This prints min/median/
# max per metric so a change can be judged against the spread rather than
# against one number.
#
# 把已编译好的 LIB=anim_fps 基准 exe 跑 N 次，报告各次运行 real_fps /
# build_avg / raster_avg 的分布。
#
# 1000 动画图标这一阶段是整套基准里噪声最大的（同一份代码下仅 raster_max 就观测到
# 85ms 到 99ms 的区间），单次采样无法支撑关于它的任何结论。这里逐指标打印
# min/median/max，使改动能对着"波动区间"而不是"一个数字"来判断。
#
# Usage:
#   flutter build windows --profile --dart-define=LIB=anim_fps --dart-define=AUTOEXIT=1
#   pwsh tool/run_anim_fps.ps1 -Runs 5

param([int]$Runs = 5, [string]$ExeDir = "")

if ($ExeDir -eq "") {
  $ExeDir = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Profile"
}
$exe = Join-Path $ExeDir "bench_app.exe"
if (-not (Test-Path $exe)) {
  Write-Error "Not found: $exe. Build with --dart-define=LIB=anim_fps --dart-define=AUTOEXIT=1"
  exit 1
}

$report = Join-Path ([System.IO.Path]::GetTempPath()) "svgx_anim_fps_report.txt"
if (Test-Path $report) { Remove-Item $report }
$env:SVGX_MICRO_OUT = $report

for ($i = 1; $i -le $Runs; $i++) {
  & $exe | Out-Null
  Write-Host "run $i done"
}

function Show-Metric($name, $values) {
  if ($values.Count -eq 0) { return }
  $sorted = $values | Sort-Object
  $median = $sorted[[int]($sorted.Count / 2)]
  Write-Host ("{0,-12} min={1,8:N3} median={2,8:N3} max={3,8:N3}  n={4}" -f `
      $name, $sorted[0], $median, $sorted[-1], $sorted.Count)
}

$fps = @(); $build = @(); $raster = @(); $over83 = @()
foreach ($line in (Get-Content $report)) {
  if ($line -match 'real_fps=([\d.]+)') { $fps += [double]$Matches[1] }
  if ($line -match '^build\s*:\s*avg=([\d.]+)ms') { $build += [double]$Matches[1] }
  if ($line -match '^raster:\s*avg=([\d.]+)ms') { $raster += [double]$Matches[1] }
  if ($line -match 'framesOver8\.3ms=(\d+)') { $over83 += [double]$Matches[1] }
}

Write-Host ""
Write-Host "=== ANIM FPS OVER $Runs RUNS ==="
Show-Metric "real_fps" $fps
Show-Metric "build_avg" $build
Show-Metric "raster_avg" $raster
Show-Metric "over8.3ms" $over83
Write-Host "=== END ==="
