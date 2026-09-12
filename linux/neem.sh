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

PLATFORM_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd -- "$PLATFORM_DIR/.." && pwd)"
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


for module in core packages web health mysql menu; do
  # shellcheck source=/dev/null
  source "$PLATFORM_DIR/modules/$module.sh"
done

main() {
  local action="menu"
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;; --health) action="health" ;; --backup) action="backup" ;;
      --create-db-user) action="dbuser" ;; --update) action="update" ;;
      --setup-nginx) action="nginx" ;;
      --create-global-db-user) action="dbuserall" ;; --list-db-users) action="dbuserlist" ;;
      -h|--help) usage; exit 0 ;; *) die "Unknown option: $1" ;;
    esac
    shift
  done
  if [[ "$action" == "update" ]]; then update_neem; return; fi
  if [[ "$action" == "backup" ]]; then mysql_backup; return; fi
  if [[ "$action" == "dbuser" ]]; then mysql_create_user; return; fi
  if [[ "$action" == "dbuserall" ]]; then mysql_create_user all; return; fi
  if [[ "$action" == "dbuserlist" ]]; then mysql_list_users; return; fi
  detect_platform
  if [[ "$action" == "health" ]]; then health_check
  elif [[ "$action" == "nginx" ]]; then
    if ! command -v nginx >/dev/null 2>&1; then package_refresh; fi
    install_nginx
  else main_menu
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
