#Requires -RunAsAdministrator
# Elevated one-shot used by ./install.sh (automatic - no --allow flag).
# kill -> promote staging -> firewall/defender/sign -> SAC off -> start :8443
param(
    [string]$RunDir = "",
    [switch]$SkipStart,
    [switch]$NoReboot
)

$ErrorActionPreference = "Continue"
$RunDir = if ($RunDir) { $RunDir } else { Join-Path $env:LOCALAPPDATA "rohomieo-run" }
$LogFile = Join-Path $RunDir "install-allow.log"

function Log([string]$m, [string]$color = "White") {
    $line = $m
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
}
function Step($m) { Log "==> $m" "Cyan" }
function Ok($m)   { Log "OK  $m" "Green" }
function Warn($m) { Log "!   $m" "Yellow" }

function Register-RohomieoAllowAtLogon {
    param([string]$ScriptPath)
    $taskName = "RohomieoInstallAllowAtLogon"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -RunDir `"$RunDir`" -NoReboot"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Ok "scheduled $taskName (runs at next login)"
}

# Permanent on-demand elevated task — after first UAC, later installs use
# `schtasks /Run /TN RohomieoElevatedAllow` with no prompt.
function Register-RohomieoElevatedAllow {
    $taskName = "RohomieoElevatedAllow"
    $wrap = Join-Path $RunDir "install-allow-wrap.ps1"
    $script = if (Test-Path $wrap) { $wrap } else { Join-Path $RunDir "install-allow.ps1" }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$script`""
    # Far-future one-shot trigger; we only ever Start via schtasks /Run
    $trigger = New-ScheduledTaskTrigger -Once -At ([datetime]"2000-01-01T00:00:00")
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    # Disable the dummy trigger so it never auto-fires
    try {
        $t = Get-ScheduledTask -TaskName $taskName
        $t.Triggers | ForEach-Object { $_.Enabled = $false }
        Set-ScheduledTask -InputObject $t | Out-Null
    } catch { }
    Ok "registered $taskName (future installs: no UAC)"
}

Set-Content -Path $LogFile -Value ("Rohomieo allow " + (Get-Date -Format o)) -Encoding utf8
Step "Rohomieo Windows allow + start ($RunDir)"

# 0) Persist elevation: one UAC forever after this (schtasks /Run)
try { Register-RohomieoElevatedAllow } catch { Warn ("elevated task: " + $_.Exception.Message) }

# 1) Kill (admin can stop elevated processes)
Step "Stop existing rohomieo processes"
Get-Process rohomieo-signaling, rohomieo-host -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
cmd /c "taskkill /F /IM rohomieo-signaling.exe /T >nul 2>&1 & taskkill /F /IM rohomieo-host.exe /T >nul 2>&1"
Start-Sleep -Seconds 2

# 2) Promote staging from WSL
$stage = Join-Path $RunDir "staging"
if (Test-Path (Join-Path $stage "rohomieo-signaling.exe")) {
    Step "Promote staging -> run dir"
    foreach ($name in @(
        "rohomieo-signaling.exe", "rohomieo-host.exe",
        "libunwind.dll", "libc++.dll", "libwinpthread-1.dll"
    )) {
        $src = Join-Path $stage $name
        if (Test-Path $src) { Copy-Item -Force $src (Join-Path $RunDir $name) }
    }
    if (Test-Path (Join-Path $stage "web\dist")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $RunDir "web\dist") | Out-Null
        Copy-Item -Force -Recurse (Join-Path $stage "web\dist\*") (Join-Path $RunDir "web\dist")
    }
    if (Test-Path (Join-Path $stage "certs")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $RunDir "certs") | Out-Null
        Copy-Item -Force (Join-Path $stage "certs\*") (Join-Path $RunDir "certs")
    }
    Ok "staging promoted"
}

if (-not (Test-Path (Join-Path $RunDir "rohomieo-signaling.exe"))) {
    Log "ERROR missing rohomieo-signaling.exe - run ./install.sh from WSL first" "Red"
    exit 1
}

# 3) Smart App Control FIRST (host will not start while Enforce=1)
Step "Smart App Control policy"
$ciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
$sacReboot = $false
$sacValue = -1
try {
    if (-not (Test-Path $ciPath)) { New-Item -Path $ciPath -Force | Out-Null }
    $sacValue = [int](Get-ItemProperty -Path $ciPath -Name "VerifiedAndReputablePolicyState" -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    Log "    current VerifiedAndReputablePolicyState=$sacValue"
    if ($sacValue -ne 0) {
        cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy`" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 0 /f" | Out-Null
        $sacValue = [int](Get-ItemProperty -Path $ciPath -Name "VerifiedAndReputablePolicyState").VerifiedAndReputablePolicyState
        if ($sacValue -eq 0) {
            Ok "set Smart App Control -> Off (0)"
            $sacReboot = $true
        } else {
            cmd /c "reg add `"HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy`" /v VerifiedAndReputablePolicyState /t REG_DWORD /d 2 /f" | Out-Null
            Ok "set Smart App Control -> Evaluation (2)"
            $sacReboot = $true
        }
    } else {
        Ok "SAC already Off"
    }
} catch {
    Warn ("SAC registry: " + $_.Exception.Message)
}

# 4) Firewall
Step "Firewall TCP 8443"
netsh interface portproxy delete v4tov4 listenport=8443 listenaddress=0.0.0.0 2>$null | Out-Null
if (-not (Get-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "Rohomieo-Signaling-TCP" -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort 8443 -Profile Any | Out-Null
    Ok "firewall rule added"
} else {
    Ok "firewall rule already exists"
}

# 5) Defender exclusions
Step "Windows Defender exclusions"
foreach ($p in @($RunDir)) {
    try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; Ok "exclude path $p" }
    catch { Warn ("exclude path: " + $_.Exception.Message) }
}
foreach ($exe in @("rohomieo-host.exe", "rohomieo-signaling.exe")) {
    try { Add-MpPreference -ExclusionProcess $exe -ErrorAction Stop; Ok "exclude process $exe" }
    catch { Warn "exclude process $exe failed" }
}

# 6) Unblock
Step "Unblock binaries"
Get-ChildItem -Path $RunDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in ".exe", ".dll" } |
    ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($_.FullName + ":Zone.Identifier") -Force -ErrorAction SilentlyContinue
    }
Ok "unblocked"

# 7) Local code sign
Step "Code-sign with local cert"
$certSubject = "CN=Rohomieo Local Dev"
$cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $certSubject -and $_.HasPrivateKey } | Select-Object -First 1
if (-not $cert) {
    try {
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $certSubject `
            -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 `
            -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(5) `
            -CertStoreLocation "Cert:\LocalMachine\My"
        Ok "created $certSubject"
    } catch {
        Warn ("cert create failed: " + $_.Exception.Message)
    }
} else {
    Ok "reusing $certSubject"
}
if ($cert) {
    foreach ($storeName in @("Root", "TrustedPublisher")) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, "LocalMachine")
            $store.Open("ReadWrite")
            if (-not ($store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
                $store.Add($cert)
                Ok "imported into LocalMachine\$storeName"
            }
            $store.Close()
        } catch {
            Warn ("store $storeName : " + $_.Exception.Message)
        }
    }
    foreach ($bin in @("rohomieo-signaling.exe", "rohomieo-host.exe")) {
        $path = Join-Path $RunDir $bin
        if (-not (Test-Path $path)) { continue }
        try {
            $sig = Set-AuthenticodeSignature -FilePath $path -Certificate $cert -ErrorAction Stop
            Ok ("signed $bin status=$($sig.Status)")
        } catch {
            Warn ("sign $bin : " + $_.Exception.Message)
        }
    }
}

if ($SkipStart) {
    Ok "SkipStart - allow steps done"
    exit 0
}

# If SAC was Enforce and we flipped it, reboot is required before host can start
if ($sacReboot -and -not $NoReboot) {
    Register-RohomieoAllowAtLogon -ScriptPath $PSCommandPath
    Step "Reboot required for Smart App Control Off - rebooting in 12s"
    Log "After login, Rohomieo will auto-finish and start the host." "Yellow"
    Write-Host "Reboot recommended (not auto): shutdown /r /t 0" # was: Warn "Reboot recommended for SAC — run: shutdown /r /t 0  (not auto)"
    exit 2
}

# 8) Start stack
Step "Starting signaling"
$sig = Start-Process -FilePath (Join-Path $RunDir "rohomieo-signaling.exe") `
    -WorkingDirectory $RunDir -ArgumentList @(
        "--bind", "0.0.0.0:8443",
        "--web-root", (Join-Path $RunDir "web\dist"),
        "--cert", (Join-Path $RunDir "certs\cert.pem"),
        "--key", (Join-Path $RunDir "certs\key.pem")
    ) -PassThru -WindowStyle Minimized

$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if ($sig.HasExited) {
        Log ("ERROR signaling exited code=" + $sig.ExitCode) "Red"
        exit 1
    }
    if (Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue) {
        $ready = $true
        break
    }
}
if (-not $ready) { Log "ERROR signaling did not open :8443" "Red"; exit 1 }
Ok "signaling on :8443"

Step "Starting host"
$hostStarted = $false
try {
    $hostProc = Start-Process -FilePath (Join-Path $RunDir "rohomieo-host.exe") `
        -WorkingDirectory $RunDir `
        -ArgumentList @("--signaling", "wss://127.0.0.1:8443/ws") `
        -PassThru -WindowStyle Normal
    Start-Sleep -Seconds 2
    if ($hostProc -and -not $hostProc.HasExited) {
        $hostStarted = $true
        Ok ("host pid=" + $hostProc.Id + " - Session ID + PIN in that window")
    }
} catch {
    Warn ("host blocked: " + $_.Exception.Message)
}

if (-not $hostStarted) {
    Warn "host still blocked by Smart App Control"
    Register-RohomieoAllowAtLogon -ScriptPath $PSCommandPath
    if (-not $NoReboot) {
        Step "Rebooting in 12s so SAC policy applies"
        Write-Host "Reboot recommended (not auto): shutdown /r /t 0" # was: Warn "Reboot recommended for SAC — run: shutdown /r /t 0  (not auto)"
    }
    $lan = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
        Select-Object -First 1).IPAddress
    Log "Laptop https://127.0.0.1:8443"
    if ($lan) { Log "Phone  https://${lan}:8443" "Yellow" }
    exit 2
}

Unregister-ScheduledTask -TaskName "RohomieoInstallAllowAtLogon" -Confirm:$false -ErrorAction SilentlyContinue
$lan = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.InterfaceAlias -notmatch 'WSL|vEthernet' } |
    Select-Object -First 1).IPAddress
Ok "Rohomieo fully running"
Log "Laptop https://127.0.0.1:8443"
if ($lan) { Log "Phone  https://${lan}:8443" "Yellow" }
Log "Session/PIN: host window"
exit 0
