
param (
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$IntuneWinPath
)

$Script:LogFile = "C:\Windows\Temp\IntuneWin32Upload.log"

. "$PSScriptRoot\Write-Log.ps1"
. "$PSScriptRoot\auth.ps1"
. "$PSScriptRoot\ExtractWinFile.ps1"
. "$PSScriptRoot\CreateApp.ps1"
. "$PSScriptRoot\UploadApp.ps1"

Write-Log "Starting Intune Win32 app upload process..."

$headers = Authenticate -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$xml = Extract-WinFile -IntuneWinPath $IntuneWinPath
$appId = Create-App -headers $headers -xml $xml
Upload-App -headers $headers -xml $xml -appId $appId -IntuneWinPath $IntuneWinPath