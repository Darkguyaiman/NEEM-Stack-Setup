$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Write-Host 'Windows CMD suite'

$cmdExe = $env:ComSpec
$launchers = @('neem.cmd','Start-NEEM.cmd','windows\neem.cmd')
foreach ($launcher in $launchers) {
    $fullPath = Join-Path $root $launcher
    Assert-True (Test-Path -LiteralPath $fullPath -PathType Leaf) "$launcher exists"
    $result = Invoke-TestProcess $cmdExe ('/d /c ""' + $fullPath + '" -Help"') $root
    Assert-Equal 0 $result.ExitCode "$launcher forwards a successful exit code"
    Assert-True $result.Output.Contains('NEEM Stack Setup v') "$launcher reaches the PowerShell entry point"
    Assert-True $result.Output.Contains('-CreateGlobalDatabaseUser') "$launcher preserves command arguments"
}

$rootAlias = Get-Content (Join-Path $root 'neem.cmd') -Raw
$rootStart = Get-Content (Join-Path $root 'Start-NEEM.cmd') -Raw
$platformCmd = Get-Content (Join-Path $root 'windows\neem.cmd') -Raw
Assert-True $rootAlias.Contains('Start-NEEM.cmd') 'neem.cmd remains a compatibility alias'
Assert-True $rootStart.Contains('windows\neem.cmd') 'Start-NEEM.cmd forwards to the modular Windows launcher'
Assert-True $platformCmd.Contains('NEEM_ARGUMENTS=%*') 'elevated CMD launches preserve every argument'
Assert-True $platformCmd.Contains("'/d','/k'") 'elevated CMD launches keep an interactive error window'
Assert-True $platformCmd.Contains('-NoElevate %*') 'PowerShell relaunch recursion is suppressed'

foreach ($safeAction in @('-Help','-DryRun','-Health','-Backup','-CreateDatabaseUser','-CreateGlobalDatabaseUser','-ListDatabaseUsers','-Update')) {
    Assert-True $platformCmd.Contains("if /i `"%~1`"==`"$safeAction`" goto run_neem") "$safeAction bypasses unnecessary elevation"
}

Write-Host "`nWindows CMD suite passed ($script:TestCount assertions)." -ForegroundColor Green
