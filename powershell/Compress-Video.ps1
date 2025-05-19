<#
.SYNOPSIS
Compresses video files using ffmpeg.  Handles both single files and directories.

.DESCRIPTION
This script takes an input video file or a directory path and compresses the video(s)
using ffmpeg.  It employs the H.264 codec (libx264) with a specified Constant Rate Factor (CRF)
and encoding preset.  It saves the output file(s) with a suffix (e.g., "_compressed").
If a "compressedVideos" folder exists in the same directory as the input video(s),
the compressed video(s) will be saved there. If the folder does not exist, it will be created.
If a directory is provided as input, the script will process all supported video files in the
*first level* of that directory.  It does *not* recurse into subdirectories.
ffmpeg must be installed and accessible via the system PATH.
Uses -LiteralPath for increased robustness with filenames containing special characters.

.PARAMETER InputFilePath
The full path to the input video file or a directory containing video files.
Provide the path accurately, using quotes around it during execution if it
contains spaces or special characters. (Mandatory)

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
# Simple execution with space in path (file)
.\Compress-Video.ps1 -InputFilePath "C:\My Videos\Holiday Footage.mp4"

.EXAMPLE
# Simple execution with space in path (directory)
.\Compress-Video.ps1 -InputFilePath "C:\My Videos\"

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
Version: 1.4 (Added support for multiple video file extensions)
LastModified: 2025-05-02
Requires: ffmpeg installed and in system PATH.
Ensure your PowerShell Execution Policy allows running local scripts.
(e.g., Set-ExecutionPolicy RemoteSigned -Scope CurrentUser)
If the filename itself contains literal double quotes ("), renaming is the most reliable solution.
#>
param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the input video file or directory containing video files.")]
    [string]$InputFilePath,

    [Parameter(HelpMessage="Suffix for the output filename (before extension).")]
    [string]$OutputSuffix = '_compressed',

    [Parameter(HelpMessage="Constant Rate Factor (18-28 common). Lower=Higher Quality/Size.")]
    [ValidateRange(17, 51)] # ffmpeg's range for libx264 CRF
    [int]$CRF = 18,

    [Parameter(HelpMessage="Encoding speed preset. Slower=Better Compression/Slower Speed.")]
    [ValidateSet('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow')]
    [string]$Preset = 'slower',

    [Parameter(HelpMessage="Target audio bitrate (e.g., '128k', '192k').")]
    [string]$AudioBitrate = '128k'
)

# --- 1. Validate Input and Environment ---

# Check if input path exists using LiteralPath
if (-not (Test-Path -LiteralPath $InputFilePath -ErrorAction SilentlyContinue)) {
    Write-Error "Input path not found (checked literal path): '$InputFilePath'"
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

# --- 2. Process Input Path ---
$inputFileList = @()  # Initialize an empty array to store files to process

# Define supported video file extensions
$supportedExtensions = @('.mp4', '.mkv', '.mov', '.avi', '.wmv', '.flv') # Add more if needed

# Determine if the input path is a file or a directory
if ((Get-Item -LiteralPath $InputFilePath).PSIsContainer) {
    # Input is a directory.  Get all supported video files in the *first level* only.
    Write-Verbose "Input path is a directory: '$InputFilePath'"
    try {
        # Use a loop to check for each supported extension
        foreach ($extension in $supportedExtensions) {
            $inputFileList += Get-ChildItem -LiteralPath $InputFilePath -Filter "*$extension" -File -ErrorAction SilentlyContinue
        }
        if ($inputFileList.Count -eq 0) {
            Write-Warning "No supported video files found in directory: '$InputFilePath'"
            return # Stop if no supported files found
        }
    }
    catch {
        Write-Error "Error getting video files from directory '$InputFilePath': $($_.Exception.Message)"
        return
    }
} else {
    # Input is a single file.
    Write-Verbose "Input path is a file: '$InputFilePath'"
    $inputFile = Get-Item -LiteralPath $InputFilePath
    # Check if the file extension is supported
    if ($supportedExtensions -contains $inputFile.Extension.ToLower()) {
        $inputFileList += $inputFile # Add the file to the array
    }
    else{
        Write-Warning "The input file '$InputFilePath' is not a supported video file type. Supported types are: $($supportedExtensions -join ', ')"
        return
    }
}

# --- 3. Process Each Input File ---
foreach ($inputFileObject in $inputFileList) {
    # Construct the output directory
    $outputDir = Join-Path -Path $inputFileObject.DirectoryName -ChildPath "compressedVideos"

    # Check if the directory exists, and create it if it doesn't
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created directory: '$outputDir'"
        }
        catch {
            Write-Error "Failed to create output directory '$outputDir'. Error: $($_.Exception.Message)"
            return # Stop script execution.  Crucial:  Don't proceed if we can't create the dir.
        }
    }

    # Construct the output file path
    $outputFileName = "$($inputFileObject.BaseName)$($OutputSuffix)$($inputFileObject.Extension)"
    $outputFilePath = Join-Path -Path $outputDir -ChildPath $outputFileName

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

    # --- 4. Construct and Execute ffmpeg Command ---
    Write-Host "Starting video compression..."
    Write-Host "Input:      $($inputFileObject.FullName)"
    Write-Host "Output:     $outputFilePath"
    Write-Host "Settings:   CRF=$CRF, Preset=$Preset, AudioBitrate=$AudioBitrate"
    Write-Host "--------------------------------------------------"

    # Define arguments for ffmpeg
    $ffmpegArgs = @(
        '-i', $inputFileObject.FullName,
        '-c:v', 'libx264',
        '-crf', $CRF.ToString(),
        '-preset', $Preset,
        '-c:a', 'aac',
        '-b:a', $AudioBitrate,
        '-movflags', '+faststart',
        $outputFilePath
    )

    # Execute ffmpeg
    try {
        & ffmpeg $ffmpegArgs

        # Check the exit code
        if ($LASTEXITCODE -eq 0) {
            Write-Host "--------------------------------------------------"
            Write-Host "Compression completed successfully!" -ForegroundColor Green
            Write-Host "Output saved to: $outputFilePath"
        } else {
            Write-Error "ffmpeg process failed with exit code $LASTEXITCODE. Command attempted: ffmpeg $($ffmpegArgs -join ' '). Check the output above for specific ffmpeg error messages."
        }
    }
    catch {
        Write-Error "A PowerShell error occurred while trying to run ffmpeg: $($_.Exception.Message)"
    }
} # End foreach loop

Write-Host "Script finished."
