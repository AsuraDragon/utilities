$dryRun = $false  # Set to $false to perform actual moves
$logFile = "move_log.txt"
Clear-Content -Path $logFile -ErrorAction SilentlyContinue

Get-ChildItem -Path . -Filter "*.mp4" | ForEach-Object {
    $file = $_
    $baseName = $file.BaseName
    $prefix = $baseName -split "-" | Select-Object -First 1
    $targetFolder = Join-Path -Path $PWD -ChildPath $prefix
    $targetPath = Join-Path -Path $targetFolder -ChildPath $file.Name

    if (-not (Test-Path $targetFolder)) {
        if ($dryRun) {
            Add-Content -Path $logFile -Value "DRY-RUN: Would create folder '$targetFolder'"
        } else {
            New-Item -Path $targetFolder -ItemType Directory | Out-Null
            Add-Content -Path $logFile -Value "Created folder '$targetFolder'"
        }
    }

    if ($dryRun) {
        Add-Content -Path $logFile -Value "DRY-RUN: Would move '$($file.Name)' to '$targetFolder'"
    } else {
        Move-Item -Path $file.FullName -Destination $targetPath
        Add-Content -Path $logFile -Value "Moved '$($file.Name)' to '$targetFolder'"
    }
}

Write-Host "Operation complete. Log saved to '$logFile'."
