param([int]$TargetPid, [string]$OutputPath)
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinCapture {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[WinCapture]::SetProcessDPIAware() | Out-Null
$proc = Get-Process -Id $TargetPid
$handle = $proc.MainWindowHandle
if ($handle -eq 0) { throw 'Owned process has no window' }
[WinCapture]::ShowWindow($handle, 9) | Out-Null
[WinCapture]::SetForegroundWindow($handle) | Out-Null
Start-Sleep -Milliseconds 600
$rect = New-Object WinCapture+RECT
[WinCapture]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
 $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
 $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
 [pscustomobject]@{pid=$TargetPid;handle=$handle.ToInt64();left=$rect.Left;top=$rect.Top;width=$width;height=$height;screens=@([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {$_.Bounds.ToString()})} | ConvertTo-Json
} finally { $graphics.Dispose(); $bitmap.Dispose() }
