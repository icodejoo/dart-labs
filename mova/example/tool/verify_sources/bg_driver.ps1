param(
  [string]$Log,                      # 验证页的日志文件（LOG_FILE / MOVA_LOG 指向的那个）
  [string]$Marker = 'WAIT_HOME',     # 看到含此字样的新行就动手：最小化窗口 -> 等 AwaySec 秒 -> 还原
  [int]$AwaySec = 5,
  [string]$Name = 'mova_example',
  [int]$TimeoutSec = 300
)
# Windows 上代替 `adb shell input keyevent KEYCODE_HOME` + `am start` 的驱动脚本：
# 盯日志里的 WAIT_HOME 标记，最小化窗口模拟"进后台"，AwaySec 秒后还原模拟"回前台"。
# 同一份日志里每出现一次标记就驱动一次（V9 / S8 / S8B 各一次）。
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type @'
using System; using System.Runtime.InteropServices;
public class BgWin { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
'@
$seen = 0
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
  if (Test-Path $Log) {
    $lines = @(Get-Content $Log -ErrorAction SilentlyContinue)
    for ($i = $seen; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match $Marker) {
        $p = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.MainWindowHandle -ne 0) {
          [BgWin]::ShowWindow($p.MainWindowHandle, 6) | Out-Null   # SW_MINIMIZE
          Start-Sleep -Seconds $AwaySec
          [BgWin]::ShowWindow($p.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
          for ($k = 0; $k -lt 8; $k++) {                           # 前台锁可能让一次激活失败，重试几次
            try { [Microsoft.VisualBasic.Interaction]::AppActivate($p.Id) } catch { }
            [BgWin]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
            Start-Sleep -Milliseconds 300
          }
        }
      }
    }
    $seen = $lines.Count
  }
  Start-Sleep -Milliseconds 200
}
