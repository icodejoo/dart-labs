<#
INSTR：按 Scenes 选择项目，各3轮、最多5次启动；使用已构建APK。
冷push wheel/grid 与 /proc CPU 首尾差分；不做窗口内轮询。
必须提供含 pending_bench_test.dart 新入口的已构建 profile APK，始终 use-application-binary。
不构建、不调用 Gradle、不改亮度/常亮/锁屏等手机设置。需用户预先保持亮屏未锁屏。
每项失败尝试也计入最多5次启动；仅成本未污染不足两轮时补样，不挑好轮替换坏轮。
窗口内只有两次CPU边界快照，无其它adb轮询；锁屏/温度检查只在启动前和结束后。
示例（包根）：
  ./tool/bench/run_instr_device_checks.ps1 -DeviceSerial <serial> -ApplicationBinary <新入口profile.apk>
#>
param(
  [Parameter(Mandatory)][string]$DeviceSerial,
  [Parameter(Mandatory)][string]$ApplicationBinary,
  [string]$ResultsDirectory = 'results/pending2/before',
  [string[]]$Scenes = @('wheel_first_frame','grid_first_frame'),
  [switch]$Resume,
  [switch]$PlanOnly
)

if ($PlanOnly) {
  @{ first_frames = @($Scenes | Where-Object { $_ -notlike 'cpu_*' })
     cpu = @($Scenes | Where-Object { $_ -like 'cpu_*' })
     retests = @()
     rounds = 3; max_starts = 5; initial_starts = 3 * $Scenes.Count; settings_modified = $false; binary_required = $true } | ConvertTo-Json
  return
}

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$packageName = 'com.example.luckdraw_bench'
$cpuPort = 41237
$binary = (Resolve-Path -LiteralPath $ApplicationBinary).Path
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw 'APK不存在' }
$binaryHash = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ResultsDirectory))
if ((Test-Path -LiteralPath $root) -and -not $Resume) { throw '本轮目录已存在；只有 -Resume 可保留并累计原始启动次数' }
$records = [Collections.Generic.List[object]]::new()
if ($Resume) { foreach ($prior in (Get-Content -Raw (Join-Path $root 'runs.json') | ConvertFrom-Json -AsHashtable)) { $records.Add($prior) } }
$flutter = (Get-Command flutter.bat).Source
$dart = (Get-Command dart.bat).Source

function Invoke-Device([string[]]$Arguments) {
  $output = & adb -s $DeviceSerial @Arguments
  if ($LASTEXITCODE -ne 0) { throw "adb失败: $($Arguments -join ' ')" }
  return $output -join "`n"
}

function Wait-Ready {
  if ((Invoke-Device @('get-state')).Trim() -ne 'device') { throw '指定设备不在线' }
  if ((Invoke-Device @('shell', 'getprop', 'ro.kernel.qemu')).Trim() -eq '1') { throw '拒绝模拟器' }
  $timer = [Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $power = Invoke-Device @('shell', 'dumpsys', 'power')
    $window = Invoke-Device @('shell', 'dumpsys', 'window')
    if ($power -notmatch 'mWakefulness=(Awake|Asleep|Dozing|Dreaming)' -or
        $window -notmatch 'isKeyguardShowing=(true|false)') { throw '无法核实亮屏/锁屏状态' }
    $awake = $power -match 'mWakefulness=Awake'
    $unlocked = $window -match 'isKeyguardShowing=false'
    if ($awake -and $unlocked) { break }
    if ($timer.Elapsed.TotalMinutes -ge 15) { throw '等待亮屏解锁超过15分钟' }
    Write-Host '等待用户保持亮屏并解锁；不修改设置'
    Start-Sleep -Seconds 15
  }
  $freeKB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
  if ($freeKB -lt 4194304) { throw "主机FreePhysicalMemory不足4GiB: $freeKB KiB" }
  $battery = Invoke-Device @('shell', 'dumpsys', 'battery')
  if ($battery -notmatch 'temperature:\s*(\d+)' -or [int]$Matches[1] -gt 420) { throw '温度未知或超过42°C，等待降温后另开新目录' }
}

# 仅结束本脚本直接启动的已知进程树，不按进程名清理用户进程。
function Stop-OwnedTree($Process) {
  if ($null -ne $Process -and -not $Process.HasExited) {
    & taskkill /PID $Process.Id /T /F | Out-Null
    $Process.WaitForExit()
  }
}

Wait-Ready
if (-not $Resume) { New-Item -ItemType Directory -Path $root | Out-Null }
$env:BENCH_DEVICE_SERIAL = $DeviceSerial
$env:BENCH_DEVICE_MODEL = (Invoke-Device @('shell', 'getprop', 'ro.product.model')).Trim()
$firstFrames = @($Scenes | Where-Object { $_ -notlike 'cpu_*' })
$cpuScenes = @($Scenes | Where-Object { $_ -like 'cpu_*' })
$retests = @()
if (-not $Resume) { [IO.File]::WriteAllText((Join-Path $root 'session.json'), (@{
  serial = $DeviceSerial; model = $env:BENCH_DEVICE_MODEL; binary = $binary; binary_sha256 = $binaryHash
  android = (Invoke-Device @('shell', 'getprop', 'ro.build.version.release')).Trim()
  started_at = (Get-Date).ToUniversalTime().ToString('o'); phone_settings_modified = $false
  source_sha256 = (Get-ChildItem (Join-Path $PSScriptRoot 'integration_test') -Filter '*.dart' | ForEach-Object { @{ name = $_.Name; hash = (Get-FileHash $_.FullName).Hash } })
} | ConvertTo-Json -Depth 8) + "`n", $utf8) }

Push-Location $PSScriptRoot
try {
  foreach ($scene in @($firstFrames + $cpuScenes + $retests)) {
    $prior = @($records | Where-Object scene -eq $scene)
    $valid = @($prior | Where-Object { $_.valid -and (-not $_.ContainsKey('cpu') -or $_.cpu.ContainsKey('process_cpu_percent')) }).Count
    $clean = 0
    $isCpu = $scene -in $cpuScenes
    $isRetest = $scene -in $retests
    $attempts = @(1..5 | Where-Object { $_ -gt $prior.Count })
    foreach ($attempt in $attempts) {
      if ($valid -ge 3 -and (-not $isRetest -or $clean -ge 2)) { break }
      Wait-Ready
      $relative = "${scene}_$attempt"
      $directory = Join-Path $root $relative
      New-Item -ItemType Directory -Path $directory | Out-Null
      $env:BENCH_PERF_OUTPUT = $directory
      Invoke-Device @('shell', 'am', 'force-stop', $packageName) | Out-Null
      $cpuProcess = $null
      $driveProcess = $null
      $reversed = $false
      $started = Get-Date
      $ok = $false
      $errorText = $null
      # 启动之前落盘；中断也消耗一次启动，不会在下次运行重置为零。
      $record = @{ scene = $scene; attempt = $attempt; directory = $relative; valid = $false
        binary_sha256 = $binaryHash; started_at = $started.ToUniversalTime().ToString('o') }
      $records.Add($record)
      [IO.File]::WriteAllText((Join-Path $root 'runs.json'), (ConvertTo-Json -InputObject $records.ToArray() -Depth 8) + "`n", $utf8)
      try {
        if ($isCpu) {
          $cpuDirectory = Join-Path $directory 'cpu'
          New-Item -ItemType Directory -Path $cpuDirectory | Out-Null
          $existingReverse = Invoke-Device @('reverse', '--list')
          if ($existingReverse -match "tcp:$cpuPort\s") { throw 'CPU转发端口已被其它会话占用，拒绝覆盖' }
          Invoke-Device @('reverse', "tcp:$cpuPort", "tcp:$cpuPort") | Out-Null
          $reversed = $true
          $cpuProcess = Start-Process -FilePath $dart -ArgumentList @('run', 'proc_cpu_sampler.dart', $DeviceSerial, $packageName, "`"$cpuDirectory`"") -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'cpu.stdout.log') -RedirectStandardError (Join-Path $directory 'cpu.stderr.log')
          $serverWatch = [Diagnostics.Stopwatch]::StartNew()
          while (-not (Test-Path (Join-Path $cpuDirectory 'server.ready'))) {
            if ($cpuProcess.HasExited -or $serverWatch.Elapsed.TotalSeconds -gt 30) { throw 'CPU主机采样器未就绪' }
            Start-Sleep -Milliseconds 100
          }
        }
        $arguments = @('drive', '--profile', '--no-pub', '--no-dds', '-d', $DeviceSerial,
          '--driver=test_driver/perf_driver.dart', '--target=integration_test/pending_bench_test.dart',
          '--dart-define=LUCKDRAW_TIMELINE=true', "--route=/$scene", "--use-application-binary=`"$binary`"")
        $driveProcess = Start-Process -FilePath $flutter -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
        # 阻塞等待子进程；不做adb、锁屏、温度或logcat看护轮询。
        if (-not $driveProcess.WaitForExit(300000)) { throw 'flutter drive 超过五分钟' }
        $driveProcess.WaitForExit()
        if ($driveProcess.ExitCode -ne 0) { throw "flutter drive失败: $($driveProcess.ExitCode)" }
        if ($isCpu) {
          if (-not $cpuProcess.WaitForExit(15000) -or $cpuProcess.ExitCode -ne 0) { throw 'CPU采样器失败或未退出' }
          $ok = Test-Path (Join-Path $cpuDirectory 'cpu.json')
          if ($ok) {
            $record.cpu = Get-Content -Raw (Join-Path $cpuDirectory 'cpu.json') | ConvertFrom-Json -AsHashtable
            if (-not $record.cpu.ContainsKey('process_cpu_percent')) { throw '仅降级原文，无可信 CPU 增量；不计作有效 CPU 轮' }
          }
        } else {
          $summaries = @(Get-ChildItem $directory -File -Filter '*.timeline_summary.json' | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json } | Where-Object report_key -eq $scene)
          $ok = $summaries.Count -eq 1
          if ($ok -and $isRetest) {
            $data = $summaries[0]
            if ($data.frame_count -le 0 -or $data.elapsed_micros -le 0 -or $data.rss_cycles -ne 5) { throw '帧/RSS采集不完整' }
            $delivery = $data.fps -ge 59 -and $data.frame_count -ge 0.98 * $data.elapsed_micros / 1000000 * 60
            if ($delivery -and $data.'90th_percentile_frame_rasterizer_time_millis' -lt 15.5) { $clean++ }
          }
          if ($ok -and -not $isRetest -and $summaries[0].first_frame_ui_millis -le 0) { throw '冷首帧未采到有效耗时' }
        }
        if (-not $ok) { throw '没有完整结果；检查APK是否包含pending新入口' }
        $powerAfter = Invoke-Device @('shell', 'dumpsys', 'power')
        $windowAfter = Invoke-Device @('shell', 'dumpsys', 'window')
        if ($powerAfter -notmatch 'mWakefulness=Awake' -or $windowAfter -notmatch 'isKeyguardShowing=false') { throw '采集结束时非亮屏未锁屏，保留该失败尝试' }
        $valid++
      } catch {
        $ok = $false
        $errorText = $_.ToString()
        Write-Warning "$scene 第$attempt 次失败: $errorText"
      } finally {
        Stop-OwnedTree $driveProcess
        Stop-OwnedTree $cpuProcess
        if ($reversed) { Invoke-Device @('reverse', '--remove', "tcp:$cpuPort") | Out-Null }
        Invoke-Device @('shell', 'am', 'force-stop', $packageName) | Out-Null
        $record.valid = $ok
        $record.error = $errorText
        $record.ended_at = (Get-Date).ToUniversalTime().ToString('o')
        [IO.File]::WriteAllText((Join-Path $root 'runs.json'), (ConvertTo-Json -InputObject $records.ToArray() -Depth 8) + "`n", $utf8)
      }
    }
    if ($valid -lt 3) { throw "$scene 五次启动仍不足三轮，失败；见runs.json" }
  }
  Write-Host 'INSTR collection complete; CPU permissions and performance status remain explicit in raw results.'
} finally {
  Pop-Location
}
