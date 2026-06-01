$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
Set-Location $root
& "$root\target\release\rohomieo-host.exe" --signaling ws://127.0.0.1:8443/ws
