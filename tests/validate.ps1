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
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$windowsLauncher = Get-Content (Join-Path $root 'Start-NEEM.cmd') -Raw
$windowsAlias = Get-Content (Join-Path $root 'neem.cmd') -Raw
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
    'CMD launcher elevates Command Prompt' = $windowsLauncher.Contains('$env:ComSpec') -and $windowsLauncher.Contains("'/k'")
    'CMD launcher suppresses PowerShell relaunch' = $windowsLauncher.Contains('-NoElevate')
    'CMD can launch local neem alias' = $windowsAlias.Contains('Start-NEEM.cmd')
    'Windows installs neem-stack command' = $windowsCommandInstaller.Contains('neem-stack.cmd')
    'Windows installs neem command alias' = $windowsCommandInstaller.Contains('neem.cmd')
    'Unix installs neem-stack command' = $unixCommandInstaller.Contains('COMMAND_PATH="$BIN_DIR/neem-stack"')
    'Unix installs neem command alias' = $unixCommandInstaller.Contains('SHORT_COMMAND_PATH="$BIN_DIR/neem"')
    'PowerShell has arrow-key main menu' = $powershell.Contains('function Select-MainAction')
    'Both terminals support hyperlinks' = $powershell.Contains('function Write-Hyperlink') -and $bash.Contains('hyperlink()')
    'Both terminals use NEEM red theme' = $powershell.Contains("'197;29;52'") -and $bash.Contains('38;2;197;29;52')
    'Both terminals use charcoal selection' = $powershell.Contains("'46;46;48'") -and $bash.Contains('48;2;46;46;48')
    'Global commands point to live project' = $windowsCommandInstaller.Contains('$liveLauncher') -and $unixCommandInstaller.Contains('$SCRIPT_DIR/neem.sh')
    'Menus redraw without full-screen flicker' = $powershell.Contains('CursorPosition = [System.Management.Automation.Host.Coordinates]') -and $bash.Contains("printf '\033[%dA'")
    'Creator screen supports keyboard links' = $powershell.Contains('Press 1-7 to open a link') -and $bash.Contains('Press 1-7 to open a link')
    'Creator screen supports side-by-side layout' = $powershell.Contains('$sideBySide') -and $bash.Contains('cols >= 138')
    'Creator screen reflows while resized' = $powershell.Contains('$lastWidth') -and $powershell.Contains('[Console]::KeyAvailable') -and $bash.Contains('last_cols=-1') -and $bash.Contains('read -rsn1 -t 0.1')
    'Version follows semantic versioning' = $version -match '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$'
    'Scripts read the shared VERSION file' = $powershell.Contains("Join-Path `$script:ProjectRoot 'VERSION'") -and $bash.Contains('VERSION_FILE="$SCRIPT_DIR/VERSION"')
    'README documents the shared VERSION file' = $readme.Contains('one source of truth') -and $readme.Contains('[`VERSION`](VERSION)')
    'Classic CMD does not advertise hyperlinks' = $powershell.Contains('$script:SupportsHyperlinks') -and $powershell.Contains("'Press 1-7 to open a link.'")
    'PowerShell filters component pickers by state' = $powershell.Contains("if (`$Verb -eq 'Install')") -and $powershell.Contains('Test-ComponentInstalled')
    'Bash filters component pickers by state' = $bash.Contains('component_installed "$index"') -and $bash.Contains('available+=("$index")')
    'Complete stack installs only missing items' = $powershell.Contains('$needed = @(Get-ComponentCatalog') -and $bash.Contains('local -a needed=()')
    'Health views replace raw PM2 tables' = $powershell.Contains("'PM2 APPLICATIONS'") -and -not $powershell.Contains('& pm2 ls') -and $bash.Contains('pm2 jlist')
    'Creator portrait is compacted at runtime' = $powershell.Contains('compactArt') -and $bash.Contains('source_row % 6')
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
