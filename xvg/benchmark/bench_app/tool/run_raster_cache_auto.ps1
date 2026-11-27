param(
    [Parameter(Mandatory)][string]$InputSvg,
    [string]$Device = 'R5CY2359S7D',
    [ValidateRange(1, 3)][int]$Repetitions = 3,
    [ValidateRange(1, 3)][int]$FirstRound = 1,
    [string[]]$SampleIds = @(),
    [switch]$ClipArtwork,
    [string]$OutputDirectory = "$PSScriptRoot/../.dart_tool/raster_cache_auto_runs"
)

$ErrorActionPreference = 'Stop'
$app = 'com.example.bench_app'
$remote = "/sdcard/Android/data/$app/files"
$prefix = "$remote/auto-raster"
$session = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$inbox = "/data/local/tmp/auto-raster-$session.svg"
$output = Join-Path $OutputDirectory $session
$null = New-Item -ItemType Directory -Path $output -Force

# 验证 adb 退出码，始终只向指定的设备发命令。
function Invoke-Phone {
    & adb -s $Device @args
    if ($LASTEXITCODE -ne 0) { throw 'adb command failed' }
}

# 以通用设备名传入 SVG，运行路径只存在于主机进程参数里。
function Send-Input([string]$LocalPath, [string]$Target) {
    Invoke-Phone push $LocalPath $inbox 2>$null | Out-Null
    Invoke-Phone shell "run-as $app cp $inbox $Target"
    Invoke-Phone shell rm -f $inbox
}

$samples = $SampleIds -join ' '
if ($samples -and $samples -notmatch '^[A-Za-z0-9-]+( [A-Za-z0-9-]+)*$') {
    throw 'Invalid sample ids'
}
if ($FirstRound + $Repetitions -gt 4) { throw 'Invalid round range' }
$runArgs = $(if ($ClipArtwork) { "clip $samples" } else { $samples }).Trim()
$localSvg = (Resolve-Path -LiteralPath $InputSvg).Path
$aurora = (Resolve-Path -LiteralPath "$PSScriptRoot/../assets/raster_cache_aurora.svg").Path
$stayAwake = (Invoke-Phone shell settings get global stay_on_while_plugged_in).Trim()
try {
    Invoke-Phone shell "run-as $app mkdir -p $remote"
    Send-Input $localSvg "$prefix-input.svg"
    Send-Input $aurora "$prefix-aurora.svg"
    Invoke-Phone shell input keyevent KEYCODE_WAKEUP
    Invoke-Phone shell wm dismiss-keyguard
    Invoke-Phone shell svc power stayon true
    Write-Output "Results in $output"
    for ($round = $FirstRound; $round -lt $FirstRound + $Repetitions; $round++) {
        Invoke-Phone shell am force-stop $app
        Invoke-Phone shell "run-as $app rm -f $prefix-status.txt $prefix-status.tmp $prefix-frames.jsonl"
        Invoke-Phone shell "run-as $app sh -c 'echo $round $runArgs > $prefix-run.txt'"
        $launch = Invoke-Phone shell am start -W -n "$app/.MainActivity" --ez enable-impeller true
        if (($launch -join "`n") -notmatch 'Status: ok') { throw "Launch failed: $round" }
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $thermalLog = [Collections.Generic.List[string]]::new()
        $lastStatus = ''
        try {
            do {
                $thermal = Invoke-Phone shell dumpsys thermalservice | Select-String '^Thermal Status:\s*(\d+)'
                if (!$thermal) { throw 'Thermal status missing' }
                $thermalLog.Add("$([int]$watch.Elapsed.TotalSeconds),$($thermal.Matches[0].Groups[1].Value)")
                $status = Invoke-Phone shell "run-as $app sh -c 'if [ -f $prefix-status.txt ]; then cat $prefix-status.txt; fi'"
                if ($status -and $status -ne $lastStatus) {
                    Write-Output "Round $round $status"
                    $lastStatus = $status
                }
                if ($status -like 'error*') { throw "Round $round $status" }
                if ($status -ne "done $round") { Start-Sleep -Seconds 6 }
            } while ($status -ne "done $round" -and $watch.Elapsed.TotalMinutes -lt 30)
            if ($status -ne "done $round") { throw "Timeout in round $round" }
        } catch {
            Invoke-Phone exec-out "run-as $app sh -c 'if [ -f $prefix-frames.jsonl ]; then cat $prefix-frames.jsonl; fi'" |
                Set-Content -LiteralPath (Join-Path $output "round-$round-partial.jsonl") -Encoding utf8
            throw
        }

        $pidOnPhone = (Invoke-Phone shell pidof $app).Trim()
        $backend = Invoke-Phone logcat -d "--pid=$pidOnPhone" -s 'flutter:I' |
            Select-String 'Using the Impeller rendering backend'
        if ("$backend" -notmatch 'Vulkan') { throw "Vulkan backend missing: $round" }
        $backend | Set-Content -LiteralPath (Join-Path $output "round-$round-backend.txt") -Encoding utf8
        @('elapsed_s,thermal_status') + $thermalLog |
            Set-Content -LiteralPath (Join-Path $output "round-$round-thermal.csv") -Encoding utf8
        Invoke-Phone exec-out "run-as $app cat $prefix-frames.jsonl" |
            Set-Content -LiteralPath (Join-Path $output "round-$round-frames.jsonl") -Encoding utf8
    }
    Write-Output 'All rounds complete'
} finally {
    try {
        Invoke-Phone shell am force-stop $app
        Invoke-Phone shell rm -f $inbox
        Invoke-Phone shell "run-as $app rm -f $prefix-input.svg $prefix-aurora.svg $prefix-run.txt $prefix-status.txt $prefix-status.tmp $prefix-frames.jsonl"
    } finally {
        if ($stayAwake -eq 'null') {
            Invoke-Phone shell settings delete global stay_on_while_plugged_in
        } else {
            Invoke-Phone shell settings put global stay_on_while_plugged_in $stayAwake
        }
    }
}
