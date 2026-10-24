param([string]$Exe,[string]$Log,[string]$Only='',[string]$Runs='',[string]$Impeller='off',[int]$TimeoutSec=1500)
Remove-Item $Log -ErrorAction SilentlyContinue
$env:MOVA_LOG=$Log
if ($Only) { $env:MOVA_ONLY=$Only } else { Remove-Item Env:MOVA_ONLY -ErrorAction SilentlyContinue }
if ($Runs) { $env:MOVA_RUNS=$Runs } else { Remove-Item Env:MOVA_RUNS -ErrorAction SilentlyContinue }
if ($Impeller -eq 'off') { $env:FLUTTER_ENGINE_SWITCHES='1'; $env:FLUTTER_ENGINE_SWITCH_1='enable-impeller=false' } else { Remove-Item Env:FLUTTER_ENGINE_SWITCHES -ErrorAction SilentlyContinue }
$p = Start-Process $Exe -PassThru -WorkingDirectory (Split-Path $Exe)
$p.WaitForExit($TimeoutSec*1000) | Out-Null
if (-not $p.HasExited) { "TIMEOUT, killing"; Stop-Process -Id $p.Id -Force } else { "exited code $($p.ExitCode)" }
