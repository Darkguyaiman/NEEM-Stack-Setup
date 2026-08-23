$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

Write-Host 'Windows PowerShell suite'

$entry = Join-Path $root 'windows\neem.ps1'
$modules = @(Get-ChildItem (Join-Path $root 'windows\modules') -Filter '*.ps1' | Sort-Object Name)
Assert-Equal 7 $modules.Count 'seven focused PowerShell modules are present'

foreach ($file in @((Get-Item $entry)) + $modules) {
    $errors = $null
    $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-Equal 0 $errors.Count "$($file.Name) parses successfully"
}

$expectedModules = @('Core.ps1','Packages.ps1','Web.ps1','Health.ps1','MySQL.ps1','Components.ps1','Menu.ps1')
$entryText = Get-Content $entry -Raw
foreach ($moduleName in $expectedModules) {
    Assert-True $entryText.Contains("'$moduleName'") "entry point loads $moduleName"
}

$script:ProjectRoot = $root
$script:Version = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
$script:PackageManager = 'test'
$script:SupportsTrueColor = $false
$script:SupportsHyperlinks = $false
$script:Theme = @{}
foreach ($moduleName in $expectedModules) {
    . (Join-Path $root "windows\modules\$moduleName")
}

Assert-True (Test-Domain 'example.com') 'domain validator accepts a normal hostname'
Assert-True (Test-Domain 'api.dev.example.co.uk') 'domain validator accepts subdomains'
Assert-True (-not (Test-Domain 'https://example.com')) 'domain validator rejects URLs'
Assert-True (-not (Test-Domain 'bad_name.example')) 'domain validator rejects underscores'
Assert-True (Test-Port '1') 'port validator accepts the minimum port'
Assert-True (Test-Port '65535') 'port validator accepts the maximum port'
Assert-True (-not (Test-Port '0')) 'port validator rejects port zero'
Assert-True (-not (Test-Port '65536')) 'port validator rejects ports above 65535'
Assert-True (-not (Test-Port 'abc')) 'port validator rejects non-numeric input'
Assert-True (-not (Test-CloudflareTunnelToken 'not-a-token')) 'tunnel validator rejects malformed tokens'

$profilePath = [Environment]::GetFolderPath('UserProfile')
Assert-Equal ([IO.Path]::GetFullPath((Join-Path $profilePath 'NEEM Test'))) (Resolve-BackupDirectory '~/NEEM Test') 'backup paths expand tilde'
Assert-Equal 'C:\NEEM Test' (Resolve-BackupDirectory 'C:/NEEM Test') 'backup paths accept forward-slash Windows paths'
Assert-Equal 'C:\NEEM Test' (Resolve-BackupDirectory '/c/NEEM Test') 'backup paths accept Git Bash drive paths'
Assert-Equal 'C:\NEEM Test' (Resolve-BackupDirectory '/mnt/c/NEEM Test') 'backup paths accept WSL drive paths'
Assert-Equal 'C:\NEEM Test' (Resolve-BackupDirectory '"C:\NEEM Test"') 'backup paths remove pasted quotes'

$catalog = @(Get-ComponentCatalog)
Assert-True ($catalog.Count -ge 8) 'component catalog contains the supported stack'
Assert-Equal $catalog.Count @($catalog.Name | Select-Object -Unique).Count 'component names are unique'
$actions = @(Get-MainActions)
Assert-True ($actions.Count -ge 10) 'main menu exposes all primary workflows'
Assert-Equal $actions.Count @($actions.Id | Select-Object -Unique).Count 'main-menu identifiers are unique'

$powerShell = (Get-Command powershell.exe).Source
foreach ($scriptPath in @('neem.ps1','windows\neem.ps1')) {
    $quotedPath = '"' + (Join-Path $root $scriptPath) + '"'
    $result = Invoke-TestProcess $powerShell "-NoLogo -NoProfile -ExecutionPolicy Bypass -File $quotedPath -Help" $root
    Assert-Equal 0 $result.ExitCode "$scriptPath help exits successfully"
    Assert-True $result.Output.Contains("NEEM Stack Setup v$script:Version") "$scriptPath reads the shared version"
    Assert-True $result.Output.Contains('-Backup') "$scriptPath help includes backup commands"
}

$invalid = Invoke-TestProcess $powerShell ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $entry + '" -NotARealOption') $root
Assert-True ($invalid.ExitCode -ne 0) 'PowerShell rejects unknown command-line options'
Assert-True ($invalid.Output -match 'NotARealOption') 'PowerShell identifies the unknown option'

foreach ($module in $modules) {
    $bytes = [IO.File]::ReadAllBytes($module.FullName)
    Assert-True ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "$($module.Name) is PowerShell 5.1-safe UTF-8"
}

Write-Host "`nWindows PowerShell suite passed ($script:TestCount assertions)." -ForegroundColor Green
