# Installs the `neem-stack` command for the current Windows user.
#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\NEEM Stack'
$commandPath = Join-Path $installRoot 'neem-stack.cmd'
$shortCommandPath = Join-Path $installRoot 'neem.cmd'
$powerShellCommandPath = Join-Path $installRoot 'neem-stack.ps1'
$shortPowerShellCommandPath = Join-Path $installRoot 'neem.ps1'

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$liveLauncher = Join-Path $sourceRoot 'Start-NEEM.cmd'
$escapedLauncher = $liveLauncher.Replace('"', '""')
$wrapper = "@echo off`r`ncall `"$escapedLauncher`" %*`r`n"
$encoding = [Text.Encoding]::Default
[IO.File]::WriteAllText($commandPath, $wrapper, $encoding)
[IO.File]::WriteAllText($shortCommandPath, $wrapper, $encoding)
$liveScript = Join-Path $sourceRoot 'neem.ps1'
$escapedScript = $liveScript.Replace("'", "''")
$powerShellWrapper = "& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File '$escapedScript' @args`r`nexit `$LASTEXITCODE`r`n"
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($powerShellCommandPath, $powerShellWrapper, $utf8)
[IO.File]::WriteAllText($shortPowerShellCommandPath, $powerShellWrapper, $utf8)

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
