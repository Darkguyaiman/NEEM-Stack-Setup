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
    $sshHost = Get-BackupSshHost
    Write-Info "Detected server address: $sshHost. Press Enter to use it, or enter a different IP/MagicDNS name."
    $sshUser = $env:USERNAME
    Write-Info 'Use the server IP address OR a hostname your receiving computer can reach.'
    Write-Info 'Examples: 203.0.113.10, a Tailscale IP, or a DNS/MagicDNS name.'
    Write-Info 'For a Tailscale address or MagicDNS name, the receiving computer must have access to that tailnet.'
    if (-not $DryRun) {
        $answer = Read-Host "Server IP or hostname (including MagicDNS) [$sshHost]"
        if ($answer) { $sshHost = $answer }
        $answer = Read-Host "SSH user [$sshUser]"
        if ($answer) { $sshUser = $answer }
    }
    $remotePath = $finalFile.Replace('\', '/')
    if ($sshHost.Contains(':') -and -not $sshHost.StartsWith('[')) { $sshHost = "[$sshHost]" }
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
        [pscustomobject]@{ Id='password'; Label='Change user password'; Hint='Choose an existing account and set a new password.' }
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
            'password' { try { Set-MySQLUserPassword } catch { Write-Warn $_.Exception.Message } }
            'return' { return }
        }
        if (-not $DryRun -and $pauseAfterAction) { [void](Read-Host 'Press Enter to continue') }
    }
}

function Get-BackupSshHost {
    if ($env:SSH_CONNECTION) {
        $parts = $env:SSH_CONNECTION -split '\s+'
        $parsed = $null
        if ($parts.Count -eq 4 -and [Net.IPAddress]::TryParse($parts[2], [ref]$parsed)) { return $parts[2] }
    }
    if (-not $DryRun) {
        try {
            $address = (Invoke-WebRequest -UseBasicParsing -Uri 'https://api.ipify.org' -TimeoutSec 3 -ErrorAction Stop).Content.Trim()
            $parsed = $null
            if ([Net.IPAddress]::TryParse($address, [ref]$parsed)) { return $address }
        } catch { }
    }
    return $env:COMPUTERNAME
}

function Set-MySQLUserPassword {
    Write-Rule 'CHANGE MYSQL USER PASSWORD'
    if ($DryRun) { Write-Info 'Would select an account and confirm a hidden password change.'; return }
    $mysql = (Get-Command mysql -ErrorAction SilentlyContinue).Source
    if (-not $mysql) { $mysql = (Get-Command mariadb -ErrorAction SilentlyContinue).Source }
    if (-not $mysql) { throw 'Install the MySQL client first.' }
    $hostName = Read-Host 'MySQL host [127.0.0.1]'
    if (-not $hostName) { $hostName = '127.0.0.1' }
    $portText = Read-Host 'MySQL port [3306]'
    if (-not $portText) { $portText = '3306' }
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Port must be between 1 and 65535.' }
    $adminUser = Read-Host 'MySQL administrator [root]'
    if (-not $adminUser) { $adminUser = 'root' }
    $connectionArgs = @("--host=$hostName", "--port=$port", "--user=$adminUser", '--password', '--protocol=TCP')
    Write-Info 'MySQL will ask for the administrator password.'
    $rows = @(& $mysql @connectionArgs --batch --raw --skip-column-names "--execute=SELECT JSON_ARRAY(User,Host) FROM mysql.user WHERE plugin IN ('caching_sha2_password','sha256_password','mysql_native_password') AND User <> '' ORDER BY User,Host")
    if ($LASTEXITCODE -ne 0) { throw 'Could not list accounts. Check administrator permissions.' }
    $accounts = @($rows | Where-Object { $_ } | ForEach-Object {
        $values = $_ | ConvertFrom-Json
        [pscustomobject]@{ User=[string]$values[0]; HostName=[string]$values[1]; Label=($_ | ConvertFrom-Json | ConvertTo-Json -Compress) }
    })
    if (-not $accounts.Count) { Write-Info 'No password-authenticated accounts found. Socket accounts do not use passwords.'; return }
    $selected = Select-MySQLDatabase -Databases @($accounts.Label) -Title 'CHOOSE ACCOUNT | [username, host]'
    if (-not $selected) { Write-Info 'Password change cancelled.'; return }
    $account = $accounts | Where-Object { $_.Label -eq $selected } | Select-Object -First 1
    $plainPassword = $null; $plainConfirmation = $null; $sql = $null
    $previousOutputEncoding = $OutputEncoding
    try {
        while ($true) {
            $secure = Read-HiddenPasteInput 'New password (minimum 12 characters):'
            if ($secure.Length -lt 12) { $secure.Dispose(); Write-Warn 'Use at least 12 characters.'; continue }
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
            $secure = Read-HiddenPasteInput 'Confirm password:'
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $plainConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
            if ($plainPassword -ceq $plainConfirmation) { break }
            $plainPassword = $null; $plainConfirmation = $null
            Write-Warn 'Passwords do not match. Try again.'
        }
        $plainConfirmation = $null
        Write-Info "Account: $selected. Applications using this account will need the new password."
        if (-not (Confirm-Action 'Change this account password?')) { Write-Info 'Password change cancelled.'; return }
        $escapedUser = $account.User.Replace("'", "''")
        $escapedHost = $account.HostName.Replace("'", "''")
        $escapedPassword = $plainPassword.Replace("'", "''")
        $sql = "SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; ALTER USER '$escapedUser'@'$escapedHost' IDENTIFIED BY '$escapedPassword';"
        Write-Info 'MySQL will ask for the administrator password again to apply this change.'
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        $sql | & $mysql @connectionArgs
        if ($LASTEXITCODE -ne 0) { throw 'Password change failed. Check permissions and the server password policy.' }
        Write-Ok "Password changed for $selected."
    } finally {
        $OutputEncoding = $previousOutputEncoding
        $plainPassword = $null; $plainConfirmation = $null; $escapedPassword = $null; $sql = $null
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
            $validPassword = $false
            $securePassword = Read-HiddenPasteInput 'New user password (minimum 12 characters):'
            if ($securePassword.Length -lt 12) {
                Write-Warn 'Password must contain at least 12 characters. Try again.'
                $securePassword.Dispose()
                continue
            }
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
            if ($plainPassword -ne $plainConfirmation) { Write-Warn 'Passwords do not match.' }
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

