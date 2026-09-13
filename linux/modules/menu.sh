# Main command palette, action dispatch, and command-line usage.
MENU_IDS=(install remove complete app startup domain ssl tunnel backup dbuser health creator exit)
MENU_LABELS=("Install components" "Remove components" "Install complete stack" "Start an app with PM2" "Configure PM2 startup" "Connect a domain" "Enable HTTPS" "Configure Cloudflare Tunnel" "Back up a MySQL database" "Manage MySQL users" "Inspect stack health" "Creator and support" "Exit NEEM")
MENU_HINTS=("Choose one or several tools for this machine." "Select installed tools you no longer need." "Install Node.js, PM2, MySQL, Nginx and utilities." "Guided app setup: port, environment and process settings." "Restore your Node.js apps after a restart." "Route a hostname through Nginx to a PM2 app." "Request and renew a free TLS certificate." "Publish a local app without opening inbound ports." "Create a portable, validated SQL dump and get download commands." "Create database users or view every account on the server." "See what is installed and validate Nginx." "View Mohamed Aiman's links and ASCII portrait." "Return to your terminal.")
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
      app) pm2_app_guide; pause ;;
      startup) pm2_startup; pause ;;
      domain) configure_domain || true; pause ;;
      ssl) enable_ssl || true; pause ;;
      tunnel) cloudflare_tunnel_guide; pause ;;
      backup) mysql_backup || true; pause ;;
      dbuser) mysql_user_guide ;;
      health) health_check; pause ;;
      creator) show_creator ;;
      exit) printf 'Goodbye.\n'; return ;;
    esac
  done
}

usage() {
  cat <<EOF
NEEM Stack Setup v$VERSION

Usage: ./neem.sh [--dry-run] [--health] [--backup] [--create-db-user]
                 [--create-global-db-user] [--list-db-users] [--update] [--help]

Without options, launches the interactive terminal menu.
  --dry-run  Print privileged/package commands without running them
  --health   Show installed components and validate Nginx
  --setup-nginx  Install/configure Nginx; use /var/www/html for Linux default sites
  --backup   Create a portable MySQL database dump
  --create-db-user  Create a user for one MySQL database
  --create-global-db-user  Create a user with access to all databases
  --list-db-users  List MySQL users and their allowed hosts
  --update   Download and install the latest version from GitHub

Interactive picker:
  Up/Down  Move between components
  Space    Tick or untick a component
  A        Tick or untick all
  Enter    Continue with the selection
  1-9      Main-menu shortcuts
EOF
}
