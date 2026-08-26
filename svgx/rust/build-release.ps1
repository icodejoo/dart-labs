<#
.SYNOPSIS
  Builds the distributable release svgx native library with nightly build-std.

  用 nightly build-std 构建对外分发的 svgx 原生库。

.DESCRIPTION
  Day-to-day development (cargo build / cargo test / flutter test / flutter analyze)
  stays on the stable toolchain and is NOT affected by this script. This script is
  only for producing the final, size-optimised artifact for distribution: it uses a
  pinned nightly toolchain plus `-Z build-std=std,panic_abort` and
  `RUSTFLAGS=-Zunstable-options -Cpanic=immediate-abort`, which recompiles std with
  the immediate-abort panic strategy and shrinks the library by roughly 21%.

  The build-std artifact lands under `target/<triple>/release/`; this script copies
  it to `target/release/` because that is where the Dart FFI loader looks
  (`lib/src/rust/frb_generated.dart` -> `ioDirectory: 'rust/target/release/'`).

  日常开发（cargo build / cargo test / flutter test / flutter analyze）仍走 stable，
  不受本脚本影响。本脚本只负责产出对外分发的最终产物：固定版本 nightly +
  `-Z build-std=std,panic_abort` + `RUSTFLAGS=-Zunstable-options -Cpanic=immediate-abort`，
  把 std 一并按 immediate-abort 重编，体积约减 21%。产物会从 `target/<triple>/release/`
  拷到 `target/release/`，因为 Dart FFI 就是从后者加载的。

.PARAMETER Target
  Rust target triple to build for. Defaults to the host triple.
  目标三元组，默认取宿主机三元组。

.PARAMETER Toolchain
  Pinned nightly toolchain name. Change only deliberately — a floating `nightly`
  would make builds non-reproducible.
  固定的 nightly 工具链名。只在有意升级时才改——用浮动的 `nightly` 会失去可复现性。

.EXAMPLE
  pwsh rust/build-release.ps1
  # -> rust/target/release/svgx.dll (~0.47 MiB)
#>
[CmdletBinding()]
param(
    [string]$Target = '',
    [string]$Toolchain = 'nightly-2026-06-24'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Native tools (rustup/cargo) write progress to stderr, which Windows PowerShell
# turns into a terminating error under `$ErrorActionPreference = 'Stop'`. Run them
# with the preference relaxed and judge success by the exit code instead.
# rustup/cargo 把进度写到 stderr，在 `Stop` 策略下会被 Windows PowerShell 当成终止错误。
# 这里临时放宽策略，改用退出码判断成败。
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed ($LASTEXITCODE)." }
}

$crateRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($Target)) {
    $hostLine = (& rustc -vV) | Where-Object { $_ -like 'host:*' }
    if (-not $hostLine) { throw 'Could not determine the host target triple from `rustc -vV`.' }
    $Target = ($hostLine -split ':\s*', 2)[1].Trim()
}

Write-Host "toolchain : $Toolchain"
Write-Host "target    : $Target"
Write-Host "crate     : $crateRoot"

# build-std needs the std sources; installing is a no-op when already present.
# build-std 需要 std 源码；已安装时重复执行无副作用。
Invoke-Native -Exe 'rustup' -Arguments @('component', 'add', 'rust-src', '--toolchain', $Toolchain)

# `-Cpanic=immediate-abort` is the current spelling; the older
# `-Z build-std-features=panic_immediate_abort` is rejected by recent nightlies.
# 现在的写法是 `-Cpanic=immediate-abort`；旧的 `-Z build-std-features=panic_immediate_abort`
# 在近期 nightly 上会直接报错。
$previousRustFlags = $env:RUSTFLAGS
$env:RUSTFLAGS = '-Zunstable-options -Cpanic=immediate-abort'
try {
    Push-Location $crateRoot
    try {
        Invoke-Native -Exe 'cargo' -Arguments @("+$Toolchain", 'build', '--release', '-Z', 'build-std=std,panic_abort', '--target', $Target)
    } finally {
        Pop-Location
    }
} finally {
    $env:RUSTFLAGS = $previousRustFlags
}

$builtDir = Join-Path $crateRoot "target\$Target\release"
$artifact = Get-ChildItem -Path $builtDir -File |
    Where-Object { $_.Name -in @('svgx.dll', 'libsvgx.so', 'libsvgx.dylib') } |
    Select-Object -First 1
if (-not $artifact) { throw "No svgx library found in $builtDir." }

# Mirror to target/release/ so the Dart FFI loader picks up this artifact.
# 镜像到 target/release/，让 Dart FFI 加载到的就是这份产物。
$destDir = Join-Path $crateRoot 'target\release'
if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
$dest = Join-Path $destDir $artifact.Name
Copy-Item -Path $artifact.FullName -Destination $dest -Force

$bytes = (Get-Item $dest).Length
$mib = [math]::Round($bytes / 1MB, 3)
Write-Host ''
Write-Host "artifact  : $dest"
Write-Host "size      : $bytes bytes ($mib MiB)"
