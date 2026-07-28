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

function Set-Utf8NoBom([string]$Path, [string]$Value) {
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Confirm-Action([string]$Prompt) {
    if ($DryRun) { return $true }
    return (Read-Host "$Prompt [y/N]") -match '^[Yy]$'
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

function Get-ComponentCatalog {
    return @(
        [pscustomobject]@{ Name='Node.js'; Probe='node'; Complete=$true; Install='Install-Node'; Remove='Remove-Node' }
        [pscustomobject]@{ Name='PM2 process manager'; Probe='pm2'; Complete=$true; Install='Install-PM2'; Remove='Remove-PM2' }
        [pscustomobject]@{ Name='MySQL Server'; Probe='mysql'; Complete=$true; Install='Install-MySQL'; Remove='Remove-MySQL' }
        [pscustomobject]@{ Name='MySQL Workbench'; Probe='workbench'; Complete=$true; Install='Install-MySQLWorkbench'; Remove='Remove-MySQLWorkbench' }
        [pscustomobject]@{ Name='Nginx'; Probe='nginx'; Complete=$true; Install='Install-Nginx'; Remove='Remove-Nginx' }
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
            { $_ -ge 49 -and $_ -le 56 } { return $actions[$_ - 49].Id }
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

Usage: .\neem.ps1 [-DryRun] [-Health] [-Help]

Without options, launches the interactive terminal menu.
  -DryRun  Print package and service commands without running them
  -Health  Show installed components and validate Nginx

Keyboard controls:
  Up/Down  Move through menus
  Enter    Open the highlighted action
  Space    Tick or untick a component
  A        Tick or untick all components
  1-8      Main-menu shortcuts
"@
}

if ($Help) { Show-Usage; exit 0 }
if (-not (Test-Administrator) -and -not $NoElevate) {
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
} else {
    Initialize-PackageManager
    Show-MainMenu
}
