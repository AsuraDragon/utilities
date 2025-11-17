<#
.SYNOPSIS
  Renames files within a specified directory and its subdirectories by replacing certain words in the filenames.
  Defaults to removing "_compressed" from filenames.

.DESCRIPTION
  This script searches for files in a given path. For each file found, it checks if its name contains any of the specified words to be replaced.
  If a match is found, it replaces that word with the new specified word and renames the file.
  By default, it looks for "_compressed" and replaces it with an empty string (effectively deleting it).

.PARAMETER Path
  Specifies the directory path where the files are located. The script will process files in this directory and all its subdirectories.

.PARAMETER WordsToReplace
  An array of strings representing the words to be replaced in the filenames.
  Defaults to "_compressed". This is case-sensitive by default.

.PARAMETER ReplacementWord
  The string that will replace the words specified in -WordsToReplace.
  Defaults to "" (an empty string), which effectively removes the matched word(s).

.PARAMETER Recurse
  A switch parameter that, if present, makes the script search for files in subdirectories as well.

.PARAMETER WhatIf
  A switch parameter that, if present, shows what changes would be made without actually renaming any files.

.PARAMETER Force
  A switch parameter that, if present, allows overwriting files if the new name already exists. Use with caution.

.EXAMPLE
  .\Rename-Files.ps1 -Path "C:\MyDocuments\Images"
  This command will search for files in "C:\MyDocuments\Images" (not subfolders) and rename files by removing "_compressed" from their names.
  It will show what would happen first due to the implicit -WhatIf behavior when no changes are forced.

.EXAMPLE
  .\Rename-Files.ps1 -Path "C:\MyDocuments\Images" -Recurse -WhatIf
  This command will show which files in "C:\MyDocuments\Images" and its subfolders would have "_compressed" removed from their names.

.EXAMPLE
  .\Rename-Files.ps1 -Path "C:\MyDocuments\Downloads" -WordsToReplace "_backup", " (copy)" -ReplacementWord "_archive" -Recurse
  This command will rename files in "C:\MyDocuments\Downloads" and its subfolders, replacing "_backup" or " (copy)" with "_archive".

.EXAMPLE
  .\Rename-Files.ps1 -Path "D:\Work\Reports" -Force
  This command will rename files in "D:\Work\Reports" (not subfolders) by removing "_compressed".
  If a renamed file matches an existing filename, it will be overwritten.

.NOTES
  Author: AI Assistant
  Version: 1.1 (Added defaults for word replacement)
  Consider backing up your files before running this script without the -WhatIf parameter, especially when using -Force.
  The script performs case-sensitive replacements by default. Modify the -replace operator if case-insensitivity is needed (e.g., using -ireplace).
#>
param (
    [Parameter(Mandatory = $true, HelpMessage = "Enter the directory path.")]
    [string]$Path,

    [Parameter(HelpMessage = "Enter the words to replace as a comma-separated list (e.g., 'oldword1','oldword2'). Defaults to '_compressed'.")]
    [string[]]$WordsToReplace = @("_compressed"),

    [Parameter(HelpMessage = "Enter the replacement word. Defaults to an empty string (effectively removing the word).")]
    [string]$ReplacementWord = "",

    [Parameter(HelpMessage = "Process files in subdirectories as well.")]
    [switch]$Recurse,

    [Parameter(HelpMessage = "Show what would happen without actually renaming files. This is implicitly active if no modifying actions like -Force are used without explicit confirmation.")]
    [switch]$WhatIf,

    [Parameter(HelpMessage = "Force overwrite if the new filename already exists. Use with caution.")]
    [switch]$Force
)

# Validate if the path exists
if (-not (Test-Path -Path $Path -PathType Container)) {
    Write-Error "Error: The specified path '$Path' does not exist or is not a directory."
    exit 1
}

Write-Host "Starting file renaming process..."
Write-Host "Target Directory: $Path"
Write-Host "Words to Replace: $($WordsToReplace -join ', ')"
Write-Host "Replacement Word: '$($ReplacementWord)'" # Enclosed in quotes to show if it's empty
Write-Host "Recurse: $($Recurse.IsPresent)"

# Effective WhatIf: If -WhatIf is present, or if -Force is NOT present and the operation is potentially destructive.
# For Rename-Item, -WhatIf is a good safety default unless -Force is specified.
$effectiveWhatIf = $WhatIf.IsPresent
if (-not $Force.IsPresent -and -not $WhatIf.IsPresent) {
    Write-Warning "Running in WhatIf mode by default as -Force was not specified. No actual changes will be made."
    Write-Warning "To apply changes, re-run with the -Force parameter (after reviewing the WhatIf output) or explicitly use -WhatIf:$false if you understand the implications."
    $effectiveWhatIf = $true
}

if ($effectiveWhatIf) {
    Write-Host "Mode: WhatIf (no actual changes will be made)"
}
if ($Force.IsPresent) {
    Write-Warning "Force mode enabled. Files might be overwritten."
}
Write-Host "------------------------------------"

# Get files
$getFilesParams = @{
    Path = $Path
    File = $true # Ensure we only get files
}
if ($Recurse.IsPresent) {
    $getFilesParams.Recurse = $true
}

try {
    $files = Get-ChildItem @getFilesParams -ErrorAction Stop
}
catch {
    Write-Error "Error accessing files in '$Path': $($_.Exception.Message)"
    exit 1
}


if ($files.Count -eq 0) {
    Write-Host "No files found in the specified directory matching the criteria."
    exit 0
}

Write-Host "Found $($files.Count) files to process..."

$filesRenamedCount = 0
$filesSkippedCount = 0

foreach ($file in $files) {
    $originalName = $file.Name
    $originalBaseName = $file.BaseName
    $extension = $file.Extension # Includes the dot (e.g., ".txt")
    $newName = $originalName # Start with the original name
    $nameChangedInLoop = $false

    $currentNameToProcess = $originalBaseName # Process replacements on the basename first

    foreach ($wordToReplace in $WordsToReplace) {
        if ($currentNameToProcess -match [regex]::Escape($wordToReplace)) {
            $currentNameToProcess = ($currentNameToProcess -replace [regex]::Escape($wordToReplace), $ReplacementWord)
            $nameChangedInLoop = $true
        }
    }

    if ($nameChangedInLoop) {
        $newName = $currentNameToProcess + $extension

        # Check for empty filename resulting from replacement (e.g., if filename was just "_compressed.txt")
        if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $extension) {
            Write-Warning "Skipping rename for '$($file.FullName)': Resulting filename would be empty or just an extension after replacing words."
            $filesSkippedCount++
            continue
        }

        $newFilePath = Join-Path -Path $file.DirectoryName -ChildPath $newName

        Write-Host ("Prospective rename: '$($file.FullName)' to '$newFilePath'")

        if (Test-Path $newFilePath -PathType Leaf -ErrorAction SilentlyContinue) {
            if ($newFilePath -eq $file.FullName) {
                # This can happen if the replacement results in the original name (e.g. replacing "A" with "A")
                # Or if WordsToReplace is empty, or the word isn't found. This 'if ($nameChangedInLoop)' should prevent most.
                Write-Verbose "Skipping rename for '$($file.FullName)': New name is identical to the old name."
                continue
            }
            if ($Force.IsPresent) {
                Write-Warning "File '$newFilePath' already exists. Overwriting due to -Force."
            } else {
                Write-Warning "Skipping rename for '$($file.FullName)': New name '$newFilePath' already exists. Use -Force to overwrite or re-run with -WhatIf:$false if you intend this."
                $filesSkippedCount++
                continue # Skip to the next file
            }
        }

        try {
            Rename-Item -Path $file.FullName -NewName $newName -ErrorAction Stop -WhatIf:$effectiveWhatIf -Force:$Force
            if (-not $effectiveWhatIf) {
                Write-Host ("Successfully renamed: '$originalName' to '$newName'") -ForegroundColor Green
                $filesRenamedCount++
            } else {
                 Write-Host ("WHATIF: Would rename: '$originalName' to '$newName'") -ForegroundColor Yellow
                 # In WhatIf mode, we can't be sure it "would have been" renamed if there was a conflict not covered by -Force
            }
        }
        catch {
            Write-Error "Error renaming file '$($file.FullName)' to '$newName': $($_.Exception.Message)"
            $filesSkippedCount++
        }
    } else {
         #Write-Verbose "No words to replace found in: '$originalName'" # Uncomment for more detailed logging
    }
}

Write-Host "------------------------------------"
if ($effectiveWhatIf) {
    Write-Host "File renaming simulation completed (WhatIf mode)."
} else {
    Write-Host "File renaming process completed."
    Write-Host "Files successfully renamed: $filesRenamedCount"
    Write-Host "Files skipped due to issues or conflicts: $filesSkippedCount"
}