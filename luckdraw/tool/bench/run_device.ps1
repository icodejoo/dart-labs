param(
  [ValidateSet('Bench', 'Shadow')][string]$Task = 'Bench',
  [string[]]$Targets = @('wheel', 'grid', 'slot', 'lever', 'capsule', 'number_wheel', 'lots', 'lotto', 'memory'),
  [string]$Device = '10AE9K17UE0011S',
  [string]$ResultsDirectory = '',
  [switch]$ReuseBinaries
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$outputRoot = if ($ResultsDirectory) {
  (Resolve-Path -LiteralPath $ResultsDirectory).Path
} else {
  Join-Path $PSScriptRoot ('results/' + $Task.ToLower() + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force $outputRoot | Out-Null
$records = [Collections.Generic.List[object]]::new()
if ($ResultsDirectory) {
  foreach ($record in (Get-Content -Raw (Join-Path $outputRoot 'runs.json') | ConvertFrom-Json)) {
    $records.Add($record)
  }
}
$env:BENCH_DEVICE_SERIAL = $Device
$env:BENCH_DEVICE_MODEL = ((& adb -s $Device shell getprop ro.product.brand).Trim() + ' ' + (& adb -s $Device shell getprop ro.product.model).Trim())
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2'
# 从 Dart 唯一来源读取次数，拒绝脚本与设备端使用不同的 RSS 循环数。
$metricsSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'metrics.dart'))
$rssMatch = [regex]::Match($metricsSource, 'const int kRssCycles = (\d+);')
if (-not $rssMatch.Success) { throw '没有拿到 kRssCycles 唯一来源' }
$rssCycles = [int]$rssMatch.Groups[1].Value
if (@($records | Where-Object { $_.rssCycles -ne $rssCycles }).Count) {
  throw '恢复目录的 RSS 次数与 kRssCycles 不一致'
}

# 每次命令前核对资源；不终止其它会话的构建、测试或 IDE。
function Wait-Resources {
  $resourceWatch = [Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    if ($free -ge 4194304) { return $free }
    $active = @(Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'java.exe' -and $_.CommandLine -match 'C:\\ldd\\luckdraw\\.*GradleWrapperMain'
    })
    if ($active.Count -gt 0) { throw '本会话已有 Gradle 构建，拒绝重复启动' }
    $idle = @(Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'java.exe' -and $_.CommandLine -match 'HeapDumpPath=C:/ldd/dev_logs/luckdraw_dev.hprof'
    })
    foreach ($daemon in $idle) {
      [IO.File]::AppendAllText((Join-Path $outputRoot 'daemon_cleanup.log'), ($daemon | Select-Object ProcessId, ParentProcessId, CommandLine | ConvertTo-Json -Compress) + "`n", $utf8)
      Stop-Process -Id $daemon.ProcessId -ErrorAction SilentlyContinue
    }
    if ($resourceWatch.Elapsed.TotalSeconds -ge 180) { throw 'Insufficient memory before build: waited 180s' }
    Write-Host "RESOURCE_WAIT freeKB=$free stoppedOwnIdle=$($idle.ProcessId -join ',')"
    Start-Sleep -Seconds 5
  }
}

# 构建完成后释放带本副本专属标识的闲置守护进程，为宿主采集驱动留出提交内存。
function Release-OwnIdleGradle {
  $memory = Get-CimInstance Win32_OperatingSystem
  if ($memory.FreePhysicalMemory -ge 6291456 -and $memory.FreeVirtualMemory -ge 4194304) { return }
  $active = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'java.exe' -and $_.CommandLine -match 'C:\\ldd\\luckdraw\\.*GradleWrapperMain'
  })
  if ($active.Count -ne 0) { return }
  $idle = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'java.exe' -and $_.CommandLine -match 'HeapDumpPath=C:/ldd/dev_logs/luckdraw_dev.hprof'
  })
  foreach ($daemon in $idle) {
    [IO.File]::AppendAllText((Join-Path $outputRoot 'daemon_cleanup.log'), ($daemon | Select-Object ProcessId, ParentProcessId, CommandLine | ConvertTo-Json -Compress) + "`n", $utf8)
    Stop-Process -Id $daemon.ProcessId -ErrorAction SilentlyContinue
  }
}

# 保留原始电池信息；不修改温控、省电模式或其它系统设置。
function Read-Battery {
  $raw = (& adb -s $Device shell dumpsys battery) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw '读取电池失败' }
  $temperatureMatch = [regex]::Match($raw, 'temperature:\s*(\d+)')
  $levelMatch = [regex]::Match($raw, '(?m)^\s*level:\s*(\d+)')
  if (-not $temperatureMatch.Success -or -not $levelMatch.Success) { throw '没有拿到有效温度或电量，拒绝记录零值' }
  return @{
    recordedAt = (Get-Date).ToUniversalTime().ToString('o')
    temperatureC = [double]$temperatureMatch.Groups[1].Value / 10
    level = [int]$levelMatch.Groups[1].Value
    raw = $raw
  }
}

# 安全锁屏会关闭帧调度；必须在构建之前拒绝启动，不能伪造零帧性能结果。
function Test-Unlocked {
  $window = (& adb -s $Device shell dumpsys window) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $window -notmatch 'isKeyguardShowing=(true|false)') {
    throw '无法核实 isKeyguardShowing，停止采集'
  }
  return $Matches[1] -eq 'false'
}

# 安全锁屏只能由本人解除；等待期间不启动应用，最长十五分钟。
function Assert-DeviceReady {
  $unlockWatch = [Diagnostics.Stopwatch]::StartNew()
  while (-not (Test-Unlocked)) {
    if ($unlockWatch.Elapsed.TotalMinutes -ge 15) { throw 'LOCK_TIMEOUT 等待解锁十五分钟，停止采集' }
    Write-Host "LOCK_WAIT elapsed=$([int]$unlockWatch.Elapsed.TotalSeconds)s"
    Start-Sleep -Seconds 15
  }
  Write-Host 'DEVICE_READY unlocked=true'
}

# 单条 flutter drive 最多五分钟；超时仅终止本次启动的进程树。
function Invoke-Round([string]$Target, [int]$Attempt) {
  Assert-DeviceReady
  $before = Read-Battery
  while ($before.temperatureC -gt 42) {
    Write-Host "COOLING temperature=$($before.temperatureC)"
    Start-Sleep -Seconds 20
    $before = Read-Battery
  }
  $binaryDirectory = Join-Path $outputRoot 'binaries'
  $binary = Join-Path $binaryDirectory "$Target.apk"
  $binaryReused = $ReuseBinaries -and (Test-Path -LiteralPath $binary)
  # 4GiB 门槛只用于真正构建；复用本次已验证 APK 时不会启动 Gradle。
  $free = if ($binaryReused) {
    Release-OwnIdleGradle
    (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
  } else { Wait-Resources }
  $directory = Join-Path $outputRoot "${Target}_$Attempt"
  New-Item -ItemType Directory -Force $directory | Out-Null
  $env:SHADOW_OUTPUT = $directory
  & adb -s $Device shell am force-stop com.example.luckdraw_bench
  $arguments = @('drive', '--profile', '--no-pub', '--no-dds', '-d', $Device)
  if ($binaryReused) { $arguments += "--use-application-binary=$binary" }
  if ($Task -eq 'Shadow') {
    $arguments += @('--verbose', '--driver=test_driver/shadow_driver.dart', '--target=integration_test/shadow_capture_test.dart', "--dart-define=SHADOW_BACKEND=$Target")
    $arguments += $(if ($Target -eq 'skia') { '--no-enable-impeller' } else { '--enable-impeller' })
  } else {
    $arguments += @('--driver=test_driver/perf_driver.dart', "--target=integration_test/${Target}_bench_test.dart", '--dart-define=LUCKDRAW_TIMELINE=true', "--dart-define=SCENARIO=$Target")
  }
  $start = Get-Date
  $deviceLogStart = ((& adb -s $Device shell "date '+%m-%d %H:%M:%S.000'") -join '').Trim()
  Write-Host "START $Target $Attempt $($start.ToString('o')) temperature=$($before.temperatureC) freeKB=$free"
  $process = Start-Process -FilePath 'E:\sdk\flutter\bin\flutter.bat' -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $timedOut = $false
  $lockedDuring = $false
  while (-not $process.HasExited) {
    if (Select-String -Path (Join-Path $directory 'stdout.log') -Pattern 'Built build.*app-profile.apk' -Quiet) {
      Release-OwnIdleGradle
    }
    if ($watch.Elapsed.TotalSeconds -ge 300) {
      & taskkill /PID $process.Id /T /F
      $timedOut = $true
      break
    }
    Start-Sleep -Seconds 10
    if (-not (Test-Unlocked)) {
      & taskkill /PID $process.Id /T /F
      $lockedDuring = $true
      break
    }
    $process.Refresh()
    Write-Host "RUNNING $Target $Attempt elapsed=$([int]$watch.Elapsed.TotalSeconds)s"
    Get-Content (Join-Path $directory 'stdout.log') -Tail 2 | ForEach-Object { Write-Host $_ }
    Get-Content (Join-Path $directory 'stderr.log') -Tail 2 | ForEach-Object { Write-Host $_ }
  }
  $process.WaitForExit()
  $after = Read-Battery
  $code = if ($timedOut -or $lockedDuring) { -1 } else { $process.ExitCode }
  $summaries = @()
  $valid = $code -eq 0
  if ($Task -eq 'Bench') {
    $summaries = @(Get-ChildItem (Join-Path $PSScriptRoot 'build') -File -Filter '*.timeline_summary.json' |
      Where-Object { $_.LastWriteTimeUtc -ge $start.ToUniversalTime() })
    if ($summaries.Count -eq 0) { $valid = $false }
    foreach ($file in $summaries) {
      $data = Get-Content -Raw $file.FullName | ConvertFrom-Json
      if ($data.report_key -eq 'reference_spin' -or $data.report_key -eq 'wheel_first_frame') { continue }
      if ($data.rss_cycles -ne $rssCycles -or @($data.rss_pages).Count -ne $rssCycles -or @($data.rss_blank).Count -ne $rssCycles) { $valid = $false }
      if ($data.report_key -ne 'memory_cycles' -and ($data.fps -le 0 -or $data.frame_count -le 0)) { $valid = $false }
    }
  } else {
    if (-not (Test-Path (Join-Path $directory 'metadata.json')) -or
        -not (Test-Path (Join-Path $directory "shadow_$Target.png"))) { $valid = $false }
  }
  $records.Add(@{
    target = $Target; attempt = $Attempt; startedAt = $start.ToUniversalTime().ToString('o')
    endedAt = (Get-Date).ToUniversalTime().ToString('o'); elapsedMs = $watch.ElapsedMilliseconds
    exitCode = $code; timedOut = $timedOut; before = $before; after = $after; freeKB = $free
    command = 'flutter ' + ($arguments -join ' '); directory = Split-Path $directory -Leaf
    deviceLogStart = $deviceLogStart
    unlockedBefore = $true
    lockedDuring = $lockedDuring; valid = $valid; rssCycles = $rssCycles
    binaryReused = $binaryReused
  })
  if ($valid -and $ReuseBinaries -and -not $binaryReused) {
    New-Item -ItemType Directory -Force $binaryDirectory | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build/app/outputs/flutter-apk/app-profile.apk') -Destination $binary
  }
  if ($Task -eq 'Bench' -and (Test-Path (Join-Path $PSScriptRoot 'build'))) {
    Get-ChildItem (Join-Path $PSScriptRoot 'build') -File -Filter '*.timeline*.json' |
      Where-Object { $_.LastWriteTimeUtc -ge $start.ToUniversalTime() } |
      ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $directory }
  }
  $logcat = (& adb -s $Device logcat -d -v threadtime -T $deviceLogStart -s flutter) -join "`n"
  [IO.File]::WriteAllText((Join-Path $directory 'flutter_logcat.log'), $logcat + "`n", $utf8)
  [IO.File]::WriteAllText((Join-Path $outputRoot 'runs.json'), ($records.ToArray() | ConvertTo-Json -Depth 10) + "`n", $utf8)
  Write-Host "FINISHED $Target $Attempt code=$code elapsedMs=$($watch.ElapsedMilliseconds) temperature=$($after.temperatureC)"
  return $valid
}

try {
  & adb -s $Device shell svc power stayon usb
  if ($Task -eq 'Shadow') { $Targets = @('skia', 'impeller') }
  foreach ($target in $Targets) {
    $previous = @($records | Where-Object target -eq $target)
    $validCount = @($previous | Where-Object valid).Count
    if ($validCount -eq 3) { Write-Host "REUSE $target 3/3"; continue }
    if ($validCount -gt 3) { throw '已有有效轮超过三次，拒绝继续' }
    $memoryFailures = 0
    foreach ($attempt in 1..5) {
      if ($attempt -le $previous.Count) { continue }
      $result = @(Invoke-Round $target $attempt)
      $result | Where-Object { $_ -isnot [bool] } | ForEach-Object { Write-Host $_ }
      if ($result[-1] -eq $true) { $validCount++ }
      $last = $records[$records.Count - 1]
      $errorLog = Get-Content -Raw (Join-Path $outputRoot ($last.directory + '/stderr.log'))
      if ($errorLog -match 'Insufficient memory|Could not reserve virtual memory|页面文件太小|OS error code: 1455') { $memoryFailures++ }
      if ($validCount -eq 3 -or $memoryFailures -ge 3) { break }
    }
    Write-Host "VALID $target $validCount/3"
  }
} finally {
  & adb -s $Device shell svc power stayon false
  Remove-Item Env:SHADOW_OUTPUT -ErrorAction SilentlyContinue
  Remove-Item Env:BENCH_DEVICE_SERIAL -ErrorAction SilentlyContinue
  Remove-Item Env:BENCH_DEVICE_MODEL -ErrorAction SilentlyContinue
}
Write-Output "REPORT $outputRoot"
if (@($records | Group-Object target | Where-Object { @($_.Group | Where-Object valid).Count -ne 3 }).Count -gt 0) { exit 1 }
