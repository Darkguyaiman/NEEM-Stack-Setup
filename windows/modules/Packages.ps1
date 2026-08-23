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

