
function Create-App {
    param (
        $headers,
        [xml]$xml
    )

    $appPayload = @{
        "@odata.type" = "#microsoft.graph.win32LobApp"
        displayName = "Dreikom Cloud Phone 2"
        description = "Dreikom Cloud Phone 2"
        publisher = "wwcom"
        fileName = $xml.ApplicationInfo.FileName
        setupFilePath = $xml.ApplicationInfo.SetupFile
        installCommandLine = "powershell.exe -executionpolicy bypass .\install.ps1 wwphone-cti"
        uninstallCommandLine = "powershell.exe -executionpolicy bypass .\install.ps1 wwphone-cti -uninstall"
        isFeatured = $false
        minimumSupportedWindowsRelease = "1607"
        installExperience = @{
            runAsAccount = "system"
            deviceRestartBehavior = "suppress"
        }
        returnCodes = @(
            @{ returnCode = 0; type = "success" },
            @{ returnCode = 3010; type = "softReboot" },
            @{ returnCode = 1641; type = "hardReboot" },
            @{ returnCode = 1618; type = "retry" }
        )
        detectionRules = @(
            @{
                "@odata.type" = "#microsoft.graph.win32LobAppFileSystemDetection"
                path = "C:\Program Files (x86)\CTI"
                fileOrFolderName = "cti.exe"
                detectionType = "exists"
                check32BitOn64System = $false
            }
        )
    }

    Write-Log "Creating app in Intune..."
    try {
        $response = Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
            -Headers $headers -Body ($appPayload | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json"
        Write-Log "App created with ID: $($response.id)"
        return $response.id
    }
    catch {
        Write-Log "Failed to create app: $_"
        exit 4
    }
}
