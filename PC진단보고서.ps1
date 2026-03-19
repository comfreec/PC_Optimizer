# PC Diagnostic Report - with Before/After Comparison

$Timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$PCName     = $env:COMPUTERNAME -replace '[\\/:*?"<>|]', '_'
$LogFile    = "$PSScriptRoot\diagnostic_${PCName}_$Timestamp.txt"
$SnapFile   = "$PSScriptRoot\diagnostic_${PCName}_$Timestamp.json"
$issues     = [System.Collections.Generic.List[string]]::new()
$snap       = @{}   # snapshot data for comparison

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
function Issue { param([string]$msg) $script:issues.Add($msg); Log "  !! $msg" "Red" }
function OK    { param([string]$msg) Log "  OK  $msg" "Green" }
function Info  { param([string]$msg) Log "  --  $msg" "Gray" }
function Warn  { param([string]$msg) Log "  >>  $msg" "Yellow" }

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
$bar55 = "=" * 55
Log $bar55 "Cyan"
Log "   PC Diagnostic Report" "Cyan"
Log "   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" "Cyan"
Log $bar55 "Cyan"

# ─── 1. PC Basic Info ───────────────────────────────────────
Section "1/8  PC Basic Info"
try {
    $cs  = Get-WmiObject Win32_ComputerSystem
    $os  = Get-WmiObject Win32_OperatingSystem
    $cpu = Get-WmiObject Win32_Processor
    $mb  = Get-WmiObject Win32_BaseBoard
    Info "PC Name     : $($cs.Name)"
    Info "Model       : $($cs.Manufacturer) $($cs.Model)"
    Info "Motherboard : $($mb.Manufacturer) $($mb.Product)"
    Info "OS          : $($os.Caption) (Build $($os.BuildNumber))"
    $installDate = [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate)
    $ageMonths   = [math]::Round(((Get-Date) - $installDate).TotalDays / 30, 0)
    Info "OS Install  : $($installDate.ToString('yyyy-MM-dd'))  ($ageMonths months ago)"
    Info "CPU         : $($cpu.Name)"
    $snap.PCName   = $cs.Name
    $snap.Model    = "$($cs.Manufacturer) $($cs.Model)"
    $snap.OS       = $os.Caption
    $snap.OSBuild  = $os.BuildNumber
    $snap.OSAgeMonths = $ageMonths
    $lic = Get-WmiObject SoftwareLicensingProduct -Filter "Name like 'Windows%' AND LicenseStatus=1" -ErrorAction SilentlyContinue
    $snap.Activated = ($null -ne $lic)
    if ($snap.Activated) { OK "Windows: Licensed" } else { Issue "Windows not activated" }
    if ($ageMonths -gt 24) { Warn "OS installed $ageMonths months ago - consider reinstall" }
} catch { Warn "Basic info error: $($_.Exception.Message)" }

# ─── 2. RAM ─────────────────────────────────────────────────
Section "2/8  Memory (RAM)"
try {
    $ramGB   = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $freeGB  = [math]::Round((Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
    $usedPct = [math]::Round(($ramGB - $freeGB) / $ramGB * 100, 0)
    Info "Total RAM   : $ramGB GB"
    Info "Free RAM    : $freeGB GB  (used $usedPct%)"
    $snap.RAMtotalGB = $ramGB
    $snap.RAMusedPct = $usedPct
    if ($ramGB -lt 4)      { Issue "RAM $ramGB GB - too low (min 8GB recommended)" }
    elseif ($ramGB -lt 8)  { Warn  "RAM $ramGB GB - low for modern use" }
    else                   { OK    "RAM $ramGB GB - sufficient" }
    if ($usedPct -gt 85)   { Issue "RAM usage $usedPct% at idle - critically high" }
    elseif ($usedPct -gt 70){ Warn "RAM usage $usedPct% at idle - high" }
    else                   { OK    "RAM usage $usedPct% - normal" }
    $sticks = Get-WmiObject Win32_PhysicalMemory
    foreach ($s in $sticks) {
        Info "  Slot $($s.DeviceLocator): $([math]::Round($s.Capacity/1GB,0)) GB @ $($s.Speed) MHz  $($s.Manufacturer)"
    }
} catch { Warn "RAM check error: $($_.Exception.Message)" }

# ─── 3. Disk ────────────────────────────────────────────────
Section "3/8  Disk"
try {
    $snap.Disks = @()
    $physDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physDisks) {
        foreach ($pd in $physDisks) {
            $sizeGB = [math]::Round($pd.Size / 1GB, 0)
            $health = $pd.HealthStatus
            $col    = if ($health -eq "Healthy") {"Green"} elseif ($health -eq "Warning") {"Yellow"} else {"Red"}
            Log "  --  $($pd.FriendlyName) | $($pd.MediaType) | $sizeGB GB | $health" $col
            if ($health -ne "Healthy") { Issue "Disk health: $($pd.FriendlyName) = $health" }
        }
    }
    $logDisks = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    foreach ($d in $logDisks) {
        $totalGB = [math]::Round($d.Size / 1GB, 1)
        $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
        $usedPct = [math]::Round(($totalGB - $freeGB) / $totalGB * 100, 0)
        Info "  Drive $($d.DeviceID)  $freeGB GB free / $totalGB GB  (used $usedPct%)"
        $snap.Disks += @{ Drive=$d.DeviceID; TotalGB=$totalGB; FreeGB=$freeGB; UsedPct=$usedPct }
        if ($usedPct -gt 90)     { Issue "Drive $($d.DeviceID) almost full ($usedPct%)" }
        elseif ($usedPct -gt 80) { Warn  "Drive $($d.DeviceID) $usedPct% used" }
        else                     { OK    "Drive $($d.DeviceID) usage OK ($usedPct%)" }
    }
    try {
        $smart = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        $snap.SMARTfail = ($smart | Where-Object { $_.PredictFailure }).Count -gt 0
        foreach ($s in $smart) {
            if ($s.PredictFailure) { Issue "SMART failure predicted - backup immediately" }
            else { OK "SMART: No failure predicted" }
        }
    } catch { Info "SMART not available"; $snap.SMARTfail = $false }
} catch { Warn "Disk check error: $($_.Exception.Message)" }

# ─── 4. CPU Load & Temperature ──────────────────────────────
Section "4/8  CPU Load and Temperature"
try {
    $cpuLoad = (Get-WmiObject Win32_Processor).LoadPercentage
    Info "CPU Load    : $cpuLoad%"
    $snap.CPUloadPct = $cpuLoad
    if ($cpuLoad -gt 80)   { Issue "CPU load $cpuLoad% at idle - something overloading CPU" }
    elseif ($cpuLoad -gt 50){ Warn "CPU load $cpuLoad% at idle - higher than normal" }
    else                   { OK   "CPU load normal ($cpuLoad%)" }
    try {
        $temps = Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        $maxTemp = 0
        foreach ($t in $temps) {
            $c = [math]::Round($t.CurrentTemperature / 10 - 273.15, 1)
            if ($c -gt $maxTemp) { $maxTemp = $c }
            Info "CPU Temp    : $c C"
            if ($c -gt 90)      { Issue "CPU temp critical: $c C" }
            elseif ($c -gt 75)  { Warn  "CPU temp high: $c C" }
            else                { OK    "CPU temp OK: $c C" }
        }
        $snap.CPUtempC = $maxTemp
    } catch {
        Info "CPU temp sensor not accessible (use HWMonitor for accurate reading)"
        $snap.CPUtempC = -1
    }
} catch { Warn "CPU check error: $($_.Exception.Message)" }

# ─── 5. Startup Programs ────────────────────────────────────
Section "5/8  Startup Programs and Services"
try {
    $startupKeys = @(
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    $startupList = @()
    foreach ($key in $startupKeys) {
        if (Test-Path $key) {
            $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            $entries.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $startupList += $_.Name
            }
        }
    }
    $startupCount = $startupList.Count
    Info "Startup programs: $startupCount"
    $startupList | ForEach-Object { Info "  - $_" }
    $snap.StartupCount = $startupCount
    if ($startupCount -gt 15)    { Issue "Too many startup programs ($startupCount)" }
    elseif ($startupCount -gt 8) { Warn  "Many startup programs ($startupCount)" }
    else                         { OK    "Startup count OK ($startupCount)" }
    $runningSvc = (Get-Service | Where-Object { $_.Status -eq "Running" }).Count
    Info "Running services: $runningSvc"
    $snap.RunningServices = $runningSvc
    if ($runningSvc -gt 150) { Warn "High service count ($runningSvc)" }
    else { OK "Services count OK ($runningSvc)" }
} catch { Warn "Startup check error: $($_.Exception.Message)" }

# ─── 6. Security ────────────────────────────────────────────
Section "6/8  Windows Update and Security"
try {
    $wu = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($wu) {
        $daysSince = [math]::Round(((Get-Date) - $wu.InstalledOn).TotalDays, 0)
        Info "Last update : $($wu.InstalledOn.ToString('yyyy-MM-dd'))  ($daysSince days ago)"
        $snap.DaysSinceUpdate = $daysSince
        if ($daysSince -gt 90)     { Issue "No Windows update in $daysSince days" }
        elseif ($daysSince -gt 30) { Warn  "Last update $daysSince days ago" }
        else                       { OK    "Windows recently updated ($daysSince days ago)" }
    }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $snap.DefenderOn   = $mp.AntivirusEnabled
        $snap.RealTimeOn   = $mp.RealTimeProtectionEnabled
        $snap.DefenderDays = [math]::Round(((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays, 0)
        if ($mp.AntivirusEnabled)        { OK    "Defender: ON" } else { Issue "Defender: OFF" }
        if ($mp.RealTimeProtectionEnabled){ OK   "Real-time protection: ON" } else { Issue "Real-time protection: OFF" }
        if ($snap.DefenderDays -gt 7)    { Warn  "Defender definitions $($snap.DefenderDays) days old" }
        else                             { OK    "Defender definitions up to date" }
    } catch { Info "Defender status not available" }
    try {
        $fw = Get-NetFirewallProfile -ErrorAction Stop
        $snap.FirewallOn = ($fw | Where-Object { -not $_.Enabled }).Count -eq 0
        $fw | ForEach-Object {
            if ($_.Enabled) { OK "Firewall $($_.Name): ON" } else { Issue "Firewall $($_.Name): OFF" }
        }
    } catch { Info "Firewall status not available" }
} catch { Warn "Security check error: $($_.Exception.Message)" }

# ─── 7. Network ─────────────────────────────────────────────
Section "7/8  Network"
try {
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($a in $adapters) { Info "Adapter: $($a.Name)  $($a.LinkSpeed)" }
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
    $snap.InternetOK = $ping
    if ($ping) { OK "Internet: Connected" } else { Issue "Internet: Not connected" }
    try {
        $null = Resolve-DnsName "www.google.com" -ErrorAction Stop
        $snap.DNSOK = $true ; OK "DNS: OK"
    } catch { $snap.DNSOK = $false ; Issue "DNS resolution failed" }
    $ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*" }
    foreach ($ip in $ipConfig) { Info "IP: $($ip.IPAddress)  ($($ip.InterfaceAlias))" }
} catch { Warn "Network check error: $($_.Exception.Message)" }

# ─── 8. Event Log ───────────────────────────────────────────
Section "8/8  System Event Log (last 7 days)"
try {
    $since = (Get-Date).AddDays(-7)
    $evts  = Get-EventLog -LogName System -EntryType Error,Warning -After $since -Newest 100 -ErrorAction SilentlyContinue
    $errCnt  = ($evts | Where-Object { $_.EntryType -eq "Error" }).Count
    $warnCnt = ($evts | Where-Object { $_.EntryType -eq "Warning" }).Count
    Info "Errors (7d)  : $errCnt"
    Info "Warnings (7d): $warnCnt"
    $snap.EventErrors   = $errCnt
    $snap.EventWarnings = $warnCnt
    if ($errCnt -gt 50)     { Issue "Very high error count ($errCnt) in 7 days" }
    elseif ($errCnt -gt 20) { Warn  "High error count ($errCnt) in 7 days" }
    elseif ($errCnt -gt 0)  { Warn  "$errCnt system errors in 7 days" }
    else                    { OK    "No system errors in last 7 days" }
    $topSrc = $evts | Where-Object { $_.EntryType -eq "Error" } |
        Group-Object Source | Sort-Object Count -Descending | Select-Object -First 5
    if ($topSrc) { $topSrc | ForEach-Object { Info "  $($_.Count)x  $($_.Name)" } }
    $bsod = Get-EventLog -LogName System -Source "BugCheck" -After $since -ErrorAction SilentlyContinue
    $snap.BSODcount = if ($bsod) { $bsod.Count } else { 0 }
    if ($snap.BSODcount -gt 0) { Issue "BSOD $($snap.BSODcount) time(s) in last 7 days" }
    else { OK "No BSOD in last 7 days" }
} catch { Warn "Event log error: $($_.Exception.Message)" }

# ─── Save snapshot JSON ─────────────────────────────────────
$snap.Timestamp  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$snap.IssueCount = $issues.Count
$snap.Issues     = $issues -join "|"
$snap | ConvertTo-Json -Depth 3 | Out-File -FilePath $SnapFile -Encoding UTF8

# ─── Summary ────────────────────────────────────────────────
$bar55 = "=" * 55
Log "" ; Log $bar55 "Cyan" ; Log "   DIAGNOSTIC SUMMARY" "Cyan" ; Log $bar55 "Cyan"
if ($issues.Count -eq 0) {
    Log "  No major issues found." "Green"
} else {
    Log "  Issues found ($($issues.Count)):" "Red"
    foreach ($iss in $issues) { Log "  !! $iss" "Red" }
}
Log ""
Log "  Recommended services:" "Yellow"
$issText = $issues -join " "
$recList = @()
if ($issText -match "startup|load|RAM|service|CPU")   { $recList += "-> Service1  Speed Optimization  (빠르게.bat)" }
if ($issText -match "update|Defender|Firewall|activ")  { $recList += "-> Service2  Windows Update      (최신상태.bat)" }
if ($issText -match "BSOD|boot")                       { $recList += "-> Service3  Boot Recovery       (부팅복구_WinRE.bat)" }
if ($issText -match "SMART|disk.*fail|reinstall")      { $recList += "-> Service4  Windows Reinstall   (최후수단_자동복구.bat)" }
if ($issText -match "virus|security")                  { $recList += "-> Virus Scan                    (바이러스검사.bat)" }
if ($recList.Count -eq 0) { $recList += "-> Service1  Speed Optimization  (routine maintenance)" }
foreach ($r in $recList) { Log "  $r" "Cyan" }
Log ""
Log "  Report : $LogFile" "Gray"
Log "  Snapshot: $SnapFile" "Gray"
Log $bar55 "Green"

# ─── Before/After Comparison ────────────────────────────────
Write-Host ""
$prevSnaps = Get-ChildItem "$PSScriptRoot\diagnostic_${PCName}_*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne (Split-Path $SnapFile -Leaf) } |
    Sort-Object LastWriteTime -Descending

if ($prevSnaps.Count -gt 0) {
    $latest = $prevSnaps[0]
    $doComp = Read-Host "Previous diagnostic found ($($latest.Name)). Compare before/after? (Y/N)"
    if ($doComp -eq "Y" -or $doComp -eq "y") {

        $before = Get-Content $latest.FullName -Raw | ConvertFrom-Json
        $after  = $snap

        $compFile = "$PSScriptRoot\comparison_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $compLines = @()
        $compLines += "====================================================="
        $compLines += "   BEFORE / AFTER COMPARISON"
        $compLines += "   Before: $($before.Timestamp)"
        $compLines += "   After : $($after.Timestamp)"
        $compLines += "====================================================="
        $compLines += ""

        Write-Host ""
        Write-Host ("=" * 55) -ForegroundColor Magenta
        Write-Host "   BEFORE / AFTER COMPARISON" -ForegroundColor Magenta
        Write-Host "   Before: $($before.Timestamp)" -ForegroundColor Gray
        Write-Host "   After : $($after.Timestamp)" -ForegroundColor Gray
        Write-Host ("=" * 55) -ForegroundColor Magenta
        Write-Host ""

        function CompareVal {
            param([string]$label, $bVal, $aVal, [string]$unit = "", [bool]$lowerIsBetter = $true)
            $bStr = if ($null -ne $bVal) { "$bVal$unit" } else { "N/A" }
            $aStr = if ($null -ne $aVal) { "$aVal$unit" } else { "N/A" }
            $line = "  {0,-28} {1,8}  ->  {2,-8}" -f $label, $bStr, $aStr
            $script:compLines += $line

            if ($null -eq $bVal -or $null -eq $aVal) {
                Write-Host $line -ForegroundColor Gray
                return
            }
            try {
                $bNum = [double]$bVal ; $aNUm = [double]$aVal
                if ($lowerIsBetter) {
                    if ($aNUm -lt $bNum)     { Write-Host $line -ForegroundColor Green }
                    elseif ($aNUm -gt $bNum) { Write-Host $line -ForegroundColor Red }
                    else                     { Write-Host $line -ForegroundColor Gray }
                } else {
                    if ($aNUm -gt $bNum)     { Write-Host $line -ForegroundColor Green }
                    elseif ($aNUm -lt $bNum) { Write-Host $line -ForegroundColor Red }
                    else                     { Write-Host $line -ForegroundColor Gray }
                }
            } catch { Write-Host $line -ForegroundColor Gray }
        }

        function CompareBool {
            param([string]$label, $bVal, $aVal, [bool]$trueIsBetter = $true)
            $bStr = if ($bVal) { "ON" } else { "OFF" }
            $aStr = if ($aVal) { "ON" } else { "OFF" }
            $line = "  {0,-28} {1,8}  ->  {2,-8}" -f $label, $bStr, $aStr
            $script:compLines += $line
            $improved = if ($trueIsBetter) { $aVal -and -not $bVal } else { -not $aVal -and $bVal }
            $worsened = if ($trueIsBetter) { -not $aVal -and $bVal } else { $aVal -and -not $bVal }
            if ($improved)    { Write-Host $line -ForegroundColor Green }
            elseif ($worsened){ Write-Host $line -ForegroundColor Red }
            else              { Write-Host $line -ForegroundColor Gray }
        }

        Write-Host ("  {0,-28} {1,8}     {2,-8}" -f "Item", "Before", "After") -ForegroundColor Yellow
        Write-Host ("  " + "-" * 50) -ForegroundColor Yellow
        $compLines += ("  {0,-28} {1,8}     {2,-8}" -f "Item", "Before", "After")
        $compLines += ("  " + "-" * 50)

        CompareVal "RAM Used %"          $before.RAMusedPct    $after.RAMusedPct    "%" $true
        CompareVal "CPU Load %"          $before.CPUloadPct    $after.CPUloadPct    "%" $true
        CompareVal "CPU Temp (C)"        $before.CPUtempC      $after.CPUtempC      "C" $true
        CompareVal "Startup Programs"    $before.StartupCount  $after.StartupCount  ""  $true
        CompareVal "Running Services"    $before.RunningServices $after.RunningServices "" $true
        CompareVal "Event Errors (7d)"   $before.EventErrors   $after.EventErrors   ""  $true
        CompareVal "Event Warnings (7d)" $before.EventWarnings $after.EventWarnings ""  $true
        CompareVal "BSOD Count (7d)"     $before.BSODcount     $after.BSODcount     ""  $true
        CompareVal "Days Since Update"   $before.DaysSinceUpdate $after.DaysSinceUpdate "d" $true
        CompareBool "Defender ON"        $before.DefenderOn    $after.DefenderOn    $true
        CompareBool "Real-time Protect"  $before.RealTimeOn    $after.RealTimeOn    $true
        CompareBool "Firewall ON"        $before.FirewallOn    $after.FirewallOn    $true
        CompareBool "Internet OK"        $before.InternetOK    $after.InternetOK    $true
        CompareVal "Issues Found"        $before.IssueCount    $after.IssueCount    ""  $true

        # Disk free space per drive
        if ($before.Disks -and $after.Disks) {
            foreach ($aDisk in $after.Disks) {
                $bDisk = $before.Disks | Where-Object { $_.Drive -eq $aDisk.Drive } | Select-Object -First 1
                if ($bDisk) {
                    CompareVal "Disk $($aDisk.Drive) Free GB" $bDisk.FreeGB $aDisk.FreeGB "GB" $false
                }
            }
        }

        $compLines += ""
        $compLines += "  Green = Improved    Red = Worsened    Gray = No change"
        $compLines += "====================================================="
        $compLines | Out-File -FilePath $compFile -Encoding UTF8

        Write-Host ""
        Write-Host "  Green = Improved    Red = Worsened    Gray = No change" -ForegroundColor DarkGray
        Write-Host ("=" * 55) -ForegroundColor Magenta
        Write-Host "  Comparison saved: $compFile" -ForegroundColor Green
    }
} else {
    Write-Host "  (No previous diagnostic found - run again after service to compare)" -ForegroundColor DarkGray
}

Write-Host ""
Read-Host "Press Enter to close"
