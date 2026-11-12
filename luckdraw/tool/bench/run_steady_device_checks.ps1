<# STEADY：四场景各三轮及 wheel /proc CPU 三轮；首轮 drive 构建，其余复用同一 APK。 #>
param(
  [string]$DeviceSerial = '10AE9K17UE0011S',
  [string]$ResultsDirectory = 'results/steady',
  [string[]]$Scenes = @('slot_raster','grid_steady','lotto_draw','lots_shaking','cpu_wheel_steady'),
  [switch]$PlanOnly
)
if ($PlanOnly) {
  @{ scenes=$scenes; rounds=3; max_starts=5; timeline=$true; entry_trace=$true; cpu_sampler='proc_cpu_sampler.dart'; settings_modified=$false } | ConvertTo-Json
  return
}
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $ResultsDirectory))
$packageName = 'com.example.luckdraw_bench'
$port = 41237
$records = [Collections.Generic.List[object]]::new()
$binary = Join-Path $PSScriptRoot 'build/app/outputs/flutter-apk/app-profile.apk'
$built = $false
$flutter = (Get-Command flutter.bat).Source
$dart = (Get-Command dart.bat).Source
function Save-Json($Path, $Value) {
  [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 12)+"`n", $utf8)
}
function Device([string[]]$Arguments) {
  $output = & adb -s $DeviceSerial @Arguments
  if ($LASTEXITCODE -ne 0) { throw "adb failed: $($Arguments -join ' ')" }
  return $output -join "`n"
}
function Ready {
  $power = Device @('shell','dumpsys','power')
  $window = Device @('shell','dumpsys','window')
  if ($window -notmatch 'isKeyguardShowing=false' -or $power -notmatch 'mWakefulness=Awake') {
    Device @('shell','input','keyevent','KEYCODE_WAKEUP') | Out-Null
    Device @('shell','input','swipe','540','2000','540','500','300') | Out-Null
    $window = Device @('shell','dumpsys','window')
    if ($window -notmatch 'isKeyguardShowing=false') { throw 'PIN/lock remains: user unlock required; no launch consumed' }
  }
  $battery = Device @('shell','dumpsys','battery')
  if ($battery -notmatch 'temperature:\s*(\d+)' -or [int]$Matches[1] -gt 420) { throw 'Temperature unknown or >42C' }
  return @{power=$power; window=$window; battery=$battery; at=(Get-Date).ToUniversalTime().ToString('o')}
}
function Stop-Owned($Process) {
  if ($null -ne $Process -and -not $Process.HasExited) {
    & taskkill /PID $Process.Id /T /F | Out-Null
    $Process.WaitForExit()
  }
}
New-Item -ItemType Directory -Force -Path $root | Out-Null
if (Test-Path (Join-Path $root 'runs.json')) { throw 'runs.json exists; refusing to reset launch counts' }
$env:BENCH_DEVICE_SERIAL = $DeviceSerial
$env:BENCH_DEVICE_MODEL = (Device @('shell','getprop','ro.product.model')).Trim()
Save-Json (Join-Path $root 'session.json') @{serial=$DeviceSerial;model=$env:BENCH_DEVICE_MODEL;started_at=(Get-Date).ToUniversalTime().ToString('o'); settings_modified=$false;entry_trace=$true;timeline=$true; free_physical_kib=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory}
Push-Location $PSScriptRoot
try {
  foreach ($scene in $scenes) {
    $valid = 0
    $clean = 0
    $isCpu = $scene.StartsWith('cpu_')
    foreach ($attempt in 1..5) {
      if ($valid -ge 3 -and ($isCpu -or $clean -ge 2)) { break }
      $before = Ready
      $directory = Join-Path $root "${scene}_$attempt"
      New-Item -ItemType Directory -Path $directory | Out-Null
      Save-Json (Join-Path $directory 'device_before.json') $before
      $env:BENCH_PERF_OUTPUT = $directory
      Device @('shell','am','force-stop',$packageName) | Out-Null
      $record = @{scene=$scene;attempt=$attempt;directory="${scene}_$attempt";valid=$false;started_at=(Get-Date).ToUniversalTime().ToString('o')}
      $records.Add($record)
      Save-Json (Join-Path $root 'runs.json') $records.ToArray()
      $drive = $null
      $cpu = $null
      $reversed = $false
      try {
        if ($isCpu) {
          if ((Device @('reverse','--list')) -match "tcp:$port\s") { throw 'CPU reverse already owned by another session' }
          Device @('reverse',"tcp:$port","tcp:$port") | Out-Null
          $reversed = $true
          $cpuDirectory = Join-Path $directory 'cpu'
          New-Item -ItemType Directory -Path $cpuDirectory | Out-Null
          $cpu = Start-Process $dart -ArgumentList @('run','proc_cpu_sampler.dart',$DeviceSerial,$packageName,$cpuDirectory) -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'cpu.stdout.log') -RedirectStandardError (Join-Path $directory 'cpu.stderr.log')
          $watch = [Diagnostics.Stopwatch]::StartNew()
          while (!(Test-Path (Join-Path $cpuDirectory 'server.ready'))) {
            if ($cpu.HasExited -or $watch.Elapsed.TotalSeconds -gt 30) { throw 'CPU sampler not ready' }
            Start-Sleep -Milliseconds 100
          }
        }
        $arguments = @('drive','--profile','--no-pub','--no-dds','-d',$DeviceSerial,'--driver=test_driver/perf_driver.dart','--target=integration_test/pending_bench_test.dart','--dart-define=LUCKDRAW_TIMELINE=true','--dart-define=LUCKDRAW_STEADY_ENTRY=true',"--route=/$scene")
        if ($built) { $arguments += "--use-application-binary=$binary" }
        else {
          $free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
          if ($free -lt 4194304) { throw "FreePhysicalMemory <4GB: $free" }
          $record.build_free_physical_kib = $free
        }
        Write-Host "START $scene $attempt $(Get-Date -Format o)"
        $drive = Start-Process $flutter -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.log') -RedirectStandardError (Join-Path $directory 'stderr.log')
        if (!$drive.WaitForExit(300000)) { throw 'drive exceeded five minutes; inspect logs' }
        $drive.WaitForExit()
        if (Test-Path $binary) { $built=$true; $record.binary_sha256=(Get-FileHash $binary -Algorithm SHA256).Hash }
        if ($drive.ExitCode -ne 0) { throw "drive exit $($drive.ExitCode)" }
        if ($isCpu) {
          if (!$cpu.WaitForExit(15000) -or $cpu.ExitCode -ne 0) { throw 'CPU sampler failed' }
          $data = Get-Content (Join-Path $cpuDirectory 'cpu.json') -Raw | ConvertFrom-Json
          if (!$data.valid_cpu) { throw 'Invalid /proc CPU' }
        } else {
          $summaries = @(Get-ChildItem $directory -Filter '*.timeline_summary.json' | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json } | Where-Object report_key -eq $scene)
          if ($summaries.Count -ne 1) { throw 'Scene summary missing' }
          $data = $summaries[0]
          if ($data.frame_count -le 0 -or $data.rss_cycles -ne 5) { throw 'Frame/RSS window incomplete' }
          $record.clean = $data.fps -ge 59 -and $data.frame_count -ge 0.98*$data.elapsed_micros/1000000*60 -and $data.'90th_percentile_frame_rasterizer_time_millis' -lt 15.5
          if ($record.clean) { $clean++ }
        }
        Save-Json (Join-Path $directory 'device_after.json') (Ready)
        $record.valid=$true
        $valid++
      } catch {
        $record.error=$_.ToString()
        Write-Warning "$scene/$attempt $($record.error)"
      } finally {
        Stop-Owned $drive
        Stop-Owned $cpu
        if ($reversed) { Device @('reverse','--remove',"tcp:$port") | Out-Null }
        Device @('shell','am','force-stop',$packageName) | Out-Null
        $record.ended_at=(Get-Date).ToUniversalTime().ToString('o')
        Save-Json (Join-Path $root 'runs.json') $records.ToArray()
        Write-Host "END $scene $attempt valid=$($record.valid) clean=$clean"
      }
    }
    if ($valid -lt 3) { Write-Warning "${scene}: fewer than three valid rounds; preserved failures" }
  }
} finally { Pop-Location }
