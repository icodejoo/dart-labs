param(
  [string[]]$Variants = @('wheel_picture', 'wheel_raster', 'wheel_no_text', 'wheel_no_images'),
  [string]$Results = 'results/perf_ablation',
  [int]$Repetitions = 3,
  [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
$device = '10AE9K17UE0011S'
$utf8 = [Text.UTF8Encoding]::new($false)
$flutter = (Get-Command flutter.bat).Source
$workspacePattern = [regex]::Escape($PSScriptRoot)
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Results))
New-Item -ItemType Directory -Force $root | Out-Null
$binary = Join-Path $root 'perf.apk'
$records = [Collections.Generic.List[object]]::new()
if (Test-Path (Join-Path $root 'runs.json')) {
  foreach ($record in (Get-Content -Raw (Join-Path $root 'runs.json') | ConvertFrom-Json)) { $records.Add($record) }
}
$env:BENCH_DEVICE_SERIAL = $device
$env:BENCH_DEVICE_MODEL = 'vivo V2417'
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2'

# 只识别本次采集持有的手机，锁屏最长等待十五分钟。
function Test-Unlocked {
  $window = (& adb -s $device shell dumpsys window) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $window -notmatch 'isKeyguardShowing=(true|false)') { throw '无法核实锁屏状态' }
  return $Matches[1] -eq 'false'
}

foreach ($variant in $Variants) {
  $wanted = if ($variant -in @('wheel_no_text', 'wheel_no_images', 'wheel_capture')) { 1 } else { $Repetitions }
  $prior = @($records | Where-Object variant -eq $variant)
  $validCount = @($prior | Where-Object valid).Count
  if ($validCount -ge $wanted) { continue }
  foreach ($attempt in 1..5) {
    if (@($prior | Where-Object attempt -eq $attempt).Count) { continue }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Unlocked)) {
      if ($watch.Elapsed.TotalMinutes -ge 15) { throw 'LOCK_TIMEOUT 等待解锁十五分钟' }
      Write-Host 'LOCK_WAIT'
      Start-Sleep -Seconds 15
    }
    $reused = (Test-Path -LiteralPath $binary) -and -not $Rebuild
    $free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    if (-not $reused -and $free -lt 4194304) { throw "构建前可用内存不足4GiB: $free KiB" }
    $active = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $workspacePattern -and $_.CommandLine -match 'GradleWrapperMain' })
    if (-not $reused -and $active.Count) { throw '副本已有构建，拒绝重复启动' }
    $batteryBefore = ((& adb -s $device shell dumpsys battery) -join "`n")
    $temperature = [regex]::Match($batteryBefore, 'temperature:\s*(\d+)')
    if (-not $temperature.Success -or [int]$temperature.Groups[1].Value -gt 420) { throw '温度无效或超过42度' }
    $directory = Join-Path $root "${variant}_$attempt"
    New-Item -ItemType Directory -Force $directory | Out-Null
    $env:BENCH_PERF_OUTPUT = $directory
    & adb -s $device shell am force-stop com.example.luckdraw_bench
    $arguments = @('drive', '--profile', '--no-pub', '--no-dds', '-d', $device,
      '--driver=test_driver/perf_driver.dart', '--target=integration_test/perf_bench_test.dart',
      '--dart-define=LUCKDRAW_TIMELINE=true', "--route=/$variant")
    if ($reused) { $arguments += "--use-application-binary=$binary" }
    $start = Get-Date
    $logStart = ((& adb -s $device shell "date '+%m-%d %H:%M:%S.000'") -join '').Trim()
    Write-Host "START $variant $attempt reused=$reused freeKB=$free"
    $process = Start-Process -FilePath $flutter -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
    $watch.Restart()
    $locked = $false
    $timeout = $false
    while (-not $process.HasExited) {
      if ($watch.Elapsed.TotalSeconds -ge 300) { $timeout = $true; & taskkill /PID $process.Id /T /F; break }
      if (-not (Test-Unlocked)) { $locked = $true; & taskkill /PID $process.Id /T /F; break }
      Write-Host "RUNNING $variant $attempt elapsed=$([int]$watch.Elapsed.TotalSeconds)s"
      Get-Content (Join-Path $directory 'stdout.log') -Tail 2
      Start-Sleep -Seconds 10
      $process.Refresh()
    }
    $process.WaitForExit()
    $code = if ($locked -or $timeout) { -1 } else { $process.ExitCode }
    $files = @(Get-ChildItem (Join-Path $PSScriptRoot 'build') -File -Filter '*.timeline*.json' | Where-Object LastWriteTimeUtc -ge $start.ToUniversalTime())
    $summaries = @($files | Where-Object Name -like '*.timeline_summary.json')
    $valid = $code -eq 0 -and $summaries.Count -ge 2
    if ($variant -eq 'wheel_capture') {
      $valid = $code -eq 0 -and (Test-Path (Join-Path $directory 'capture_metadata.json'))
    }
    foreach ($file in $summaries) {
      $data = Get-Content -Raw $file.FullName | ConvertFrom-Json
      if ($data.report_key -eq 'reference_spin') { continue }
      if ($data.frame_count -le 0 -or $data.fps -le 0 -or $data.rss_cycles -ne 5) { $valid = $false }
    }
    if ($valid -and -not $reused) {
      Copy-Item (Join-Path $PSScriptRoot 'build/app/outputs/flutter-apk/app-profile.apk') $binary
      $Rebuild = $false
    }
    foreach ($file in $files) { Move-Item -LiteralPath $file.FullName -Destination $directory }
    [IO.File]::WriteAllText((Join-Path $directory 'flutter_logcat.log'), ((& adb -s $device logcat -d -v threadtime -T $logStart -s flutter) -join "`n") + "`n", $utf8)
    $records.Add(@{ variant = $variant; attempt = $attempt; startedAt = $start.ToUniversalTime().ToString('o'); endedAt = (Get-Date).ToUniversalTime().ToString('o'); valid = $valid; exitCode = $code; lockedDuring = $locked; timedOut = $timeout; unlockedBefore = $true; freeKB = $free; binaryReused = $reused; elapsedMs = $watch.ElapsedMilliseconds; batteryBefore = $batteryBefore; batteryAfter = ((& adb -s $device shell dumpsys battery) -join "`n"); command = 'flutter ' + ($arguments -join ' '); directory = Split-Path $directory -Leaf })
    [IO.File]::WriteAllText((Join-Path $root 'runs.json'), ($records.ToArray() | ConvertTo-Json -Depth 10) + "`n", $utf8)
    Write-Host "FINISHED $variant $attempt valid=$valid code=$code"
    if ($valid) { $validCount++ }
    if ($validCount -eq $wanted) { break }
    if ($timeout -or ($code -ne 0 -and -not $locked)) { throw "轮次失败，先诊断：$directory" }
  }
  if ($validCount -ne $wanted) { throw "$variant 未获得规定有效轮数" }
}
