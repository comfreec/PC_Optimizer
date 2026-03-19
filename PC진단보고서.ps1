# PC Diagnostic Report - Pre-Service Assessment

$LogFile = "$PSScriptRoot\diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$issues  = @()   # collected problems to show in summary

function Log {
    param([string]$msg, [string]$color = "White")
    $line = $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Section {
    param([string]$title)
    $bar = "=" * 55
    Write-Host "" ; Write-Host $bar -ForegroundColor Yellow
    Write-Host "  $title" -ForegroundColor Yellow
    Write-Host $bar -ForegroundColor Yellow ; Write-Host ""
    Add-Content -Path $LogFile -Value "" -Encoding UTF8
    Add-Content -Path $LogFile -Value $bar -Encoding UTF8
    Add-Content -Path $LogFile -Value "  $title" -Encoding UTF8
    Add-Content -Path $LogFile -Value $bar -Encoding UTF8
}

function Issue {
    param([string]$msg)
    $issues += $msg
    $script:issues += $msg
    Log "  !! $msg" "Red"
}

function OK   { param([string]$msg) Log "  OK  $msg" "Green" }
function Info { param([string]$msg) Log "  --  $msg" "Gray"  }
function Warn { param([string]$msg) Log "  >>  $msg" "Yellow" }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
$bar55 = "=" * 55
Write-Host $bar55 -ForegroundColor Cyan
Write-Host "   PC Diagnostic Report" -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host $bar55 -ForegroundColor Cyan
Add-Content -Path $LogFile -Value $bar55 -Encoding UTF8
Add-Content -Path $LogFile -Value "   PC Diagnostic Report" -Encoding UTF8
Add-Content -Path $LogFile -Value "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -Encoding UTF8
Add-Content -Path $LogFile -Value $bar55 -Encoding UTF8

# ─── 1. PC Basic Info ───────────────────────────────────────
Section "1/8  PC Basic Info"
try {
    $cs  = Get-WmiObject Win32_ComputerSystem
    $os  = Get-WmiObject Win32_OperatingSystem
    $cpu = Get-WmiObject Win32_Processor
    $mb  = Get-WmiObject Win32_BaseBoard

    Info "PC Name     : $($cs.Name)"
    Info "Manufacturer: $($cs.Manufacturer)"
    Info "Model       : $($cs.Model)"
    Info "Motherboard : $($mb.Manufacturer) $($mb.Product)"
    Info "OS          : $($os.Caption) (Build $($os.BuildNumber))"
    Info "OS Install  : $([Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate).ToString('yyyy-MM-dd'))"
    Info "Last Boot   : $([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm'))"
    Info "CPU         : $($cpu.Name)"
    Info "CPU Cores   : $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"

    # Windows activation
    $lic = Get-WmiObject SoftwareLicensingProduct -Filter "Name like 'Windows%' AND LicenseStatus=1" -ErrorAction SilentlyContinue
    if ($lic) { OK "Windows activation: Licensed" }
    else { Issue "Windows not activated" }

    # OS age
    $installDate = [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)
    $ageMonths   = [math]::Round(((Get-Date) - $installDate).TotalDays / 30, 0)
    if ($ageMonths -gt 24) { Warn "OS installed $ageMonths months ago - consider reinstall" }
    else { Info "OS age: $ageMonths months" }

} catch { Warn "Basic info collection error: $($_.Exception.Message)" }

# ─── 2. RAM ─────────────────────────────────────────────────
Section "2/8  Memory (RAM)"
try {
    $ramGB    = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $freeGB   = [math]::Round((Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    $usedPct  = [math]::Round(($ramGB - $freeGB) / $ramGB * 100, 0)

    Info "Total RAM   : $ramGB GB"
    Info "Free RAM    : $freeGB GB  (used $usedPct%)"

    if ($ramGB -lt 4)       { Issue "RAM $ramGB GB - too low, upgrade recommended (min 8GB)" }
    elseif ($ramGB -lt 8)   { Warn  "RAM $ramGB GB - low for modern use, 8GB+ recommended" }
    else                    { OK    "RAM $ramGB GB - sufficient" }

    if ($usedPct -gt 85)    { Issue "RAM usage $usedPct% - critically high at idle" }
    elseif ($usedPct -gt 70){ Warn  "RAM usage $usedPct% - high at idle" }

    # RAM sticks detail
    $sticks = Get-WmiObject Win32_PhysicalMemory
    foreach ($s in $sticks) {
        $gb   = [math]::Round($s.Capacity / 1GB, 0)
        $mhz  = $s.Speed
        Info "  Slot $($s.DeviceLocator): $gb GB @ $mhz MHz  $($s.Manufacturer)"
    }
} catch { Warn "RAM check error: $($_.Exception.Message)" }

# ─── 3. Disk ────────────────────────────────────────────────
Section "3/8  Disk"
try {
    # Physical disks
    $physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physDisks) {
        foreach ($pd in $physDisks) {
            $sizeGB = [math]::Round($pd.Size / 1GB, 0)
            $health = $pd.HealthStatus
            $hColor = if ($health -eq "Healthy") { "Green" } elseif ($health -eq "Warning") { "Yellow" } else { "Red" }
            Log "  --  Disk: $($pd.FriendlyName) | $($pd.MediaType) | $sizeGB GB | Health: $health" $hColor
            if ($health -ne "Healthy") { $script:issues += "Disk health: $($pd.FriendlyName) = $health" }
        }
    }

    # Logical drives
    $logDisks = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    foreach ($d in $logDisks) {
        $totalGB = [math]::Round($d.Size / 1GB, 1)
        $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round(($totalGB - $freeGB) / $totalGB * 100, 0)
        Info "  Drive $($d.DeviceID)  $freeGB GB free / $totalGB GB  (used $usedPct%)"
        if ($usedPct -gt 90)      { Issue "Drive $($d.DeviceID) almost full ($usedPct%) - cleanup needed" }
        elseif ($usedPct -gt 80)  { Warn  "Drive $($d.DeviceID) $usedPct% used - getting full" }
    }

    # SMART via WMI
    try {
        $smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($s in $smart) {
            if ($s.PredictFailure) { Issue "SMART failure predicted - disk may fail soon, backup immediately" }
            else { OK "SMART: No failure predicted" }
        }
    } catch { Info "SMART data not available" }

} catch { Warn "Disk check error: $($_.Exception.Message)" }

# ─── 4. CPU Temperature & Load ──────────────────────────────
Section "4/8  CPU Temperature and Load"
try {
    # CPU load
    $cpuLoad = (Get-WmiObject Win32_Processor).LoadPercentage
    Info "CPU Load    : $cpuLoad%"
    if ($cpuLoad -gt 80) { Issue "CPU load $cpuLoad% at idle - something is overloading CPU" }
    elseif ($cpuLoad -gt 50) { Warn "CPU load $cpuLoad% - higher than normal at idle" }
    else { OK "CPU load normal ($cpuLoad%)" }

    # Temperature via WMI (works on some systems)
    try {
        $temps = Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        foreach ($t in $temps) {
            $celsius = [math]::Round($t.CurrentTemperature / 10 - 273.15, 1)
            Info "CPU Temp    : $celsius C"
            if ($celsius -gt 90)      { Issue "CPU temperature critical: $celsius C - check cooling" }
            elseif ($celsius -gt 75)  { Warn  "CPU temperature high: $celsius C" }
            else                      { OK    "CPU temperature OK: $celsius C" }
        }
    } catch {
        Info "CPU temperature sensor not accessible via WMI"
        Info "Use HWMonitor or HWiNFO for accurate temperature reading"
    }
} catch { Warn "CPU check error: $($_.Exception.Message)" }

# ─── 5. Startup Programs & Services ────────────────────────
Section "5/8  Startup Programs and Services"
try {
    $startupKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    $startupCount = 0
    $startupList  = @()
    foreach ($key in $startupKeys) {
        if (Test-Path $key) {
            $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            $entries.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $startupCount++
                $startupList += $_.Name
            }
        }
    }
    Info "Startup programs: $startupCount"
    $startupList | ForEach-Object { Info "  - $_" }

    if ($startupCount -gt 15)     { Issue "Too many startup programs ($startupCount) - slowing boot" }
    elseif ($startupCount -gt 8)  { Warn  "Many startup programs ($startupCount) - consider cleanup" }
    else                          { OK    "Startup count OK ($startupCount)" }

    # Running services count
    $runningSvc = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
    Info "Running services: $runningSvc"
    if ($runningSvc -gt 150) { Warn "High number of running services ($runningSvc)" }
    else { OK "Services count OK ($runningSvc)" }

} catch { Warn "Startup check error: $($_.Exception.Message)" }

# ─── 6. Windows Update & Security ──────────────────────────
Section "6/8  Windows Update and Security"
try {
    # Last Windows Update
    $wu = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($wu) {
        $daysSince = ((Get-Date) - $wu.InstalledOn).Days
        Info "Last update : $($wu.InstalledOn.ToString('yyyy-MM-dd'))  ($daysSince days ago)"
        if ($daysSince -gt 90)     { Issue "No Windows update in $daysSince days - security risk" }
        elseif ($daysSince -gt 30) { Warn  "Last update $daysSince days ago - update recommended" }
        else                       { OK    "Windows recently updated ($daysSince days ago)" }
    } else { Warn "Cannot determine last update date" }

    # Windows Defender
    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop
        if ($mpStatus.AntivirusEnabled)       { OK   "Defender antivirus: ON" }
        else                                  { Issue "Defender antivirus: OFF - security risk" }
        if ($mpStatus.RealTimeProtectionEnabled) { OK "Real-time protection: ON" }
        else                                  { Issue "Real-time protection: OFF" }
        $defAge = ((Get-Date) - $mpStatus.AntivirusSignatureLastUpdated).Days
        Info "Defender definitions: $defAge days old"
        if ($defAge -gt 7) { Warn "Defender definitions outdated ($defAge days)" }
    } catch { Info "Defender status not available" }

    # Firewall
    try {
        $fw = Get-NetFirewallProfile -ErrorAction Stop
        $fw | ForEach-Object {
            if ($_.Enabled) { OK   "Firewall $($_.Name): ON" }
            else            { Issue "Firewall $($_.Name): OFF - security risk" }
        }
    } catch { Info "Firewall status not available" }

} catch { Warn "Security check error: $($_.Exception.Message)" }

# ─── 7. Network ─────────────────────────────────────────────
Section "7/8  Network"
try {
    # Active adapters
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adapters) {
        Info "Adapter: $($a.Name)  $($a.InterfaceDescription)  $($a.LinkSpeed)"
    }

    # Internet connectivity
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($ping) { OK "Internet: Connected" }
    else       { Issue "Internet: Not connected or DNS issue" }

    # DNS check
    try {
        $dns = Resolve-DnsName "www.google.com" -ErrorAction Stop
        OK "DNS resolution: OK"
    } catch { Issue "DNS resolution failed - network config issue" }

    # IP info
    $ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
    foreach ($ip in $ipConfig) {
        Info "IP: $($ip.IPAddress)  ($($ip.InterfaceAlias))"
    }
} catch { Warn "Network check error: $($_.Exception.Message)" }

# ─── 8. Event Log Errors (last 7 days) ──────────────────────
Section "8/8  System Event Log (last 7 days)"
try {
    $since = (Get-Date).AddDays(-7)
    $critErrors = Get-EventLog -LogName System -EntryType Error,Warning -After $since -Newest 50 -ErrorAction SilentlyContinue

    $errorCount   = ($critErrors | Where-Object { $_.EntryType -eq "Error" }).Count
    $warningCount = ($critErrors | Where-Object { $_.EntryType -eq "Warning" }).Count
    Info "Errors (7d)  : $errorCount"
    Info "Warnings (7d): $warningCount"

    if ($errorCount -gt 50)     { Issue "Very high system error count ($errorCount) in last 7 days" }
    elseif ($errorCount -gt 20) { Warn  "High system error count ($errorCount) in last 7 days" }
    elseif ($errorCount -gt 0)  { Warn  "$errorCount system errors in last 7 days" }
    else                        { OK    "No system errors in last 7 days" }

    # Top error sources
    $topSources = $critErrors | Where-Object { $_.EntryType -eq "Error" } |
        Group-Object Source | Sort-Object Count -Descending | Select-Object -First 5
    if ($topSources) {
        Info "Top error sources:"
        $topSources | ForEach-Object { Info "  $($_.Count)x  $($_.Name)" }
    }

    # BSOD check
    $bsod = Get-EventLog -LogName System -Source "BugCheck" -After $since -ErrorAction SilentlyContinue
    if ($bsod) {
        Issue "BSOD detected $($bsod.Count) time(s) in last 7 days"
    } else { OK "No BSOD in last 7 days" }

} catch { Warn "Event log check error: $($_.Exception.Message)" }

# ─── Summary ────────────────────────────────────────────────
$bar55 = "=" * 55
Write-Host ""
Write-Host $bar55 -ForegroundColor Cyan
Write-Host "   DIAGNOSTIC SUMMARY" -ForegroundColor Cyan
Write-Host $bar55 -ForegroundColor Cyan
Add-Content -Path $LogFile -Value "" -Encoding UTF8
Add-Content -Path $LogFile -Value $bar55 -Encoding UTF8
Add-Content -Path $LogFile -Value "   DIAGNOSTIC SUMMARY" -Encoding UTF8
Add-Content -Path $LogFile -Value $bar55 -Encoding UTF8

if ($issues.Count -eq 0) {
    Write-Host "  No major issues found." -ForegroundColor Green
    Add-Content -Path $LogFile -Value "  No major issues found." -Encoding UTF8
} else {
    Write-Host "  Issues found ($($issues.Count)):" -ForegroundColor Red
    Add-Content -Path $LogFile -Value "  Issues found ($($issues.Count)):" -Encoding UTF8
    foreach ($iss in $issues) {
        Write-Host "  !! $iss" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "  !! $iss" -Encoding UTF8
    }
}

Write-Host ""
Write-Host "  Recommended services:" -ForegroundColor Yellow
Add-Content -Path $LogFile -Value "" -Encoding UTF8
Add-Content -Path $LogFile -Value "  Recommended services:" -Encoding UTF8

# Auto-recommend based on issues
$recList = @()
$issueText = $issues -join " "
if ($issueText -match "startup|load|RAM|service") { $recList += "Service1 - Speed Optimization (빠르게.bat)" }
if ($issueText -match "update|Defender|Firewall|activation") { $recList += "Service2 - Windows Update (최신상태.bat)" }
if ($issueText -match "BSOD|boot") { $recList += "Service3 - Boot Recovery (부팅복구_WinRE.bat)" }
if ($issueText -match "SMART|disk.*fail|reinstall") { $recList += "Service4 - Windows Reinstall (최후수단_자동복구.bat)" }
if ($issueText -match "virus|security") { $recList += "Virus Scan (바이러스검사.bat)" }

if ($recList.Count -eq 0) { $recList += "Service1 - Speed Optimization (routine maintenance)" }

foreach ($r in $recList) {
    Write-Host "  -> $r" -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value "  -> $r" -Encoding UTF8
}

Write-Host ""
Write-Host $bar55 -ForegroundColor Green
Write-Host "  Report saved: $LogFile" -ForegroundColor Green
Write-Host $bar55 -ForegroundColor Green
Add-Content -Path $LogFile -Value $bar55 -Encoding UTF8
Add-Content -Path $LogFile -Value "  Report saved: $LogFile" -Encoding UTF8

Read-Host "Press Enter to close"
