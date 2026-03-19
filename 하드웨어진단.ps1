# Hardware Diagnostic - Pre-Reinstall Check

$LogFile = "$PSScriptRoot\log_hardware_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$problems = [System.Collections.Generic.List[string]]::new()
$warnings  = [System.Collections.Generic.List[string]]::new()

function Log {
    param([string]$msg, [string]$color = "White")
    Write-Host $msg -ForegroundColor $color
    Add-Content -Path $LogFile -Value $msg -Encoding UTF8
}
function Section {
    param([string]$title)
    $bar = "=" * 55
    Log "" ; Log $bar "Yellow" ; Log "  $title" "Yellow" ; Log $bar "Yellow" ; Log ""
}
function Bad  { param([string]$msg) $script:problems.Add($msg); Log "  !! $msg" "Red" }
function Warn { param([string]$msg) $script:warnings.Add($msg); Log "  >> $msg" "Yellow" }
function OK   { param([string]$msg) Log "  OK  $msg" "Green" }
function Info { param([string]$msg) Log "  --  $msg" "Gray" }

function Popup {
    param([string]$title, [string]$msg)
    $wsh = New-Object -ComObject WScript.Shell
    $wsh.Popup($msg, 0, $title, 0x30) | Out-Null
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Log ("=" * 55) "Cyan"
Log "   Hardware Diagnostic" "Cyan"
Log "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" "Cyan"
Log "   PC: $env:COMPUTERNAME" "Cyan"
Log ("=" * 55) "Cyan"
Log "" "White"
Log "  Checking hardware before Windows reinstall..." "Gray"
Log "  This takes about 2~3 minutes." "Gray"

# ─── 1. Disk S.M.A.R.T ──────────────────────────────────────
Section "1/5  Disk Health (S.M.A.R.T)"
Log "  Checking disk health..." "Cyan"
try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop
    foreach ($pd in $physDisks) {
        $sizeGB = [math]::Round($pd.Size / 1GB, 0)
        $health = $pd.HealthStatus
        $media  = $pd.MediaType
        $col    = if ($health -eq "Healthy") {"Green"} elseif ($health -eq "Warning") {"Yellow"} else {"Red"}
        Log "  $($pd.FriendlyName)  |  $media  |  $sizeGB GB  |  $health" $col
        if ($health -eq "Unhealthy") {
            Bad "Disk FAILURE: $($pd.FriendlyName) - replace immediately"
        } elseif ($health -eq "Warning") {
            Warn "Disk WARNING: $($pd.FriendlyName) - may fail soon"
        } else {
            OK "Disk OK: $($pd.FriendlyName)"
        }
    }
} catch {
    # Fallback SMART via WMI
    try {
        $smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($s in $smart) {
            if ($s.PredictFailure) {
                Bad "SMART failure predicted - disk may fail, replace before reinstall"
            } else {
                OK "SMART: No failure predicted"
            }
        }
    } catch {
        Warn "SMART data not accessible - manual disk check recommended"
    }
}

# Disk free space check
$sysDisk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
if ($sysDisk) {
    $freeGB  = [math]::Round($sysDisk.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($sysDisk.Size / 1GB, 1)
    Info "C: drive  $freeGB GB free / $totalGB GB total"
    if ($freeGB -lt 20) {
        Bad "C: drive critically low ($freeGB GB free) - Windows needs at least 20GB"
    } elseif ($freeGB -lt 40) {
        Warn "C: drive low ($freeGB GB free) - recommend 40GB+ for comfortable use"
    } else {
        OK "C: drive space sufficient ($freeGB GB free)"
    }
}

# ─── 2. RAM ──────────────────────────────────────────────────
Section "2/5  RAM Check"
Log "  Checking RAM..." "Cyan"
try {
    $ramGB   = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $freeGB  = [math]::Round((Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    $usedPct = [math]::Round(($ramGB - $freeGB) / $ramGB * 100, 0)
    Info "Total RAM : $ramGB GB  |  Used: $usedPct%"

    if ($ramGB -lt 2) {
        Bad "RAM $ramGB GB - too low, Windows 10/11 requires minimum 4GB"
    } elseif ($ramGB -lt 4) {
        Warn "RAM $ramGB GB - below minimum recommendation (4GB+)"
    } else {
        OK "RAM $ramGB GB - sufficient for Windows install"
    }

    # RAM slot details
    $sticks = Get-WmiObject Win32_PhysicalMemory
    foreach ($s in $sticks) {
        $gb  = [math]::Round($s.Capacity / 1GB, 0)
        $mhz = $s.Speed
        Info "  Slot $($s.DeviceLocator): $gb GB @ $mhz MHz  ($($s.Manufacturer))"
    }

    # RAM error check via event log
    $ramErrors = Get-EventLog -LogName System -Source "Microsoft-Windows-MemoryDiagnostics-Results" `
        -Newest 5 -ErrorAction SilentlyContinue
    if ($ramErrors) {
        foreach ($e in $ramErrors) {
            if ($e.Message -match "error" -or $e.Message -match "fail") {
                Bad "RAM error detected in event log: $($e.Message.Substring(0,[math]::Min(80,$e.Message.Length)))"
            }
        }
    } else {
        OK "No RAM errors in event log"
    }
} catch {
    Warn "RAM check error: $($_.Exception.Message)"
}

# ─── 3. CPU ──────────────────────────────────────────────────
Section "3/5  CPU Check"
Log "  Checking CPU..." "Cyan"
try {
    $cpus    = @(Get-WmiObject Win32_Processor)
    $cpuLoad = [math]::Round(($cpus | Measure-Object -Property LoadPercentage -Average).Average, 0)
    Info "CPU       : $($cpus[0].Name)"
    Info "Cores     : $($cpus[0].NumberOfCores) cores / $($cpus[0].NumberOfLogicalProcessors) threads"
    Info "CPU Load  : $cpuLoad%  ($($cpus.Count) socket(s))"

    if ($cpuLoad -gt 95) {
        Bad "CPU load $cpuLoad% - critically overloaded, may cause install failure"
    } elseif ($cpuLoad -gt 80) {
        Warn "CPU load $cpuLoad% at idle - something is overloading CPU"
    } else {
        OK "CPU load normal ($cpuLoad%)"
    }

    # CPU temperature
    try {
        $temps = Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        $maxC  = 0
        foreach ($t in $temps) {
            $c = [math]::Round($t.CurrentTemperature / 10 - 273.15, 1)
            if ($c -gt $maxC) { $maxC = $c }
        }
        Info "CPU Temp  : $maxC C"
        if ($maxC -gt 95) {
            Bad "CPU temperature critical: $maxC C - cooling failure, do not install"
        } elseif ($maxC -gt 80) {
            Warn "CPU temperature high: $maxC C - check cooling before install"
        } elseif ($maxC -gt 0) {
            OK "CPU temperature OK: $maxC C"
        }
    } catch {
        Info "CPU temp sensor not accessible via WMI"
    }
} catch {
    Warn "CPU check error: $($_.Exception.Message)"
}

# ─── 4. GPU / Display ────────────────────────────────────────
Section "4/5  GPU and Display"
Log "  Checking GPU..." "Cyan"
try {
    $gpus = Get-WmiObject Win32_VideoController
    foreach ($g in $gpus) {
        $vramMB = [math]::Round($g.AdapterRAM / 1MB, 0)
        Info "GPU: $($g.Name)  VRAM: $vramMB MB  Status: $($g.Status)"
        if ($g.Status -ne "OK") {
            Bad "GPU error: $($g.Name) status = $($g.Status)"
        } else {
            OK "GPU OK: $($g.Name)"
        }
        if ($g.Name -match "Microsoft Basic Display") {
            Warn "Basic Display Adapter detected - GPU driver missing or GPU issue"
        }
    }
} catch {
    Warn "GPU check error: $($_.Exception.Message)"
}

# ─── 5. System Event Log (hardware errors) ───────────────────
Section "5/5  Hardware Error Events (last 30 days)"
Log "  Checking hardware error events..." "Cyan"
try {
    $since = (Get-Date).AddDays(-30)

    # Disk errors
    $diskEvt = Get-EventLog -LogName System -Source "disk","atapi","iaStorA","nvme" `
        -EntryType Error -After $since -Newest 20 -ErrorAction SilentlyContinue
    if ($diskEvt -and $diskEvt.Count -gt 0) {
        Bad "Disk hardware errors in event log ($($diskEvt.Count) events) - disk may be failing"
        $diskEvt | Select-Object -First 3 | ForEach-Object {
            Info "  $($_.TimeGenerated.ToString('MM/dd')) $($_.Source): $($_.Message.Substring(0,[math]::Min(60,$_.Message.Length)))"
        }
    } else {
        OK "No disk hardware errors in event log"
    }

    # BSOD
    $bsod = Get-EventLog -LogName System -Source "BugCheck" -After $since -ErrorAction SilentlyContinue
    if ($bsod -and $bsod.Count -gt 0) {
        Warn "BSOD detected $($bsod.Count) time(s) in last 30 days"
        $bsod | Select-Object -First 3 | ForEach-Object {
            Info "  $($_.TimeGenerated.ToString('MM/dd HH:mm'))"
        }
    } else {
        OK "No BSOD in last 30 days"
    }

    # Memory hardware errors
    $memEvt = Get-EventLog -LogName System -Source "Microsoft-Windows-WER-SystemErrorReporting" `
        -EntryType Error -After $since -Newest 10 -ErrorAction SilentlyContinue
    if ($memEvt -and $memEvt.Count -gt 0) {
        Warn "System error reports found ($($memEvt.Count)) - may indicate hardware instability"
    } else {
        OK "No critical system error reports"
    }
} catch {
    Warn "Event log check error: $($_.Exception.Message)"
}

# ─── Final Verdict ───────────────────────────────────────────
$bar = "=" * 55
Log "" ; Log $bar "Cyan" ; Log "   HARDWARE DIAGNOSTIC RESULT" "Cyan" ; Log $bar "Cyan"

$canInstall = $problems.Count -eq 0

if ($problems.Count -gt 0) {
    Log "" "White"
    Log "  PROBLEMS FOUND ($($problems.Count)):" "Red"
    foreach ($p in $problems) { Log "  !! $p" "Red" }
}
if ($warnings.Count -gt 0) {
    Log "" "White"
    Log "  WARNINGS ($($warnings.Count)):" "Yellow"
    foreach ($w in $warnings) { Log "  >> $w" "Yellow" }
}

Log "" "White"

if ($canInstall) {
    Log "  RESULT: Hardware OK - Safe to proceed with Windows reinstall" "Green"
    Log $bar "Green"

    # Customer popup - all clear
    $popupMsg = "[ Hardware Check Complete ]`n`n" +
        "All hardware is functioning normally.`n`n" +
        "PC: $env:COMPUTERNAME`n" +
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n`n" +
        "Windows reinstall can proceed safely."
    Popup "Hardware Diagnostic - OK" $popupMsg

} else {
    Log "  RESULT: Hardware problems detected - DO NOT reinstall yet" "Red"
    Log $bar "Red"

    # Build customer-friendly problem description
    $problemDesc = ""
    $replaceList = ""

    foreach ($p in $problems) {
        if ($p -match "Disk FAILURE|SMART failure|disk.*fail") {
            $problemDesc += "- Storage drive (HDD/SSD) failure detected`n"
            $replaceList += "  HDD/SSD replacement required`n"
        }
        if ($p -match "RAM.*too low|RAM.*below") {
            $problemDesc += "- Insufficient RAM memory`n"
            $replaceList += "  RAM upgrade required (minimum 4GB)`n"
        }
        if ($p -match "RAM error") {
            $problemDesc += "- RAM memory error detected`n"
            $replaceList += "  RAM replacement required`n"
        }
        if ($p -match "CPU.*critical|CPU temperature critical") {
            $problemDesc += "- CPU overheating (cooling system failure)`n"
            $replaceList += "  CPU cooler cleaning or replacement required`n"
        }
        if ($p -match "GPU error") {
            $problemDesc += "- GPU (graphics card) error detected`n"
            $replaceList += "  GPU driver reinstall or replacement required`n"
        }
        if ($p -match "C:.*low|drive critically") {
            $problemDesc += "- Insufficient disk space for Windows install`n"
            $replaceList += "  Larger HDD/SSD replacement recommended`n"
        }
        if ($p -match "Disk hardware errors") {
            $problemDesc += "- Disk hardware errors in system log`n"
            $replaceList += "  HDD/SSD replacement recommended`n"
        }
    }

    if ($problemDesc -eq "") { $problemDesc = "- Hardware issues detected (see log for details)`n" }
    if ($replaceList -eq "") { $replaceList = "  Hardware inspection required`n" }

    # Customer popup - problems found
    $popupMsg = "[ Hardware Problem Detected ]`n`n" +
        "The following hardware issues were found:`n`n" +
        $problemDesc + "`n" +
        "Windows reinstall cannot proceed until these are resolved.`n`n" +
        "Parts that need replacement:`n" +
        $replaceList + "`n" +
        "Please consult with the technician for repair options.`n`n" +
        "PC: $env:COMPUTERNAME`n" +
        "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    Popup "Hardware Problem - Action Required" $popupMsg

    # Also show warnings if any
    if ($warnings.Count -gt 0) {
        $warnMsg = "[ Additional Warnings ]`n`n"
        foreach ($w in $warnings) { $warnMsg += "- $w`n" }
        $warnMsg += "`nThese are not critical but should be monitored."
        Popup "Hardware Warnings" $warnMsg
    }
}

Log "" "White"
Log "  Log saved: $LogFile" "Gray"
Log $bar "Cyan"

Read-Host "Press Enter to close"
