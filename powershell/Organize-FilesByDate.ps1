<#
.SYNOPSIS
    Organizes files into a directory structure based on their dates (Year/Month/Day).

.DESCRIPTION
    This script moves files from a source to a destination directory. 
    It creates folders based on the file dates. 
    By default, it uses the LastWriteTime (Modification) and organizes by Year -> Month.

.PARAMETER SourcePath
    The folder containing the files to organize.

.PARAMETER DestinationPath
    The root folder where organized files will be moved. Defaults to SourcePath.

.PARAMETER DateType
    The type of date to use. Options: Modification (Default), Creation, Access.

.PARAMETER Year
    Boolean. Create a Year folder? Default is $true.
    To disable, use: -Year:$false

.PARAMETER Month
    Boolean. Create a Month folder? Default is $true.
    To disable, use: -Month:$false

.PARAMETER Day
    Boolean. Create a Day folder? Default is $false.
    To enable, use: -Day:$true

.EXAMPLE
    .\Organize-Files.ps1 -SourcePath "C:\Downloads"
    # Sorts by Modification Date into "C:\Downloads\2023\10-October"

.EXAMPLE
    .\Organize-Files.ps1 -SourcePath "C:\Photos" -DateType Creation -Day:$true
    # Sorts by Creation Date into "C:\Photos\2023\10-October\25"

.EXAMPLE
    .\Organize-Files.ps1 -SourcePath "C:\Logs" -Month:$false
    # Sorts by Modification Date into "C:\Logs\2023" (Year only)
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$SourcePath,

    [Parameter(Position=1)]
    [string]$DestinationPath,

    [Parameter()]
    [ValidateSet("Modification", "Creation", "Access")]
    [string]$DateType = "Modification",

    [Parameter()]
    [bool]$Year = $true,

    [Parameter()]
    [bool]$Month = $true,

    [Parameter()]
    [bool]$Day = $false
)

# 1. Set Destination to Source if not provided
if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
    $DestinationPath = $SourcePath
}

# 2. Map the DateType string to the actual FileInfo property
$DateProperty = switch ($DateType) {
    "Modification" { "LastWriteTime" }
    "Creation"     { "CreationTime" }
    "Access"       { "LastAccessTime" }
}

Write-Verbose "Sorting files from '$SourcePath' using '$DateProperty'."
Write-Verbose "Structure settings: Year=$Year, Month=$Month, Day=$Day"

# 3. Get all files (exclude directories)
$files = Get-ChildItem -Path $SourcePath -File

foreach ($file in $files) {
    # Get the specific date value
    $targetDate = $file.$DateProperty

    # 4. Build the folder structure path based on flags
    $folderStructure = @()

    if ($Year) {
        $folderStructure += $targetDate.Year.ToString()
    }

    if ($Month) {
        # Format: 01-January for better sorting
        $folderStructure += $targetDate.ToString("MM-MMMM")
    }

    if ($Day) {
        $folderStructure += $targetDate.ToString("dd")
    }

    # If no flags are true, files stay in root (or destination root)
    if ($folderStructure.Count -eq 0) {
        $fullDestPath = $DestinationPath
    }
    else {
        # Join the destination root with the calculated subfolders
        $subPath = [System.IO.Path]::Combine($folderStructure)
        $fullDestPath = Join-Path -Path $DestinationPath -ChildPath $subPath
    }

    # 5. Create Directory if it doesn't exist
    if (-not (Test-Path -Path $fullDestPath)) {
        # -Force creates parent directories if needed
        New-Item -ItemType Directory -Path $fullDestPath -Force | Out-Null
        Write-Verbose "Created directory: $fullDestPath"
    }

    # 6. Move the file
    $destFilePath = Join-Path -Path $fullDestPath -ChildPath $file.Name
    
    # Check if file already exists at destination to prevent overwrite errors
    if (Test-Path -Path $destFilePath) {
        Write-Warning "File '$($file.Name)' already exists in '$fullDestPath'. Skipping."
    }
    else {
        # Move-Item supports -WhatIf automatically due to CmdletBinding
        Move-Item -Path $file.FullName -Destination $destFilePath
        Write-Verbose "Moved '$($file.Name)' to '$fullDestPath'"
    }
}

Write-Host "Organization complete!" -ForegroundColor Green