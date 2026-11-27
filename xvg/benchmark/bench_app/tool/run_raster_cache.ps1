param(
    [string]$InputSvg = "$PSScriptRoot/../assets/raster_cache_aurora.svg",
    [double]$AspectRatio = 0.25,
    [string[]]$Cases = @('vector:still', 'full:still'),
    [string]$Device = 'R5CY2359S7D',
    [ValidateRange(1, 100)][int]$Repetitions = 3,
    [string]$OutputDirectory = "$PSScriptRoot/../.dart_tool/raster_cache_runs",
    [switch]$UnclippedAurora
)

$ErrorActionPreference = 'Stop'
$app = 'com.example.bench_app'
$name = 'tile-raster'
$remote = "/sdcard/Android/data/$app/files"
$session = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$inbox = "/data/local/tmp/$name-$session.svg"
$output = Join-Path $OutputDirectory $session
$ratio = $AspectRatio.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
New-Item -ItemType Directory -Path $output -Force | Out-Null

if ($UnclippedAurora -and $PSBoundParameters.ContainsKey('InputSvg')) {
    throw 'UnclippedAurora requires the built-in synthetic SVG'
}
$inputPath = (Resolve-Path -LiteralPath $InputSvg).Path
if ($UnclippedAurora) {
    # 仅为合成样本移除 SVG 裁剪，保留原文件供旧数据复现。
    $svg = [xml](Get-Content -LiteralPath $inputPath -Raw)
    foreach ($clip in $svg.SelectNodes('//*[local-name()="clipPath"]')) {
        $null = $clip.ParentNode.RemoveChild($clip)
    }
    foreach ($node in $svg.SelectNodes('//*[@clip-path]')) {
        $node.RemoveAttribute('clip-path')
    }
    $inputPath = Join-Path ((Resolve-Path -LiteralPath $output).Path) 'aurora-unclipped.svg'
    $svg.Save($inputPath)
}

# 仅调用指定真机，并验证 adb 的退出码。
function Invoke-Phone {
    & adb -s $Device @args
    if ($LASTEXITCODE -ne 0) { throw 'adb command failed' }
}

$stayAwake = (Invoke-Phone shell settings get global stay_on_while_plugged_in).Trim()
try {
    Invoke-Phone push $inputPath $inbox 2>$null | Out-Null
    Invoke-Phone shell "run-as $app mkdir -p $remote"
    Invoke-Phone shell "run-as $app cp $inbox $remote/$name-input.svg"
    Invoke-Phone shell rm -f $inbox
    Invoke-Phone shell input keyevent KEYCODE_WAKEUP
    Invoke-Phone shell wm dismiss-keyguard
    Invoke-Phone shell svc power stayon true
    for ($round = 1; $round -le $Repetitions; $round++) {
        # 轮换起点以减小固定运行顺序的热偏差。
        for ($index = 0; $index -lt $Cases.Length; $index++) {
            $case = $Cases[($index + $round - 1) % $Cases.Length]
            if ($case -notmatch '^(vector|full|half|async|never):(still|scroll)$') {
                throw "Invalid case: $case"
            }
            $mode, $motion = $case.Split(':')
            $tag = "$mode-$motion-$round"
            $run = "$session-$tag"
            $thermal = Invoke-Phone shell dumpsys thermalservice | Select-String 'Thermal Status:'
            Invoke-Phone shell am force-stop $app
            Invoke-Phone shell "run-as $app rm -f $remote/$name-report.json $remote/$name-report.tmp"
            Invoke-Phone shell "run-as $app sh -c 'echo $run $mode $ratio $motion > $remote/$name-run.txt'"
            $launch = Invoke-Phone shell am start -W -n "$app/.MainActivity" --ez enable-impeller true
            if (($launch -join "`n") -notmatch 'Status: ok') { throw "Launch failed: $tag" }
            $watch = [Diagnostics.Stopwatch]::StartNew()
            do {
                $json = Invoke-Phone shell "run-as $app sh -c 'if [ -f $remote/$name-report.json ]; then cat $remote/$name-report.json; fi'"
                if (!$json) { Start-Sleep -Milliseconds 350 }
            } while (!$json -and $watch.Elapsed.TotalSeconds -lt 25)
            if (!$json) { throw "No report: $tag" }
            $report = $json | ConvertFrom-Json
            $json | Set-Content -LiteralPath (Join-Path $output "$tag.json") -Encoding utf8
            if ($report.run[0] -ne $run -or $report.error -or $report.frames.Count -lt 30 -or
                $report.first_us -le 0 -or $report.ready_us -lt $report.first_us -or
                ($mode -ne 'vector' -and $report.steady_bytes -le 0) -or
                ($UnclippedAurora -and $report.has_pixel_snap_risk -ne $false) -or
                ($motion -eq 'scroll' -and ($report.scroll_finished_frames -lt 30 -or
                    $report.scroll_frames.Count -ne $report.scroll_finished_frames -or
                    $report.scroll_frames[-1][1] -ne $report.scroll_extent_px))) {
                throw "Invalid report: $tag, error=$($report.error), frames=$($report.frames.Count), scroll matched=$($report.scroll_frames.Count)/$($report.scroll_finished_frames), snap risk=$($report.has_pixel_snap_risk)"
            }
            $appPid = (Invoke-Phone shell pidof $app).Trim()
            $backend = Invoke-Phone logcat -d "--pid=$appPid" -s 'flutter:I' |
                Select-String 'Using the Impeller rendering backend'
            if ("$backend" -notmatch 'Vulkan') { throw "Vulkan backend missing: $tag" }
            @("$backend", "$thermal") | Set-Content -LiteralPath (Join-Path $output "$tag.log") -Encoding utf8
            $readySummary = if ($motion -eq 'scroll') {
                $readyFrames = @($report.scroll_frames | Where-Object { $_[2] }).Count
                ", $readyFrames/$($report.scroll_finished_frames) frames tile-ready"
            }
            Write-Output "$tag $($report.raster_p50_us)/$($report.raster_p95_us) us raster, $($report.peak_bytes) B peak, $($report.completed_per_second) fps$readySummary"
        }
    }
    Write-Output "Results in $output"
} finally {
    try {
        Invoke-Phone shell am force-stop $app
        Invoke-Phone shell rm -f $inbox
        Invoke-Phone shell "run-as $app rm -f $remote/$name-input.svg $remote/$name-run.txt $remote/$name-report.json $remote/$name-report.tmp"
    } finally {
        if ($stayAwake -eq 'null') {
            Invoke-Phone shell settings delete global stay_on_while_plugged_in
        } else {
            Invoke-Phone shell settings put global stay_on_while_plugged_in $stayAwake
        }
    }
}
