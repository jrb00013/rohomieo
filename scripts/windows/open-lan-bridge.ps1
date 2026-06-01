# Run this script as Administrator (right-click PowerShell -> Run as administrator).
# Or from the repo folder:  powershell -ExecutionPolicy Bypass -File scripts\windows\open-lan-bridge.ps1

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $RepoRoot "setup.sh"))) {
    $RepoRoot = "\\wsl.localhost\Ubuntu\home\josep\rohomieo"
}

Set-Location $RepoRoot
Write-Host "Repo: $RepoRoot" -ForegroundColor Cyan

& (Join-Path $RepoRoot "scripts\windows\wsl-bridge-portproxy.ps1")

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " On your phone (same Wi-Fi), open:" -ForegroundColor Green
Write-Host "   https://${lan}:8443" -ForegroundColor Yellow
Write-Host " Accept the certificate warning." -ForegroundColor Green
Write-Host " Session + PIN: Windows host PowerShell window" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
