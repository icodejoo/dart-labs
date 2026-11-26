param(
    [Parameter(Mandatory = $true)][string]$InputSvg,
    [Parameter(Mandatory = $true)][double]$AspectRatio,
    [string]$Device = 'R5CY2359S7D',
    [ValidateRange(1, 100)][int]$Repetitions = 3,
    [switch]$Normalize,
    [string[]]$Cases = @(
        'impeller:xvg', 'skia:xvg',
        'impeller:no_boundary', 'skia:no_boundary',
        'impeller:boundary', 'skia:boundary',
        'impeller:offscreen', 'skia:offscreen',
        'impeller:fit_all', 'impeller:flutter_svg', 'skia:flutter_svg',
        'impeller:xvg_sync', 'impeller:no_clip', 'impeller:no_gradient',
        'impeller:no_layer', 'impeller:bitmap_full', 'impeller:bitmap_view',
        'impeller:aligned', 'impeller:aligned_boundary'
    ),
    [string]$OutputDirectory = "$PSScriptRoot/../.dart_tool/raster_233kb_runs"
)

$ErrorActionPreference = 'Stop'
$app = 'com.example.bench_app'
$remote = "/sdcard/Android/data/$app/files"
$inputPath = (Resolve-Path -LiteralPath $InputSvg).Path
$ratio = $AspectRatio.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$normalization = if ($Normalize) { ' normalize' } else { '' }
$session = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$inbox = "/data/local/tmp/xvg-raster-$session.svg"
$output = Join-Path $OutputDirectory $session
New-Item -ItemType Directory -Path $output -Force | Out-Null

# 调用已选真机并验证退出码。
function Invoke-Phone {
    & adb -s $Device @args
    if ($LASTEXITCODE -ne 0) { throw 'adb command failed' }
}

$stayAwakeSetting = (Invoke-Phone shell settings get global stay_on_while_plugged_in).Trim()
try {
    Invoke-Phone push $inputPath $inbox 2>$null | Out-Null
    Invoke-Phone shell "run-as $app sh -c 'cp $inbox $remote/raster-input.svg'"
    Invoke-Phone shell rm -f $inbox
    Invoke-Phone shell input keyevent KEYCODE_WAKEUP
    Invoke-Phone shell wm dismiss-keyguard
    Invoke-Phone shell svc power stayon true
    for ($round = 1; $round -le $Repetitions; $round++) {
        # 正反交错并轮换起点，让后端与方案受热机过程的影响更均匀。
        $shift = (($round - 1) * 5) % $Cases.Length
        for ($index = 0; $index -lt $Cases.Length; $index++) {
            $step = if ($round % 2 -eq 1) { $index } else { $Cases.Length - $index }
            $case = $Cases[($shift + $step) % $Cases.Length]
            if ($case -notmatch '^(impeller|skia):([a-z_]+)$') { throw "Invalid case: $case" }
            $backend, $mode = $case.Split(':')
            $enable = if ($backend -eq 'impeller') { 'true' } else { 'false' }
            $tag = "$backend-$mode-$round"
            $runId = "$session-$tag"
            $thermal = Invoke-Phone shell dumpsys thermalservice | Select-String 'Thermal Status:'
            Invoke-Phone shell am force-stop $app
            Invoke-Phone shell "run-as $app sh -c 'rm -f $remote/raster-report.json $remote/raster-report.tmp'"
            Invoke-Phone shell "run-as $app sh -c 'echo $runId $mode $ratio$normalization > $remote/raster-run.txt'"
            $launch = Invoke-Phone shell am start -W -n "$app/.MainActivity" --ez enable-impeller $enable
            if (($launch -join "`n") -notmatch 'Status: ok') { throw "Launch failed: $tag ($launch)" }
            $wait = [Diagnostics.Stopwatch]::StartNew()
            do {
                $json = Invoke-Phone shell "run-as $app sh -c 'if [ -f $remote/raster-report.json ]; then cat $remote/raster-report.json; fi'"
                if (!$json) { Start-Sleep -Milliseconds 400 }
            } while (!$json -and $wait.Elapsed.TotalSeconds -lt 20)
            if (!$json) { throw "No report: $tag" }
            $report = $json | ConvertFrom-Json
            $json | Set-Content -LiteralPath (Join-Path $output "$tag.json") -Encoding utf8
            if ($report.run[0] -ne $runId -or ($report.error_kind -and $mode -ne 'flutter_svg') -or $report.frames.Count -lt 50) {
                throw "Invalid report: $tag, error=$($report.error_kind), frames=$($report.frames.Count)"
            }
            if ($mode -ne 'flutter_svg' -and $mode -ne 'spinner' -and !$report.picture_bytes) {
                throw "xvg picture was not recorded: $tag"
            }
            if ($mode.StartsWith('bitmap_') -and !$report.image_size[0]) {
                throw "Bitmap was not created: $tag"
            }
            $appPid = (Invoke-Phone shell pidof $app).Trim()
            $engine = Invoke-Phone logcat -d --pid=$appPid -s 'flutter:I'
            $reportedImpeller = ($engine -join "`n") -match 'Using the Impeller rendering backend'
            $reportedSkia = ($engine -join "`n") -match 'Impeller opt.out deprecated'
            if ($reportedImpeller -ne ($backend -eq 'impeller') -or ($backend -eq 'skia' -and !$reportedSkia)) {
                throw "Backend mismatch: $tag"
            }
            $engine | Select-String 'rendering backend|Impeller opt.out' |
                ForEach-Object { $_.Line } |
                Set-Content -LiteralPath (Join-Path $output "$tag.log") -Encoding utf8
            $thermal | ForEach-Object { $_.Line.Trim() } |
                Add-Content -LiteralPath (Join-Path $output "$tag.log") -Encoding utf8
            Write-Output "$tag $($report.frames.Count) frames, $($report.display_hz) Hz $($report.error_kind)"
        }
    }
    Write-Output "Results in $output"
} finally {
    try {
        Invoke-Phone shell am force-stop $app
        Invoke-Phone shell rm -f $inbox
        Invoke-Phone shell "run-as $app sh -c 'rm -f $remote/raster-input.svg $remote/raster-run.txt $remote/raster-report.json $remote/raster-report.tmp'"
    } finally {
        if ($stayAwakeSetting -eq 'null') {
            Invoke-Phone shell settings delete global stay_on_while_plugged_in
        } else {
            Invoke-Phone shell settings put global stay_on_while_plugged_in $stayAwakeSetting
        }
    }
}
