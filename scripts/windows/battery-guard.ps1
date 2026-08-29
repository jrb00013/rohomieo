param(
    [int]$Limit = 80,
    [switch]$Status,
    [switch]$Detect
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe = Join-Path $repoRoot "target\release\rohomieo-battery-guard.exe"

if (-not (Test-Path $exe)) {
    Write-Host "Building rohomieo-battery-guard (release)..."
    Push-Location $repoRoot
    try {
        cargo build --release -p rohomieo-battery-guard
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $exe)) {
    Write-Error "rohomieo-battery-guard.exe not found after build at $exe"
    exit 1
}

$cliArgs = @()
if ($Detect) { $cliArgs += "--detect" }
elseif ($Status) { $cliArgs += "--status" }
else { $cliArgs += "--limit"; $cliArgs += $Limit }

& $exe @cliArgs
exit $LASTEXITCODE
