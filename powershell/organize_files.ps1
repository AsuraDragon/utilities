chcp 65001
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

param (
    [switch]$TestFolders, # Lists only the folders that would be created
    [switch]$TestFiles    # Shows a Tree view of where every file will go
)

# --- Configuration ---
$currentLocation = Get-Location
$files = Get-ChildItem -Path $currentLocation -File
$keywordPattern = "^(.+?)(_post_|_feed_|_story_|_reel_|_stories_|_highlights_)"

# We use a Hash Table (Dictionary) to store the plan in memory before acting
# Key = Folder Name, Value = List of Files
$executionPlan = @{}

# --- Phase 1: Analyze and Build the Plan ---
foreach ($file in $files) {
    # Skip the script file itself
    if ($file.Name -eq $MyInvocation.MyCommand.Name) { continue }

    $targetFolder = $null

    # Logic 1: Check for keywords
    if ($file.Name -match $keywordPattern) {
        $targetFolder = $matches[1]
    }
    # Logic 2: Check for underscore (Split logic)
    elseif ($file.Name -match "_") {
        $targetFolder = "Uncategorized\splitted"
    }
    # Logic 3: Fallback (Review logic)
    else {
        $targetFolder = "Uncategorized\toBeReviewed"
    }

    # Add to the execution plan
    if (-not $executionPlan.ContainsKey($targetFolder)) {
        $executionPlan[$targetFolder] = [System.Collections.ArrayList]::new()
    }
    [void]$executionPlan[$targetFolder].Add($file.Name)
}

# --- Phase 2: Output or Execute ---

# OPTION A: Test Mode - Folders Only
if ($TestFolders) {
    Write-Host "`n--- TEST MODE: PREVIEWING FOLDERS ---" -ForegroundColor Cyan
    Write-Host "The following folders would be created/used:`n"
    
    foreach ($key in $executionPlan.Keys) {
        Write-Host " $key" -ForegroundColor Yellow
    }
    Write-Host "`n(No files were moved)" -ForegroundColor Gray
    exit
}

# OPTION B: Test Mode - Files Tree Structure
if ($TestFiles) {
    Write-Host "`n--- TEST MODE: PREVIEWING FILE TREE ---" -ForegroundColor Cyan
    
    foreach ($folderKey in $executionPlan.Keys) {
        Write-Host "`n $folderKey" -ForegroundColor Yellow
        
        $fileList = $executionPlan[$folderKey]
        $count = 0
        foreach ($fileName in $fileList) {
            $count++
            # Visual logic to make the tree pretty (last item has different corner)
            if ($count -eq $fileList.Count) {
                Write-Host "   └── $fileName" -ForegroundColor White
            }
            else {
                Write-Host "   |── $fileName" -ForegroundColor White
            }
        }
    }
    Write-Host "`n(No files were moved)" -ForegroundColor Gray
    exit
}

# OPTION C: Execution Mode (No switches provided)
Write-Host "Starting file organization..." -ForegroundColor Cyan

foreach ($folderName in $executionPlan.Keys) {
    
    # Define full path
    $destinationPath = Join-Path -Path $currentLocation -ChildPath $folderName

    # Create directory if missing
    if (-not (Test-Path -Path $destinationPath)) {
        New-Item -ItemType Directory -Path $destinationPath | Out-Null
        Write-Host "Created folder: $folderName" -ForegroundColor Green
    }

    # Move the files in the list
    foreach ($fileName in $executionPlan[$folderName]) {
        $sourceFile = Join-Path -Path $currentLocation -ChildPath $fileName
        Move-Item -Path $sourceFile -Destination $destinationPath -Force
        Write-Host "Moved $fileName -> $folderName"
    }
}

Write-Host "Organization complete." -ForegroundColor Cyan