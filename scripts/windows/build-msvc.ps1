# Build rohomieo-host.exe with MSVC. Syncs off \\wsl paths to %LOCALAPPDATA%\rohomieo-build first.
param(
    [string]$RepoRoot = "",
    [switch]$HostOnly,
    [switch]$SignalingOnly
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Join-Path $PSScriptRoot "..\..")
}
$RepoRoot = $RepoRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::', ''
if ($RepoRoot -match 'wsl\.localhost|wsl\$') {
    $OrigRepoRoot = $RepoRoot
} else {
    $OrigRepoRoot = (Resolve-Path $RepoRoot).Path
}

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path

function Get-NativeBuildRoot([string]$Root) {
    if ($Root -notmatch 'wsl\.localhost|wsl\$') {
        return $Root
    }
    $local = Join-Path $env:LOCALAPPDATA "rohomieo-build"
    $wslPath = (wsl -e wslpath -u "$Root").Trim()
    if (-not $wslPath.StartsWith("/")) {
        throw "wslpath failed for: $Root"
    }
    $drive = $local.Substring(0, 1).ToLower()
    $rest = $local.Substring(2).TrimStart('\').Replace('\', '/')
    $mnt = "/mnt/$drive/$rest"
    Write-Host "==> Syncing repo to $local" -ForegroundColor Cyan
    wsl -e bash -lc "mkdir -p '$mnt' && rsync -a --delete '$wslPath/' '$mnt/' --exclude target --exclude node_modules --exclude web/node_modules --exclude var"
    return $local
}

function Import-MsvcEnv {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $installPath = $null
    if (Test-Path $vswhere) {
        $installPath = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
    }
    if (-not $installPath) {
        foreach ($c in @(
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools"
        )) {
            if (Test-Path (Join-Path $c "VC\Auxiliary\Build\vcvars64.bat")) {
                $installPath = $c
                break
            }
        }
    }
    if (-not $installPath) { return $false }
    $vcvars = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
    Write-Host "==> MSVC: $vcvars" -ForegroundColor Cyan
    $envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2] -Force
        }
    }
    $env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
    return $true
}

function Install-BuildTools {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
    Write-Host "==> Installing VS 2022 Build Tools (passive)..." -ForegroundColor Cyan
    & winget install Microsoft.VisualStudio.2022.BuildTools `
        --disable-interactivity --accept-package-agreements --accept-source-agreements `
        --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    return ($LASTEXITCODE -eq 0)
}

$RepoRoot = Get-NativeBuildRoot $OrigRepoRoot
$env:CARGO_TARGET_DIR = Join-Path $RepoRoot "target"
New-Item -ItemType Directory -Force -Path $env:CARGO_TARGET_DIR | Out-Null

if (-not (Import-MsvcEnv)) {
    if (-not (Install-BuildTools)) {
        Write-Error "MSVC not found. Install VS Build Tools with C++ workload."
    }
    if (-not (Import-MsvcEnv)) { Write-Error "MSVC still unavailable." }
}

Push-Location $RepoRoot
try {
    if (-not $HostOnly) {
        Write-Host "==> cargo build -p rohomieo-signaling --release" -ForegroundColor Cyan
        cargo build --release -p rohomieo-signaling
    }
    if (-not $SignalingOnly) {
        Write-Host "==> cargo build -p rohomieo-host --release" -ForegroundColor Cyan
        cargo build --release -p rohomieo-host
    }
} finally {
    Pop-Location
}

$hostExe = Join-Path $env:CARGO_TARGET_DIR "release\rohomieo-host.exe"
if (-not (Test-Path $hostExe)) { Write-Error "rohomieo-host.exe missing after build" }

if ($OrigRepoRoot -match 'wsl\.localhost|wsl\$') {
    $wslRepo = (wsl -e wslpath -u "$OrigRepoRoot").Trim()
    $drive = $env:LOCALAPPDATA.Substring(0, 1).ToLower()
    $rel = $env:LOCALAPPDATA.Substring(2).TrimStart('\').Replace('\', '/')
    $fromMnt = "/mnt/$drive/$rel/rohomieo-build/target/release/rohomieo-host.exe"
    $wslDest = "$wslRepo/target/release/rohomieo-host.exe"
    wsl -e bash -lc "mkdir -p '$wslRepo/target/release' && cp -f '$fromMnt' '$wslDest' && ls -la '$wslDest'"
    Write-Host "OK  $wslDest" -ForegroundColor Green
} else {
    Write-Host "OK  $hostExe" -ForegroundColor Green
}
