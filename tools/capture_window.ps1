param(
    [string]$ProcessName = 'neu_better_pro',
    [string]$OutPath = 'docs\design\m0-windows.png'
)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32Capture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
"@

$process = Get-Process -Name $ProcessName -ErrorAction Stop | Select-Object -First 1
$handle = $process.MainWindowHandle
if ($handle -eq [IntPtr]::Zero) {
    throw "No main window for $ProcessName"
}

[Win32Capture]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
[Win32Capture]::ShowWindow($handle, 9) | Out-Null
[Win32Capture]::SetWindowPos($handle, [IntPtr]::Zero, 0, 0, 1920, 1200, 0x0040) | Out-Null
[Win32Capture]::SetForegroundWindow($handle) | Out-Null
Start-Sleep -Milliseconds 1200

$rect = New-Object Win32Capture+RECT
[Win32Capture]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
$printed = [Win32Capture]::PrintWindow($handle, $hdc, 2)
$graphics.ReleaseHdc($hdc)
if (-not $printed) {
    $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
}
$graphics.Dispose()

$resolved = Join-Path (Get-Location) $OutPath
$bitmap.Save($resolved, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
Write-Output "saved $resolved ($width x $height)"
