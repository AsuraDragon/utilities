<#
.SYNOPSIS
    Recursively deletes empty folders in a given directory using a bottom-up approach.

.DESCRIPTION
    - Scans the target directory for all folders.
    - Sorts paths by length descending to ensure sub-folders are processed before parents.
    - Deletes folders only if they contain no files and no sub-directories.
    - Default behavior is a Dry Run. Use -Execute to perform the deletion.

.EXAMPLE
    .\Remove-EmptyFolders.ps1 -TargetDirectory "C:\MyFiles"
    (Shows a list of folders that would be deleted)

.EXAMPLE
    .\Remove-EmptyFolders.ps1 -TargetDirectory "C:\MyFiles" -Execute
    (Actually deletes the folders)
#>

param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$TargetDirectory,

    [switch]$Execute
)

Write-Host "Scanning '$TargetDirectory' for empty folders..." -ForegroundColor Cyan

# 1. Get all directories recursively
# 2. Sort Descending by FullName length. 
#    This ensures we process "C:\A\B" before "C:\A". 
#    If "B" is empty and deleted, "A" might become empty and can be caught in the same run.
$AllFolders = Get-ChildItem -Path $TargetDirectory -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending

$Count = 0

foreach ($Folder in $AllFolders) {
    # Check contents (using -Force to see hidden files)
    $Contents = Get-ChildItem -Path $Folder.FullName -Force

    if ($Contents.Count -eq 0) {
        $Count++
        
        if ($Execute) {
            try {
                Remove-Item -Path $Folder.FullName -Force -ErrorAction Stop
                Write-Host "Deleted: $($Folder.FullName)" -ForegroundColor Green
            }
            catch {
                Write-Host "Error deleting $($Folder.FullName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "[DRY RUN] Would delete: $($Folder.FullName)" -ForegroundColor Yellow
        }
    }
}

# --- Summary ---
if (-not $Execute) {
    Write-Host "`n[DRY RUN COMPLETE]" -ForegroundColor Cyan
    if ($Count -eq 0) { Write-Host "No empty folders found." -ForegroundColor DarkGray }
    else { Write-Host "Found $Count empty folders. Use -Execute to delete them." -ForegroundColor White }
}
else {
    Write-Host "`n[OPERATION COMPLETE]" -ForegroundColor Cyan
    Write-Host "Deleted $Count empty folders." -ForegroundColor White
}