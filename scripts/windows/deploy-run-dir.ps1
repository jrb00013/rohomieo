# Copy exes + DLLs + web + certs to %LOCALAPPDATA%\rohomieo-run (native path, no missing DLLs).
param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$run = Join-Path $env:LOCALAPPDATA "rohomieo-run"
New-Item -ItemType Directory -Force -Path $run, (Join-Path $run "web\dist"), (Join-Path $run "certs") | Out-Null

$files = @(
    "rohomieo-signaling.exe",
    "rohomieo-host.exe",
    "libunwind.dll",
    "libc++.dll",
    "libwinpthread-1.dll"
)
foreach ($f in $files) {
    $src = Join-Path $RepoRoot "target\release\$f"
    if (Test-Path $src) {
        Copy-Item -Force $src $run
    }
}

$webSrc = Join-Path $RepoRoot "web\dist"
$webDst = Join-Path $run "web\dist"
if (Test-Path $webSrc) {
  # robocopy from \\wsl can hang; use Copy-Item for typical PWA size
  if (Test-Path $webDst) { Remove-Item -Recurse -Force $webDst }
  Copy-Item -Recurse -Force $webSrc $webDst
}
$certDir = Join-Path $RepoRoot "infra\certs"
Copy-Item -Force (Join-Path $certDir "cert.pem") (Join-Path $run "certs\") -ErrorAction SilentlyContinue
Copy-Item -Force (Join-Path $certDir "key.pem") (Join-Path $run "certs\") -ErrorAction SilentlyContinue

Write-Output $run
