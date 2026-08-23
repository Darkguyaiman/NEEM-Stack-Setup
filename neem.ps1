# Compatibility entry point. The maintained Windows implementation lives under windows/.
#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Health,
    [switch]$Backup,
    [switch]$CreateDatabaseUser,
    [switch]$CreateGlobalDatabaseUser,
    [switch]$ListDatabaseUsers,
    [switch]$Update,
    [switch]$Help,
    [switch]$NoElevate
)

& (Join-Path $PSScriptRoot 'windows\neem.ps1') @PSBoundParameters
