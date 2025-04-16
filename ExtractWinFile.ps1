function Extract-WinFile {
    param ([string]$IntuneWinPath)

    $baseDir = Split-Path -Path $IntuneWinPath -Parent
    $extractPath = Join-Path $baseDir "__extracted"
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    New-Item -ItemType Directory -Path $extractPath | Out-Null

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($IntuneWinPath, $extractPath)
        Write-Log "Extracted .intunewin file."
    }
    catch {
        Write-Log "Failed to extract .intunewin: $_"
        exit 2
    }

    $detectionXmlPath = Get-ChildItem -Path $extractPath -Recurse -Filter "detection.xml" | Select-Object -First 1
    if (-not $detectionXmlPath) {
        Write-Log "detection.xml not found."
        exit 3
    }

    return [xml](Get-Content $detectionXmlPath.FullName)
}
