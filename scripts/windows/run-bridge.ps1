# Start signaling (wait for :8443), then host. LAN = Windows IP, no WSL portproxy.
# Optional reachability overrides (from scripts/run.sh --global / --local):
#   -PublicUrl  https://PUBLIC_OR_LAN:8443
#   -TurnUrl / -TurnUser / -TurnPass
#   -Session / -Pin  (fixed invite so run.sh can print the web-UI QR)
param(
    [switch]$SkipFirewall,
    [string]$PublicUrl = "",
    [string]$TurnUrl = "",
    [string]$TurnUser = "",
    [string]$TurnPass = "",
    [string]$Session = "",
    [string]$Pin = ""
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

Get-ChildItem -Path $Run -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($_.FullName + ":Zone.Identifier") -Force -ErrorAction SilentlyContinue
    }

Get-Process rohomieo-signaling, rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

$stage = Join-Path $Run "staging"
if (Test-Path (Join-Path $stage "rohomieo-signaling.exe")) {
    Write-Host "Promoting staging -> run dir..." -ForegroundColor Cyan
    Get-ChildItem -Path $stage -File | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $Run $_.Name)
    }
    $stageWeb = Join-Path $stage "web\dist"
    $runWeb = Join-Path $Run "web\dist"
    if (Test-Path $stageWeb) {
        New-Item -ItemType Directory -Force -Path $runWeb | Out-Null
        Copy-Item -Force -Recurse (Join-Path $stageWeb "*") $runWeb
    }
    $stageCerts = Join-Path $stage "certs"
    $runCerts = Join-Path $Run "certs"
    if (Test-Path $stageCerts) {
        New-Item -ItemType Directory -Force -Path $runCerts | Out-Null
        Copy-Item -Force (Join-Path $stageCerts "*") $runCerts
    }
}

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
    $listen = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.OwningProcess -eq $sig.Id }
    if ($listen) { $ready = $true; break }
}
if (-not $ready) {
    Write-Error "Signaling did not open port 8443 within 30s (is another app bound there?)"
}

Write-Host "OK  signaling on :8443" -ForegroundColor Green

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

$signalingHost = "127.0.0.1"
$loop = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -eq "127.0.0.1" }
foreach ($c in @($loop)) {
    $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -ne "rohomieo-signaling") {
        if ($lan) { $signalingHost = $lan }
        Write-Host ("Note: 127.0.0.1:8443 owned by {0} - host dials {1}" -f $proc.ProcessName, $signalingHost) -ForegroundColor DarkYellow
        break
    }
}

$hostArgs = @("--signaling", ("wss://{0}:8443/ws" -f $signalingHost))
if ($PublicUrl) { $hostArgs += @("--public-url", $PublicUrl) }
if ($TurnUrl) { $hostArgs += @("--turn-url", $TurnUrl) }
if ($TurnUser) { $hostArgs += @("--turn-user", $TurnUser) }
if ($TurnPass) { $hostArgs += @("--turn-pass", $TurnPass) }
if ($Session) { $hostArgs += @("--session", $Session) }
if ($Pin) { $hostArgs += @("--pin", $Pin) }

Write-Host "Starting host..." -ForegroundColor Cyan
try {
    $hostProc = Start-Process -FilePath (Join-Path $Run "rohomieo-host.exe") `
        -WorkingDirectory $Run `
        -ArgumentList $hostArgs `
        -PassThru -WindowStyle Normal -ErrorAction Stop
} catch {
    Write-Warning "Host blocked by App Control. From WSL run: ./install.sh --allow"
    Write-Warning "Or Windows Security -> Smart App Control -> Off / Evaluation, then re-run."
    throw
}

Start-Sleep -Seconds 2
if ($hostProc.HasExited) {
    Write-Error ("Host exited immediately (code {0}). Signaling URL was wss://{1}:8443/ws" -f $hostProc.ExitCode, $signalingHost)
}

Write-Host ""
if ($PublicUrl) {
    Write-Host "Web UI invite base: $PublicUrl" -ForegroundColor Yellow
    if ($Session -and $Pin) {
        Write-Host ("Session: {0}  PIN: {1}" -f $Session, $Pin) -ForegroundColor Green
        Write-Host "Scan the QR printed in the WSL/terminal (or host window)." -ForegroundColor Green
    }
    if ($TurnUrl) {
        Write-Host "TURN relay:         $TurnUrl" -ForegroundColor DarkGray
    }
}
if ($lan) {
    Write-Host "Phone (same Wi-Fi):  https://${lan}:8443" -ForegroundColor Yellow
}
Write-Host "Keep this window open while the session runs." -ForegroundColor DarkGray
Write-Host ""

try {
    Wait-Process -Id $sig.Id
} catch {
}
Get-Process rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not $sig.HasExited) {
    Stop-Process -Id $sig.Id -Force -ErrorAction SilentlyContinue
}
