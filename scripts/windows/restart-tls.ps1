$ErrorActionPreference = "Stop"
$run = Join-Path $env:LOCALAPPDATA "rohomieo-run"
Set-Location -LiteralPath $run

Get-Process rohomieo-signaling, rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$sig = Join-Path $run "rohomieo-signaling.exe"
$hostExe = Join-Path $run "rohomieo-host.exe"
$web = Join-Path $run "web\dist"
$cert = Join-Path $run "certs\cert.pem"
$key = Join-Path $run "certs\key.pem"

foreach ($p in @($sig, $hostExe, $web, $cert, $key)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing $p" }
}

$staged = Join-Path $run "staging\rohomieo-host.exe"
if (Test-Path -LiteralPath $staged) {
  Copy-Item -Force $staged $hostExe -ErrorAction SilentlyContinue
}

Write-Host "Starting signaling with TLS..."
Start-Process -FilePath $sig -WorkingDirectory $run -ArgumentList @(
  "--bind", "0.0.0.0:8443",
  "--web-root", $web,
  "--cert", $cert,
  "--key", $key
) -WindowStyle Minimized

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Milliseconds 500
  $code = & curl.exe -sk -o NUL -w "%{http_code}" "https://127.0.0.1:8443/health" 2>$null
  if ($code -eq "200") { $ready = $true; break }
}
if (-not $ready) { throw "HTTPS signaling did not come up" }
Write-Host "OK HTTPS signaling"

$sid = "live-" + [guid]::NewGuid().ToString()
$pin = "424242"
($sid + "|" + $pin) | Set-Content -Path (Join-Path $run "e2e-session.txt") -NoNewline

$bat = Join-Path $run "start-host-visible.bat"
$batLines = @(
  "@echo off",
  "title Rohomieo Host - SCAN THIS QR",
  "cd /d `"$run`"",
  "`"$hostExe`" --signaling wss://127.0.0.1:8443/ws --session $sid --pin $pin",
  "echo Host exited %ERRORLEVEL%",
  "pause"
)
Set-Content -Path $bat -Value $batLines -Encoding ASCII

Start-Process -FilePath $bat -WorkingDirectory $run -WindowStyle Normal
Start-Sleep -Seconds 3

$lan = (Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
  Select-Object -First 1).IPAddress
if (-not $lan) { $lan = "192.168.1.223" }

Write-Host ""
Write-Host ("PHONE=https://{0}:8443/?s={1}&p={2}&auto=1" -f $lan, $sid, $pin)
& curl.exe -sk "https://127.0.0.1:8443/api/status"
Write-Host ""
Get-Process rohomieo* | Format-Table Id, ProcessName -AutoSize
