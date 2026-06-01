# Enable WSL2 mirrored networking (Windows 11 22H2+) so UDP WireGuard in WSL is reachable on your LAN IP.
# Run in PowerShell (no Admin required for writing .wslconfig).

$ErrorActionPreference = "Stop"
$wslconf = Join-Path $env:USERPROFILE ".wslconfig"

$block = @"
[wsl2]
# Rohomieo: expose WSL services (WireGuard UDP, signaling TCP) on Windows network adapters
networkingMode=mirrored
dnsTunneling=true
firewall=true
ipv6=true

[experimental]
hostAddressLoopback=true
"@

if (Test-Path $wslconf) {
    $existing = Get-Content $wslconf -Raw
    if ($existing -match "networkingMode\s*=\s*mirrored") {
        Write-Host "OK  .wslconfig already has networkingMode=mirrored" -ForegroundColor Green
    } else {
        Write-Host "Appending mirrored networking block to $wslconf"
        Add-Content -Path $wslconf -Value "`n$block"
    }
} else {
    Set-Content -Path $wslconf -Value $block
    Write-Host "Created $wslconf" -ForegroundColor Green
}

Write-Host ""
Write-Host "Required: restart WSL from PowerShell:" -ForegroundColor Yellow
Write-Host "  wsl --shutdown"
Write-Host "  wsl"
Write-Host ""
Write-Host "Then in WSL:" -ForegroundColor Cyan
Write-Host "  ./scripts/wireguard-wsl-bridge.sh up"
Write-Host "  ./scripts/start-wsl-bridge.sh"
