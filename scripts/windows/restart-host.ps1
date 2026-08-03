# Restart only the host with updated invite/TURN args (signaling stays up).
# Used after outbound tunnels rewrite the public URL.
param(
    [Parameter(Mandatory = $true)][string]$PublicUrl,
    [Parameter(Mandatory = $true)][string]$TurnUrl,
    [Parameter(Mandatory = $true)][string]$TurnUser,
    [Parameter(Mandatory = $true)][string]$TurnPass,
    [Parameter(Mandatory = $true)][string]$Session,
    [Parameter(Mandatory = $true)][string]$Pin
)

$ErrorActionPreference = "Stop"
$Run = Join-Path $env:LOCALAPPDATA "rohomieo-run"
$hostExe = Join-Path $Run "rohomieo-host.exe"
if (-not (Test-Path $hostExe)) {
    Write-Error "Missing $hostExe"
}

Get-Process rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.|^10\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet|Loopback' } |
    Select-Object -First 1).IPAddress

$signalingHost = "127.0.0.1"
$loop = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -eq "127.0.0.1" }
foreach ($c in @($loop)) {
    $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -ne "rohomieo-signaling") {
        if ($lan) { $signalingHost = $lan }
        break
    }
}

$hostArgs = @(
    "--signaling", ("wss://{0}:8443/ws" -f $signalingHost),
    "--public-url", $PublicUrl,
    "--turn-url", $TurnUrl,
    "--turn-user", $TurnUser,
    "--turn-pass", $TurnPass,
    "--session", $Session,
    "--pin", $Pin
)

Write-Host "Restarting host with tunnel invite: $PublicUrl" -ForegroundColor Cyan
$hostProc = Start-Process -FilePath $hostExe -WorkingDirectory $Run `
    -ArgumentList $hostArgs -PassThru -WindowStyle Normal
Start-Sleep -Seconds 2
if ($hostProc.HasExited) {
    Write-Error ("Host exited immediately (code {0})" -f $hostProc.ExitCode)
}
Write-Host "OK  host restarted" -ForegroundColor Green
