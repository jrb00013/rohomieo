$run = & (Join-Path $PSScriptRoot "deploy-run-dir.ps1")
Set-Location $run

Write-Host "Rohomieo host — Session + PIN below" -ForegroundColor Cyan
& (Join-Path $run "rohomieo-host.exe") --signaling ws://127.0.0.1:8443/ws
