# Start signaling + host on Windows (two windows)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Start-Process powershell -ArgumentList "-NoExit", "-File", "$root\scripts\windows\start-signaling.ps1"
Start-Sleep -Seconds 2
Start-Process powershell -ArgumentList "-NoExit", "-File", "$root\scripts\windows\start-host.ps1"
Write-Host "Open http://127.0.0.1:8443 - use Session ID + PIN from the host window"
