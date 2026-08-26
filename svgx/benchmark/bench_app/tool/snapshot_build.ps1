# Builds the bench app and copies the profile output into a private, named
# directory, so several benchmark variants (or several agents sharing this
# machine) can coexist instead of overwriting `build/windows/x64/runner/Profile`.
#
# Needed because `flutter build windows` has no output-directory switch: two
# variants built in sequence leave only the second one on disk, and an A/B
# comparison then silently measures the same binary twice.
#
# 编译基准应用，并把 profile 产物拷进一个私有的具名目录，使多个基准变体（或共用
# 同一台机器的多个 agent）可以共存，而不是互相覆盖
# `build/windows/x64/runner/Profile`。
#
# 之所以需要：`flutter build windows` 没有输出目录参数，先后编译两个变体后磁盘上
# 只剩后一个，A/B 对比就会在毫无察觉的情况下把同一个二进制测了两遍。
#
# Usage:
#   pwsh tool/snapshot_build.ps1 -Name base -Defines "LIB=svgx","AUTOEXIT=1","CYCLES=6","ITEMS=1000"

param(
  [Parameter(Mandatory = $true)][string]$Name,
  [string[]]$Defines = @("LIB=svgx", "AUTOEXIT=1", "CYCLES=6", "ITEMS=1000")
)

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$args = @("build", "windows", "--profile")
foreach ($d in $Defines) { $args += "--dart-define=$d" }

Push-Location $root
try {
  & flutter @args
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
}
finally { Pop-Location }

$src = Join-Path $root "build\windows\x64\runner\Profile"
$dst = Join-Path $root "build\bench_variants\$Name"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Recurse -Force (Join-Path $src "*") $dst
Write-Host "snapshot -> $dst"
