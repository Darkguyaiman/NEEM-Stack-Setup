#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$TEST_DIR/.." && pwd)"
TEST_COUNT=0

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf '+ %s\n' "$1"
}

fail() {
  printf 'Assertion failed: %s\n' "$1" >&2
  exit 1
}

assert_true() {
  local message=$1
  shift
  "$@" || fail "$message"
  pass "$message"
}

assert_false() {
  local message=$1
  shift
  if "$@"; then fail "$message"; fi
  pass "$message"
}

assert_equal() {
  local expected=$1 actual=$2 message=$3
  [[ "$expected" == "$actual" ]] || fail "$message (expected '$expected', got '$actual')"
  pass "$message"
}

assert_contains() {
  local value=$1 expected=$2 message=$3
  [[ "$value" == *"$expected"* ]] || fail "$message"
  pass "$message"
}

printf 'Bash suite\n'

mapfile -t shell_files < <(find "$PROJECT_ROOT/linux" -type f -name '*.sh' | sort)
assert_equal 7 "${#shell_files[@]}" 'one entry point and six focused Bash modules are present'
bash -n "$PROJECT_ROOT/neem.sh" "${shell_files[@]}"
pass 'all Bash entry points and modules parse successfully'

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$PROJECT_ROOT/neem.sh" "${shell_files[@]}"
  pass 'ShellCheck reports no issues'
else
  printf 'i ShellCheck is not installed; optional lint check skipped.\n'
fi

# The platform entry point deliberately avoids running main when sourced.
# shellcheck source=../linux/neem.sh
source "$PROJECT_ROOT/linux/neem.sh"
pass 'platform entry point can be sourced safely for unit tests'

for function_name in info run root_run detect_platform update_neem package_install \
  component_workflow valid_domain valid_port write_nginx_config health_check \
  normalize_backup_directory mysql_backup mysql_create_user select_main_action usage main; do
  declare -F "$function_name" >/dev/null || fail "function $function_name is loaded"
  pass "function $function_name is loaded"
done

assert_true 'domain validator accepts a normal hostname' valid_domain 'example.com'
assert_true 'domain validator accepts subdomains' valid_domain 'api.dev.example.co.uk'
assert_false 'domain validator rejects URLs' valid_domain 'https://example.com'
assert_false 'domain validator rejects underscores' valid_domain 'bad_name.example'
assert_true 'port validator accepts the minimum port' valid_port '1'
assert_true 'port validator accepts the maximum port' valid_port '65535'
assert_false 'port validator rejects port zero' valid_port '0'
assert_false 'port validator rejects ports above 65535' valid_port '65536'
assert_false 'port validator rejects non-numeric input' valid_port 'abc'
assert_false 'tunnel validator rejects malformed tokens' valid_cloudflare_tunnel_token 'not-a-token'

assert_equal '/tmp/NEEM Backups' "$(normalize_backup_directory '/tmp/NEEM Backups')" 'absolute backup paths remain absolute'
assert_equal "$HOME/NEEM Backups" "$(normalize_backup_directory '~/NEEM Backups')" 'backup paths expand tilde'
assert_equal "$PWD/relative backups" "$(normalize_backup_directory 'relative backups')" 'relative backup paths become absolute'
assert_equal '/tmp/Quoted Backups' "$(normalize_backup_directory '"/tmp/Quoted Backups"')" 'backup paths remove pasted quotes'

if command -v wslpath >/dev/null 2>&1 || command -v cygpath >/dev/null 2>&1; then
  windows_path=$(normalize_backup_directory 'C:\NEEM Backups')
  [[ "$windows_path" == /c/* || "$windows_path" == /mnt/c/* ]] || fail 'Windows drive path was not translated'
  pass 'Windows drive backup paths are translated under WSL or Git Bash'
else
  if normalize_backup_directory 'C:\NEEM Backups' >/dev/null 2>&1; then
    fail 'native Unix should reject unmappable Windows drive paths'
  fi
  pass 'native Unix clearly rejects unmappable Windows drive paths'
fi

assert_equal "${#COMPONENT_NAMES[@]}" "${#COMPONENT_INSTALL[@]}" 'component names and installers stay aligned'
assert_equal "${#COMPONENT_NAMES[@]}" "${#COMPONENT_REMOVE[@]}" 'component names and removers stay aligned'
assert_equal "${#MENU_IDS[@]}" "${#MENU_LABELS[@]}" 'menu identifiers and labels stay aligned'
assert_equal "${#MENU_IDS[@]}" "${#MENU_HINTS[@]}" 'menu identifiers and hints stay aligned'

root_help=$(bash "$PROJECT_ROOT/neem.sh" --help)
assert_contains "$root_help" "NEEM Stack Setup v$VERSION" 'root Bash launcher reads the shared version'
assert_contains "$root_help" '--backup' 'root Bash launcher preserves command arguments'
platform_help=$(bash "$PROJECT_ROOT/linux/neem.sh" --help)
assert_contains "$platform_help" "NEEM Stack Setup v$VERSION" 'platform Bash launcher reads the shared version'
assert_contains "$platform_help" '--create-global-db-user' 'platform help exposes database-user commands'

if invalid_output=$(bash "$PROJECT_ROOT/neem.sh" --not-a-real-option 2>&1); then
  fail 'Bash accepts an unknown command-line option'
fi
assert_contains "$invalid_output" 'Unknown option: --not-a-real-option' 'Bash rejects and identifies unknown options'

if grep -R $'\r' "$PROJECT_ROOT/neem.sh" "$PROJECT_ROOT/linux"/*.sh "$PROJECT_ROOT/linux/modules"/*.sh >/dev/null; then
  fail 'Bash files contain CRLF line endings'
fi
pass 'Bash scripts use Unix LF line endings'

if grep -R -E 'â[„œ–—]' "$PROJECT_ROOT/neem.sh" "$PROJECT_ROOT/linux" >/dev/null; then
  fail 'Bash files contain mojibake'
fi
pass 'Bash scripts retain valid UTF-8 symbols'

(
  DRY_RUN=0
  noisy_success() { printf 'unnecessary package details\n'; }
  result=$(package_step 'Installing example' noisy_success)
  assert_contains "$result" 'Installing example...' 'quiet commands show readable progress'
  [[ "$result" != *'unnecessary package details'* ]] || fail 'successful command output leaked'
  noisy_failure() { printf 'meaningful failure detail\n'; return 7; }
  if result=$(package_step 'Installing example' noisy_failure 2>&1); then fail 'failed quiet command reported success';
  else status=$?; fi
  assert_equal 7 "$status" 'quiet command preserves its failure exit status'
  assert_contains "$result" 'meaningful failure detail' 'failed quiet commands show diagnostic output'
  failure_log=${result##*Full output: }
  [[ -f "$failure_log" ]] || fail 'failure log was not preserved'
  rm -f -- "$failure_log"
)
pass 'quiet progress hides routine output and preserves failures'

# Parser tests use jq, the same small JSON tool bootstrapped by the installer.
command -v jq >/dev/null 2>&1 || fail 'jq is required to run release-parser tests'
node_metadata='[{"version":"v26.1.0","lts":false},{"version":"v24.9.0","lts":"Example"},{"version":"v24.10.0","lts":"Example"}]'
assert_equal '24.10.0' "$(printf '%s' "$node_metadata" | parse_production_metadata node)" 'Node parser excludes current and sorts numerically'
mysql_metadata='<option value="26.7">26.7.0</option><option value="9.7">9.7.2 LTS</option><option value="8.4">8.4.11 LTS</option>'
assert_equal '9.7.2' "$(printf '%s' "$mysql_metadata" | parse_production_metadata mysql)" 'MySQL parser requires an LTS label'
nginx_metadata='<h4>Mainline version</h4>nginx-1.31.5.tar.gz<h4>Stable version</h4>nginx-1.30.4.tar.gz<h4>Legacy versions</h4>nginx-1.28.3.tar.gz'
assert_equal '1.30.4' "$(printf '%s' "$nginx_metadata" | parse_production_metadata nginx)" 'Nginx parser excludes mainline and legacy'
for component in node mysql nginx; do
  if printf '[]' | parse_production_metadata "$component" >/dev/null 2>&1; then fail "$component accepted missing metadata"; fi
done
pass 'missing metadata is rejected without fallback'
(
  # Simulate missing dependencies and make them available after one install.
  ready=0
  command() {
    if [[ "$1" == -v && ( "$2" == curl || "$2" == jq ) ]]; then ((ready)); else builtin command "$@"; fi
  }
  package_install() {
    [[ "$*" == 'curl jq' ]] || fail 'unexpected bootstrap packages'
    ready=1
  }
  ensure_release_tools || fail 'dependency bootstrap failed'
  ((ready)) || fail 'dependency installation did not run'
  package_install() { fail 'available dependencies should not be reinstalled'; }
  ensure_release_tools
)
pass 'missing release tools install automatically and are reused in the same run'

# Package calls are mocked: these tests never install software.
apt_repository_spec node 24.21.0 ubuntu noble amd64 || fail 'Node repository plan failed'
assert_contains "$APT_VENDOR_LINE" 'https://deb.nodesource.com/node_24.x nodistro main' 'Ubuntu Node uses the selected LTS major at NodeSource'
assert_contains "$APT_VENDOR_LINE" 'signed-by=/etc/apt/keyrings/neem-node.asc' 'repository trust is scoped to its signing key'
apt_repository_spec mysql 9.7.2 ubuntu noble amd64 || fail 'MySQL repository plan failed'
assert_contains "$APT_VENDOR_LINE" 'https://repo.mysql.com/apt/ubuntu noble mysql-9.7-lts' 'Ubuntu MySQL uses the selected LTS channel'
apt_repository_spec nginx 1.30.4 debian bookworm arm64 || fail 'Nginx repository plan failed'
assert_contains "$APT_VENDOR_LINE" 'https://nginx.org/packages/debian bookworm nginx' 'Debian Nginx uses the stable repository'
assert_false 'unknown distributions do not receive guessed repositories' apt_repository_spec node 24.21.0 unknown noble amd64
assert_false 'invalid release metadata cannot enter repository configuration' apt_repository_spec node '24;bad' ubuntu noble amd64
(
  repository_log=$(mktemp)
  sudo() { return 0; }
  trap 'rm -f -- "$repository_log"' EXIT
  apt_platform() { printf 'ubuntu noble\n'; }
  dpkg() { printf 'amd64\n'; }
  package_install() { printf 'prerequisites:%s\n' "$*" >> "$repository_log"; }
  curl() {
    local output=''
    while (($#)); do
      if [[ "$1" == -o ]]; then output=$2; break; fi
      shift
    done
    printf '%s\n' '-----BEGIN PGP PUBLIC KEY BLOCK-----' > "$output"
  }
  root_run() {
    printf '%s\n' "$*" >> "$repository_log"
    return 0
  }
  configure_apt_production_repository node 24.21.0 >/dev/null || fail 'repository setup failed'
  result=$(cat "$repository_log")
  assert_contains "$result" '/etc/apt/keyrings/neem-node.asc' 'repository setup installs its scoped key'
  assert_contains "$result" 'apt-get update -o APT::Update::Error-Mode=any' 'repository setup requires a successful signed APT refresh'
  root_run() {
    printf '%s\n' "$*" >> "$repository_log"
    [[ "$1" != apt-get ]]
  }
  if configure_apt_production_repository node 24.21.0 >/dev/null 2>&1; then fail 'failed refresh reported success'; fi
  result=$(cat "$repository_log")
  assert_contains "$result" 'rm -f -- /etc/apt/sources.list.d/neem-node.list' 'failed refresh removes the newly added source'
)
pass 'repository setup and refresh failure handling run without changing system files in tests'
(
  DRY_RUN=0
  PKG=apt
  production_version() { printf '24.10.0\n'; }
  apt-cache() { printf 'nodejs | 1:24.10.0-1vendor1 | repository\n'; }
  package_install() { printf 'INSTALL:%s\n' "$*"; }
  result=$(install_production_package node nodejs)
  assert_contains "$result" 'INSTALL:nodejs=1:24.10.0-1vendor1' 'APT preserves epoch and pins the verified upstream patch'
  apt-cache() { printf 'nodejs | 26.1.0-1 | repository\n'; }
  configure_apt_production_repository() { printf 'REPOSITORY:%s\n' "$*"; }
  if result=$(install_production_package node nodejs 2>&1); then
    fail 'wrong-channel repository package should be rejected'
  fi
  [[ "$result" != *INSTALL:* ]] || fail 'rejected package attempted installation'
  assert_contains "$result" 'REPOSITORY:node 24.10.0' 'missing APT version triggers automatic repository setup'
  configure_apt_production_repository() {
    [[ "$*" == 'node 24.10.0' ]] || fail 'wrong repository selection'
    apt-cache() { printf 'nodejs | 24.10.0-1nodesource1 | repository\n'; }
  }
  result=$(install_production_package node nodejs)
  assert_contains "$result" 'INSTALL:nodejs=24.10.0-1nodesource1' 'installer retries and installs the exact patch after repository setup'
  DRY_RUN=1
  production_version() { fail 'dry run must not fetch release metadata'; }
  configure_apt_production_repository() { fail 'dry run must not modify repositories'; }
  install_production_package node nodejs >/dev/null
)
pass 'production installer pins matching packages, rejects mismatches, and previews offline'

(
  select_components() { SELECTED_COMPONENTS=(0 1 3); }
  confirm() { return 0; }
  remove_pm2() { printf 'REMOVE:pm2\n'; }
  remove_node() { printf 'REMOVE:node\n'; }
  remove_nginx() { printf 'REMOVE:nginx\n'; }
  result=$(component_workflow Remove)
  calls=$(printf '%s\n' "$result" | grep '^REMOVE:')
  assert_equal $'REMOVE:pm2\nREMOVE:nginx\nREMOVE:node' "$calls" 'batch removal uninstalls PM2 before Node'
)
pass 'runtime removal is ordered after dependent components'
(
  runtime_ready=0
  sudo() { return 0; }
  calls=''
  OS=linux
  command() {
    if [[ "$1" == -v && ( "$2" == node || "$2" == npm ) ]]; then
      ((runtime_ready)) || return 1
      printf '/bin/bash\n'
    else builtin command "$@"; fi
  }
  install_node() { calls+='restore '; runtime_ready=1; }
  root_run() { calls+="$* "; }
  remove_node() { calls+='remove-node'; }
  remove_pm2
  assert_equal 'restore npm uninstall --global pm2 remove-node' "$calls" 'orphaned PM2 restores its runtime for uninstall then removes the temporary runtime'
)
pass 'PM2 removal recovers when Node was already removed'

(
  # Real disposable Git repositories exercise backups and update behavior.
  fixture=$(mktemp -d)
  trap 'rm -rf -- "$fixture"' EXIT
  git init -q -b main "$fixture/upstream"
  printf '1.0.0\n' > "$fixture/upstream/VERSION"
  printf '#!/bin/sh\nexit 0\n' > "$fixture/upstream/install-neem-command.sh"
  git -C "$fixture/upstream" add .
  git -C "$fixture/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
  git clone -q "$fixture/upstream" "$fixture/client"
  SCRIPT_DIR="$fixture/client"
  DRY_RUN=0
  VERSION=1.0.0
  printf '2.0.0\n' > "$fixture/upstream/VERSION"
  git -C "$fixture/upstream" -c user.name=Test -c user.email=test@example.invalid commit -qam update
  printf 'local-edit\n' > "$SCRIPT_DIR/VERSION"
  printf 'personal-notes\n' > "$SCRIPT_DIR/notes.txt"
  update_neem >/dev/null
  assert_equal '2.0.0' "$(cat "$SCRIPT_DIR/VERSION")" 'dirty checkout updates automatically'
  assert_equal 'local-edit' "$(git -C "$SCRIPT_DIR" show 'stash@{0}:VERSION')" 'tracked edits remain in the automatic stash'
  assert_equal 'personal-notes' "$(git -C "$SCRIPT_DIR" show 'stash@{0}^3:notes.txt')" 'untracked files remain in the automatic stash'
  result=$(update_neem)
  assert_contains "$result" 'NEEM v2.0.0 is up to date.' 'current checkout shows a concise version result'
  [[ "$result" != *'git -C'* && "$result" != *'install-neem-command.sh'* && "$result" != *'Run neem'* ]] || fail 'already-current update showed unnecessary setup instructions'
  printf 'local-commit\n' > "$SCRIPT_DIR/VERSION"
  git -C "$SCRIPT_DIR" -c user.name=Test -c user.email=test@example.invalid commit -qam local
  local_commit=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
  update_neem >/dev/null
  assert_equal '2.0.0' "$(cat "$SCRIPT_DIR/VERSION")" 'local commits do not block updating to upstream'
  backup_commit=$(git -C "$SCRIPT_DIR" for-each-ref --format='%(objectname)' 'refs/heads/neem-backup-*')
  assert_equal "$local_commit" "$backup_commit" 'local commits are preserved on a backup branch'
  printf 'keep-on-failure\n' > "$SCRIPT_DIR/VERSION"
  git -C "$SCRIPT_DIR" remote set-url origin "$fixture/missing"
  if update_neem >/dev/null 2>&1; then fail 'failed fetch reported success'; fi
  assert_equal 'keep-on-failure' "$(cat "$SCRIPT_DIR/VERSION")" 'fetch failure leaves edits untouched'
  DRY_RUN=1
  update_neem >/dev/null
  assert_equal 'keep-on-failure' "$(cat "$SCRIPT_DIR/VERSION")" 'update dry run leaves edits untouched'
)
pass 'automatic update backups and failure handling pass with real Git repositories'

(
  PKG=apt
  DRY_RUN=0
  remaining=1
  removed=''
  dpkg-query() {
    printf 'mysql-community-server-core\tinstall ok installed\n'
    printf 'mysql-community-server\tdeinstall ok config-files\n'
    printf 'mysql-community-client\tinstall ok installed\n'
    printf 'unrelated-app\tinstall ok installed\n'
  }
  mysql_server_installed() { ((remaining)); }
  package_remove() { removed="$*"; remaining=0; }
  remove_mysql
  assert_equal 'mysql-community-server-core' "$removed" 'MySQL removal handles an orphaned core package without removing clients or unrelated packages'
  assert_false 'MySQL disappears from the picker after core removal' component_installed 2
  remaining=1
  package_remove() { return 0; }
  if (remove_mysql) >/dev/null 2>&1; then fail 'leftover server binary reported successful removal'; fi
)
pass 'MySQL core leftovers are removed and remaining binaries prevent false success'
(
  command() { printf '/nonexistent/neem-test-mysqld\n'; }
  assert_false 'stale command locations do not mark MySQL installed' mysql_server_installed
)
pass 'database detection verifies the server executable still exists'

webroot_result=$(printf '%s\n' '    root /usr/share/nginx/html;' '# root /usr/share/nginx/html;' '    root /srv/custom;' | rewrite_nginx_webroot)
assert_contains "$webroot_result" '    root /var/www/html;' 'packaged Nginx webroot changes to /var/www/html'
assert_contains "$webroot_result" '# root /usr/share/nginx/html;' 'commented Nginx directives remain unchanged'
assert_contains "$webroot_result" '    root /srv/custom;' 'custom Nginx webroots remain unchanged'
assert_equal "$webroot_result" "$(printf '%s\n' "$webroot_result" | rewrite_nginx_webroot)" 'webroot migration is repeatable'

(
  declare -a connection_args mysql_prefix
  socket_client() { return 0; }
  mysql_admin_connection socket_client 127.0.0.1 3306 root >/dev/null
  assert_contains "${connection_args[*]}" '--protocol=SOCKET' 'local root uses socket authentication when available'
  [[ " ${connection_args[*]} " != *' --password '* ]] || fail 'socket login requested a password'
  assert_equal 0 "${#mysql_prefix[@]}" 'direct socket login needs no sudo'
  socket_client() { return 1; }
  sudo() { return 0; }
  mysql_admin_connection socket_client localhost 3306 root >/dev/null
  assert_equal 'sudo -n' "${mysql_prefix[*]}" 'sudo socket authentication is retained for subsequent queries'
  socket_client() { fail 'remote and nondefault-port connections must not probe the local socket'; }
  mysql_admin_connection socket_client db.example.com 3306 root >/dev/null
  assert_contains "${connection_args[*]}" '--protocol=TCP' 'remote administrators retain TCP authentication'
  assert_equal 0 "${#mysql_prefix[@]}" 'remote login clears the sudo prefix'
  mysql_admin_connection socket_client localhost 3307 root >/dev/null
  assert_contains "${connection_args[*]}" '--port=3307' 'nondefault ports are never redirected to the default socket'
)
pass 'MySQL user management supports local socket authentication without a root password'

(
  sql_capture=$(mktemp)
  trap 'rm -f -- "$sql_capture"' EXIT
  DRY_RUN=0
  command() { if [[ "$*" == '-v mysql' ]]; then printf 'fake_mysql\n'; else builtin command "$@"; fi; }
  fake_mysql() {
    if [[ "$*" == *'SHOW DATABASES'* ]]; then printf 'mysql\nsys\ninformation_schema\nperformance_schema\n'
    else cat > "$sql_capture"; fi
  }
  clear() { :; }
  show_brand() { :; }
  mysql_admin_connection() { connection_args=(); mysql_prefix=(); }
  read_hidden_paste_input() { HIDDEN_PASTE_VALUE='test-password-only'; }
  confirm() { return 1; }
  mysql_create_user database <<< $'\n\n\nportfolio\napp_user\n\n' >/dev/null
  [[ ! -s "$sql_capture" ]] || fail 'cancelled account plan created a database'
  confirm() { return 0; }
  mysql_create_user database <<< $'\n\n\nportfolio\napp_user\n\n' >/dev/null
  result=$(cat "$sql_capture")
  assert_contains "$result" 'CREATE DATABASE `portfolio`;' 'empty server can create an app database with its user'
  assert_contains "$result" 'GRANT ALL PRIVILEGES ON `portfolio`.*' 'new user remains scoped to the selected database'
)
pass 'empty database setup waits for confirmation before applying SQL'

(
  env_fixture=$(mktemp)
  trap 'rm -f -- "$env_fixture"' EXIT
  printf 'DATABASE_URL\0value with "quotes" and $symbols\0' > "$env_fixture"
  result=$(write_pm2_app_config "$env_fixture" example '/tmp/app folder' /usr/bin/npm start 1 512M 3000 production)
  assert_equal 'fork' "$(printf '%s' "$result" | jq -r '.apps[0].exec_mode')" 'npm wizard configs use fork mode'
  assert_equal 'value with "quotes" and $symbols' "$(printf '%s' "$result" | jq -r '.apps[0].env.DATABASE_URL')" 'environment values survive JSON encoding unchanged'
  assert_equal '3000' "$(printf '%s' "$result" | jq -r '.apps[0].env.PORT')" 'wizard config sets PORT'
  assert_equal 'start' "$(printf '%s' "$result" | jq -r '.apps[0].args[1]')" 'npm script is passed as a literal argument'
  result=$(write_pm2_app_config "$env_fixture" example /tmp/app /tmp/app/server.js '' 2 1G 4000 production)
  assert_equal 'cluster' "$(printf '%s' "$result" | jq -r '.apps[0].exec_mode')" 'direct Node supports multiple cluster instances'
  DRY_RUN=1
  pm2() { fail 'dry-run wizard must not call PM2'; }
  pm2_app_guide >/dev/null
)
pass 'PM2 wizard generates valid process settings and preserves hidden values'
(
  wizard_fixture=$(mktemp -d)
  trap 'rm -rf -- "$wizard_fixture"' EXIT
  mkdir -p "$wizard_fixture/project"
  printf '// example app\n' > "$wizard_fixture/project/server.js"
  XDG_STATE_HOME="$wizard_fixture/state"
  DRY_RUN=0
  pm2() {
    if [[ "$1" == jlist ]]; then printf '[]\n'
    elif [[ "$1" == start ]]; then printf '%s' "$2" > "$wizard_fixture/started"; fi
  }
  ensure_release_tools() { :; }
  show_pm2_apps() { :; }
  confirm() { return 1; }
  wizard_input=$(printf '%s\n' "$wizard_fixture/project" example 2 server.js 3000 production '' 1 512M)
  pm2_app_guide <<< "$wizard_input" >/dev/null
  [[ ! -e "$wizard_fixture/started" && ! -e "$XDG_STATE_HOME" ]] || fail 'cancelled wizard changed PM2 or saved configuration'
  confirm() { [[ "$1" == 'Save this configuration and start the app?' ]]; }
  pm2_app_guide <<< "$wizard_input" >/dev/null
  config="$XDG_STATE_HOME/neem/pm2/example.ecosystem.json"
  assert_equal "$config" "$(cat "$wizard_fixture/started")" 'confirmed wizard starts the reviewed configuration'
  [[ -f "$config" ]] || fail 'confirmed wizard did not save its config'
)
pass 'PM2 wizard starts only after confirmation and cancellation leaves no config'

(
  DRY_RUN=0
  dns_addresses() { [[ "$1" == example.com ]] && printf '2001:db8::1\n'; }
  curl() { printf '192.0.2.1\n'; }
  assert_true 'proxied or IPv6-only DNS does not falsely block HTTPS' dns_check example.com
  include_www=yes
  confirm() { return 0; }
  check_www_alias example.com >/dev/null 2>&1
  assert_equal no "$include_www" 'missing www alias can be omitted before requesting a certificate'
  install_certbot() { :; }
  package_step() { printf '%s\n' "$*"; }
  result=$(enable_ssl example.com yes <<< 'admin@example.com' 2>/dev/null)
  assert_contains "$result" '-d example.com' 'certificate request includes the resolving hostname'
  [[ "$result" != *'-d www.example.com'* ]] || fail 'certificate request retained a missing alias'
  package_step() { return 1; }
  if enable_ssl example.com no <<< 'admin@example.com' >/dev/null 2>&1; then fail 'Certbot failure reported success'; fi
)
pass 'HTTPS validates every hostname and handles certificate failure'

printf '\nBash suite passed (%d assertions).\n' "$TEST_COUNT"
