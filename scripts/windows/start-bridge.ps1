# Signaling + host on Windows (phone: https://YOUR_LAN_IP:8443). Bundles runtime DLLs.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

$sigExe = Join-Path $root "target\release\rohomieo-signaling.exe"
if (-not (Test-Path $sigExe)) {
    Write-Host "==> Building from WSL..." -ForegroundColor Cyan
    $wslRoot = (wsl wslpath -u "`"$root`"").Trim()
    wsl -e bash -lc "cd '$wslRoot' && ./scripts/build-windows-host.sh"
}

$run = & (Join-Path $PSScriptRoot "deploy-run-dir.ps1") -RepoRoot $root
Write-Host "Run dir: $run" -ForegroundColor DarkGray

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Phone (same Wi-Fi):  https://${lan}:8443" -ForegroundColor Yellow
Write-Host "Tap Advanced / Proceed if certificate warning." -ForegroundColor Green
Write-Host ""

try {
    if (-not (Get-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort 8443 -Profile Any | Out-Null
        Write-Host "OK  firewall rule added" -ForegroundColor Green
    }
} catch {
    Write-Warning "Run as Admin once: scripts\windows\enable-phone-access.ps1"
}

$sigScript = Join-Path $PSScriptRoot "start-signaling.ps1"
$hostScript = Join-Path $PSScriptRoot "start-host.ps1"

Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $sigScript
Start-Sleep -Seconds 2
Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $hostScript

Write-Host "Started signaling + host." -ForegroundColor Cyan
