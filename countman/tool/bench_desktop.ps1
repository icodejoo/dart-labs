<#
.SYNOPSIS
  桌面真窗口基准（profile）：每个库隔离进程跑 N 轮，采 UI/Raster 帧耗时、FPS、RSS（页面内）+ 外部 CPU 采样。
  报告落盘到 build/perf/desktop-<时间戳>.json 与 .md。

.EXAMPLE
  pwsh tool/bench_desktop.ps1                 # 4 个库 × 5 轮
  pwsh tool/bench_desktop.ps1 -Rounds 1 -Libs countmanText
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
  # 可选：复用先前 --no-pub 构建的 profile 程序，避免重复构建工具占用内存。
  [switch]$UseBuiltBinary
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$example = Join-Path $root 'example'
$out = Join-Path $root 'build/perf'
New-Item -ItemType Directory -Force $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$cores = [Environment]::ProcessorCount
$results = @()
$profileExe = Join-Path $example 'build/windows/x64/runner/Profile/example.exe'
if ($UseBuiltBinary -and -not (Test-Path $profileExe)) { throw '未找到 profile 程序，请先 flutter build windows --profile --no-pub。' }
if ($KeepWindowVisible) { . (Join-Path $PSScriptRoot 'desktop_window.ps1') }

# pwsh -File 的逗号参数可能作为单个字符串传入，统一展开并校验。
$Libs = @($Libs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
$validLibs = @('countmanCard', 'slide', 'countmanText', 'stopWatch',
  'countmanCardFair', 'slide450', 'countmanCardDefault', 'countmanCardDefault30', 'coveredCounter', 'coveredCard', 'counterFree', 'ringCountdown', 'dialCountdown', 'barCountdown', 'counter30', 'counterGlobal30', 'counterPlugin30', 'preciseFree', 'precise30', 'preciseGlobal30', 'precisePlugin30', 'countmanCardStaggered', 'slideStaggered',
  'cardSlideScale', 'cardSlideOpacity', 'cardFlipDefault',
  'mixedPerCard', 'mixedGroupLayer', 'mixedNoBoundary', 'mixedWrapAll')
foreach ($lib in $Libs) {
  if ($lib -notin $validLibs) { throw "未知基准库: $lib" }
}
if ($Libs.Count -eq 0) { throw 'Libs 不能为空' }

# 启动单库隔离进程，保留原 CPU 采样与退出前测量窗口逻辑；第 0 轮仅预跑。
function Invoke-DesktopBench {
  param([string]$Lib, [int]$Round)

  Get-Process example -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $profileExe } | Stop-Process -Force
  $log = Join-Path $out "desktop-$stamp-$Lib-$Round.log"
  $env:BENCH_LIB = $Lib
  $launch = if ($UseBuiltBinary) { '复用已构建 profile 程序' } else { 'flutter run --profile' }
  Write-Host "[$Lib #$Round] $launch ..."
  $p = $null
  $samples = @()
  $last = $null
  # 等待真正的 Flutter 窗口，并在外部 CPU 采样时维持可见性。
  $windowReady = $false
  try {
    if ($UseBuiltBinary) {
      $p = Start-Process $profileExe -WorkingDirectory $example -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    } else {
      $p = Start-Process flutter -WorkingDirectory $example -PassThru -NoNewWindow `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
        -ArgumentList @('run', '--profile', '-d', 'windows', '--no-pub', '--dart-define=INITIAL_ROUTE=/benchmark')
    }
    $deadline = (Get-Date).AddSeconds(300)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 500
      $app = Get-Process example -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $profileExe } | Select-Object -First 1
      if ($app) {
        if ($KeepWindowVisible) { $windowReady = (Set-DesktopBenchVisible -App $app) -or $windowReady }
        $samples += [pscustomobject]@{ t = Get-Date; cpu = $app.TotalProcessorTime.TotalSeconds }
        $last = Get-Date
      } elseif ($last) { break }
      if ($p.HasExited -and -not $app) { break }
    }
  } finally {
    if ($p -and -not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null }
    $apps = @(Get-Process example -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $profileExe })
    $apps | Stop-Process -Force -ErrorAction SilentlyContinue
    $apps | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
  }

  $line = Select-String -Path $log -Pattern '^\s*(flutter: )?BENCH \{' | Select-Object -Last 1
  if (-not $line) { throw "[$Lib #$Round] 没有拿到 BENCH 输出，见 $log" }
  $json = ($line.Line -replace '^\s*(flutter: )?BENCH ', '') | ConvertFrom-Json
  if ($json.lib -ne $Lib) { throw "[$Lib #$Round] BENCH 返回了错误的库: $($json.lib)" }
  if ($KeepWindowVisible -and (-not $windowReady -or $json.frames -eq 0)) { throw "[$Lib #$Round] 窗口不可见或零帧，禁止计入报告。" }

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
  [pscustomobject]@{ lib = $Lib; round = $Round; cpuPctOfCore = $cpuPct; bench = $json }
}

# 环境变量只在本脚本运行期间切换；预跑完成构建并启动一次，不计入报告。
$previousBenchLib = $env:BENCH_LIB
try {
  if ($KeepWindowVisible) { Initialize-DesktopBenchVisibility }
  Write-Host '预跑（不计数）：启动一次，随后按轮交错测量。'
  $null = Invoke-DesktopBench -Lib $Libs[0] -Round 0
  for ($round = 1; $round -le $Rounds; $round++) {
    foreach ($lib in $Libs) {
      $results += Invoke-DesktopBench -Lib $lib -Round $round
      # 每次成功即保存检查点，单个进程异常不抹掉已经完成的测量。
      $results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "desktop-$stamp-partial.json") -Encoding utf8
    }
  }
} finally {
  if ($KeepWindowVisible) { Reset-DesktopBenchVisibility }
  $env:BENCH_LIB = $previousBenchLib
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

$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "desktop-$stamp.json") -Encoding utf8
$md = @("# countman 桌面 profile 基准 $stamp", '',
  "CPU 为占单核百分比（本机 $cores 逻辑核）。预跑一次不计数，正式测量按轮交错。窗口可见性保护：$KeepWindowVisible；复用 profile 程序：$UseBuiltBinary。", '',
  '卡顿帧口径：max(UI, Raster) > 16.67ms；RSS 增量为 rss_peak − rss_start。', '',
  '## 按库聚合', '', '各指标为中位数（极差 = 最大值 − 最小值）。', '',
  '| 库 | 轮数 | FPS | UI avg | UI p90 | UI p99 | Raster avg | Raster p99 | 卡顿帧% | RSS avg MB | RSS peak MB | RSS 增量 MB | CPU %核 |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
foreach ($group in ($results | Group-Object lib)) {
  $rows = @($group.Group)
  $cells = @($group.Name, $rows.Count)
  foreach ($metric in @('fps', 'uiMs_avg', 'uiMs_p90', 'uiMs_p99', 'rasterMs_avg', 'rasterMs_p99', 'jankPct', 'rss_avg_mb', 'rss_peak_mb')) {
    $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.bench.$metric })
  }
  $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.bench.rss_peak_mb - $_.bench.rss_start_mb })
  $cells += Format-BenchStats -Values @($rows | ForEach-Object { $_.cpuPctOfCore })
  $md += '| ' + ($cells -join ' | ') + ' |'
}
$md += @('', '## 逐轮明细', '',
  '| 库 | 轮 | FPS | UI avg | UI p90 | UI p99 | Raster avg | Raster p99 | 卡顿帧% | RSS avg MB | RSS peak MB | RSS 增量 MB | CPU %核 |',
  '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
foreach ($r in $results) {
  $b = $r.bench
  $rssDelta = [math]::Round($b.rss_peak_mb - $b.rss_start_mb, 1)
  $md += "| $($r.lib) | $($r.round) | $($b.fps) | $($b.uiMs_avg) | $($b.uiMs_p90) | $($b.uiMs_p99) | $($b.rasterMs_avg) | $($b.rasterMs_p99) | $($b.jankPct) | $($b.rss_avg_mb) | $($b.rss_peak_mb) | $rssDelta | $($r.cpuPctOfCore) |"
}
$md | Set-Content (Join-Path $out "desktop-$stamp.md") -Encoding utf8
Write-Host "报告: build/perf/desktop-$stamp.md"
