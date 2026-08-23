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

