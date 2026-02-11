# Define the source folder (Current Directory by default)
$sourceFolder = Get-Location
$destinationFolder = Join-Path -Path $sourceFolder -ChildPath "flagMoved"

# 1. Create the 'flagMoved' directory if it doesn't exist
if (!(Test-Path -Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder | Out-Null
    Write-Host "Created folder: $destinationFolder" -ForegroundColor Cyan
}

# 2. Get all files in the current folder (excluding the output folder itself)
$files = Get-ChildItem -Path $sourceFolder -File

foreach ($file in $files) {
    # Define the output path
    $outputPath = Join-Path -Path $destinationFolder -ChildPath $file.Name

    Write-Host "Processing: $($file.Name)..." -ForegroundColor Yellow

    # 3. Execute ffmpeg
    # -i: Input file
    # -c copy: Stream copy (no re-encoding, very fast)
    # -movflags +faststart: Moves metadata to the front for web streaming
    ffmpeg -i "$($file.FullName)" -c copy -movflags +faststart "$outputPath" -y
}

Write-Host "Done! All files processed to: $destinationFolder" -ForegroundColor Green