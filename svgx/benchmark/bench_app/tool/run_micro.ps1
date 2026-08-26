# Runs the already-built LIB=micro benchmark exe N times and reports, per
# metric, the minimum across all runs.
#
# Why min-of-N-runs: `micro_bench.dart` already takes the min across trials
# inside one process, but the paint-shaped benchmarks still swing ~20% between
# processes on this machine (background load, heap layout). Noise only ever
# adds time, so the minimum over repeated processes converges downward to the
# true cost. Running the built exe directly instead of `flutter run` avoids a
# recompile per repetition.
#
# 把已编译好的 LIB=micro 基准 exe 跑 N 次，逐指标报告全部运行里的最小值。
#
# 为什么要跨进程取最小值：`micro_bench.dart` 已经在单个进程内跨轮次取了最小值，
# 但绘制型基准在本机跨进程仍有约 20% 的波动（后台负载、堆布局）。噪声只会增加
# 耗时，所以对重复进程取最小值会自下方收敛到真实开销。直接跑编译好的 exe（而不是
# `flutter run`）可以省掉每次重复的重新编译。
#
# Usage: pwsh tool/run_micro.ps1 [-Runs 8]

param([int]$Runs = 8)

$exe = Join-Path $PSScriptRoot "..\build\windows\x64\runner\Profile\bench_app.exe"
if (-not (Test-Path $exe)) {
  Write-Error "Build first: flutter run -d windows --profile --dart-define=LIB=micro"
  exit 1
}

$best = [ordered]@{}
for ($i = 1; $i -le $Runs; $i++) {
  $out = & $exe 2>$null
  foreach ($line in $out) {
    if ($line -match '^(?<name>\w+): min=(?<min>[\d.]+)us/unit') {
      $name = $Matches['name']
      $val = [double]$Matches['min']
      if (-not $best.Contains($name) -or $val -lt $best[$name]) { $best[$name] = $val }
    }
  }
  Write-Host "run $i done"
}

Write-Host ""
Write-Host "=== MICRO BEST-OF-$Runs (us/unit) ==="
foreach ($k in $best.Keys) {
  Write-Host ("{0,-38} {1,9:N3}" -f $k, $best[$k])
}
Write-Host "=== END MICRO BEST-OF-$Runs ==="
