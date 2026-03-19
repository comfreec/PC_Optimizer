# Security Hardening Script

$LogFile = "$PSScriptRoot\log_security_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Log {
    param([string]$msg, [string]$color = "Cyan")
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}
function Section {
    param([string]$title)
    Write-Host "" ; Write-Host ("=" * 55) -ForegroundColor Yellow
    Write-Host "  $title" -ForegroundColor Yellow
    Write-Host ("=" * 55) -ForegroundColor Yellow ; Write-Host ""
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host "   Security Hardening" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Log "Start - PC: $env:COMPUTERNAME" "Green"

# Step 1: Windows Defender 강화
Section "1/6  Windows Defender"
Log "Enabling Defender and real-time protection..." "Cyan"
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
    Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
    Set-MpPreference -DisableBlockAtFirstSeen $false -ErrorAction SilentlyContinue
    Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
    Set-MpPreference -DisableScriptScanning $false -ErrorAction SilentlyContinue
    Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue
    Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    Log "  Defender: all protections ON" "Green"
} catch {
    Log "  Defender config error: $($_.Exception.Message)" "Red"
}

# Ransomware protection (Controlled Folder Access)
try {
    Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction Stop
    Log "  Ransomware protection (Controlled Folder Access): ON" "Green"
} catch {
    Log "  Controlled Folder Access not available on this edition" "DarkGray"
}

# Update Defender definitions
Log "  Updating Defender definitions..." "Cyan"
try {
    Update-MpSignature -ErrorAction Stop
    Log "  Defender definitions updated" "Green"
} catch {
    Log "  Definition update failed (check internet)" "Yellow"
}
Log "Defender done" "Green"

# Step 2: Firewall
Section "2/6  Firewall"
Log "Enabling firewall on all profiles..." "Cyan"
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
    Log "  Firewall: ON (Domain, Public, Private)" "Green"
} catch {
    Log "  Firewall config error: $($_.Exception.Message)" "Red"
}

# Block common attack ports (inbound)
$blockPorts = @(
    @{ Port=23;   Proto="TCP"; Desc="Telnet" },
    @{ Port=135;  Proto="TCP"; Desc="RPC" },
    @{ Port=137;  Proto="UDP"; Desc="NetBIOS" },
    @{ Port=138;  Proto="UDP"; Desc="NetBIOS" },
    @{ Port=139;  Proto="TCP"; Desc="NetBIOS" },
    @{ Port=445;  Proto="TCP"; Desc="SMB" },
    @{ Port=3389; Proto="TCP"; Desc="RDP" }
)
foreach ($p in $blockPorts) {
    $ruleName = "Block_Inbound_$($p.Desc)_$($p.Port)"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $existing) {
        try {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol $p.Proto `
                -LocalPort $p.Port -Action Block -ErrorAction Stop | Out-Null
            Log "  Blocked inbound port $($p.Port) ($($p.Desc))" "Gray"
        } catch {
            Log "  Port $($p.Port) block skip: $($_.Exception.Message)" "DarkGray"
        }
    } else {
        Log "  Port $($p.Port) ($($p.Desc)) already blocked" "DarkGray"
    }
}
Log "Firewall done" "Green"

# Step 3: UAC
Section "3/6  UAC (User Account Control)"
Log "Setting UAC to recommended level..." "Cyan"
try {
    $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $uacKey -Name "EnableLUA" -Value 1 -Type DWORD
    Set-ItemProperty -Path $uacKey -Name "ConsentPromptBehaviorAdmin" -Value 2 -Type DWORD
    Set-ItemProperty -Path $uacKey -Name "ConsentPromptBehaviorUser" -Value 3 -Type DWORD
    Set-ItemProperty -Path $uacKey -Name "PromptOnSecureDesktop" -Value 1 -Type DWORD
    Log "  UAC: enabled at recommended level" "Green"
} catch {
    Log "  UAC config error: $($_.Exception.Message)" "Red"
}

# Step 4: Disable Remote Desktop (if not needed)
Section "4/6  Remote Desktop"
Log "Checking Remote Desktop status..." "Cyan"
try {
    $rdpKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"
    $rdpVal = (Get-ItemProperty -Path $rdpKey -Name "fDenyTSConnections" -ErrorAction Stop).fDenyTSConnections
    if ($rdpVal -eq 0) {
        $ans = Read-Host "  Remote Desktop is ON. Disable it? (Y/N)"
        if ($ans -eq "Y" -or $ans -eq "y") {
            Set-ItemProperty -Path $rdpKey -Name "fDenyTSConnections" -Value 1 -Type DWORD
            Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "TermService" -StartupType Disabled -ErrorAction SilentlyContinue
            Log "  Remote Desktop: disabled" "Green"
        } else {
            Log "  Remote Desktop: kept ON (user choice)" "Yellow"
        }
    } else {
        Log "  Remote Desktop: already OFF" "Green"
    }
} catch {
    Log "  RDP check error: $($_.Exception.Message)" "DarkGray"
}

# Step 5: Disable AutoRun / AutoPlay
Section "5/6  AutoRun and AutoPlay"
Log "Disabling AutoRun/AutoPlay (USB attack prevention)..." "Cyan"
try {
    $autorunKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    if (-not (Test-Path $autorunKey)) { New-Item -Path $autorunKey -Force | Out-Null }
    Set-ItemProperty -Path $autorunKey -Name "NoDriveTypeAutoRun" -Value 255 -Type DWORD
    Set-ItemProperty -Path $autorunKey -Name "NoAutorun" -Value 1 -Type DWORD

    $autoplayKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"
    Set-ItemProperty -Path $autoplayKey -Name "DisableAutoplay" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
    Log "  AutoRun: disabled" "Green"
    Log "  AutoPlay: disabled" "Green"
} catch {
    Log "  AutoRun config error: $($_.Exception.Message)" "Red"
}

# Step 6: Security registry tweaks
Section "6/6  Security Registry Tweaks"
Log "Applying security registry settings..." "Cyan"

# Disable SMBv1 (WannaCry vector)
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -Name "SMB1" -Value 0 -Type DWORD -ErrorAction Stop
    Log "  SMBv1: disabled (ransomware prevention)" "Green"
} catch { Log "  SMBv1 disable skip" "DarkGray" }

# Disable LLMNR (credential theft prevention)
try {
    $llmnrKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
    if (-not (Test-Path $llmnrKey)) { New-Item -Path $llmnrKey -Force | Out-Null }
    Set-ItemProperty -Path $llmnrKey -Name "EnableMulticast" -Value 0 -Type DWORD
    Log "  LLMNR: disabled" "Green"
} catch { Log "  LLMNR disable skip" "DarkGray" }

# Disable Windows Script Host (prevents malicious .vbs/.js)
try {
    $wshKey = "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings"
    if (-not (Test-Path $wshKey)) { New-Item -Path $wshKey -Force | Out-Null }
    Set-ItemProperty -Path $wshKey -Name "Enabled" -Value 0 -Type DWORD
    Log "  Windows Script Host: disabled (blocks malicious scripts)" "Green"
} catch { Log "  WSH disable skip" "DarkGray" }

# Show file extensions (helps spot fake files like photo.jpg.exe)
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "HideFileExt" -Value 0 -Type DWORD -ErrorAction SilentlyContinue
Log "  File extensions: visible" "Green"

# Show hidden files
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "Hidden" -Value 1 -Type DWORD -ErrorAction SilentlyContinue
Log "  Hidden files: visible" "Green"

Log "Security tweaks done" "Green"

# Summary
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Security hardening complete" -ForegroundColor Green
Write-Host "  Reboot recommended to apply all changes." -ForegroundColor Yellow
Write-Host ("=" * 55) -ForegroundColor Green
Log "Done. Log: $LogFile" "Green"

$ans = Read-Host "Reboot now? (Y/N)"
if ($ans -eq "Y" -or $ans -eq "y") {
    Restart-Computer -Force
} else {
    Read-Host "Press Enter to close"
}
