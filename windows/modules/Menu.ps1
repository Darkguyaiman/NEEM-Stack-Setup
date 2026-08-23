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

