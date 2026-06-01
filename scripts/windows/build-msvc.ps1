# Build rohomieo-host.exe (and signaling) with MSVC env auto-loaded.
# Called from WSL via setup.sh / setup-windows.ps1.
param(
    [string]$RepoRoot = "",
    [switch]$HostOnly,
    [switch]$SignalingOnly
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
Set-Location $RepoRoot

$env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path

function Import-MsvcEnv {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $installPath = $null
    if (Test-Path $vswhere) {
        $installPath = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath 2>$null
    }
    if (-not $installPath) {
        $candidates = @(
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community",
            "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional",
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools"
        )
        foreach ($c in $candidates) {
            if (Test-Path (Join-Path $c "VC\Auxiliary\Build\vcvars64.bat")) {
                $installPath = $c
                break
            }
        }
    }
    if (-not $installPath) {
        return $false
    }
    $vcvars = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        return $false
    }
    Write-Host "==> MSVC environment: $vcvars" -ForegroundColor Cyan
    $envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            Set-Item -Path "env:$name" -Value $value -Force
        }
    }
    $env:Path = "$env:USERPROFILE\.cargo\bin;" + $env:Path
    return $true
}

function Install-BuildTools {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return $false
    }
    Write-Host "==> Installing VS 2022 Build Tools (C++ workload, passive)..." -ForegroundColor Cyan
    Write-Host "    First run can take 10-20 minutes." -ForegroundColor Yellow
    & winget install Microsoft.VisualStudio.2022.BuildTools `
        --disable-interactivity `
        --accept-package-agreements `
        --accept-source-agreements `
        --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    return ($LASTEXITCODE -eq 0)
}

if (-not (Import-MsvcEnv)) {
    if (-not (Install-BuildTools)) {
        Write-Error "MSVC not found. Install 'Desktop development with C++' from Visual Studio Build Tools, then re-run."
    }
    if (-not (Import-MsvcEnv)) {
        Write-Error "MSVC still not available after Build Tools install."
    }
}

if (-not $HostOnly) {
    Write-Host "==> cargo build -p rohomieo-signaling --release" -ForegroundColor Cyan
    cargo build --release -p rohomieo-signaling
}
if (-not $SignalingOnly) {
    Write-Host "==> cargo build -p rohomieo-host --release" -ForegroundColor Cyan
    cargo build --release -p rohomieo-host
}

$hostExe = Join-Path $RepoRoot "target\release\rohomieo-host.exe"
if (Test-Path $hostExe) {
    Write-Host "OK  $hostExe" -ForegroundColor Green
} else {
    Write-Error "Build finished but rohomieo-host.exe missing"
}
