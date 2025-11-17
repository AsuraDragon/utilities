$dryRun = $false  # Set to $false to perform actual moves
$recursive = $true  # Set to $true to search all subfolders
$logFile = "move_log.txt"
Clear-Content -Path $logFile -ErrorAction SilentlyContinue

# Define media type categories and their extensions
$mediaTypes = @{
    "Videos"    = @(".mp4", ".avi", ".mkv", ".mov", ".wmv", ".flv", ".webm", ".m4v")
    "Images"    = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg", ".webp", ".tiff", ".ico")
    "Audio"     = @(".mp3", ".wav", ".flac", ".aac", ".ogg", ".wma", ".m4a", ".opus")
    "Documents" = @(".pdf", ".doc", ".docx", ".txt", ".xls", ".xlsx", ".ppt", ".pptx", ".csv")
    "Archives"  = @(".zip", ".rar", ".7z", ".tar", ".gz", ".bz2")
}

# Get all files in the current directory (and subdirectories if recursive is enabled)
$searchParams = @{
    Path = "."
    File = $true
}

if ($recursive) {
    $searchParams.Add("Recurse", $true)
}

Get-ChildItem @searchParams | ForEach-Object {
    $file = $_
    $extension = $file.Extension.ToLower()
    $targetFolder = $null

    # Determine which folder this file belongs to
    foreach ($category in $mediaTypes.Keys) {
        if ($mediaTypes[$category] -contains $extension) {
            $targetFolder = Join-Path -Path $PWD -ChildPath $category
            break
        }
    }

    # Skip if no matching category found
    if (-not $targetFolder) {
        Add-Content -Path $logFile -Value "Skipped '$($file.Name)' - unknown media type"
        return
    }

    # Skip if file is already in the target folder (avoid moving to itself)
    if ($file.DirectoryName -eq $targetFolder) {
        Add-Content -Path $logFile -Value "Skipped '$($file.Name)' - already in target folder"
        return
    }

    $targetPath = Join-Path -Path $targetFolder -ChildPath $file.Name

    # Handle duplicate filenames
    if (Test-Path $targetPath) {
        $counter = 1
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        do {
            $newName = "${nameWithoutExt}_${counter}$extension"
            $targetPath = Join-Path -Path $targetFolder -ChildPath $newName
            $counter++
        } while (Test-Path $targetPath)
        
        if ($dryRun) {
            Add-Content -Path $logFile -Value "DRY-RUN: File exists, would rename to '$newName'"
        }
        else {
            Add-Content -Path $logFile -Value "File exists, renaming to '$newName'"
        }
    }

    # Create folder if it doesn't exist
    if (-not (Test-Path $targetFolder)) {
        if ($dryRun) {
            Add-Content -Path $logFile -Value "DRY-RUN: Would create folder '$targetFolder'"
        }
        else {
            New-Item -Path $targetFolder -ItemType Directory | Out-Null
            Add-Content -Path $logFile -Value "Created folder '$targetFolder'"
        }
    }

    # Move the file
    if ($dryRun) {
        Add-Content -Path $logFile -Value "DRY-RUN: Would move '$($file.Name)' to '$targetFolder'"
    }
    else {
        Move-Item -Path $file.FullName -Destination $targetPath
        Add-Content -Path $logFile -Value "Moved '$($file.Name)' to '$targetFolder'"
    }
}

Write-Host "Operation complete. Log saved to '$logFile'."