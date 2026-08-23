# NEEM Stack Setup - interactive Windows server bootstrapper
#
# THESIS: A calm command centre for assembling a server stack, not a numbered
# prompt maze. OWN-WORLD: NEEM red, charcoal surfaces, cream-white type, cool
# gray hierarchy, crisp rules and native checkbox controls. STORY: see the stack,
# select any combination, review it, then install or remove with confidence.
# FIRST VIEWPORT: compact NEEM masthead, platform state, creator credit, then a
# short action menu. FORM: keyboard-operated terminal workbench with a dedicated
# creator card and reversible component management.
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

$ErrorActionPreference = 'Stop'
$script:PlatformRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = Split-Path $script:PlatformRoot -Parent
$versionPath = Join-Path $script:ProjectRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "Version file not found: $versionPath"
}
$script:Version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($script:Version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid version in ${versionPath}: $script:Version"
}
$script:PackageManager = $null
$script:Theme = @{
    Accent = '197;29;52'       # #c51d34
    DarkSurface = '46;46;48'   # #2e2e30
    Muted = '128;128;128'      # #808080
    Subtle = '90;90;90'        # #5a5a5a
    Paper = '245;245;245'      # #f5f5f5
    Cream = '253;251;247'      # #fdfbf7
}
$vtProperty = $Host.UI.PSObject.Properties['SupportsVirtualTerminal']
$script:SupportsTrueColor = [bool](-not [Console]::IsOutputRedirected -and
    ($env:WT_SESSION -or $env:TERM_PROGRAM -or $env:COLORTERM -eq 'truecolor' -or
    ($vtProperty -and $Host.UI.SupportsVirtualTerminal)))
$script:SupportsHyperlinks = [bool](-not [Console]::IsOutputRedirected -and
    ($env:WT_SESSION -or $env:TERM_PROGRAM))


$moduleRoot = Join-Path $script:PlatformRoot 'modules'
@(
    'Core.ps1'
    'Packages.ps1'
    'Web.ps1'
    'Health.ps1'
    'MySQL.ps1'
    'Components.ps1'
    'Menu.ps1'
) | ForEach-Object {
    . (Join-Path $moduleRoot $_)
}

if ($Help) { Show-Usage; exit 0 }
if ($Update) {
    try { Update-NEEM; exit 0 }
    catch { Write-Theme -Text "[x] $($_.Exception.Message)" -Role Accent; exit 1 }
}
if (-not (Test-Administrator) -and -not $NoElevate -and -not $Backup -and
    -not $CreateDatabaseUser -and -not $CreateGlobalDatabaseUser -and -not $ListDatabaseUsers) {
    if (-not $DryRun -and -not $Health) {
        Write-Info 'Requesting administrator access...'
        $scriptPath = $MyInvocation.MyCommand.Path
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
        exit 0
    }
    Write-Warn 'Administrator access is required for installation, Nginx, and SSL tasks.'
}
if ($Health) {
    Show-Health
} elseif ($Backup) {
    Backup-MySQLDatabase
} elseif ($CreateDatabaseUser) {
    New-MySQLDatabaseUser
} elseif ($CreateGlobalDatabaseUser) {
    New-MySQLDatabaseUser -Scope All
} elseif ($ListDatabaseUsers) {
    Show-MySQLUsers
} else {
    Initialize-PackageManager
    Show-MainMenu
}
