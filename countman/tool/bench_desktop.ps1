<#
.SYNOPSIS
  桌面真窗口基准（profile）：每个库隔离进程跑 N 轮，采 UI/Raster 帧耗时、FPS、RSS（页面内）+ 外部 CPU 采样。
  报告落盘到 build/perf/desktop-<时间戳>.json 与 .md。

.EXAMPLE
  pwsh tool/bench_desktop.ps1                 # 4 个库 × 5 轮
  pwsh tool/bench_desktop.ps1 -Rounds 1 -Libs countmanText
  pwsh tool/bench_desktop.ps1 -ForceFrames -Rounds 3
#>
param(
  # 每个库跑几轮
  [ValidateRange(1, 1000)]
  [int]$Rounds = 5,
  # 参与测量的库，对应 benchmark_page 的 BENCH_LIB
  [string[]]$Libs = @('countmanCard', 'slide', 'countmanText', 'stopWatch'),
  # 页面测量窗口（秒），需与 benchmark_page.dart 的 kMeasure 一致
  [int]$MeasureSeconds = 15,
  # 可选：采样窗口临时置顶并保持显示器唤醒，避免遮挡产生零帧。
  [switch]$KeepWindowVisible,
  # 可见性保护使用的小窗口尺寸，保持全部 50 个单元可见。
  [ValidateRange(640, 3840)]
  [int]$WindowWidth = 900,
  [ValidateRange(480, 2160)]
  [int]$WindowHeight = 600,
  # 可选：复用先前 --no-pub 构建的 profile 程序，避免重复构建工具占用内存。
  [switch]$UseBuiltBinary,
  # 强制每 vsync 出帧，空载校验后测呈现间隔与同轮差值。
  [switch]$ForceFrames
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$example = Join-Path $root 'example'
$out = Join-Path $root 'build/perf'
New-Item -ItemType Directory -Force $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$cores = [Environment]::ProcessorCount
$results = @()
$stem = if ($ForceFrames) { "desktop-present-$stamp" } else { "desktop-$stamp" }
if ($ForceFrames) {
  if ($Rounds -lt 3 -or $MeasureSeconds -ne 15) { throw '强制模式须至少 3 轮，每轮固定 15 秒。' }
  $KeepWindowVisible = $true
  if (-not $PSBoundParameters.ContainsKey('Libs')) {
    $Libs = @('emptyBaseline', 'dialCountdown', 'ringCountdown', 'barCountdown',
      'animatedCounter', 'counterFree', 'countmanCardDefault', 'cardFlipDefault')
  }
}
$profileExe = [IO.Path]::GetFullPath((Join-Path $example 'build/windows/x64/runner/Profile/example.exe'))
if ($UseBuiltBinary -and -not (Test-Path $profileExe)) { throw '未找到 profile 程序，请先 flutter build windows --profile --no-pub。' }
if ($KeepWindowVisible) { . (Join-Path $PSScriptRoot 'desktop_window.ps1') }

# pwsh -File 的逗号参数可能作为单个字符串传入，统一展开并校验。
$Libs = @($Libs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
$validLibs = @('emptyBaseline', 'countmanCard', 'slide', 'countmanText', 'stopWatch',
  'countmanCardFair', 'slide450', 'countmanCardDefault', 'countmanCardDefault30', 'coveredCounter', 'coveredCard', 'counterFree', 'ringCountdown', 'animatedCounter', 'dialCountdown', 'barCountdown', 'counter30', 'counterGlobal30', 'counterPlugin30', 'preciseFree', 'precise30', 'preciseGlobal30', 'precisePlugin30', 'countmanCardStaggered', 'slideStaggered',
  'cardSlideScale', 'cardSlideOpacity', 'cardFlipDefault',
  'mixedPerCard', 'mixedGroupLayer', 'mixedNoBoundary', 'mixedWrapAll')
foreach ($lib in $Libs) {
  if ($lib -notin $validLibs) { throw "未知基准库: $lib" }
}
if ($Libs.Count -eq 0) { throw 'Libs 不能为空' }
if ($ForceFrames) { $Libs = @('emptyBaseline') + @($Libs | Where-Object { $_ -ne 'emptyBaseline' } | Select-Object -Unique) }
if (-not $ForceFrames -and 'emptyBaseline' -in $Libs) { throw 'emptyBaseline 只用于 -ForceFrames。' }

# 空载天花板不足时停止，保留日志供排查。
function Assert-PresentBaseline {
  param($Row)
  $b = $Row.bench
  $hz = 1000000 / $b.vsyncPeriodUs
  $ratio = $b.presentFps / $hz
  if ($ratio -lt 0.95 -or $ratio -gt 1.05 -or $b.missedVsyncPct -gt 5) {
    throw "空载校验失败：presentFps=$($b.presentFps)，参考刷新率=$hz，错过vsync=$($b.missedVsyncPct)%。先排查遮挡、降频和驱动，禁止继续报告。"
  }
}

# 启动单库隔离进程，保留原 CPU 采样与退出前测量窗口逻辑；第 0 轮仅预跑。
function Invoke-DesktopBench {
  param([string]$Lib, [int]$Round)

  Get-Process example -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited -and $_.Path -eq $profileExe } | Stop-Process -Force
  $log = Join-Path $out "$stem-$Lib-$Round.log"
  $env:BENCH_LIB = $Lib
  $launch = if ($UseBuiltBinary) { '复用已构建 profile 程序' } else { 'flutter run --profile' }
  Write-Host "[$Lib #$Round] $launch ..."
  $p = $null
  $samples = @()
  $last = $null
  # 等待真正的 Flutter 窗口，并在外部 CPU 采样时维持可见性。
  $windowReady = $false
  $monitor = $null
  try {
    if ($UseBuiltBinary) {
      $p = Start-Process $profileExe -WorkingDirectory $example -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    } else {
      $p = Start-Process flutter -WorkingDirectory $example -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
        -ArgumentList @('run', '--profile', '-d', 'windows', '--no-pub', '--dart-define=INITIAL_ROUTE=/benchmark')
    }
    $deadline = (Get-Date).AddSeconds(300)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 500
      $app = Get-Process example -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited -and $_.Path -eq $profileExe } | Select-Object -First 1
      if ($app) {
        if ($KeepWindowVisible) {
          $windowReady = (Set-DesktopBenchVisible -App $app -Width $WindowWidth -Height $WindowHeight) -or $windowReady
          if ($ForceFrames -and $windowReady) {
            $handle = [CountmanPerfWindow]::FindFlutterWindow([uint32]$app.Id)
            if ($handle -ne [IntPtr]::Zero) {
              $info = [CountmanPerfWindow]::ReadMonitor($handle)
              $rect = New-Object CountmanPerfWindow+Rect
              $null = [CountmanPerfWindow]::GetWindowRect($handle, [ref]$rect)
              $current = [pscustomobject]@{
                device = $info.Device; primary = (($info.Flags -band 1) -ne 0)
                bounds = $info.Monitor; window = $rect
              }
              if ($monitor -and $monitor.device -ne $current.device) { throw '测量期间窗口跨显示器，禁止混合报告。' }
              $monitor = $current
            }
          }
        }
        $samples += [pscustomobject]@{ t = Get-Date; cpu = $app.TotalProcessorTime.TotalSeconds }
        $last = Get-Date
      } elseif ($last) { break }
      if ($p.HasExited -and -not $app) { break }
    }
  } finally {
    if ($p -and -not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null }
    $apps = @(Get-Process example -ErrorAction SilentlyContinue | Where-Object { -not $_.HasExited -and $_.Path -eq $profileExe })
    $apps | Stop-Process -Force -ErrorAction SilentlyContinue
    $apps | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
  }

  $line = Select-String -Path $log -Pattern '^\s*(flutter: )?BENCH \{' | Select-Object -Last 1
  if (-not $line) { throw "[$Lib #$Round] 没有拿到 BENCH 输出，见 $log" }
  $json = ($line.Line -replace '^\s*(flutter: )?BENCH ', '') | ConvertFrom-Json
  if ($json.lib -ne $Lib) { throw "[$Lib #$Round] BENCH 返回了错误的库: $($json.lib)" }
  if ($KeepWindowVisible -and (-not $windowReady -or $json.frames -eq 0)) { throw "[$Lib #$Round] 窗口不可见或零帧，禁止计入报告。" }
  if ($ForceFrames -and (-not $json.forceFrames -or -not $monitor)) { throw '强制出帧或显示器信息缺失，请重新构建 profile 程序。' }

  # CPU：取进程退出前的测量窗口（退出前 0.3s 为 flush 间隔）。
  $cpuPct = $null
  if ($last) {
    $end = $last.AddSeconds(-0.3); $start = $end.AddSeconds(-$MeasureSeconds)
    $w = @($samples | Where-Object { $_.t -ge $start -and $_.t -le $end })
    if ($w.Count -ge 2) {
      $d = ($w[-1].cpu - $w[0].cpu) / ($w[-1].t - $w[0].t).TotalSeconds
      $cpuPct = [math]::Round($d * 100, 1)   # 占单核百分比
    }
  }
  Write-Host ("  fps={0} ui_avg={1}ms cpu={2}%" -f $json.fps, $json.uiMs_avg, $cpuPct)
  $row = [pscustomobject]@{ lib = $Lib; round = $Round; cpuPctOfCore = $cpuPct; bench = $json }
  if ($ForceFrames) { $row | Add-Member -NotePropertyName monitor -NotePropertyValue $monitor }
  $row
}

# 环境变量只在本脚本运行期间切换；预跑完成构建并启动一次，不计入报告。
$previousBenchLib = $env:BENCH_LIB
$previousForceFrames = $env:BENCH_FORCE_FRAMES
$previousBaseline = $env:BENCH_BASELINE_INTERVAL_US
$visibilityInitialized = $false
try {
  if ($ForceFrames) {
    $env:BENCH_FORCE_FRAMES = 'true'
    $env:BENCH_BASELINE_INTERVAL_US = $null
    if (-not $UseBuiltBinary) {
      Push-Location $example
      try {
        & flutter build windows --profile --no-pub --dart-define=INITIAL_ROUTE=/benchmark
        if ($LASTEXITCODE -ne 0) { throw 'profile 构建失败。' }
      } finally { Pop-Location }
      $UseBuiltBinary = $true
    }
  }
  if ($KeepWindowVisible) {
    Initialize-DesktopBenchVisibility
    $visibilityInitialized = $true
  }
  Write-Host '预跑（不计数）：启动一次，随后按轮交错测量。'
  $preflight = Invoke-DesktopBench -Lib $Libs[0] -Round 0
  if ($ForceFrames) {
    $preflight | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "$stem-preflight.json") -Encoding utf8
    Assert-PresentBaseline $preflight
    $env:BENCH_BASELINE_INTERVAL_US = ($preflight.bench.intervalMs_p50 * 1000).ToString([Globalization.CultureInfo]::InvariantCulture)
  }
  for ($round = 1; $round -le $Rounds; $round++) {
    foreach ($lib in $Libs) {
      $row = Invoke-DesktopBench -Lib $lib -Round $round
      if ($ForceFrames) {
        if ($row.monitor.device -ne $preflight.monitor.device -or
            $row.bench.displayId -ne $preflight.bench.displayId -or
            $row.bench.refreshRateDetectedHz -ne $preflight.bench.refreshRateDetectedHz) {
          throw '各轮显示器或检测刷新率不一致，禁止混合报告。'
        }
        if ($lib -eq 'emptyBaseline') {
          Assert-PresentBaseline $row
          $baseline = $row
          $env:BENCH_BASELINE_INTERVAL_US = ($row.bench.intervalMs_p50 * 1000).ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        $row | Add-Member -NotePropertyName deltaPresentFps -NotePropertyValue ($row.bench.presentFps - $baseline.bench.presentFps)
        $row | Add-Member -NotePropertyName deltaMissedVsyncPp -NotePropertyValue ($row.bench.missedVsyncPct - $baseline.bench.missedVsyncPct)
        $row | Add-Member -NotePropertyName deltaRasterP99Ms -NotePropertyValue ($row.bench.rasterMs_p99 - $baseline.bench.rasterMs_p99)
      }
      $results += $row
      # 每次成功即保存检查点，单个进程异常不抹掉已经完成的测量。
      $results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "$stem-partial.json") -Encoding utf8
    }
  }
} finally {
  if ($visibilityInitialized) { Reset-DesktopBenchVisibility }
  $env:BENCH_LIB = $previousBenchLib
  $env:BENCH_FORCE_FRAMES = $previousForceFrames
  $env:BENCH_BASELINE_INTERVAL_US = $previousBaseline
}

# 聚合为“中位数（极差）”；缺失的 CPU 样本不参与计算。
function Format-BenchStats {
  param([object[]]$Values)

  $sorted = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
  if ($sorted.Count -eq 0) { return '—' }
  $middle = [int][math]::Floor($sorted.Count / 2)
  $median = $sorted[$middle]
  if ($sorted.Count % 2 -eq 0) { $median = ($sorted[$middle - 1] + $median) / 2 }
  $range = $sorted[-1] - $sorted[0]
  '{0:0.##}（{1:0.##}）' -f $median, $range
}

if ($ForceFrames) {
  $results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "$stem.json") -Encoding utf8
  $b = $preflight.bench
  $monitor = $preflight.monitor
  $md = @("# countman 持续出帧 profile 基准 $stamp", '',
    "预跑 1 次；$Rounds 轮，按轮交错，每轮先测 emptyBaseline，每变体固定 15 秒；组件数 50，空载仅驱动。窗口 ${WindowWidth}×${WindowHeight}，临时置顶且不激活。", '',
    "窗口显示器：$($monitor.device)，主屏=$($monitor.primary)，边界=[$($monitor.bounds.Left),$($monitor.bounds.Top),$($monitor.bounds.Right),$($monitor.bounds.Bottom)]；Flutter displayId=$($b.displayId)，尺寸=$($b.displaySizePx)，DPR=$($b.displayDevicePixelRatio)。", '',
    "检测刷新率=$($b.refreshRateDetectedHz) Hz；vsync 周期来源=$($b.vsyncSource)，预跑周期=$($b.vsyncPeriodUs) μs。刷新率不可用时仅使用空载中位间隔估算；此时天花板自检不构成对硬件刷新率的独立验证。", '',
    "预跑空载 presentFps=$($b.presentFps)，错过vsync=$($b.missedVsyncPct)%：校验通过。正式各轮空载也须通过 presentFps / 参考刷新率在 95%–105%、长间隔占比 ≤5% 的校验。", '',
    'presentFps = 窗口内 rasterFinish 帧数 / 15s；窗口为同一引擎时钟的半开区间，等待尾帧回调后统计。间隔为相邻 rasterFinish 差；错过vsync帧数是间隔 > 1.5×vsync周期的帧数，占比以 N−1 个间隔为分母，不是丢失槽位数。', '',
    'FrameTiming 的 rasterFinish 仅代表引擎光栅完成，是持续出帧能力的代理；无法直接观测 DWM 合成、硬件 present 或扫描输出，不能据此宣称精确测得物理屏幕 FPS。', '',
    '## 更新节奏', '', '| 变体 | 节奏 |', '| --- | --- |')
  foreach ($group in ($results | Group-Object lib)) {
    $md += "| $($group.Name) | $($group.Group[0].bench.updateCadence) |"
  }
  $md += @('', 'Ring/Bar 使用默认 interval:1000ms；Dial 使用显式 interval:0。二者负载不同，本次结果不能外推到 Ring/Bar 的 interval:0 或 Dial 的默认整秒配置。独立驱动仅强制提交帧，不改变组件更新节奏。', '',
    '## 按变体聚合', '',
    '指标为逐轮中位数（极差）；差值先减同轮 emptyBaseline，再取中位数（极差）。Δ错过vsync 使用百分点，时间单位 ms。', '',
    '| 变体 | 轮数 | presentFps | 间隔 p50 | 间隔 p90 | 间隔 p99 | 错过vsync% | ΔpresentFps | Δ错过vsync pp | Raster p99 | ΔRaster p99 | Build avg | Build p90 | Build p99 | Raster avg | Raster p90 |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
  foreach ($group in ($results | Group-Object lib)) {
    $rows = @($group.Group)
    $cells = @($group.Name, $rows.Count)
    foreach ($metric in @('presentFps', 'intervalMs_p50', 'intervalMs_p90', 'intervalMs_p99', 'missedVsyncPct')) {
      $cells += Format-BenchStats @($rows | ForEach-Object { $_.bench.$metric })
    }
    $cells += Format-BenchStats @($rows.deltaPresentFps)
    $cells += Format-BenchStats @($rows.deltaMissedVsyncPp)
    $cells += Format-BenchStats @($rows | ForEach-Object { $_.bench.rasterMs_p99 })
    $cells += Format-BenchStats @($rows.deltaRasterP99Ms)
    foreach ($metric in @('uiMs_avg', 'uiMs_p90', 'uiMs_p99', 'rasterMs_avg', 'rasterMs_p90')) {
      $cells += Format-BenchStats @($rows | ForEach-Object { $_.bench.$metric })
    }
    $md += '| ' + ($cells -join ' | ') + ' |'
  }
  $md += @('', '## 逐轮明细', '',
    '| 变体 | 轮 | 帧数 | 间隔数 | presentFps | 间隔 p50 | 间隔 p90 | 间隔 p99 | 错过vsync帧 | 错过vsync% | ΔpresentFps | Δ错过vsync pp | Raster p99 | ΔRaster p99 | Build avg | Build p90 | Build p99 | Raster avg | Raster p90 |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
  foreach ($r in $results) {
    $b = $r.bench
    $cells = @($r.lib, $r.round, $b.presentFrames, $b.intervalCount)
    foreach ($value in @($b.presentFps, $b.intervalMs_p50, $b.intervalMs_p90, $b.intervalMs_p99,
      $b.missedVsyncFrames, $b.missedVsyncPct, $r.deltaPresentFps, $r.deltaMissedVsyncPp,
      $b.rasterMs_p99, $r.deltaRasterP99Ms, $b.uiMs_avg, $b.uiMs_p90, $b.uiMs_p99, $b.rasterMs_avg, $b.rasterMs_p90)) {
      $cells += '{0:0.###}' -f $value
    }
    $md += '| ' + ($cells -join ' | ') + ' |'
  }
  $md += @('', '原始 JSON 保留每帧 rasterFinishUs / vsyncStartUs、窗口边界、显示器和同轮差值；预跑单存为 -preflight.json，未计入正式统计。CPU 仍为占单核百分比，仅供辅助。', '',
    '脚本：`pwsh -NoProfile -File tool/bench_desktop.ps1 -ForceFrames -Rounds 3`；可加 `-UseBuiltBinary` 复用包含本次修改的 profile 二进制。', '',
    '时间戳语义：[Flutter FramePhase](https://api.flutter.dev/flutter/dart-ui/FramePhase.html)；批量回调：[Flutter TimingsCallback](https://api.flutter.dev/flutter/dart-ui/TimingsCallback.html)。')
  $md | Set-Content (Join-Path $out "$stem.md") -Encoding utf8
  Write-Host "报告: build/perf/$stem.md"
  return
}

$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "desktop-$stamp.json") -Encoding utf8
$md = @("# countman 桌面 profile 基准 $stamp", '',
  "CPU 为占单核百分比（本机 $cores 逻辑核）。预跑一次不计数，正式测量按轮交错。窗口可见性保护：$KeepWindowVisible；窗口：${WindowWidth}×${WindowHeight}；复用 profile 程序：$UseBuiltBinary。", '',
  '卡顿帧口径：max(UI, Raster) > 16.67ms；RSS 增量为 rss_peak − rss_start。', '',
  '## 按库聚合', '', '各指标为中位数（极差 = 最大值 − 最小值）。', '',
  '| 库 | 轮数 | FPS | UI avg | UI p90 | UI p99 | Raster avg | Raster p90 | Raster p99 | 卡顿帧% | RSS avg MB | RSS peak MB | RSS 增量 MB | CPU %核 |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
foreach ($group in ($results | Group-Object lib)) {
  $rows = @($group.Group)
  $cells = @($group.Name, $rows.Count)
  foreach ($metric in @('fps', 'uiMs_avg', 'uiMs_p90', 'uiMs_p99', 'rasterMs_avg', 'rasterMs_p90', 'rasterMs_p99', 'jankPct', 'rss_avg_mb', 'rss_peak_mb')) {
    $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.bench.$metric })
  }
  $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.bench.rss_peak_mb - $_.bench.rss_start_mb })
  $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.cpuPctOfCore })
  $md += '| ' + ($cells -join ' | ') + ' |'
}
$md += @('', '## 逐轮明细', '',
  '| 库 | 轮 | FPS | UI avg | UI p90 | UI p99 | Raster avg | Raster p90 | Raster p99 | 卡顿帧% | RSS avg MB | RSS peak MB | RSS 增量 MB | CPU %核 |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
foreach ($r in $results) {
  $b = $r.bench
  $rssDelta = [math]::Round($b.rss_peak_mb - $b.rss_start_mb, 1)
  $md += "| $($r.lib) | $($r.round) | $($b.fps) | $($b.uiMs_avg) | $($b.uiMs_p90) | $($b.uiMs_p99) | $($b.rasterMs_avg) | $($b.rasterMs_p90) | $($b.rasterMs_p99) | $($b.jankPct) | $($b.rss_avg_mb) | $($b.rss_peak_mb) | $rssDelta | $($r.cpuPctOfCore) |"
}
$md | Set-Content (Join-Path $out "desktop-$stamp.md") -Encoding utf8
Write-Host "报告: build/perf/desktop-$stamp.md"
