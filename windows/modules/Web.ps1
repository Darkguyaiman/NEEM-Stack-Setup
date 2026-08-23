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

