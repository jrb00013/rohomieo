# Expose WSL Rohomieo + assist WireGuard on WSL2. Run as Administrator.
# UDP 51820: requires mirrored networking (use wsl-enable-mirrored-network.ps1).
# TCP 8443: portproxy to WSL for signaling when not using mirrored mode.

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$listenWg = 51820
$listenWeb = 8443

function Get-WslIp {
    $out = wsl -e hostname -I 2>$null
    if (-not $out) { throw "Could not get WSL IP — is WSL running?" }
    return ($out.Trim() -split '\s+')[0]
}

Write-Host "==> WSL2 bridge port setup" -ForegroundColor Cyan

$wslIp = Get-WslIp
Write-Host "WSL IP: $wslIp"

# Check mirrored mode hint
$wslconf = Join-Path $env:USERPROFILE ".wslconfig"
if (Test-Path $wslconf) {
    $c = Get-Content $wslconf -Raw
    if ($c -match "networkingMode\s*=\s*mirrored") {
        Write-Host "OK  mirrored networking enabled in .wslconfig" -ForegroundColor Green
    } else {
        Write-Warning "mirrored networking NOT set — UDP WireGuard may not reach WSL from LAN"
        Write-Warning "Run: powershell -File scripts\windows\wsl-enable-mirrored-network.ps1"
    }
} else {
    Write-Warning "No .wslconfig — run wsl-enable-mirrored-network.ps1 first"
}

# Windows Firewall: allow inbound UDP WireGuard + TCP web
$rules = @(
    @{ Name = "Rohomieo-WireGuard-UDP"; Port = $listenWg; Proto = "UDP" },
    @{ Name = "Rohomieo-Signaling-TCP"; Port = $listenWeb; Proto = "TCP" }
)
foreach ($r in $rules) {
    $existing = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "OK  firewall rule $($r.Name) exists" -ForegroundColor Green
    } else {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow `
            -Protocol $r.Proto -LocalPort $r.Port -Profile Any | Out-Null
        Write-Host "OK  added firewall rule $($r.Name)" -ForegroundColor Green
    }
}

# TCP portproxy for signaling (works without mirrored mode)
netsh interface portproxy delete v4tov4 listenport=$listenWeb listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenport=$listenWeb listenaddress=0.0.0.0 `
    connectport=$listenWeb connectaddress=$wslIp
Write-Host "OK  TCP $listenWeb -> ${wslIp}:$listenWeb (portproxy)" -ForegroundColor Green

Write-Host ""
Write-Host "UDP $listenWg (WireGuard):" -ForegroundColor Cyan
Write-Host "  With mirrored networking, wg in WSL listens on all Windows interfaces."
Write-Host "  Forward router UDP $listenWg -> this PC's LAN IP."
Write-Host ""
Write-Host "Phone on VPN: http://10.8.0.1:$listenWeb" -ForegroundColor Green
Write-Host "Same Wi-Fi test: http://$(hostname):$listenWeb or http://127.0.0.1:$listenWeb"
Write-Host ""
