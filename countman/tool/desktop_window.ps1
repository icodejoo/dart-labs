# 基准专用窗口控制；不发送键鼠事件，只保证采样窗口可见及显示器唤醒。
function Initialize-DesktopBenchVisibility {
  if (-not ('CountmanPerfWindow' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
// 仅供桌面测量使用的 Win32 窗口与电源接口。
public static class CountmanPerfWindow {
  // 置顶且不激活窗口，避免其它窗口遮挡基准。
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
  // 检查是否被最小化。
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
  // 必要时还原被最小化的基准窗口。
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window, int command);
  // 排除启动时短暂出现的控制台窗口，只操作 Flutter 真窗口。
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder name, int count);
  // 枚举实际窗口，避免 Process.MainWindowHandle 暂时指向控制台。
  private delegate bool WindowCallback(IntPtr window, IntPtr state);
  // 遍历顶层窗口。
  [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr state);
  // 确认窗口属于目标进程。
  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
  // 仅返回指定进程的 Flutter 窗口。
  public static IntPtr FindFlutterWindow(uint process) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((window, state) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner != process) return true;
      var name = new StringBuilder(256);
      GetClassName(window, name, 256);
      if (name.ToString() != "FLUTTER_RUNNER_WIN32_WINDOW") return true;
      found = window;
      return false;
    }, IntPtr.Zero);
    return found;
  }
  // 采样期间保持系统与显示器唤醒，结束时归还。
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
'@
  }
  $null = [CountmanPerfWindow]::SetThreadExecutionState([uint32]2147483651)
}

# 对指定应用的主窗口设临时置顶，返回是否已成功；进程退出即销毁窗口。
function Set-DesktopBenchVisible {
  param([System.Diagnostics.Process]$App)
  $handle = [CountmanPerfWindow]::FindFlutterWindow([uint32]$App.Id)
  if ($handle -eq [IntPtr]::Zero) { return $false }
  if ([CountmanPerfWindow]::IsIconic($handle)) { $null = [CountmanPerfWindow]::ShowWindowAsync($handle, 9) }
  return [CountmanPerfWindow]::SetWindowPos($handle, [IntPtr]::new(-1), 0, 0, 0, 0, 0x53)
}

# 清理采样线程的唤醒请求，恢复原电源策略。
function Reset-DesktopBenchVisibility {
  $null = [CountmanPerfWindow]::SetThreadExecutionState([uint32]2147483648)
}
