# Nginx, domains, TLS, PM2 startup, and Cloudflare Tunnel workflows.
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

pm2_startup() {
  need_command pm2
  run pm2 save
  info "PM2 will print the exact privileged command required by this operating system."
  run pm2 startup
  warn "If PM2 printed a sudo command, run that command once to finish startup registration."
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
