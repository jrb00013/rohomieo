# Run as Administrator once — firewall for phone on same Wi-Fi (no portproxy needed when using Windows signaling).
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "Rohomieo: allow inbound TCP 8443 on Private/Public Wi-Fi" -ForegroundColor Cyan

# Remove stale WSL portproxy if any (Windows signaling binds LAN directly)
netsh interface portproxy delete v4tov4 listenport=8443 listenaddress=0.0.0.0 2>$null | Out-Null

$rule = Get-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort 8443 -Profile Any | Out-Null
    Write-Host "OK  firewall rule added" -ForegroundColor Green
} else {
    Write-Host "OK  firewall rule already exists" -ForegroundColor Green
}

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Then run (no Admin):" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\windows\run-bridge.ps1"
Write-Host ""
Write-Host "Phone:  https://${lan}:8443" -ForegroundColor Yellow
Write-Host ""
