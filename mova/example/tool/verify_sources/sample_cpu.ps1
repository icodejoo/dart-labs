param([string]$Out,[string]$Name='mova_example',[int]$TimeoutSec=1500)
# 每秒记录目标进程的累计 CPU 秒数；进程出现后开始，消失后结束。
Remove-Item $Out -ErrorAction SilentlyContinue
$deadline=(Get-Date).AddSeconds($TimeoutSec); $seen=$false
while ((Get-Date) -lt $deadline) {
  $p = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { $seen=$true; $t=(Get-Date).ToString('HH:mm:ss.fff'); Add-Content $Out ("{0},{1:F3},{2}" -f $t,$p.TotalProcessorTime.TotalSeconds,[int]($p.WorkingSet64/1MB)) }
  elseif ($seen) { break }
  Start-Sleep -Milliseconds 1000
}
