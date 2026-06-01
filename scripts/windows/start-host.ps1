$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
Set-Location $root

$hostExe = Join-Path $root "target\release\rohomieo-host.exe"
if (-not (Test-Path $hostExe)) {
    Write-Host "==> rohomieo-host.exe missing — building with MSVC..." -ForegroundColor Cyan
    $build = Join-Path $PSScriptRoot "build-msvc.ps1"
    & $build -RepoRoot $root -HostOnly
}

# Signaling runs in WSL; host connects to localhost forwarded port
& $hostExe --signaling ws://127.0.0.1:8443/ws
