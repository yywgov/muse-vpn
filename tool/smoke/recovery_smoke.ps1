# Chuanyun Windows 1.2.1 recovery smoke test (windows-latest, Windows PowerShell 5.1).
# The app is connected in system-proxy mode to a local SOCKS node (tool/smoke/test_node.dart) and
# then broken in every way the user hit: status stream lost, core stopped behind the app's back,
# process suspended (sleep), window hidden to the tray and restored, process killed, crash exit,
# killed together with its guard. After each: the app must be connected again, OR the user's
# own proxy settings must be back and the internet must work. Screenshots of each state.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less scripts in the ANSI code page).
#
#   powershell -File tool/smoke/recovery_smoke.ps1 -AppDir <dir with Chuanyun.exe> -Out <dir> -RepoDir .
#
# Part of Chuanyun, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
param(
  [Parameter(Mandatory = $true)][string]$AppDir,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$RepoDir = ".",
  [int]$Port = 12334
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$AppDir = (Resolve-Path $AppDir).Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class R {
  [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);
  [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[R]::SetProcessDPIAware() | Out-Null

$title = [string]::new([char[]]@(0x7A7F, 0x4E91))
$exe = Join-Path $AppDir "Chuanyun.exe"
$guard = Join-Path $AppDir "ChuanyunGuard.exe"
$ctlPort = 17990
$token = "smoke" + [guid]::NewGuid().ToString("N")
$results = New-Object System.Collections.ArrayList
function Rec([string]$id, [string]$name, [bool]$pass, [string]$detail, [bool]$optional = $false) {
  [void]$results.Add([pscustomobject]@{ id = $id; name = $name; pass = $pass; optional = $optional; detail = $detail })
  $tag = if ($pass) { "PASS" } elseif ($optional) { "WARN" } else { "FAIL" }
  Write-Host "$tag [$id] $name - $detail"
}
function Shot([string]$name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $path = Join-Path $Out "recovery-$name.png"
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "screenshot $path"
}
function Win { [R]::FindWindow("FLUTTER_RUNNER_WIN32_WINDOW", $title) }
function AppProcs { @(Get-Process -Name Chuanyun -ErrorAction SilentlyContinue) }
function Ctl([string]$path) {
  $sep = if ($path.Contains("?")) { "&" } else { "?" }
  $raw = & curl.exe -s --noproxy "*" --max-time 15 "http://127.0.0.1:$ctlPort$path${sep}token=$token"
  if (-not $raw) { return $null }
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}
function StateText($s) {
  if ($null -eq $s) { return "no answer" }
  return "ui=$($s.ui) core=$($s.core) startedByUser=$($s.startedByUser) proxyOurs=$($s.proxyOurs)"
}
function WaitConnected([int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  $s = $null
  while ((Get-Date) -lt $deadline) {
    $s = Ctl "/state"
    if ($s -and $s.uiConnected -and $s.core -eq "started" -and $s.proxyOurs) { return @($true, $s) }
    Start-Sleep -Seconds 1
  }
  return @($false, $s)
}
# ChuanyunGuard.exe is a GUI-subsystem exe: PowerShell neither waits for it nor captures its
# output, so run it through System.Diagnostics.Process
function RunGuard([string[]]$guardArgs) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $guard
  $psi.Arguments = (($guardArgs | ForEach-Object { '"' + $_ + '"' }) -join " ")
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.CreateNoWindow = $true
  $pr = [System.Diagnostics.Process]::Start($psi)
  $o = $pr.StandardOutput.ReadToEnd()
  $pr.WaitForExit(15000) | Out-Null
  return $o.Trim()
}
function GuardStatus { return (RunGuard @("status", $env:TEMP, "$Port")) }
# a request through 127.0.0.1:<mixed port> (proves the core forwards)
function ViaProxy {
  $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 15 -x "http://127.0.0.1:$Port" "https://www.google.com/generate_204"
  return "$code"
}
# a request with the CURRENT Windows proxy settings (what every app on the PC gets)
function ViaSystemSettings {
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $null = $wc.DownloadString("http://www.msftconnecttest.com/connecttest.txt")
    return $true
  } catch { return $false }
}
# without any proxy
function Direct {
  $code = & curl.exe -s -o NUL -w "%{http_code}" --noproxy "*" --max-time 15 "https://www.google.com/generate_204"
  return "$code"
}
function LaunchApp {
  $env:CHUANYUN_SMOKE_CONTROL = "$ctlPort"
  $env:CHUANYUN_SMOKE_TOKEN = $token
  $p = Start-Process -FilePath $exe -WorkingDirectory $AppDir -PassThru
  Remove-Item Env:\CHUANYUN_SMOKE_CONTROL -ErrorAction SilentlyContinue
  Remove-Item Env:\CHUANYUN_SMOKE_TOKEN -ErrorAction SilentlyContinue
  return $p
}
function WaitCtl([int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    if (Ctl "/state") { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
}
function DataDir {
  foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
    $f = Get-ChildItem -Path $root -Recurse -Depth 5 -Filter "guard.log" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.DirectoryName }
  }
  return $null
}

if (-not (Test-Path $exe)) { Rec "exe" "Chuanyun.exe exists" $false $exe; exit 1 }
Rec "guard-exe" "ChuanyunGuard.exe is shipped next to Chuanyun.exe" (Test-Path $guard) $guard
if (-not (Test-Path $guard)) { exit 1 }
Get-Process -Name Chuanyun, ChuanyunGuard -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

# ---- the user's own proxy settings: off, but with a server and bypass list filled in ----
# (restoring must bring these back, not just blank everything)
$origServer = "original.example:8080"
$applied = RunGuard @("apply", $env:TEMP, "$Port", "0x1", $origServer, "<local>")
Write-Host "apply: $applied"
$st0 = GuardStatus
Rec "orig" "user's own proxy settings in place (direct, server original.example:8080)" ($st0 -match "ours=0" -and $st0 -match "original.example:8080") $st0

# ---- test node + profile ----
$nodeExe = Join-Path $Out "test_node.exe"
Push-Location $RepoDir
& dart compile exe tool/smoke/test_node.dart -o $nodeExe | Out-Null
Pop-Location
$node = Start-Process -FilePath $nodeExe -ArgumentList "--port", "11080", "--counters", "11990" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$profilePath = Join-Path $Out "smoke-profile.json"
'{"outbounds":[{"type":"socks","tag":"smoke-node","server":"127.0.0.1","server_port":11080,"version":"5"}]}' | Set-Content -Path $profilePath -Encoding ASCII
$nodeOk = (& curl.exe -s -o NUL -w "%{http_code}" --max-time 15 --socks5-hostname 127.0.0.1:11080 "https://www.google.com/generate_204") -eq "204"
Rec "node" "local SOCKS test node forwards to the internet" $nodeOk "127.0.0.1:11080"

# ---- launch, import, connect ----
$p = LaunchApp
$ctlUp = WaitCtl 60
Rec "launch" "app up with its smoke control port" $ctlUp "pid $($p.Id)"
if (-not $ctlUp) { Shot "launch-failed"; $results | ConvertTo-Json | Set-Content (Join-Path $Out "recovery-smoke.json"); exit 1 }
$imp = Ctl ("/import?path=" + [uri]::EscapeDataString($profilePath))
Rec "import" "profile imported and active" ($imp -and $imp.ok) ($imp | ConvertTo-Json -Compress)
Start-Sleep -Seconds 2
Ctl "/connect" | Out-Null
$c = WaitConnected 45
$guardRunning = @(Get-Process -Name ChuanyunGuard -ErrorAction SilentlyContinue).Count -ge 1
Rec "connect" "connected in system-proxy mode (UI connected, core started, system proxy -> 127.0.0.1:$Port)" $c[0] (StateText $c[1])
Rec "guard-running" "ChuanyunGuard.exe is watching the app" $guardRunning "processes: $(@(Get-Process -Name ChuanyunGuard -ErrorAction SilentlyContinue).Count)"
$vp = ViaProxy
Rec "via-proxy" "request through the mixed port works (node used)" ($vp -eq "204") "http $vp"
Rec "via-system" "request with the Windows proxy settings works" (ViaSystemSettings) (GuardStatus)
[R]::SetForegroundWindow((Win)) | Out-Null
Start-Sleep -Seconds 3
Shot "1-connected"
$dataDir = DataDir
Write-Host "data dir: $dataDir"

# ---- (b) the status stream breaks while the core keeps running ----
Ctl "/break-status" | Out-Null
Start-Sleep -Seconds 6
$s = Ctl "/state"
Rec "status-break" "status stream lost while the core runs: UI stays connected" ($s -and $s.uiConnected -and $s.core -eq "started") (StateText $s)
Shot "2-after-status-break"

# ---- (1) the core stops without the app asking (not the user) ----
Ctl "/core-stop" | Out-Null
Start-Sleep -Seconds 1
$mid = GuardStatus
$c = WaitConnected 45
$vp = ViaProxy
Rec "core-stop" "core stopped behind the app's back: reconnected automatically" ($c[0] -and $vp -eq "204") ((StateText $c[1]) + "; via proxy $vp; right after stop: $mid")
Start-Sleep -Seconds 8
Shot "3-after-core-stop"

# ---- (c) sleep: the whole process is suspended for 45 s, then resumed ----
$h = (Get-Process -Id $p.Id).Handle
[R]::NtSuspendProcess($h) | Out-Null
Start-Sleep -Seconds 45
$during = GuardStatus
[R]::NtResumeProcess($h) | Out-Null
Start-Sleep -Seconds 3
$c = WaitConnected 70
$vp = ViaProxy
Rec "suspend-guard" "while the app was frozen the guard put the user's settings back (port silent)" ($during -match "ours=0") $during
Rec "suspend" "after a 45 s suspend (sleep): connected and forwarding again" ($c[0] -and $vp -eq "204") ((StateText $c[1]) + "; via proxy $vp")
Ctl "/resume" | Out-Null
Start-Sleep -Seconds 4
$s = Ctl "/state"
Rec "resume-path" "resume path (window restore / wake) keeps it connected, no reconnect" ($s -and $s.uiConnected -and $s.core -eq "started") (StateText $s)
Shot "4-after-suspend"

# ---- window to the tray and back ----
[R]::PostMessage((Win), 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # WM_CLOSE -> tray
Start-Sleep -Seconds 20
$s = Ctl "/state"
$hidden = -not [R]::IsWindowVisible((Win))
Rec "tray-hidden" "hidden in the tray for 20 s: still connected" ($hidden -and $s -and $s.uiConnected -and $s.core -eq "started") ("hidden $hidden; " + (StateText $s))
Shot "5-tray"
Start-Process -FilePath $exe -WorkingDirectory $AppDir | Out-Null   # second launch = show window
Start-Sleep -Seconds 6
$s = Ctl "/state"
$shown = [R]::IsWindowVisible((Win))
Rec "tray-restore" "window restored from the tray: shows connected (no 'disconnected' flash)" ($shown -and $s -and $s.uiConnected) ("visible $shown; " + (StateText $s))
[R]::SetForegroundWindow((Win)) | Out-Null
Start-Sleep -Seconds 2
Shot "6-restored-from-tray"

# ---- (a) the app process is killed while connected ----
Stop-Process -Id $p.Id -Force
Start-Sleep -Seconds 2
$st = GuardStatus
$sys = ViaSystemSettings
$d = Direct
Rec "kill-restore" "app killed while connected: user's own settings restored at once (not blank)" ($st -match "ours=0" -and $st -match "original.example:8080") $st
Rec "kill-internet" "after the kill the PC is online (Windows proxy settings work, direct works)" ($sys -and $d -eq "204") "system settings $sys, direct $d"
$n = (AppProcs).Count
Rec "kill-no-relaunch" "a kill (not a crash) is not relaunched" ($n -eq 0) "app processes: $n"
Shot "7-after-kill"

# ---- crash exit: guard restores the proxy and relaunches the app, which reconnects ----
$p = LaunchApp
$up = WaitCtl 60
$c = WaitConnected 45
Rec "restart-restores" "next launch restores the connection the user had on" $c[0] (StateText $c[1])
Ctl "/crash" | Out-Null
Start-Sleep -Milliseconds 1500
$st = GuardStatus
Rec "crash-restore" "crash exit: proxy settings restored right away" ($st -match "ours=0") $st
$relaunched = $false
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
  $procs = AppProcs
  if ($procs.Count -ge 1 -and $procs[0].Id -ne $p.Id) { $relaunched = $true; break }
  Start-Sleep -Seconds 1
}
Rec "crash-relaunch" "crash exit: the guard relaunched the app" $relaunched "processes: $((AppProcs | ForEach-Object { $_.Id }) -join ',')"
$up = WaitCtl 60
$c = WaitConnected 60
$hiddenAfter = -not [R]::IsWindowVisible((Win))
Rec "crash-reconnect" "relaunched app reconnected on its own (window stays in the tray)" $c[0] ((StateText $c[1]) + "; window hidden $hiddenAfter")
Shot "8-after-crash-relaunch"

# ---- (d) killed together with its guard: the stale proxy is left; next launch clears it ----
$procs = AppProcs
Get-Process -Name ChuanyunGuard -ErrorAction SilentlyContinue | Stop-Process -Force
$procs | Stop-Process -Force
Start-Sleep -Seconds 2
$st = GuardStatus
Rec "stale-left" "app + guard killed: system proxy still points at the dead port (setup for the next check)" ($st -match "ours=1") $st
$sysDead = ViaSystemSettings
Rec "stale-offline" "(that is the 'whole PC offline' state)" (-not $sysDead) "system settings work: $sysDead" $true
$p = LaunchApp
$up = WaitCtl 60
$glog = if ($dataDir) { Get-Content -Path (Join-Path $dataDir "guard.log") -ErrorAction SilentlyContinue } else { @() }
$startupRestore = @($glog | Where-Object { $_ -match "restore\(startup\)" }).Count -ge 1
Rec "stale-cleared" "next launch restored the leftover proxy at start-up (guard.log: restore(startup))" $startupRestore (($glog | Where-Object { $_ -match "restore\(startup\)" } | Select-Object -Last 1) -join "")
$c = WaitConnected 45
Rec "stale-reconnect" "and reconnected" $c[0] (StateText $c[1])

# ---- the user disconnects: own settings back, no auto-reconnect ----
Ctl "/disconnect" | Out-Null
Start-Sleep -Seconds 25
$s = Ctl "/state"
$st = GuardStatus
Rec "user-disconnect" "user disconnect: stays disconnected, own settings restored (server kept)" ($s -and -not $s.uiConnected -and -not $s.startedByUser -and $st -match "ours=0" -and $st -match "original.example:8080") ((StateText $s) + "; " + $st)
Rec "user-disconnect-internet" "after disconnect the PC is online" (ViaSystemSettings) ""
[R]::SetForegroundWindow((Win)) | Out-Null
Start-Sleep -Seconds 2
Shot "9-user-disconnected"

# ---- logs ----
Get-Process -Name Chuanyun, ChuanyunGuard -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Process -Id $node.Id -Force -ErrorAction SilentlyContinue
RunGuard @("apply", $env:TEMP, "$Port", "0x1") | Out-Null
$logs = Join-Path $Out "recovery-logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
if ($dataDir) {
  Get-ChildItem -Path $dataDir -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object { Copy-Item $_.FullName (Join-Path $logs $_.Name) }
}
foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
  Get-ChildItem -Path $root -Recurse -Depth 4 -Include "app.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "Chuanyun|chuanyun|hiddify|Hiddify" } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $logs ("app-" + ($_.FullName -replace "[:\\]", "_"))) -ErrorAction SilentlyContinue }
}
$dlog = Join-Path $logs "disconnect.log"
if (Test-Path $dlog) {
  $lines = @(Get-Content -Path $dlog -Encoding UTF8)
  Rec "disconnect-log" "disconnect.log records the recoveries (for diagnostics)" ($lines.Count -ge 3) "$($lines.Count) lines"
} else {
  Rec "disconnect-log" "disconnect.log records the recoveries (for diagnostics)" $false "missing"
}

$failed = @($results | Where-Object { -not $_.pass -and -not $_.optional }).Count
$md = "# Chuanyun recovery smoke test`n`n| | check | detail |`n|---|---|---|`n"
foreach ($x in $results) {
  $m = if ($x.pass) { "PASS" } elseif ($x.optional) { "WARN" } else { "FAIL" }
  $md += "| $m | $($x.name) | $(($x.detail -replace '\|', '/')) |`n"
}
$md += "`nfailed (required): $failed`n"
Set-Content -Path (Join-Path $Out "recovery-smoke.md") -Value $md -Encoding UTF8
$results | ConvertTo-Json | Set-Content (Join-Path $Out "recovery-smoke.json") -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding UTF8 }
if ($failed -gt 0) { exit 1 } else { exit 0 }
