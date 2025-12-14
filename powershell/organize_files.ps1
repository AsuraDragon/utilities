<#
.SYNOPSIS
    Organizes files based on keywords and grouping patterns.
    - Default behavior: Tree View Preview (Safe Mode).
    - Use -Execute to actually move files.
#>
[CmdletBinding()]
param (
    [switch]$ShowFoldersOnly,
    [switch]$Execute
)

# 0. SAFETY: Force UTF-8 but use ASCII visuals to prevent crashes
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ==========================================
# 1. CORE LOGIC (STRATEGY)
# ==========================================

function Get-Prefix {
    param ($FileName)
    # Extracts text before the first underscore
    if ($FileName -match "^(.+?)_") { return $matches[1] }
    return $FileName
}

function Build-ExecutionPlan {
    param ([string]$Path)
    
    $files = Get-ChildItem -Path $Path -File
    $plan = @{}
    
    # We need a temporary holding area for files that *might* be grouped
    $splitCandidates = [System.Collections.ArrayList]::new()
    
    $keywordPattern = "^(.+?)(_post_|_feed_|_story_|_reel_|_stories_|_highlights_)"

    # --- PASS 1: Filter Keywords vs Candidates ---
    foreach ($file in $files) {
        if ($file.Name -eq $MyInvocation.MyCommand.Name) { continue }

        # Priority 1: Specific Keywords
        if ($file.Name -match $keywordPattern) {
            $folderName = $matches[1]
            AddTo-Plan -Plan $plan -Folder $folderName -File $file
        }
        # Priority 2: Has Underscore (Add to candidates for Pass 2)
        elseif ($file.Name -match "_") {
            [void]$splitCandidates.Add($file)
        }
        # Priority 3: No Underscore (Review)
        else {
            AddTo-Plan -Plan $plan -Folder "Uncategorized\toBeReviewed" -File $file
        }
    }

    # --- PASS 2: Analyze Candidates for Grouping ---
    # Group the candidates by the part before the first underscore
    $groupedFiles = $splitCandidates | Group-Object -Property { Get-Prefix $_.Name }

    foreach ($group in $groupedFiles) {
        if ($group.Count -ge 2) {
            # If 2 or more files share a prefix, create a specific folder
            # e.g. "Uncategorized\splitted\ProjectA"
            $targetFolder = "Uncategorized\splitted\$($group.Name)"
        }
        else {
            # If unique, just throw in the general bin
            $targetFolder = "Uncategorized\splitted"
        }

        foreach ($file in $group.Group) {
            AddTo-Plan -Plan $plan -Folder $targetFolder -File $file
        }
    }

    return $plan
}

# Helper to keep code clean
function AddTo-Plan {
    param ($Plan, $Folder, $File)
    if (-not $Plan.ContainsKey($Folder)) {
        $Plan[$Folder] = [System.Collections.ArrayList]::new()
    }
    [void]$Plan[$Folder].Add($File)
}

# ==========================================
# 2. VISUALIZATION (UI)
# ==========================================

function Show-TreePreview {
    param ($Plan)
    Write-Host "`n--- PREVIEW MODE: TREE VIEW (Default) ---" -ForegroundColor Cyan
    Write-Host "No files are being moved. Use -Execute to proceed.`n" -ForegroundColor Gray

    if ($Plan.Count -eq 0) { Write-Host "No files found to organize." -ForegroundColor Yellow; return }

    # Sort keys so output is tidy
    $sortedFolders = $Plan.Keys | Sort-Object

    foreach ($folder in $sortedFolders) {
        Write-Host "[DIR] $folder" -ForegroundColor Yellow
        $fileList = $Plan[$folder]
        $count = 0
        
        foreach ($file in $fileList) {
            $count++
            $prefix = if ($count -eq $fileList.Count) { "   +--" } else { "   |--" }
            Write-Host "$prefix $($file.Name)" -ForegroundColor White
        }
    }
}

function Show-FolderPreview {
    param ($Plan)
    Write-Host "`n--- PREVIEW MODE: FOLDER LIST ---" -ForegroundColor Cyan
    if ($Plan.Count -eq 0) { Write-Host "No files found." -ForegroundColor Yellow; return }

    foreach ($folder in $Plan.Keys | Sort-Object) {
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
$plan = Build-ExecutionPlan -Path $currentPath

if ($Execute) {
    Invoke-FileMove -Plan $plan -RootPath $currentPath
}
elseif ($ShowFoldersOnly) {
    Show-FolderPreview -Plan $plan
}
else {
    Show-TreePreview -Plan $plan
}