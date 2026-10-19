# Chuanyun Windows UI smoke test, run on windows-latest in CI (Windows PowerShell 5.1).
# Launches Chuanyun.exe, checks it stays up with hiddify-core.dll loaded and its core gRPC
# listening, takes screenshots (default size, each tab, maximized), checks single instance,
# close-to-tray and restore-from-second-launch, then quits it and collects its logs.
# ASCII only on purpose: Chinese text is built from code points (PowerShell 5.1 reads BOM-less
# scripts in the ANSI code page).
#
#   powershell -File tool/smoke/app_smoke.ps1 -AppDir <dir with Chuanyun.exe> -Out <dir> -Label portable
#
# Part of Chuanyun, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
param(
  [Parameter(Mandatory = $true)][string]$AppDir,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$Label = "portable",
  [int]$StartupWait = 25,
  # repo checkout: when set, tool/smoke/core_smoke.dart --app-grpc checks the app's gRPC token
  [string]$RepoDir = ""
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
}
"@
[W]::SetProcessDPIAware() | Out-Null

$title = [string]::new([char[]]@(0x7A7F, 0x4E91))           
$results = New-Object System.Collections.ArrayList
function Rec([string]$id, [string]$name, [bool]$pass, [string]$detail, [bool]$optional = $false) {
  [void]$results.Add([pscustomobject]@{ id = $id; name = $name; pass = $pass; optional = $optional; detail = $detail })
  $tag = if ($pass) { "PASS" } elseif ($optional) { "WARN" } else { "FAIL" }
  Write-Host "$tag [$id] $name - $detail"
}
function Win { [W]::FindWindow("FLUTTER_RUNNER_WIN32_WINDOW", $title) }
function Procs { @(Get-Process -Name Chuanyun -ErrorAction SilentlyContinue) }
function Shot([string]$name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $path = Join-Path $Out "$Label-$name.png"
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "screenshot $path ($($b.Width)x$($b.Height))"
}
function Click([int]$x, [int]$y) {
  [W]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 150
  [W]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [W]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}
function WinRect {
  $r = New-Object W+RECT
  [W]::GetWindowRect((Win), [ref]$r) | Out-Null
  return $r
}

$exe = Join-Path $AppDir "Chuanyun.exe"
if (-not (Test-Path $exe)) { Rec "exe" "Chuanyun.exe exists" $false $exe; exit 1 }
Get-Process -Name Chuanyun -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "screen: $([System.Windows.Forms.SystemInformation]::VirtualScreen)"

# ---- launch ----
$p = Start-Process -FilePath $exe -WorkingDirectory $AppDir -PassThru
Start-Sleep -Seconds $StartupWait
$alive = -not $p.HasExited
Rec "alive" "Chuanyun.exe still running after ${StartupWait}s" $alive ($(if ($alive) { "pid $($p.Id)" } else { "exit code $($p.ExitCode)" }))
if (-not $alive) { Shot "crashed"; $results | ConvertTo-Json | Set-Content (Join-Path $Out "$Label-app-smoke.json"); exit 1 }

$mods = @()
try { $mods = @((Get-Process -Id $p.Id).Modules | ForEach-Object { $_.ModuleName }) } catch { $mods = @("error: $_") }
$coreLoaded = $mods -contains "hiddify-core.dll"
Rec "dll" "hiddify-core.dll loaded in the app process" $coreLoaded ("modules: " + (($mods | Where-Object { $_ -match "hiddify|cronet|flutter" }) -join ", "))

$listen = @(Get-NetTCPConnection -LocalPort 17078 -State Listen -ErrorAction SilentlyContinue)
$owner = if ($listen.Count) { $listen[0].OwningProcess } else { 0 }
Rec "grpc" "core gRPC listening on 127.0.0.1:17078 (owned by the app)" ($listen.Count -gt 0 -and $owner -eq $p.Id) "owner pid $owner, local $($listen | ForEach-Object { $_.LocalAddress } | Select-Object -First 1)"

if ($RepoDir) {
  Push-Location $RepoDir
  & dart run tool/smoke/core_smoke.dart --app-grpc --out $Out
  $grpcExit = $LASTEXITCODE
  Pop-Location
  Rec "grpc-token" "app core rejects gRPC calls without / with a wrong x-muse-token (see app-grpc.md)" ($grpcExit -eq 0) "dart exit $grpcExit"
}

$h = Win
$vis = ($h -ne [IntPtr]::Zero) -and [W]::IsWindowVisible($h)
$r = WinRect
$dpi = if ($h -ne [IntPtr]::Zero) { [W]::GetDpiForWindow($h) } else { 0 }
Rec "window" "main window titled (chuanyun) is visible" $vis "hwnd $h rect $($r.L),$($r.T)-$($r.R),$($r.B) size $($r.R-$r.L)x$($r.B-$r.T) dpi $dpi"
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Seconds 2
Shot "1-home"

# ---- the three tabs (rail on wide windows: icons at the left; bottom bar on narrow ones) ----
# Positions come from the layout: NavigationRail 80px wide, destinations from the top.
# They are best effort: the screenshots show whether the click landed.
$r = WinRect
$w = $r.R - $r.L
$scale = if ($dpi) { $dpi / 96.0 } else { 1.0 }
if ($w -ge 600 * $scale) {
  $x = $r.L + [int](48 * $scale)
  $tabs = @(@{ n = "2-config"; y = 2 }, @{ n = "3-settings"; y = 3 })
  foreach ($t in $tabs) {
    # rail: title bar ~31px, rail top padding 8, each destination 72px tall
    $y = $r.T + [int]((31 + 8 + 72 * ($t.y - 1) + 36) * $scale)
    Click $x $y
    Start-Sleep -Seconds 3
    Shot $t.n
  }
  # settings -> about (version line), 900x680 layout
  Click ($r.L + [int](490 * $scale)) ($r.T + [int](585 * $scale))
  Start-Sleep -Seconds 3
  Shot "3b-about"
  # tapping the current tab again returns to the settings root
  Click $x ($r.T + [int]((31 + 8 + 72 * 2 + 36) * $scale))
  Start-Sleep -Seconds 2
  $y = $r.T + [int]((31 + 8 + 36) * $scale)
  Click $x $y
  Start-Sleep -Seconds 2
  # home, no profile yet: the add row sits under the connect button (900x680 layout)
  Click ($r.L + [int](490 * $scale)) ($r.T + [int](493 * $scale))
  Start-Sleep -Seconds 3
  Shot "2b-add-profile"
  [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
  Start-Sleep -Seconds 2
}

# ---- maximized (content should stay centered with a max width) ----
[W]::ShowWindow($h, 3) | Out-Null
Start-Sleep -Seconds 3
Shot "4-maximized"
[W]::ShowWindow($h, 9) | Out-Null
Start-Sleep -Seconds 2

# ---- single instance: a second launch must not start a second process ----
Start-Process -FilePath $exe -WorkingDirectory $AppDir | Out-Null
Start-Sleep -Seconds 8
$n = (Procs).Count
Rec "single" "second launch keeps a single instance" ($n -eq 1) "processes: $n"
Get-Process -Name Chuanyun -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $p.Id } | Stop-Process -Force

# ---- close button hides to the tray, the process keeps running ----
[W]::PostMessage((Win), 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # WM_CLOSE
Start-Sleep -Seconds 4
$h2 = Win
$hidden = ($h2 -ne [IntPtr]::Zero) -and -not [W]::IsWindowVisible($h2)
Rec "tray" "closing the window hides it to the tray (process alive, window hidden)" ((-not $p.HasExited) -and $hidden) "alive $(-not $p.HasExited), hidden $hidden"
Shot "5-after-close"

# ---- launching again brings the hidden window back ----
Start-Process -FilePath $exe -WorkingDirectory $AppDir | Out-Null
Start-Sleep -Seconds 8
$h3 = Win
$back = ($h3 -ne [IntPtr]::Zero) -and [W]::IsWindowVisible($h3)
$n = (Procs).Count
Rec "restore" "launching again shows the hidden window (still one process)" ($back -and $n -eq 1) "visible $back, processes $n"
Shot "6-restored"

# ---- quit, logs ----
Get-Process -Name Chuanyun -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$logs = Join-Path $Out "$Label-logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
  Get-ChildItem -Path $root -Recurse -Depth 4 -Include "app.log", "box.log", "current-config.json", "go.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "Chuanyun|chuanyun|hiddify|Hiddify" } |
    ForEach-Object { $dest = Join-Path $logs (($_.FullName -replace "[:\\]", "_")); Copy-Item $_.FullName $dest -ErrorAction SilentlyContinue; Write-Host "log: $($_.FullName) ($($_.Length) B)" }
}

# ---- tray right-click menu (1.2; route modes 规则/全局 since 1.2.2): the app logs the menu it hands to the tray ----
function Cn([int[]]$cps) { [string]::new([char[]]$cps) }
$expect = @((Cn 0x8FDE,0x63A5), (Cn 0x89C4,0x5219), (Cn 0x5168,0x5C40), (Cn 0x663E,0x793A,0x7A97,0x53E3), (Cn 0x9000,0x51FA))
$menuLine = ""
Get-ChildItem -Path $logs -Filter "*app.log" -ErrorAction SilentlyContinue | ForEach-Object {
  $l = Get-Content -Path $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match "tray menu: " } | Select-Object -Last 1
  if ($l) { $menuLine = $l }
}
$menuOk = $menuLine -ne ""
$pos = 0
foreach ($e in $expect) {
  $i = $menuLine.IndexOf($e, $pos)
  if ($i -lt 0) { $menuOk = $false; break }
  $pos = $i + $e.Length
}
$menuDetail = if ($menuLine) { ($menuLine -replace "^.*tray menu: ", "") } else { "no 'tray menu:' line in app.log" }
Rec "tray-menu" "tray menu: connect / rule-global / show window / quit" $menuOk $menuDetail

$failed = @($results | Where-Object { -not $_.pass -and -not $_.optional }).Count
$md = "# Chuanyun app smoke test ($Label)`n`n| | check | detail |`n|---|---|---|`n"
foreach ($x in $results) {
  $m = if ($x.pass) { "PASS" } elseif ($x.optional) { "WARN" } else { "FAIL" }
  $md += "| $m | $($x.name) | $(($x.detail -replace '\|', '/')) |`n"
}
$md += "`nfailed (required): $failed`n"
Set-Content -Path (Join-Path $Out "$Label-app-smoke.md") -Value $md -Encoding UTF8
$results | ConvertTo-Json | Set-Content (Join-Path $Out "$Label-app-smoke.json") -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding UTF8 }
if ($failed -gt 0) { exit 1 } else { exit 0 }
