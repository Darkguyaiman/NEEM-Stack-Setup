# Package-manager integration and component install/remove operations.
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
