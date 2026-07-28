# Installs the `neem-stack` command for the current Windows user.
#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\NEEM Stack'
$commandPath = Join-Path $installRoot 'neem-stack.cmd'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item (Join-Path $sourceRoot 'neem.ps1') $installRoot -Force
Copy-Item (Join-Path $sourceRoot 'Start-NEEM.cmd') $commandPath -Force

$artPath = Join-Path $sourceRoot 'ASCI_ART_ME.txt'
if (Test-Path $artPath) {
    Copy-Item $artPath $installRoot -Force
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ })
if ($entries -notcontains $installRoot) {
    $updatedPath = (($entries + $installRoot) | Select-Object -Unique) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')
}

Write-Host ''
Write-Host 'NEEM command installed.' -ForegroundColor Green
Write-Host "Location: $commandPath" -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Open a new terminal, then run:' -ForegroundColor White
Write-Host '  neem-stack' -ForegroundColor Cyan
