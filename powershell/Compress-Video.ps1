param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the input video file or directory.")]
    [string]$InputFilePath,

    [Parameter(HelpMessage = "Enable NVIDIA GPU hardware acceleration (NVENC).")]
    [switch]$UseNVIDIA,

    [Parameter(HelpMessage = "Enable AMD GPU hardware acceleration (AMF).")]
    [switch]$UseAMD,

    [Parameter(HelpMessage = "Use all CPU cores minus one for encoding.")]
    [switch]$UseMaxCores,

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
        $Preset = 'slow' 
    }
    else {
        $Preset = 'quality' 
    }
}

# Validate and map presets for GPU encoding
if ($UseAMD) {
    $validAMDPresets = @('speed', 'balanced', 'quality')
    if ($Preset -notin $validAMDPresets) {
        Write-Warning "Preset '$Preset' not valid for AMD AMF. Mapping to AMD equivalent..."
        switch -Regex ($Preset) {
            'fast|faster|veryfast|superfast|ultrafast' { $Preset = 'speed' }
            'medium' { $Preset = 'balanced' }
            'slow|slower|veryslow' { $Preset = 'quality' }
            default { $Preset = 'quality' }
        }
    }
}
elseif ($UseNVIDIA) {
    $validNVIDIAPresets = @('fast', 'medium', 'slow', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 
        'default', 'hp', 'hq', 'll', 'llhp', 'llhq', 'lossless', 'losslesshp')
    if ($Preset -notin $validNVIDIAPresets) {
        Write-Warning "Preset '$Preset' not optimal for NVIDIA NVENC. Mapping to NVIDIA equivalent..."
        switch -Regex ($Preset) {
            'ultrafast|superfast|veryfast' { $Preset = 'fast' }
            'faster' { $Preset = 'medium' }
            'slow|slower|veryslow' { $Preset = 'slow' }
            default { $Preset = 'medium' }
        }
    }
}

# Define supported video file extensions
$supportedExtensions = @('.mp4', '.mkv', '.mov', '.avi', '.wmv', '.flv', '.webm', '.m4v', '.ts', '.m2ts')

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
        }
        catch {
            Write-Error "Failed to create output directory: $($_.Exception.Message)"
            return
        }
    }

    # Construct output file path - FORCE .mp4 EXTENSION
    # This fixes issues where input is FLV/AVI but we are encoding h264 (which prefers mp4)
    $outputFileName = "$($inputFileObject.BaseName)$($OutputSuffix).mp4"
    $outputFilePath = Join-Path -Path $outputDir -ChildPath $outputFileName

    # Check if output exists
    if (Test-Path -LiteralPath $outputFilePath) {
        Write-Warning "Output file exists and will be overwritten: '$outputFileName'"
    }

    # --- Build ffmpeg Arguments ---
    $ffmpegArgs = @()

    # Hardware-accelerated decoding
    if ($EnableHWAccelDecode) {
        if ($UseNVIDIA) {
            $ffmpegArgs += '-hwaccel', 'cuda'
            $ffmpegArgs += '-hwaccel_output_format', 'cuda'
            Write-Host "Hardware decode: CUDA (NVDEC)" -ForegroundColor Green
        }
        elseif ($UseAMD) {
            $ffmpegArgs += '-hwaccel', 'd3d11va'
            $ffmpegArgs += '-hwaccel_output_format', 'd3d11'
            Write-Host "Hardware decode: D3D11VA (AMD VCN)" -ForegroundColor Green
        }
    }

    # Input file
    $ffmpegArgs += '-i', $inputFileObject.FullName

    # Video codec
    $ffmpegArgs += '-c:v', $videoCodec

    if ($encodingMode -eq 'CPU') {
        $ffmpegArgs += '-crf', $CRF.ToString()
        $ffmpegArgs += '-preset', $Preset
        
        # Add thread control for CPU encoding
        if ($UseMaxCores) {
            $cpuCores = (Get-CimInstance -ClassName Win32_Processor | 
                Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
            $threadsToUse = [Math]::Max(1, $cpuCores - 2)
            $ffmpegArgs += '-threads', $threadsToUse.ToString()
            Write-Host "CPU Threads: Using $threadsToUse of $cpuCores available cores" -ForegroundColor Green
        }
    }
    else {
        $ffmpegArgs += '-preset', $Preset
        if ([string]::IsNullOrEmpty($Bitrate)) {
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
            $ffmpegArgs += '-b:v', $Bitrate
            if ($UseNVIDIA) { $ffmpegArgs += '-rc', 'vbr' }
            elseif ($UseAMD) { $ffmpegArgs += '-rc', 'vbr_peak' }
        }
    }

    # Audio settings
    $ffmpegArgs += '-c:a', 'aac'
    $ffmpegArgs += '-b:a', $AudioBitrate

    # --- FIX: Error Handling Args ---
    # Fixes "Packets poorly interleaved" / "Negative timestamp" errors
    # Fixes muxing errors when converting from legacy containers like FLV
    $ffmpegArgs += '-max_interleave_delta', '0'
    
    # MP4 optimization
    $ffmpegArgs += '-movflags', '+faststart'

    # Output file
    $ffmpegArgs += $outputFilePath

    # --- Display Settings ---
    Write-Host "`nSettings:" -ForegroundColor Cyan
    Write-Host "  Encoding Mode:  $encodingMode" -ForegroundColor White
    Write-Host "  Container:      MP4 (Forced for stability)" -ForegroundColor White
    
    # --- Execute ffmpeg ---
    Write-Host "Encoding..." -ForegroundColor Yellow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "Command: $ffmpegArgs"  -ForegroundColor White
    try {
        # Redirect StandardError to capture ffmpeg output cleanly if needed, 
        # but simpler to let it flow to console for progress bar visibility
        & ffmpeg $ffmpegArgs

        $stopwatch.Stop()
        $elapsedTime = $stopwatch.Elapsed.ToString("mm\:ss")

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n========================================" -ForegroundColor Green
            Write-Host "✓ Success! Completed in $elapsedTime" -ForegroundColor Green
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