# Launch the pure Dart verifier without a console window; retain all evidence.
# 无控制台窗口启动纯 Dart 验证器，保留所有证据。
[CmdletBinding()]
param([string]$DartExe)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$evidence = Join-Path $repo 'doc/plans/2026-11-06-review-fix-evidence'
$report = Join-Path $evidence 'windows-report.txt'
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $PID
$runDir = Join-Path $evidence ('windows-runs/' + $runId)
[IO.Directory]::CreateDirectory($runDir) | Out-Null
$bootstrap = Join-Path ([IO.Path]::GetTempPath()) ('mova_wrfv_launcher_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($bootstrap) | Out-Null
$bootstrapEntry = Join-Path $bootstrap 'verify.dart'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verify.dart') -Destination $bootstrapEntry
$utf8 = New-Object Text.UTF8Encoding($false)
if (-not $DartExe) {
    $dartCommand = (Get-Command dart -ErrorAction Stop).Source
    if ([IO.Path]::GetExtension($dartCommand) -eq '.bat') {
        $DartExe = Join-Path ([IO.Path]::GetDirectoryName($dartCommand)) 'cache/dart-sdk/bin/dart.exe'
    } else {
        $DartExe = $dartCommand
    }
}
$DartExe = (Resolve-Path -LiteralPath $DartExe).Path
$sources = @('lib/src/core/preview/dir_lease.dart', 'lib/src/platform_impl/thumb_dir_impl.dart')
$before = @{}
foreach ($source in $sources) { $before[$source] = (Get-FileHash -LiteralPath (Join-Path $repo $source) -Algorithm SHA256).Hash }
$baseline = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('dart.exe', 'dartvm.exe', 'dartaotruntime.exe') } | Select-Object ProcessId, ParentProcessId, Name)
[IO.File]::WriteAllText((Join-Path $runDir 'baseline-dart-processes.json'), (ConvertTo-Json -InputObject $baseline -Depth 4), $utf8)
$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $DartExe
$startInfo.WorkingDirectory = $bootstrap
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
# Windows file names cannot contain quotes; each path is passed as one argument.
# Windows 文件名不含双引号，逐路径加引号以保留空格。
$entry = Join-Path $PSScriptRoot 'verify.dart'
$startInfo.Arguments = 'run "' + $bootstrapEntry + '" "' + $repo + '" "' + $runDir + '" "' + $report + '"'
$process = New-Object Diagnostics.Process
$process.StartInfo = $startInfo
[void]$process.Start()
$outTask = $process.StandardOutput.ReadToEndAsync()
$errTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$outText = $outTask.GetAwaiter().GetResult()
$errText = $errTask.GetAwaiter().GetResult()
[IO.File]::WriteAllText((Join-Path $runDir 'stdout.txt'), $outText, $utf8)
[IO.File]::WriteAllText((Join-Path $runDir 'stderr.txt'), $errText, $utf8)
[Console]::Write($outText)
if ($errText) { [Console]::Error.Write($errText) }
$clean = $true
$tail = "`nLAUNCHER_VERIFICATION`nlauncher_child_pid=$($process.Id) exit=$($process.ExitCode)`n"
foreach ($source in $sources) {
    $after = (Get-FileHash -LiteralPath (Join-Path $repo $source) -Algorithm SHA256).Hash
    $same = $before[$source] -eq $after
    if (-not $same) { $clean = $false }
    $tail += "SOURCE_SHA256 $source before=$($before[$source]) after=$after unchanged=$same`n"
}
$manifestPath = Join-Path $runDir 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $live = @(Get-CimInstance Win32_Process)
    $owned = @($live | Where-Object {
        ($_.CommandLine -and ($_.CommandLine.Contains($manifest.temporary) -or $_.CommandLine.Contains($bootstrapEntry))) -and
        $_.Name -in @('dart.exe', 'dartvm.exe', 'dartaotruntime.exe')
    })
    $tempExists = Test-Path -LiteralPath $manifest.temporary
    if ($owned.Count -ne 0 -or $tempExists) { $clean = $false }
    $tail += "CLEANUP owned_dart_processes_remaining=$($owned.Count) temporary_exists=$tempExists temporary=$($manifest.temporary)`n"
    $tail += "All worker/launcher exit receipts: $(Join-Path $runDir 'manifest.json')`n"
} else {
    $clean = $false
    $tail += "CLEANUP FAIL missing manifest; consult stderr.txt`n"
}
$resolvedBootstrap = (Resolve-Path -LiteralPath $bootstrap).Path
$resolvedSystemTemp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path.TrimEnd('\')
if ([IO.Path]::GetDirectoryName($resolvedBootstrap).TrimEnd('\') -ne $resolvedSystemTemp -or
    -not [IO.Path]::GetFileName($resolvedBootstrap).StartsWith('mova_wrfv_launcher_')) {
    throw "Unsafe bootstrap cleanup path: $resolvedBootstrap"
}
Remove-Item -LiteralPath $resolvedBootstrap -Recurse -Force
$bootstrapExists = Test-Path -LiteralPath $resolvedBootstrap
if ($bootstrapExists) { $clean = $false }
$tail += "BOOTSTRAP_CLEANUP temporary_exists=$bootstrapExists temporary=$resolvedBootstrap`n"
$tail += "Pre-existing unrelated Dart processes were not terminated; baseline=$(Join-Path $runDir 'baseline-dart-processes.json')`n"
$tail += "FINAL launcher_exit=$($process.ExitCode) integrity_and_cleanup=$clean`n"
[IO.File]::AppendAllText($report, $tail, $utf8)
[Console]::Write($tail)
if ($process.ExitCode -ne 0 -or -not $clean) { exit 1 }
