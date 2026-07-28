# Installs the `neem-stack` command for the current Windows user.
#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\NEEM Stack'
$commandPath = Join-Path $installRoot 'neem-stack.cmd'
$shortCommandPath = Join-Path $installRoot 'neem.cmd'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$liveLauncher = Join-Path $sourceRoot 'Start-NEEM.cmd'
$escapedLauncher = $liveLauncher.Replace('"', '""')
$wrapper = "@echo off`r`ncall `"$escapedLauncher`" %*`r`n"
$encoding = [Text.Encoding]::Default
[IO.File]::WriteAllText($commandPath, $wrapper, $encoding)
[IO.File]::WriteAllText($shortCommandPath, $wrapper, $encoding)

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @($userPath -split ';' | Where-Object { $_ -and $_ -ne $installRoot })
$updatedPath = ((@($installRoot) + $entries) | Select-Object -Unique) -join ';'
[Environment]::SetEnvironmentVariable('Path', $updatedPath, 'User')

Write-Host ''
Write-Host 'NEEM command installed.' -ForegroundColor Green
Write-Host "Command: $commandPath" -ForegroundColor DarkGray
Write-Host "Live project: $sourceRoot" -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Open a new terminal, then run:' -ForegroundColor White
Write-Host '  neem-stack' -ForegroundColor Cyan
Write-Host '  neem' -ForegroundColor Cyan
