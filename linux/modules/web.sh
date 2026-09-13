# Nginx, domains, TLS, PM2 startup, and Cloudflare Tunnel workflows.
rewrite_nginx_webroot() {
  sed -E 's#^([[:space:]]*root[[:space:]]+)/usr/share/nginx/html([[:space:]]*;)#\1/var/www/html\2#'
}

configure_nginx_webroot() (
  [[ "$OS" != macos ]] || return 0
  local stage config backup stamp index
  local -a changed=() backups=()
  if ((DRY_RUN)); then
    info 'Would prepare /var/www/html and update the packaged Nginx default site.'
    return
  fi
  stage=$(mktemp -d) || return 1
  trap 'rm -rf -- "$stage"' EXIT
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  root_run install -d -m 0755 /var/www/html || return 1
  if [[ -d /usr/share/nginx/html ]]; then
    root_run cp -Rn /usr/share/nginx/html/. /var/www/html/ || return 1
  fi
  for config in /etc/nginx/conf.d/default.conf /etc/nginx/sites-available/default /etc/nginx/nginx.conf; do
    [[ -f "$config" ]] || continue
    rewrite_nginx_webroot < "$config" > "$stage/config"
    cmp -s "$config" "$stage/config" && continue
    backup="$config.neem-webroot-backup-$stamp"
    root_run cp -p "$config" "$backup" || return 1
    changed+=("$config")
    backups+=("$backup")
    if ! root_run cp "$stage/config" "$config"; then
      for index in "${!changed[@]}"; do root_run cp -p "${backups[index]}" "${changed[index]}"; done
      return 1
    fi
  done
  if ! root_run nginx -t; then
    for index in "${!changed[@]}"; do root_run cp -p "${backups[index]}" "${changed[index]}"; done
    warn 'Nginx validation failed; default-site changes were restored.'
    return 1
  fi
  info 'Default website files: /var/www/html. Custom website roots are retained.'
)

valid_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

nginx_paths() {
  if [[ "$OS" == "macos" ]]; then
    local prefix
    prefix="$(brew --prefix)"
    NGINX_AVAILABLE="$prefix/etc/nginx/servers"
    NGINX_ENABLED=""
  elif [[ -d /etc/nginx/sites-available ]]; then
    NGINX_AVAILABLE="/etc/nginx/sites-available"
    NGINX_ENABLED="/etc/nginx/sites-enabled"
  else
    NGINX_AVAILABLE="/etc/nginx/conf.d"
    NGINX_ENABLED=""
  fi
}

show_pm2_apps() {
  if ! command -v pm2 >/dev/null 2>&1; then
    warn "PM2 is not installed yet."
    return 1
  fi
  info "Current PM2 applications:"
  pm2 jlist 2>/dev/null | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try {
        const a=JSON.parse(s);
        if (!a.length) console.log("  (no processes)");
        for (const p of a) console.log(`  ${p.pm_id}: ${p.name} [${p.pm2_env.status}]`);
      } catch (_) { console.log("  Unable to parse PM2 process list."); }
    });'
}

dns_check() {
  local domain=$1 resolved="" public=""
  if command -v dig >/dev/null 2>&1; then
    resolved="$(dig +short A "$domain" | head -n1 || true)"
  elif command -v getent >/dev/null 2>&1; then
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  elif command -v nslookup >/dev/null 2>&1; then
    resolved="$(nslookup "$domain" 2>/dev/null | awk '/^Address: /{print $2}' | tail -n1 || true)"
  fi
  if command -v curl >/dev/null 2>&1; then
    public="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  [[ -n "$resolved" ]] && info "$domain resolves to $resolved." || warn "$domain does not currently return an IPv4 address."
  if [[ -n "$public" && -n "$resolved" && "$public" != "$resolved" ]]; then
    warn "This machine's public IPv4 is $public, but DNS resolves to $resolved."
    warn "SSL validation will fail unless a proxy or load balancer correctly forwards ports 80 and 443."
    return 1
  fi
  return 0
}

write_nginx_config() {
  local domain=$1 port=$2 include_www=$3
  local names="$domain" temp target link backup=""
  [[ "$include_www" == "yes" ]] && names="$domain www.$domain"
  nginx_paths
  target="$NGINX_AVAILABLE/neem-$domain.conf"
  link=""
  [[ -n "$NGINX_ENABLED" ]] && link="$NGINX_ENABLED/neem-$domain.conf"
  temp="$(mktemp)"
  cat >"$temp" <<EOF
# Managed by NEEM Stack Setup
server {
    listen 80;
    listen [::]:80;
    server_name $names;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type text/plain;
    }

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 60s;
    }
}
EOF

  root_run mkdir -p "$NGINX_AVAILABLE" /var/www/letsencrypt
  [[ -n "$NGINX_ENABLED" ]] && root_run mkdir -p "$NGINX_ENABLED"
  if [[ -f "$target" ]]; then
    backup="$target.backup.$(date +%Y%m%d%H%M%S)"
    root_run cp "$target" "$backup"
    info "Backed up the existing config."
  fi
  root_run install -m 0644 "$temp" "$target"
  rm -f "$temp"
  [[ -n "$link" ]] && root_run ln -sfn "$target" "$link"

  if ! root_run nginx -t; then
    if [[ -n "$backup" ]]; then
      root_run cp "$backup" "$target"
    else
      root_run rm -f "$target"
      [[ -n "$link" ]] && root_run rm -f "$link"
    fi
    warn "Nginx rejected the generated configuration. The previous configuration was restored."
    return 1
  fi
  if [[ "$OS" == "macos" ]]; then
    # Public HTTP/HTTPS ports are privileged on macOS, so the domain workflow
    # replaces the user-level Homebrew service with a root-owned Nginx process.
    run brew services stop nginx
    if pgrep -x nginx >/dev/null 2>&1; then root_run nginx -s reload
    else root_run nginx
    fi
  elif command -v systemctl >/dev/null 2>&1; then root_run systemctl reload nginx
  else root_run nginx -s reload
  fi
  ok "Nginx now proxies http://$domain to http://127.0.0.1:$port."
}

enable_ssl() {
  local domain=${1:-} include_www=${2:-} email domains=(-d)
  [[ -n "$domain" ]] || read -r -p "Domain name: " domain
  valid_domain "$domain" || die "Invalid domain name: $domain"
  if [[ -z "$include_www" ]]; then
    if confirm "Include www.$domain?"; then include_www="yes"; else include_www="no"; fi
  fi
  read -r -p "Email for expiry and security notices: " email
  [[ "$email" == *"@"* ]] || die "Please enter a valid email address."
  dns_check "$domain" || confirm "Continue with SSL anyway?" || return
  [[ "$include_www" == "yes" ]] && dns_check "www.$domain" || true
  install_certbot
  domains=(-d "$domain")
  [[ "$include_www" == "yes" ]] && domains+=(-d "www.$domain")
  info "Requesting a Let's Encrypt certificate and enabling HTTPS..."
  root_run certbot --nginx "${domains[@]}" --email "$email" --agree-tos --no-eff-email --redirect
  ok "HTTPS is enabled. Certbot also installed automatic renewal where supported."
}

configure_domain() {
  local app port domain include_www="no"
  install_nginx
  show_pm2_apps || true
  read -r -p "PM2 app name or id (for your reference): " app
  [[ -n "$app" ]] && pm2 describe "$app" >/dev/null 2>&1 ||
    warn "That PM2 process was not found. You can still configure a listening port manually."
  read -r -p "Local port used by the app (for example 3000): " port
  valid_port "$port" || die "Port must be between 1 and 65535."
  read -r -p "Domain name (for example app.example.com): " domain
  valid_domain "$domain" || die "Invalid domain name: $domain"
  confirm "Also serve www.$domain?" && include_www="yes"

  if command -v curl >/dev/null 2>&1 && ! curl -fsS --max-time 3 "http://127.0.0.1:$port/" >/dev/null 2>&1; then
    warn "Nothing answered over HTTP on 127.0.0.1:$port."
    confirm "Write the Nginx configuration anyway?" || return
  fi
  dns_check "$domain" || true
  write_nginx_config "$domain" "$port" "$include_www"
  if confirm "Apply a free Let's Encrypt SSL certificate now?"; then
    enable_ssl "$domain" "$include_www"
  else
    info "Run this tool later and choose 'Enable SSL' after DNS points to this server."
  fi
}

write_pm2_app_config() {
  local env_file=$1 name=$2 project=$3 script=$4 npm_script=$5 instances=$6 memory=$7 port=$8 environment=$9
  jq -n --rawfile values "$env_file" --arg name "$name" --arg cwd "$project" \
    --arg script "$script" --arg npm_script "$npm_script" --argjson instances "$instances" \
    --arg memory "$memory" --arg port "$port" --arg environment "$environment" '
    ($values | split("\u0000") | .[:-1]) as $pairs |
    (reduce range(0; $pairs|length; 2) as $i ({}; .[$pairs[$i]] = $pairs[$i+1])) as $extra |
    {apps:[{name:$name,cwd:$cwd,script:$script,
      args:(if $npm_script == "" then [] else ["run",$npm_script] end),
      interpreter:(if $npm_script == "" then "node" else "none" end),
      exec_mode:(if $instances > 1 then "cluster" else "fork" end),
      instances:$instances,max_memory_restart:$memory,autorestart:true,
      exp_backoff_restart_delay:100,min_uptime:10000,max_restarts:10,
      kill_timeout:5000,watch:false,time:true,
      env:($extra + {PORT:$port,NODE_ENV:$environment})}]}'
}

pm2_app_guide() (
  local project name kind entry script npm_script='' port environment instances=1 memory
  local key value stage destination config processes install_deps=0 build_app=0
  umask 077
  rule 'START AN APP WITH PM2'
  if ((DRY_RUN)); then
    info 'Would guide project, npm/Node entry, port, environment, memory and instances; review before starting.'
    return
  fi
  command -v pm2 >/dev/null 2>&1 || install_pm2 || return 1
  ensure_release_tools || return 1
  stage=$(mktemp -d) || return 1
  trap 'rm -rf -- "$stage"' EXIT
  : > "$stage/environment"
  rule '1/5  PROJECT'
  while true; do
    read -r -p "App folder [$PWD] (q to cancel): " project || return
    [[ "$project" != q ]] || return 0
    project=${project:-$PWD}
    project=${project/#\~/$HOME}
    [[ -d "$project" ]] && { project=$(cd -- "$project" && pwd -P); break; }
    warn 'That folder does not exist.'
  done
  while true; do
    read -r -p 'App name (letters, numbers, underscores, hyphens): ' name || return
    [[ "$name" =~ ^[A-Za-z][A-Za-z0-9_-]{0,63}$ ]] || { warn 'Enter a name starting with a letter, up to 64 characters.'; continue; }
    processes=$(pm2 jlist) || return 1
    printf '%s' "$processes" | jq -e 'type == "array"' >/dev/null || { warn 'Could not read the PM2 app list.'; return 1; }
    if printf '%s' "$processes" | jq -e --arg name "$name" 'any(.[]; .name == $name)' >/dev/null; then
      warn 'PM2 already has that name. Choose another name.'
    else break; fi
  done
  rule '2/5  START COMMAND'
  info '1: npm script (recommended for Next.js and similar projects). 2: Node entry file.'
  while true; do
    read -r -p 'Start method [1]: ' kind || return
    kind=${kind:-1}; [[ "$kind" == 1 || "$kind" == 2 ]] && break
  done
  if [[ "$kind" == 1 ]]; then
    [[ -f "$project/package.json" ]] || { warn 'No package.json in that folder.'; return 1; }
    jq -r '(.scripts // {}) | keys[] | "    " + .' "$project/package.json" || return 1
    while true; do
      read -r -p 'npm script [start]: ' npm_script || return
      npm_script=${npm_script:-start}
      [[ "$npm_script" != -* ]] && jq -e --arg script "$npm_script" '.scripts[$script] | type == "string"' "$project/package.json" >/dev/null && break
      warn 'Choose a script listed in package.json.'
    done
    script=$(command -v npm) || return 1
  else
    while true; do
      read -r -p 'Node entry file, relative to app folder [server.js]: ' entry || return
      entry=${entry:-server.js}
      script="$project/$entry"
      [[ -f "$script" ]] && break
      warn 'That entry file does not exist. Build the app first if required.'
    done
  fi
  if [[ -f "$project/package.json" ]]; then
    confirm 'Install app dependencies before starting?' && install_deps=1
    if jq -e '.scripts.build | type == "string"' "$project/package.json" >/dev/null; then
      confirm 'Run the npm build script before starting?' && build_app=1
    fi
  fi
  rule '3/5  PORT AND ENVIRONMENT'
  info 'Your app must read PORT for this setting to take effect. Framework-specific settings may also be required.'
  while true; do
    read -r -p 'App port [3000]: ' port || return
    port=${port:-3000}; valid_port "$port" && break
    warn 'Use a port from 1 to 65535.'
  done
  read -r -p 'NODE_ENV [production]: ' environment || return
  environment=${environment:-production}
  info 'Add environment variables such as DATABASE_URL. Values are hidden. Press Enter on a name to finish.'
  info 'Values are saved in a private PM2 config file and PM2 state. Existing .env files are left to your app to load.'
  while true; do
    read -r -p 'Environment variable name: ' key || return
    [[ -n "$key" ]] || break
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "$key" != PORT && "$key" != NODE_ENV ]] || { warn 'Use a valid variable name other than PORT or NODE_ENV.'; continue; }
    read_hidden_paste_input "Value for $key:"
    value=$HIDDEN_PASTE_VALUE; HIDDEN_PASTE_VALUE=''
    printf '%s\0%s\0' "$key" "$value" >> "$stage/environment"
    value=''
  done
  rule '4/5  PROCESS SETTINGS'
  info 'One process is the safest default. Memory restart is a recovery threshold, not a hard RAM limit.'
  if [[ "$kind" == 2 ]]; then
    info 'Multiple instances use Node cluster mode. Use only for apps that support shared ports and keep session state outside the process.'
    while true; do
      read -r -p 'Instances [1]: ' instances || return
      instances=${instances:-1}
      [[ "$instances" =~ ^[1-9][0-9]?$ ]] && break
      warn 'Enter a number from 1 to 99.'
    done
  else info 'npm scripts use a single process; cluster mode requires a direct Node entry file.'; fi
  while true; do
    read -r -p 'Restart above memory usage [512M]: ' memory || return
    memory=${memory:-512M}
    [[ "$memory" =~ ^[1-9][0-9]*[MG]$ ]] && break
    warn 'Use a value such as 256M, 512M, or 1G.'
  done
  config="${XDG_STATE_HOME:-$HOME/.local/state}/neem/pm2/$name.ecosystem.json"
  [[ ! -e "$config" ]] || { warn "Saved configuration already exists: $config. Choose another app name."; return 1; }
  write_pm2_app_config "$stage/environment" "$name" "$project" "$script" "$npm_script" "$instances" "$memory" "$port" "$environment" > "$stage/app.json" || return 1
  rule '5/5  REVIEW AND START'
  printf '  App: %s\n  Folder: %s\n  Entry: %s %s\n  Port: %s\n  NODE_ENV: %s\n  Instances: %s\n  Memory restart: %s per process\n' "$name" "$project" "$script" "$npm_script" "$port" "$environment" "$instances" "$memory"
  printf '  Install dependencies: %s | Build: %s\n' "$install_deps" "$build_app"
  info 'Automatic crash recovery enabled; file watching disabled. Environment values are hidden.'
  confirm 'Save this configuration and start the app?' || { info 'App setup cancelled.'; return 0; }
  cd -- "$project" || return 1
  if ((install_deps)); then
    if [[ -f package-lock.json ]]; then package_step 'Installing app dependencies' run npm ci || return 1
    else package_step 'Installing app dependencies' run npm install || return 1; fi
  fi
  if ((build_app)); then
    package_step 'Building app' run node -e '
      const fs=require("fs"),cp=require("child_process");
      const app=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).apps[0];
      const r=cp.spawnSync("npm",["run","build"],{cwd:app.cwd,env:{...process.env,...app.env},stdio:"inherit"});
      if(r.error)console.error(r.error.message);process.exit(r.status===null?1:r.status);
    ' "$stage/app.json" || return 1
  fi
  destination=$(dirname -- "$config")
  mkdir -p -- "$destination" || return 1
  (set -o noclobber; cat "$stage/app.json" > "$config") || return 1
  package_step 'Starting app' run pm2 start "$config" || return 1
  ok "App submitted to PM2. Configuration: $config"
  show_pm2_apps
  printf '  View logs: pm2 logs %s\n  Monitor CPU/memory: pm2 monit\n' "$name"
  info 'An online PM2 process does not by itself confirm the website is healthy. Check the app before connecting a domain.'
  if confirm 'Configure restart after server reboot now?'; then pm2_startup; fi
)

pm2_startup() {
  local processes count
  need_command pm2
  rule 'PM2 STARTUP'
  info 'Restore the current PM2 app list when this machine restarts.'
  if ((DRY_RUN)); then
    info 'Would show managed apps and ask before saving them and registering startup.'
    return
  fi
  processes=$(pm2 jlist) || return 1
  count=$(printf '%s' "$processes" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const a=JSON.parse(s);if(!Array.isArray(a))throw Error();console.log(a.length)}catch{process.exit(1)}})') || {
    warn 'Could not read the PM2 app list.'; return 1;
  }
  if ((count == 0)); then
    info 'PM2 is not managing any apps yet. There is nothing to restore at boot.'
    if confirm 'Open the guided app setup now?'; then pm2_app_guide; fi
    return
  fi
  show_pm2_apps
  confirm "Save these $count app(s) and configure startup?" || return
  package_step 'Saving PM2 apps' run pm2 save || return 1
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    package_step 'Registering PM2 startup' run pm2 startup || return 1
    ok "PM2 startup configured for $count app(s)."
  else
    info 'PM2 will show the administrator command needed to register startup for your user.'
    run pm2 startup || return 1
    info 'Run the displayed sudo command to finish startup registration.'
  fi
}

quick_tunnel_state_root() {
  printf '%s/neem/quick-tunnels' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

start_background_quick_tunnel() {
  local origin=$1 port=$2 root stamp log pid process_start published_at tunnel_url="" attempt
  local -a spinner=('|' '/' '-' '\')
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  %shttps://example.trycloudflare.com%s\n' "$CREAM" "$RESET"
    return
  fi
  root=$(quick_tunnel_state_root)
  mkdir -p "$root"
  stamp="$(date +%Y%m%d-%H%M%S)-$$"
  log="$root/$stamp.log"
  nohup cloudflared tunnel --url "$origin" >"$log" 2>&1 </dev/null &
  pid=$!
  disown "$pid" 2>/dev/null || true
  [[ -t 1 ]] || printf '  Creating Quick Tunnel...\n'
  for ((attempt=0; attempt<45; attempt++)); do
    if [[ -t 1 ]]; then
      printf '\r  Creating Quick Tunnel... %s' "${spinner[attempt % ${#spinner[@]}]}"
    fi
    sleep 0.5
    tunnel_url=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$log" 2>/dev/null | head -n1 || true)
    [[ -n "$tunnel_url" ]] && break
    kill -0 "$pid" 2>/dev/null || break
  done
  [[ -t 1 ]] && printf '\r%48s\r' ''
  if [[ -z "$tunnel_url" ]]; then
    kill "$pid" 2>/dev/null || true
    die "Cloudflare did not return a Quick Tunnel URL. Diagnostics: $log"
  fi
  process_start=$(ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//' || true)
  published_at=$(date '+%Y-%m-%d %H:%M')
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$pid" "$port" "$tunnel_url" "$origin" "$log" "$process_start" "$published_at" > "$root/$pid.quick.state"
  printf '\n  %s%s%s\n' "$CREAM" "$tunnel_url" "$RESET"
  printf '%s  Running in the background. Return here and choose option 3 to stop it.%s\n' "$MUTED" "$RESET"
}

manage_cloudflare_tunnels() {
  local root state pid port tunnel_url origin log process_start current_start published_at choice index process_name selected_index
  local managed_file managed_present=0 managed_status hostname
  local -a files=() pids=() ports=() urls=() origins=() logs=() starts=() published=() types=() statuses=() state_files=()
  root=$(quick_tunnel_state_root)
  mkdir -p "$root"
  shopt -s nullglob
  files=("$root"/*.quick.state)
  shopt -u nullglob
  for state in "${files[@]}"; do
    IFS='|' read -r pid port tunnel_url origin log process_start published_at < "$state" || true
    process_name=$(ps -p "$pid" -o comm= 2>/dev/null || true)
    current_start=$(ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//' || true)
    if kill -0 "$pid" 2>/dev/null && [[ "$process_name" == *cloudflared* && -n "$process_start" && "$current_start" == "$process_start" ]]; then
      pids+=("$pid"); ports+=("$port"); urls+=("$tunnel_url"); origins+=("$origin"); logs+=("$log"); starts+=("$process_start")
      published+=("${published_at:-unknown}"); types+=("Quick"); statuses+=("RUNNING"); state_files+=("$state")
    else
      rm -f "$state"
    fi
  done

  managed_file="$root/managed.state"
  [[ -f "$managed_file" ]] && managed_present=1
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files cloudflared.service 2>/dev/null | grep -q '^cloudflared\.service'; then managed_present=1; fi
  if [[ "$OS" == "macos" ]] && launchctl list 2>/dev/null | grep -q 'com.cloudflare.cloudflared'; then managed_present=1; fi
  if ((managed_present)); then
    if [[ ! -f "$managed_file" ]]; then
      warn "This managed service predates NEEM tunnel tracking, so its hostname and port are not stored locally."
      if confirm "Add its display details now?"; then
        while true; do
          read -r -p "Local application port used by this tunnel: " port
          valid_port "$port" && break
          warn "Port must be between 1 and 65535. Please try again."
        done
        while true; do
          read -r -p "Public hostname (for example app.example.com): " hostname
          valid_domain "$hostname" && break
          warn "That hostname is invalid. Please try again."
        done
        while true; do
          read -r -p "Published date/time (for example 2026-08-09 22:35, or Enter if unknown): " published_at
          [[ -z "$published_at" || "$published_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}$ ]] && break
          warn "Use YYYY-MM-DD HH:MM, or press Enter if unknown."
        done
        [[ -n "$published_at" ]] || published_at=unknown
        printf '%s|%s|%s|%s|%s\n' "$hostname" "$port" "https://$hostname" "http://127.0.0.1:$port" "$published_at" > "$managed_file"
        ok "Managed tunnel details saved."
      fi
    fi
    hostname="unknown"; port="?"; tunnel_url="Configured in Cloudflare"; origin="unknown"; published_at="unknown"
    [[ -f "$managed_file" ]] && IFS='|' read -r hostname port tunnel_url origin published_at < "$managed_file" || true
    if command -v systemctl >/dev/null 2>&1; then
      systemctl is-active --quiet cloudflared && managed_status=RUNNING || managed_status=STOPPED
    elif pgrep -f 'cloudflared.*tunnel.*run' >/dev/null 2>&1; then managed_status=RUNNING
    else managed_status=STOPPED
    fi
    pids+=(""); ports+=("$port"); urls+=("$tunnel_url"); origins+=("$origin"); logs+=(""); starts+=("")
    published+=("$published_at"); types+=("Managed"); statuses+=("$managed_status"); state_files+=("$managed_file")
  fi

  if ((${#types[@]} == 0)); then info "No NEEM Cloudflare Tunnels were found."; return; fi
  rule "CLOUDFLARE TUNNELS"
  printf '%s  %-3s %-9s %-9s %-6s %-17s %s%s\n' "$SELECTED" '#' TYPE STATUS PORT PUBLISHED 'PUBLIC URL' "$RESET"
  for index in "${!pids[@]}"; do
    printf '  %-3d %-9s %-9s %-6s %-17s %s\n' "$((index + 1))" "${types[index]}" "${statuses[index]}" "${ports[index]}" "${published[index]}" "${urls[index]}"
  done
  read -r -p "Choose a tunnel to stop/start, A to stop all running tunnels, or Enter to return: " choice
  [[ -n "$choice" ]] || return
  if [[ "$choice" =~ ^[Aa]$ ]]; then
    selected_index=-1
  elif [[ "$choice" =~ ^[0-9]+$ ]] && ((10#$choice >= 1 && 10#$choice <= ${#pids[@]})); then
    selected_index=$((10#$choice - 1))
  else
    warn "Invalid selection."
    return
  fi
  if ((selected_index == -1)); then confirm "Stop all running tunnels?" || return; fi
  for index in "${!pids[@]}"; do
    ((selected_index == -1 || selected_index == index)) || continue
    if [[ "${types[index]}" == "Managed" ]]; then
      if [[ "${statuses[index]}" == "RUNNING" ]]; then
        ((selected_index == -1)) || confirm "Stop managed tunnel ${urls[index]}?" || continue
        if [[ "$OS" == "macos" ]]; then root_run launchctl stop com.cloudflare.cloudflared
        else root_run systemctl stop cloudflared
        fi
        ok "Stopped ${urls[index]}."
      elif ((selected_index != -1)); then
        confirm "Start managed tunnel ${urls[index]}?" || continue
        if [[ "$OS" == "macos" ]]; then root_run launchctl start com.cloudflare.cloudflared
        else root_run systemctl start cloudflared
        fi
        ok "Started ${urls[index]}."
      fi
    else
      ((selected_index == -1)) || confirm "Stop Quick Tunnel ${urls[index]}?" || continue
      kill "${pids[index]}" 2>/dev/null || true
      rm -f "${state_files[index]}"
      ok "Stopped ${urls[index]}."
    fi
  done
}

cloudflare_tunnel_guide() {
  local mode port origin hostname retry pasted_value="" token="" existing=0 url="https://one.dash.cloudflare.com/"
  install_cloudflared
  if [[ $DRY_RUN -eq 0 ]] && ! command -v cloudflared >/dev/null 2>&1; then
    die "cloudflared was installed but is not on PATH yet. Open a new terminal and run NEEM again."
  fi

  rule "CLOUDFLARE TUNNEL"
  printf '  %s1  Start Quick Tunnel%s     Run a temporary public URL in the background.\n' "$CREAM" "$RESET"
  printf '  %s2  Set up managed tunnel%s  Production hostname and automatic startup.\n' "$CREAM" "$RESET"
  printf '  %s3  View or stop tunnels%s   Manage Quick and managed tunnels.\n' "$CREAM" "$RESET"
  if [[ $DRY_RUN -eq 1 ]]; then mode=2
  else read -r -p "Choose 1, 2, or 3: " mode
  fi
  [[ "$mode" == 1 || "$mode" == 2 || "$mode" == 3 ]] || { info "Cloudflare Tunnel setup cancelled."; return; }
  if [[ "$mode" == 3 ]]; then manage_cloudflare_tunnels; return; fi

  port=""
  while true; do
    [[ -n "$port" ]] || read -r -p "Local application port (for example 3000): " port
    if ! valid_port "$port"; then
      warn "Port must be between 1 and 65535. Please try again."
      port=""
      continue
    fi
    origin="http://127.0.0.1:$port"
    [[ $DRY_RUN -eq 1 ]] && break
    if ! command -v curl >/dev/null 2>&1 || curl -fsS --max-time 3 "$origin/" >/dev/null 2>&1; then
      ok "The local application answered at $origin."
      break
    fi
    warn "Nothing answered over HTTP at $origin."
    read -r -p "Press Enter or R to retry, type a new port, A to continue anyway, or C to cancel: " retry
    case "$retry" in
      A|a) break ;;
      C|c) info "Cloudflare Tunnel setup cancelled."; return ;;
      ""|R|r) ;;
      *) port=$retry ;;
    esac
  done

  if [[ "$mode" == 1 ]]; then
    start_background_quick_tunnel "$origin" "$port"
    return
  fi

  while true; do
    read -r -p "Public hostname to use (for example app.example.com): " hostname
    valid_domain "$hostname" && break
    warn "That hostname is invalid. Please try this step again."
  done

  printf '  %sIn the Cloudflare dashboard:%s\n' "$CREAM" "$RESET"
  printf '%s  1. Open Networking > Tunnels and create a Cloudflared tunnel.%s\n' "$MUTED" "$RESET"
  printf '%s  2. Select this machine\x27s operating system.%s\n' "$MUTED" "$RESET"
  printf '%s  3. Copy the complete cloudflared service install command.%s\n' "$MUTED" "$RESET"
  printf '%s  One cloudflared service can serve several published routes on this machine.%s\n' "$MUTED" "$RESET"
  if [[ $DRY_RUN -eq 0 ]] && confirm "Open the Cloudflare Tunnels dashboard now?"; then
    if [[ "$OS" == "macos" ]]; then run open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then run xdg-open "$url"
    else info "Open $url in a browser."
    fi
  else
    info "Dashboard: $url"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    root_run_secret "dry-run-placeholder"
    info "Dry run complete. No token was requested and no service was installed."
    return
  fi

  while [[ -z "$token" ]]; do
    info "Press Ctrl+Shift+V (or right-click) to paste, then press Enter. The value stays hidden."
    read_hidden_paste_input "Paste the token or full cloudflared install command:"
    pasted_value=$HIDDEN_PASTE_VALUE
    HIDDEN_PASTE_VALUE=""
    [[ -n "$pasted_value" ]] && ok "Paste received. Validating token..."
    token=$(printf '%s' "$pasted_value" | grep -Eo 'eyJ[A-Za-z0-9_-]{20,}' | head -n1 || true)
    pasted_value=""
    if [[ -z "$token" ]] || ! valid_cloudflare_tunnel_token "$token"; then
      token=""
      warn "No valid Cloudflare Tunnel token was found. Copy a fresh install command and retry this step."
    fi
  done
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files cloudflared.service 2>/dev/null | grep -q '^cloudflared\.service'; then
    existing=1
  elif [[ "$OS" == "macos" ]] && launchctl list 2>/dev/null | grep -q 'com.cloudflare.cloudflared'; then
    existing=1
  fi
  if ((existing)); then
    warn "A cloudflared service is already installed on this machine."
    if ! confirm "Replace it with this tunnel token?"; then token=""; return; fi
    root_run cloudflared service uninstall
  fi
  root_run_secret "$token"
  token=""

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet cloudflared; then ok "Cloudflare Tunnel is installed and running as a system service."
    else warn "The service was installed but is not active. Check: sudo systemctl status cloudflared"
    fi
  else
    ok "Cloudflare Tunnel service installation finished."
  fi
  rule "ADD THE PUBLIC HOSTNAME"
  printf '  %sReturn to the tunnel in the Cloudflare dashboard, then:%s\n' "$CREAM" "$RESET"
  printf '%s  1. Continue to Routes and choose Add route > Published application.%s\n' "$MUTED" "$RESET"
  printf '%s  2. Set Hostname to %s.%s\n' "$MUTED" "$hostname" "$RESET"
  printf '%s  3. Set Service URL to %s.%s\n' "$MUTED" "$origin" "$RESET"
  printf '%s  4. Save the route.%s\n' "$MUTED" "$RESET"
  if confirm "Open the Cloudflare dashboard again?"; then
    if [[ "$OS" == "macos" ]]; then run open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then run xdg-open "$url"
    else info "Open $url in a browser."
    fi
  fi
  read -r -p "Press Enter after the published application route is saved..." _
  mkdir -p "$(quick_tunnel_state_root)"
  printf '%s|%s|%s|%s|%s\n' "$hostname" "$port" "https://$hostname" "$origin" "$(date '+%Y-%m-%d %H:%M')" > "$(quick_tunnel_state_root)/managed.state"
  ok "Cloudflare Tunnel configuration finished."
  printf '  %shttps://%s%s\n' "$CREAM" "$hostname" "$RESET"
  info "Cloudflare may need a short time before a newly created hostname becomes reachable."
}
