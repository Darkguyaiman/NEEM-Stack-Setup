#!/usr/bin/env bash
#
# NEEM Stack Setup - interactive Linux/macOS server bootstrapper
#
# THESIS: A calm command centre for assembling a server stack, not a numbered
# prompt maze. OWN-WORLD: NEEM red, charcoal surfaces, cream-white type, cool
# gray hierarchy, crisp rules and native checkbox controls. STORY: see the stack,
# select any combination, review it, then install or remove with confidence.
# FIRST VIEWPORT: compact NEEM masthead, platform state, creator credit, then a
# short action menu. FORM: keyboard-operated terminal workbench with a dedicated
# creator card and reversible component management.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
if [[ ! -r "$VERSION_FILE" ]]; then
  printf 'Version file not found: %s\n' "$VERSION_FILE" >&2
  exit 1
fi
VERSION=$(tr -d '\r\n' < "$VERSION_FILE")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Invalid version in %s: %s\n' "$VERSION_FILE" "$VERSION" >&2
  exit 1
fi
DRY_RUN=0
OS=""
PKG=""
SUPPORTS_HYPERLINKS=0

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  ACCENT=$'\033[38;2;197;29;52m'
  DARK_SURFACE=$'\033[48;2;46;46;48m'
  MUTED=$'\033[38;2;128;128;128m'
  SUBTLE=$'\033[38;2;90;90;90m'
  PAPER=$'\033[38;2;245;245;245m'
  CREAM=$'\033[38;2;253;251;247m'
  SELECTED=$'\033[38;2;253;251;247;48;2;46;46;48m'
  BLUE=$ACCENT; GREEN=$PAPER; YELLOW=$MUTED; RED=$ACCENT
  RESET=$'\033[0m'
else
  BOLD=""; ACCENT=""; DARK_SURFACE=""; MUTED=""; SUBTLE=""
  PAPER=""; CREAM=""; SELECTED=""; BLUE=""; GREEN=""; YELLOW=""
  RED=""; RESET=""
fi
if [[ -t 1 && (-n "${WT_SESSION:-}" || -n "${TERM_PROGRAM:-}" ||
  -n "${VTE_VERSION:-}" || -n "${KITTY_WINDOW_ID:-}" || -n "${KONSOLE_VERSION:-}") ]]; then
  SUPPORTS_HYPERLINKS=1
fi

info() { printf '%sℹ%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
pause() { [[ $DRY_RUN -eq 1 ]] || read -r -p "Press Enter to continue..." _; }

hyperlink() {
  local label=$1 url=$2 prefix=${3:-"  "}
  if ((SUPPORTS_HYPERLINKS)); then
    printf '%s%s%s\033]8;;%s\033\\%s\033]8;;\033\\%s\n' "$MUTED" "$prefix" "$PAPER" "$url" "$label" "$RESET"
  else
    printf '%s%s <%s>\n' "$prefix" "$label" "$url"
  fi
}

rule() {
  local title=${1:-} width=68 line fill
  if [[ -n "$title" ]]; then
    printf -v line -- '-- %s ' "$title"
    printf -v fill '%*s' "$((width-${#line}))" ''
    printf '%s%s%s%s\n' "$SUBTLE" "$line" "${fill// /-}" "$RESET"
  else
    printf -v fill '%*s' "$width" ''
    printf '%s%s%s\n' "$SUBTLE" "${fill// /-}" "$RESET"
  fi
}

show_brand() {
  printf '\n%s' "$ACCENT"
  printf '  _   _  _____ _____ __  __\n'
  printf ' | \\ | || ____| ____|  \\/  |\n'
  printf ' |  \\| ||  _| |  _| | |\\/| |\n'
  printf ' | |\\  || |___| |___| |  | |\n'
  printf ' |_| \\_||_____|_____|_|  |_|\n'
  printf '%s%s  Stack Setup%s%s  v%s%s\n' "$CREAM" "$BOLD" "$RESET" "$MUTED" "$VERSION" "$RESET"
  printf '%s  Built with care by Mohamed Aiman%s\n' "$MUTED" "$RESET"
  rule
}

show_creator() {
  local cols row left key url line column compact shift source_row=0 last_cols=-1
  local -a art_lines=()
  if [[ -f "$SCRIPT_DIR/ASCI_ART_ME.txt" ]]; then
    while IFS= read -r line; do
      source_row=$((source_row + 1))
      ((source_row % 6 == 0)) && continue
      compact=""
      for ((column=0; column<${#line}; column++)); do
        (((column + 1) % 8 == 0)) || compact+="${line:column:1}"
      done
      for ((shift=0; shift<12 && ${#compact}>0; shift++)); do
        [[ "${compact:0:1}" == " " ]] && compact=${compact# } || break
      done
      art_lines+=("$compact")
    done < "$SCRIPT_DIR/ASCI_ART_ME.txt"
  else
    art_lines=("  ASCII portrait not found.")
  fi
  while true; do
    cols=$(tput cols 2>/dev/null || printf '120')
    if ((cols != last_cols)); then
      clear 2>/dev/null || true
      if ((cols >= 138)); then
        for ((row=0; row<${#art_lines[@]}; row++)); do
          left=${art_lines[row]}
          printf '%s%-104s%s' "$SUBTLE" "$left" "$RESET"
          case "$row" in
            5) printf '%sMOHAMED AIMAN%s\n' "$ACCENT" "$RESET" ;;
            6) printf '%sCreator of NEEM Stack Setup%s\n' "$MUTED" "$RESET" ;;
            9) hyperlink "mohamedaiman103@gmail.com" "mailto:mohamedaiman103@gmail.com" "[1] Email       " ;;
            11) hyperlink "darkguyaiman.com" "https://darkguyaiman.com" "[2] Portfolio   " ;;
            13) hyperlink "linkedin.com/in/darkguyaiman" "https://www.linkedin.com/in/darkguyaiman" "[3] LinkedIn    " ;;
            15) hyperlink "instagram.com/darkguyaiman" "https://www.instagram.com/darkguyaiman" "[4] Instagram   " ;;
            17) hyperlink "x.com/thedarkguyaiman" "https://x.com/thedarkguyaiman" "[5] X / Twitter " ;;
            19) hyperlink "ko-fi.com/darkguyaiman" "https://ko-fi.com/darkguyaiman" "[6] Ko-fi       " ;;
            21) hyperlink "paypal.me/thedarkguyaiman" "https://paypal.me/thedarkguyaiman" "[7] PayPal      " ;;
            25)
              if ((SUPPORTS_HYPERLINKS)); then
                printf '%sCtrl+click a link, or press 1-7 to open.%s\n' "$MUTED" "$RESET"
              else
                printf '%sPress 1-7 to open a link.%s\n' "$MUTED" "$RESET"
              fi
              ;;
            *) printf '\n' ;;
          esac
        done
      else
        printf '%s' "$SUBTLE"
        printf '%s\n' "${art_lines[@]}"
        printf '%s' "$RESET"
        rule "CREATOR"
        printf '  %s%sMohamed Aiman%s | Creator of NEEM Stack Setup\n' "$CREAM" "$BOLD" "$RESET"
        hyperlink "mohamedaiman103@gmail.com" "mailto:mohamedaiman103@gmail.com" "  [1] Email       "
        hyperlink "darkguyaiman.com" "https://darkguyaiman.com" "  [2] Portfolio   "
        hyperlink "linkedin.com/in/darkguyaiman" "https://www.linkedin.com/in/darkguyaiman" "  [3] LinkedIn    "
        hyperlink "instagram.com/darkguyaiman" "https://www.instagram.com/darkguyaiman" "  [4] Instagram   "
        hyperlink "x.com/thedarkguyaiman" "https://x.com/thedarkguyaiman" "  [5] X / Twitter "
        hyperlink "ko-fi.com/darkguyaiman" "https://ko-fi.com/darkguyaiman" "  [6] Ko-fi       "
        hyperlink "paypal.me/thedarkguyaiman" "https://paypal.me/thedarkguyaiman" "  [7] PayPal      "
      fi
      printf '\n%s  Press 1-7 to open a link | Enter or Esc to return | Resize to reflow%s\n' "$MUTED" "$RESET"
      last_cols=$cols
    fi
    if ! IFS= read -rsn1 -t 0.1 key < /dev/tty; then
      continue
    fi
    case "$key" in
      1) url="mailto:mohamedaiman103@gmail.com" ;;
      2) url="https://darkguyaiman.com" ;;
      3) url="https://www.linkedin.com/in/darkguyaiman" ;;
      4) url="https://www.instagram.com/darkguyaiman" ;;
      5) url="https://x.com/thedarkguyaiman" ;;
      6) url="https://ko-fi.com/darkguyaiman" ;;
      7) url="https://paypal.me/thedarkguyaiman" ;;
      ""|$'\e') return ;;
      *) continue ;;
    esac
    if [[ "$OS" == "macos" ]]; then run open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then run xdg-open "$url"
    else warn "Open this address in your browser: $url"
    fi
    last_cols=-1
  done
}

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

root_run_secret() {
  local token=$1
  printf '%s+%s cloudflared service install <TUNNEL_TOKEN hidden>\n' "$BLUE" "$RESET"
  [[ $DRY_RUN -eq 1 ]] && return 0
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    cloudflared service install "$token"
  elif command -v sudo >/dev/null 2>&1; then
    sudo cloudflared service install "$token"
  else
    die "This action needs root access, but sudo is not installed."
  fi
}

valid_cloudflare_tunnel_token() {
  local token=$1 normalized decoded padding
  [[ "$token" =~ ^eyJ[A-Za-z0-9_-]{20,}$ ]] || return 1
  normalized=${token//-/+}
  normalized=${normalized//_/\/}
  case $((${#normalized} % 4)) in
    2) padding='==' ;;
    3) padding='=' ;;
    1) return 1 ;;
    *) padding='' ;;
  esac
  normalized+=$padding
  decoded=$(printf '%s' "$normalized" | base64 --decode 2>/dev/null ||
    printf '%s' "$normalized" | base64 -D 2>/dev/null || true)
  [[ "$decoded" == \{*\} && "$decoded" == *'"a"'* && "$decoded" == *'"t"'* && "$decoded" == *'"s"'* ]]
}

confirm() {
  local prompt=${1:-"Continue?"} answer
  [[ $DRY_RUN -eq 1 ]] && return 0
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

read_hidden_paste_input() {
  local prompt=$1 character visible_stars=0 maximum_stars=12
  HIDDEN_PASTE_VALUE=""
  printf '%s ' "$prompt"
  while IFS= read -rsn1 character; do
    [[ -n "$character" ]] || break
    case "$character" in
      $'\b'|$'\177')
        if [[ -n "$HIDDEN_PASTE_VALUE" ]]; then
          HIDDEN_PASTE_VALUE=${HIDDEN_PASTE_VALUE%?}
          if ((visible_stars > 0 && ${#HIDDEN_PASTE_VALUE} < maximum_stars)); then
            printf '\b \b'
            visible_stars=$((visible_stars - 1))
          fi
        fi
        ;;
      *)
        HIDDEN_PASTE_VALUE+=$character
        if ((visible_stars < maximum_stars)); then
          printf '*'
          visible_stars=$((visible_stars + 1))
        fi
        ;;
    esac
  done
  printf '\n'
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

update_neem() {
  local repository="https://github.com/Darkguyaiman/NEEM-Stack-Setup.git"
  local archive_url="https://github.com/Darkguyaiman/NEEM-Stack-Setup/archive/refs/heads/main.zip"
  local current latest temp_root temp_base archive source new_version
  rule "NEEM UPDATE"
  if [[ -d "$SCRIPT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
      die "Local project changes are present. Commit or stash them before running neem --update."
    fi
    info "Checking GitHub for updates..."
    run git -C "$SCRIPT_DIR" fetch origin main
    current=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
    latest=$(git -C "$SCRIPT_DIR" rev-parse origin/main)
    if [[ "$current" == "$latest" ]]; then
      ok "NEEM v$VERSION is already current."
    else
      run git -C "$SCRIPT_DIR" merge --ff-only origin/main
      new_version=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")
      ok "NEEM was updated to v$new_version."
    fi
  else
    warn "This copy was downloaded without Git history."
    confirm "Download the latest files from $repository and replace NEEM program files?" || return
    need_command curl
    need_command unzip
    temp_root=$(mktemp -d)
    archive="$temp_root/neem-main.zip"
    info "Downloading the latest NEEM release files from GitHub..."
    run curl --fail --location --output "$archive" "$archive_url"
    run unzip -q "$archive" -d "$temp_root"
    source=$(find "$temp_root" -mindepth 1 -maxdepth 1 -type d -name 'NEEM-Stack-Setup-*' | head -n1)
    [[ -n "$source" && -r "$source/VERSION" ]] || die "The downloaded NEEM archive was not valid."
    run cp -R "$source/." "$SCRIPT_DIR/"
    new_version=$(tr -d '\r\n' < "$SCRIPT_DIR/VERSION")
    temp_base=${TMPDIR:-/tmp}
    temp_base=${temp_base%/}
    case "$temp_root" in
      "$temp_base"/*) rm -rf -- "$temp_root" ;;
      *) warn "Temporary update files were retained at $temp_root." ;;
    esac
    ok "NEEM was updated to v$new_version."
  fi
  run bash "$SCRIPT_DIR/install-neem-command.sh"
  info "Run neem again to use the updated version."
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

package_remove() {
  case "$PKG" in
    apt) root_run apt-get remove -y "$@" ;;
    dnf) root_run dnf remove -y "$@" ;;
    yum) root_run yum remove -y "$@" ;;
    pacman) root_run pacman -R --noconfirm "$@" ;;
    zypper) root_run zypper --non-interactive remove "$@" ;;
    brew) run brew uninstall "$@" ;;
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

install_cloudflared() {
  local machine release_arch temp url
  if command -v cloudflared >/dev/null 2>&1; then
    ok "Cloudflare Tunnel (cloudflared) is already installed."
    return
  fi
  info "Installing Cloudflare Tunnel..."
  case "$PKG" in
    brew|pacman) package_install cloudflared ;;
    *)
      need_command curl
      machine=$(uname -m)
      case "$machine" in
        x86_64|amd64) release_arch=amd64 ;;
        aarch64|arm64) release_arch=arm64 ;;
        armv6l|armv7l) release_arch=arm ;;
        i386|i486|i586|i686) release_arch=386 ;;
        *) die "Cloudflare Tunnel does not have a supported download for architecture: $machine" ;;
      esac
      temp=$(mktemp)
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$release_arch"
      run curl --fail --location --output "$temp" "$url"
      root_run install -m 0755 "$temp" /usr/local/bin/cloudflared
      rm -f "$temp"
      ;;
  esac
  ok "Cloudflare Tunnel installation finished."
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
  local index fn
  local -a needed=()
  for index in 0 1 2 3 4 5; do
    component_installed "$index" || needed+=("$index")
  done
  if ((${#needed[@]} == 0)); then
    ok "The complete NEEM stack is already installed. Nothing to do."
    return
  fi
  rule "COMPLETE STACK PLAN"
  for index in "${needed[@]}"; do printf '  + %s\n' "${COMPONENT_NAMES[index]}"; done
  info "${#needed[@]} missing component(s) will be installed; existing tools are skipped."
  confirm "Install the missing components?" || return
  package_refresh
  for index in "${needed[@]}"; do
    fn=${COMPONENT_INSTALL[index]}
    "$fn"
  done
  ok "The NEEM stack is installed."
}

remove_node() {
  warn "Removing Node.js may also make global npm tools such as PM2 unavailable."
  case "$PKG" in
    brew) package_remove node ;;
    *) package_remove nodejs npm ;;
  esac
}

remove_pm2() {
  need_command npm
  if [[ "$OS" == "macos" ]]; then run npm uninstall --global pm2
  else root_run npm uninstall --global pm2
  fi
}

remove_mysql() {
  warn "The database package will be removed; database files and configuration are intentionally retained."
  case "$PKG" in
    brew) run brew services stop mysql || true; package_remove mysql ;;
    apt) package_remove default-mysql-server ;;
    dnf|yum) package_remove mysql-server ;;
    pacman) package_remove mariadb ;;
    zypper) package_remove mysql-community-server ;;
  esac
}

remove_nginx() {
  if [[ "$OS" == "macos" ]]; then run brew services stop nginx || true; fi
  package_remove nginx
}

remove_cloudflared() {
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files cloudflared.service 2>/dev/null | grep -q '^cloudflared\.service'; then
    root_run cloudflared service uninstall
  elif [[ "$OS" == "macos" ]] && launchctl list 2>/dev/null | grep -q 'com.cloudflare.cloudflared'; then
    root_run cloudflared service uninstall
  fi
  case "$PKG" in
    brew|pacman) package_remove cloudflared ;;
    *) root_run rm -f /usr/local/bin/cloudflared ;;
  esac
  ok "Cloudflare Tunnel removal finished. Cloudflare dashboard routes were left unchanged."
}

remove_micro() { package_remove micro; }

remove_glances() {
  case "$PKG" in
    brew|pacman) package_remove glances ;;
    apt) command -v pipx >/dev/null 2>&1 && run pipx uninstall glances || package_remove glances ;;
    dnf|yum|zypper) run python3 -m pip uninstall --yes glances ;;
  esac
}

remove_certbot() {
  case "$PKG" in
    apt|dnf|yum|zypper) package_remove certbot python3-certbot-nginx ;;
    pacman) package_remove certbot certbot-nginx ;;
    brew) package_remove certbot ;;
  esac
}

COMPONENT_NAMES=("Node.js" "PM2 process manager" "MySQL Server" "Nginx" "Micro editor" "Glances monitor" "Certbot SSL" "Cloudflare Tunnel")
COMPONENT_INSTALL=(install_node install_pm2 install_mysql install_nginx install_micro install_glances install_certbot install_cloudflared)
COMPONENT_REMOVE=(remove_node remove_pm2 remove_mysql remove_nginx remove_micro remove_glances remove_certbot remove_cloudflared)
SELECTED_COMPONENTS=()

component_installed() {
  case "$1" in
    0) command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 ;;
    1) command -v pm2 >/dev/null 2>&1 ;;
    2) command -v mysqld >/dev/null 2>&1 || command -v mariadbd >/dev/null 2>&1 ;;
    3) command -v nginx >/dev/null 2>&1 ;;
    4) command -v micro >/dev/null 2>&1 ;;
    5) command -v glances >/dev/null 2>&1 ;;
    6) command -v certbot >/dev/null 2>&1 ;;
    7) command -v cloudflared >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

select_components() {
  local verb=$1 cursor=0 key rest index position component target=1 mark first_render=1
  local -a available=() checked=()
  SELECTED_COMPONENTS=()
  for index in "${!COMPONENT_NAMES[@]}"; do
    if [[ "$verb" == "Install" ]]; then
      component_installed "$index" || available+=("$index")
    else
      component_installed "$index" && available+=("$index")
    fi
  done
  if ((${#available[@]} == 0)); then
    clear 2>/dev/null || true
    show_brand
    if [[ "$verb" == "Install" ]]; then ok "Every available component is already installed."
    else info "No managed components are currently installed."
    fi
    return 1
  fi
  for index in "${!available[@]}"; do checked+=(0); done
  if [[ ! -t 0 || ! -r /dev/tty ]]; then
    warn "The checkbox picker needs an interactive terminal."
    return 1
  fi
  clear 2>/dev/null || true
  show_brand
  printf '  %s%s%s components%s\n' "$CREAM" "$BOLD" "$verb" "$RESET"
  printf '%s  Up/Down move | Space tick | A all | Enter continue | Esc cancel%s\n\n' "$MUTED" "$RESET"
  while true; do
    if ((first_render)); then first_render=0
    else printf '\033[%dA' "${#available[@]}"
    fi
    for position in "${!available[@]}"; do
      component=${available[position]}
      if ((position == cursor)); then
        if ((checked[position])); then mark=x; else mark=' '; fi
        printf '\033[2K\r%s  > [%s] %-28s %-10s %s\n' "$SELECTED" "$mark" "${COMPONENT_NAMES[component]}" "$([[ "$verb" == "Install" ]] && echo needed || echo installed)" "$RESET"
      elif ((checked[position])); then
        printf '\033[2K\r    [%sx%s] %s%s%s\n' "$ACCENT" "$RESET" "$CREAM" "${COMPONENT_NAMES[component]}" "$RESET"
      else
        printf '\033[2K\r%s    [ ] %s%s\n' "$CREAM" "${COMPONENT_NAMES[component]}" "$RESET"
      fi
    done

    IFS= read -rsn1 key < /dev/tty || true
    if [[ "$key" == $'\e' ]]; then
      rest=""
      IFS= read -rsn2 -t 0.1 rest < /dev/tty || true
      case "$rest" in
        '[A') cursor=$(((cursor - 1 + ${#available[@]}) % ${#available[@]})) ;;
        '[B') cursor=$(((cursor + 1) % ${#available[@]})) ;;
        '') return 1 ;;
      esac
    elif [[ "$key" == " " ]]; then
      checked[cursor]=$((1-checked[cursor]))
    elif [[ "$key" == "a" || "$key" == "A" ]]; then
      target=1
      for index in "${!checked[@]}"; do ((checked[index])) || target=0; done
      target=$((1-target))
      for index in "${!checked[@]}"; do checked[index]=$target; done
    elif [[ -z "$key" ]]; then
      for position in "${!checked[@]}"; do
        ((checked[position])) && SELECTED_COMPONENTS+=("${available[position]}")
      done
      return 0
    fi
  done
}

component_workflow() {
  local mode=$1 index fn plan_title
  select_components "$mode" || { info "No components selected."; return; }
  ((${#SELECTED_COMPONENTS[@]})) || { info "No components selected."; return; }
  printf '\n'
  if [[ "$mode" == "Install" ]]; then plan_title="INSTALL PLAN"; else plan_title="REMOVE PLAN"; fi
  rule "$plan_title"
  for index in "${SELECTED_COMPONENTS[@]}"; do printf '  * %s\n' "${COMPONENT_NAMES[index]}"; done
  confirm "$mode these ${#SELECTED_COMPONENTS[@]} component(s)?" || return
  [[ "$mode" == "Install" ]] && package_refresh
  for index in "${SELECTED_COMPONENTS[@]}"; do
    rule "${COMPONENT_NAMES[index]}"
    if [[ "$mode" == "Install" ]]; then fn=${COMPONENT_INSTALL[index]}
    else fn=${COMPONENT_REMOVE[index]}
    fi
    "$fn"
  done
  ok "$mode workflow complete."
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

health_check() {
  clear 2>/dev/null || true
  show_brand
  local item cmd path cols max_path keep ready=0 total=9
  cols=$(tput cols 2>/dev/null || printf '100')
  max_path=$((cols - 38))
  ((max_path < 24)) && max_path=24
  for item in "Node.js:node" "npm:npm" "PM2:pm2" "MySQL:mysql" "Nginx:nginx" "Micro:micro" "Glances:glances" "Certbot:certbot" "Cloudflare:cloudflared"; do
    cmd=${item#*:}
    command -v "$cmd" >/dev/null 2>&1 && ready=$((ready + 1))
  done
  rule "STACK HEALTH"
  printf '%s  %d of %d components ready%s\n' "$CREAM" "$ready" "$total" "$RESET"
  printf '%s  %-10s %-19s %s%s\n' "$SELECTED" "STATE" "COMPONENT" "LOCATION" "$RESET"
  for item in "Node.js:node" "npm:npm" "PM2:pm2" "MySQL:mysql" "Nginx:nginx" "Micro:micro" "Glances:glances" "Certbot:certbot" "Cloudflare:cloudflared"; do
    cmd=${item#*:}
    if command -v "$cmd" >/dev/null 2>&1; then
      path=$(command -v "$cmd")
      if ((${#path} > max_path)); then
        keep=$((max_path - 3))
        path="...${path: -$keep}"
      fi
      printf '%s  %-10s %-19s %s%s\n' "$PAPER" "READY" "${item%%:*}" "$path" "$RESET"
    else
      printf '%s  %-10s %-19s %s%s\n' "$MUTED" "MISSING" "${item%%:*}" "not installed" "$RESET"
    fi
  done
  if command -v pm2 >/dev/null 2>&1; then
    printf '\n'
    rule "PM2 APPLICATIONS"
    pm2 jlist 2>/dev/null | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        try {
          const apps=JSON.parse(s);
          if (!apps.length) return console.log("  No PM2 applications are running.");
          console.log("  ID   NAME                   STATUS        CPU     MEMORY");
          for (const app of apps) {
            const m=((app.monit?.memory||0)/1048576).toFixed(1)+" MB";
            console.log(`  ${String(app.pm_id).padEnd(4)} ${app.name.slice(0,22).padEnd(22)} ${String(app.pm2_env.status).padEnd(10)} ${String(app.monit?.cpu||0).padStart(5)}% ${m.padStart(10)}`);
          }
        } catch (_) { console.log("  PM2 process details could not be read."); }
      });'
  fi
  if command -v nginx >/dev/null 2>&1; then
    if root_run nginx -t; then ok "Nginx configuration is valid."
    else warn "Nginx configuration validation failed."
    fi
  fi
}

MENU_IDS=(install remove complete startup domain ssl tunnel health creator exit)
MENU_LABELS=("Install components" "Remove components" "Install complete stack" "Configure PM2 startup" "Connect a domain" "Enable HTTPS" "Configure Cloudflare Tunnel" "Inspect stack health" "Creator and support" "Exit NEEM")
MENU_HINTS=("Choose one or several tools for this machine." "Select installed tools you no longer need." "Install Node.js, PM2, MySQL, Nginx and utilities." "Restore your Node.js apps after a restart." "Route a hostname through Nginx to a PM2 app." "Request and renew a free TLS certificate." "Publish a local app without opening inbound ports." "See what is installed and validate Nginx." "View Mohamed Aiman's links and ASCII portrait." "Return to your terminal.")
MAIN_ACTION=""

select_main_action() {
  local cursor=0 key rest index shortcut first_render=1
  MAIN_ACTION=""
  clear 2>/dev/null || true
  show_brand
  printf '%s  %s | %s%s%s\n\n' "$MUTED" "$OS" "$PKG" "$([[ $DRY_RUN -eq 1 ]] && echo ' | DRY RUN')" "$RESET"
  printf '  %s%sWhat would you like to do?%s\n' "$CREAM" "$BOLD" "$RESET"
  printf '%s  Up/Down move | Enter select | Esc exit | Number shortcuts work too%s\n\n' "$MUTED" "$RESET"
  while true; do
    if ((first_render)); then first_render=0
    else printf '\033[%dA' "$((${#MENU_LABELS[@]} + 1))"
    fi
    for index in "${!MENU_LABELS[@]}"; do
      if ((index == cursor)); then
        printf '\033[2K\r%s  > %-36s  %s\n' "$SELECTED" "${MENU_LABELS[index]}" "$RESET"
      elif [[ "${MENU_IDS[index]}" == "exit" ]]; then
        printf '\033[2K\r%s    %s%s\n' "$MUTED" "${MENU_LABELS[index]}" "$RESET"
      else
        printf '\033[2K\r%s    %s%s\n' "$CREAM" "${MENU_LABELS[index]}" "$RESET"
      fi
    done
    printf '\033[2K\r%s      %-68s%s\n' "$PAPER" "${MENU_HINTS[cursor]}" "$RESET"

    IFS= read -rsn1 key < /dev/tty || true
    if [[ "$key" == $'\e' ]]; then
      rest=""
      IFS= read -rsn2 -t 0.1 rest < /dev/tty || true
      case "$rest" in
        '[A') cursor=$(((cursor - 1 + ${#MENU_IDS[@]}) % ${#MENU_IDS[@]})) ;;
        '[B') cursor=$(((cursor + 1) % ${#MENU_IDS[@]})) ;;
        '') MAIN_ACTION=exit; return ;;
      esac
    elif [[ -z "$key" ]]; then
      MAIN_ACTION=${MENU_IDS[cursor]}
      return
    elif [[ "$key" == "0" ]]; then
      MAIN_ACTION=exit
      return
    elif [[ "$key" =~ ^[1-9]$ ]]; then
      shortcut=$((10#$key - 1))
      MAIN_ACTION=${MENU_IDS[shortcut]}
      return
    fi
  done
}

main_menu() {
  local action
  while true; do
    select_main_action
    action=$MAIN_ACTION
    case "$action" in
      install) component_workflow Install; pause ;;
      remove) component_workflow Remove; pause ;;
      complete) install_all; pause ;;
      startup) pm2_startup; pause ;;
      domain) configure_domain; pause ;;
      ssl) enable_ssl; pause ;;
      tunnel) cloudflare_tunnel_guide; pause ;;
      health) health_check; pause ;;
      creator) show_creator ;;
      exit) printf 'Goodbye.\n'; return ;;
    esac
  done
}

usage() {
  cat <<EOF
NEEM Stack Setup v$VERSION

Usage: ./neem.sh [--dry-run] [--health] [--update] [--help]

Without options, launches the interactive terminal menu.
  --dry-run  Print privileged/package commands without running them
  --health   Show installed components and validate Nginx
  --update   Download and install the latest version from GitHub

Interactive picker:
  Up/Down  Move between components
  Space    Tick or untick a component
  A        Tick or untick all
  Enter    Continue with the selection
  1-9      Main-menu shortcuts
EOF
}

main() {
  local action="menu"
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;; --health) action="health" ;; --update) action="update" ;;
      -h|--help) usage; exit 0 ;; *) die "Unknown option: $1" ;;
    esac
    shift
  done
  if [[ "$action" == "update" ]]; then update_neem; return; fi
  detect_platform
  if [[ "$action" == "health" ]]; then health_check; else main_menu; fi
}

main "$@"
