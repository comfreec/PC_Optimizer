$files = Get-ChildItem $PSScriptRoot -Filter "*.ps1" | Where-Object { $_.Name -notlike "_check*" }
foreach ($f in $files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        Write-Host "OK: $($f.Name)" -ForegroundColor Green
    } else {
        Write-Host "ERRORS in $($f.Name):" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    }
}
