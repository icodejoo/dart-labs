<#
.SYNOPSIS
  一条命令跑完全部性能基准（engine + painter），报告落盘到 build/perf/。

.EXAMPLE
  pwsh tool/bench.ps1            # 全部
  pwsh tool/bench.ps1 -Only engine
#>
param(
  # 只跑某一类：engine | painter | all
  [ValidateSet('all', 'engine', 'painter')][string]$Only = 'all'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$dirs = switch ($Only) {
  'engine'  { @('test/benchmark/engine') }
  'painter' { @('test/benchmark/painter') }
  default   { @('test/benchmark/engine', 'test/benchmark/painter') }
}

$out = 'build/perf'
New-Item -ItemType Directory -Force $out | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$raw = "$out/bench-$stamp.txt"

# 单次 flutter test 调用覆盖所有目录，避免多次启动。
flutter test --no-pub --tags benchmark --run-skipped -r expanded @dirs 2>&1 | Tee-Object $raw | Out-Null

# 摘要：只取带 median= 的结果行。
$summary = "$out/bench-$stamp-summary.md"
$lines = Select-String -Path $raw -Pattern 'median=' | ForEach-Object { $_.Line.Trim() }
@("# countman 性能基准 $stamp", '', '```') + $lines + '```' | Set-Content $summary -Encoding utf8

$failed = Select-String -Path $raw -Pattern 'Some tests failed' -Quiet
Write-Host "原始输出: $raw`n摘要: $summary"
if ($failed) { Write-Error '有基准用例失败，见原始输出'; exit 1 }
