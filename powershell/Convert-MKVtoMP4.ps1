# PowerShell script to convert MKV to MP4 using FFmpeg

param (
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

# Check if the input file exists
if (-Not (Test-Path $InputFile)) {
    Write-Error "Input file does not exist: $InputFile"
    exit 1
}

# Get the directory and base name of the input file
$Directory = Split-Path $InputFile
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)

# Construct the output file path with .mp4 extension
$OutputFile = Join-Path $Directory "$BaseName.mp4"

# Run FFmpeg to convert the file
ffmpeg -i "$InputFile" -c:v libx264 -crf 24 -c:a aac "$OutputFile"

Write-Host "Conversion complete: $OutputFile"
