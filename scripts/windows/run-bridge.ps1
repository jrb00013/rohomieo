# Start signaling (wait for :8443), then host. LAN = Windows IP, no WSL portproxy.
# Optional reachability overrides (from scripts/run.sh --global):
#   -PublicUrl  https://PUBLIC_IP:8443
#   -TurnUrl    turn:PUBLIC_IP:3478
#   -TurnUser / -TurnPass
param(
    [switch]$SkipFirewall,
    [string]$PublicUrl = "",
    [string]$TurnUrl = "",
    [string]$TurnUser = "",
    [string]$TurnPass = ""
)

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
        if ($TurnUrl) {
            $turnRule = Get-NetFirewallRule -DisplayName "Rohomieo-TURN" -ErrorAction SilentlyContinue
            if (-not $turnRule) {
                New-NetFirewallRule -DisplayName "Rohomieo-TURN" -Direction Inbound -Action Allow `
                    -Protocol UDP -LocalPort 3478 -Profile Any -ErrorAction SilentlyContinue | Out-Null
                New-NetFirewallRule -DisplayName "Rohomieo-TURN-TCP" -Direction Inbound -Action Allow `
                    -Protocol TCP -LocalPort 3478 -Profile Any -ErrorAction SilentlyContinue | Out-Null
                Write-Host "OK  firewall: inbound UDP/TCP 3478 (TURN)" -ForegroundColor Green
            }
        }
    } catch {
        Write-Warning "Firewall: run enable-phone-access.ps1 as Administrator once (phone on Wi-Fi)"
    }
}

# Clear MOTW so Smart App Control / Defender are less likely to block
Get-ChildItem -Path $Run -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($_.FullName + ":Zone.Identifier") -Force -ErrorAction SilentlyContinue
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

$hostArgs = @("--signaling", "wss://127.0.0.1:8443/ws")
if ($PublicUrl) { $hostArgs += @("--public-url", $PublicUrl) }
if ($TurnUrl) { $hostArgs += @("--turn-url", $TurnUrl) }
if ($TurnUser) { $hostArgs += @("--turn-user", $TurnUser) }
if ($TurnPass) { $hostArgs += @("--turn-pass", $TurnPass) }

Write-Host "Starting host..." -ForegroundColor Cyan
try {
    Start-Process -FilePath (Join-Path $Run "rohomieo-host.exe") `
        -WorkingDirectory $Run `
        -ArgumentList $hostArgs `
        -WindowStyle Normal -ErrorAction Stop
} catch {
    Write-Warning "Host blocked by App Control. From WSL run: ./install.sh --allow"
    Write-Warning "Or Windows Security → Smart App Control → Off / Evaluation, then re-run."
    throw
}

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
if ($PublicUrl) {
    Write-Host "Internet (global):  $PublicUrl" -ForegroundColor Yellow
    if ($TurnUrl) {
        Write-Host "TURN relay:         $TurnUrl" -ForegroundColor DarkGray
    }
}
Write-Host "Phone (same Wi-Fi):  https://${lan}:8443" -ForegroundColor Yellow
Write-Host "Session + PIN: host window" -ForegroundColor Green
Write-Host ""
