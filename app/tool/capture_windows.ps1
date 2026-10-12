# Launches the Windows build, resizes the window so that the CLIENT area is W x H logical px,
# waits, and saves a PNG of the window. Usage:
#   powershell -File capture_windows.ps1 -Exe <path> -Width 360 -Height 800 -Out shot.png [-Wait 6] [-Keys "..."]
param(
  [string]$Exe,
  [int]$Width = 1440,
  [int]$Height = 900,
  [string]$Out = "shot.png",
  [int]$Wait = 6,
  [switch]$KeepOpen
)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@
[W]::SetProcessDPIAware() | Out-Null
$p = Start-Process -FilePath $Exe -PassThru
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 100 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh(); $h = $p.MainWindowHandle }
$dpi = [W]::GetDpiForWindow($h); $s = $dpi / 96.0
# first set a guess, then correct for non-client borders
$cw = [int]($Width * $s); $ch = [int]($Height * $s)
[W]::SetWindowPos($h, [IntPtr]::Zero, 20, 20, $cw + 40, $ch + 80, 0x0040) | Out-Null
Start-Sleep -Milliseconds 500
$r = New-Object W+RECT; [W]::GetClientRect($h, [ref]$r) | Out-Null
$w2 = $r.R - $r.L; $h2 = $r.B - $r.T
$wr = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$wr) | Out-Null
$nonW = ($wr.R - $wr.L) - $w2; $nonH = ($wr.B - $wr.T) - $h2
[W]::SetWindowPos($h, [IntPtr]::Zero, 20, 20, $cw + $nonW, $ch + $nonH, 0x0040) | Out-Null
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds $Wait
[W]::GetClientRect($h, [ref]$r) | Out-Null
$pt = New-Object W+POINT; $pt.X = 0; $pt.Y = 0; [W]::ClientToScreen($h, [ref]$pt) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($pt.X, $pt.Y, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("dpi=$dpi scale=$s client={0}x{1} logical={2:N0}x{3:N0}" -f ($r.R - $r.L), ($r.B - $r.T), (($r.R - $r.L) / $s), (($r.B - $r.T) / $s))
if (-not $KeepOpen) { Stop-Process -Id $p.Id -Force }
