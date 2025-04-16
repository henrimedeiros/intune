function Upload-App {
    param (
        $headers,
        [xml]$xml,
        [string]$appId,
        [string]$IntuneWinPath
    )

    $contentUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions"
    $content = Invoke-RestMethod -Method POST -Uri $contentUri -Headers $headers -Body '{}' -ContentType "application/json"
    $contentId = $content.id
    Write-Log "Content version created: $contentId"

    $fileName = [System.IO.Path]::GetFileName($IntuneWinPath)
    [int64]$size = $xml.ApplicationInfo.UnencryptedContentSize
    [int64]$encryptedSize = (Get-Item $IntuneWinPath).Length
    $filePayload = @{
        "@odata.type" = "#microsoft.graph.mobileAppContentFile"
        name          = $fileName
        size          = $size
        sizeEncrypted = $encryptedSize
        isDependency  = $false
        manifest      = $null
    }
    $fileUri = "$contentUri/$contentId/files"
    try {
        $fileResponse = Invoke-RestMethod -Method POST -Uri $fileUri -Headers $headers -Body ($filePayload | ConvertTo-Json -Compress) -ContentType "application/json"
        $fileId = $fileResponse.id
        Write-Log "File registered: $fileId"
    }
    catch {
        Write-Log "File registration failed: $_"
        exit 5
    }

    Write-Log "Waiting for Azure Blob upload URL..."
    $uploadUrl = $null
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 3
        $fileStatus = Invoke-RestMethod -Method GET -Uri "$fileUri/$fileId" -Headers $headers
        if ($fileStatus.uploadState -eq "azureStorageUriRequestSuccess") {
            $uploadUrl = $fileStatus.azureStorageUri
            break
        }
    }
    if (-not $uploadUrl) {
        Write-Log "Upload URL not received."
        exit 6
    }

    Write-Log "Uploading .intunewin file..."
    try {
        Invoke-RestMethod -Uri $uploadUrl -Method PUT -InFile $IntuneWinPath -Headers @{ "x-ms-blob-type" = "BlockBlob" }
        Write-Log "File uploaded."
    }
    catch {
        Write-Log "Upload failed: $_"
        exit 7
    }

    $commitUri = "$fileUri/$fileId/commit"
    $fileEncryptionInfo = @{
        encryptionKey          = $xml.ApplicationInfo.EncryptionInfo.EncryptionKey
        macKey                 = $xml.ApplicationInfo.EncryptionInfo.MacKey
        initializationVector   = $xml.ApplicationInfo.EncryptionInfo.InitializationVector
        mac                    = $xml.ApplicationInfo.EncryptionInfo.Mac
        profileIdentifier      = $xml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
        fileDigest             = $xml.ApplicationInfo.EncryptionInfo.FileDigest
        fileDigestAlgorithm    = $xml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
    }
    $commitPayload = @{ fileEncryptionInfo = $fileEncryptionInfo }

    Write-Log "Sending commit payload..."
    Write-Log ($commitPayload | ConvertTo-Json -Depth 10)

    try {
        Invoke-RestMethod -Method POST -Uri $commitUri -Headers $headers -Body ($commitPayload | ConvertTo-Json -Depth 10) -ContentType "application/json"
        Write-Log "File committed."
    }
    catch {
        Write-Log "Failed to commit file: $_"
        if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd()
            Write-Log "API error details: $responseBody"
        }
        exit 8
    }

    $finalizeUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId"
    $finalizeBody = @{
        "@odata.type" = "#microsoft.graph.win32LobApp"
        committedContentVersion = $contentId
    }

    $maxWaitTime = 300
    $pollInterval = 10
    $elapsed = 0
    $retryCommitCount = 0
    $maxCommitRetries = 3

    while ($true) {
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
        $fileStatus = Invoke-RestMethod -Method GET -Uri "$fileUri/$fileId" -Headers $headers
        if ($fileStatus.uploadState -eq "commitFileSuccess") {
            Write-Log "Upload state is 'commitFileSuccess'. Proceeding to finalize the app."
            break
        } elseif ($fileStatus.uploadState -eq "commitFileFailed") {
            if ($retryCommitCount -lt $maxCommitRetries) {
                Write-Log "Upload state is 'commitFileFailed'. Retrying commit ($retryCommitCount/$maxCommitRetries)"
                $retryCommitCount++
                Start-Sleep -Seconds 10
                continue
            } else {
                Write-Log "Upload state is 'commitFileFailed'. Aborting."
                exit 9
            }
        } else {
            Write-Log "Upload state is '$($fileStatus.uploadState)'. Waiting... ($elapsed/$maxWaitTime seconds)"
        }

        if ($elapsed -ge $maxWaitTime) {
            Write-Log "Timeout reached while waiting for commitFileSuccess. Aborting."
            exit 9
        }
    }

    $retryCount = 0
    $maxRetries = 3
    $success = $false

    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
            Write-Log "Attempt $[retryCount]: Sending PATCH request to finalize app..."
            Invoke-RestMethod -Method PATCH -Uri $finalizeUri -Headers $headers -Body ($finalizeBody | ConvertTo-Json -Compress) -ContentType "application/json"
            Write-Log "App successfully finalized and published to Intune."
            $success = $true
        }
        catch {
            Write-Log "Failed to finalize app: $_"
            if ($_.Exception.Response -and $_.Exception.Response.GetResponseStream()) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $responseBody = $reader.ReadToEnd()
                Write-Log "API error details: $responseBody"
            }
            Start-Sleep -Seconds 10
            $retryCount++
        }
    }

    if (-not $success) {
        Write-Log "Exceeded maximum retries. App could not be finalized."
        exit 9
    }
}
