$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
Set-Location $root

$hostExe = Join-Path $root "target\release\rohomieo-host.exe"
if (-not (Test-Path $hostExe)) {
    Write-Host "==> Building rohomieo-host.exe (WSL MinGW, no Visual Studio)..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "build-host.ps1") $root
}

& $hostExe --signaling ws://127.0.0.1:8443/ws
