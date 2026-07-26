#Requires -RunAsAdministrator
# Install RohomieoBroker Windows service (UAC once). After this, unprivileged
# rohomieo-broker-ctl.exe talks over \\.\pipe\RohomieoBroker — no more UAC.
param(
    [string]$BrokerExe = "",
    [string]$CtlExe = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$ServiceName = "RohomieoBroker"
$DisplayName = "Rohomieo Elevated Broker"
$InstallDir = Join-Path $env:ProgramFiles "Rohomieo"
$DestBroker = Join-Path $InstallDir "rohomieo-broker.exe"
$DestCtl = Join-Path $InstallDir "rohomieo-broker-ctl.exe"

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m) { Write-Host "OK  $m" -ForegroundColor Green }

if ($Uninstall) {
    Write-Step "Uninstall $ServiceName"
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne "Stopped") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 1
    }
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
    }
    Write-Ok "uninstalled"
    exit 0
}

$Run = Join-Path $env:LOCALAPPDATA "rohomieo-run"
if (-not $BrokerExe) {
    $cand = @(
        (Join-Path $Run "rohomieo-broker.exe"),
        (Join-Path $Run "staging\rohomieo-broker.exe")
    )
    foreach ($c in $cand) { if (Test-Path $c) { $BrokerExe = $c; break } }
}
if (-not $CtlExe) {
    $cand = @(
        (Join-Path $Run "rohomieo-broker-ctl.exe"),
        (Join-Path $Run "staging\rohomieo-broker-ctl.exe")
    )
    foreach ($c in $cand) { if (Test-Path $c) { $CtlExe = $c; break } }
}

if (-not (Test-Path $BrokerExe)) {
    Write-Error "Missing broker exe. From WSL: ./scripts/build-windows-broker.sh && ./scripts/sync-windows-run.sh"
}
if (-not (Test-Path $CtlExe)) {
    Write-Error "Missing broker-ctl exe."
}

Write-Step "Install to $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

Copy-Item -Force $BrokerExe $DestBroker
Copy-Item -Force $CtlExe $DestCtl
# Also keep ctl next to run dir for WSL/scripts convenience
New-Item -ItemType Directory -Force -Path $Run | Out-Null
Copy-Item -Force $DestCtl (Join-Path $Run "rohomieo-broker-ctl.exe")

if ($existing) {
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

Write-Step "Create service $ServiceName (LocalSystem, auto-start)"
$binPath = "`"$DestBroker`""
New-Service -Name $ServiceName -BinaryPathName $binPath -DisplayName $DisplayName `
    -Description "Elevated broker for Rohomieo firewall, Defender exclusions, and process control." `
    -StartupType Automatic | Out-Null

# Allow interactive desktop for CreateProcessAsUser UI (host window)
sc.exe sidtype $ServiceName unrestricted | Out-Null

Start-Service -Name $ServiceName
Start-Sleep -Seconds 1
$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne "Running") {
    Write-Error "Service failed to start — see $env:ProgramData\Rohomieo\broker.log"
}

# Smoke-test pipe
$ctl = $DestCtl
$ping = & $ctl PING 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Pipe PING failed: $ping"
}
Write-Ok "service running; pipe \\.\pipe\RohomieoBroker OK"

# One-shot privileged setup the broker owns going forward
Write-Step "FIREWALL_ADD + DEFENDER_ADD (via broker)"
& $ctl FIREWALL_ADD | Out-Host
& $ctl DEFENDER_ADD $Run | Out-Host
& $ctl DEFENDER_ADD (Join-Path $Run "rohomieo-host.exe") | Out-Host
& $ctl DEFENDER_ADD (Join-Path $Run "rohomieo-signaling.exe") | Out-Host

Write-Ok "RohomieoBroker installed — later ./install.sh needs no UAC for allow/start"
Write-Host "Uninstall: powershell -File install-broker.ps1 -Uninstall" -ForegroundColor Yellow
exit 0
