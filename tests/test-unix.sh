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

printf '\nBash suite passed (%d assertions).\n' "$TEST_COUNT"
