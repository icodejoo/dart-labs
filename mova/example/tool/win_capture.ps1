param([int]$TargetPid, [string]$OutputPath)
# 只读式截图：用 PrintWindow(PW_RENDERFULLCONTENT) 取窗口内容，不激活、不置前、不改显示状态，
# 窗口被遮住或在 z 序最底也能截；最小化窗口会是空白，调用方据此判断而不是去恢复窗口。
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WinCapture {
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[WinCapture]::SetProcessDPIAware() | Out-Null
$proc = Get-Process -Id $TargetPid
$handle = $proc.MainWindowHandle
if ($handle -eq 0) { throw 'Owned process has no window' }
$rect = New-Object WinCapture+RECT
[WinCapture]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
 $hdc = $graphics.GetHdc()
 $ok = [WinCapture]::PrintWindow($handle, $hdc, 2)
 $graphics.ReleaseHdc($hdc)
 $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
 [pscustomobject]@{pid=$TargetPid;handle=$handle.ToInt64();left=$rect.Left;top=$rect.Top;width=$width;height=$height;printWindow=$ok;screens=@([System.Windows.Forms.Screen]::AllScreens | ForEach-Object {$_.Bounds.ToString()})} | ConvertTo-Json
} finally { $graphics.Dispose(); $bitmap.Dispose() }
