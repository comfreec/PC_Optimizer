# Customer Service Report Generator

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Clear-Host
Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host "   Service Report Generator" -ForegroundColor Cyan
Write-Host ("=" * 55) -ForegroundColor Cyan
Write-Host ""

$techName  = Read-Host "Technician name"
$custName  = Read-Host "Customer name"
$custPhone = Read-Host "Customer phone"

Write-Host ""
Write-Host "Services performed (Y/N):"
$s1 = Read-Host "  Service1 - Speed Optimization (Y/N)"
$s2 = Read-Host "  Service2 - Windows Update (Y/N)"
$s3 = Read-Host "  Service3 - Boot Recovery (Y/N)"
$s4 = Read-Host "  Service4 - Windows Reinstall (Y/N)"
$sv = Read-Host "  Virus Scan (Y/N)"
$dr = Read-Host "  Driver Install (Y/N)"
$rc = Read-Host "  Data Recovery Tools (Y/N)"
$etc = Read-Host "  Other work (Enter to skip)"

# PC info
$pcName  = $env:COMPUTERNAME
$os      = (Get-WmiObject Win32_OperatingSystem).Caption
$cpu     = (Get-WmiObject Win32_Processor).Name
$ramGB   = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)
$model   = (Get-WmiObject Win32_ComputerSystem).Model
$isSSD   = $false
try { if (Get-PhysicalDisk | Where-Object { $_.MediaType -eq "SSD" }) { $isSSD = $true } } catch {}
$diskType = if($isSSD){"SSD"}else{"HDD"}

$disk    = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeGB  = [math]::Round($disk.FreeSpace/1GB,1)
$totalGB = [math]::Round($disk.Size/1GB,1)

$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$safeCustomer = $custName -replace '[\\/:*?"<>|]', '_'
$reportPath = "$PSScriptRoot\report_$($safeCustomer)_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

# Build report
$lines = @()
$lines += "====================================================="
$lines += "   PC Service Report"
$lines += "====================================================="
$lines += ""
$lines += "  Date       : $date"
$lines += "  Technician : $techName"
$lines += "  Customer   : $custName"
$lines += "  Phone      : $custPhone"
$lines += ""
$lines += "-----------------------------------------------------"
$lines += "  PC Info"
$lines += "-----------------------------------------------------"
$lines += "  PC Name    : $pcName"
$lines += "  Model      : $model"
$lines += "  OS         : $os"
$lines += "  CPU        : $cpu"
$lines += "  RAM        : $ramGB GB"
$lines += "  Storage    : $diskType"
$lines += "  Disk       : $freeGB GB free / $totalGB GB total"
$lines += ""
$lines += "-----------------------------------------------------"
$lines += "  Work Performed"
$lines += "-----------------------------------------------------"

if ($s1 -eq "Y" -or $s1 -eq "y") {
    $lines += "  [Done] Service1 - Speed Optimization"
    $lines += "         Startup cleanup, service disable, temp files,"
    $lines += "         visual effects, high-performance power plan"
}
if ($s2 -eq "Y" -or $s2 -eq "y") {
    $lines += "  [Done] Service2 - Windows Update"
    $lines += "         Windows security updates, app updates,"
    $lines += "         system file repair, disk cleanup"
}
if ($s3 -eq "Y" -or $s3 -eq "y") {
    $lines += "  [Done] Service3 - Boot Recovery"
    $lines += "         MBR/BCD repair, system file repair"
}
if ($s4 -eq "Y" -or $s4 -eq "y") {
    $lines += "  [Done] Service4 - Windows Reinstall"
    $lines += "         Data backup, full Windows reinstall,"
    $lines += "         drivers and updates installed"
}
if ($sv -eq "Y" -or $sv -eq "y") {
    $lines += "  [Done] Virus Scan and Removal"
}
if ($dr -eq "Y" -or $dr -eq "y") {
    $lines += "  [Done] Driver Auto Install"
}
if ($rc -eq "Y" -or $rc -eq "y") {
    $lines += "  [Done] Data Recovery Tools Installed"
}
if ($etc -ne "") {
    $lines += "  [Done] Other: $etc"
}

$lines += ""
$lines += "-----------------------------------------------------"
$lines += "  Notes for Customer"
$lines += "-----------------------------------------------------"
$lines += "  * Reboot to fully apply all changes."
$lines += "  * Back up important files regularly to external drive."
$lines += "  * Do not click suspicious email links or attachments."
$lines += "  * Contact us if any issues arise."
$lines += ""
$lines += "====================================================="
$lines += "  Thank you.  - $techName"
$lines += "====================================================="

$report = $lines -join "`r`n"

# Save
$report | Out-File -FilePath $reportPath -Encoding UTF8

# Display
Write-Host ""
Write-Host $report
Write-Host ""
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host "  Report saved: $reportPath" -ForegroundColor Green
Write-Host ("=" * 55) -ForegroundColor Green
Write-Host ""

$print = Read-Host "Open report in Notepad? (Y/N)"
if ($print -eq "Y" -or $print -eq "y") {
    Start-Process notepad.exe -ArgumentList $reportPath
    Start-Sleep -Seconds 2
    Write-Host "Use Ctrl+P to print" -ForegroundColor Yellow
}

Read-Host "Press Enter to close"
