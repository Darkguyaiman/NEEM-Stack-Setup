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
$script:ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
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

function Write-Theme {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Accent','Primary','Secondary','Muted','Subtle','Selected')][string]$Role = 'Primary',
        [switch]$NoNewline
    )
    if ($script:SupportsTrueColor) {
        $escape = [char]27
        $code = switch ($Role) {
            'Accent' { "38;2;$($script:Theme.Accent)" }
            'Primary' { "38;2;$($script:Theme.Cream)" }
            'Secondary' { "38;2;$($script:Theme.Paper)" }
            'Muted' { "38;2;$($script:Theme.Muted)" }
            'Subtle' { "38;2;$($script:Theme.Subtle)" }
            'Selected' { "38;2;$($script:Theme.Cream);48;2;$($script:Theme.DarkSurface)" }
        }
        Write-Host ($escape + '[' + $code + 'm' + $Text + $escape + '[0m') -NoNewline:$NoNewline
        return
    }
    $foreground = switch ($Role) {
        'Accent' { 'Red' }
        'Primary' { 'White' }
        'Secondary' { 'Gray' }
        'Muted' { 'DarkGray' }
        'Subtle' { 'DarkGray' }
        'Selected' { 'White' }
    }
    if ($Role -eq 'Selected') {
        Write-Host $Text -ForegroundColor $foreground -BackgroundColor DarkGray -NoNewline:$NoNewline
    } else {
        Write-Host $Text -ForegroundColor $foreground -NoNewline:$NoNewline
    }
}

function Write-Info([string]$Message) { Write-Theme -Text "[i] $Message" -Role Muted }
function Write-Ok([string]$Message) { Write-Theme -Text "[+] $Message" -Role Secondary }
function Write-Warn([string]$Message) { Write-Theme -Text "[!] $Message" -Role Accent }

function Write-Hyperlink {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Url,
        [string]$Prefix = '  '
    )
    $supportsLinks = $script:SupportsHyperlinks
    if ($supportsLinks) {
        $escape = [char]27
        $link = $escape + ']8;;' + $Url + $escape + '\' + $Label + $escape + ']8;;' + $escape + '\'
        Write-Theme -Text $Prefix -Role Muted -NoNewline
        Write-Theme -Text $link -Role Secondary
    } else {
        Write-Theme -Text "$Prefix$Label" -Role Secondary
    }
}

function Write-Rule {
    param([string]$Title = '')
    $width = [Math]::Min(72, [Math]::Max(44, $Host.UI.RawUI.WindowSize.Width - 2))
    if ($Title) {
        $line = "-- $Title "
        $line += '-' * [Math]::Max(2, $width - $line.Length)
    } else {
        $line = '-' * $width
    }
    Write-Theme -Text $line -Role Subtle
}

function Show-Brand {
    Write-Host ''
    Write-Theme -Text '  ███╗   ██╗███████╗███████╗███╗   ███╗' -Role Accent
    Write-Theme -Text '  ████╗  ██║██╔════╝██╔════╝████╗ ████║' -Role Accent
    Write-Theme -Text '  ██╔██╗ ██║█████╗  █████╗  ██╔████╔██║' -Role Accent
    Write-Theme -Text '  ██║╚██╗██║██╔══╝  ██╔══╝  ██║╚██╔╝██║' -Role Accent
    Write-Theme -Text '  ██║ ╚████║███████╗███████╗██║ ╚═╝ ██║' -Role Accent
    Write-Theme -Text '  ╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝     ╚═╝' -Role Accent
    Write-Theme -Text '  Stack Setup' -Role Primary -NoNewline
    Write-Theme -Text "  v$script:Version" -Role Muted
    Write-Theme -Text '  Built with care by Mohamed Aiman' -Role Muted
    Write-Rule
}

function Show-CreatorCard {
    $artPath = Join-Path $script:ProjectRoot 'ASCI_ART_ME.txt'
    $art = if (Test-Path $artPath) { @(Get-Content $artPath) } else { @('  ASCII portrait not found.') }
    $compactArt = for ($row = 0; $row -lt $art.Count; $row++) {
        if ((($row + 1) % 6) -eq 0) { continue }
        $line = $art[$row]
        if (-not $line.Length) { ''; continue }
        $characters = for ($column = 0; $column -lt $line.Length; $column++) {
            if ((($column + 1) % 8) -ne 0) { $line[$column] }
        }
        (-join $characters) -replace '^ {0,12}', ''
    }
    $art = @($compactArt)
    $links = @(
        [pscustomobject]@{ Key='1'; Label='Email'; Text='mohamedaiman103@gmail.com'; Url='mailto:mohamedaiman103@gmail.com' }
        [pscustomobject]@{ Key='2'; Label='Portfolio'; Text='darkguyaiman.com'; Url='https://darkguyaiman.com' }
        [pscustomobject]@{ Key='3'; Label='LinkedIn'; Text='linkedin.com/in/darkguyaiman'; Url='https://www.linkedin.com/in/darkguyaiman' }
        [pscustomobject]@{ Key='4'; Label='Instagram'; Text='instagram.com/darkguyaiman'; Url='https://www.instagram.com/darkguyaiman' }
        [pscustomobject]@{ Key='5'; Label='X / Twitter'; Text='x.com/thedarkguyaiman'; Url='https://x.com/thedarkguyaiman' }
        [pscustomobject]@{ Key='6'; Label='Ko-fi'; Text='ko-fi.com/darkguyaiman'; Url='https://ko-fi.com/darkguyaiman' }
        [pscustomobject]@{ Key='7'; Label='PayPal'; Text='paypal.me/thedarkguyaiman'; Url='https://paypal.me/thedarkguyaiman' }
    )
    $artWidth = (($art | ForEach-Object Length | Measure-Object -Maximum).Maximum) + 3
    $panelWidth = 54
    $linkHelp = if ($script:SupportsHyperlinks) {
        'Ctrl+click a link, or press 1-7 to open.'
    } else {
        'Press 1-7 to open a link.'
    }

    $renderCreator = {
        param([int]$Width)
        Clear-Host
        $sideBySide = $Width -ge ($artWidth + $panelWidth)
        if ($sideBySide) {
            $panelRows = @{}
            $panelRows[5] = [pscustomobject]@{ Type='heading'; Text='MOHAMED AIMAN' }
            $panelRows[6] = [pscustomobject]@{ Type='copy'; Text='Creator of NEEM Stack Setup' }
            for ($index = 0; $index -lt $links.Count; $index++) {
                $panelRows[9 + ($index * 2)] = [pscustomobject]@{ Type='link'; Link=$links[$index] }
            }
            $panelRows[25] = [pscustomobject]@{ Type='copy'; Text=$linkHelp }
            $rowCount = [Math]::Max($art.Count, 27)
            for ($row = 0; $row -lt $rowCount; $row++) {
                $left = if ($row -lt $art.Count) { $art[$row].TrimEnd() } else { '' }
                Write-Theme -Text ($left.PadRight($artWidth)) -Role Subtle -NoNewline
                $panel = $panelRows[$row]
                if (-not $panel) { Write-Host ''; continue }
                switch ($panel.Type) {
                    'heading' { Write-Theme -Text $panel.Text -Role Accent }
                    'copy' { Write-Theme -Text $panel.Text -Role Muted }
                    'link' {
                        $item = $panel.Link
                        Write-Hyperlink -Prefix ("[{0}] {1,-11} " -f $item.Key, $item.Label) -Label $item.Text -Url $item.Url
                    }
                }
            }
        } else {
            $art | ForEach-Object { Write-Theme -Text $_ -Role Subtle }
            Write-Rule 'CREATOR'
            Write-Theme -Text '  Mohamed Aiman  |  Creator of NEEM Stack Setup' -Role Primary
            foreach ($item in $links) {
                Write-Hyperlink -Prefix ("  [{0}] {1,-11} " -f $item.Key, $item.Label) -Label $item.Text -Url $item.Url
            }
        }
        Write-Host ''
        Write-Theme -Text '  Press 1-7 to open a link  |  Enter or Esc to return  |  Resize to reflow' -Role Muted
    }

    $lastWidth = -1
    while ($true) {
        try { $currentWidth = $Host.UI.RawUI.WindowSize.Width } catch { $currentWidth = 120 }
        if ($currentWidth -ne $lastWidth) {
            & $renderCreator $currentWidth
            $lastWidth = $currentWidth
        }
        try { $keyAvailable = [Console]::KeyAvailable } catch { $keyAvailable = $false }
        if (-not $keyAvailable) {
            Start-Sleep -Milliseconds 100
            continue
        }
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.VirtualKeyCode -in 13,27) { return }
        if ($key.Character -match '^[1-7]$') {
            $item = $links[[int]::Parse([string]$key.Character) - 1]
            Start-Process $item.Url
        }
    }
}

function Invoke-Step {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Display)
    Write-Theme -Text "> $Display" -Role Accent
    if (-not $DryRun) {
        $global:LASTEXITCODE = 0
        & $Action
        if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE`: $Display" }
    }
}

function Invoke-SecretStep {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Display)
    Write-Theme -Text "> $Display" -Role Accent
    if (-not $DryRun) {
        $global:LASTEXITCODE = 0
        & $Action
        if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE`: $Display" }
    }
}

function Set-Utf8NoBom([string]$Path, [string]$Value) {
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Confirm-Action([string]$Prompt) {
    if ($DryRun) { return $true }
    return (Read-Host "$Prompt [y/N]") -match '^[Yy]$'
}

function Read-HiddenPasteInput {
    param([Parameter(Mandatory)][string]$Prompt)
    Write-Host "$Prompt " -NoNewline
    $secure = [Security.SecureString]::new()
    $visibleStars = 0
    $maximumStars = 12
    try {
        while ($true) {
            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            if ($key.VirtualKeyCode -eq 13) { Write-Host ''; return $secure }
            if ($key.VirtualKeyCode -eq 27) { Write-Host ''; return [Security.SecureString]::new() }
            if ($key.VirtualKeyCode -eq 8) {
                if ($secure.Length -gt 0) {
                    if ($secure.Length -le $maximumStars -and $visibleStars -gt 0) {
                        Write-Host "`b `b" -NoNewline
                        $visibleStars--
                    }
                    $secure.RemoveAt($secure.Length - 1)
                }
                continue
            }
            if ($key.Character -and [int]$key.Character -ne 0) {
                $secure.AppendChar($key.Character)
                if ($visibleStars -lt $maximumStars) {
                    Write-Host '*' -NoNewline
                    $visibleStars++
                }
            }
        }
    } catch {
        Write-Host ''
        return Read-Host 'Paste the value and press Enter (input remains hidden)' -AsSecureString
    }
}

function Test-CloudflareTunnelToken {
    param([Parameter(Mandatory)][string]$Token)
    if ($Token -notmatch '^eyJ[A-Za-z0-9_-]{20,}$') { return $false }
    try {
        $base64 = $Token.Replace('-', '+').Replace('_', '/')
        switch ($base64.Length % 4) {
            2 { $base64 += '==' }
            3 { $base64 += '=' }
            1 { return $false }
        }
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
        $credential = $json | ConvertFrom-Json
        return [bool]($credential.a -and $credential.t -and $credential.s)
    } catch {
        return $false
    }
}

function Update-NEEM {
    $repository = 'https://github.com/Darkguyaiman/NEEM-Stack-Setup.git'
    $archiveUrl = 'https://github.com/Darkguyaiman/NEEM-Stack-Setup/archive/refs/heads/main.zip'
    Write-Rule 'NEEM UPDATE'
    if ((Test-Path -LiteralPath (Join-Path $script:ProjectRoot '.git')) -and
        (Get-Command git -ErrorAction SilentlyContinue)) {
        $changes = @(& git -C $script:ProjectRoot status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Git working tree.' }
        if ($changes.Count) {
            throw 'Local project changes are present. Commit or stash them before running neem --update.'
        }
        Write-Info 'Checking GitHub for updates...'
        Invoke-Step { & git -C $script:ProjectRoot fetch origin main } 'git fetch origin main'
        $current = (& git -C $script:ProjectRoot rev-parse HEAD).Trim()
        $latest = (& git -C $script:ProjectRoot rev-parse origin/main).Trim()
        if ($current -eq $latest) {
            Write-Ok "NEEM v$script:Version is already current."
        } else {
            Invoke-Step { & git -C $script:ProjectRoot merge --ff-only origin/main } 'git merge --ff-only origin/main'
            $newVersion = (Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'VERSION') -Raw).Trim()
            Write-Ok "NEEM was updated to v$newVersion."
        }
    } else {
        Write-Warn 'This copy was downloaded without Git history.'
        if (-not (Confirm-Action "Download the latest files from $repository and replace NEEM program files?")) { return }
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("neem-update-" + [guid]::NewGuid().ToString('N'))
        $archive = Join-Path $tempRoot 'neem-main.zip'
        try {
            New-Item -ItemType Directory -Path $tempRoot | Out-Null
            Write-Info 'Downloading the latest NEEM release files from GitHub...'
            Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing
            Expand-Archive -LiteralPath $archive -DestinationPath $tempRoot -Force
            $source = Get-ChildItem -LiteralPath $tempRoot -Directory |
                Where-Object Name -like 'NEEM-Stack-Setup-*' | Select-Object -First 1
            if (-not $source -or -not (Test-Path -LiteralPath (Join-Path $source.FullName 'VERSION'))) {
                throw 'The downloaded NEEM archive was not valid.'
            }
            foreach ($item in Get-ChildItem -LiteralPath $source.FullName -Force) {
                Copy-Item -LiteralPath $item.FullName -Destination $script:ProjectRoot -Recurse -Force
            }
            $newVersion = (Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'VERSION') -Raw).Trim()
            Write-Ok "NEEM was updated to v$newVersion."
        } finally {
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
    $commandInstaller = Join-Path $script:ProjectRoot 'Install-NEEM-Command.ps1'
    if (Test-Path -LiteralPath $commandInstaller) {
        & $commandInstaller
    }
    Write-Info 'Run neem again to use the updated version.'
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-PackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $script:PackageManager = 'winget'
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        $script:PackageManager = 'choco'
    } else {
        throw 'Install Windows Package Manager (winget) or Chocolatey, then run NEEM again.'
    }
}

function Install-Package {
    param([string]$WingetId, [string]$ChocoId, [string]$Name)
    if ($script:PackageManager -eq 'winget') {
        Invoke-Step { winget install --id $WingetId --exact --accept-package-agreements --accept-source-agreements } "winget install $WingetId"
    } else {
        Invoke-Step { choco install $ChocoId -y } "choco install $ChocoId"
    }
    Write-Ok "$Name installation finished. Open a new terminal if its command is not found yet."
}

function Install-Node {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Ok "Node.js $(& node --version) is already installed."
        return
    }
    Install-Package -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts' -Name 'Node.js'
}

function Install-PM2 {
    Install-Node
    if (Get-Command pm2 -ErrorAction SilentlyContinue) {
        Write-Ok 'PM2 is already installed.'
        return
    }
    Invoke-Step { npm install --global pm2@latest } 'npm install --global pm2@latest'
}

function Install-MySQL {
    if (Get-Command mysql -ErrorAction SilentlyContinue) {
        Write-Ok 'A MySQL client is already installed.'
        return
    }
    Install-Package -WingetId 'Oracle.MySQL' -ChocoId 'mysql' -Name 'MySQL'
}

function Install-MySQLWorkbench {
    if ((Test-Path "$env:ProgramFiles\MySQL\MySQL Workbench*\MySQLWorkbench.exe") -or
        (Test-Path "${env:ProgramFiles(x86)}\MySQL\MySQL Workbench*\MySQLWorkbench.exe")) {
        Write-Ok 'MySQL Workbench is already installed.'
        return
    }
    Install-Package -WingetId 'Oracle.MySQLWorkbench' -ChocoId 'mysql.workbench' -Name 'MySQL Workbench'
}

function Install-Nginx {
    if (Get-Command nginx -ErrorAction SilentlyContinue) {
        Write-Ok 'Nginx is already installed.'
        return
    }
    Install-Package -WingetId 'nginxinc.nginx' -ChocoId 'nginx' -Name 'Nginx'
}

function Install-Cloudflared {
    if (Get-CloudflaredPath) {
        Write-Ok 'Cloudflare Tunnel (cloudflared) is already installed.'
        return
    }
    Install-Package -WingetId 'Cloudflare.cloudflared' -ChocoId 'cloudflared' -Name 'Cloudflare Tunnel'
}

function Get-CloudflaredPath {
    $command = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        "$env:ProgramFiles\cloudflared\cloudflared.exe",
        "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe",
        "$env:ProgramData\chocolatey\bin\cloudflared.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetRoot) {
        $match = Get-ChildItem -LiteralPath $wingetRoot -Filter cloudflared.exe -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    return $null
}

function Install-Micro {
    if (Get-Command micro -ErrorAction SilentlyContinue) {
        Write-Ok 'Micro is already installed.'
        return
    }
    Install-Package -WingetId 'zyedidia.micro' -ChocoId 'micro' -Name 'Micro'
}

function Install-Glances {
    if (Get-Command glances -ErrorAction SilentlyContinue) {
        Write-Ok 'Glances is already installed.'
        return
    }
    if (-not (Get-Command py -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
        Install-Package -WingetId 'Python.Python.3.13' -ChocoId 'python313' -Name 'Python'
    }
    $python = if (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
    Invoke-Step { & $python -m pip install --user --upgrade glances } "$python -m pip install --user --upgrade glances"
}

function Install-WinAcme {
    if (Get-WacsPath) {
        Write-Ok 'win-acme is already installed.'
        return
    }
    if ($script:PackageManager -eq 'choco') {
        Install-Package -WingetId '' -ChocoId 'win-acme' -Name 'win-acme'
        return
    }
    $destination = Join-Path $env:ProgramData 'NEEM\win-acme'
    Write-Info 'Downloading the current win-acme release from its official GitHub repository...'
    Invoke-Step {
        $release = Invoke-RestMethod 'https://api.github.com/repos/win-acme/win-acme/releases/latest'
        $asset = $release.assets |
            Where-Object { $_.name -match '^win-acme\..*\.x64\.trimmed\.zip$' } |
            Select-Object -First 1
        if (-not $asset) { throw 'The win-acme x64 release archive was not found.' }
        $archive = Join-Path ([IO.Path]::GetTempPath()) "win-acme-$($release.tag_name).zip"
        Invoke-WebRequest $asset.browser_download_url -OutFile $archive -UseBasicParsing
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Expand-Archive $archive -DestinationPath $destination -Force
        Remove-Item $archive -Force
    } "install win-acme to $destination"
    Write-Ok "win-acme installation finished in $destination."
}

function Install-All {
    $needed = @(Get-ComponentCatalog | Where-Object { $_.Complete -and -not (Test-ComponentInstalled $_) })
    if (-not $needed.Count) {
        Write-Ok 'The complete NEEM stack is already installed. Nothing to do.'
        return
    }
    Write-Rule 'COMPLETE STACK PLAN'
    $needed | ForEach-Object { Write-Theme -Text "  + $($_.Name)" -Role Primary }
    Write-Theme -Text "  $($needed.Count) missing component(s) will be installed; existing tools are skipped." -Role Muted
    if (-not (Confirm-Action 'Install the missing components?')) { return }
    foreach ($item in $needed) {
        Write-Rule $item.Name
        $command = $item.Install
        & $command
    }
    Write-Ok 'The NEEM stack is installed.'
}

function Uninstall-Package {
    param([string]$WingetId, [string]$ChocoId, [string]$Name)
    if ($script:PackageManager -eq 'winget') {
        Invoke-Step { winget uninstall --id $WingetId --exact --accept-source-agreements } "winget uninstall $WingetId"
    } else {
        Invoke-Step { choco uninstall $ChocoId -y } "choco uninstall $ChocoId"
    }
    Write-Ok "$Name removal finished."
}

function Remove-Node { Uninstall-Package -WingetId 'OpenJS.NodeJS.LTS' -ChocoId 'nodejs-lts' -Name 'Node.js' }
function Remove-PM2 { Invoke-Step { npm uninstall --global pm2 } 'npm uninstall --global pm2'; Write-Ok 'PM2 removal finished.' }
function Remove-MySQL {
    Write-Warn 'The MySQL package will be removed; existing databases and configuration are intentionally retained.'
    Uninstall-Package -WingetId 'Oracle.MySQL' -ChocoId 'mysql' -Name 'MySQL'
}
function Remove-MySQLWorkbench { Uninstall-Package -WingetId 'Oracle.MySQLWorkbench' -ChocoId 'mysql.workbench' -Name 'MySQL Workbench' }
function Remove-Nginx { Uninstall-Package -WingetId 'nginxinc.nginx' -ChocoId 'nginx' -Name 'Nginx' }
function Remove-Cloudflared {
    $cloudflared = Get-CloudflaredPath
    $service = Get-Service -Name cloudflared -ErrorAction SilentlyContinue
    if ($service -and $cloudflared) {
        Invoke-Step { & $cloudflared service uninstall } 'cloudflared service uninstall'
    }
    Uninstall-Package -WingetId 'Cloudflare.cloudflared' -ChocoId 'cloudflared' -Name 'Cloudflare Tunnel'
}
function Remove-Micro { Uninstall-Package -WingetId 'zyedidia.micro' -ChocoId 'micro' -Name 'Micro' }
function Remove-Glances {
    $python = if (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
    Invoke-Step { & $python -m pip uninstall --yes glances } "$python -m pip uninstall --yes glances"
    Write-Ok 'Glances removal finished.'
}
function Remove-WinAcme {
    if ($script:PackageManager -eq 'choco') {
        Uninstall-Package -WingetId '' -ChocoId 'win-acme' -Name 'win-acme'
        return
    }
    $destination = Join-Path $env:ProgramData 'NEEM\win-acme'
    if (-not (Test-Path $destination)) { Write-Warn 'The NEEM-managed win-acme folder was not found.'; return }
    Invoke-Step { Remove-Item -LiteralPath $destination -Recurse -Force } "remove $destination"
    Write-Ok 'win-acme removal finished. Existing certificates were left in the Nginx folder.'
}

function Test-Domain([string]$Domain) {
    return $Domain -match '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
}

function Test-Port([string]$Port) {
    $number = 0
    return [int]::TryParse($Port, [ref]$number) -and $number -ge 1 -and $number -le 65535
}

function Get-NginxRoot {
    $command = Get-Command nginx -ErrorAction SilentlyContinue
    if ($command) {
        $candidate = Split-Path (Split-Path $command.Source -Parent) -Parent
        if (Test-Path (Join-Path $candidate 'conf\nginx.conf')) { return $candidate }
        $candidate = Split-Path $command.Source -Parent
        if (Test-Path (Join-Path $candidate 'conf\nginx.conf')) { return $candidate }
    }
    $roots = @(
        'C:\tools',
        "$env:ProgramData\chocolatey\lib\nginx\tools",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
        'C:\nginx'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $match = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -match 'nginx' |
            ForEach-Object {
                if (Test-Path (Join-Path $_.FullName 'conf\nginx.conf')) { $_ }
                else {
                    Get-ChildItem $_.FullName -Directory -Filter 'nginx*' -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path (Join-Path $_.FullName 'conf\nginx.conf') }
                }
            } | Select-Object -First 1
        if ($match) { return $match.FullName }
        if (Test-Path (Join-Path $root 'conf\nginx.conf')) { return $root }
    }
    throw 'Nginx root could not be found. Reopen PowerShell after installing Nginx.'
}

function Get-NginxExe([string]$NginxRoot) {
    $command = Get-Command nginx -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $executable = Join-Path $NginxRoot 'nginx.exe'
    if (Test-Path $executable) { return $executable }
    $executable = Get-ChildItem $NginxRoot -Filter nginx.exe -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($executable) { return $executable }
    throw "nginx.exe was not found below $NginxRoot."
}

function Enable-NginxIncludes([string]$NginxRoot) {
    $mainConfig = Join-Path $NginxRoot 'conf\nginx.conf'
    $content = Get-Content $mainConfig -Raw
    if ($content -match 'conf\.d/\*\.conf') { return }
    $backup = "$mainConfig.backup.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $mainConfig $backup
    $lastBrace = $content.LastIndexOf('}')
    if ($lastBrace -lt 0) { throw "Could not locate the http block in $mainConfig." }
    $updated = $content.Substring(0, $lastBrace) + "    include conf.d/*.conf;`r`n" + $content.Substring($lastBrace)
    Set-Utf8NoBom -Path $mainConfig -Value $updated
    Write-Info "Enabled conf.d includes; backup: $backup"
}

function Get-PM2Apps {
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        Write-Warn 'PM2 is not installed.'
        return
    }
    Write-Info 'Current PM2 applications:'
    try {
        $apps = (& pm2 jlist 2>$null | Out-String | ConvertFrom-Json)
        if (-not $apps) { Write-Host '  (no processes)' }
        foreach ($app in $apps) {
            Write-Host "  $($app.pm_id): $($app.name) [$($app.pm2_env.status)]"
        }
    } catch {
        Write-Warn 'Unable to parse the PM2 process list.'
    }
}

function Test-Dns([string]$Domain) {
    try {
        $resolved = [Net.Dns]::GetHostAddresses($Domain) |
            Where-Object AddressFamily -eq InterNetwork |
            Select-Object -First 1 -ExpandProperty IPAddressToString
        if ($resolved) { Write-Info "$Domain resolves to $resolved."; return $true }
    } catch {}
    Write-Warn "$Domain does not currently return an IPv4 address."
    return $false
}

function Write-NginxSite {
    param([string]$Domain, [int]$Port, [bool]$IncludeWww)
    $root = Get-NginxRoot
    $nginxExe = Get-NginxExe $root
    $configDir = Join-Path $root 'conf\conf.d'
    $webroot = Join-Path $root 'html'
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    Enable-NginxIncludes $root
    $names = if ($IncludeWww) { "$Domain www.$Domain" } else { $Domain }
    $config = @"
# Managed by NEEM Stack Setup
server {
    listen 80;
    server_name $names;

    location ^~ /.well-known/acme-challenge/ {
        root $($webroot.Replace('\', '/'));
        default_type text/plain;
    }

    location / {
        proxy_pass http://127.0.0.1:$Port;
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 60s;
    }
}
"@
    $target = Join-Path $configDir "neem-$Domain.conf"
    $backup = $null
    if (Test-Path $target) {
        $backup = "$target.backup.$(Get-Date -Format yyyyMMddHHmmss)"
        Copy-Item $target $backup
    }
    Set-Utf8NoBom -Path $target -Value $config
    try {
        Invoke-Step { & $nginxExe -t -p "$root\" } "nginx -t -p `"$root\`""
    } catch {
        if ($backup) { Copy-Item $backup $target -Force } else { Remove-Item $target -Force }
        throw "Nginx rejected the generated site. The previous configuration was restored. $($_.Exception.Message)"
    }
    $nginxProcesses = Get-Process nginx -ErrorAction SilentlyContinue
    if ($nginxProcesses) {
        Invoke-Step { & $nginxExe -s reload -p "$root\" } 'nginx -s reload'
    } else {
        Invoke-Step { Start-Process -FilePath $nginxExe -WorkingDirectory $root -WindowStyle Hidden } 'start nginx'
    }
    Write-Ok "Nginx now proxies http://$Domain to http://127.0.0.1:$Port."
}

function Get-WacsPath {
    $command = Get-Command wacs -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $roots = @(
        "$env:ProgramData\NEEM\win-acme",
        "$env:ProgramData\chocolatey",
        "$env:ProgramFiles\win-acme",
        'C:\tools'
    )
    foreach ($root in $roots) {
        if (Test-Path $root) {
            $match = Get-ChildItem $root -Filter wacs.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }
    return $null
}

function Enable-Ssl {
    param([string]$Domain, [Nullable[bool]]$IncludeWww)
    if (-not $Domain) { $Domain = Read-Host 'Domain name' }
    if (-not (Test-Domain $Domain)) { throw "Invalid domain name: $Domain" }
    if ($null -eq $IncludeWww) { $IncludeWww = Confirm-Action "Include www.$Domain?" }
    $email = Read-Host 'Email for expiry and security notices'
    if ($email -notmatch '@') { throw 'Please enter a valid email address.' }
    [void](Test-Dns $Domain)
    if ($IncludeWww) { [void](Test-Dns "www.$Domain") }
    Install-WinAcme

    $nginxRoot = Get-NginxRoot
    $nginxExe = Get-NginxExe $nginxRoot
    $certDir = Join-Path $nginxRoot 'conf\certificates'
    $reloadScript = Join-Path $nginxRoot 'conf\neem-reload-nginx.ps1'
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null
    $reloadContent = @"
& '$($nginxExe.Replace("'", "''"))' -s reload -p '$($nginxRoot.Replace("'", "''"))\'
"@
    Set-Utf8NoBom -Path $reloadScript -Value $reloadContent

    $hosts = if ($IncludeWww) { "$Domain,www.$Domain" } else { $Domain }
    $wacs = Get-WacsPath
    if (-not $wacs) { throw 'win-acme was installed but wacs.exe was not found. Reopen PowerShell and try again.' }
    $arguments = @(
        '--source', 'manual', '--host', $hosts,
        '--validation', 'filesystem', '--webroot', (Join-Path $nginxRoot 'html'),
        '--store', 'pemfiles', '--pemfilespath', $certDir, '--pemfilesname', $Domain,
        '--installation', 'script', '--script', $reloadScript,
        '--emailaddress', $email, '--accepttos'
    )
    Invoke-Step { & $wacs @arguments } "wacs.exe (request certificate for $hosts)"
    if ($DryRun) { return }

    $chain = Join-Path $certDir "$Domain-chain.pem"
    $key = Join-Path $certDir "$Domain-key.pem"
    if (-not (Test-Path $chain) -or -not (Test-Path $key)) {
        throw "Certificate files were not created in $certDir."
    }
    $site = Join-Path $nginxRoot "conf\conf.d\neem-$Domain.conf"
    if (-not (Test-Path $site)) {
        throw "Configure the domain in NEEM before enabling SSL ($site is missing)."
    }
    $current = Get-Content $site -Raw
    $names = if ($IncludeWww) { "$Domain www.$Domain" } else { $Domain }
    $https = @"
# Managed by NEEM Stack Setup
server {
    listen 80;
    server_name $names;
    location ^~ /.well-known/acme-challenge/ { root $((Join-Path $nginxRoot 'html').Replace('\', '/')); }
    location / { return 301 https://`$host`$request_uri; }
}
server {
    listen 443 ssl;
    server_name $names;
    ssl_certificate $($chain.Replace('\', '/'));
    ssl_certificate_key $($key.Replace('\', '/'));
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:$(([regex]::Match($current, '127\.0\.0\.1:(\d+)')).Groups[1].Value);
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
"@
    $backup = "$site.backup.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $site $backup
    Set-Utf8NoBom -Path $site -Value $https
    try {
        Invoke-Step { & $nginxExe -t -p "$nginxRoot\" } 'validate HTTPS configuration'
    } catch {
        Copy-Item $backup $site -Force
        throw "Nginx rejected the HTTPS configuration. The HTTP configuration was restored. $($_.Exception.Message)"
    }
    Invoke-Step { & $nginxExe -s reload -p "$nginxRoot\" } 'reload Nginx'
    Write-Ok "HTTPS is enabled for $Domain. win-acme registered automatic renewal."
}

function Connect-Domain {
    Install-Nginx
    Get-PM2Apps
    $app = Read-Host 'PM2 app name or id (for your reference)'
    if ($app -and (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        & pm2 describe $app *> $null
        if ($LASTEXITCODE -ne 0) { Write-Warn 'That PM2 process was not found; continuing with a manual port.' }
    }
    $port = Read-Host 'Local port used by the app (for example 3000)'
    if (-not (Test-Port $port)) { throw 'Port must be between 1 and 65535.' }
    $domain = Read-Host 'Domain name (for example app.example.com)'
    if (-not (Test-Domain $domain)) { throw "Invalid domain name: $domain" }
    $www = Confirm-Action "Also serve www.$domain?"
    try {
        Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 3 | Out-Null
    } catch {
        Write-Warn "Nothing answered over HTTP on 127.0.0.1:$port."
        if (-not (Confirm-Action 'Write the Nginx configuration anyway?')) { return }
    }
    [void](Test-Dns $domain)
    Write-NginxSite -Domain $domain -Port ([int]$port) -IncludeWww $www
    if (Confirm-Action "Apply a free Let's Encrypt SSL certificate now?") {
        Enable-Ssl -Domain $domain -IncludeWww $www
    } else {
        Write-Info "Choose 'Enable SSL' later after DNS points to this server."
    }
}

function Set-PM2Startup {
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) { throw 'Install PM2 first.' }
    Invoke-Step { pm2 save } 'pm2 save'
    Write-Warn 'PM2 does not ship a native Windows startup integration.'
    Write-Info 'Use a Windows service wrapper or the PM2 Windows startup package approved by your organization.'
}

function Get-QuickTunnelStateRoot {
    $root = Join-Path $env:LOCALAPPDATA 'NEEM\quick-tunnels'
    if (-not $DryRun) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    return $root
}

function Get-RunningQuickTunnels {
    $root = Get-QuickTunnelStateRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $running = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.quick.json' -File -ErrorAction SilentlyContinue) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $process = Get-Process -Id ([int]$state.Pid) -ErrorAction SilentlyContinue
            $sameStart = $process -and $state.ProcessStartTime -and
                $process.StartTime.ToUniversalTime().Ticks -eq [long]$state.ProcessStartTime
            if ($process -and $process.ProcessName -eq 'cloudflared' -and $sameStart) {
                $state | Add-Member -NotePropertyName StateFile -NotePropertyValue $file.FullName -Force
                $state
            } else {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    return @($running)
}

function Start-BackgroundQuickTunnel {
    param([Parameter(Mandatory)][string]$Cloudflared, [Parameter(Mandatory)][string]$Origin, [Parameter(Mandatory)][int]$Port)
    if ($DryRun) {
        Write-Theme -Text '  https://example.trycloudflare.com' -Role Primary
        return
    }
    $root = Get-QuickTunnelStateRoot
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $stdout = Join-Path $root "$stamp.out.log"
    $stderr = Join-Path $root "$stamp.err.log"
    $process = Start-Process -FilePath $Cloudflared -ArgumentList @('tunnel','--url',$Origin) `
        -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $url = $null
    $spinner = @('|','/','-','\')
    if ([Console]::IsOutputRedirected) { Write-Host '  Creating Quick Tunnel...' }
    for ($attempt = 0; $attempt -lt 45 -and -not $url; $attempt++) {
        if (-not [Console]::IsOutputRedirected) {
            Write-Host ("`r  Creating Quick Tunnel... {0}" -f $spinner[$attempt % $spinner.Count]) -NoNewline
        }
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { break }
        $text = ''
        if (Test-Path -LiteralPath $stdout) { $text += Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderr) { $text += Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue }
        $match = [regex]::Match($text, 'https://[a-z0-9-]+\.trycloudflare\.com', 'IgnoreCase')
        if ($match.Success) { $url = $match.Value }
    }
    if (-not [Console]::IsOutputRedirected) {
        Write-Host ("`r" + (' ' * 48) + "`r") -NoNewline
    }
    if (-not $url) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        throw "Cloudflare did not return a Quick Tunnel URL. Diagnostics: $stderr"
    }
    $stateFile = Join-Path $root "$($process.Id).quick.json"
    [pscustomobject]@{
        Type = 'Quick'
        Pid = $process.Id
        ProcessStartTime = $process.StartTime.ToUniversalTime().Ticks
        Port = $Port
        Origin = $Origin
        Url = $url
        StartedAt = (Get-Date).ToString('o')
        StdoutLog = $stdout
        StderrLog = $stderr
    } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Write-Host ''
    Write-Theme -Text "  $url" -Role Primary
    Write-Theme -Text '  Running in the background. Return here and choose option 3 to stop it.' -Role Muted
}

function Save-ManagedTunnelState {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Origin,
        [AllowNull()][AllowEmptyString()][string]$PublishedAt = '__NOW__'
    )
    $path = Join-Path (Get-QuickTunnelStateRoot) 'managed.json'
    $value = [pscustomobject]@{
        Type = 'Managed'
        Port = $Port
        Origin = $Origin
        Url = "https://$Hostname"
        PublishedAt = if ($PublishedAt -eq '__NOW__') { (Get-Date).ToString('o') } elseif ($PublishedAt) { $PublishedAt } else { $null }
    } | ConvertTo-Json
    Set-Utf8NoBom -Path $path -Value $value
}

function Complete-ManagedTunnelMetadata {
    Write-Warn 'This managed service predates NEEM tunnel tracking, so its hostname and port are not stored locally.'
    if (-not (Confirm-Action 'Add its display details now?')) { return $false }
    do {
        $managedPort = Read-Host 'Local application port used by this tunnel'
        if (-not (Test-Port $managedPort)) { Write-Warn 'Port must be between 1 and 65535. Please try again.' }
    } until (Test-Port $managedPort)
    do {
        $managedHostname = Read-Host 'Public hostname (for example app.example.com)'
        if (-not (Test-Domain $managedHostname)) { Write-Warn 'That hostname is invalid. Please try again.' }
    } until (Test-Domain $managedHostname)
    while ($true) {
        $publishedInput = Read-Host 'Published date/time (for example 2026-08-09 22:35, or Enter if unknown)'
        if (-not $publishedInput) { $publishedAt = $null; break }
        $parsedDate = [datetime]::MinValue
        if ([datetime]::TryParse($publishedInput, [ref]$parsedDate)) {
            $publishedAt = $parsedDate.ToString('o')
            break
        }
        Write-Warn 'That date could not be understood. Please try again.'
    }
    Save-ManagedTunnelState -Hostname $managedHostname -Port ([int]$managedPort) `
        -Origin "http://127.0.0.1:$managedPort" -PublishedAt $publishedAt
    Write-Ok 'Managed tunnel details saved.'
    return $true
}

function Get-ManagedTunnelState {
    $service = Get-Service -Name cloudflared -ErrorAction SilentlyContinue
    $path = Join-Path (Get-QuickTunnelStateRoot) 'managed.json'
    if (-not $service -and -not (Test-Path -LiteralPath $path)) { return $null }
    if (Test-Path -LiteralPath $path) {
        try { $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { $state = $null }
    }
    if (-not $state) {
        $state = [pscustomobject]@{ Type='Managed'; Port='?'; Origin='unknown'; Url='Configured in Cloudflare'; PublishedAt=$null }
    }
    $state | Add-Member -NotePropertyName Status -NotePropertyValue $(if ($service) { $service.Status.ToString().ToUpper() } else { 'MISSING' }) -Force
    return $state
}

function Manage-CloudflareTunnels {
    $tunnels = @()
    foreach ($quick in @(Get-RunningQuickTunnels)) {
        $quick | Add-Member -NotePropertyName Status -NotePropertyValue 'RUNNING' -Force
        $tunnels += $quick
    }
    $managed = Get-ManagedTunnelState
    if ($managed -and $managed.Url -eq 'Configured in Cloudflare') {
        if (Complete-ManagedTunnelMetadata) { $managed = Get-ManagedTunnelState }
    }
    if ($managed) { $tunnels += $managed }
    if (-not $tunnels.Count) { Write-Info 'No NEEM Cloudflare Tunnels were found.'; return }
    Write-Rule 'CLOUDFLARE TUNNELS'
    Write-Theme -Text ("  {0,-3} {1,-9} {2,-9} {3,-6} {4,-17} {5}" -f '#','TYPE','STATUS','PORT','PUBLISHED','PUBLIC URL') -Role Selected
    for ($index = 0; $index -lt $tunnels.Count; $index++) {
        $publishedValue = if ($tunnels[$index].Type -eq 'Quick') { $tunnels[$index].StartedAt } else { $tunnels[$index].PublishedAt }
        $published = if ($publishedValue) { ([datetime]$publishedValue).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } else { 'unknown' }
        Write-Theme -Text ("  {0,-3} {1,-9} {2,-9} {3,-6} {4,-17} {5}" -f ($index + 1), $tunnels[$index].Type, $tunnels[$index].Status, $tunnels[$index].Port, $published, $tunnels[$index].Url) -Role Primary
    }
    $choice = Read-Host 'Choose a tunnel to stop/start, A to stop all running tunnels, or Enter to return'
    if (-not $choice) { return }
    if ($choice -match '^[Aa]$') {
        $selected = @($tunnels | Where-Object Status -eq 'RUNNING')
    } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $tunnels.Count) {
        $selected = @($tunnels[[int]$choice - 1])
    } else {
        Write-Warn 'Invalid selection.'
        return
    }
    if (-not $selected.Count) { Write-Info 'No running tunnels were selected.'; return }
    foreach ($tunnel in $selected) {
        if ($tunnel.Type -eq 'Managed') {
            $service = Get-Service -Name cloudflared -ErrorAction SilentlyContinue
            if (-not $service) { Write-Warn 'The managed cloudflared service is missing.'; continue }
            if ($service.Status -eq 'Running') {
                if (Confirm-Action "Stop managed tunnel $($tunnel.Url)?") { Stop-Service cloudflared; Write-Ok "Stopped $($tunnel.Url)." }
            } else {
                if (Confirm-Action "Start managed tunnel $($tunnel.Url)?") { Start-Service cloudflared; Write-Ok "Started $($tunnel.Url)." }
            }
        } else {
            if (-not (Confirm-Action "Stop Quick Tunnel $($tunnel.Url)?")) { continue }
            $process = Get-Process -Id ([int]$tunnel.Pid) -ErrorAction SilentlyContinue
            $sameStart = $process -and $tunnel.ProcessStartTime -and
                $process.StartTime.ToUniversalTime().Ticks -eq [long]$tunnel.ProcessStartTime
            if ($process -and $process.ProcessName -eq 'cloudflared' -and $sameStart) { Stop-Process -Id $process.Id -Force }
            Remove-Item -LiteralPath $tunnel.StateFile -Force -ErrorAction SilentlyContinue
            Write-Ok "Stopped $($tunnel.Url)."
        }
    }
}

function Start-CloudflareTunnelGuide {
    Install-Cloudflared
    $cloudflared = Get-CloudflaredPath
    if (-not $DryRun -and -not $cloudflared) { throw 'cloudflared was installed but its executable could not be found.' }

    Write-Rule 'CLOUDFLARE TUNNEL'
    Write-Theme -Text '  1  Start Quick Tunnel     Run a temporary public URL in the background.' -Role Primary
    Write-Theme -Text '  2  Set up managed tunnel  Production hostname and automatic startup.' -Role Primary
    Write-Theme -Text '  3  View or stop tunnels   Manage Quick and managed tunnels.' -Role Primary
    $mode = if ($DryRun) { '2' } else { Read-Host 'Choose 1, 2, or 3' }
    if ($mode -notin '1','2','3') { Write-Info 'Cloudflare Tunnel setup cancelled.'; return }
    if ($mode -eq '3') { Manage-CloudflareTunnels; return }

    $port = $null
    while ($true) {
        if (-not $port) { $port = Read-Host 'Local application port (for example 3000)' }
        if (-not (Test-Port $port)) {
            Write-Warn 'Port must be between 1 and 65535. Please try again.'
            $port = $null
            continue
        }
        $origin = "http://127.0.0.1:$port"
        if ($DryRun) { break }
        try {
            Invoke-WebRequest "$origin/" -UseBasicParsing -TimeoutSec 3 | Out-Null
            Write-Ok "The local application answered at $origin."
            break
        } catch {
            Write-Warn "Nothing answered over HTTP at $origin."
            $retry = Read-Host "Press Enter or R to retry, type a new port, A to continue anyway, or C to cancel"
            if ($retry -match '^[Aa]$') { break }
            if ($retry -match '^[Cc]$') { Write-Info 'Cloudflare Tunnel setup cancelled.'; return }
            if ($retry -and $retry -notmatch '^[Rr]$') { $port = $retry }
        }
    }

    if ($mode -eq '1') {
        Start-BackgroundQuickTunnel -Cloudflared $cloudflared -Origin $origin -Port ([int]$port)
        return
    }

    do {
        $hostname = Read-Host 'Public hostname to use (for example app.example.com)'
        if (-not (Test-Domain $hostname)) { Write-Warn 'That hostname is invalid. Please try this step again.' }
    } until (Test-Domain $hostname)

    Write-Theme -Text '  In the Cloudflare dashboard:' -Role Primary
    Write-Theme -Text '  1. Open Networking > Tunnels and create a Cloudflared tunnel.' -Role Muted
    Write-Theme -Text '  2. Select this machine''s operating system.' -Role Muted
    Write-Theme -Text '  3. Copy the complete cloudflared service install command.' -Role Muted
    Write-Theme -Text '  One cloudflared service can serve several published routes on this machine.' -Role Muted
    if (-not $DryRun -and (Confirm-Action 'Open the Cloudflare Tunnels dashboard now?')) {
        Start-Process 'https://one.dash.cloudflare.com/'
    }

    if ($DryRun) {
        Invoke-SecretStep { } 'cloudflared service install <TUNNEL_TOKEN hidden>'
        Write-Info 'Dry run complete. No token was requested and no service was installed.'
        return
    }

    $token = $null
    while (-not $token) {
        Write-Info 'Press Ctrl+Shift+V (or right-click) to paste, then press Enter. The value stays hidden.'
        $secureToken = Read-HiddenPasteInput 'Paste the token or full install command:'
        if ($secureToken.Length -gt 0) { Write-Ok 'Paste received. Validating token...' }
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        try {
            $pastedValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            $tokenMatch = [regex]::Match($pastedValue, 'eyJ[A-Za-z0-9_-]{20,}')
            if ($tokenMatch.Success -and (Test-CloudflareTunnelToken $tokenMatch.Value)) {
                $token = $tokenMatch.Value
            } else {
                Write-Warn 'No valid Cloudflare Tunnel token was found. Copy a fresh install command and retry this step.'
            }
        } finally {
            if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
            $pastedValue = $null
            $tokenMatch = $null
            $secureToken = $null
        }
    }
    try {
        $existing = Get-Service -Name cloudflared -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Warn 'A cloudflared service is already installed on this machine.'
            if (-not (Confirm-Action 'Replace it with this tunnel token?')) { return }
            Invoke-Step { & $cloudflared service uninstall } 'cloudflared service uninstall'
        }
        Invoke-SecretStep { & $cloudflared service install $token } 'cloudflared service install <TUNNEL_TOKEN hidden>'
    } finally {
        $token = $null
    }

    $service = Get-Service -Name cloudflared -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Running') { Start-Service cloudflared; $service.Refresh() }
        Write-Ok "Cloudflare Tunnel is installed as a Windows service ($($service.Status))."
    } else {
        Write-Warn 'The install command finished, but the cloudflared service was not detected.'
    }
    Write-Rule 'ADD THE PUBLIC HOSTNAME'
    Write-Theme -Text '  Return to the tunnel in the Cloudflare dashboard, then:' -Role Primary
    Write-Theme -Text '  1. Continue to Routes and choose Add route > Published application.' -Role Muted
    Write-Theme -Text "  2. Set Hostname to $hostname." -Role Muted
    Write-Theme -Text "  3. Set Service URL to $origin." -Role Muted
    Write-Theme -Text '  4. Save the route.' -Role Muted
    if (Confirm-Action 'Open the Cloudflare dashboard again?') { Start-Process 'https://one.dash.cloudflare.com/' }
    [void](Read-Host 'Press Enter after the published application route is saved')
    Save-ManagedTunnelState -Hostname $hostname -Port ([int]$port) -Origin $origin
    Write-Ok 'Cloudflare Tunnel configuration finished.'
    Write-Theme -Text "  https://$hostname" -Role Primary
    Write-Info 'Cloudflare may need a short time before a newly created hostname becomes reachable.'
}

function Show-Health {
    Clear-Host
    Show-Brand
    $checks = @(
        [pscustomobject]@{ Name='Node.js'; Probe='node' }
        [pscustomobject]@{ Name='npm'; Probe='npm' }
        [pscustomobject]@{ Name='PM2'; Probe='pm2' }
        [pscustomobject]@{ Name='MySQL'; Probe='mysql' }
        [pscustomobject]@{ Name='MySQL Workbench'; Probe='workbench' }
        [pscustomobject]@{ Name='Nginx'; Probe='nginx' }
        [pscustomobject]@{ Name='Cloudflare Tunnel'; Probe='cloudflared' }
        [pscustomobject]@{ Name='Micro'; Probe='micro' }
        [pscustomobject]@{ Name='Glances'; Probe='glances' }
        [pscustomobject]@{ Name='win-acme'; Probe='wacs' }
    )
    $rows = foreach ($item in $checks) {
        $path = Get-ComponentPath $item
        [pscustomobject]@{ Name=$item.Name; Installed=[bool]$path; Path=$path }
    }
    $ready = @($rows | Where-Object Installed).Count
    Write-Rule 'STACK HEALTH'
    Write-Theme -Text ("  {0} of {1} components ready" -f $ready, $rows.Count) -Role Primary
    Write-Theme -Text ("  {0,-10} {1,-19} {2}" -f 'STATE', 'COMPONENT', 'LOCATION') -Role Selected
    foreach ($row in $rows) {
        if ($row.Installed) {
            $maxPath = [Math]::Max(24, $Host.UI.RawUI.WindowSize.Width - 38)
            $path = [string]$row.Path
            if ($path.Length -gt $maxPath) { $path = '...' + $path.Substring($path.Length - ($maxPath - 3)) }
            Write-Theme -Text ("  {0,-10} {1,-19} {2}" -f 'READY', $row.Name, $path) -Role Secondary
        } else {
            Write-Theme -Text ("  {0,-10} {1,-19} {2}" -f 'MISSING', $row.Name, 'not installed') -Role Muted
        }
    }

    if (Get-Command pm2 -ErrorAction SilentlyContinue) {
        Write-Host ''
        Write-Rule 'PM2 APPLICATIONS'
        try {
            $apps = @(& pm2 jlist 2>$null | Out-String | ConvertFrom-Json)
            if (-not $apps.Count) {
                Write-Theme -Text '  No PM2 applications are running.' -Role Muted
            } else {
                Write-Theme -Text ("  {0,-4} {1,-22} {2,-10} {3,7} {4,10}" -f 'ID','NAME','STATUS','CPU','MEMORY') -Role Selected
                foreach ($app in $apps) {
                    $memory = '{0:N1} MB' -f ([double]$app.monit.memory / 1MB)
                    Write-Theme -Text ("  {0,-4} {1,-22} {2,-10} {3,6}% {4,10}" -f
                        $app.pm_id, $app.name, $app.pm2_env.status, $app.monit.cpu, $memory) -Role Secondary
                }
            }
        } catch {
            Write-Theme -Text '  Process list unavailable in this Windows session.' -Role Muted
        }
    }

    if (Get-Command nginx -ErrorAction SilentlyContinue) {
        try {
            $root = Get-NginxRoot
            $nginxExe = Get-NginxExe $root
            $validation = & $nginxExe -t -p "$root\" 2>&1
            if ($LASTEXITCODE -eq 0) { Write-Ok 'Nginx configuration is valid.' }
            else { Write-Warn ($validation -join ' ') }
        } catch {
            Write-Warn $_.Exception.Message
        }
    }
}

function Select-MySQLDatabase {
    param(
        [Parameter(Mandatory)][string[]]$Databases,
        [Parameter(Mandatory)][string]$Title
    )
    if (-not $Databases.Count) { return $null }
    $cursor = 0
    $start = 0
    Clear-Host
    Show-Brand
    Write-Rule $Title
    Write-Theme -Text '  Up/Down move  |  Enter select  |  Esc cancel' -Role Muted
    Write-Host ''
    $listTop = $Host.UI.RawUI.CursorPosition.Y
    $visible = [Math]::Min($Databases.Count, [Math]::Max(5, $Host.UI.RawUI.WindowSize.Height - $listTop - 2))
    $maxName = [Math]::Max(20, $Host.UI.RawUI.WindowSize.Width - 10)
    $render = {
        if ($cursor -lt $start) { $start = $cursor }
        if ($cursor -ge $start + $visible) { $start = $cursor - $visible + 1 }
        try { $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $listTop) } catch {}
        for ($offset = 0; $offset -lt $visible; $offset++) {
            $index = $start + $offset
            if ($index -ge $Databases.Count) { Write-Host (' ' * [Math]::Max(1, $maxName)); continue }
            $label = [string]$Databases[$index]
            if ($label.Length -gt $maxName) { $label = $label.Substring(0, $maxName - 3) + '...' }
            $pointer = if ($index -eq $cursor) { '>' } else { ' ' }
            $role = if ($index -eq $cursor) { 'Selected' } else { 'Primary' }
            Write-Theme -Text ("  {0} {1,-$maxName}" -f $pointer, $label) -Role $role
        }
        Write-Theme -Text ("      Database {0} of {1}" -f ($cursor + 1), $Databases.Count) -Role Secondary
    }
    & $render
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { $cursor = ($cursor - 1 + $Databases.Count) % $Databases.Count }
            40 { $cursor = ($cursor + 1) % $Databases.Count }
            13 { return [string]$Databases[$cursor] }
            27 { return $null }
        }
        & $render
    }
}

function Resolve-BackupDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = $Path.Trim()
    if (($resolvedPath.StartsWith('"') -and $resolvedPath.EndsWith('"')) -or
        ($resolvedPath.StartsWith("'") -and $resolvedPath.EndsWith("'"))) {
        $resolvedPath = $resolvedPath.Substring(1, $resolvedPath.Length - 2)
    }
    $resolvedPath = [Environment]::ExpandEnvironmentVariables($resolvedPath)
    if ($resolvedPath -eq '~') {
        $resolvedPath = [Environment]::GetFolderPath('UserProfile')
    } elseif ($resolvedPath -match '^~[\\/](.*)$') {
        $resolvedPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) $Matches[1]
    }
    if ($env:OS -eq 'Windows_NT') {
        if ($resolvedPath -match '^/mnt/([A-Za-z])(?:/(.*))?$') {
            $tail = if ($Matches[2]) { $Matches[2] } else { '' }
            $resolvedPath = '{0}:/{1}' -f $Matches[1].ToUpperInvariant(), $tail
        } elseif ($resolvedPath -match '^/([A-Za-z])(?:/(.*))?$') {
            $tail = if ($Matches[2]) { $Matches[2] } else { '' }
            $resolvedPath = '{0}:/{1}' -f $Matches[1].ToUpperInvariant(), $tail
        }
    }
    return [IO.Path]::GetFullPath($resolvedPath)
}

function Backup-MySQLDatabase {
    $mysql = (Get-Command mysql -ErrorAction SilentlyContinue).Source
    if (-not $mysql) { $mysql = (Get-Command mariadb -ErrorAction SilentlyContinue).Source }
    $dump = (Get-Command mysqldump -ErrorAction SilentlyContinue).Source
    if (-not $dump) { $dump = (Get-Command mariadb-dump -ErrorAction SilentlyContinue).Source }
    if ($DryRun) {
        if (-not $mysql) { $mysql = 'mysql' }
        if (-not $dump) { $dump = 'mysqldump' }
    }
    if (-not $mysql -or -not $dump) { throw 'MySQL client tools were not found. Install MySQL or MariaDB first.' }

    Clear-Host
    Show-Brand
    Write-Rule 'STEP 1 OF 6 | CONNECT TO MYSQL'
    Write-Theme -Text '  Enter the MySQL connection used to discover databases.' -Role Primary
    Write-Theme -Text '  Press Enter to accept a value shown in brackets.' -Role Muted
    Write-Host ''
    if ($DryRun) {
        $hostName = '127.0.0.1'; $port = 3306; $user = 'mysql-user'; $database = 'chosen_database'; $includeSchema = $true
        Write-Info 'Dry run uses placeholders and does not connect to MySQL.'
        Write-Rule 'STEP 2 OF 6 | CHOOSE A DATABASE'
        Write-Info 'Would open the Up/Down database picker.'
        Write-Rule 'STEP 3 OF 6 | CHOOSE BACKUP CONTENT'
        Write-Info 'Would include CREATE statements (recommended).'
    } else {
        $hostName = Read-Host 'MySQL host [127.0.0.1]'
        if (-not $hostName) { $hostName = '127.0.0.1' }
        $portText = Read-Host 'MySQL port [3306]'
        if (-not $portText) { $portText = '3306' }
        $port = 0
        if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Port must be between 1 and 65535.' }
        $user = Read-Host 'MySQL user [root]'
        if (-not $user) { $user = 'root' }
        $connectionArgs = @("--host=$hostName", "--port=$port", "--user=$user", '--password', '--protocol=TCP')
        Write-Info 'MySQL will ask for the password without displaying it.'
        $global:LASTEXITCODE = 0
        $databases = @(& $mysql @connectionArgs '--batch' '--skip-column-names' '--execute=SHOW DATABASES' |
            Where-Object { $_ -and $_ -notin @('information_schema','performance_schema','mysql','sys') })
        if ($LASTEXITCODE -ne 0) { throw 'Could not list databases. Check the connection and credentials.' }
        if (-not $databases.Count) { throw 'No user databases were returned.' }
        $database = Select-MySQLDatabase -Databases $databases -Title 'STEP 2 OF 6 | CHOOSE A DATABASE'
        if (-not $database) { Write-Info 'Backup cancelled. No file was created.'; return }
        Clear-Host
        Show-Brand
        Write-Rule 'STEP 3 OF 6 | CHOOSE BACKUP CONTENT'
        Write-Theme -Text "  Selected database: $database" -Role Primary
        Write-Theme -Text '  CREATE statements include the database structure, routines, events, and triggers.' -Role Muted
        Write-Theme -Text '  Choose No only when the destination schema already exists.' -Role Muted
        Write-Host ''
        $includeSchema = (Read-Host 'Include CREATE statements? [Y/n]') -notmatch '^[Nn]$'
    }

    $safeDatabase = $database -replace '[^A-Za-z0-9_.-]', '_'
    $fileName = '{0}-{1}.sql' -f $safeDatabase, (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backupDirectory = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'NEEM Backups'
    Write-Rule 'STEP 4 OF 6 | CHOOSE SAVE LOCATION'
    Write-Theme -Text "  The dump will be named: $fileName" -Role Primary
    Write-Theme -Text '  Windows and Unix-style paths are accepted. Press Enter to use the default.' -Role Muted
    if ($DryRun) {
        Write-Info "Would use destination directory: $backupDirectory"
    } else {
        $answer = Read-Host "Destination directory [$backupDirectory]"
        if ($answer) { $backupDirectory = Resolve-BackupDirectory -Path $answer }
        else { $backupDirectory = Resolve-BackupDirectory -Path $backupDirectory }
        if (Test-Path -LiteralPath $backupDirectory -PathType Leaf) {
            throw "The destination is a file, not a directory: $backupDirectory"
        }
    }
    $finalFile = Join-Path $backupDirectory $fileName
    $partialFile = "$finalFile.partial"
    $dumpArgs = @("--host=$hostName", "--port=$port", "--user=$user", '--password', '--protocol=TCP',
        '--default-character-set=utf8mb4', '--single-transaction', '--quick', '--hex-blob',
        '--complete-insert', '--skip-lock-tables', '--skip-comments', '--tz-utc')
    $helpText = (& $dump --help 2>$null | Out-String)
    if ($helpText.Contains('--no-tablespaces')) { $dumpArgs += '--no-tablespaces' }
    if ($helpText.Contains('--set-gtid-purged')) { $dumpArgs += '--set-gtid-purged=OFF' }
    if ($helpText.Contains('--column-statistics')) { $dumpArgs += '--column-statistics=0' }
    if ($includeSchema) { $dumpArgs += @('--routines', '--events', '--triggers', '--databases', $database) }
    else { $dumpArgs += @('--no-create-info', '--skip-triggers', $database) }

    Write-Rule 'STEP 5 OF 6 | CREATE AND VALIDATE DUMP'
    Write-Theme -Text '  For safety, MySQL asks for the password again before writing the dump.' -Role Muted
    Write-Theme -Text "> $([IO.Path]::GetFileName($dump)) <portable options> --result-file=`"$partialFile`" $database" -Role Accent
    if ($DryRun) {
        Write-Info "Would create: $finalFile"
    } else {
        [void](New-Item -ItemType Directory -Path $backupDirectory -Force)
        Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
        & $dump @dumpArgs "--result-file=$partialFile"
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
            throw 'Backup failed; the incomplete dump was removed.'
        }
        try {
            $bytes = [IO.File]::ReadAllBytes($partialFile)
            if (-not $bytes.Length) { throw 'The dump is empty.' }
            [void]([Text.UTF8Encoding]::new($false, $true).GetString($bytes))
        } catch {
            Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
            throw 'Backup validation failed; the incomplete dump was removed.'
        }
        Move-Item -LiteralPath $partialFile -Destination $finalFile
        Write-Ok "Validated UTF-8 dump created: $finalFile"
    }

    Write-Rule 'STEP 6 OF 6 | DOWNLOAD THE DUMP'
    Write-Theme -Text '  Tell us how this server is reached over SSH, then run the matching command' -Role Muted
    Write-Theme -Text '  on the computer that should receive the file.' -Role Muted
    Write-Host ''
    $sshHost = $env:COMPUTERNAME
    $sshUser = $env:USERNAME
    if (-not $DryRun) {
        $answer = Read-Host "SSH address clients use for this server [$sshHost]"
        if ($answer) { $sshHost = $answer }
        $answer = Read-Host "SSH user [$sshUser]"
        if ($answer) { $sshUser = $answer }
    }
    $remotePath = $finalFile.Replace('\', '/')
    $source = "${sshUser}@${sshHost}:$remotePath"
    Write-Host ''
    Write-Theme -Text '  Windows PowerShell:' -Role Primary
    Write-Theme -Text "  scp `"$source`" `"`$HOME\Downloads\`"" -Role Secondary
    Write-Theme -Text '  macOS:' -Role Primary
    Write-Theme -Text "  scp `"$source`" ~/Downloads/" -Role Secondary
    Write-Theme -Text '  Linux:' -Role Primary
    Write-Theme -Text "  scp `"$source`" ~/Downloads/" -Role Secondary
    Write-Info 'Run the matching command on the computer that will receive the file.'
}

function Select-MySQLUserAction {
    $actions = @(
        [pscustomobject]@{ Id='database'; Label='Create user for one database'; Hint='Grant full access to one selected database.' }
        [pscustomobject]@{ Id='all'; Label='Create user for all databases'; Hint='Grant full access across the entire MySQL server.' }
        [pscustomobject]@{ Id='list'; Label='View MySQL users'; Hint='List each MySQL account and its allowed connection host.' }
        [pscustomobject]@{ Id='return'; Label='Return to main menu'; Hint='Leave MySQL user management without changes.' }
    )
    $cursor = 0
    Clear-Host
    Show-Brand
    Write-Rule 'MANAGE MYSQL USERS'
    Write-Theme -Text '  Up/Down move  |  Enter select  |  Esc return' -Role Muted
    Write-Host ''
    $listTop = $Host.UI.RawUI.CursorPosition.Y
    $render = {
        try { $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $listTop) } catch {}
        for ($index = 0; $index -lt $actions.Count; $index++) {
            $pointer = if ($index -eq $cursor) { '>' } else { ' ' }
            $role = if ($index -eq $cursor) { 'Selected' } elseif ($actions[$index].Id -eq 'return') { 'Muted' } else { 'Primary' }
            Write-Theme -Text ("  {0} {1,-40}" -f $pointer, $actions[$index].Label) -Role $role
        }
        Write-Theme -Text ("      {0,-68}" -f $actions[$cursor].Hint) -Role Secondary
    }
    & $render
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { $cursor = ($cursor - 1 + $actions.Count) % $actions.Count }
            40 { $cursor = ($cursor + 1) % $actions.Count }
            13 { return $actions[$cursor].Id }
            27 { return 'return' }
        }
        & $render
    }
}

function Show-MySQLUsers {
    $mysql = (Get-Command mysql -ErrorAction SilentlyContinue).Source
    if (-not $mysql) { $mysql = (Get-Command mariadb -ErrorAction SilentlyContinue).Source }
    if ($DryRun -and -not $mysql) { $mysql = 'mysql' }
    if (-not $mysql) { throw 'MySQL client tools were not found. Install MySQL or MariaDB first.' }
    Clear-Host
    Show-Brand
    Write-Rule 'VIEW MYSQL USERS'
    Write-Theme -Text '  MySQL identifies an account by both its user and allowed host.' -Role Muted
    Write-Host ''
    if ($DryRun) { Write-Info 'Would list User and Host from mysql.user.'; return }
    $hostName = Read-Host 'MySQL host [127.0.0.1]'
    if (-not $hostName) { $hostName = '127.0.0.1' }
    $portText = Read-Host 'MySQL port [3306]'
    if (-not $portText) { $portText = '3306' }
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Port must be between 1 and 65535.' }
    $adminUser = Read-Host 'MySQL administrator [root]'
    if (-not $adminUser) { $adminUser = 'root' }
    $connectionArgs = @("--host=$hostName", "--port=$port", "--user=$adminUser", '--password', '--protocol=TCP')
    Write-Info 'MySQL will ask for the administrator password without displaying it.'
    Write-Rule 'ACCOUNTS ON THIS SERVER'
    $global:LASTEXITCODE = 0
    & $mysql @connectionArgs '--table' '--execute=SELECT User AS USER, Host AS ALLOWED_HOST FROM mysql.user ORDER BY User, Host'
    if ($LASTEXITCODE -ne 0) { throw 'MySQL users could not be listed. Use an administrator with permission to read mysql.user.' }
}

function Show-MySQLUserManager {
    while ($true) {
        $pauseAfterAction = $true
        switch (Select-MySQLUserAction) {
            'database' { New-MySQLDatabaseUser -Scope Database }
            'all' { New-MySQLDatabaseUser -Scope All }
            'list' { Show-MySQLUsers }
            'return' { return }
        }
        if (-not $DryRun -and $pauseAfterAction) { [void](Read-Host 'Press Enter to continue') }
    }
}

function New-MySQLDatabaseUser {
    param([ValidateSet('Database','All')][string]$Scope = 'Database')
    $mysql = (Get-Command mysql -ErrorAction SilentlyContinue).Source
    if (-not $mysql) { $mysql = (Get-Command mariadb -ErrorAction SilentlyContinue).Source }
    if ($DryRun -and -not $mysql) { $mysql = 'mysql' }
    if (-not $mysql) { throw 'MySQL client tools were not found. Install MySQL or MariaDB first.' }

    Clear-Host
    Show-Brand
    Write-Rule 'STEP 1 OF 4 | CONNECT TO MYSQL'
    Write-Theme -Text '  Sign in with an account that can create users and grant privileges.' -Role Primary
    Write-Theme -Text '  Press Enter to accept a value shown in brackets.' -Role Muted
    Write-Host ''
    if ($DryRun) {
        $hostName = '127.0.0.1'; $port = 3306; $adminUser = 'root'
        $database = if ($Scope -eq 'All') { 'all databases' } else { 'chosen_database' }
        $newUser = 'app_user'; $allowedHost = 'localhost'; $plainPassword = '<hidden>'
        Write-Info 'Dry run uses placeholders and does not connect to MySQL.'
        if ($Scope -eq 'All') {
            Write-Rule 'STEP 2 OF 4 | CONFIRM SERVER-WIDE ACCESS'
            Write-Warn 'Would grant ALL privileges on *.*.'
        } else {
            Write-Rule 'STEP 2 OF 4 | CHOOSE A DATABASE'
            Write-Info 'Would open the Up/Down database picker.'
        }
        Write-Rule 'STEP 3 OF 4 | ACCOUNT DETAILS'
        Write-Info 'Would collect the username, allowed host, and hidden password.'
    } else {
        $hostName = Read-Host 'MySQL host [127.0.0.1]'
        if (-not $hostName) { $hostName = '127.0.0.1' }
        $portText = Read-Host 'MySQL port [3306]'
        if (-not $portText) { $portText = '3306' }
        $port = 0
        if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Port must be between 1 and 65535.' }
        $adminUser = Read-Host 'MySQL administrator [root]'
        if (-not $adminUser) { $adminUser = 'root' }
        $connectionArgs = @("--host=$hostName", "--port=$port", "--user=$adminUser", '--password', '--protocol=TCP')
        Write-Info 'MySQL will ask for the administrator password without displaying it.'
        if ($Scope -eq 'All') {
            Clear-Host
            Show-Brand
            Write-Rule 'STEP 2 OF 4 | CONFIRM SERVER-WIDE ACCESS'
            Write-Warn 'This account will receive ALL privileges on *.*.'
            Write-Theme -Text '  That includes every current database, system schemas, and databases created later.' -Role Muted
            if (-not (Confirm-Action 'Continue with server-wide database access?')) { Write-Info 'User creation cancelled. No account was changed.'; return }
            $database = 'all databases'
        } else {
            $global:LASTEXITCODE = 0
            $databases = @(& $mysql @connectionArgs '--batch' '--skip-column-names' '--execute=SHOW DATABASES' |
                Where-Object { $_ -and $_ -notin @('information_schema','performance_schema','mysql','sys') })
            if ($LASTEXITCODE -ne 0) { throw 'Could not list databases. Check the connection and credentials.' }
            if (-not $databases.Count) { throw 'No user databases were returned.' }
            $database = Select-MySQLDatabase -Databases $databases -Title 'STEP 2 OF 4 | CHOOSE A DATABASE'
            if (-not $database) { Write-Info 'User creation cancelled. No account was changed.'; return }
        }
        Clear-Host
        Show-Brand
        Write-Rule 'STEP 3 OF 4 | ACCOUNT DETAILS'
        if ($Scope -eq 'All') { Write-Theme -Text '  The new account will receive server-wide database privileges.' -Role Muted }
        else { Write-Theme -Text "  The new account will receive privileges on: $database" -Role Muted }
        Write-Host ''
        do {
            $newUser = Read-Host 'New database username'
            $validUser = $newUser -match '^[A-Za-z0-9_.-]{1,32}$'
            if (-not $validUser) { Write-Warn 'Use 1-32 letters, numbers, dots, underscores, or hyphens.' }
        } until ($validUser)
        do {
            $allowedHost = Read-Host 'Allowed connection host [localhost]'
            if (-not $allowedHost) { $allowedHost = 'localhost' }
            $validHost = $allowedHost -match '^[A-Za-z0-9.%:_-]+$'
            if (-not $validHost) { Write-Warn 'Enter localhost, an IP/hostname, or a MySQL host pattern such as 10.0.0.%.' }
        } until ($validHost)
        if ($allowedHost -eq '%') { Write-Warn 'Host % allows this account to authenticate from any reachable address.' }
        do {
            $securePassword = Read-HiddenPasteInput 'New user password:'
            $secureConfirmation = Read-HiddenPasteInput 'Confirm password:'
            $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
            $confirmationPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureConfirmation)
            try {
                $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
                $plainConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPointer)
            } finally {
                if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
                if ($confirmationPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPointer) }
            }
            $validPassword = $plainPassword.Length -ge 12 -and $plainPassword -eq $plainConfirmation
            if ($plainPassword.Length -lt 12) { Write-Warn 'Use at least 12 characters.' }
            elseif ($plainPassword -ne $plainConfirmation) { Write-Warn 'Passwords do not match.' }
            $plainConfirmation = $null
        } until ($validPassword)
    }

    $escapedDatabase = $database.Replace('`', '``')
    $escapedUser = $newUser.Replace('\', '\\').Replace("'", "''")
    $escapedHost = $allowedHost.Replace('\', '\\').Replace("'", "''")
    $escapedPassword = $plainPassword.Replace('\', '\\').Replace("'", "''")
    if ($Scope -eq 'All') {
        $sql = "CREATE USER '$escapedUser'@'$escapedHost' IDENTIFIED BY '$escapedPassword';`n" +
            "GRANT ALL PRIVILEGES ON *.* TO '$escapedUser'@'$escapedHost';`n" + 'FLUSH PRIVILEGES;'
    } else {
        $sql = "CREATE USER '$escapedUser'@'$escapedHost' IDENTIFIED BY '$escapedPassword';`n" +
            "GRANT ALL PRIVILEGES ON ``$escapedDatabase``.* TO '$escapedUser'@'$escapedHost';`n" + 'FLUSH PRIVILEGES;'
    }

    Write-Rule 'STEP 4 OF 4 | REVIEW AND CREATE'
    Write-Theme -Text "  User:      $newUser@$allowedHost" -Role Primary
    Write-Theme -Text "  Database:  $database" -Role Primary
    if ($Scope -eq 'All') {
        Write-Theme -Text '  Access:    ALL privileges on *.* (server-wide)' -Role Primary
        Write-Warn 'This account can modify system schemas and every current or future database.'
    } else {
        Write-Theme -Text '  Access:    ALL privileges on this database only' -Role Primary
    }
    if ($DryRun) {
        Write-Theme -Text '> mysql < CREATE USER + GRANT + FLUSH PRIVILEGES (password hidden)' -Role Accent
        Write-Info 'No user was created.'
        return
    }
    if (-not (Confirm-Action 'Create this database user?')) { $plainPassword = $null; $sql = $null; return }
    Write-Info 'MySQL will ask for the administrator password again to apply the account plan.'
    $previousOutputEncoding = $OutputEncoding
    try {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        $global:LASTEXITCODE = 0
        $sql | & $mysql @connectionArgs
        if ($LASTEXITCODE -ne 0) { throw 'User creation failed. MySQL may have applied an earlier statement; review the account before retrying.' }
    } finally {
        $OutputEncoding = $previousOutputEncoding
        $plainPassword = $null; $escapedPassword = $null; $sql = $null
    }
    if ($Scope -eq 'All') {
        Write-Ok "Created '$newUser'@'$allowedHost' with server-wide database access."
        Write-Theme -Text "  Connect with: mysql --host=`"$hostName`" --port=$port --user=`"$newUser`" --password" -Role Secondary
    } else {
        Write-Ok "Created '$newUser'@'$allowedHost' with access to '$database' only."
        Write-Theme -Text "  Connect with: mysql --host=`"$hostName`" --port=$port --user=`"$newUser`" --password `"$database`"" -Role Secondary
    }
}

function Get-ComponentCatalog {
    return @(
        [pscustomobject]@{ Name='Node.js'; Probe='node'; Complete=$true; Install='Install-Node'; Remove='Remove-Node' }
        [pscustomobject]@{ Name='PM2 process manager'; Probe='pm2'; Complete=$true; Install='Install-PM2'; Remove='Remove-PM2' }
        [pscustomobject]@{ Name='MySQL Server'; Probe='mysql'; Complete=$true; Install='Install-MySQL'; Remove='Remove-MySQL' }
        [pscustomobject]@{ Name='MySQL Workbench'; Probe='workbench'; Complete=$true; Install='Install-MySQLWorkbench'; Remove='Remove-MySQLWorkbench' }
        [pscustomobject]@{ Name='Nginx'; Probe='nginx'; Complete=$true; Install='Install-Nginx'; Remove='Remove-Nginx' }
        [pscustomobject]@{ Name='Cloudflare Tunnel'; Probe='cloudflared'; Complete=$false; Install='Install-Cloudflared'; Remove='Remove-Cloudflared' }
        [pscustomobject]@{ Name='Micro editor'; Probe='micro'; Complete=$true; Install='Install-Micro'; Remove='Remove-Micro' }
        [pscustomobject]@{ Name='Glances monitor'; Probe='glances'; Complete=$true; Install='Install-Glances'; Remove='Remove-Glances' }
        [pscustomobject]@{ Name='win-acme SSL'; Probe='wacs'; Complete=$false; Install='Install-WinAcme'; Remove='Remove-WinAcme' }
    )
}

function Get-ComponentPath {
    param([Parameter(Mandatory)]$Item)
    if ($Item.Probe -eq 'workbench') {
        $match = Get-Item "$env:ProgramFiles\MySQL\MySQL Workbench*\MySQLWorkbench.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $match) {
            $match = Get-Item "${env:ProgramFiles(x86)}\MySQL\MySQL Workbench*\MySQLWorkbench.exe" -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        return $match.FullName
    }
    if ($Item.Probe -eq 'wacs') { return Get-WacsPath }
    if ($Item.Probe -eq 'cloudflared') { return Get-CloudflaredPath }
    $command = Get-Command $Item.Probe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Test-ComponentInstalled {
    param([Parameter(Mandatory)]$Item)
    return [bool](Get-ComponentPath $Item)
}

function Select-Components {
    param([Parameter(Mandatory)][string]$Verb)
    $items = if ($Verb -eq 'Install') {
        @(Get-ComponentCatalog | Where-Object { -not (Test-ComponentInstalled $_) })
    } else {
        @(Get-ComponentCatalog | Where-Object { Test-ComponentInstalled $_ })
    }
    if (-not $items.Count) {
        Clear-Host
        Show-Brand
        if ($Verb -eq 'Install') { Write-Ok 'Every available component is already installed.' }
        else { Write-Info 'No managed components are currently installed.' }
        return @()
    }
    $selected = [bool[]]::new($items.Count)
    $cursor = 0
    Clear-Host
    Show-Brand
    Write-Theme -Text "  $Verb components" -Role Primary
    Write-Theme -Text '  Up/Down move  |  Space tick  |  A all  |  Enter continue  |  Esc cancel' -Role Muted
    Write-Host ''
    $listTop = $Host.UI.RawUI.CursorPosition.Y
    $render = {
        try { $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $listTop) } catch {}
        for ($index = 0; $index -lt $items.Count; $index++) {
            $pointer = if ($index -eq $cursor) { '>' } else { ' ' }
            $mark = if ($selected[$index]) { 'x' } else { ' ' }
            $role = if ($index -eq $cursor) { 'Selected' } elseif ($selected[$index]) { 'Secondary' } else { 'Primary' }
            $state = if ($Verb -eq 'Remove') { 'installed' } else { 'needed' }
            Write-Theme -Text ("  {0} [{1}] {2,-25} {3,-12}  " -f $pointer, $mark, $items[$index].Name, $state) -Role $role
        }
    }
    & $render
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { $cursor = ($cursor - 1 + $items.Count) % $items.Count }
            40 { $cursor = ($cursor + 1) % $items.Count }
            32 { $selected[$cursor] = -not $selected[$cursor] }
            65 {
                $target = $selected -contains $false
                for ($index = 0; $index -lt $selected.Count; $index++) { $selected[$index] = $target }
            }
            13 {
                $result = for ($index = 0; $index -lt $items.Count; $index++) {
                    if ($selected[$index]) { $items[$index] }
                }
                return @($result)
            }
            27 { return @() }
        }
        & $render
    }
}

function Invoke-ComponentWorkflow {
    param([ValidateSet('Install','Remove')][string]$Mode)
    $items = @(Select-Components -Verb $Mode)
    if (-not $items.Count) { return }
    Write-Host ''
    Write-Rule "$($Mode.ToUpper()) PLAN"
    $items | ForEach-Object { Write-Theme -Text "  * $($_.Name)" -Role Primary }
    if (-not (Confirm-Action "$Mode these $($items.Count) component(s)?")) { return }
    foreach ($item in $items) {
        Write-Rule $item.Name
        $command = $item.$Mode
        & $command
    }
    Write-Ok "$Mode workflow complete."
}

function Get-MainActions {
    return @(
        [pscustomobject]@{ Id='install'; Label='Install components'; Hint='Choose one or several tools for this machine.' }
        [pscustomobject]@{ Id='remove'; Label='Remove components'; Hint='Select installed tools you no longer need.' }
        [pscustomobject]@{ Id='complete'; Label='Install complete stack'; Hint='Node.js, PM2, MySQL, Workbench, Nginx and utilities.' }
        [pscustomobject]@{ Id='startup'; Label='Configure PM2 startup'; Hint='Restore your Node.js apps after a restart.' }
        [pscustomobject]@{ Id='domain'; Label='Connect a domain'; Hint='Route a hostname through Nginx to a PM2 app.' }
        [pscustomobject]@{ Id='ssl'; Label='Enable HTTPS'; Hint='Request and renew a free TLS certificate.' }
        [pscustomobject]@{ Id='tunnel'; Label='Configure Cloudflare Tunnel'; Hint='Publish a local app without opening inbound ports.' }
        [pscustomobject]@{ Id='backup'; Label='Back up a MySQL database'; Hint='Create a portable, validated SQL dump and get download commands.' }
        [pscustomobject]@{ Id='dbuser'; Label='Manage MySQL users'; Hint='Create database users or view every account on the server.' }
        [pscustomobject]@{ Id='health'; Label='Inspect stack health'; Hint='See what is installed and validate Nginx.' }
        [pscustomobject]@{ Id='creator'; Label='Creator and support'; Hint='View Mohamed Aiman''s links and ASCII portrait.' }
        [pscustomobject]@{ Id='exit'; Label='Exit NEEM'; Hint='Return to your terminal.' }
    )
}

function Select-MainAction {
    $actions = @(Get-MainActions)
    $cursor = 0
    Clear-Host
    Show-Brand
    Write-Theme -Text "  Windows  |  $script:PackageManager$(if ($DryRun) {'  |  DRY RUN'})" -Role Muted
    Write-Host ''
    Write-Theme -Text '  What would you like to do?' -Role Primary
    Write-Theme -Text '  Up/Down move  |  Enter select  |  Esc exit  |  Number shortcuts work too' -Role Muted
    Write-Host ''
    $listTop = $Host.UI.RawUI.CursorPosition.Y
    $render = {
        try { $Host.UI.RawUI.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $listTop) } catch {}
        for ($index = 0; $index -lt $actions.Count; $index++) {
            $active = $index -eq $cursor
            $pointer = if ($active) { '>' } else { ' ' }
            $role = if ($active) { 'Selected' } elseif ($actions[$index].Id -eq 'exit') { 'Muted' } else { 'Primary' }
            Write-Theme -Text ("  {0} {1,-40}  " -f $pointer, $actions[$index].Label) -Role $role
        }
        Write-Theme -Text ("      {0,-68}" -f $actions[$cursor].Hint) -Role Secondary
    }
    & $render
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { $cursor = ($cursor - 1 + $actions.Count) % $actions.Count }
            40 { $cursor = ($cursor + 1) % $actions.Count }
            13 { return $actions[$cursor].Id }
            27 { return 'exit' }
            48 { return 'exit' }
            { $_ -ge 49 -and $_ -le 57 } { return $actions[$_ - 49].Id }
        }
        & $render
    }
}

function Show-MainMenu {
    while ($true) {
        $pauseAfterAction = $true
        try {
            switch (Select-MainAction) {
                'install' { Invoke-ComponentWorkflow -Mode Install }
                'remove' { Invoke-ComponentWorkflow -Mode Remove }
                'complete' { Install-All }
                'startup' { Set-PM2Startup }
                'domain' { Connect-Domain }
                'ssl' { Enable-Ssl }
                'tunnel' { Start-CloudflareTunnelGuide }
                'backup' { Backup-MySQLDatabase }
                'dbuser' { Show-MySQLUserManager; $pauseAfterAction = $false }
                'health' { Show-Health }
                'creator' { Show-CreatorCard; $pauseAfterAction = $false }
                'exit' { Write-Host 'Goodbye.'; return }
            }
        } catch {
            Write-Theme -Text "[x] $($_.Exception.Message)" -Role Accent
        }
        if (-not $DryRun -and $pauseAfterAction) { [void](Read-Host 'Press Enter to continue') }
    }
}

function Show-Usage {
    Write-Host @"
NEEM Stack Setup v$script:Version

Usage: .\neem.ps1 [-DryRun] [-Health] [-Backup] [-CreateDatabaseUser]
                   [-CreateGlobalDatabaseUser] [-ListDatabaseUsers] [-Update] [-Help]

Without options, launches the interactive terminal menu.
  -DryRun  Print package and service commands without running them
  -Health  Show installed components and validate Nginx
  -Backup  Create a portable MySQL database dump
  -CreateDatabaseUser  Create a user for one MySQL database
  -CreateGlobalDatabaseUser  Create a user with access to all databases
  -ListDatabaseUsers  List MySQL users and their allowed hosts
  -Update  Download and install the latest version from GitHub

Keyboard controls:
  Up/Down  Move through menus
  Enter    Open the highlighted action
  Space    Tick or untick a component
  A        Tick or untick all components
  1-9      Main-menu shortcuts
"@
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
