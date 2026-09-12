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
    if ($Mode -eq 'Remove') {
        $items = @($items | Where-Object { $_.Remove -ne 'Remove-Node' }) +
            @($items | Where-Object { $_.Remove -eq 'Remove-Node' })
    }
    Write-Host ''
    Write-Rule "$($Mode.ToUpper()) PLAN"
    $items | ForEach-Object { Write-Theme -Text "  * $($_.Name)" -Role Primary }
    if (-not (Confirm-Action "$Mode these $($items.Count) component(s)?")) { return }
    $position = 0
    foreach ($item in $items) {
        $position++
        Write-Rule "$position/$($items.Count)  $($item.Name)"
        $command = $item.$Mode
        & $command
        Write-Ok "$($item.Name) complete."
    }
    Write-Ok "$Mode workflow complete."
}

