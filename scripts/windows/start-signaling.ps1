$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
Set-Location $root
& "$root\target\release\rohomieo-signaling.exe" --bind 0.0.0.0:8443 --web-root "$root\web\dist"
