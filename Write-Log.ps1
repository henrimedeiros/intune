
function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp`t$message"
    Write-Host $line
    Add-Content -Path $Script:LogFile -Value $line
}
