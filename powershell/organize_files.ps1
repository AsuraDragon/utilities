<#
.SYNOPSIS
    Organizes files based on naming conventions. 
    Refactored for maximum compatibility (ASCII only) to prevent console crashes.
#>
[CmdletBinding()]
param (
    [switch]$ShowFoldersOnly,
    [switch]$Execute
)

# 0. CONFIGURATION & SAFETY
# Force the console to use UTF-8, just in case, but we will use ASCII visuals to be safe.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # If this fails, we ignore it and rely on the ASCII characters below.
}

# ==========================================
# 1. CORE LOGIC (STRATEGY)
# ==========================================

function Get-TargetFolder {
    param ([string]$FileName)

    $keywordPattern = "^(.+?)(_post_|_feed_|_story_|_reel_|_stories_|_highlights_)"

    if ($FileName -match $keywordPattern) { return $matches[1] }
    if ($FileName -match "_") { return "Uncategorized\splitted" }
    return "Uncategorized\toBeReviewed"
}

function Get-ExecutionPlan {
    param ([string]$Path)
    $files = Get-ChildItem -Path $Path -File
    $plan = @{}

    foreach ($file in $files) {
        if ($file.Name -eq $MyInvocation.MyCommand.Name) { continue }
        $target = Get-TargetFolder -FileName $file.Name
        if (-not $plan.ContainsKey($target)) {
            $plan[$target] = [System.Collections.ArrayList]::new()
        }
        [void]$plan[$target].Add($file)
    }
    return $plan
}

# ==========================================
# 2. VISUALIZATION (UI)
# ==========================================

function Show-TreePreview {
    param ($Plan)
    
    Write-Host "`n--- PREVIEW MODE: TREE VIEW (Default) ---" -ForegroundColor Cyan
    Write-Host "No files are being moved. Use -Execute to proceed.`n" -ForegroundColor Gray

    if ($Plan.Count -eq 0) { Write-Host "No files found to organize." -ForegroundColor Yellow; return }

    foreach ($folder in $Plan.Keys) {
        # Using [DIR] instead of emoji to prevent crash
        Write-Host "[DIR] $folder" -ForegroundColor Yellow
        $fileList = $Plan[$folder]
        $count = 0
        
        foreach ($file in $fileList) {
            $count++
            # Using standard pipes and dashes instead of Box Drawing characters
            $prefix = if ($count -eq $fileList.Count) { "   +--" } else { "   |--" }
            Write-Host "$prefix $($file.Name)" -ForegroundColor White
        }
    }
}

function Show-FolderPreview {
    param ($Plan)
    Write-Host "`n--- PREVIEW MODE: FOLDER LIST ---" -ForegroundColor Cyan
    if ($Plan.Count -eq 0) { Write-Host "No files found." -ForegroundColor Yellow; return }

    foreach ($folder in $Plan.Keys) {
        Write-Host "[DIR] $folder" -ForegroundColor Yellow
    }
}

# ==========================================
# 3. EXECUTION (INFRASTRUCTURE)
# ==========================================

function Invoke-FileMove {
    param ($Plan, $RootPath)
    Write-Host "Starting execution..." -ForegroundColor Cyan

    foreach ($folder in $Plan.Keys) {
        $destinationPath = Join-Path -Path $RootPath -ChildPath $folder
        if (-not (Test-Path -Path $destinationPath)) {
            New-Item -ItemType Directory -Path $destinationPath | Out-Null
            Write-Host "Created: $folder" -ForegroundColor Green
        }
        foreach ($file in $Plan[$folder]) {
            Move-Item -Path $file.FullName -Destination $destinationPath -Force
            Write-Host "Moved: $($file.Name)"
        }
    }
    Write-Host "Done." -ForegroundColor Cyan
}

# ==========================================
# MAIN CONTROLLER
# ==========================================

$currentPath = Get-Location
$plan = Get-ExecutionPlan -Path $currentPath

if ($Execute) {
    Invoke-FileMove -Plan $plan -RootPath $currentPath
}
elseif ($ShowFoldersOnly) {
    Show-FolderPreview -Plan $plan
}
else {
    Show-TreePreview -Plan $plan
}