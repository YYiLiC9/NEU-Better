param(
    [int]$X = 1830,
    [int]$Y = 145
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Click {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
[Win32Click]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$process = Get-Process -Name 'neu_better_pro' -ErrorAction Stop | Select-Object -First 1
[Win32Click]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 600
[Win32Click]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
[Win32Click]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)  # left down
Start-Sleep -Milliseconds 80
[Win32Click]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)  # left up
Write-Output "clicked at ($X, $Y)"
