<#
.SYNOPSIS
Compresses video files using ffmpeg with optional NVIDIA or AMD hardware acceleration.

.DESCRIPTION
This script compresses video files using ffmpeg with support for:
- CPU encoding (default - libx264)
- NVIDIA GPU acceleration (NVENC - h264_nvenc)
- AMD GPU acceleration (AMF - h264_amf)

Hardware acceleration is disabled by default. Use -UseNVIDIA or -UseAMD flags to enable.
The script handles both single files and directories (first level only).
Compressed videos are saved to a "compressedVideos" subfolder.

.PARAMETER InputFilePath
The full path to the input video file or directory containing video files. (Mandatory)

.PARAMETER UseNVIDIA
Switch to enable NVIDIA GPU hardware acceleration using NVENC encoder.
Requires compatible NVIDIA GPU with NVENC support.

.PARAMETER UseAMD
Switch to enable AMD GPU hardware acceleration using AMF encoder.
Requires compatible AMD GPU with AMF support.

.PARAMETER OutputSuffix
String to append to the original filename (before extension) for the output file.
Defaults to '_compressed'.

.PARAMETER CRF
Constant Rate Factor (quality level) for CPU encoding only.
Lower values = higher quality/larger files. Range: 17-51.
Defaults to 18 (high quality). NOT used with GPU encoding.

.PARAMETER QP
Quantization Parameter for GPU encoding (NVIDIA/AMD).
Lower values = higher quality/larger files. Range: 0-51.
Defaults to 23 (balanced quality). NOT used with CPU encoding.

.PARAMETER Preset
Encoding speed preset.
CPU (libx264): ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
NVIDIA (NVENC): p1-p7 or fast, medium, slow (p7/slow = best quality)
AMD (AMF): speed, balanced, quality (quality = best)
Defaults to 'slower' for CPU, 'slow' for NVIDIA, 'quality' for AMD.

.PARAMETER Bitrate
Target video bitrate for GPU encoding (e.g., '5M', '10M').
Optional - uses QP-based encoding if not specified.

.PARAMETER AudioBitrate
Target bitrate for the audio stream (e.g., '128k', '192k').
Defaults to '128k'.

.PARAMETER EnableHWAccelDecode
Switch to enable hardware-accelerated decoding (keeps frames in GPU memory).
Only applicable when using -UseNVIDIA or -UseAMD.
Recommended for best performance with GPU encoding.

.EXAMPLE
# CPU encoding (default, high quality)
.\Compress-Video.ps1 -InputFilePath "C:\Videos\sample.mp4"

.EXAMPLE
# NVIDIA GPU encoding with hardware decode
.\Compress-Video.ps1 -InputFilePath "C:\Videos\sample.mp4" -UseNVIDIA -EnableHWAccelDecode

.EXAMPLE
# AMD GPU encoding with custom QP
.\Compress-Video.ps1 -InputFilePath "C:\Videos\" -UseAMD -QP 20 -EnableHWAccelDecode

.EXAMPLE
# NVIDIA GPU with bitrate control
.\Compress-Video.ps1 -InputFilePath "C:\Videos\sample.mp4" -UseNVIDIA -Bitrate "10M" -Preset medium

.EXAMPLE
# CPU encoding with custom CRF and preset
.\Compress-Video.ps1 -InputFilePath "C:\Videos\sample.mp4" -CRF 20 -Preset medium

.NOTES
Author: AI Assistant (Enhanced)
Version: 2.0 (Added NVIDIA NVENC and AMD AMF hardware acceleration support)
LastModified: 2025-11-17
Requires: 
  - ffmpeg installed and in system PATH
  - For NVIDIA: Compatible GPU with NVENC support (Kepler or newer)
  - For AMD: Compatible GPU with AMF support (GCN or newer)
Execution Policy: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

Hardware Acceleration Notes:
- NVIDIA NVENC: Uses dedicated hardware encoder, significantly faster than CPU
- AMD AMF: Uses GPU encoder, faster than CPU with lower CPU usage
- GPU encoders produce slightly larger files than CPU for same quality
- Hardware decode (-EnableHWAccelDecode) keeps frames in GPU memory for best performance
- QP values for GPU: 0 = lossless (huge files), 18-23 = high quality, 28+ = lower quality
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the input video file or directory.")]
    [string]$InputFilePath,

    [Parameter(HelpMessage = "Enable NVIDIA GPU hardware acceleration (NVENC).")]
    [switch]$UseNVIDIA,

    [Parameter(HelpMessage = "Enable AMD GPU hardware acceleration (AMF).")]
    [switch]$UseAMD,

    [Parameter(HelpMessage = "Suffix for the output filename (before extension).")]
    [string]$OutputSuffix = '_compressed',

    [Parameter(HelpMessage = "Constant Rate Factor for CPU encoding (17-51). Lower=Higher Quality.")]
    [ValidateRange(17, 51)]
    [int]$CRF = 18,

    [Parameter(HelpMessage = "Quantization Parameter for GPU encoding (0-51). Lower=Higher Quality.")]
    [ValidateRange(0, 51)]
    [int]$QP = 23,

    [Parameter(HelpMessage = "Encoding preset. CPU: ultrafast to veryslow. GPU: fast, medium, slow.")]
    [string]$Preset = '',

    [Parameter(HelpMessage = "Target video bitrate for GPU encoding (e.g., '5M', '10M'). Optional.")]
    [string]$Bitrate = '',

    [Parameter(HelpMessage = "Target audio bitrate (e.g., '128k', '192k').")]
    [string]$AudioBitrate = '128k',

    [Parameter(HelpMessage = "Enable hardware-accelerated decoding (GPU only).")]
    [switch]$EnableHWAccelDecode
)

# --- Validation and Setup ---

# Check for conflicting GPU flags
if ($UseNVIDIA -and $UseAMD) {
    Write-Error "Cannot use both -UseNVIDIA and -UseAMD flags simultaneously. Choose one."
    return
}

# Validate input path
if (-not (Test-Path -LiteralPath $InputFilePath -ErrorAction SilentlyContinue)) {
    Write-Error "Input path not found: '$InputFilePath'"
    return
}

# Check if ffmpeg is available
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-Verbose "Found: $ffmpegVersion"
}
catch {
    Write-Error "ffmpeg not found in PATH. Please install ffmpeg and add it to your system PATH."
    return
}

# Determine encoding mode and validate encoder availability
$encodingMode = 'CPU'
$videoCodec = 'libx264'

if ($UseNVIDIA) {
    $encodingMode = 'NVIDIA'
    $videoCodec = 'h264_nvenc'
    
    # Check if NVENC encoder is available
    $encoders = & ffmpeg -encoders 2>&1 | Out-String
    if ($encoders -notmatch 'h264_nvenc') {
        Write-Error "NVIDIA NVENC encoder (h264_nvenc) not found in ffmpeg. Your ffmpeg build may not support NVENC."
        Write-Host "To check available encoders, run: ffmpeg -encoders | findstr nvenc"
        return
    }
    Write-Host "NVIDIA GPU acceleration enabled (NVENC)" -ForegroundColor Green
}
elseif ($UseAMD) {
    $encodingMode = 'AMD'
    $videoCodec = 'h264_amf'
    
    # Check if AMF encoder is available
    $encoders = & ffmpeg -encoders 2>&1 | Out-String
    if ($encoders -notmatch 'h264_amf') {
        Write-Error "AMD AMF encoder (h264_amf) not found in ffmpeg. Your ffmpeg build may not support AMF."
        Write-Host "To check available encoders, run: ffmpeg -encoders | findstr amf"
        return
    }
    Write-Host "AMD GPU acceleration enabled (AMF)" -ForegroundColor Green
}
else {
    Write-Host "CPU encoding enabled (libx264)" -ForegroundColor Cyan
}

# Set default preset based on encoding mode
if ([string]::IsNullOrEmpty($Preset)) {
    if ($encodingMode -eq 'CPU') {
        $Preset = 'slower'
    }
    elseif ($encodingMode -eq 'NVIDIA') {
        $Preset = 'slow'  # NVIDIA preset (p7 equivalent, best quality)
    }
    else {
        $Preset = 'quality'  # AMD preset (best quality)
    }
}

# Validate and map presets for GPU encoding
if ($UseAMD) {
    # AMD AMF only accepts: speed, balanced, quality
    $validAMDPresets = @('speed', 'balanced', 'quality')
    if ($Preset -notin $validAMDPresets) {
        Write-Warning "Preset '$Preset' not valid for AMD AMF. Valid options: speed, balanced, quality"
        Write-Host "Mapping to AMD equivalent..." -ForegroundColor Yellow
        
        # Map common presets to AMD equivalents
        switch -Regex ($Preset) {
            'fast|faster|veryfast|superfast|ultrafast' { $Preset = 'speed' }
            'medium' { $Preset = 'balanced' }
            'slow|slower|veryslow' { $Preset = 'quality' }
            default { $Preset = 'quality' }
        }
        Write-Host "Using AMD preset: $Preset" -ForegroundColor Green
    }
}
elseif ($UseNVIDIA) {
    # NVIDIA NVENC accepts: p1-p7 or fast, medium, slow, plus legacy presets
    $validNVIDIAPresets = @('fast', 'medium', 'slow', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 
        'default', 'hp', 'hq', 'll', 'llhp', 'llhq', 'lossless', 'losslesshp')
    if ($Preset -notin $validNVIDIAPresets) {
        Write-Warning "Preset '$Preset' not optimal for NVIDIA NVENC. Recommended: p1-p7, fast, medium, or slow"
        Write-Host "Mapping to NVIDIA equivalent..." -ForegroundColor Yellow
        
        # Map CPU presets to NVIDIA equivalents
        switch -Regex ($Preset) {
            'ultrafast|superfast|veryfast' { $Preset = 'fast' }
            'faster' { $Preset = 'medium' }
            'slow|slower|veryslow' { $Preset = 'slow' }  # or 'p7' for max quality
            default { $Preset = 'medium' }
        }
        Write-Host "Using NVIDIA preset: $Preset" -ForegroundColor Green
    }
}

# Define supported video file extensions
$supportedExtensions = @('.mp4', '.mkv', '.mov', '.avi', '.wmv', '.flv', '.webm', '.m4v')

# --- Build File List ---
$inputFileList = @()

if ((Get-Item -LiteralPath $InputFilePath).PSIsContainer) {
    Write-Verbose "Processing directory: '$InputFilePath'"
    foreach ($extension in $supportedExtensions) {
        $inputFileList += Get-ChildItem -LiteralPath $InputFilePath -Filter "*$extension" -File -ErrorAction SilentlyContinue
    }
    if ($inputFileList.Count -eq 0) {
        Write-Warning "No supported video files found in: '$InputFilePath'"
        return
    }
}
else {
    Write-Verbose "Processing single file: '$InputFilePath'"
    $inputFile = Get-Item -LiteralPath $InputFilePath
    if ($supportedExtensions -contains $inputFile.Extension.ToLower()) {
        $inputFileList += $inputFile
    }
    else {
        Write-Warning "File type not supported: '$($inputFile.Extension)'. Supported: $($supportedExtensions -join ', ')"
        return
    }
}

# --- Process Each File ---
foreach ($inputFileObject in $inputFileList) {
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "Processing: $($inputFileObject.Name)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow

    # Create output directory
    $outputDir = Join-Path -Path $inputFileObject.DirectoryName -ChildPath "compressedVideos"
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $outputDir -Force -ErrorAction Stop | Out-Null
            Write-Verbose "Created directory: '$outputDir'"
        }
        catch {
            Write-Error "Failed to create output directory: $($_.Exception.Message)"
            return
        }
    }

    # Construct output file path
    $outputFileName = "$($inputFileObject.BaseName)$($OutputSuffix)$($inputFileObject.Extension)"
    $outputFilePath = Join-Path -Path $outputDir -ChildPath $outputFileName

    # Check if output exists
    if (Test-Path -LiteralPath $outputFilePath) {
        Write-Warning "Output file exists and will be overwritten: '$outputFileName'"
    }

    # --- Build ffmpeg Arguments ---
    $ffmpegArgs = @()

    # Hardware-accelerated decoding (if enabled for GPU encoding)
    if ($EnableHWAccelDecode) {
        if ($UseNVIDIA) {
            # NVIDIA: Use CUDA hardware acceleration for decoding
            $ffmpegArgs += '-hwaccel', 'cuda'
            $ffmpegArgs += '-hwaccel_output_format', 'cuda'
            Write-Host "Hardware decode: CUDA (NVDEC)" -ForegroundColor Green
        }
        elseif ($UseAMD) {
            # AMD: Use D3D11VA for Windows (most compatible)
            $ffmpegArgs += '-hwaccel', 'd3d11va'
            $ffmpegArgs += '-hwaccel_output_format', 'd3d11'
            Write-Host "Hardware decode: D3D11VA (AMD VCN)" -ForegroundColor Green
        }
        else {
            Write-Warning "Hardware decode only available with -UseNVIDIA or -UseAMD"
        }
    }

    # Input file
    $ffmpegArgs += '-i', $inputFileObject.FullName

    # Video codec and quality settings
    $ffmpegArgs += '-c:v', $videoCodec

    if ($encodingMode -eq 'CPU') {
        # CPU encoding with CRF
        $ffmpegArgs += '-crf', $CRF.ToString()
        $ffmpegArgs += '-preset', $Preset
    }
    else {
        # GPU encoding
        $ffmpegArgs += '-preset', $Preset
        
        if ([string]::IsNullOrEmpty($Bitrate)) {
            # Use QP-based quality control (constant quality)
            if ($UseNVIDIA) {
                $ffmpegArgs += '-rc', 'constqp'
                $ffmpegArgs += '-qp', $QP.ToString()
            }
            elseif ($UseAMD) {
                $ffmpegArgs += '-rc', 'cqp'
                $ffmpegArgs += '-qp_i', $QP.ToString()
                $ffmpegArgs += '-qp_p', $QP.ToString()
            }
        }
        else {
            # Use bitrate control (VBR)
            $ffmpegArgs += '-b:v', $Bitrate
            if ($UseNVIDIA) {
                $ffmpegArgs += '-rc', 'vbr'
            }
            elseif ($UseAMD) {
                $ffmpegArgs += '-rc', 'vbr_peak'
            }
        }
    }

    # Audio settings
    $ffmpegArgs += '-c:a', 'aac'
    $ffmpegArgs += '-b:a', $AudioBitrate

    # MP4 optimization
    $ffmpegArgs += '-movflags', '+faststart'

    # Output file
    $ffmpegArgs += $outputFilePath

    # --- Display Settings ---
    Write-Host "`nSettings:" -ForegroundColor Cyan
    Write-Host "  Encoding Mode:  $encodingMode" -ForegroundColor White
    Write-Host "  Video Codec:    $videoCodec" -ForegroundColor White
    Write-Host "  Preset:         $Preset" -ForegroundColor White
    
    if ($encodingMode -eq 'CPU') {
        Write-Host "  CRF:            $CRF" -ForegroundColor White
    }
    else {
        if ([string]::IsNullOrEmpty($Bitrate)) {
            Write-Host "  QP:             $QP (constant quality)" -ForegroundColor White
        }
        else {
            Write-Host "  Bitrate:        $Bitrate (variable bitrate)" -ForegroundColor White
        }
    }
    
    Write-Host "  Audio Bitrate:  $AudioBitrate" -ForegroundColor White
    Write-Host "  HW Decode:      $(if ($EnableHWAccelDecode) { 'Enabled' } else { 'Disabled' })" -ForegroundColor White
    Write-Host ""

    # --- Execute ffmpeg ---
    Write-Host "Encoding..." -ForegroundColor Yellow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        & ffmpeg $ffmpegArgs

        $stopwatch.Stop()
        $elapsedTime = $stopwatch.Elapsed.ToString("mm\:ss")

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "✓ Success! Completed in $elapsedTime" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "Output: $outputFilePath" -ForegroundColor White
            
            # Show file size comparison
            $inputSize = [math]::Round($inputFileObject.Length / 1MB, 2)
            $outputSize = [math]::Round((Get-Item -LiteralPath $outputFilePath).Length / 1MB, 2)
            $reduction = [math]::Round((1 - ($outputSize / $inputSize)) * 100, 1)
            
            Write-Host "`nFile Size Comparison:" -ForegroundColor Cyan
            Write-Host "  Original:  $inputSize MB" -ForegroundColor White
            Write-Host "  Compressed: $outputSize MB" -ForegroundColor White
            Write-Host "  Reduction:  $reduction%" -ForegroundColor $(if ($reduction -gt 0) { 'Green' } else { 'Yellow' })
        }
        else {
            Write-Error "ffmpeg failed with exit code $LASTEXITCODE"
            Write-Host "Command attempted: ffmpeg $($ffmpegArgs -join ' ')" -ForegroundColor Red
        }
    }
    catch {
        Write-Error "Error executing ffmpeg: $($_.Exception.Message)"
    }
}

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "All files processed!" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow