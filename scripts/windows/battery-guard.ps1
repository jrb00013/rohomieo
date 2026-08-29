param(
    [int]$Limit = 80,
    [switch]$Status,
    [switch]$Detect
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$srcExe = Join-Path $repoRoot "target\release\rohomieo-battery-guard.exe"

if (-not (Test-Path $srcExe)) {
    Write-Host "Building rohomieo-battery-guard (release)..."
    Push-Location $repoRoot
    try {
        cargo build --release -p rohomieo-battery-guard
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $srcExe)) {
    Write-Error "rohomieo-battery-guard.exe not found after build at $srcExe"
    exit 1
}

# Stage the exe (+ mingw runtime DLLs) onto local NTFS. When this repo is
# built from WSL, target/release can live under a \\wsl.localhost\ share,
# which an elevated process (separate logon session) generally cannot see
# at all — staging locally keeps both the normal and elevated run paths
# working the same way, and matches sync-windows-run.sh's convention.
$runDir = Join-Path $env:LOCALAPPDATA "rohomieo-run"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$exe = Join-Path $runDir "rohomieo-battery-guard.exe"
Copy-Item -Force $srcExe $exe
foreach ($dll in @("libunwind.dll", "libc++.dll", "libwinpthread-1.dll")) {
    $srcDll = Join-Path $repoRoot "target\release\$dll"
    if (Test-Path $srcDll) { Copy-Item -Force $srcDll $runDir }
}

$cliArgs = @()
if ($Detect) { $cliArgs += "--detect" }
elseif ($Status) { $cliArgs += "--status" }
else { $cliArgs += "--limit"; $cliArgs += $Limit }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    & $exe @cliArgs
    exit $LASTEXITCODE
}

# ASUS's ATK WMI ExecMethod calls (and vendor equivalents) fail with
# "Invalid method Parameter(s)" when the caller isn't elevated — WMI
# accepts the call but the underlying ACPI/EC method rejects it from a
# non-admin token. Self-elevate once rather than making every caller
# (run.sh, a user double-click) remember to launch this as admin.
#
# -Verb RunAs is incompatible with Start-Process's own
# -RedirectStandardOutput/-Error (PowerShell rejects the parameter set),
# and an elevated process gets its own console anyway — so have it
# redirect its own output to a log file via `*>` and read that back here
# once it exits.
$log = Join-Path $runDir "battery-guard.log"
Remove-Item -ErrorAction SilentlyContinue $log
$cliArgsStr = $cliArgs -join ' '
# A RunAs-elevated process does not inherit this session's environment,
# so forward RUST_LOG explicitly rather than relying on inheritance.
$rustLogPrefix = if ($env:RUST_LOG) { "`$env:RUST_LOG = '$($env:RUST_LOG)'; " } else { "" }
$innerCommand = "$rustLogPrefix& '$exe' $cliArgsStr *> '$log'; exit `$LASTEXITCODE"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($innerCommand))

$proc = Start-Process powershell.exe -Verb RunAs `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
    -Wait -PassThru
Get-Content -ErrorAction SilentlyContinue $log | Write-Host
exit $proc.ExitCode
