# Build rohomieo-host.exe via WSL (llvm-mingw cross-compile — no Visual Studio).
$ErrorActionPreference = "Stop"
$root = if ($args[0]) { $args[0] } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
$wslRoot = (wsl wslpath -u "`"$root`"").Trim()
wsl -e bash -lc "cd '$wslRoot' && ./scripts/build-windows-host.sh"
