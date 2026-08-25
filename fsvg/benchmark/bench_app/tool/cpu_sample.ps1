# Samples bench_app.exe's CPU time once per second for DurationSec seconds,
# converting deltas to CPU% (of one logical core). Used alongside the Flutter
# profile-mode benchmark run to get a real process CPU utilization number,
# since Dart-side code cannot read whole-process CPU% cross-platform.
param(
  [int]$DurationSec = 40,
  [string]$ProcessName = "bench_app"
)
$logicalCores = [Environment]::ProcessorCount
$prevTime = $null
$prevCpu = $null
for ($i = 0; $i -lt $DurationSec; $i++) {
  $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
  $now = Get-Date
  if ($p) {
    $cpu = $p.TotalProcessorTime.TotalSeconds
    $ws = $p.WorkingSet64
    if ($prevCpu -ne $null) {
      $dt = ($now - $prevTime).TotalSeconds
      $dcpu = $cpu - $prevCpu
      $pct = [math]::Round((($dcpu / $dt) / $logicalCores) * 100, 2)
      Write-Output "$([math]::Round($now.Subtract((Get-Process -Id $PID).StartTime).TotalSeconds,1)) cpu_pct=$pct ws_mb=$([math]::Round($ws/1MB,2))"
    }
    $prevCpu = $cpu
    $prevTime = $now
  } else {
    Write-Output "no-process"
  }
  Start-Sleep -Seconds 1
}
