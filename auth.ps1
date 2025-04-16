
function Authenticate {
    param (
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    Write-Log "Authenticating to Microsoft Graph..."
    $authBody = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    try {
        $authResult = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $authBody
        Write-Log "Authentication successful."
        return @{ Authorization = "Bearer $($authResult.access_token)" }
    }
    catch {
        Write-Log "Authentication failed: $_"
        exit 1
    }
}
