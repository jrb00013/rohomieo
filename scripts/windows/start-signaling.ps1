$run = & (Join-Path $PSScriptRoot "deploy-run-dir.ps1")
Set-Location $run

$args = @(
    "--bind", "0.0.0.0:8443",
    "--web-root", (Join-Path $run "web\dist")
)
$cert = Join-Path $run "certs\cert.pem"
$key = Join-Path $run "certs\key.pem"
if ((Test-Path $cert) -and (Test-Path $key)) {
    $args += @("--cert", $cert, "--key", $key)
}

Write-Host "Rohomieo signaling on https://0.0.0.0:8443" -ForegroundColor Cyan
& (Join-Path $run "rohomieo-signaling.exe") @args
