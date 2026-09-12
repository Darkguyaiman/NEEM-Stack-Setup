# Package-manager integration and component install/remove operations.
package_step() {
  local label=$1 log status
  shift
  if ((DRY_RUN)); then run "$@"; return; fi
  # Keep privilege prompts on the terminal before capturing routine output.
  if [[ ( "$1" == root_run || "$1" == configure_nginx_webroot ) && ${EUID:-$(id -u)} -ne 0 ]]; then
    sudo -v || return 1
  fi
  log=$(mktemp "${TMPDIR:-/tmp}/neem-step.XXXXXX") || return 1
  printf '    %s...\n' "$label"
  if "$@" > "$log" 2>&1; then
    if grep -Eqi 'Service restarts being deferred|reboot required|restart required' "$log"; then
      warn 'Some services or the system need a restart after these changes.'
    fi
    rm -f -- "$log"
  else
    status=$?
    warn "$label failed (exit $status)."
    tail -n 12 "$log" >&2
    warn "Full output: $log"
    return "$status"
  fi
}

package_refresh() {
  case "$PKG" in
    apt) package_step 'Refreshing packages' root_run apt-get update ;;
    dnf) package_step 'Refreshing packages' root_run dnf makecache ;;
    yum) package_step 'Refreshing packages' root_run yum makecache ;;
    pacman) package_step 'Refreshing packages' root_run pacman -Sy ;;
    zypper) package_step 'Refreshing packages' root_run zypper refresh ;;
    brew) package_step 'Refreshing packages' run brew update ;;
  esac
}

package_install() {
  case "$PKG" in
    apt) package_step 'Installing packages' root_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) package_step 'Installing packages' root_run dnf install -y "$@" ;;
    yum) package_step 'Installing packages' root_run yum install -y "$@" ;;
    pacman) package_step 'Installing packages' root_run pacman -S --needed --noconfirm "$@" ;;
    zypper) package_step 'Installing packages' root_run zypper --non-interactive install "$@" ;;
    brew) package_step 'Installing packages' run brew install "$@" ;;
  esac
}

package_remove() {
  case "$PKG" in
    apt) package_step 'Removing packages' root_run apt-get remove -y "$@" ;;
    dnf) package_step 'Removing packages' root_run dnf remove -y "$@" ;;
    yum) package_step 'Removing packages' root_run yum remove -y "$@" ;;
    pacman) package_step 'Removing packages' root_run pacman -R --noconfirm "$@" ;;
    zypper) package_step 'Removing packages' root_run zypper --non-interactive remove "$@" ;;
    brew) package_step 'Removing packages' run brew uninstall "$@" ;;
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

# Resolve upstream policy first, then require that exact upstream version in
# the configured package repository. Distribution revision suffixes are kept.
ensure_release_tools() {
  local tool
  local -a missing=()
  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if ((${#missing[@]})); then
    info "Installing release-check tools: ${missing[*]}" >&2
    package_install "${missing[@]}" >&2 || return 1
    hash -r
    for tool in "${missing[@]}"; do
      command -v "$tool" >/dev/null 2>&1 || { warn "$tool is unavailable after installation."; return 1; }
    done
  fi
}

parse_production_metadata() {
  local component=$1
  case "$component" in
    node)
      jq -er '[.[] | select((.lts | type) == "string") | select(.lts != "") |
        .version | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | ltrimstr("v")]
        | sort_by(split(".") | map(tonumber)) | last // error("No LTS release found")'
      ;;
    mysql)
      jq -erRs '[match("<option\\b[^>]*>\\s*([0-9]+\\.[0-9]+\\.[0-9]+)\\s+LTS\\s*</option>"; "g") | .captures[0].string]
        | sort_by(split(".") | map(tonumber)) | last // error("No MySQL LTS release found")'
      ;;
    nginx)
      jq -erRs '[capture("Stable version</h4>(?<section>.*?)<h4>"; "s").section |
        match("nginx-([0-9]+\\.[0-9]+\\.[0-9]+)\\.tar\\.gz"; "g") | .captures[0].string]
        | sort_by(split(".") | map(tonumber)) | last // error("No Nginx stable release found")'
      ;;
    *) warn "Unknown component: $component"; return 1 ;;
  esac
}

production_version() {
  local component=$1 url content
  case "$component" in
    node) url=https://nodejs.org/dist/index.json ;;
    mysql) url=https://dev.mysql.com/downloads/mysql/ ;;
    nginx) url=https://nginx.org/en/download.html ;;
    *) warn "Unknown component: $component"; return 1 ;;
  esac
  ensure_release_tools || return 1
  content=$(curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 30 "$url") || return 1
  printf '%s' "$content" | parse_production_metadata "$component"
}

apt_repository_spec() {
  local component=$1 version=$2 distro=$3 codename=$4 architecture=$5
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$codename" =~ ^[a-z][a-z0-9]*$ && "$architecture" =~ ^[a-z0-9]+$ ]] || return 1
  [[ "$distro" == ubuntu || "$distro" == debian ]] || return 1
  case "$component" in
    node)
      APT_VENDOR_URL="https://deb.nodesource.com/node_${version%%.*}.x"
      APT_VENDOR_SUITE=nodistro
      APT_VENDOR_COMPONENT=main
      APT_VENDOR_KEY=https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
      ;;
    mysql)
      APT_VENDOR_URL="https://repo.mysql.com/apt/$distro"
      APT_VENDOR_SUITE=$codename
      APT_VENDOR_COMPONENT="mysql-${version%.*}-lts"
      APT_VENDOR_KEY=https://repo.mysql.com/RPM-GPG-KEY-mysql-2025
      ;;
    nginx)
      APT_VENDOR_URL="https://nginx.org/packages/$distro"
      APT_VENDOR_SUITE=$codename
      APT_VENDOR_COMPONENT=nginx
      APT_VENDOR_KEY=https://nginx.org/keys/nginx_signing.key
      ;;
    *) return 1 ;;
  esac
  APT_VENDOR_LINE="deb [arch=$architecture signed-by=/etc/apt/keyrings/neem-$component.asc] $APT_VENDOR_URL $APT_VENDOR_SUITE $APT_VENDOR_COMPONENT"
}

apt_platform() (
  local ID='' VERSION_CODENAME=''
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  printf '%s %s\n' "$ID" "$VERSION_CODENAME"
)

configure_apt_production_repository() (
  # Subshell keeps os-release variables and cleanup traps local to this operation.
  local component=$1 version=$2 architecture stage key_path source_path platform distro codename
  platform=$(apt_platform) || { warn 'Cannot identify the APT distribution.'; return 1; }
  read -r distro codename <<< "$platform"
  architecture=$(dpkg --print-architecture) || return 1
  apt_repository_spec "$component" "$version" "$distro" "$codename" "$architecture" || {
    warn "Automatic vendor repositories require Debian or Ubuntu with a release codename."; return 1;
  }
  info "Configuring $component production repository: $APT_VENDOR_URL ($APT_VENDOR_COMPONENT)."
  package_install ca-certificates curl || return 1
  stage=$(mktemp -d) || return 1
  trap 'rm -rf -- "$stage"' EXIT
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 30 \
    "$APT_VENDOR_URL/dists/$APT_VENDOR_SUITE/InRelease" -o "$stage/InRelease" || return 1
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --max-time 30 \
    "$APT_VENDOR_KEY" -o "$stage/key.asc" || return 1
  grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$stage/key.asc" || { warn 'Invalid repository signing key.'; return 1; }
  printf '%s\n' "$APT_VENDOR_LINE" > "$stage/vendor.list"
  key_path="/etc/apt/keyrings/neem-$component.asc"
  source_path="/etc/apt/sources.list.d/neem-$component.list"
  root_run install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d || return 1
  # Only NEEM-owned files are replaced. Keep copies for a failed refresh.
  [[ ! -f "$key_path" ]] || cp "$key_path" "$stage/previous-key"
  [[ ! -f "$source_path" ]] || cp "$source_path" "$stage/previous-source"
  root_run install -m 0644 "$stage/key.asc" "$key_path" || return 1
  root_run install -m 0644 "$stage/vendor.list" "$source_path" || return 1
  if ! package_step 'Refreshing vendor packages' root_run apt-get update -o APT::Update::Error-Mode=any; then
    if [[ -f "$stage/previous-source" ]]; then root_run install -m 0644 "$stage/previous-source" "$source_path"
    else root_run rm -f -- "$source_path"; fi
    if [[ -f "$stage/previous-key" ]]; then root_run install -m 0644 "$stage/previous-key" "$key_path"
    else root_run rm -f -- "$key_path"; fi
    warn 'Repository refresh failed; the previous NEEM repository configuration was restored.'
    return 1
  fi
)

matching_package_version() {
  local version=$1 entry upstream
  while IFS= read -r entry; do
    upstream=${entry##*:}
    if [[ "$upstream" == "$version" || "$upstream" == "$version-"* || "$upstream" == "$version+"* ]]; then
      printf '%s\n' "$entry"
      return 0
    fi
  done
  return 1
}

install_production_package() {
  local component=$1 package=$2 version candidate listing upstream formula
  if ((DRY_RUN)); then
    info "Would verify and install the latest $component LTS/stable patch, configuring its signed vendor repository on Debian/Ubuntu if needed."
    return
  fi
  version=$(production_version "$component") || die "Could not verify $component release; installation stopped."
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid release metadata."
  PRODUCTION_VERSION=$version
  info "Selected $component $version (latest LTS/stable patch)."
  if [[ "$PKG" == brew ]]; then
    formula=$package
    [[ "$component" == node ]] && formula="node@${version%%.*}"
    [[ "$component" == mysql ]] && formula="mysql@${version%.*}"
    listing=$(brew info --json=v2 "$formula") || die "Homebrew has no $formula formula."
    candidate=$(printf '%s' "$listing" | jq -er '.formulae[0].versions.stable') || die "Cannot read Homebrew version."
    [[ "$candidate" == "$version" ]] || die "Homebrew offers $candidate; policy requires $version. Update Homebrew and retry."
    package_install "$formula"
    PRODUCTION_FORMULA=$formula
    if [[ "$component" == node || "$component" == mysql ]]; then
      # Versioned formulas are keg-only. Expose them for subsequent PM2 steps.
      export PATH="$(brew --prefix "$formula")/bin:$PATH"
      info "Add $(brew --prefix "$formula")/bin to your shell PATH for future terminals."
    fi
    return
  fi
  case "$PKG" in
    apt) listing=$(apt-cache madison "$package" | awk '{print $3}') ;;
    dnf) listing=$(dnf -q repoquery --available --qf '%{version}-%{release}' "$package") ;;
    yum) listing=$(yum --showduplicates list available "$package" | awk 'NF >= 3 {print $2}') ;;
    pacman) listing=$(pacman -Si "$package" | awk '/^Version[[:space:]]*:/ {print $3}') ;;
    zypper) listing=$(LC_ALL=C zypper --non-interactive info "$package" | awk '/^Version[[:space:]]*:/ {print $3}') ;;
    *) die "Unsupported package manager for verified releases: $PKG" ;;
  esac
  if [[ "$PKG" == apt ]] && ! matching_package_version "$version" <<< "$listing" >/dev/null; then
    configure_apt_production_repository "$component" "$version" || die "Could not configure the signed $component repository. Installation stopped."
    listing=$(apt-cache madison "$package" | awk '{print $3}')
  fi
  candidate=''
  while IFS= read -r upstream; do
    upstream=${upstream##*:}
    if [[ "$upstream" == "$version" || "$upstream" == "$version-"* || "$upstream" == "$version+"* ]]; then
      candidate=$upstream
      break
    fi
  done <<< "$listing"
  [[ -n "$candidate" ]] || die "Repository does not provide $package $version. Configure the vendor LTS/stable repository and retry; no older or alternate database will be installed."
  case "$PKG" in
    apt)
      # Retain epochs from apt metadata in the exact package specification.
      while IFS= read -r upstream; do
        [[ "${upstream##*:}" == "$candidate" ]] && { candidate=$upstream; break; }
      done <<< "$listing"
      package_install "$package=$candidate"
      if [[ "$component" == node ]] && ! command -v npm >/dev/null 2>&1; then
        package_install "$package=$candidate" npm
      fi
      ;;
    dnf|yum)
      package_install "$package-$candidate"
      if [[ "$component" == node ]] && ! command -v npm >/dev/null 2>&1; then package_install "$package-$candidate" npm; fi
      ;;
    pacman)
      if [[ "$component" == node ]]; then package_install "$package" npm
      else package_install "$package"; fi
      ;;
    zypper)
      if [[ "$component" == node ]]; then package_install "$package=$candidate" npm
      else package_install "$package=$candidate"; fi
      ;;
  esac
}

install_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    warn "Existing Node.js $(node --version) retained; installation does not check or apply security updates."
    return
  fi
  info "Installing Node.js and npm..."
  install_production_package node nodejs
  if ((!DRY_RUN)); then
    [[ "$(node --version)" == "v$PRODUCTION_VERSION" ]] || die "Installed Node version differs from the selected LTS. Check PATH and package dependencies."
    command -v npm >/dev/null 2>&1 || die "Node was installed but npm is missing. Install the matching npm package."
  fi
  ok "Node.js installation finished."
}

install_pm2() {
  install_node
  if command -v pm2 >/dev/null 2>&1; then
    ok "PM2 is already installed."
  else
    info "Installing the latest PM2 globally with npm..."
    if [[ "$OS" == "macos" ]]; then package_step 'Installing PM2' run npm install --global pm2@latest
    else package_step 'Installing PM2' root_run npm install --global pm2@latest
    fi
  fi
  ok "PM2 installation finished."
}

mysql_server_installed() {
  local binary location
  for binary in mysqld mariadbd; do
    location=$(command -v "$binary" || true)
    [[ -n "$location" && -x "$location" ]] && return 0
  done
  return 1
}

install_mysql() {
  if mysql_server_installed; then
    warn "Existing database retained; security patches and database upgrades require separate maintenance."
    return
  fi
  info "Installing MySQL..."
  case "$PKG" in
    brew)
      install_production_package mysql mysql
      if ((!DRY_RUN)); then enable_service "$PRODUCTION_FORMULA"; fi
      ;;
    apt) install_production_package mysql mysql-community-server; enable_service mysql ;;
    dnf|yum) install_production_package mysql mysql-community-server; enable_service mysqld ;;
    pacman) die "Arch's MariaDB package does not meet the MySQL LTS policy. Install Oracle MySQL LTS separately." ;;
    zypper) install_production_package mysql mysql-community-server; enable_service mysql ;;
  esac
  ok "Database server installed. Run 'mysql_secure_installation' to harden it."
}

install_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    warn "Existing Nginx retained; installation does not check or apply security updates."
    if [[ "$OS" != macos ]]; then package_step 'Preparing /var/www/html' configure_nginx_webroot || return 1; fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
      package_step 'Reloading Nginx' root_run nginx -s reload || return 1
    fi
    return
  fi
  info "Installing Nginx..."
  install_production_package nginx nginx
  if [[ "$OS" != macos ]]; then package_step 'Preparing /var/www/html' configure_nginx_webroot || return 1; fi
  enable_service nginx
  if [[ "$OS" != macos ]]; then package_step 'Reloading Nginx' root_run nginx -s reload; fi
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
    apt) package_install pipx; package_step 'Configuring Glances' run pipx ensurepath; package_step 'Installing Glances' run pipx install glances ;;
    dnf|yum) package_install python3-pip; package_step 'Installing Glances' run python3 -m pip install --user --upgrade glances ;;
    pacman) package_install glances ;;
    zypper) package_install python3-pip; package_step 'Installing Glances' run python3 -m pip install --user --upgrade glances ;;
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
    warn "The stack is already installed. Existing versions were not audited or updated; apply security updates separately."
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

installed_brew_formula() {
  local component=$1 formula
  local -a matches=()
  while IFS= read -r formula; do
    [[ "$formula" == "$component" || "$formula" == "$component@"* ]] && matches+=("$formula")
  done < <(brew list --formula)
  ((${#matches[@]} == 1)) || die "Cannot choose one installed $component formula. Remove the intended formula using brew uninstall."
  printf '%s\n' "${matches[0]}"
}

remove_node() {
  warn "Removing Node.js may also make global npm tools such as PM2 unavailable."
  case "$PKG" in
    brew) local formula; formula=$(installed_brew_formula node) || return; package_remove "$formula" ;;
    *) package_remove nodejs npm ;;
  esac
  hash -r
}

remove_pm2() {
  local restore_node=0 node_path npm_path
  hash -r
  node_path=$(command -v node || true)
  npm_path=$(command -v npm || true)
  if [[ ! -x "$node_path" || ! -x "$npm_path" ]]; then
    [[ -x "$node_path" ]] || restore_node=1
    info 'Restoring Node.js/npm so PM2 can be uninstalled through its package manager.'
    install_node
    hash -r
  fi
  if [[ "$OS" == "macos" ]]; then package_step 'Removing PM2' run npm uninstall --global pm2
  else package_step 'Removing PM2' root_run npm uninstall --global pm2
  fi
  if ((restore_node)); then remove_node; fi
}

remove_mysql() {
  warn "The database package will be removed; database files and configuration are intentionally retained."
  case "$PKG" in
    brew) local formula; formula=$(installed_brew_formula mysql) || return; run brew services stop "$formula" || true; package_remove "$formula" ;;
    apt)
      local installed package state
      local -a server_packages=()
      installed=$(dpkg-query -W -f='${binary:Package}\t${Status}\n') || return 1
      while IFS=$'\t' read -r package state; do
        package=${package%%:*}
        [[ "$state" == 'install ok installed' ]] || continue
        if [[ "$package" =~ ^(default-mysql-server(-core)?|mysql-(community-server(-core)?|server(-core)?(-[0-9.]+)?)|mariadb-server(-core)?(-[0-9.]+)?)$ ]]; then
          server_packages+=("$package")
        fi
      done <<< "$installed"
      if ((${#server_packages[@]})); then
        package_remove "${server_packages[@]}" || return 1
      elif mysql_server_installed; then
        die 'A database server binary remains outside the recognized APT packages. Removal was not completed.'
      fi
      ;;
    dnf|yum)
      if rpm -q mysql-community-server >/dev/null 2>&1; then package_remove mysql-community-server
      else package_remove mysql-server; fi
      ;;
    pacman) package_remove mariadb ;;
    zypper) package_remove mysql-community-server ;;
  esac
  hash -r
  if ((!DRY_RUN)) && mysql_server_installed; then
    die 'A database server binary is still installed. Removal was not completed; database files were retained.'
  fi
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
    apt) command -v pipx >/dev/null 2>&1 && package_step 'Removing Glances' run pipx uninstall glances || package_remove glances ;;
    dnf|yum|zypper) package_step 'Removing Glances' run python3 -m pip uninstall --yes glances ;;
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
    2) mysql_server_installed ;;
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
  local mode=$1 index fn plan_title position=0
  select_components "$mode" || { info "No components selected."; return; }
  ((${#SELECTED_COMPONENTS[@]})) || { info "No components selected."; return; }
  if [[ "$mode" == Remove ]]; then
    # Keep runtime removal last, both in the preview and execution.
    local -a removal_order=()
    for index in "${SELECTED_COMPONENTS[@]}"; do
      [[ "${COMPONENT_REMOVE[index]}" == remove_node ]] || removal_order+=("$index")
    done
    for index in "${SELECTED_COMPONENTS[@]}"; do
      [[ "${COMPONENT_REMOVE[index]}" != remove_node ]] || removal_order+=("$index")
    done
    SELECTED_COMPONENTS=("${removal_order[@]}")
  fi
  printf '\n'
  if [[ "$mode" == "Install" ]]; then plan_title="INSTALL PLAN"; else plan_title="REMOVE PLAN"; fi
  rule "$plan_title"
  for index in "${SELECTED_COMPONENTS[@]}"; do printf '  * %s\n' "${COMPONENT_NAMES[index]}"; done
  confirm "$mode these ${#SELECTED_COMPONENTS[@]} component(s)?" || return
  [[ "$mode" == "Install" ]] && package_refresh
  for index in "${SELECTED_COMPONENTS[@]}"; do
    position=$((position + 1))
    rule "$position/${#SELECTED_COMPONENTS[@]}  ${COMPONENT_NAMES[index]}"
    if [[ "$mode" == "Install" ]]; then fn=${COMPONENT_INSTALL[index]}
    else fn=${COMPONENT_REMOVE[index]}
    fi
    "$fn"
    ok "${COMPONENT_NAMES[index]} complete."
  done
  ok "$mode workflow complete."
}
