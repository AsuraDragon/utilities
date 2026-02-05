<#
.SYNOPSIS
    Organizes files recursively into folders based on the first word segment 
    before an internal underscore.

.DESCRIPTION
    - Scans the target directory recursively for files (ignoring folder structures).
    - Parses filenames to determine the destination folder.
      Logic: Captures leading underscores + text up to the first separator underscore.
    - Flattens the file structure into the organized folders in the root of TargetDirectory.
    - Default behavior is a Dry Run (Tree View). Use -Execute to perform the move.

.EXAMPLE
    .\Organize-Files.ps1 -TargetDirectory "C:\MyDocs\Downloads"
    (Shows a tree view of what would happen)

.EXAMPLE
    .\Organize-Files.ps1 -TargetDirectory "C:\MyDocs\Downloads" -Execute
    (Actually moves the files)
#>

param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$TargetDirectory,

    [switch]$Execute
)

# Regex Explanation:
# ^          : Start of string
# (          : Start Capture Group
#   _* : Match zero or more underscores (leading underscores)
#   [^_]+    : Match one or more characters that are NOT underscores
# )          : End Capture Group (This becomes the Folder Name)
# (?=_)      : Positive Lookahead - ensure the next character is an underscore, but don't capture it.
$Pattern = "^(_*[^_]+)(?=_)"

# Get all files recursively
Write-Host "Scanning '$TargetDirectory' for files..." -ForegroundColor Cyan
$AllFiles = Get-ChildItem -Path $TargetDirectory -Recurse -File

# Initialize a hashtable to store the plan (Key = FolderName, Value = List of Files)
$OrganizationPlan = @{}
$SkippedFiles = @()

foreach ($File in $AllFiles) {
    # Skip this script if it happens to be inside the folder
    if ($File.FullName -eq $PSCommandPath) { continue }

    if ($File.Name -match $Pattern) {
        $FolderName = $matches[1]
        
        # Initialize list if key doesn't exist
        if (-not $OrganizationPlan.ContainsKey($FolderName)) {
            $OrganizationPlan[$FolderName] = @()
        }
        
        # Add file to the list for that folder
        $OrganizationPlan[$FolderName] += $File
    }
    else {
        $SkippedFiles += $File.Name
    }
}

# --- Execution / Display Logic ---

if (-not $Execute) {
    Write-Host "`n[DRY RUN MODE] - No files will be moved." -ForegroundColor Yellow
    Write-Host "Use -Execute to perform the operation.`n" -ForegroundColor Gray
    
    if ($OrganizationPlan.Count -eq 0) {
        Write-Host "No files matched the naming pattern." -ForegroundColor DarkGray
    }
    else {
        # Sort keys for pretty tree display
        $SortedFolders = $OrganizationPlan.Keys | Sort-Object

        foreach ($Folder in $SortedFolders) {
            Write-Host "$Folder/" -ForegroundColor Green
            foreach ($File in $OrganizationPlan[$Folder]) {
                Write-Host "  |-- $($File.Name)" -ForegroundColor White
            }
        }
    }

    if ($SkippedFiles.Count -gt 0) {
        Write-Host "`nIgnored Files (No internal underscore pattern found):" -ForegroundColor DarkGray
        foreach ($Skip in $SkippedFiles) { Write-Host "  [x] $Skip" -ForegroundColor DarkGray }
    }
}
else {
    Write-Host "`n[EXECUTING] - Moving files..." -ForegroundColor Magenta
    
    foreach ($Folder in $OrganizationPlan.Keys) {
        $DestPath = Join-Path -Path $TargetDirectory -ChildPath $Folder
        
        # Create Directory if it doesn't exist
        if (-not (Test-Path -Path $DestPath)) {
            New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
            Write-Host "Created Folder: $Folder" -ForegroundColor Green
        }

        # Move Files
        foreach ($File in $OrganizationPlan[$Folder]) {
            $DestFile = Join-Path -Path $DestPath -ChildPath $File.Name
            
            # Prevent moving a file onto itself if it's already in the right spot
            if ($File.FullName -ne $DestFile) {
                try {
                    Move-Item -Path $File.FullName -Destination $DestPath -ErrorAction Stop
                    Write-Host "  Moved: $($File.Name)"
                }
                catch {
                    Write-Host "  ERROR moving $($File.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
    Write-Host "`nOperation Complete." -ForegroundColor Cyan
}