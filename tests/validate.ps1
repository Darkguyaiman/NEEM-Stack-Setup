$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$powerShellFiles = @(
    (Join-Path $root 'neem.ps1')
    (Join-Path $root 'windows\neem.ps1')
) + @(Get-ChildItem (Join-Path $root 'windows\modules') -Filter '*.ps1' | ForEach-Object FullName)
foreach ($powerShellFile in $powerShellFiles) {
    $errors = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $powerShellFile,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count) {
        $errors | ForEach-Object { Write-Error "$powerShellFile`: $($_.Message)" }
    }
}

$bashFiles = @((Join-Path $root 'linux\neem.sh')) +
    @(Get-ChildItem (Join-Path $root 'linux\modules') -Filter '*.sh' | Sort-Object Name | ForEach-Object FullName)
$bash = ($bashFiles | ForEach-Object { Get-Content $_ -Raw }) -join "`n"
$powershell = ($powerShellFiles | Where-Object { $_ -like '*\windows\*' } |
    ForEach-Object { Get-Content $_ -Raw }) -join "`n"
$rootBashLauncher = Get-Content (Join-Path $root 'neem.sh') -Raw
$rootPowerShellLauncher = Get-Content (Join-Path $root 'neem.ps1') -Raw
$readme = Get-Content (Join-Path $root 'README.md') -Raw
$version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$windowsCompatibilityLauncher = Get-Content (Join-Path $root 'Start-NEEM.cmd') -Raw
$windowsLauncher = Get-Content (Join-Path $root 'windows\neem.cmd') -Raw
$windowsAlias = Get-Content (Join-Path $root 'neem.cmd') -Raw
$windowsCommandInstaller = Get-Content (Join-Path $root 'Install-NEEM-Command.ps1') -Raw
$unixCommandInstaller = Get-Content (Join-Path $root 'install-neem-command.sh') -Raw

$checks = [ordered]@{
    'Bash has strict mode' = $bash.Contains('set -Eeuo pipefail')
    'Root launchers preserve backwards compatibility' = $rootBashLauncher.Contains('linux/neem.sh') -and $rootPowerShellLauncher.Contains('windows\neem.ps1') -and $windowsCompatibilityLauncher.Contains('windows\neem.cmd')
    'Platform scripts load maintainable modules' = $bash.Contains('source "$PLATFORM_DIR/modules/$module.sh"') -and $powershell.Contains("'Components.ps1'") -and $powershell.Contains("'MySQL.ps1'")
    'README documents the modular platform layout' = $readme.Contains('## Project structure') -and $readme.Contains('windows/') -and $readme.Contains('linux/')
    'Bash validates Nginx before reload' = $bash.Contains('nginx -t')
    'Bash supports dry run' = $bash.Contains('--dry-run')
    'Bash supports GitHub updates' = $bash.Contains('update_neem()') -and $bash.Contains('--update')
    'PowerShell validates Nginx before reload' = $powershell.Contains('-t -p')
    'PowerShell supports dry run' = $powershell.Contains('[switch]$DryRun')
    'PowerShell supports GitHub updates' = $powershell.Contains('function Update-NEEM') -and $powershell.Contains('[switch]$Update')
    'PowerShell has multi-select picker' = $powershell.Contains('function Select-Components')
    'PowerShell installs MySQL Workbench' = $powershell.Contains('Oracle.MySQLWorkbench')
    'PowerShell supports component removal' = $powershell.Contains('Invoke-ComponentWorkflow -Mode Remove')
    'Bash has multi-select picker' = $bash.Contains('select_components()')
    'Bash supports component removal' = $bash.Contains('component_workflow Remove')
    'Both terminals show creator details' = $bash.Contains('mohamedaiman103@gmail.com') -and $powershell.Contains('mohamedaiman103@gmail.com')
    'README includes support links' = $readme.Contains('ko-fi.com/darkguyaiman') -and $readme.Contains('paypal.me/thedarkguyaiman')
    'Windows has a double-click launcher' = $windowsCompatibilityLauncher.Contains('windows\neem.cmd') -and $windowsLauncher.Contains('neem.ps1')
    'CMD launcher elevates Command Prompt' = $windowsLauncher.Contains('$env:ComSpec') -and $windowsLauncher.Contains("'/k'")
    'CMD launcher suppresses PowerShell relaunch' = $windowsLauncher.Contains('-NoElevate')
    'CMD can launch local neem alias' = $windowsAlias.Contains('Start-NEEM.cmd')
    'Windows installs neem-stack command' = $windowsCommandInstaller.Contains('neem-stack.cmd')
    'Windows installs neem command alias' = $windowsCommandInstaller.Contains('neem.cmd')
    'Windows PowerShell aliases forward to live project' = $windowsCommandInstaller.Contains('neem-stack.ps1') -and $windowsCommandInstaller.Contains('$powerShellWrapper')
    'Windows PowerShell aliases preserve long options' = $windowsCommandInstaller.Contains('powershell.exe') -and $windowsCommandInstaller.Contains('@args')
    'Unix installs neem-stack command' = $unixCommandInstaller.Contains('COMMAND_PATH="$BIN_DIR/neem-stack"')
    'Unix installs neem command alias' = $unixCommandInstaller.Contains('SHORT_COMMAND_PATH="$BIN_DIR/neem"')
    'PowerShell has arrow-key main menu' = $powershell.Contains('function Select-MainAction')
    'Both terminals support hyperlinks' = $powershell.Contains('function Write-Hyperlink') -and $bash.Contains('hyperlink()')
    'Both terminals use NEEM red theme' = $powershell.Contains("'197;29;52'") -and $bash.Contains('38;2;197;29;52')
    'Both terminals use charcoal selection' = $powershell.Contains("'46;46;48'") -and $bash.Contains('48;2;46;46;48')
    'Global commands point to live project' = $windowsCommandInstaller.Contains('$liveLauncher') -and $unixCommandInstaller.Contains('$SCRIPT_DIR/neem.sh')
    'README documents self-update commands' = $readme.Contains('neem --update') -and $readme.Contains('neem-stack --update')
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
    'Both scripts install cloudflared' = $bash.Contains('install_cloudflared()') -and $powershell.Contains('function Install-Cloudflared')
    'Both scripts guide Cloudflare Tunnel' = $bash.Contains('cloudflare_tunnel_guide()') -and $powershell.Contains('function Start-CloudflareTunnelGuide')
    'Both scripts create MySQL backups' = $bash.Contains('mysql_backup()') -and $powershell.Contains('function Backup-MySQLDatabase')
    'MySQL backups enforce portable encoding' = $bash.Contains('--default-character-set=utf8mb4') -and $powershell.Contains("'--default-character-set=utf8mb4'") -and $bash.Contains('--hex-blob') -and $powershell.Contains("'--hex-blob'")
    'MySQL backups publish only validated dumps' = $bash.Contains('.partial') -and $bash.Contains('iconv -f UTF-8') -and $powershell.Contains('.partial') -and $powershell.Contains('UTF8Encoding')
    'Both scripts prompt for a backup destination' = $bash.Contains('Destination directory [$backup_dir]') -and $powershell.Contains('Destination directory [$backupDirectory]')
    'Both scripts normalize cross-platform backup paths' = $bash.Contains('normalize_backup_directory()') -and $bash.Contains('wslpath -u') -and $powershell.Contains('function Resolve-BackupDirectory') -and $powershell.Contains("'^/mnt/([A-Za-z])")
    'Both scripts print cross-platform SCP commands' = $bash.Contains('Windows PowerShell:') -and $bash.Contains('macOS:') -and $bash.Contains('Linux:') -and $powershell.Contains('Windows PowerShell:') -and $powershell.Contains('macOS:') -and $powershell.Contains('Linux:')
    'README documents MySQL backups' = $readme.Contains('## MySQL database backups') -and $readme.Contains('neem --backup')
    'Both scripts create database-scoped MySQL users' = $bash.Contains('mysql_create_user()') -and $powershell.Contains('function New-MySQLDatabaseUser') -and $bash.Contains('GRANT ALL PRIVILEGES ON') -and $powershell.Contains('GRANT ALL PRIVILEGES ON')
    'MySQL user passwords stay out of previews' = $bash.Contains('password hidden') -and $powershell.Contains('password hidden') -and $bash.Contains('read_hidden_paste_input "New user password:"') -and $powershell.Contains("Read-HiddenPasteInput 'New user password:'")
    'README documents MySQL user creation' = $readme.Contains('## MySQL database users') -and $readme.Contains('--create-db-user')
    'Both scripts have arrow-key database pickers' = $bash.Contains('select_mysql_database()') -and $bash.Contains('STEP 2 OF 6 | CHOOSE A DATABASE') -and $powershell.Contains('function Select-MySQLDatabase') -and $powershell.Contains('STEP 2 OF 6 | CHOOSE A DATABASE')
    'Database pickers support cancellation' = $bash.Contains('Backup cancelled. No file was created.') -and $powershell.Contains('Backup cancelled. No file was created.') -and $bash.Contains('User creation cancelled. No account was changed.') -and $powershell.Contains('User creation cancelled. No account was changed.')
    'Both scripts manage MySQL users from a submenu' = $bash.Contains('select_mysql_user_action()') -and $bash.Contains('Manage MySQL users') -and $powershell.Contains('function Select-MySQLUserAction') -and $powershell.Contains('Manage MySQL users')
    'Both scripts support server-wide database users' = $bash.Contains('GRANT ALL PRIVILEGES ON *.*') -and $powershell.Contains('GRANT ALL PRIVILEGES ON *.*') -and $bash.Contains('system schemas') -and $powershell.Contains('system schemas')
    'Both scripts list MySQL users and hosts' = $bash.Contains('mysql_list_users()') -and $bash.Contains('ALLOWED_HOST') -and $powershell.Contains('function Show-MySQLUsers') -and $powershell.Contains('ALLOWED_HOST')
    'README warns about server-wide database users' = $readme.Contains('ALL PRIVILEGES ON *.*') -and $readme.Contains('system schemas')
    'Both scripts expose direct MySQL user commands' = $bash.Contains('--create-global-db-user') -and $bash.Contains('--list-db-users') -and $powershell.Contains('[switch]$CreateGlobalDatabaseUser') -and $powershell.Contains('[switch]$ListDatabaseUsers')
    'Tunnel tokens are redacted' = $bash.Contains('<TUNNEL_TOKEN hidden>') -and $powershell.Contains('<TUNNEL_TOKEN hidden>')
    'Both scripts extract tokens from full commands' = $bash.Contains("grep -Eo 'eyJ[A-Za-z0-9_-]{20,}'") -and $powershell.Contains("[regex]::Match(`$pastedValue, 'eyJ[A-Za-z0-9_-]{20,}')")
    'Both scripts validate tokens before service replacement' = $bash.Contains('valid_cloudflare_tunnel_token') -and $powershell.Contains('Test-CloudflareTunnelToken')
    'Both scripts guide published hostname setup' = $bash.Contains('ADD THE PUBLIC HOSTNAME') -and $powershell.Contains('ADD THE PUBLIC HOSTNAME')
    'Both scripts explain paste shortcut' = $bash.Contains('Ctrl+Shift+V') -and $powershell.Contains('Ctrl+Shift+V')
    'Both scripts retry the current port step' = $bash.Contains('type a new port, A to continue anyway') -and $powershell.Contains('type a new port, A to continue anyway')
    'Both scripts run Quick Tunnels in background' = $bash.Contains('start_background_quick_tunnel()') -and $bash.Contains('nohup cloudflared tunnel --url') -and $powershell.Contains('function Start-BackgroundQuickTunnel') -and $powershell.Contains('-WindowStyle Hidden')
    'Both scripts manage Quick and managed Tunnels' = $bash.Contains('manage_cloudflare_tunnels()') -and $powershell.Contains('function Manage-CloudflareTunnels')
    'Both scripts confirm hidden paste was received' = $bash.Contains('Paste received. Validating token') -and $powershell.Contains('Paste received. Validating token')
    'Both scripts mask pasted tunnel credentials' = $bash.Contains('read_hidden_paste_input()') -and $powershell.Contains('$maximumStars = 12')
    'Both scripts backfill older managed tunnel details' = $bash.Contains('predates NEEM tunnel tracking') -and $powershell.Contains('predates NEEM tunnel tracking')
    'Both scripts show tunnel creation progress' = $bash.Contains('Creating Quick Tunnel...') -and $powershell.Contains('Creating Quick Tunnel...')
    'README documents Cloudflare Tunnel' = $readme.Contains('## Guided Cloudflare Tunnel') -and $readme.Contains('trycloudflare.com')
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
