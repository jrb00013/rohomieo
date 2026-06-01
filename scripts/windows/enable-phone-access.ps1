# Run as Administrator. Works from any directory.
# Example:
#   cd \\wsl.localhost\Ubuntu\home\josep\rohomieo
#   powershell -ExecutionPolicy Bypass -File .\scripts\windows\enable-phone-access.ps1

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$wslIp = (wsl -e hostname -I).Trim().Split()[0]
if (-not $wslIp) { throw "Could not read WSL IP. Is WSL running?" }

Write-Host "WSL IP: $wslIp" -ForegroundColor Cyan

netsh interface portproxy delete v4tov4 listenport=8443 listenaddress=0.0.0.0 2>$null | Out-Null
netsh interface portproxy add v4tov4 listenport=8443 listenaddress=0.0.0.0 connectport=8443 connectaddress=$wslIp
netsh interface portproxy show all

$rule = Get-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort 8443 -Profile Any | Out-Null
    Write-Host "OK  firewall rule added" -ForegroundColor Green
} else {
    Write-Host "OK  firewall rule exists" -ForegroundColor Green
}

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Phone (same Wi-Fi):  https://${lan}:8443" -ForegroundColor Yellow
Write-Host "Accept the self-signed certificate, then enter Session ID + PIN." -ForegroundColor Green
