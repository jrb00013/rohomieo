# Start signaling (wait for :8443), then host. LAN = Windows IP, no WSL portproxy.
param([switch]$SkipFirewall)

$ErrorActionPreference = "Stop"
$Run = Join-Path $env:LOCALAPPDATA "rohomieo-run"

if (-not (Test-Path (Join-Path $Run "rohomieo-signaling.exe"))) {
    Write-Host "Run folder missing. In WSL:" -ForegroundColor Yellow
    Write-Host "  cd ~/rohomieo && ./scripts/build-windows-host.sh && ./scripts/sync-windows-run.sh"
    exit 1
}

if (-not $SkipFirewall) {
    try {
        $rule = Get-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -ErrorAction SilentlyContinue
        if (-not $rule) {
            New-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort 8443 -Profile Any -ErrorAction Stop | Out-Null
            Write-Host "OK  firewall: inbound TCP 8443" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Firewall: run enable-phone-access.ps1 as Administrator once (phone on Wi-Fi)"
    }
}

# Stop old instances
Get-Process rohomieo-signaling, rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force

$sigArgs = @(
    "--bind", "0.0.0.0:8443",
    "--web-root", (Join-Path $Run "web\dist"),
    "--cert", (Join-Path $Run "certs\cert.pem"),
    "--key", (Join-Path $Run "certs\key.pem")
)

Write-Host "Starting signaling..." -ForegroundColor Cyan
$sig = Start-Process -FilePath (Join-Path $Run "rohomieo-signaling.exe") `
    -WorkingDirectory $Run -ArgumentList $sigArgs -PassThru -WindowStyle Normal

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if ($sig.HasExited) {
        Write-Error "Signaling exited (code $($sig.ExitCode)). Check DLLs beside .exe in $Run"
    }
    $listen = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
    if ($listen) { $ready = $true; break }
}
if (-not $ready) {
    Write-Error "Signaling did not open port 8443 within 30s"
}

Write-Host "OK  signaling on :8443" -ForegroundColor Green

Write-Host "Starting host..." -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $Run "rohomieo-host.exe") `
    -WorkingDirectory $Run `
    -ArgumentList @("--signaling", "ws://127.0.0.1:8443/ws") `
    -WindowStyle Normal

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "Phone (same Wi-Fi):  https://${lan}:8443" -ForegroundColor Yellow
Write-Host "Session + PIN: host window" -ForegroundColor Green
Write-Host ""
