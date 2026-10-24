param([string]$Log,[string]$OutDir,[string]$Name='mova_example',[int]$TimeoutSec=180)
Add-Type -AssemblyName System.Drawing,System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public class WinApi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
'@
[WinApi]::SetProcessDPIAware() | Out-Null
New-Item -ItemType Directory -Force $OutDir | Out-Null
$seen=0; $deadline=(Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
  if (Test-Path $Log) {
    $lines=@(Get-Content $Log -ErrorAction SilentlyContinue)
    for ($i=$seen; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match 'S14 SHOT (\w+)') {
        $label=$matches[1]
        $p=Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p -and $p.MainWindowHandle -ne 0) {
          [WinApi]::ShowWindow($p.MainWindowHandle,9) | Out-Null; [WinApi]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
          Start-Sleep -Milliseconds 150
          $r=New-Object WinApi+RECT; [WinApi]::GetWindowRect($p.MainWindowHandle,[ref]$r) | Out-Null
          $w=$r.R-$r.L; $h=$r.B-$r.T
          $bmp=New-Object System.Drawing.Bitmap $w,$h
          $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L,$r.T,0,0,$bmp.Size)
          $bmp.Save((Join-Path $OutDir "s14_$label.png")); $g.Dispose(); $bmp.Dispose()
          Add-Content (Join-Path $OutDir 'shots.txt') "$label ${w}x${h} at $($r.L),$($r.T)"
        } else { Add-Content (Join-Path $OutDir 'shots.txt') "$label NO_WINDOW" }
      }
    }
    $seen=$lines.Count
  }
  Start-Sleep -Milliseconds 100
}
