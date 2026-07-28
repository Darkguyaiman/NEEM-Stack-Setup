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
$windowsLauncher = Get-Content (Join-Path $root 'Start-NEEM.cmd') -Raw
$windowsCommandInstaller = Get-Content (Join-Path $root 'Install-NEEM-Command.ps1') -Raw
$unixCommandInstaller = Get-Content (Join-Path $root 'install-neem-command.sh') -Raw

$checks = [ordered]@{
    'Bash has strict mode' = $bash.Contains('set -Eeuo pipefail')
    'Bash validates Nginx before reload' = $bash.Contains('nginx -t')
    'Bash supports dry run' = $bash.Contains('--dry-run')
    'PowerShell validates Nginx before reload' = $powershell.Contains('-t -p')
    'PowerShell supports dry run' = $powershell.Contains('[switch]$DryRun')
    'PowerShell has multi-select picker' = $powershell.Contains('function Select-Components')
    'PowerShell installs MySQL Workbench' = $powershell.Contains('Oracle.MySQLWorkbench')
    'PowerShell supports component removal' = $powershell.Contains('Invoke-ComponentWorkflow -Mode Remove')
    'Bash has multi-select picker' = $bash.Contains('select_components()')
    'Bash supports component removal' = $bash.Contains('component_workflow Remove')
    'Both terminals show creator details' = $bash.Contains('mohamedaiman103@gmail.com') -and $powershell.Contains('mohamedaiman103@gmail.com')
    'README includes support links' = $readme.Contains('ko-fi.com/darkguyaiman') -and $readme.Contains('paypal.me/thedarkguyaiman')
    'Windows has a double-click launcher' = $windowsLauncher.Contains('neem.ps1')
    'Windows installs neem-stack command' = $windowsCommandInstaller.Contains('neem-stack.cmd')
    'Unix installs neem-stack command' = $unixCommandInstaller.Contains('COMMAND_PATH="$BIN_DIR/neem-stack"')
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
