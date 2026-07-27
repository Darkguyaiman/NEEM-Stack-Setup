# NEEM Stack Setup - interactive Windows server bootstrapper
#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Health,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'
$script:PackageManager = $null

function Write-Info([string]$Message) { Write-Host "[i] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[!] $Message" -ForegroundColor Yellow }

function Invoke-Step {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Display)
    Write-Host "> $Display" -ForegroundColor DarkCyan
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
    Write-Info 'This installs Node.js, PM2, MySQL, Nginx, Micro and Glances.'
    if (-not (Confirm-Action 'Install the complete NEEM stack?')) { return }
    Install-Node
    Install-PM2
    Install-MySQL
    Install-Nginx
    Install-Micro
    Install-Glances
    Write-Ok 'The NEEM stack is installed.'
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
    Write-Host "`nNEEM stack status" -ForegroundColor White
    $items = [ordered]@{
        'Node.js'='node'; 'npm'='npm'; 'PM2'='pm2'; 'MySQL'='mysql'
        'Nginx'='nginx'; 'Micro'='micro'; 'Glances'='glances'; 'win-acme'='wacs'
    }
    foreach ($item in $items.GetEnumerator()) {
        $command = Get-Command $item.Value -ErrorAction SilentlyContinue
        if ($command) { Write-Host ("  + {0,-12} {1}" -f $item.Key, $command.Source) -ForegroundColor Green }
        else { Write-Host ("  - {0,-12} not installed" -f $item.Key) -ForegroundColor Yellow }
    }
    if (Get-Command pm2 -ErrorAction SilentlyContinue) { & pm2 ls }
    try {
        $root = Get-NginxRoot
        $nginxExe = Get-NginxExe $root
        & $nginxExe -t -p "$root\"
    } catch {
        if (Get-Command nginx -ErrorAction SilentlyContinue) { Write-Warn $_.Exception.Message }
    }
}

function Show-ComponentMenu {
    while ($true) {
        Write-Host "`nInstall a component" -ForegroundColor White
        Write-Host "  1) Node.js`n  2) PM2`n  3) MySQL`n  4) Nginx"
        Write-Host "  5) Micro editor`n  6) Glances`n  7) win-acme`n  0) Back"
        switch (Read-Host 'Choose') {
            '1' { Install-Node } '2' { Install-PM2 } '3' { Install-MySQL }
            '4' { Install-Nginx } '5' { Install-Micro } '6' { Install-Glances }
            '7' { Install-WinAcme } '0' { return }
            default { Write-Warn 'Choose a listed option.' }
        }
    }
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host "NEEM Stack Setup  v$script:Version" -ForegroundColor Cyan
        Write-Host "Windows · $script:PackageManager$(if ($DryRun) {' · dry run'})`n"
        Write-Host "  1) Install complete stack"
        Write-Host "  2) Install one component"
        Write-Host "  3) Configure PM2 startup"
        Write-Host "  4) Connect a domain to a PM2 app"
        Write-Host "  5) Enable SSL for an existing domain"
        Write-Host "  6) Health check"
        Write-Host "  0) Exit"
        try {
            switch (Read-Host 'Choose') {
                '1' { Install-All } '2' { Show-ComponentMenu } '3' { Set-PM2Startup }
                '4' { Connect-Domain } '5' { Enable-Ssl } '6' { Show-Health }
                '0' { Write-Host 'Goodbye.'; return }
                default { Write-Warn 'Choose a listed option.' }
            }
        } catch {
            Write-Host "[x] $($_.Exception.Message)" -ForegroundColor Red
        }
        if (-not $DryRun) { [void](Read-Host 'Press Enter to continue') }
    }
}

function Show-Usage {
    Write-Host @"
NEEM Stack Setup v$script:Version

Usage: .\neem.ps1 [-DryRun] [-Health] [-Help]

Without options, launches the interactive terminal menu.
  -DryRun  Print package and service commands without running them
  -Health  Show installed components and validate Nginx
"@
}

if ($Help) { Show-Usage; exit 0 }
if (-not (Test-Administrator)) {
    Write-Warn 'Run PowerShell as Administrator for installation, Nginx, and SSL tasks.'
}
if ($Health) {
    Show-Health
} else {
    Initialize-PackageManager
    Show-MainMenu
}
