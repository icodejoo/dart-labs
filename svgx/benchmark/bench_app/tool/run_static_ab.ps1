# Runs two snapshotted bench variants ALTERNATELY (A,B,A,B,...) and reports
# each memory metric side by side.
#
# Alternating rather than "N runs of A, then N runs of B" is the point: this
# machine's absolute RSS has been observed to shift ~9 MB between quiet and
# busy periods (another build running is enough), which is the same order as
# the effect a memory change is trying to prove. Interleaving spreads any drift
# over both variants instead of loading it entirely onto whichever ran second.
#
# 交替运行两个已快照的基准变体（A,B,A,B,...），并把各内存指标并排报告。
#
# 之所以交替、而不是"先跑 N 次 A 再跑 N 次 B"：这台机器的 RSS 绝对值在空闲与繁忙
# 时段之间实测能漂移约 9 MB（旁边有一个编译在跑就够了），与内存改动想证明的效应
# 同一量级。交替能把漂移摊到两个变体上，而不是全压在后跑的那个身上。
#
# Usage:
#   pwsh tool/run_static_ab.ps1 -A base -B disposed -Runs 3

param(
  [Parameter(Mandatory = $true)][string]$A,
  [Parameter(Mandatory = $true)][string]$B,
  [int]$Runs = 3
)

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$variants = @{}
foreach ($name in @($A, $B)) {
  $exe = Join-Path $root "build\bench_variants\$name\bench_app.exe"
  if (-not (Test-Path $exe)) { Write-Error "Not found: $exe (snapshot it first)"; exit 1 }
  $report = Join-Path ([System.IO.Path]::GetTempPath()) "svgx_ab_$name.txt"
  if (Test-Path $report) { Remove-Item $report }
  $variants[$name] = @{ Exe = $exe; Report = $report }
}

for ($i = 1; $i -le $Runs; $i++) {
  foreach ($name in @($A, $B)) {
    $env:SVGX_MICRO_OUT = $variants[$name].Report
    & $variants[$name].Exe | Out-Null
    Write-Host "$name run $i done"
  }
}

$keys = @(
  'rss_after_warmup_mb', 'rss_peak_mb', 'rss_steady_after_scroll_mb',
  'rss_after_idle_mb', 'rss_after_grid_unmount_mb', 'rss_after_cache_clear_mb',
  'cached_pictures', 'cached_picture_mb'
)

function Get-Metrics($path) {
  $out = @{}
  foreach ($k in $keys) { $out[$k] = @() }
  $out['build_avg_ms'] = @(); $out['raster_avg_ms'] = @()
  foreach ($line in (Get-Content $path)) {
    foreach ($k in $keys) {
      if ($line -match ("^" + [regex]::Escape($k) + "=([\d.]+)")) { $out[$k] += [double]$Matches[1] }
    }
    if ($line -match '^build\s*:\s*avg=([\d.]+)ms') { $out['build_avg_ms'] += [double]$Matches[1] }
    if ($line -match '^raster:\s*avg=([\d.]+)ms') { $out['raster_avg_ms'] += [double]$Matches[1] }
  }
  return $out
}

function Median($values) {
  if ($values.Count -eq 0) { return $null }
  $s = $values | Sort-Object
  return $s[[int]($s.Count / 2)]
}

$ma = Get-Metrics $variants[$A].Report
$mb = Get-Metrics $variants[$B].Report

Write-Host ""
Write-Host ("=== A/B OVER $Runs INTERLEAVED RUNS EACH:  A=$A   B=$B ===")
Write-Host ("{0,-28} {1,>26} {2,>26} {3,>9}" -f "metric", "A median (min~max)", "B median (min~max)", "B-A")
foreach ($k in @($keys + @('build_avg_ms', 'raster_avg_ms'))) {
  $va = $ma[$k]; $vb = $mb[$k]
  if ($va.Count -eq 0 -and $vb.Count -eq 0) { continue }
  $medA = Median $va; $medB = Median $vb
  $sa = if ($va.Count) { "{0:N2} ({1:N2}~{2:N2})" -f $medA, ($va | Measure-Object -Minimum).Minimum, ($va | Measure-Object -Maximum).Maximum } else { "-" }
  $sb = if ($vb.Count) { "{0:N2} ({1:N2}~{2:N2})" -f $medB, ($vb | Measure-Object -Minimum).Minimum, ($vb | Measure-Object -Maximum).Maximum } else { "-" }
  $delta = if ($va.Count -and $vb.Count) { "{0:N2}" -f ($medB - $medA) } else { "-" }
  Write-Host ("{0,-28} {1,26} {2,26} {3,9}" -f $k, $sa, $sb, $delta)
}
Write-Host "=== END ==="
