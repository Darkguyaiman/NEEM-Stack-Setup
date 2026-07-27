#!/usr/bin/env bash
#
# NEEM Stack Setup - interactive Linux/macOS server bootstrapper
# Nginx, Node.js, PM2, MySQL, Micro and Glances

set -Eeuo pipefail

VERSION="1.0.0"
DRY_RUN=0
OS=""
PKG=""

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info() { printf '%sℹ%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
pause() { [[ $DRY_RUN -eq 1 ]] || read -r -p "Press Enter to continue..." _; }

run() {
  printf '%s+%s ' "$BLUE" "$RESET"
  printf '%q ' "$@"
  printf '\n'
  [[ $DRY_RUN -eq 1 ]] || "$@"
}

root_run() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    die "This action needs root access, but sudo is not installed."
  fi
}

confirm() {
  local prompt=${1:-"Continue?"} answer
  [[ $DRY_RUN -eq 1 ]] && return 0
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found."
}

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      OS="macos"
      command -v brew >/dev/null 2>&1 ||
        die "Homebrew is required on macOS. Install it from https://brew.sh and run this again."
      PKG="brew"
      ;;
    Linux)
      OS="linux"
      if command -v apt-get >/dev/null 2>&1; then PKG="apt"
      elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
      elif command -v yum >/dev/null 2>&1; then PKG="yum"
      elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
      elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
      else die "Supported package manager not found (apt, dnf, yum, pacman, or zypper)."
      fi
      ;;
    *) die "Unsupported operating system. On Windows, run neem.ps1 in PowerShell." ;;
  esac
}

package_refresh() {
  case "$PKG" in
    apt) root_run apt-get update ;;
    dnf) root_run dnf makecache ;;
    yum) root_run yum makecache ;;
    pacman) root_run pacman -Sy ;;
    zypper) root_run zypper refresh ;;
    brew) run brew update ;;
  esac
}

package_install() {
  case "$PKG" in
    apt) root_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) root_run dnf install -y "$@" ;;
    yum) root_run yum install -y "$@" ;;
    pacman) root_run pacman -S --needed --noconfirm "$@" ;;
    zypper) root_run zypper --non-interactive install "$@" ;;
    brew) run brew install "$@" ;;
  esac
}

enable_service() {
  local name=$1
  if [[ "$OS" == "macos" ]]; then
    run brew services start "$name"
  elif command -v systemctl >/dev/null 2>&1; then
    root_run systemctl enable --now "$name"
  else
    warn "systemd was not found. Start the '$name' service using your init system."
  fi
}

install_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    ok "Node.js $(node --version) and npm $(npm --version) are already installed."
    return
  fi
  info "Installing Node.js and npm..."
  case "$PKG" in
    brew) package_install node ;;
    *) package_install nodejs npm ;;
  esac
  ok "Node.js installation finished."
}

install_pm2() {
  install_node
  if command -v pm2 >/dev/null 2>&1; then
    ok "PM2 is already installed."
  else
    info "Installing the latest PM2 globally with npm..."
    if [[ "$OS" == "macos" ]]; then run npm install --global pm2@latest
    else root_run npm install --global pm2@latest
    fi
  fi
  ok "PM2 installation finished."
}

install_mysql() {
  if command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1; then
    ok "A MySQL-compatible server is already installed."
    return
  fi
  info "Installing MySQL..."
  case "$PKG" in
    brew) package_install mysql; enable_service mysql ;;
    apt) package_install default-mysql-server; enable_service mysql ;;
    dnf|yum) package_install mysql-server; enable_service mysqld ;;
    pacman) package_install mariadb; root_run mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql; enable_service mariadb ;;
    zypper) package_install mysql-community-server; enable_service mysql ;;
  esac
  ok "Database server installed. Run 'mysql_secure_installation' to harden it."
}

install_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    ok "Nginx is already installed."
    return
  fi
  info "Installing Nginx..."
  package_install nginx
  enable_service nginx
  ok "Nginx installation finished."
}

install_micro() {
  if command -v micro >/dev/null 2>&1; then ok "Micro is already installed."; return; fi
  info "Installing Micro terminal editor..."
  package_install micro
  ok "Micro installation finished."
}

install_glances() {
  if command -v glances >/dev/null 2>&1; then ok "Glances is already installed."; return; fi
  info "Installing Glances in an isolated pipx environment..."
  case "$PKG" in
    brew) package_install glances ;;
    apt) package_install pipx; run pipx ensurepath; run pipx install glances ;;
    dnf|yum) package_install python3-pip; run python3 -m pip install --user --upgrade glances ;;
    pacman) package_install glances ;;
    zypper) package_install python3-pip; run python3 -m pip install --user --upgrade glances ;;
  esac
  ok "Glances installation finished. You may need a new shell before 'glances' is on PATH."
}

install_certbot() {
  if command -v certbot >/dev/null 2>&1; then ok "Certbot is already installed."; return; fi
  info "Installing Certbot..."
  case "$PKG" in
    apt) package_install certbot python3-certbot-nginx ;;
    dnf|yum) package_install certbot python3-certbot-nginx ;;
    pacman) package_install certbot certbot-nginx ;;
    zypper) package_install certbot python3-certbot-nginx ;;
    brew) package_install certbot ;;
  esac
}

install_all() {
  info "This installs Node.js, PM2, MySQL, Nginx, Micro and Glances."
  confirm "Install the complete NEEM stack?" || return
  package_refresh
  install_node
  install_pm2
  install_mysql
  install_nginx
  install_micro
  install_glances
  ok "The NEEM stack is installed."
}

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

health_check() {
  printf '\n%sNEEM stack status%s\n' "$BOLD" "$RESET"
  local item cmd
  for item in "Node.js:node" "npm:npm" "PM2:pm2" "MySQL:mysql" "Nginx:nginx" "Micro:micro" "Glances:glances" "Certbot:certbot"; do
    cmd=${item#*:}
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  %s✓%s %-12s %s\n' "$GREEN" "$RESET" "${item%%:*}" "$(command -v "$cmd")"
    else
      printf '  %s–%s %-12s not installed\n' "$YELLOW" "$RESET" "${item%%:*}"
    fi
  done
  if command -v pm2 >/dev/null 2>&1; then printf '\n'; pm2 ls || true; fi
  if command -v nginx >/dev/null 2>&1; then root_run nginx -t || true; fi
}

component_menu() {
  while true; do
    printf '\n%sInstall a component%s\n' "$BOLD" "$RESET"
    printf '  1) Node.js\n  2) PM2\n  3) MySQL\n  4) Nginx\n'
    printf '  5) Micro editor\n  6) Glances\n  7) Certbot\n  0) Back\n'
    read -r -p "Choose: " choice
    case "$choice" in
      1) install_node ;; 2) install_pm2 ;; 3) install_mysql ;;
      4) install_nginx ;; 5) install_micro ;; 6) install_glances ;;
      7) install_certbot ;; 0) return ;; *) warn "Choose a listed option." ;;
    esac
  done
}

main_menu() {
  while true; do
    clear 2>/dev/null || true
    printf '%sNEEM Stack Setup%s  v%s\n' "$BOLD" "$RESET" "$VERSION"
    printf 'Platform: %s (%s)%s\n\n' "$OS" "$PKG" "$([[ $DRY_RUN -eq 1 ]] && echo ' · dry run')"
    printf '  1) Install complete stack\n'
    printf '  2) Install one component\n'
    printf '  3) Configure PM2 startup\n'
    printf '  4) Connect a domain to a PM2 app\n'
    printf '  5) Enable SSL for an existing domain\n'
    printf '  6) Health check\n'
    printf '  0) Exit\n'
    read -r -p "Choose: " choice
    case "$choice" in
      1) install_all; pause ;; 2) component_menu ;;
      3) pm2_startup; pause ;; 4) configure_domain; pause ;;
      5) enable_ssl; pause ;; 6) health_check; pause ;;
      0) printf 'Goodbye.\n'; return ;; *) warn "Choose a listed option."; pause ;;
    esac
  done
}

usage() {
  cat <<EOF
NEEM Stack Setup v$VERSION

Usage: ./neem.sh [--dry-run] [--health] [--help]

Without options, launches the interactive terminal menu.
  --dry-run  Print privileged/package commands without running them
  --health   Show installed components and validate Nginx
EOF
}

main() {
  local action="menu"
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;; --health) action="health" ;;
      -h|--help) usage; exit 0 ;; *) die "Unknown option: $1" ;;
    esac
    shift
  done
  detect_platform
  if [[ "$action" == "health" ]]; then health_check; else main_menu; fi
}

main "$@"
