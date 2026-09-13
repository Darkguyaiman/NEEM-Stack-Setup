# MySQL database selection, portable backups, and user management.
select_mysql_database() {
  local title=$1
  shift
  local -a items=("$@")
  local cursor=0 start=0 visible rows first_render=1 key rest offset index width max_name
  SELECTED_DATABASE=""
  ((${#items[@]})) || return 1
  rows=$(tput lines 2>/dev/null || printf '24')
  visible=$((rows - 12))
  ((visible < 5)) && visible=5
  ((visible > ${#items[@]})) && visible=${#items[@]}
  width=$(tput cols 2>/dev/null || printf '100')
  max_name=$((width - 10))
  ((max_name < 20)) && max_name=20

  clear 2>/dev/null || true
  show_brand
  rule "$title"
  printf '%s  Up/Down move | Enter select | Esc cancel%s\n\n' "$MUTED" "$RESET"
  while true; do
    ((cursor < start)) && start=$cursor
    ((cursor >= start + visible)) && start=$((cursor - visible + 1))
    if ((first_render)); then first_render=0
    else printf '\033[%dA' "$((visible + 1))"
    fi
    for ((offset=0; offset<visible; offset++)); do
      index=$((start + offset))
      if ((index >= ${#items[@]})); then printf '\033[2K\r\n'; continue; fi
      local label=${items[index]}
      ((${#label} > max_name)) && label="${label:0:max_name-3}..."
      if ((index == cursor)); then
        printf '\033[2K\r%s  > %-*s%s\n' "$SELECTED" "$max_name" "$label" "$RESET"
      else
        printf '\033[2K\r%s    %-*s%s\n' "$CREAM" "$max_name" "$label" "$RESET"
      fi
    done
    printf '\033[2K\r%s      Database %d of %d%s\n' "$PAPER" "$((cursor + 1))" "${#items[@]}" "$RESET"
    IFS= read -rsn1 key < /dev/tty || return 1
    if [[ "$key" == $'\e' ]]; then
      rest=""
      IFS= read -rsn2 -t 0.1 rest < /dev/tty || true
      case "$rest" in
        '[A') cursor=$(((cursor - 1 + ${#items[@]}) % ${#items[@]})) ;;
        '[B') cursor=$(((cursor + 1) % ${#items[@]})) ;;
        '') return 1 ;;
      esac
    elif [[ -z "$key" ]]; then
      SELECTED_DATABASE=${items[cursor]}
      return 0
    fi
  done
}

normalize_backup_directory() {
  local path=$1
  if [[ "$path" == \"*\" && "$path" == *\" ]] || [[ "$path" == \'*\' && "$path" == *\' ]]; then
    path=${path:1:${#path}-2}
  fi
  case "$path" in
    '~') path=$HOME ;;
    '~/'*) path="$HOME/${path:2}" ;;
  esac
  if [[ "$path" =~ ^([A-Za-z]):[\\/](.*)$ ]]; then
    if command -v wslpath >/dev/null 2>&1; then
      path=$(wslpath -u "$path")
    elif command -v cygpath >/dev/null 2>&1; then
      path=$(cygpath -u "$path")
    else
      warn "Windows drive paths require WSL or Git Bash. Enter a Unix path on this system."
      return 1
    fi
  else
    path=${path//\\//}
  fi
  [[ "$path" == /* ]] || path="$PWD/$path"
  while [[ "$path" != / && "$path" == */ ]]; do path=${path%/}; done
  printf '%s\n' "$path"
}

detect_backup_ssh_host() {
  local client client_port server server_port address
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    read -r client client_port server server_port <<< "$SSH_CONNECTION"
    if [[ "$server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "$server" =~ ^[0-9a-fA-F:]+:[0-9a-fA-F:]+$ ]]; then
      printf '%s\n' "$server"; return
    fi
  fi
  if ((!DRY_RUN)) && command -v curl >/dev/null 2>&1; then
    address=$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)
    if [[ "$address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s\n' "$address"; return; fi
  fi
  hostname -f 2>/dev/null || hostname
}

compress_mysql_dump() {
  local source=$1 target=$2 compressed="$2.partial"
  [[ ! -e "$target" && ! -e "$compressed" ]] || { warn 'Backup destination already exists.'; return 1; }
  if ! (umask 077; gzip -c -- "$source" > "$compressed") || ! gzip -t -- "$compressed"; then
    rm -f -- "$compressed"
    warn "Compression failed. The SQL dump was retained at $source."
    return 1
  fi
  mv -- "$compressed" "$target" || return 1
  rm -f -- "$source"
}

mysql_backup() {
  local mysql_cmd dump_cmd dump_help host port user database choice include_schema answer
  local backup_dir timestamp safe_database partial_file final_file remote_host remote_user remote_path database_output argument
  local -a databases connection_args dump_args mysql_prefix

  mysql_cmd=$(command -v mysql || command -v mariadb || true)
  dump_cmd=$(command -v mysqldump || command -v mariadb-dump || true)
  if ((DRY_RUN)); then
    mysql_cmd=${mysql_cmd:-mysql}
    dump_cmd=${dump_cmd:-mysqldump}
  fi
  [[ -n "$mysql_cmd" && -n "$dump_cmd" ]] || {
    warn "MySQL client tools were not found. Install MySQL or MariaDB first."
    return 1
  }

  clear 2>/dev/null || true
  show_brand
  rule "STEP 1 OF 6 | CONNECT TO MYSQL"
  printf '%s  Enter the MySQL connection used to discover databases.%s\n' "$CREAM" "$RESET"
  printf '%s  Press Enter to accept a value shown in brackets.%s\n\n' "$MUTED" "$RESET"
  if ((DRY_RUN)); then
    host="127.0.0.1"; port="3306"; user="mysql-user"; database="chosen_database"
    connection_args=(--host="$host" --port="$port" --user="$user" --password --protocol=TCP)
    mysql_prefix=()
    include_schema=1
    info "Dry run uses placeholders and does not connect to MySQL."
    rule "STEP 2 OF 6 | CHOOSE A DATABASE"
    info "Would open the Up/Down database picker."
    rule "STEP 3 OF 6 | CHOOSE BACKUP CONTENT"
    info "Would include CREATE statements (recommended)."
  else
    read -r -p "MySQL host [127.0.0.1]: " host
    host=${host:-127.0.0.1}
    read -r -p "MySQL port [3306]: " port
    port=${port:-3306}
    [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || { warn "Port must be between 1 and 65535."; return 1; }
    read -r -p "MySQL user [root]: " user
    user=${user:-root}
    mysql_admin_connection "$mysql_cmd" "$host" "$port" "$user"
    if ! database_output=$("${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}" --batch --skip-column-names --execute='SHOW DATABASES'); then
      warn 'Could not connect to MySQL or list databases. Check your login and retry Back up a MySQL database.'
      return 1
    fi
    databases=()
    while IFS= read -r answer; do
      case "$answer" in information_schema|performance_schema|mysql|sys|'') ;; *) databases+=("$answer") ;; esac
    done <<< "$database_output"
    ((${#databases[@]})) || { warn "No user databases were returned."; return 1; }
    if ! select_mysql_database "STEP 2 OF 6 | CHOOSE A DATABASE" "${databases[@]}"; then
      info "Backup cancelled. No file was created."
      return
    fi
    database=$SELECTED_DATABASE
    clear 2>/dev/null || true
    show_brand
    rule "STEP 3 OF 6 | CHOOSE BACKUP CONTENT"
    printf '%s  Selected database:%s %s\n' "$MUTED" "$RESET" "$database"
    printf '%s  CREATE statements include the database structure, routines, events, and triggers.%s\n' "$MUTED" "$RESET"
    printf '%s  Choose No only when the destination schema already exists.%s\n\n' "$MUTED" "$RESET"
    include_schema=1
    read -r -p "Include CREATE statements? [Y/n] " answer
    [[ "$answer" =~ ^[Nn]$ ]] && include_schema=0
  fi

  safe_database=${database//[^A-Za-z0-9_.-]/_}
  timestamp=$(date '+%Y%m%d-%H%M%S')
  backup_dir="${HOME}/neem-backups"
  final_file="${safe_database}-${timestamp}.sql.gz"
  rule "STEP 4 OF 6 | CHOOSE SAVE LOCATION"
  printf '%s  The dump will be named:%s %s\n' "$CREAM" "$RESET" "$final_file"
  printf '%s  Windows and Unix-style paths are accepted. Press Enter to use the default.%s\n' "$MUTED" "$RESET"
  if ((DRY_RUN)); then
    info "Would use destination directory: $backup_dir"
  else
    read -r -p "Destination directory [$backup_dir]: " answer
    backup_dir=$(normalize_backup_directory "${answer:-$backup_dir}") || return 1
    [[ ! -f "$backup_dir" ]] || { warn "The destination is a file, not a directory: $backup_dir"; return 1; }
  fi
  final_file="$backup_dir/$final_file"
  partial_file="${final_file%.gz}.partial"

  dump_args=()
  for argument in "${connection_args[@]}"; do
    [[ "$argument" == --connect-timeout=* ]] || dump_args+=("$argument")
  done
  dump_args+=(
    --default-character-set=utf8mb4 --single-transaction --quick --hex-blob
    --complete-insert --skip-lock-tables --skip-comments --tz-utc)
  dump_help=$("$dump_cmd" --help 2>/dev/null || true)
  [[ "$dump_help" == *--no-tablespaces* ]] && dump_args+=(--no-tablespaces)
  [[ "$dump_help" == *--set-gtid-purged* ]] && dump_args+=(--set-gtid-purged=OFF)
  [[ "$dump_help" == *--column-statistics* ]] && dump_args+=(--column-statistics=0)
  if ((include_schema)); then
    dump_args+=(--routines --events --triggers --databases "$database")
  else
    dump_args+=(--no-create-info --skip-triggers "$database")
  fi

  rule "STEP 5 OF 6 | CREATE AND VALIDATE DUMP"
  if [[ " ${connection_args[*]} " == *' --password '* ]]; then
    info 'MySQL will ask for the password again before writing the dump.'
  fi
  if ((DRY_RUN)); then
    info "Would create: $final_file"
  else
    if ! command -v gzip >/dev/null 2>&1; then
      [[ -n "$PKG" ]] || detect_platform
      package_install gzip || return 1
    fi
    info 'Creating compressed backup...'
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir" 2>/dev/null || true
    rm -f -- "$partial_file"
    (umask 077; : > "$partial_file") || return 1
    if ! "${mysql_prefix[@]}" "$dump_cmd" "${dump_args[@]}" --result-file="$partial_file"; then
      rm -f -- "$partial_file"
      warn "Backup failed; the incomplete dump was removed."
      return 1
    fi
    if [[ ! -s "$partial_file" ]] || (command -v iconv >/dev/null 2>&1 && ! iconv -f UTF-8 -t UTF-8 "$partial_file" >/dev/null); then
      rm -f -- "$partial_file"
      warn "Backup validation failed; the incomplete dump was removed."
      return 1
    fi
    chmod 600 "$partial_file" 2>/dev/null || true
    compress_mysql_dump "$partial_file" "$final_file" || return 1
    ok "Backup saved: $final_file"
  fi

  rule "STEP 6 OF 6 | DOWNLOAD THE DUMP"
  info 'Run the matching command on your own computer to save the backup in Downloads.'
  remote_user=$(id -un)
  remote_host=$(detect_backup_ssh_host)
  if ((!DRY_RUN)); then
    read -r -p "Server IP or hostname (including MagicDNS) [$remote_host]: " answer
    remote_host=${answer:-$remote_host}
    read -r -p "SSH user [$remote_user]: " answer
    remote_user=${answer:-$remote_user}
  fi
  remote_path=$final_file
  if [[ "$remote_host" == *:* && "$remote_host" != \[*\] ]]; then remote_host="[$remote_host]"; fi
  printf '\n'
  local scp_source="$remote_user@$remote_host:$remote_path" filename="${final_file##*/}" ps_source
  ps_source=${scp_source//\'/\'\'}
  printf "%s  Windows PowerShell:%s\n  scp '%s' \"\$HOME/Downloads/%s\"\n" "$CREAM" "$RESET" "$ps_source" "$filename"
  printf '%s  macOS:%s\n  scp %q "$HOME/Downloads/%s"\n' "$CREAM" "$RESET" "$scp_source" "$filename"
  printf '%s  Linux:%s\n  scp %q "$HOME/Downloads/%s"\n' "$CREAM" "$RESET" "$scp_source" "$filename"
}

MYSQL_USER_ACTION=""
select_mysql_user_action() {
  local cursor=0 key rest index first_render=1
  local -a ids=(database all list password return)
  local -a labels=("Create user for one database" "Create user for all databases" "View MySQL users" "Change user password" "Return to main menu")
  local -a hints=("Grant full access to one selected database." "Grant full access across the entire MySQL server." "List each MySQL account and its allowed connection host." "Choose an existing account and set a new password." "Leave MySQL user management without changes.")
  MYSQL_USER_ACTION=""
  clear 2>/dev/null || true
  show_brand
  rule "MANAGE MYSQL USERS"
  printf '%s  Up/Down move | Enter select | Esc return%s\n\n' "$MUTED" "$RESET"
  while true; do
    if ((first_render)); then first_render=0; else printf '\033[%dA' "$((${#labels[@]} + 1))"; fi
    for index in "${!labels[@]}"; do
      if ((index == cursor)); then
        printf '\033[2K\r%s  > %-40s%s\n' "$SELECTED" "${labels[index]}" "$RESET"
      elif [[ "${ids[index]}" == "return" ]]; then
        printf '\033[2K\r%s    %-40s%s\n' "$MUTED" "${labels[index]}" "$RESET"
      else
        printf '\033[2K\r%s    %-40s%s\n' "$CREAM" "${labels[index]}" "$RESET"
      fi
    done
    printf '\033[2K\r%s      %-68s%s\n' "$PAPER" "${hints[cursor]}" "$RESET"
    IFS= read -rsn1 key < /dev/tty || return 1
    if [[ "$key" == $'\e' ]]; then
      rest=""; IFS= read -rsn2 -t 0.1 rest < /dev/tty || true
      case "$rest" in
        '[A') cursor=$(((cursor - 1 + ${#ids[@]}) % ${#ids[@]})) ;;
        '[B') cursor=$(((cursor + 1) % ${#ids[@]})) ;;
        '') MYSQL_USER_ACTION=return; return ;;
      esac
    elif [[ -z "$key" ]]; then MYSQL_USER_ACTION=${ids[cursor]}; return
    fi
  done
}

mysql_admin_connection() {
  local client=$1 host=$2 port=$3 user=$4
  local -a socket_args=(--no-defaults --user=root --protocol=SOCKET --connect-timeout=5)
  mysql_prefix=()
  connection_args=(--host="$host" --port="$port" --user="$user" --password --protocol=TCP)
  if [[ "$user" == root && "$port" == 3306 && ( "$host" == localhost || "$host" == 127.0.0.1 ) ]]; then
    if "$client" "${socket_args[@]}" --execute='SELECT 1' >/dev/null 2>&1; then
      connection_args=("${socket_args[@]}")
      info 'Connected as local MySQL root. No administrator password is needed.'
      return
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n "$client" "${socket_args[@]}" --execute='SELECT 1' >/dev/null 2>&1; then
      mysql_prefix=(sudo -n)
      connection_args=("${socket_args[@]}")
      info 'Connected as local MySQL root using sudo. No administrator password is needed.'
      return
    fi
  fi
  info 'MySQL will ask for the administrator password without displaying it.'
}

mysql_list_users() {
  local mysql_cmd host port admin_user
  local -a connection_args mysql_prefix
  mysql_cmd=$(command -v mysql || command -v mariadb || true)
  if ((DRY_RUN)); then mysql_cmd=${mysql_cmd:-mysql}; fi
  [[ -n "$mysql_cmd" ]] || { warn "MySQL client tools were not found. Install MySQL or MariaDB first."; return 1; }
  clear 2>/dev/null || true
  show_brand
  rule "VIEW MYSQL USERS"
  printf '%s  MySQL identifies an account by both its user and allowed host.%s\n\n' "$MUTED" "$RESET"
  if ((DRY_RUN)); then
    info "Would list User and Host from mysql.user."
    return
  fi
  read -r -p "MySQL host [127.0.0.1]: " host; host=${host:-127.0.0.1}
  read -r -p "MySQL port [3306]: " port; port=${port:-3306}
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || { warn "Port must be between 1 and 65535."; return 1; }
  read -r -p "MySQL administrator [root]: " admin_user; admin_user=${admin_user:-root}
  mysql_admin_connection "$mysql_cmd" "$host" "$port" "$admin_user"
  rule "ACCOUNTS ON THIS SERVER"
  if ! "${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}" --table \
    --execute='SELECT User AS USER, Host AS ALLOWED_HOST FROM mysql.user ORDER BY User, Host'; then
    warn "MySQL users could not be listed. Use an administrator with permission to read mysql.user."
    return 1
  fi
}

mysql_user_guide() {
  while true; do
    select_mysql_user_action || return
    case "$MYSQL_USER_ACTION" in
      database) mysql_create_user database || true; pause ;;
      all) mysql_create_user all || true; pause ;;
      list) mysql_list_users || true; pause ;;
      password) mysql_change_password || true; pause ;;
      return) return ;;
    esac
  done
}

mysql_change_password() (
  local mysql_cmd host port admin_user rows row label selected='' account_user account_host password confirmation sql
  local -a connection_args mysql_prefix accounts=() labels=()
  rule 'CHANGE MYSQL USER PASSWORD'
  if ((DRY_RUN)); then
    info 'Would connect, select a password-authenticated account, and confirm a hidden password change.'
    return
  fi
  mysql_cmd=$(command -v mysql || command -v mariadb || true)
  [[ -n "$mysql_cmd" ]] || { warn 'Install the MySQL client first.'; return 1; }
  ensure_release_tools || return 1
  read -r -p 'MySQL host [127.0.0.1]: ' host || return; host=${host:-127.0.0.1}
  read -r -p 'MySQL port [3306]: ' port || return; port=${port:-3306}
  valid_port "$port" || { warn 'Port must be between 1 and 65535.'; return 1; }
  read -r -p 'MySQL administrator [root]: ' admin_user || return; admin_user=${admin_user:-root}
  mysql_admin_connection "$mysql_cmd" "$host" "$port" "$admin_user"
  rows=$("${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}" --batch --raw --skip-column-names \
    --execute="SELECT JSON_ARRAY(User,Host) FROM mysql.user WHERE plugin IN ('caching_sha2_password','sha256_password','mysql_native_password') AND User <> '' ORDER BY User,Host") || {
    warn 'Could not list accounts. Check administrator permissions.'; return 1;
  }
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    label=$(printf '%s' "$row" | jq -er 'map(@json) | join(" @ ")') || return 1
    accounts+=("$row"); labels+=("$label")
  done <<< "$rows"
  ((${#accounts[@]})) || { info 'No password-authenticated accounts found. Socket-authenticated accounts do not use passwords.'; return; }
  select_mysql_database 'CHOOSE ACCOUNT | username @ host' "${labels[@]}" || { info 'Password change cancelled.'; return 0; }
  for label in "${!labels[@]}"; do
    [[ "${labels[label]}" == "$SELECTED_DATABASE" ]] && selected=${accounts[label]}
  done
  [[ -n "$selected" ]] || return 1
  account_user=$(printf '%s' "$selected" | jq -r '.[0]') || return 1
  account_host=$(printf '%s' "$selected" | jq -r '.[1]') || return 1
  while true; do
    read_hidden_paste_input 'New password (minimum 12 characters):'
    password=$HIDDEN_PASTE_VALUE; HIDDEN_PASTE_VALUE=''
    if ((${#password} < 12)); then password=''; warn 'Use at least 12 characters.'; continue; fi
    read_hidden_paste_input 'Confirm password:'
    confirmation=$HIDDEN_PASTE_VALUE; HIDDEN_PASTE_VALUE=''
    [[ "$password" == "$confirmation" ]] && break
    password=''; confirmation=''; warn 'Passwords do not match. Try again.'
  done
  confirmation=''
  info "Account: $SELECTED_DATABASE"
  info 'Applications using this account will need the new password.'
  confirm 'Change this account password?' || { password=''; info 'Password change cancelled.'; return 0; }
  # Fix SQL escaping independently of the server's existing SQL mode.
  account_user=${account_user//\'/\'\'}; account_host=${account_host//\'/\'\'}; password=${password//\'/\'\'}
  sql="SET SESSION sql_mode='NO_BACKSLASH_ESCAPES'; ALTER USER '$account_user'@'$account_host' IDENTIFIED BY '$password';"
  if ! printf '%s\n' "$sql" | "${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}"; then
    password=''; sql=''; warn 'Password change failed. Check account permissions and the server password policy.'; return 1
  fi
  password=''; sql=''
  ok "Password changed for $SELECTED_DATABASE."
)

mysql_create_user() {
  local scope=${1:-database}
  local mysql_cmd host port admin_user database choice new_user allowed_host password password_again answer
  local escaped_database escaped_user escaped_host escaped_password sql database_output create_database=0
  local -a databases connection_args mysql_prefix

  mysql_cmd=$(command -v mysql || command -v mariadb || true)
  if ((DRY_RUN)); then mysql_cmd=${mysql_cmd:-mysql}; fi
  [[ -n "$mysql_cmd" ]] || { warn "MySQL client tools were not found. Install MySQL or MariaDB first."; return 1; }

  clear 2>/dev/null || true
  show_brand
  rule "STEP 1 OF 4 | CONNECT TO MYSQL"
  printf '%s  Sign in with an account that can create users and grant privileges.%s\n' "$CREAM" "$RESET"
  printf '%s  Press Enter to accept a value shown in brackets.%s\n\n' "$MUTED" "$RESET"
  if ((DRY_RUN)); then
    host="127.0.0.1"; port="3306"; admin_user="root"
    [[ "$scope" == "all" ]] && database="all databases" || database="chosen_database"
    new_user="app_user"; allowed_host="localhost"; password="<hidden>"
    info "Dry run uses placeholders and does not connect to MySQL."
    if [[ "$scope" == "all" ]]; then
      rule "STEP 2 OF 4 | CONFIRM SERVER-WIDE ACCESS"
      warn "Would grant ALL privileges on *.*."
    else
      rule "STEP 2 OF 4 | CHOOSE A DATABASE"
      info "Would open the Up/Down database picker."
    fi
    rule "STEP 3 OF 4 | ACCOUNT DETAILS"
    info "Would collect the username, allowed host, and hidden password."
  else
    read -r -p "MySQL host [127.0.0.1]: " host
    host=${host:-127.0.0.1}
    read -r -p "MySQL port [3306]: " port
    port=${port:-3306}
    [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || { warn "Port must be between 1 and 65535."; return 1; }
    read -r -p "MySQL administrator [root]: " admin_user
    admin_user=${admin_user:-root}
    mysql_admin_connection "$mysql_cmd" "$host" "$port" "$admin_user"
    if [[ "$scope" == "all" ]]; then
      clear 2>/dev/null || true; show_brand
      rule "STEP 2 OF 4 | CONFIRM SERVER-WIDE ACCESS"
      warn "This account will receive ALL privileges on *.*."
      printf '%s  That includes every current database, system schemas, and databases created later.%s\n' "$MUTED" "$RESET"
      confirm "Continue with server-wide database access?" || { info "User creation cancelled. No account was changed."; return; }
      database="all databases"
    else
      databases=()
      if ! database_output=$("${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}" --batch --skip-column-names --execute='SHOW DATABASES'); then
        warn 'Could not list databases. Check the connection and administrator permissions.'
        return 1
      fi
      while IFS= read -r answer; do
        case "$answer" in information_schema|performance_schema|mysql|sys|'') ;; *) databases+=("$answer") ;; esac
      done <<< "$database_output"
      if ((${#databases[@]} == 0)); then
        info 'No app databases exist yet. You can create one with this user.'
        while true; do
          read -r -p 'New database name (Enter to cancel): ' database || return 1
          [[ -n "$database" ]] || { info 'User creation cancelled. No account was changed.'; return; }
          [[ "$database" =~ ^[A-Za-z0-9_]{1,64}$ && ! "$database" =~ ^(mysql|sys|information_schema|performance_schema)$ ]] && break
          warn 'Use 1-64 letters, numbers, or underscores, excluding system database names.'
        done
        create_database=1
      else
        if ! select_mysql_database "STEP 2 OF 4 | CHOOSE A DATABASE" "${databases[@]}"; then
          info "User creation cancelled. No account was changed."
          return
        fi
        database=$SELECTED_DATABASE
      fi
    fi
    clear 2>/dev/null || true
    show_brand
    rule "STEP 3 OF 4 | ACCOUNT DETAILS"
    if [[ "$scope" == "all" ]]; then
      printf '%s  The new account will receive server-wide database privileges.%s\n\n' "$MUTED" "$RESET"
    else
      printf '%s  The new account will receive privileges on:%s %s\n\n' "$MUTED" "$RESET" "$database"
    fi
    while true; do
      read -r -p "New database username: " new_user
      [[ "$new_user" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] && break
      warn "Use 1-32 letters, numbers, dots, underscores, or hyphens."
    done
    while true; do
      read -r -p "Allowed connection host [localhost]: " allowed_host
      allowed_host=${allowed_host:-localhost}
      [[ "$allowed_host" =~ ^[A-Za-z0-9.%:_-]+$ ]] && break
      warn "Enter localhost, an IP/hostname, or a MySQL host pattern such as 10.0.0.%."
    done
    [[ "$allowed_host" == "%" ]] && warn "Host % allows this account to authenticate from any reachable address."
    while true; do
      read_hidden_paste_input "New user password (minimum 12 characters):"
      password=$HIDDEN_PASTE_VALUE; HIDDEN_PASTE_VALUE=""
      if ((${#password} < 12)); then
        warn 'Password must contain at least 12 characters. Try again.'
        password=""
        continue
      fi
      read_hidden_paste_input "Confirm password:"
      password_again=$HIDDEN_PASTE_VALUE; HIDDEN_PASTE_VALUE=""
      if [[ "$password" != "$password_again" ]]; then warn "Passwords do not match."
      else break
      fi
      password=""; password_again=""
    done
    password_again=""
  fi

  escaped_database=${database//\`/\`\`}
  escaped_user=${new_user//\\/\\\\}; escaped_user=${escaped_user//\'/\'\'}
  escaped_host=${allowed_host//\\/\\\\}; escaped_host=${escaped_host//\'/\'\'}
  escaped_password=${password//\\/\\\\}; escaped_password=${escaped_password//\'/\'\'}
  if [[ "$scope" == "all" ]]; then
    sql="CREATE USER '$escaped_user'@'$escaped_host' IDENTIFIED BY '$escaped_password';
GRANT ALL PRIVILEGES ON *.* TO '$escaped_user'@'$escaped_host';
FLUSH PRIVILEGES;"
  else
    sql="CREATE USER '$escaped_user'@'$escaped_host' IDENTIFIED BY '$escaped_password';
GRANT ALL PRIVILEGES ON \`$escaped_database\`.* TO '$escaped_user'@'$escaped_host';
FLUSH PRIVILEGES;"
  fi

  rule "STEP 4 OF 4 | REVIEW AND CREATE"
  if ((create_database)); then
    sql="CREATE DATABASE \`$escaped_database\`;"$'\n'"$sql"
    info "A new database named '$database' will be created after confirmation."
  fi
  printf '%s  User:%s      %s@%s\n' "$MUTED" "$RESET" "$new_user" "$allowed_host"
  printf '%s  Database:%s  %s\n' "$MUTED" "$RESET" "$database"
  if [[ "$scope" == "all" ]]; then
    printf '%s  Access:%s    ALL privileges on *.* (server-wide)\n' "$MUTED" "$RESET"
    warn "This account can modify system schemas and every current or future database."
  else
    printf '%s  Access:%s    ALL privileges on this database only\n' "$MUTED" "$RESET"
  fi
  if ((DRY_RUN)); then
    printf '%s+%s mysql < CREATE USER + GRANT + FLUSH PRIVILEGES (password hidden)\n' "$BLUE" "$RESET"
    info "No user was created."
    return
  fi
  confirm "Create this database user?" || { password=""; sql=""; return; }
  if [[ " ${connection_args[*]} " == *' --password '* ]]; then
    info 'MySQL will ask for the administrator password again to apply the account plan.'
  fi
  if ! printf '%s\n' "$sql" | "${mysql_prefix[@]}" "$mysql_cmd" "${connection_args[@]}"; then
    password=""; escaped_password=""; sql=""
    warn "User creation failed. MySQL may have applied an earlier statement; review the account before retrying."
    return 1
  fi
  password=""; escaped_password=""; sql=""
  if [[ "$scope" == "all" ]]; then
    ok "Created '$new_user'@'$allowed_host' with server-wide database access."
    printf '%s  Connect with:%s\n  mysql --host=%q --port=%q --user=%q --password\n' \
      "$CREAM" "$RESET" "$host" "$port" "$new_user"
  else
    ok "Created '$new_user'@'$allowed_host' with access to '$database' only."
    printf '%s  Connect with:%s\n  mysql --host=%q --port=%q --user=%q --password %q\n' \
      "$CREAM" "$RESET" "$host" "$port" "$new_user" "$database"
  fi
}
