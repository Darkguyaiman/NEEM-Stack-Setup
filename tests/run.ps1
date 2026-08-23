$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Run-Suite([string]$Name, [scriptblock]$Action) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE) { throw "$Name failed with exit code $LASTEXITCODE." }
}

Run-Suite 'Static project validation' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
}
Run-Suite 'Windows PowerShell behavior' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-windows.ps1')
}
Run-Suite 'Windows CMD behavior' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-cmd.ps1')
}

$bashCandidates = @(
    (Get-Command bash.exe -ErrorAction SilentlyContinue | ForEach-Object Source)
    'C:\Program Files\Git\bin\bash.exe'
    'C:\Program Files\Git\usr\bin\bash.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
if (-not $bashCandidates) { throw 'Bash was not found. Install Git for Windows to run the Bash suite.' }
$bash = $bashCandidates[0]
Run-Suite 'Bash behavior' {
    & $bash (Join-Path $PSScriptRoot 'test-unix.sh')
}

Write-Host "`nAll NEEM test suites passed." -ForegroundColor Green
