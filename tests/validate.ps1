$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$errors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'neem.ps1'),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_.Message }
}

$bash = Get-Content (Join-Path $root 'neem.sh') -Raw
$powershell = Get-Content (Join-Path $root 'neem.ps1') -Raw
$readme = Get-Content (Join-Path $root 'README.md') -Raw

$checks = [ordered]@{
    'Bash has strict mode' = $bash.Contains('set -Eeuo pipefail')
    'Bash validates Nginx before reload' = $bash.Contains('nginx -t')
    'Bash supports dry run' = $bash.Contains('--dry-run')
    'PowerShell validates Nginx before reload' = $powershell.Contains('-t -p')
    'PowerShell supports dry run' = $powershell.Contains('[switch]$DryRun')
    'Both scripts configure ACME' = $bash.Contains('certbot --nginx') -and $powershell.Contains("'--validation', 'filesystem'")
    'Documentation covers Linux' = $readme.Contains('### Linux')
    'Documentation covers macOS' = $readme.Contains('### macOS')
    'Documentation covers Windows' = $readme.Contains('### Windows')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $mark = if ($check.Value) { '+' } else { 'x' }
    Write-Host "$mark $($check.Key)"
}
if ($failed.Count) { throw "$($failed.Count) validation check(s) failed." }

Write-Host "`nAll project validation checks passed." -ForegroundColor Green
