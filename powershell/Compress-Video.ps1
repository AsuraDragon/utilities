<#
.SYNOPSIS
Compresses an MP4 video file using ffmpeg.

.DESCRIPTION
This script takes an input MP4 file and compresses it using ffmpeg,
employing the H.264 codec (libx264) with a specified Constant Rate Factor (CRF)
and encoding preset. It saves the output file with a suffix (e.g., "_compressed").
ffmpeg must be installed and accessible via the system PATH.
Uses -LiteralPath for increased robustness with filenames containing special characters.

.PARAMETER InputFilePath
The full path to the input MP4 video file. Provide the path accurately, using quotes
around it during execution if it contains spaces or special characters. (Mandatory)

.PARAMETER OutputSuffix
A string to append to the original filename (before the extension) for the output file.
Defaults to '_compressed'.

.PARAMETER CRF
The Constant Rate Factor (quality level). Lower values mean higher quality and larger files.
Higher values mean lower quality and smaller files. A range of 18-28 is common for H.264.
Defaults to 24.

.PARAMETER Preset
The encoding speed preset. Slower presets provide better compression for the same CRF
but take longer to encode. Options: ultrafast, superfast, veryfast, faster, fast,
medium, slow, slower, veryslow.
Defaults to 'medium'.

.PARAMETER AudioBitrate
The target bitrate for the audio stream (e.g., '128k', '192k').
Defaults to '128k'.

.EXAMPLE
# Simple execution with space in path
.\Compress-Video.ps1 -InputFilePath "C:\My Videos\Holiday Footage.mp4"

.EXAMPLE
# Custom settings and output suffix
.\Compress-Video.ps1 -InputFilePath 'C:\Movies\Action Scene.mp4' -CRF 26 -Preset slow -OutputSuffix "_web_optimized"

.EXAMPLE
# Handling path with single quote
.\Compress-Video.ps1 -InputFilePath "C:\Recordings\Meeting 'Important'.mp4"

.EXAMPLE
# Handling path with literal double quotes (use doubled quotes "" or outer single quotes ') - RENAMING THE FILE IS RECOMMENDED!
.\Compress-Video.ps1 -InputFilePath "C:\Misc\My ""Quoted"" File.mp4"
.\Compress-Video.ps1 -InputFilePath 'C:\Misc\My "Quoted" File.mp4'

.NOTES
Author: AI Assistant
Version: 1.1 (Added -LiteralPath)
LastModified: 2025-05-02
Requires: ffmpeg installed and in system PATH.
Ensure your PowerShell Execution Policy allows running local scripts.
(e.g., Set-ExecutionPolicy RemoteSigned -Scope CurrentUser)
If the filename itself contains literal double quotes ("), renaming is the most reliable solution.
#>
param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the input MP4 file.")]
    [string]$InputFilePath,

    [Parameter(HelpMessage="Suffix for the output filename (before extension).")]
    [string]$OutputSuffix = '_compressed',

    [Parameter(HelpMessage="Constant Rate Factor (18-28 common). Lower=Higher Quality/Size.")]
    [ValidateRange(17, 51)] # ffmpeg's range for libx264 CRF
    [int]$CRF = 24,

    [Parameter(HelpMessage="Encoding speed preset. Slower=Better Compression/Slower Speed.")]
    [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow')]
    [string]$Preset = 'medium',

    [Parameter(HelpMessage="Target audio bitrate (e.g., '128k', '192k').")]
    [string]$AudioBitrate = '128k'
)

# --- 1. Validate Input and Environment ---

# Check if input file exists using LiteralPath
# Use -PathType Leaf to ensure it's a file, not a directory
if (-not (Test-Path -LiteralPath $InputFilePath -PathType Leaf -ErrorAction SilentlyContinue)) {
    Write-Error "Input file not found or is not a file (checked literal path): '$InputFilePath'"
    # Add a check to see if maybe it exists but isn't a file (is a directory)
    if (Test-Path -LiteralPath $InputFilePath -PathType Container -ErrorAction SilentlyContinue) {
         Write-Error "'$InputFilePath' exists but is a directory, not a file."
    }
    return # Stop script execution
}

# Check if ffmpeg command is available
try {
    Get-Command ffmpeg -ErrorAction Stop | Out-Null
    Write-Verbose "ffmpeg command found in PATH."
}
catch {
    Write-Error "ffmpeg command not found in PATH. Please install ffmpeg and ensure it's added to your system's PATH environment variable."
    return # Stop script execution
}

# --- 2. Determine Output File Path ---
# Use LiteralPath for Get-Item as well, wrapped in Try/Catch for other potential errors
try {
    $inputFileObject = Get-Item -LiteralPath $InputFilePath -ErrorAction Stop
}
catch {
    # This might catch permissions issues or other problems Get-Item might have
    Write-Error "Could not get file information for input '$InputFilePath'. Error: $($_.Exception.Message)"
    return
}

# Construct the output path
$outputFileName = "$($inputFileObject.BaseName)$($OutputSuffix)$($inputFileObject.Extension)"
$outputFilePath = Join-Path -Path $inputFileObject.DirectoryName -ChildPath $outputFileName

# Check if output file already exists (optional: add overwrite confirmation)
if (Test-Path -LiteralPath $outputFilePath) {
    Write-Warning "Output file '$outputFilePath' already exists and will be overwritten."
    # Optional: Prompt user before overwriting
    # try {
    #     Read-Host -Prompt "Output file '$outputFilePath' exists. Press ENTER to overwrite or CTRL+C to cancel" | Out-Null
    # } catch {
    #     Write-Host "Operation cancelled by user."
    #     return
    # }
}

# --- 3. Construct and Execute ffmpeg Command ---
Write-Host "Starting video compression..."
Write-Host "Input:      $($inputFileObject.FullName)" # Use FullName for clarity
Write-Host "Output:     $outputFilePath"
Write-Host "Settings:   CRF=$CRF, Preset=$Preset, AudioBitrate=$AudioBitrate"
Write-Host "--------------------------------------------------"

# Define arguments for ffmpeg
# -i: Input file (passing the $InputFilePath variable which holds the potentially complex path)
# -c:v libx264: Use H.264 video codec
# -crf: Set Constant Rate Factor (quality)
# -preset: Set encoding speed/compression preset
# -c:a aac: Use AAC audio codec (common for MP4)
# -b:a: Set audio bitrate
# -movflags +faststart: Optimizes the file structure for web streaming (good practice)
# $outputFilePath: Output file path
$ffmpegArgs = @(
    '-i', $InputFilePath,        # Pass the original input path string
    '-c:v', 'libx264',
    '-crf', $CRF.ToString(),
    '-preset', $Preset,
    '-c:a', 'aac',
    '-b:a', $AudioBitrate,
    '-movflags', '+faststart',
    $outputFilePath             # Output path should be safe as we constructed it
)

# Execute ffmpeg. The '&' call operator runs the command and waits for it to complete.
# Standard output and error from ffmpeg will be displayed in the console.
try {
    # Using the call operator '&' is usually sufficient.
    # If extremely complex arguments cause issues, Start-Process might offer more control,
    # but '&' handles quoting for external args reasonably well in most cases.
    & ffmpeg $ffmpegArgs

    # Check the exit code of the last external command ($LASTEXITCODE)
    if ($LASTEXITCODE -eq 0) {
        Write-Host "--------------------------------------------------"
        Write-Host "Compression completed successfully!" -ForegroundColor Green
        Write-Host "Output saved to: $outputFilePath"
    } else {
        # Provide more context in the error message
        Write-Error "ffmpeg process failed with exit code $LASTEXITCODE. Command attempted: ffmpeg $($ffmpegArgs -join ' '). Check the output above for specific ffmpeg error messages."
    }
}
catch {
    # Catch errors related to PowerShell execution itself (e.g., if '&' fails unexpectedly)
    Write-Error "A PowerShell error occurred while trying to run ffmpeg: $($_.Exception.Message)"
}

Write-Host "Script finished."