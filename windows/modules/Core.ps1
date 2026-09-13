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
    if ($DryRun) {
        Write-Info 'Would fetch the latest NEEM, save local edits automatically, and update program files.'
        return
    }
    if ((Test-Path -LiteralPath (Join-Path $script:ProjectRoot '.git')) -and
        (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info 'Checking GitHub for updates...'
        Invoke-PackageStep -QuietProgress -Action { & git -C $script:ProjectRoot fetch origin main } 'git fetch origin main'
        $current = (& git -C $script:ProjectRoot rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to read the current Git commit.' }
        $latest = (& git -C $script:ProjectRoot rev-parse FETCH_HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to read the fetched Git commit.' }
        $changes = @(& git -C $script:ProjectRoot status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Git working tree.' }
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N')
        if ($changes.Count) {
            Invoke-PackageStep -QuietProgress -Action { & git -c user.name=NEEM -c user.email=neem@localhost -C $script:ProjectRoot stash push --include-untracked -m "NEEM automatic update backup $stamp" } 'Save local edits automatically'
            $backup = (& git -C $script:ProjectRoot rev-parse refs/stash).Trim()
            if ($LASTEXITCODE -ne 0) { throw 'Unable to read the automatic backup reference.' }
            Write-Info "Local edits saved automatically in Git stash $backup."
        }
        if ($current -eq $latest) {
            Write-Ok "NEEM v$script:Version is up to date."
            return
        } else {
            & git -C $script:ProjectRoot merge-base --is-ancestor $current $latest
            $ancestorStatus = $LASTEXITCODE
            if ($ancestorStatus -eq 0) {
                Invoke-PackageStep -QuietProgress -Action { & git -C $script:ProjectRoot merge --ff-only $latest } 'Apply the latest NEEM update'
            } elseif ($ancestorStatus -eq 1) {
                $backup = "neem-backup-$stamp"
                Invoke-PackageStep -QuietProgress -Action { & git -C $script:ProjectRoot branch $backup $current } 'Back up local commits'
                Write-Info "Local commits saved on branch $backup."
                Invoke-PackageStep -QuietProgress -Action { & git -C $script:ProjectRoot reset --keep $latest } 'Apply the latest NEEM update'
            } else { throw 'Unable to compare the local and fetched Git commits.' }
            $newVersion = (Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'VERSION') -Raw).Trim()

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

        } finally {
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        }
    }
    $commandInstaller = Join-Path $script:ProjectRoot 'Install-NEEM-Command.ps1'
    if (Test-Path -LiteralPath $commandInstaller) {
        Invoke-PackageStep -QuietProgress -Action { & $commandInstaller } -Display 'Refresh NEEM commands'
    }
    Write-Ok "Updated to NEEM v$newVersion."
    Write-Info 'Run neem to continue.'
}

