# Chuanyun installer smoke test on windows-latest (Windows PowerShell 5.1, runner is admin).
# Silent install -> files, shortcuts, uninstall entry -> UI smoke of the installed copy ->
# upgrade over a running copy (it must be closed and replaced) -> silent uninstall -> cleaned up.
# ASCII only on purpose (PowerShell 5.1 reads BOM-less scripts in the ANSI code page).
#
#   powershell -File tool/smoke/installer_smoke.ps1 -Setup out\Chuanyun-Windows-x64-Setup.exe -Out smoke -RepoDir .
#
# Part of Chuanyun, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.
param(
  [Parameter(Mandatory = $true)][string]$Setup,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$RepoDir = ""
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Setup = (Resolve-Path $Setup).Path
$Out = (Resolve-Path $Out).Path
$name = [string]::new([char[]]@(0x7A7F, 0x4E91))   
$dir = Join-Path $env:ProgramFiles "Chuanyun"
$exe = Join-Path $dir "Chuanyun.exe"
$startMenu = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$name.lnk"
$desktop = Join-Path $env:PUBLIC "Desktop\$name.lnk"
$uninstKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8F3C2A51-6B7E-4D2A-9C1F-3E5D7A9B0C11}_is1"

$results = New-Object System.Collections.ArrayList
function Rec([string]$id, [string]$n, [bool]$pass, [string]$detail) {
  [void]$results.Add([pscustomobject]@{ id = $id; name = $n; pass = $pass; detail = $detail })
  Write-Host "$(if ($pass) { 'PASS' } else { 'FAIL' }) [$id] $n - $detail"
}
function RunSetup([string]$exePath, [string[]]$a) {
  $p = Start-Process -FilePath $exePath -ArgumentList $a -PassThru -Wait
  return $p.ExitCode
}

# ---- install ----
$size = (Get-Item $Setup).Length
$code = RunSetup $Setup @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/TASKS=desktopicon", "/LOG=`"$Out\install.log`"")
Rec "install" "silent install exits 0" ($code -eq 0) "exit $code, setup $size B"
Rec "files" "installed to Program Files\Chuanyun with the core" ((Test-Path $exe) -and (Test-Path (Join-Path $dir "hiddify-core.dll")) -and (Test-Path (Join-Path $dir "data\flutter_assets"))) $dir
Rec "startmenu" "start menu shortcut" (Test-Path $startMenu) $startMenu
Rec "desktop" "desktop shortcut (task desktopicon)" (Test-Path $desktop) $desktop
$u = Get-ItemProperty -Path $uninstKey -ErrorAction SilentlyContinue
Rec "uninstall-entry" "Apps & features entry" ($null -ne $u) "$($u.DisplayName) $($u.DisplayVersion) $($u.UninstallString)"

# ---- the installed copy runs (UI smoke, screenshots prefixed 'installed') ----
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "app_smoke.ps1") -AppDir $dir -Out $Out -Label installed -RepoDir $RepoDir
Rec "installed-app" "installed copy passes the UI smoke test (installed-app-smoke.md)" ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"

# ---- upgrade while the app is running: it gets closed and replaced, then relaunched (/RELAUNCH) ----
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 12
$code = RunSetup $Setup @("/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/RELAUNCH", "/LOG=`"$Out\upgrade.log`"")
Start-Sleep -Seconds 10
$old = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
$new = @(Get-Process -Name Chuanyun -ErrorAction SilentlyContinue)
Rec "upgrade" "upgrade over a running copy exits 0, old process closed" (($code -eq 0) -and ($null -eq $old)) "exit $code, old process alive: $($null -ne $old)"
Rec "relaunch" "/RELAUNCH starts the new version again" ($new.Count -ge 1) "processes after upgrade: $($new.Count)"
Get-Process -Name Chuanyun -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# ---- uninstall ----
$unins = Join-Path $dir "unins000.exe"
$code = if (Test-Path $unins) { RunSetup $unins @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=`"$Out\uninstall.log`"") } else { -1 }
Start-Sleep -Seconds 3
Rec "uninstall" "silent uninstall exits 0" ($code -eq 0) "exit $code"
Rec "uninstall-clean" "files, shortcuts and Apps entry removed" ((-not (Test-Path $exe)) -and (-not (Test-Path $startMenu)) -and (-not (Test-Path $desktop)) -and (-not (Test-Path $uninstKey))) "exe $(Test-Path $exe), start $(Test-Path $startMenu), desktop $(Test-Path $desktop), entry $(Test-Path $uninstKey)"

$failed = @($results | Where-Object { -not $_.pass }).Count
$md = "# Chuanyun installer smoke test`n`n| | check | detail |`n|---|---|---|`n"
foreach ($x in $results) { $md += "| $(if ($x.pass) { 'PASS' } else { 'FAIL' }) | $($x.name) | $(($x.detail -replace '\|', '/')) |`n" }
$md += "`nfailed: $failed`n"
Set-Content -Path (Join-Path $Out "installer-smoke.md") -Value $md -Encoding UTF8
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $md -Encoding UTF8 }
if ($failed -gt 0) { exit 1 } else { exit 0 }
