# Runs the already-built LIB=svgx (or LIB=flutter_svg) 1000-icon static
# benchmark exe N times and reports the distribution of the memory numbers
# across runs.
#
# Memory is the target here, not frame timing: a single RSS reading cannot
# support a claim about a memory change any more than a single build_avg can
# support one about speed, and this suite's own notes record 20%+ run-to-run
# drift on this machine. min/median/max per metric lets a change be judged
# against the spread.
#
# 把已编译好的 LIB=svgx（或 LIB=flutter_svg）千图标静态基准 exe 跑 N 次，
# 报告各次运行内存指标的分布。
#
# 这里的目标是内存而不是帧耗时：单次 RSS 读数支撑不了任何内存结论，正如单次
# build_avg 支撑不了速度结论——本套件自己的记录里，这台机器的跨运行漂移就有
# 20% 以上。逐指标的 min/median/max 才能让改动对着"波动区间"来判断。
#
# Usage:
#   flutter build windows --profile --dart-define=LIB=svgx --dart-define=AUTOEXIT=1 --dart-define=CYCLES=6 --dart-define=ITEMS=1000
#   pwsh tool/run_static.ps1 -Runs 3

param([int]$Runs = 3, [string]$ExeDir = "", [string]$Tag = "")

if ($ExeDir -eq "") {
  $ExeDir = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Profile"
}
$exe = Join-Path $ExeDir "bench_app.exe"
if (-not (Test-Path $exe)) {
  Write-Error "Not found: $exe. Build with --dart-define=LIB=svgx --dart-define=AUTOEXIT=1"
  exit 1
}

$report = Join-Path ([System.IO.Path]::GetTempPath()) "svgx_static_report$Tag.txt"
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
  Write-Host ("{0,-26} min={1,8:N2} median={2,8:N2} max={3,8:N2}  n={4}" -f `
      $name, $sorted[0], $median, $sorted[-1], $sorted.Count)
}

$metrics = [ordered]@{
  'rss_after_warmup_mb'       = @()
  'rss_peak_mb'               = @()
  'rss_steady_after_scroll_mb' = @()
  'rss_after_idle_mb'         = @()
  'rss_after_grid_unmount_mb' = @()
  'rss_after_cache_clear_mb'  = @()
}
$build = @(); $raster = @(); $parse = @()
foreach ($line in (Get-Content $report)) {
  foreach ($key in @($metrics.Keys)) {
    if ($line -match ("^" + [regex]::Escape($key) + "=([\d.]+)")) {
      $metrics[$key] += [double]$Matches[1]
    }
  }
  if ($line -match '^build\s*:\s*avg=([\d.]+)ms') { $build += [double]$Matches[1] }
  if ($line -match '^raster:\s*avg=([\d.]+)ms') { $raster += [double]$Matches[1] }
  if ($line -match '^parse\s*:\s*avg=([\d.]+)ms') { $parse += [double]$Matches[1] }
}

Write-Host ""
Write-Host "=== STATIC BENCH OVER $Runs RUNS ($report) ==="
foreach ($key in $metrics.Keys) { Show-Metric $key $metrics[$key] }
Show-Metric "build_avg_ms" $build
Show-Metric "raster_avg_ms" $raster
Show-Metric "parse_avg_ms" $parse
Write-Host "=== END ==="
